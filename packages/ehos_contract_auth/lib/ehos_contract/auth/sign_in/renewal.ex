defmodule EhosContract.Auth.SignIn.Renewal do
  @moduledoc false

  # A credential for the session a browser's token names, renewed when it is stale (S4, S5 and
  # S10 in docs/adr/browser-session.md).
  #
  # 1. **The fast path.** A credential good for more than 30 seconds by `EhosContract.Clock` is
  #    used, and nothing is written.
  # 2. **The lease.** One renewal per session at a time: the lease is taken by one statement, on
  #    the database's clock, for 30 seconds, longer than what a holder can spend before writing. A lease taken over from a holder that never released
  #    it ends the session instead: that holder may have presented the refresh token, and
  #    presenting it again would revoke the sign-in everywhere (S5).
  # 3. **The row read again.** A predecessor may have renewed meanwhile; then its credential is
  #    used.
  # 4. **The call.** `Oidcc.Token.refresh/3`, with no transaction open, a 10-second deadline
  #    shorter than the lease, and the sign-in child's keys refetched once for a `kid` it does not
  #    hold.
  # 5. **The write.** What EHOS returned is checked as the callback checks a sign-in: the
  #    credential by `verify/2` (for the client's own application) and of the session's person,
  #    the ID token of its `sub`, `sid` and `auth_time`. It is written, and the lease released, in
  #    one transaction guarded by the lease.
  # 6. **While another renews.** A credential still unexpired is used as it is. An expired one
  #    waits: the row is read every 200 ms, the lease taken when it is free, for at most 15
  #    seconds.
  #
  # When EHOS does not answer, the lease is kept for 5 seconds as a pause, so the session's other
  # requests use the held credential, or answer `:ehos_unavailable`, instead of each calling EHOS
  # again. What each outcome leaves is S5's table, and `outcome/2` follows it row by row; the
  # transport's last status tells a response `oidcc` refused from one that never came.

  require Logger

  alias EhosContract.Auth.{Development, SignIn}
  alias EhosContract.Auth.SignIn.{Http, Sessions}

  @margin_seconds 30
  # What a holder may spend between taking the lease and writing: the call (10 s), keys refetched
  # once for an unknown `kid` (at most 5 s waited for) and `verify/2`'s own refetch (10 s).
  @lease_ms 30_000
  @jwks_wait_ms 5_000
  @poll_ms 200
  @wait_ms 15_000
  @pause_ms 5_000
  # S5: a refusal for one application is remembered for a credential's lifetime, so a person with
  # no role there does not leave a refused request, and an audit row at EHOS, on every page.
  @refused_ms 10 * 60 * 1000
  @paused "paused after a failed renewal"
  @verify_opts [:keys, :audience, :issuer]

  @doc false
  # The credential for `resource`, an application's address, in the session `browser_token`
  # names, renewed when it is stale. `opts`: `session:`, the session already fetched for this
  # request; `verify/2`'s `:keys`, `:audience` and `:issuer`; and, for tests only, `wait_ms:` and
  # `poll_ms:`.
  @spec credential(atom(), term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, EhosContract.Auth.Session.credential_refusal()}
  def credential(name, browser_token, resource, opts \\ []) do
    at = %{
      name: name,
      browser_token: browser_token,
      resource: resource,
      verify: opts |> Keyword.take(@verify_opts) |> Enum.reject(&is_nil(elem(&1, 1))),
      deadline: System.monotonic_time(:millisecond) + Keyword.get(opts, :wait_ms, @wait_ms),
      poll_ms: Keyword.get(opts, :poll_ms, @poll_ms)
    }

    session =
      case Keyword.fetch(opts, :session) do
        {:ok, session} -> {:ok, session}
        :error -> Sessions.fetch(name, browser_token)
      end

    with {:ok, session} <- session do
      case freshness(session, resource) do
        {:fresh, token} -> {:ok, token}
        :refused -> {:error, :refused}
        _stale -> lead_or_wait(session, at)
      end
    end
  end

  # `{:fresh, token}` past the margin, `{:usable, token}` inside it but unexpired, `:expired`, or
  # `:refused` while EHOS's refusal for that application is remembered.
  defp freshness(session, resource) do
    case Map.get(session.credentials, resource) do
      %{refused_until: %DateTime{} = until} = credential ->
        if DateTime.compare(until, now()) == :gt, do: :refused, else: freshness_of(credential)

      credential ->
        freshness_of(credential)
    end
  end

  defp freshness_of(credential) do
    case credential do
      %{token: token, expires_at: %DateTime{} = expires_at} when is_binary(token) ->
        cond do
          DateTime.compare(expires_at, DateTime.add(now(), @margin_seconds)) == :gt ->
            {:fresh, token}

          DateTime.compare(expires_at, now()) == :gt ->
            {:usable, token}

          true ->
            :expired
        end

      _none ->
        :expired
    end
  end

  defp lead_or_wait(session, at) do
    holder = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    case Sessions.take_lease(session, holder, @lease_ms) do
      {:taken, previous} when previous in [nil, @paused] -> lead(holder, at)
      {:taken, _overran} -> ended(session, :lease_overrun)
      :busy -> busy(at)
    end
  end

  # Read again: the row may be gone (the holder ended the session), or held now by another than
  # when it was read.
  defp busy(at) do
    with {:ok, session} <- Sessions.fetch(at.name, at.browser_token) do
      case freshness(session, at.resource) do
        {:fresh, token} -> {:ok, token}
        {:usable, token} -> {:ok, token}
        :refused -> {:error, :refused}
        :expired when session.lease_holder == @paused -> {:error, :ehos_unavailable}
        :expired -> wait(at)
      end
    end
  end

  # Step 3: the row as it is now, under the lease.
  defp lead(holder, at) do
    with {:ok, session} <- Sessions.fetch(at.name, at.browser_token) do
      case freshness(session, at.resource) do
        {:fresh, token} ->
          :ok = Sessions.release(session, holder)
          {:ok, token}

        :refused ->
          :ok = Sessions.release(session, holder)
          {:error, :refused}

        _stale ->
          renew(session, holder, at)
      end
    end
  end

  defp wait(at) do
    if System.monotonic_time(:millisecond) >= at.deadline do
      {:error, :renewal_busy}
    else
      Process.sleep(at.poll_ms)

      with {:ok, session} <- Sessions.fetch(at.name, at.browser_token) do
        case freshness(session, at.resource) do
          {:fresh, token} -> {:ok, token}
          :refused -> {:error, :refused}
          _stale -> lead_or_wait(session, at)
        end
      end
    end
  end

  # Step 4, where the sign-in child is the development mode's process, which signs the new
  # credential itself (`EhosContract.Auth.Development`): only one its own key signed, and of the
  # session's person. One it cannot renew, from before a restart for one, ends the session.
  defp renew(session, holder, %{name: name} = at) do
    if Development.started?(name),
      do: development(session, holder, at),
      else: ehos(session, holder, at)
  end

  defp development(session, holder, at) do
    held = session.credentials |> Map.get(at.resource, %{}) |> Map.get(:token)

    with {:ok, token, expires_at} <- Development.renew(at.name, session.subject, held),
         written = %{
           refresh_token: session.refresh_token,
           id_token: session.id_token,
           resource: at.resource,
           token: token,
           expires_at: expires_at
         },
         :ok <- Sessions.renewed(at.name, session, holder, written) do
      {:ok, token}
    else
      :lost -> ended(session, :lease_lost)
      {:error, reason} -> ended(session, reason)
    end
  end

  # Step 4. For the client's own application the request names no `resource`; for another, its
  # address, as EHOS takes it.
  defp ehos(session, holder, at) do
    config = SignIn.config(at.name)

    case SignIn.client_context(at.name) do
      {:ok, context} ->
        opts =
          %{
            expected_subject: session.subject,
            preferred_auth_methods: [:private_key_jwt],
            request_opts: config.request_opts,
            refresh_jwks: refresh_jwks(at.name)
          }
          |> then(fn opts ->
            if at.resource == config.address,
              do: opts,
              else: Map.put(opts, :body_extension, [{"resource", at.resource}])
          end)

        started = now()
        :ok = Http.forget_status()

        result =
          try do
            Oidcc.Token.refresh(session.refresh_token, context, opts)
          rescue
            # `oidcc` raises on some 2xx bodies it cannot read (a JWT where it wants JSON, JSON
            # that is not an object); the exception is never printed, as it may hold the body.
            exception -> {:error, {:raised, exception.__struct__}}
          catch
            kind, _reason -> {:error, {:raised, kind}}
          end

        outcome(result, %{
          at: at,
          config: config,
          session: session,
          holder: holder,
          started: started
        })

      {:error, reason} ->
        Logger.warning("ehos_contract_auth could not renew: #{describe(reason)}")
        kept(session, holder, at.resource)
    end
  end

  # The child refetches EHOS's keys when an ID token names one it does not hold, as after a
  # rotation at EHOS; once per renewal, since `oidcc` asks once.
  defp refresh_jwks(name) do
    fn _jwks, _kid ->
      with :ok <- SignIn.refresh(name, @jwks_wait_ms),
           {:ok, context} <- SignIn.client_context(name) do
        # `oidcc` calls this from Erlang, and takes the key set as JOSE's record.
        {:ok, JOSE.JWK.to_record(context.jwks)}
      end
    end
  end

  # S5, row by row.
  defp outcome({:ok, %Oidcc.Token{} = token}, renewal) do
    case renewed(token, renewal) do
      {:ok, written} ->
        case Sessions.renewed(renewal.at.name, renewal.session, renewal.holder, written) do
          :ok ->
            {:ok, written.token}

          # The holder overran its lease, and another may have presented the same refresh token:
          # the new one cannot be stored safely.
          :lost ->
            ended(renewal.session, :lease_lost)
        end

      # A 2xx response without what a renewal needs: EHOS rotated, and the successor is lost.
      {:error, reason} ->
        ended(renewal.session, reason)
    end
  end

  defp outcome({:error, {:http_error, status, %{"error" => "invalid_grant"}}}, renewal)
       when status in [400, 401],
       do: ended(renewal.session, :invalid_grant)

  # EHOS refuses a credential for that application (`invalid_target`). EHOS consumed nothing, so
  # the refresh token stays, and the session lives on for every other application. A lease lost
  # meanwhile is a session ended. For the client's own application, which names no `resource`,
  # EHOS never answers it; one that did is any other error response, so the own application is
  # never remembered as refused.
  defp outcome(
         {:error, {:http_error, 400, %{"error" => "invalid_target"}}},
         %{at: %{resource: resource}, config: %{address: address}} = renewal
       )
       when resource != address do
    until = DateTime.add(now(), @refused_ms, :millisecond)

    case Sessions.refused(renewal.session, renewal.holder, renewal.at.resource, until) do
      :ok -> {:error, :refused}
      :lost -> {:error, :signed_out}
    end
  end

  # A shape outside `oidcc`'s spec is read as any other error.
  defp outcome(result, renewal) when not is_tuple(result) or elem(result, 0) not in [:ok, :error],
    do: outcome({:error, :unexpected}, renewal)

  defp outcome({:error, reason}, renewal) do
    case Http.last_status() do
      # A 2xx response `oidcc` refused (`sub_invalid`, an ID token that does not validate, a body
      # it raised on or past the size limit): EHOS rotated, and the successor is lost.
      status when status in 200..299 ->
        ended(renewal.session, reason)

      # A timeout, a reset, a 5xx or another error response: whether EHOS rotated is unknown, and
      # an error response consumes nothing, so the refresh token is kept.
      _no_success ->
        Logger.warning("ehos_contract_auth could not renew a credential: #{describe(reason)}")
        kept(renewal.session, renewal.holder, renewal.at.resource)
    end
  end

  # Step 5's checks. Nothing is matched in a function head, so a refusal prints no token.
  defp renewed(token, renewal) do
    session = renewal.session

    with %Oidcc.Token.Access{token: credential, expires: expires_in} when is_binary(credential) <-
           token.access,
         true <- is_integer(expires_in) and expires_in > 0,
         %Oidcc.Token.Refresh{token: refresh_token} when is_binary(refresh_token) <-
           token.refresh,
         %Oidcc.Token.Id{token: id_token, claims: claims} when is_binary(id_token) <- token.id,
         true <-
           claims["sid"] == session.sid and
             claims["auth_time"] == DateTime.to_unix(session.auth_time),
         expires_at = expires_at(credential, renewal.started, expires_in),
         true <- beyond_margin?(expires_at),
         :ok <- verified(credential, renewal) do
      {:ok,
       %{
         refresh_token: refresh_token,
         id_token: id_token,
         resource: renewal.at.resource,
         token: credential,
         expires_at: expires_at
       }}
    else
      {:error, reason} -> {:error, reason}
      _incomplete -> {:error, :incomplete_token_response}
    end
  end

  # The client's own credential is checked as every request will check it, and must be the
  # session's person. Another application's is that application's to verify (S8).
  defp verified(credential, renewal) do
    if renewal.at.resource == renewal.config.address do
      case EhosContract.Auth.verify(credential, renewal.at.verify) do
        {:ok, %{subject: subject}} when subject == renewal.session.subject -> :ok
        {:ok, _other} -> {:error, :subject_mismatch}
        # This application does not hold EHOS's keys yet: nothing is wrong with the credential,
        # and the rotated refresh token is kept; each request's `verify/2` decides.
        {:error, reason} when reason in [:unknown_key, :no_keys] -> :ok
        {:error, reason} -> {:error, {:credential_refused, reason}}
      end
    else
      :ok
    end
  end

  @doc false
  # Whether a credential expiring at `expires_at` is fresh past the margin: one that is not would
  # be renewed again by every request, each rotating the refresh token.
  @spec beyond_margin?(DateTime.t()) :: boolean()
  def beyond_margin?(expires_at),
    do: DateTime.compare(expires_at, DateTime.add(now(), @margin_seconds)) == :gt

  @doc false
  # From `started`, the time the call began, and never past the credential's own `exp`, so a slow answer or a
  # clock that runs behind EHOS's does not keep a credential past its life. The callback uses it
  # too.
  @spec expires_at(String.t(), DateTime.t(), pos_integer()) :: DateTime.t()
  def expires_at(credential, started, expires_in) do
    by_expires_in = DateTime.add(started, expires_in)

    case JOSE.JWT.peek_payload(credential) do
      %JOSE.JWT{fields: %{"exp" => exp}} when is_integer(exp) ->
        Enum.min([by_expires_in, DateTime.from_unix!(exp)], DateTime)

      _other ->
        by_expires_in
    end
  rescue
    _not_a_jwt -> DateTime.add(started, expires_in)
  end

  defp ended(session, reason) do
    Logger.info("ehos_contract_auth ended a session at renewal: #{describe(reason)}")
    :ok = Sessions.end_session(session)
    {:error, :signed_out}
  end

  # The held credential while it is unexpired, else none; the lease kept a moment as a pause.
  defp kept(session, holder, resource) do
    :ok = Sessions.hold_off(session, holder, @paused, @pause_ms)

    case freshness(session, resource) do
      :expired -> {:error, :ehos_unavailable}
      :refused -> {:error, :refused}
      {_fresh_or_usable, token} -> {:ok, token}
    end
  end

  defp now, do: EhosContract.Clock.now()

  # A reason's name, never its value: some of `oidcc`'s carry the token they refused.
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe({:http_error, status, _body}), do: "HTTP #{status}"

  defp describe({:credential_refused, reason}) when is_atom(reason),
    do: "credential_refused (#{reason})"

  defp describe({:raised, module}) when is_atom(module), do: "raised #{inspect(module)}"

  defp describe(reason) when is_tuple(reason) and is_atom(elem(reason, 0)),
    do: Atom.to_string(elem(reason, 0))

  defp describe(_reason), do: "unexpected"
end
