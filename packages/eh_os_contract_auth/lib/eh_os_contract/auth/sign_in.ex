defmodule EhOsContract.Auth.SignIn do
  # Sign-in through EHOS is `eh-os` D-64; what this package decides beside it is
  # docs/adr/browser-session.md, S1-S11. In the moduledoc: the addresses' form and the
  # post-logout address are D-68, the redirect URI D-64, `applications` naming only the others
  # D-69, the issuer's and the document's endpoints' form #89, starting while EHOS is down FM-19,
  # the limits on every call to EHOS S6. In the typedoc of `t`: the cipher key S3, the random
  # client secret S6.
  @moduledoc """
  Signing a person in to the application's pages through EHOS, with OpenID Connect:
  the application's client, and the process that keeps EHOS's discovery document and
  keys.

      # config/runtime.exs
      config :eh_os_contract_auth,
        issuer: System.fetch_env!("EHOS_ISSUER"),
        audience: System.fetch_env!("EHOS_AUDIENCE"),
        sign_in: [
          client_id: System.fetch_env!("EHOS_CLIENT_ID"),
          client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
          address: "https://" <> System.fetch_env!("PHX_HOST"),
          secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
          applications: Jason.decode!(System.get_env("EHOS_SIGN_IN_APPLICATIONS", "{}"))
        ]

      # the supervision tree, after EhOsContract.Auth
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.SignIn]

  The package reads no environment variable itself; the host maps them, as it maps
  `EHOS_ISSUER`. `EHOS_CA_FILE` goes to this child as it goes to `EhOsContract.Auth`:
  `{EhOsContract.Auth.SignIn, cacertfile: ca}`.

  **What is checked at boot.** `child_spec/1` raises, so a host's boot fails while its
  children are listed, when:

    * `config :eh_os_contract_auth, :sign_in` is missing or not a keyword list, or has a
      key it does not take;
    * the top-level `:issuer` is not `https://<host>[:port]` alone, as every parser
      reads it: a lowercase host, and no user, path, query or fragment;
    * `client_id` is not a non-empty string;
    * `address`, or an address in `applications`, is not exactly `https://<host>`, in
      lower case: no port, no path, no trailing slash, no query;
    * an address in `applications` is `address` itself: they are the other
      applications;
    * `secret_key_base` is shorter than 64 bytes, Phoenix's own minimum;
    * the file at `client_key_file` is not one private Ed25519 JWK with exactly
      `kty`, `crv`, `x`, `d`, `use: "sig"`, `alg: "Ed25519"` and a `kid` that is the
      RFC 7638 thumbprint of its public half. A PEM is refused.

  Nothing secret appears in what it raises.

  **What the process does.** It fetches `<issuer>/.well-known/openid-configuration` and
  the key set the document names, and keeps both, refetching every five minutes. It
  starts while EHOS is down: a failed fetch is logged and retried after one
  second, doubling to thirty, and a failed refetch keeps what was held. Every call to
  EHOS goes over https, follows no redirect, reads at most 64 KiB and ends after ten
  seconds; EHOS's certificate is checked against the system's authorities, or
  `cacertfile:` / `cacerts:` when given. A document is not held unless its `issuer` is
  the configured one and its endpoints are at the issuer's own origin, held to the rule
  the configured addresses are: https, read back as written, with a lowercase
  host, and no user, query or fragment.

  **What is held.** The client and the addresses derived from `address`, for the
  sign-in itself (`config/1`): the redirect URI is `address <> "/auth/ehos/callback"`
  and the post-logout address `address <> "/"`, never configured.
  """

  use GenServer

  require Logger

  alias EhOsContract.Auth.{Address, Keys}
  alias EhOsContract.Auth.SignIn.{Cipher, ClientKey, Http}

  @timeout 10_000
  @refresh_every :timer.minutes(5)
  @retry_min 1_000
  @retry_max 30_000
  @min_secret 64
  @sign_in_keys [:client_id, :client_key_file, :address, :secret_key_base, :applications]
  # The endpoints of the document `oidcc` calls or sends the browser to; a PAR endpoint is posted
  # the client's assertion whenever the document names one. `mtls_endpoint_aliases` would replace
  # the token and PAR endpoints only for `tls_client_auth`, which needs `ssl:` in `request_opts`,
  # and this client has none (`oidcc_auth_util:maybe_mtls_endpoint/4`).
  @endpoints [
    :authorization_endpoint,
    :token_endpoint,
    :jwks_uri,
    :userinfo_endpoint,
    :end_session_endpoint,
    :pushed_authorization_request_endpoint
  ]

  @derive {Inspect, except: [:client_key, :client_secret, :secret_key_base, :cipher_key]}
  @enforce_keys [
    :name,
    :issuer,
    :client_id,
    :client_key,
    :address,
    :redirect_uri,
    :post_logout_redirect_uri,
    :applications,
    :secret_key_base,
    :cipher_key,
    :request_opts
  ]
  defstruct [:client_secret | @enforce_keys]

  @typedoc """
  The application's client, as `config/1` returns it. `client_key`, `client_secret`,
  `secret_key_base` and `cipher_key`, the key the session's tokens are encrypted with,
  are left out of its inspection.

  `client_secret` is random, made at each start and never written down. EHOS
  takes `private_key_jwt` alone, so it authenticates nothing; it is there because
  `oidcc` refuses every other method without one, and it is random because `oidcc`
  turns it into a key for any `HS*` algorithm a document names.
  """
  @type t :: %__MODULE__{
          name: atom(),
          issuer: String.t(),
          client_id: String.t(),
          client_key: JOSE.JWK.t(),
          address: String.t(),
          redirect_uri: String.t(),
          post_logout_redirect_uri: String.t(),
          applications: %{String.t() => String.t()},
          secret_key_base: String.t(),
          cipher_key: binary(),
          client_secret: String.t() | nil,
          request_opts: map()
        }

  # What the document must say: S6 in docs/adr/browser-session.md.
  @typedoc "Why a document is not one a person can be signed in with."
  @type unsupported ::
          :no_iss_parameter
          | :no_s256
          | :no_ed25519_id_token
          | :symmetric_id_token_alg
          | :no_private_key_jwt

  @typedoc "Why the provider cannot be signed in with."
  @type unavailable :: :ehos_unavailable | {:unsupported_provider, [unsupported()]}

  @doc """
  The child for the application's supervision tree, after `EhOsContract.Auth`. Raises on
  what the module's doc lists. `opts` take `:name` (`EhOsContract.Auth.SignIn` by
  default), and `:cacertfile` or `:cacerts` for an EHOS behind an authority of its own.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    # Built here to fail the boot while the children are listed, then again in
    # `init/1`: the start arguments carry only `opts`, so no crash report prints the
    # key.
    _checked = build!(opts)

    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc "Starts the process. See `child_spec/1`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  The client the process named `name` holds. Raises when it is not running: signing
  in without the child is a defect of the host's wiring, not a request to refuse.
  """
  @spec config(atom()) :: t()
  def config(name \\ __MODULE__) do
    case held(name, :config) do
      {:ok, config} ->
        config

      :error ->
        raise ArgumentError,
              "#{inspect(name)} is not started: add EhOsContract.Auth.SignIn to the " <>
                "application's supervision tree"
    end
  end

  # The checks are S6 in docs/adr/browser-session.md.
  @doc """
  EHOS's discovery document, when a person can be signed in with it.

  `oidcc` checks the authorization response's `iss`, sends PKCE and authenticates the
  client with `private_key_jwt` only when the document says the provider supports
  them, and quietly does without otherwise; and it accepts ID tokens in every
  algorithm the document names, an `HS*` one with a key made from the client secret.
  So the document is checked here before any sign-in: `{:error, {:unsupported_provider,
  reasons}}` names every one of these that fails:

    * `authorization_response_iss_parameter_supported: true` — `:no_iss_parameter`;
    * `S256` among `code_challenge_methods_supported` — `:no_s256`;
    * `Ed25519` among `id_token_signing_alg_values_supported` — `:no_ed25519_id_token`;
    * no `none` and no `HS*` among them — `:symmetric_id_token_alg`;
    * `private_key_jwt` with `Ed25519` or `EdDSA` for the token endpoint —
      `:no_private_key_jwt`.

  `{:error, :ehos_unavailable}` until a document and its keys have been fetched, or
  when the process is not running. It reads what is held, and never fetches, waits or
  raises.
  """
  @spec provider(atom()) :: {:ok, Oidcc.ProviderConfiguration.t()} | {:error, unavailable()}
  def provider(name \\ __MODULE__) do
    case held(name, :provider) do
      {:ok, {configuration, _jwks, []}} -> {:ok, configuration}
      {:ok, {_configuration, _jwks, reasons}} -> {:error, {:unsupported_provider, reasons}}
      :error -> {:error, :ehos_unavailable}
    end
  end

  # Built per call from the process's name: S1 as amended, docs/adr/browser-session.md.
  @doc """
  The client context `oidcc` calls EHOS with: the document and keys held, when a
  person can be signed in with them (`provider/1`), the client's id, its random
  secret and its private key (`Oidcc.ClientContext.from_manual/5`).

  It holds the private key, and neither `oidcc`'s struct nor `JOSE.JWK` leaves it
  out of an inspection. So it is built for the call that needs it, from the process's
  name, and is never kept, logged, assigned to a connection or passed to anything
  but `oidcc`. The same errors as `provider/1`; never fetches, waits or raises.
  """
  @spec client_context(atom()) :: {:ok, Oidcc.ClientContext.t()} | {:error, unavailable()}
  def client_context(name \\ __MODULE__) do
    # One read of what is held, so a refetch in between cannot pair one document with
    # another's keys.
    with {:ok, {configuration, jwks, []}} <- held(name, :provider),
         {:ok, config} <- held(name, :config) do
      {:ok,
       Oidcc.ClientContext.from_manual(
         configuration,
         jwks,
         config.client_id,
         config.client_secret,
         %{client_jwks: config.client_key}
       )}
    else
      {:ok, {_configuration, _jwks, reasons}} -> {:error, {:unsupported_provider, reasons}}
      :error -> {:error, :ehos_unavailable}
    end
  end

  @doc """
  Fetches EHOS's document and keys now, and answers how it went. What was held is kept
  when the fetch fails. For operations and tests, and for a renewal that meets a key it
  does not hold; the process refetches on its own. `timeout` bounds the wait, not the
  fetch, which goes on and is kept.
  """
  @spec refresh(atom(), timeout()) :: :ok | {:error, term()}
  def refresh(name \\ __MODULE__, timeout \\ 3 * @timeout) do
    GenServer.call(name, :refresh, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, _not_running -> {:error, :not_running}
  end

  # The table is the process's own and goes with it, so a stopped child holds nothing.
  defp held(name, key) do
    case :ets.lookup(name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  @impl GenServer
  def init(opts) do
    config = %{build!(opts) | client_secret: random_secret()}
    :ets.new(config.name, [:named_table, :protected, :set, read_concurrency: true])
    true = :ets.insert(config.name, {:config, config})

    state = %{
      name: config.name,
      issuer: config.issuer,
      http: config.request_opts.http_adapter |> elem(1),
      retry_in: @retry_min,
      timer: nil
    }

    {:ok, state, {:continue, :fetch}}
  end

  @impl GenServer
  def handle_continue(:fetch, state), do: {:noreply, fetch_and_schedule(state)}

  @impl GenServer
  def handle_info(:fetch, state), do: {:noreply, fetch_and_schedule(%{state | timer: nil})}

  @impl GenServer
  def handle_call(:refresh, _from, state) do
    {result, state} = fetch(state)
    {:reply, result, schedule(state, result)}
  end

  defp fetch_and_schedule(state) do
    {result, state} = fetch(state)
    schedule(state, result)
  end

  defp schedule(state, result) do
    if state.timer, do: Process.cancel_timer(state.timer)

    {wait, state} =
      case result do
        :ok ->
          {@refresh_every, %{state | retry_in: @retry_min}}

        {:error, _reason} ->
          {state.retry_in, %{state | retry_in: min(state.retry_in * 2, @retry_max)}}
      end

    %{state | timer: Process.send_after(self(), :fetch, wait)}
  end

  defp fetch(state) do
    url = state.issuer <> "/.well-known/openid-configuration"

    with {:ok, document} <- Http.get_json(url, state.http),
         {:ok, configuration} <- decode(document),
         :ok <- same_issuer(configuration, state.issuer),
         :ok <- endpoints_held(configuration, state.issuer),
         {:ok, keys} <- Http.get_json(configuration.jwks_uri, state.http),
         {:ok, jwks} <- key_set(keys) do
      reasons = unsupported(configuration)
      log_unsupported(state.name, reasons)
      true = :ets.insert(state.name, {:provider, {configuration, jwks, reasons}})
      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning(
          "eh_os_contract_auth could not fetch EHOS's sign-in document or keys from " <>
            "#{state.issuer}: #{inspect(reason)}; " <>
            if(held(state.name, :provider) == :error,
              do: "nobody can sign in until it can",
              else: "the document and keys held are kept"
            )
        )

        {{:error, reason}, state}
    end
  end

  # `oidcc`'s decoder raises on some malformed documents (a relative URI where it wants
  # https, for one); that is a document refused, never a crash of this process.
  defp decode(document) do
    case Oidcc.ProviderConfiguration.decode_configuration(document) do
      {:ok, configuration} -> {:ok, configuration}
      {:error, reason} -> {:error, {:invalid_document, reason}}
    end
  rescue
    exception -> {:error, {:invalid_document, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:invalid_document, {kind, reason}}}
  end

  defp same_issuer(%{issuer: issuer}, issuer), do: :ok
  defp same_issuer(%{issuer: other}, _issuer), do: {:error, {:issuer_mismatch, other}}

  # By the rule the configured addresses are held to (#89), so the browser and `oidcc` go where
  # the check read: `https://evil.example\@ehos.test/...` passed a prefix, and a browser sent there
  # goes to evil.example. And at the issuer's own origin, where EHOS serves every one: an endpoint
  # elsewhere would be posted the code, the PKCE verifier and the client's assertion.
  defp endpoints_held(configuration, issuer) do
    case Enum.reject(@endpoints, &held_or_absent?(Map.get(configuration, &1), issuer)) do
      [] -> :ok
      endpoints -> {:error, {:endpoints_refused, endpoints}}
    end
  end

  defp held_or_absent?(:undefined, _issuer), do: true
  defp held_or_absent?(nil, _issuer), do: true

  defp held_or_absent?(endpoint, issuer) do
    Address.check(endpoint, plain_on_loopback: false, path: true) == :ok and
      origin(endpoint) == origin(issuer)
  end

  defp origin(address) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(address)
    {scheme, host, port}
  end

  defp key_set(%{"keys" => [_ | _]} = keys) do
    {:ok, JOSE.JWK.from_map(keys)}
  rescue
    _malformed -> {:error, :invalid_key_set}
  end

  defp key_set(_keys), do: {:error, :invalid_key_set}

  defp unsupported(configuration) do
    id_token_algs = list(configuration.id_token_signing_alg_values_supported)

    [
      {configuration.authorization_response_iss_parameter_supported == true, :no_iss_parameter},
      {"S256" in list(configuration.code_challenge_methods_supported), :no_s256},
      {"Ed25519" in id_token_algs, :no_ed25519_id_token},
      {not Enum.any?(id_token_algs, &(&1 == "none" or String.starts_with?(&1, "HS"))),
       :symmetric_id_token_alg},
      {"private_key_jwt" in list(configuration.token_endpoint_auth_methods_supported) and
         Enum.any?(
           list(configuration.token_endpoint_auth_signing_alg_values_supported),
           &(&1 in ["Ed25519", "EdDSA"])
         ), :no_private_key_jwt}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  # Once per document that changes the answer, not on every sign-in that is refused.
  defp log_unsupported(name, reasons) do
    previous =
      case held(name, :provider) do
        {:ok, {_configuration, _jwks, previous}} -> previous
        :error -> []
      end

    if reasons != [] and reasons != previous do
      Logger.error(
        "eh_os_contract_auth refuses to sign anyone in with EHOS's discovery document: " <>
          "#{inspect(reasons)} (S6 in docs/adr/browser-session.md)"
      )
    end
  end

  defp list(values) when is_list(values), do: values
  defp list(_undefined), do: []

  defp build!(opts) do
    Keyword.validate!(opts, [:name, :cacertfile, :cacerts, :plug])
    name = Keyword.get(opts, :name, __MODULE__)

    unless is_atom(name) do
      raise ArgumentError, "EhOsContract.Auth.SignIn takes name: as an atom"
    end

    env = Application.get_all_env(:eh_os_contract_auth)

    # Checked before anything reads it, and never inspected: it holds the secret.
    sign_in =
      case env[:sign_in] do
        nil ->
          raise ArgumentError,
                "config :eh_os_contract_auth, sign_in: [...] is missing; it names the " <>
                  "application's client at EHOS (eh-os D-64)"

        sign_in when is_list(sign_in) ->
          if Keyword.keyword?(sign_in), do: sign_in, else: not_a_keyword_list!()

        _other ->
          not_a_keyword_list!()
      end

    unknown = Keyword.keys(sign_in) -- @sign_in_keys

    unless unknown == [] do
      raise ArgumentError,
            "config :eh_os_contract_auth, sign_in: takes #{inspect(@sign_in_keys)}, " <>
              "not #{inspect(unknown)}"
    end

    issuer = issuer!(env[:issuer])
    address = origin!("address", sign_in[:address])
    secret_key_base = secret_key_base!(sign_in[:secret_key_base])

    %__MODULE__{
      name: name,
      issuer: issuer,
      client_id: client_id!(sign_in[:client_id]),
      client_key: ClientKey.load!(client_key_file!(sign_in[:client_key_file])),
      address: address,
      redirect_uri: address <> "/auth/ehos/callback",
      post_logout_redirect_uri: address <> "/",
      applications: applications!(Keyword.get(sign_in, :applications, %{}), address),
      secret_key_base: secret_key_base,
      cipher_key: Cipher.key(secret_key_base),
      request_opts: %{timeout: @timeout, http_adapter: {Http, http!(opts)}}
    }
  end

  defp random_secret, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp not_a_keyword_list! do
    raise ArgumentError, "config :eh_os_contract_auth, sign_in: must be a keyword list"
  end

  defp client_id!(id) when is_binary(id) and id != "", do: id

  defp client_id!(other) do
    raise ArgumentError,
          "sign_in: client_id must be the client's identifier at EHOS, EHOS_CLIENT_ID, " <>
            "and is #{inspect(other)}"
  end

  defp client_key_file!(path) when is_binary(path) and path != "", do: path

  defp client_key_file!(_other) do
    raise ArgumentError,
          "sign_in: client_key_file must be the path of the client's key, EHOS_CLIENT_KEY_FILE"
  end

  defp secret_key_base!(secret) when is_binary(secret) and byte_size(secret) >= @min_secret,
    do: secret

  defp secret_key_base!(_other) do
    raise ArgumentError,
          "sign_in: secret_key_base must be the application's SECRET_KEY_BASE, at least " <>
            "#{@min_secret} bytes; the session's tokens are encrypted with a key derived from it"
  end

  # eh-os D-69: the other applications, never this one. Under this application's own address,
  # `Session.credential/3` would hand out its own credential as another's.
  defp applications!(applications, own) when is_map(applications) do
    Map.new(applications, fn
      {name, address} when is_binary(name) and name != "" ->
        case origin!("the address of #{inspect(name)} in applications", address) do
          ^own ->
            raise ArgumentError,
                  "sign_in: #{inspect(name)} in applications is this application's address, " <>
                    "#{own}; applications names the other applications its pages call"

          address ->
            {name, address}
        end

      {name, _address} ->
        raise ArgumentError,
              "sign_in: applications maps application names to addresses, and has the key " <>
                inspect(name)
    end)
  end

  # Not printed: unchecked, it may hold an address with a password in it.
  defp applications!(other, _own) do
    raise ArgumentError,
          "sign_in: applications must map application names to their addresses " <>
            "(EHOS_SIGN_IN_APPLICATIONS, decoded), and is #{kind(other)}"
  end

  defp kind(value) when is_list(value), do: "a list"
  defp kind(value) when is_binary(value), do: "a string"
  defp kind(_value), do: "neither a map nor a list"

  # `https://<host>`, exactly: an application's address for `resource` and the base of
  # this one's callback and post-logout addresses (eh-os D-68), which EHOS compares as
  # strings, so no port and no upper case either.
  # Read alike by every parser too (#89), so a browser goes where the comparison says.
  defp origin!(what, value) when is_binary(value) do
    with :ok <- Address.check(value, plain_on_loopback: false, path: false),
         %URI{host: host} <- URI.parse(value),
         true <- value == "https://" <> host do
      value
    else
      _refused -> origin_refused!(what, value)
    end
  end

  defp origin!(what, value), do: origin_refused!(what, value)

  defp origin_refused!(what, value) do
    raise ArgumentError,
          "sign_in: #{what} must be https://<host>, in lower case, with no port, no path, " <>
            "no trailing slash and no query (eh-os D-68), as every parser reads it, and is " <>
            Address.shown(value)
  end

  # Discovery and the token endpoint are what a sign-in trusts, and `oidcc` refuses an
  # http document's endpoints anyway, so https without exception; and what `oidcc`
  # would refuse in an issuer is refused here, at boot, rather than retried for ever.
  defp issuer!(issuer) when is_binary(issuer) do
    case Address.check(issuer, plain_on_loopback: false, path: false) do
      :ok ->
        issuer

      :error ->
        raise ArgumentError,
              "sign-in asks EHOS at #{Address.shown(issuer)}, which is not https://<host>[:port] " <>
                "alone, as every parser reads it: a lowercase host, and no user, path, query " <>
                "or fragment, as EHOS's issuer never has"
    end
  end

  defp issuer!(nil) do
    raise ArgumentError,
          "config :eh_os_contract_auth, issuer: \"<EHOS's public URL>\" is missing; " <>
            "sign-in asks it for its discovery document"
  end

  defp issuer!(_other) do
    raise ArgumentError, "config :eh_os_contract_auth, issuer: must be a string, EHOS_ISSUER"
  end

  defp http!(opts) do
    if Keyword.has_key?(opts, :plug) and not Keys.test_trust?() do
      # Whatever the plug answers is trusted as EHOS, as `plug:` is for
      # `EhOsContract.Auth.Keys`.
      raise ArgumentError,
            "EhOsContract.Auth.SignIn takes plug: only in a test: whatever it answers is " <>
              "trusted as EHOS. Set config :eh_os_contract_auth, pin_keys: true in " <>
              "config/test.exs"
    end

    opts |> Keyword.take([:cacertfile, :cacerts, :plug]) |> Map.new()
  end
end
