defmodule EhOsContract.Auth.SignIn do
  @moduledoc """
  Signing a person in to the application's pages through EHOS, with OpenID Connect
  (`eh-os` D-64): the application's client, and the child that keeps EHOS's discovery
  document. What the package decides beside D-64 is `docs/adr/browser-session.md` in
  this repository; S1–S11 below are its sections.

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

    * `config :eh_os_contract_auth, :sign_in` or the top-level `:issuer` is missing,
      or `sign_in:` has a key it does not take;
    * `client_id` is not a non-empty string;
    * `address`, or an address in `applications`, is not exactly
      `https://<host>`: no path, no trailing slash, no query (`eh-os` D-68);
    * `secret_key_base` is shorter than 64 bytes, Phoenix's own minimum;
    * the file at `client_key_file` is not one private Ed25519 JWK with exactly
      `kty`, `crv`, `x`, `d`, `use: "sig"`, `alg: "Ed25519"` and a `kid` that is the
      RFC 7638 thumbprint of its public half (`eh-os` D-68). A PEM is refused;
    * the issuer is not https (plain http is allowed for `localhost` only).

  Nothing secret appears in what it raises.

  **What the child runs.** A supervisor with one `Oidcc.ProviderConfiguration.Worker`,
  which fetches `<issuer>/.well-known/openid-configuration` and EHOS's keys and keeps
  them current. It starts while EHOS is down (FM-19): a failed fetch is retried, at
  one to thirty seconds, and never stops the worker. Until the first fetch,
  `provider/1` answers `{:error, :ehos_unavailable}`.

  **What is held.** The client and the addresses derived from `address`, for the
  sign-in itself (`config/1`): the redirect URI is `address <> "/auth/ehos/callback"`
  (D-64) and the post-logout address `address <> "/"` (D-68), never configured. Calls to
  EHOS time out after ten seconds (S6), and its certificate is checked against the
  system's certificate authorities, or `cacertfile:` / `cacerts:` when given.
  """

  use Supervisor

  alias EhOsContract.Auth.SignIn.ClientKey

  @timeout 10_000
  @min_secret 64
  @sign_in_keys [:client_id, :client_key_file, :address, :secret_key_base, :applications]

  @derive {Inspect, except: [:client_key, :secret_key_base]}
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
    :provider,
    :request_opts
  ]
  defstruct @enforce_keys

  @typedoc """
  The application's client, as `config/1` returns it. `client_key` and
  `secret_key_base` are left out of its inspection.
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
          provider: atom(),
          request_opts: map()
        }

  @typedoc "Why the provider cannot be signed in with."
  @type unavailable ::
          :ehos_unavailable
          | {:unsupported_provider,
             [:no_iss_parameter | :no_s256 | :no_ed25519_id_token | :no_private_key_jwt]}

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
      type: :supervisor
    }
  end

  @doc "Starts the child. See `child_spec/1`."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Supervisor
  def init(opts) do
    config = build!(opts)
    # Written once per start, and the same value on a restart, which leaves
    # `:persistent_term` as it is.
    :persistent_term.put({__MODULE__, config.name}, config)

    worker =
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer: config.issuer,
         name: config.provider,
         provider_configuration_opts: %{request_opts: config.request_opts},
         # Its default, `stop`, ends the worker at the first failed fetch, and a few
         # restarts with EHOS down would take the application with it.
         backoff_type: :random_exponential,
         backoff_min: 1_000,
         backoff_max: 30_000
       }}

    Supervisor.init([worker], strategy: :one_for_one)
  end

  @doc """
  The client the child named `name` holds. Raises when it is not running: signing in
  without the child is a defect of the host's wiring, not a request to refuse.
  """
  @spec config(atom()) :: t()
  def config(name \\ __MODULE__) do
    case :persistent_term.get({__MODULE__, name}, nil) do
      %__MODULE__{} = config ->
        config

      nil ->
        raise ArgumentError,
              "#{inspect(name)} is not started: add EhOsContract.Auth.SignIn to the " <>
                "application's supervision tree"
    end
  end

  @doc """
  EHOS's discovery document, when a person can be signed in with it (S6).

  `oidcc` checks the authorization response's `iss`, sends PKCE and authenticates the
  client with `private_key_jwt` only when the document says the provider supports
  them, and quietly does without otherwise. So the document is checked here before
  any sign-in: `{:error, {:unsupported_provider, reasons}}` names every one of these
  it lacks:

    * `authorization_response_iss_parameter_supported: true` — `:no_iss_parameter`;
    * `S256` among `code_challenge_methods_supported` — `:no_s256`;
    * `Ed25519` among `id_token_signing_alg_values_supported` — `:no_ed25519_id_token`;
    * `private_key_jwt` with `Ed25519` or `EdDSA` for the token endpoint —
      `:no_private_key_jwt`.

  `{:error, :ehos_unavailable}` until the document has been fetched once, or when the
  child is not running. It never fetches and never raises.
  """
  @spec provider(atom()) :: {:ok, Oidcc.ProviderConfiguration.t()} | {:error, unavailable()}
  def provider(name \\ __MODULE__) do
    with {:ok, config} <- running(name),
         {:ok, record} <- fetched(config.provider) do
      configuration = Oidcc.ProviderConfiguration.record_to_struct(record)

      case unsupported(configuration) do
        [] -> {:ok, configuration}
        reasons -> {:error, {:unsupported_provider, reasons}}
      end
    end
  end

  defp running(name) do
    case :persistent_term.get({__MODULE__, name}, nil) do
      %__MODULE__{} = config -> {:ok, config}
      nil -> {:error, :ehos_unavailable}
    end
  end

  # The Erlang call, not `Oidcc.ProviderConfiguration.Worker.get_provider_configuration/1`,
  # which raises on the `undefined` a worker answers before its first fetch.
  defp fetched(provider) do
    case :oidcc_provider_configuration_worker.get_provider_configuration(provider) do
      :undefined -> {:error, :ehos_unavailable}
      record -> {:ok, record}
    end
  catch
    :exit, _not_running -> {:error, :ehos_unavailable}
  end

  defp unsupported(configuration) do
    [
      {configuration.authorization_response_iss_parameter_supported == true, :no_iss_parameter},
      {"S256" in list(configuration.code_challenge_methods_supported), :no_s256},
      {"Ed25519" in list(configuration.id_token_signing_alg_values_supported),
       :no_ed25519_id_token},
      {"private_key_jwt" in list(configuration.token_endpoint_auth_methods_supported) and
         Enum.any?(
           list(configuration.token_endpoint_auth_signing_alg_values_supported),
           &(&1 in ["Ed25519", "EdDSA"])
         ), :no_private_key_jwt}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp list(values) when is_list(values), do: values
  defp list(_undefined), do: []

  defp build!(opts) do
    Keyword.validate!(opts, [:name, :cacertfile, :cacerts, :http_adapter])
    name = Keyword.get(opts, :name, __MODULE__)
    env = Application.get_all_env(:eh_os_contract_auth)

    sign_in =
      env[:sign_in] ||
        raise ArgumentError,
              "config :eh_os_contract_auth, sign_in: [...] is missing; it names the " <>
                "application's client at EHOS (eh-os D-64)"

    unknown = Keyword.keys(sign_in) -- @sign_in_keys

    unless unknown == [] do
      raise ArgumentError,
            "config :eh_os_contract_auth, sign_in: takes #{inspect(@sign_in_keys)}, " <>
              "not #{inspect(unknown)}"
    end

    issuer =
      env[:issuer] ||
        raise ArgumentError,
              "config :eh_os_contract_auth, issuer: \"<EHOS's public URL>\" is missing; " <>
                "sign-in asks it for its discovery document"

    issuer!(issuer)
    address = origin!("address", sign_in[:address])

    %__MODULE__{
      name: name,
      issuer: issuer,
      client_id: client_id!(sign_in[:client_id]),
      client_key: ClientKey.load!(client_key_file!(sign_in[:client_key_file])),
      address: address,
      redirect_uri: address <> "/auth/ehos/callback",
      post_logout_redirect_uri: address <> "/",
      applications: applications!(Keyword.get(sign_in, :applications, %{})),
      secret_key_base: secret_key_base!(sign_in[:secret_key_base]),
      provider: Module.concat(name, Provider),
      request_opts: request_opts!(opts)
    }
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

  defp applications!(applications) when is_map(applications) do
    Map.new(applications, fn
      {name, address} when is_binary(name) and name != "" ->
        {name, origin!("the address of #{inspect(name)} in applications", address)}

      {name, _address} ->
        raise ArgumentError,
              "sign_in: applications maps application names to addresses, and has the key " <>
                inspect(name)
    end)
  end

  defp applications!(other) do
    raise ArgumentError,
          "sign_in: applications must map application names to their addresses " <>
            "(EHOS_SIGN_IN_APPLICATIONS, decoded), and is #{inspect(other)}"
  end

  # `https://<host>`, exactly: an application's address for `resource` and the base of
  # this one's callback and post-logout addresses (eh-os D-68), which EHOS compares as
  # strings.
  defp origin!(what, value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host, path: nil, query: nil, fragment: nil, userinfo: nil}
      when is_binary(host) and host != "" ->
        value

      _other ->
        raise ArgumentError,
              "sign_in: #{what} must be https://<host>, with no path, no trailing slash and " <>
                "no query (eh-os D-68), and is #{inspect(value)}"
    end
  end

  defp origin!(what, value) do
    raise ArgumentError, "sign_in: #{what} must be https://<host>, and is #{inspect(value)}"
  end

  # Discovery and the token endpoint are what a sign-in trusts, so the same rule as
  # the key set's URL (`EhOsContract.Auth.Keys`): https, and plain http on loopback only.
  defp issuer!(issuer) do
    case URI.parse(issuer) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        :ok

      %URI{scheme: "http", host: host} when host in ["localhost", "127.0.0.1", "::1"] ->
        :ok

      _other ->
        raise ArgumentError,
              "sign-in asks EHOS at #{inspect(issuer)}, which is not https: a discovery " <>
                "document fetched in the clear can be replaced on the way. Only localhost " <>
                "may be plain http"
    end
  end

  defp request_opts!(opts) do
    request_opts = %{timeout: @timeout, ssl: ssl(opts)}

    case Keyword.fetch(opts, :http_adapter) do
      :error ->
        request_opts

      {:ok, adapter} ->
        # Whatever the adapter answers is trusted as EHOS, so only where test keys may
        # be pinned, as `plug:` is for `EhOsContract.Auth.Keys`.
        unless Application.get_env(:eh_os_contract_auth, :pin_keys, false) == true do
          raise ArgumentError,
                "EhOsContract.Auth.SignIn takes http_adapter: only in a test: whatever it " <>
                  "answers is trusted as EHOS. Set config :eh_os_contract_auth, " <>
                  "pin_keys: true in config/test.exs"
        end

        Map.put(request_opts, :http_adapter, adapter)
    end
  end

  # The peer is checked, by name, against the system's authorities or the ones given,
  # never left to `httpc`'s defaults (S6).
  # The system's authorities are read only when none are given: on a machine without
  # them, reading would fail the boot of a host that named its own.
  defp ssl(opts) do
    case Keyword.take(opts, [:cacertfile, :cacerts]) do
      [] ->
        :httpc.ssl_verify_host_options(true)

      authority ->
        [
          verify: :verify_peer,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ authority
    end
  end
end
