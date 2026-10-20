defmodule EhOsContract.Auth.Grants do
  # `eh-os` D-112: a person grants, through their application, a role a rule of their own role
  # names, and EHOS checks it on their credential. The exchange and the routes are `eh-os`
  # `docs/grants-api.md`; the grant is made in the person's request and never kept for later
  # (EmpoweredHouse/eh-os#719). Issue EmpoweredHouse/eh-os#773.
  @moduledoc """
  A signed-in person grants or revokes, from the application's own page, a role their
  role here may give: an accountant invites a client's representative with the client
  role. The rule is `may_grant:` on the person's actor in the contract, carried to EHOS
  by the manifest; EHOS checks it, invites, mails and records.

      # a controller, after the application's own command is recorded
      case EhOsContract.Auth.Grants.grant(conn, email: email, name: name, role: "taxvision.client") do
        {:ok, %Grant{person_id: id, delivery: :mailed}} -> # keep the id; "invited"
        {:error, :beyond_rule} -> # "your role may not give that role"
        {:error, :unavailable} -> # "they were not invited; try again"
        ...
      end

      # later, with the id the grant answered
      {:ok, _binding} = EhOsContract.Auth.Grants.revoke(conn, id, "taxvision.client")

  Both take the person's request: a `Plug.Conn` with its session fetched, or the
  session map a LiveView's `mount/3` is given, as `EhOsContract.Auth.Session` does;
  `sign_in:`, the name of the `EhOsContract.Auth.SignIn` child; and `verify/2`'s `:keys`,
  `:audience` and `:issuer`, which a renewed credential is checked with, as
  `EhOsContract.Auth.Session.actor/2` takes them. Nothing else is configured: the
  sign-in's client is the one EHOS expects.

  **What a call does.** It takes the person's credential for this application from
  their session, renewed first when it is about to expire, and exchanges it at EHOS's
  token endpoint (RFC 8693), authenticated as the sign-in's client with
  `private_key_jwt`, for one EHOS takes on its grant routes alone, for a minute at most.
  It sends the grant or the revocation with that one, and answers what EHOS answered.
  Each call exchanges anew: the exchanged credential is dropped when the call returns,
  and neither credential is kept, logged or returned.

  **It retries nothing.** A grant is the person's decision, made while they wait: when
  it fails, the page says so and they ask again. Asking again is safe: a role bound
  already is answered `bound: :before`, and a person invited and not joined is mailed a
  new link, which ends the earlier ones.

  **What a grant answers** is an `EhOsContract.Auth.Grants.Grant`: the person's id,
  whether they were invited or have joined, whether the role was bound now or before,
  and whether a link was mailed. A revocation answers the binding it removed.

  **What a call answers when EHOS says no**, each an `{:error, reason}` a page can say in
  words:

    * `:beyond_rule`: none of the person's roles here may grant that role;
    * `:not_permitted`: EHOS refused to exchange the person's credential, and says no
      more, by design: no role of theirs here carries a rule, they are disabled, or the
      credential is not this client's. Also a person disabled since the exchange, whichever
      of EHOS's checks finds it;
    * `:unknown_role`: no role of this application in this environment;
    * `:mail_required`: the installation sends no mail, so someone who manages people
      invites them in the console instead;
    * `:person_disabled`: the person the email names is disabled at EHOS;
    * `:invalid_email`, `:invalid_name`: EHOS will not keep the address or the name;
    * `:already_bound`: the role was bound to them meanwhile by another decision; ask
      again;
    * `:too_many_invitations`: this application registered its 100 new people of the day;
    * `:not_mailed`: the role is granted but the mail failed; granting it again sends a
      new link;
    * `:not_found`: `revoke/4` of a binding that is not there, or an environment removed;
    * `:rate_limited`: EHOS's limit on its token endpoint or its grant routes. Each call
      exchanges once, and EHOS takes at most 60 token requests a minute from the
      application's client, `EhOsContract.Auth.People`'s included: offer the grant only to
      people whose role may give one;
    * `:signed_out`, `:renewal_busy`: the session's, as `EhOsContract.Auth.Session.actor/2`
      answers them. `:renewal_busy` also when the person's credential has too few seconds
      left for EHOS to exchange it while another request renews it; ask again;
    * `:unavailable`: EHOS cannot be reached, fails, or answers what it never answers,
      which is logged.

  A call never raises or exits for what EHOS does. Each request goes over https,
  follows no redirect, reads at most 64 KiB and ends after ten seconds, as sign-in's
  do, so a call answers within about twenty seconds when EHOS hangs, and a renewal's
  wait on top when the person's credential is stale.

  Raises `ArgumentError` for an argument it does not take: a defect of the host's code,
  not something the person can change.
  """

  require Logger

  alias EhOsContract.Auth.Grants.Grant
  alias EhOsContract.Auth.{Session, SignIn}
  alias EhOsContract.Auth.SignIn.{ClientKey, Http, Renewal}

  @exchange "urn:ietf:params:oauth:grant-type:token-exchange"
  @access_token "urn:ietf:params:oauth:token-type:access_token"
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @grants "/api/v1/role-bindings/grants"
  @verify_opts [:keys, :audience, :issuer]
  @deadline 10_000
  # EHOS exchanges a credential with at least 5 seconds left (`Ehos.SignIn.PersonExchange`); one
  # with less, which Renewal hands out while another request renews, is not sent to be refused as
  # though the person may not grant.
  @least_remaining_seconds 10
  # EHOS's ids are UUIDs: anything else is no one's, and is not sent.
  @id ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  # A role is `<application>.<name>`, its name as EHOS's manifest takes it: anything else is no
  # role's, and is not put in a path, where `.` or `..` would name another route.
  @role ~r/\A[^\/.\s]+\.[a-z][a-z0-9_]*\z/
  # The refusals of the grant routes `docs/grants-api.md` names, each answered as itself.
  @refusals Map.new(
              ~w(beyond_rule unknown_role mail_required person_disabled invalid_email invalid_name
                 already_bound too_many_invitations not_mailed not_found)a,
              &{Atom.to_string(&1), &1}
            )

  @typedoc "Why a grant or a revocation was not made."
  @type reason ::
          :beyond_rule
          | :not_permitted
          | :unknown_role
          | :mail_required
          | :person_disabled
          | :invalid_email
          | :invalid_name
          | :already_bound
          | :too_many_invitations
          | :not_mailed
          | :not_found
          | :rate_limited
          | :signed_out
          | :renewal_busy
          | :unavailable

  @typedoc """
  What `grant/3` takes: `email:` and `role:`, `<application>.<name>`, each a non-empty
  string; and `name:`, optional, given only to a person this grant registers.
  """
  @type grant_option :: {:email, String.t()} | {:role, String.t()} | {:name, String.t() | nil}

  @typedoc "Whose sign-in, and what a renewed credential is verified with."
  @type option ::
          {:sign_in, atom()}
          | {:keys, GenServer.server()}
          | {:audience, String.t()}
          | {:issuer, String.t()}

  @doc """
  Grants `role` to the person `email:` names, for the person signed in in `session`,
  under their role's rule. See the module's doc for what it answers.
  """
  @spec grant(Plug.Conn.t() | map(), [grant_option()], [option()]) ::
          {:ok, Grant.t()} | {:error, reason()}
  def grant(session, grant, opts \\ []) do
    body = grant!(grant)

    with {:ok, answer} <- call(session, opts, :post, @grants, body) do
      case Grant.from_map(answer) do
        {:ok, grant} -> {:ok, grant}
        :error -> unexpected("a grant it never writes")
      end
    end
  end

  @doc """
  Takes `role` back from the person `person_id` names, the id a grant answered, for the
  person signed in in `session`, under their role's rule, whoever bound it. Answers the
  binding's id and role; `{:error, :not_found}` without one, an id that is no one's
  or a role that is not `<application>.<name>` included, which are not sent.
  """
  @spec revoke(Plug.Conn.t() | map(), String.t(), String.t(), [option()]) ::
          {:ok, %{role_binding_id: String.t(), role: String.t()}} | {:error, reason()}
  def revoke(session, person_id, role, opts \\ [])

  def revoke(session, person_id, role, opts)
      when is_binary(person_id) and is_binary(role) and role != "" do
    person_id = String.downcase(person_id)

    with true <- (person_id =~ @id and role =~ @role) || {:error, :not_found},
         path = Enum.join([@grants, person_id, URI.encode(role, &URI.char_unreserved?/1)], "/"),
         {:ok, answer} <- call(session, opts, :delete, path, nil) do
      case answer do
        %{"role_binding" => %{"id" => id, "role" => role}}
        when is_binary(id) and is_binary(role) ->
          {:ok, %{role_binding_id: id, role: role}}

        _other ->
          unexpected("a revocation it never writes")
      end
    end
  end

  def revoke(_session, _person_id, _role, _opts),
    do: raise(ArgumentError, "revoke/4 takes the person's id and the role, each a string")

  defp grant!(grant) do
    unless Keyword.keyword?(grant) and Keyword.keys(grant) -- [:email, :role, :name] == [] do
      bad!()
    end

    email = grant[:email]
    role = grant[:role]
    name = grant[:name]

    unless text?(email) and email != "" and text?(role) and role != "" and
             (is_nil(name) or text?(name)) do
      bad!()
    end

    if is_nil(name),
      do: %{"email" => email, "role" => role},
      else: %{"email" => email, "role" => role, "name" => name}
  end

  # Valid UTF-8, so the body is encoded before EHOS is asked, and a value no JSON can carry fails
  # here, without the value in what is raised.
  defp text?(value), do: is_binary(value) and String.valid?(value)

  defp bad!,
    do:
      raise(
        ArgumentError,
        "grant/3 takes email: and role:, each a non-empty UTF-8 string, and name:, a UTF-8 " <>
          "string or nil"
      )

  ## The calls

  # The person's credential, exchanged, then the call, each once.
  defp call(session, opts, method, path, body) do
    opts = Keyword.validate!(opts, [sign_in: SignIn] ++ @verify_opts)
    name = opts[:sign_in]
    config = SignIn.config(name)
    request_opts = request_opts(config)
    verify_opts = opts |> Keyword.take(@verify_opts) |> Enum.reject(&is_nil(elem(&1, 1)))

    with {:ok, subject_token} <- subject_token(session, name, config, verify_opts),
         {:ok, credential} <- exchange(config, request_opts, subject_token) do
      send_call(config, request_opts, credential, method, path, body)
    end
  end

  # The credential the client's own sign-in got for the person: the one EHOS exchanges (its
  # check 2). Renewal verifies a renewed one as this application's; EHOS verifies it again.
  defp subject_token(session, name, config, verify_opts) do
    browser_token =
      case session do
        %Plug.Conn{} = conn -> Plug.Conn.get_session(conn, Session.session_key())
        session when is_map(session) -> Map.get(session, Session.session_key())
      end

    case Renewal.credential(name, browser_token, config.address, verify_opts) do
      {:ok, token} -> lasting(token)
      {:error, :ehos_unavailable} -> {:error, :unavailable}
      # Renewal refuses only another application's address; this one is the client's own.
      {:error, :refused} -> {:error, :not_permitted}
      {:error, reason} -> {:error, reason}
    end
  end

  # Measured on `EhOsContract.Clock`, as Renewal judges a credential fresh.
  defp lasting(token) do
    exp =
      try do
        JOSE.JWT.peek_payload(token).fields["exp"]
      rescue
        _not_a_jwt -> nil
      end

    if is_integer(exp) and
         exp - DateTime.to_unix(EhOsContract.Clock.now()) >= @least_remaining_seconds,
       do: {:ok, token},
       else: {:error, :renewal_busy}
  end

  # What sign-in's transport is configured with: the plug of a test, or EHOS's authority.
  defp request_opts(config) do
    {Http, http} = config.request_opts.http_adapter
    http
  end

  # RFC 8693, as `docs/grants-api.md` "The exchange" takes it: no scope, resource or actor token.
  defp exchange(config, request_opts, subject_token) do
    token_endpoint = config.issuer <> "/oauth/token"

    form =
      URI.encode_query(%{
        "grant_type" => @exchange,
        "subject_token" => subject_token,
        "subject_token_type" => @access_token,
        "audience" => "ehos",
        "client_assertion_type" => @assertion_type,
        "client_assertion" =>
          ClientKey.assertion(config.client_key, config.client_id, token_endpoint)
      })

    request =
      {token_endpoint, [{"accept", "application/json"}], "application/x-www-form-urlencoded",
       form}

    case Http.request(:post, request, [timeout: @deadline], [], request_opts) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token}} when is_binary(token) and token != "" ->
            {:ok, token}

          _other ->
            unexpected("an exchange with no credential")
        end

      {:ok, {{_version, 429, _reason}, _headers, _body}} ->
        {:error, :rate_limited}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        exchange_refusal(status, body)

      {:error, reason} ->
        Logger.warning("EHOS's token endpoint could not be reached: #{describe(reason)}")
        {:error, :unavailable}
    end
  end

  # `invalid_grant` is every refusal of the person or their token, and says nothing more. Any
  # other is the host's configuration or an EHOS too old to exchange, which no person can mend.
  defp exchange_refusal(status, body) do
    case error(body) do
      "invalid_grant" ->
        {:error, :not_permitted}

      error ->
        Logger.warning(
          "EHOS refused to exchange a person's credential: #{status} #{inspect(error)}"
        )

        {:error, :unavailable}
    end
  end

  defp send_call(config, request_opts, credential, method, path, body) do
    headers = [{"authorization", "Bearer " <> credential}, {"accept", "application/json"}]

    request =
      if body,
        do: {config.issuer <> path, headers, "application/json", Jason.encode!(body)},
        else: {config.issuer <> path, headers}

    case Http.request(method, request, [timeout: @deadline], [], request_opts) do
      {:ok, {{_version, status, _reason}, _headers, body}} when status in [200, 201] ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) -> {:ok, json}
          _other -> unexpected("an answer that is not a JSON object")
        end

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        refusal(status, error(body))

      {:error, reason} ->
        Logger.warning("EHOS's grant routes could not be reached: #{describe(reason)}")
        {:error, :unavailable}
    end
  end

  defp refusal(_status, error) when is_map_key(@refusals, error),
    do: {:error, Map.fetch!(@refusals, error)}

  # A person disabled since the exchange: at the route's door (`disabled`), or under the lock the
  # grant is decided under (`forbidden`). One cause, one answer.
  defp refusal(401, "disabled"), do: {:error, :not_permitted}
  defp refusal(403, "forbidden"), do: {:error, :not_permitted}
  defp refusal(429, _error), do: {:error, :rate_limited}
  defp refusal(status, error), do: unexpected("status #{status} #{inspect(error)}")

  defp error(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error}} when is_binary(error) -> error
      _other -> nil
    end
  end

  # What failed, never the request: a transport's own reason, or an exception's module alone, since
  # an exception raised inside the request may carry its headers, the bearer token among them.
  defp describe(%{__exception__: true, reason: reason}) when is_atom(reason), do: inspect(reason)
  defp describe(%{__exception__: true, __struct__: module}), do: inspect(module)
  defp describe(reason) when is_atom(reason), do: inspect(reason)
  defp describe(_reason), do: "an error in the request"

  defp unexpected(what) do
    Logger.warning("EHOS's grant routes answered #{what}")
    {:error, :unavailable}
  end
end
