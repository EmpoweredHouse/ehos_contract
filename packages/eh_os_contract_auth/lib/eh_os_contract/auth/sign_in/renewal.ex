defmodule EhOsContract.Auth.SignIn.Renewal do
  @moduledoc false

  # A credential for the session a browser's token names, renewed when it is stale (S4, S5 and
  # S10 in docs/adr/browser-session.md, `eh-os` D-64).
  #
  # 1. **The fast path.** A credential good for more than 30 seconds by `EhOsContract.Clock` is
  #    used, and nothing is written.
  # 2. **The lease.** One renewal per session at a time: the lease is taken by one statement, on
  #    the database's clock, for 15 seconds.
  # 3. **The row read again.** A predecessor may have renewed meanwhile; then its credential is
  #    used.
  # 4. **The call.** `Oidcc.Token.refresh/3`, with no transaction open, and a 10-second deadline
  #    shorter than the lease.
  # 5. **The write.** The result is written, and the lease released, in one transaction guarded
  #    by the lease.
  # 6. **A waiter** reads the row every 200 ms, takes the lease when it is free and the
  #    credential still stale, and gives up after 15 seconds.
  #
  # What each outcome leaves is S5's table, and `outcome/2` below follows it row by row. To tell
  # a response `oidcc` refused (its rotated refresh token is lost) from one that never came (the
  # old one is kept), the transport records the last response's status (`Http.last_status/0`).

  require Logger

  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.{Http, Sessions}

  @margin_seconds 30
  @lease_ms 15_000
  @poll_ms 200
  @wait_ms 15_000

  @typedoc "Why there is no credential."
  @type refusal :: :signed_out | :ehos_unavailable | :renewal_busy

  @doc false
  # The credential for `resource`, an application's address, in the session `browser_token`
  # names, renewed when it is stale. `opts` are for tests only: `wait_ms:` and `poll_ms:`.
  @spec credential(atom(), term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, refusal()}
  def credential(name, browser_token, resource, opts \\ []) do
    timing = %{
      deadline: System.monotonic_time(:millisecond) + Keyword.get(opts, :wait_ms, @wait_ms),
      poll_ms: Keyword.get(opts, :poll_ms, @poll_ms)
    }

    with {:ok, session} <- Sessions.fetch(name, browser_token) do
      case fresh(session, resource) do
        {:ok, token} -> {:ok, token}
        :stale -> lead_or_wait(name, browser_token, session, resource, timing)
      end
    end
  end

  defp fresh(session, resource) do
    with %{token: token, expires_at: %DateTime{} = expires_at} when is_binary(token) <-
           Map.get(session.credentials, resource),
         :gt <- DateTime.compare(expires_at, DateTime.add(now(), @margin_seconds)) do
      {:ok, token}
    else
      _stale -> :stale
    end
  end

  defp lead_or_wait(name, browser_token, session, resource, timing) do
    holder = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    if Sessions.take_lease(session, holder, @lease_ms),
      do: lead(name, browser_token, holder, resource),
      else: wait(name, browser_token, resource, timing)
  end

  # Step 3: the row as it is now, under the lease.
  defp lead(name, browser_token, holder, resource) do
    case Sessions.fetch(name, browser_token) do
      {:ok, session} ->
        case fresh(session, resource) do
          {:ok, token} ->
            :ok = Sessions.release(session, holder)
            {:ok, token}

          :stale ->
            renew(name, session, holder, resource)
        end

      {:error, :signed_out} ->
        {:error, :signed_out}
    end
  end

  defp wait(name, browser_token, resource, timing) do
    if System.monotonic_time(:millisecond) >= timing.deadline do
      {:error, :renewal_busy}
    else
      Process.sleep(timing.poll_ms)

      with {:ok, session} <- Sessions.fetch(name, browser_token) do
        case fresh(session, resource) do
          {:ok, token} -> {:ok, token}
          :stale -> lead_or_wait(name, browser_token, session, resource, timing)
        end
      end
    end
  end

  # Step 4. The renewal is for the client's own application; another's is `resource` (EB3b).
  defp renew(name, session, holder, resource) do
    config = SignIn.config(name)

    case SignIn.client_context(name) do
      {:ok, context} ->
        opts = %{
          expected_subject: session.subject,
          preferred_auth_methods: [:private_key_jwt],
          request_opts: config.request_opts
        }

        result = Oidcc.Token.refresh(session.refresh_token, context, opts)
        outcome(result, %{name: name, session: session, holder: holder, resource: resource})

      {:error, reason} ->
        Logger.warning("eh_os_contract_auth could not renew: #{describe(reason)}")
        kept(session, holder, resource)
    end
  end

  # S5, row by row.
  defp outcome({:ok, %Oidcc.Token{} = token}, at) do
    with %Oidcc.Token.Access{token: credential, expires: expires_in} when is_binary(credential) <-
           token.access,
         true <- is_integer(expires_in) and expires_in > 0,
         %Oidcc.Token.Refresh{token: refresh_token} when is_binary(refresh_token) <-
           token.refresh,
         %Oidcc.Token.Id{token: id_token} when is_binary(id_token) <- token.id do
      renewal = %{
        refresh_token: refresh_token,
        id_token: id_token,
        resource: at.resource,
        token: credential,
        expires_at: DateTime.add(now(), expires_in)
      }

      case Sessions.renewed(at.name, at.session, at.holder, renewal) do
        :ok ->
          {:ok, credential}

        # The holder overran its lease, and another may have presented the same refresh token:
        # the new one cannot be stored safely.
        :lost ->
          ended(at.session, :lease_lost)
      end
    else
      # A 2xx response without what a renewal needs: EHOS rotated, and the successor is lost.
      _incomplete -> ended(at.session, :incomplete_token_response)
    end
  end

  defp outcome({:error, {:http_error, status, %{"error" => "invalid_grant"}}}, at)
       when status in [400, 401],
       do: ended(at.session, :invalid_grant)

  defp outcome({:error, reason}, at) do
    case Http.last_status() do
      # A 2xx response `oidcc` refused (`sub_invalid`, an ID token that does not validate): EHOS
      # rotated, and the successor is in the refused response.
      status when status in 200..299 ->
        ended(at.session, reason)

      # A timeout, a reset, a 5xx or another error response: whether EHOS rotated is unknown, and
      # an error response consumes nothing, so the refresh token is kept.
      _no_success ->
        Logger.warning("eh_os_contract_auth could not renew a credential: #{describe(reason)}")
        kept(at.session, at.holder, at.resource)
    end
  end

  defp ended(session, reason) do
    Logger.info("eh_os_contract_auth ended a session at renewal: #{describe(reason)}")
    :ok = Sessions.end_session(session)
    {:error, :signed_out}
  end

  # The held credential while it is unexpired, else none.
  defp kept(session, holder, resource) do
    :ok = Sessions.release(session, holder)

    case Map.get(session.credentials, resource) do
      %{token: token, expires_at: %DateTime{} = expires_at} when is_binary(token) ->
        if DateTime.compare(expires_at, now()) == :gt,
          do: {:ok, token},
          else: {:error, :ehos_unavailable}

      _none ->
        {:error, :ehos_unavailable}
    end
  end

  defp now, do: EhOsContract.Clock.now()

  # A reason's name, never its value: some of `oidcc`'s carry the token they refused.
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp describe({:http_error, status, _body}), do: "HTTP #{status}"

  defp describe(reason) when is_tuple(reason) and is_atom(elem(reason, 0)),
    do: Atom.to_string(elem(reason, 0))

  defp describe(_reason), do: "unexpected"
end
