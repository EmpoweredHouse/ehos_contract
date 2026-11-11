defmodule EhOsContract.Auth.Development do
  # The mode, its refusal and its properties are a decision of EHOS's (#619): a key made at start
  # and held in memory, a switch of its own, a refusal that reads its inputs directly, a token
  # printed at start, renewal only through this process.
  @moduledoc """
  Signs a person in on a developer's computer, where no EHOS runs: the development mode.

  With `mix phx.server` and no EHOS, nobody can sign in through EHOS, so no page behind
  `EhOsContract.Auth.Session` opens. In this mode the application signs the credential
  itself, with a key it makes when the mode starts, for a person with the actors of its
  domain that the developer chooses. The credential then goes through the same
  `EhOsContract.Auth.verify/2`, `EhOsContract.Auth.Session`, `EhOsContract.Auth.Plug` and
  the engine's check as one EHOS issued.

      # config/dev.exs, and no other file
      config :eh_os_contract_auth, development: true

      # the supervision tree, after EhOsContract.Auth, in every environment
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.Development]

      # the router, in the `dev_routes` block
      scope "/dev" do
        pipe_through [:browser, EhOsContract.Auth.Development.Guard]
        get "/sign-in", MyAppWeb.DevSignInController, :new
        post "/sign-in", MyAppWeb.DevSignInController, :create
      end

      forward "/dev/credential", EhOsContract.Auth.Development.Credential

  Without the switch, the child starts nothing (`start_link/1` answers `:ignore`), so the
  same list of children serves every environment.

  **The refusal.** With the switch set, the mode starts only where all of these hold, and
  the child raises, failing the boot, where one does not:

    * the `:mix` application is started, a Mix project is loaded, and `Mix.env()` is
      `:dev`, as in `mix phx.server` and `iex -S mix`;
    * the process is not a release: neither `RELEASE_NAME` nor `RELEASE_ROOT` is set;
    * EHOS did not configure the workload: neither `EHOS_ISSUER` nor `EHOS_AUDIENCE` is
      set, and none of `sign_in:`, `workload:` and its older name `people:` is configured.

  It reads the started applications, the Mix project, Mix's environment and the process's
  environment directly. No option or configuration makes a condition hold. A release can
  carry Mix, and there `Mix.env()` is `:dev` when `MIX_ENV` is not set, so Mix alone is not
  the guard: the other two conditions refuse that case.

  **The key.** An Ed25519 key, made when the mode starts and held in this process's memory
  only. Nothing writes it to disk or to the table of keys. The mode pins its public half in
  `EhOsContract.Auth.Keys` (`EhOsContract.Auth.Keys.pin/2`), which admits it only from a
  mode that started. A restart makes a new key, and ends every session signed in before
  it: the browser is sent to `/dev/sign-in` again. A verifier that did not pin the key,
  another application's for one, refuses each credential signed with it.

  **The token.** A random token, made when the mode starts and printed in the terminal,
  as Livebook prints its own. `EhOsContract.Auth.Development.Guard` lets a request through
  only with it, from a loopback address, with a `Host` of `localhost`, `127.0.0.1` or
  `[::1]`. A computer on the network, a proxy or a tunnel does not have it.

  **A person signed in.** `sign_in/3` writes a session for the browser as signing in
  through EHOS does; `credential/3` answers a bearer credential, for `curl`. The
  credential grants the union of the capabilities the domain grants the chosen actors
  (`EhOsContract.Model.capabilities/1`), each scoped capability with the value given for
  its scope, and lives ten minutes, as EHOS's does. `actors/0` lists what to choose from.

  **Renewal.** When a session's credential expires, this process signs a new one with the
  same claims, as EHOS renews one, so a page does not answer 503 after ten minutes. Only a
  credential signed by this process's key is renewed. A session it cannot renew, one from
  before a restart for one, is signed out, and the browser is sent to `/dev/sign-in`.

  **What is not EHOS's here.** OpenID Connect, a sign-out at EHOS, a real grant and a real
  message do not happen. Check them with EHOS before a pull request. The people, grants
  and mail take the stand-ins for development: [Use people, grants and mail where EHOS does
  not answer](without-ehos.md). How to set the mode up: [Sign a person in on a developer's
  computer](development.md).
  """

  use GenServer

  alias EhOsContract.Auth.{Keys, SignIn, Signing}
  alias EhOsContract.Auth.SignIn.{Cipher, Http}

  # The table that marks the mode as started: written only by this process, after the refusal.
  @marker __MODULE__
  @path "/dev/sign-in"
  @placeholder_address "https://application.localhost"

  @typedoc "What `start_link/1` takes."
  @type option :: {:url, String.t()}

  @typedoc "An actor of the domain, as `actors/0` lists it."
  @type actor :: %{
          role: String.t(),
          capabilities: [String.t()],
          scopes: [String.t()]
        }

  @typedoc "Why `sign_in/3` or `credential/3` signs nothing."
  @type refusal ::
          :not_started
          | :no_subject
          | :malformed
          | {:unknown_actors, [String.t()]}
          | {:missing_scopes, [String.t()]}

  @doc """
  The child for the application's supervision tree, after `EhOsContract.Auth`, which it
  pins its key in. See `start_link/1`.
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @doc """
  Starts the mode where `config :eh_os_contract_auth, development: true` is set, and answers
  `:ignore` where it is not.

  `url:` is the application's address, such as `"http://localhost:4000"`, printed with the
  token so the developer can open the page from the terminal.

  Raises `ArgumentError`, naming each condition that fails, where the switch is set and the
  module's refusal holds; on an option it does not take; on a switch that is not `true` or
  `false`; and where `EhOsContract.Auth` is not running.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = opts |> Keyword.validate!([:url]) |> Keyword.update(:url, nil, &url/1)

    if switch?() do
      :ok = refuse!()

      unless Process.whereis(Keys) do
        raise ArgumentError,
              "EhOsContract.Auth is not running, so the development key has nowhere to be " <>
                "trusted: list EhOsContract.Auth.Development after it"
      end

      GenServer.start_link(__MODULE__, opts, name: SignIn)
    else
      :ignore
    end
  end

  defp url(nil), do: nil
  defp url(url) when is_binary(url), do: String.trim_trailing(url, "/")

  @doc false
  # Why the mode may not start here: `:ok`, or each condition that fails, in words. Reads
  # every input directly; nothing a host sets reaches it but the three keys of its own
  # configuration that EHOS's credentials are configured under.
  @spec refusal() :: :ok | {:error, [String.t()]}
  def refusal do
    case mix_refusal() ++ release_refusal() ++ ehos_refusal() do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  defp mix_refusal do
    cond do
      not List.keymember?(Application.started_applications(), :mix, 0) ->
        ["the :mix application is not started, as it is in mix phx.server and iex -S mix"]

      Mix.Project.get() == nil ->
        ["no Mix project is loaded"]

      Mix.env() != :dev ->
        ["Mix's environment is #{inspect(Mix.env())}, not :dev"]

      true ->
        []
    end
  end

  defp release_refusal do
    for variable <- ~w(RELEASE_NAME RELEASE_ROOT), System.get_env(variable) != nil do
      "#{variable} is set, as it is in a release"
    end
  end

  defp ehos_refusal do
    variables =
      for variable <- ~w(EHOS_ISSUER EHOS_AUDIENCE), System.get_env(variable) != nil do
        "#{variable} is set, as EHOS sets it in every container it starts"
      end

    keys =
      for key <- [:sign_in, :workload, :people],
          Application.get_env(:eh_os_contract_auth, key) != nil do
        "config :eh_os_contract_auth, #{key}: is configured, as it is where EHOS runs the " <>
          "application"
      end

    variables ++ keys
  end

  defp refuse! do
    case refusal() do
      :ok ->
        :ok

      {:error, reasons} ->
        raise ArgumentError,
              "config :eh_os_contract_auth, development: true is set, and the development " <>
                "mode refuses to start here, since it would trust a key EHOS did not issue:\n" <>
                Enum.map_join(reasons, "\n", &("  * " <> &1)) <>
                "\nSet the line in config/dev.exs alone, and run the application with " <>
                "mix phx.server or iex -S mix"
    end
  end

  defp switch? do
    case Application.get_env(:eh_os_contract_auth, :development, false) do
      flag when is_boolean(flag) ->
        flag

      other ->
        raise ArgumentError,
              "config :eh_os_contract_auth, development: takes true or false, not " <>
                inspect(other)
    end
  end

  @doc false
  # Whether `jwk` is the public key of the mode that started here, which `Keys.pin/2` admits
  # outside a test. The refusal is read again, and the key compared with the one the mode's
  # process wrote in its table, which no other process can write.
  @spec key?(map()) :: boolean()
  def key?(jwk) when is_map(jwk) do
    case mode() do
      {:ok, %{public: ^jwk}} -> switch?() and refusal() == :ok
      _other -> false
    end
  end

  @doc false
  # Whether the sign-in child under `name` is the mode's process: what renews a session and
  # where the browser is sent to sign in. Nothing in a session chooses it.
  @spec started?(atom()) :: boolean()
  def started?(name) do
    case mode() do
      {:ok, %{pid: pid}} -> Process.whereis(name) == pid
      :error -> false
    end
  end

  @doc false
  # The page a browser is sent to sign in where the mode runs under `name`, or nil.
  @spec sign_in_path(atom()) :: String.t() | nil
  def sign_in_path(name), do: if(started?(name), do: @path)

  @doc false
  # Whether `token` is the one the mode printed at start. Compared by its hash, in constant
  # time; the token itself is not kept.
  @spec token?(term()) :: boolean()
  def token?(token) when is_binary(token) do
    case mode() do
      {:ok, %{token_hash: hash}} -> Plug.Crypto.secure_compare(hash(token), hash)
      :error -> false
    end
  end

  def token?(_token), do: false

  @doc false
  # Whether `encoded`, the URL-safe Base64 of a token's SHA-256, is the hash of the mode's
  # token: what a browser's Plug session keeps after the first request carried the token.
  @spec token_hash?(term()) :: boolean()
  def token_hash?(encoded) when is_binary(encoded) do
    with {:ok, given} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{token_hash: hash}} <- mode() do
      Plug.Crypto.secure_compare(given, hash)
    else
      _other -> false
    end
  end

  def token_hash?(_encoded), do: false

  defp mode do
    case :ets.lookup(@marker, :mode) do
      [{:mode, mode}] -> {:ok, mode}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  The actors of the domain a person can be signed in as: each role, `"<domain>.<actor>"`,
  with the capabilities the contracts grant it and the scopes those capabilities are
  checked along, sorted. Read from the contracts of `config :eh_os_contract, applications:`.
  """
  @spec actors() :: [actor()]
  def actors do
    granted()
    |> Enum.map(fn {role, capabilities} ->
      %{
        role: role,
        capabilities: capabilities |> Map.keys() |> Enum.sort(),
        scopes:
          capabilities |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.role)
  end

  # role => %{capability => scope dimension or nil}
  defp granted do
    for contract <- EhOsContract.Registry.load!().contracts,
        {capability, %{roles: roles} = access} <- EhOsContract.Model.capabilities(contract),
        role <- roles,
        reduce: %{} do
      acc ->
        scope = if access.scope, do: Atom.to_string(access.scope)
        Map.update(acc, role, %{capability => scope}, &Map.put(&1, capability, scope))
    end
  end

  @doc """
  Signs a browser in as `subject`, a person with `actors`, and answers the token for its
  session: put it in the Plug session under `EhOsContract.Auth.Session.session_key/0`, and
  `EhOsContract.Auth.Session` lets the browser's requests through.

      {:ok, token} =
        EhOsContract.Auth.Development.sign_in("u-dev", ["clinic.receptionist"], %{
          "clinic_id" => "clinic-1"
        })

      conn
      |> put_session(EhOsContract.Auth.Session.session_key(), token)
      |> redirect(to: "/")

  `scopes` maps each scope of the actors' capabilities to its value, or a list of values.
  Refuses, with `{:error, reason}`: `:not_started` where the mode has not started;
  `:no_subject` for an empty `subject`; `:malformed` when `actors` is not a list of strings
  or `scopes` not a map of strings to a string or a list of strings; `{:unknown_actors,
  roles}` for a role `actors/0` does not list; and `{:missing_scopes, scopes}` for a scope
  with no value.
  """
  @spec sign_in(String.t(), [String.t()], %{String.t() => String.t() | [String.t()]}) ::
          {:ok, String.t()} | {:error, refusal()}
  def sign_in(subject, actors, scopes \\ %{}) do
    with {:ok, token, expires_at} <- signed(subject, actors, scopes),
         do: Signing.session(SignIn, subject, token, expires_at, "dev")
  end

  @doc """
  A bearer credential for `subject`, a person with `actors`, as `sign_in/3` signs one: for
  `curl -H "authorization: Bearer <credential>"`. It lives ten minutes and is not renewed.
  Refuses as `sign_in/3` does.
  """
  @spec credential(String.t(), [String.t()], %{String.t() => String.t() | [String.t()]}) ::
          {:ok, String.t()} | {:error, refusal()}
  def credential(subject, actors, scopes \\ %{}) do
    with {:ok, token, _expires_at} <- signed(subject, actors, scopes), do: {:ok, token}
  end

  defp signed(subject, actors, scopes) do
    with :ok <- running(),
         :ok <- subject(subject),
         {:ok, capabilities, scp} <- claims(actors, scopes) do
      call({:sign, subject, capabilities, scp, EhOsContract.Clock.now()})
    end
  end

  defp running, do: if(started?(SignIn), do: :ok, else: {:error, :not_started})

  defp subject(subject) when is_binary(subject) and subject != "", do: :ok
  defp subject(_subject), do: {:error, :no_subject}

  defp claims(actors, scopes) do
    with :ok <- well_formed(actors, scopes),
         {:ok, held} <- held(actors),
         {:ok, scp} <- scoped(held, scopes) do
      {:ok, held |> Map.keys() |> Enum.sort(), scp}
    end
  end

  # A list of roles and a map of scopes to a value or a list of values, from a page's form or
  # the terminal's JSON.
  defp well_formed(actors, scopes) do
    if is_list(actors) and Enum.all?(actors, &is_binary/1) and is_map(scopes) and
         Enum.all?(scopes, fn {scope, value} -> is_binary(scope) and value_shape?(value) end),
       do: :ok,
       else: {:error, :malformed}
  end

  defp value_shape?(value) when is_binary(value), do: true
  defp value_shape?(values) when is_list(values), do: Enum.all?(values, &is_binary/1)
  defp value_shape?(_value), do: false

  # capability => scope, for the union of the actors' capabilities.
  defp held(actors) do
    granted = granted()

    case Enum.reject(actors, &Map.has_key?(granted, &1)) do
      [] -> {:ok, actors |> Enum.map(&Map.fetch!(granted, &1)) |> Enum.reduce(%{}, &Map.merge/2)}
      unknown -> {:error, {:unknown_actors, Enum.sort(unknown)}}
    end
  end

  defp scoped(held, scopes) do
    dimensions = held |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case Enum.reject(dimensions, &value?(Map.get(scopes, &1))) do
      [] ->
        {:ok,
         for {capability, dimension} <- held, dimension != nil, into: %{} do
           {capability, %{dimension => List.wrap(Map.fetch!(scopes, dimension))}}
         end}

      missing ->
        {:error, {:missing_scopes, Enum.sort(missing)}}
    end
  end

  defp value?(value) when is_binary(value), do: value != ""
  defp value?([_ | _] = values), do: Enum.all?(values, &(is_binary(&1) and &1 != ""))
  defp value?(_value), do: false

  @doc false
  # Called by the renewal for a session whose sign-in child is the mode's process, and by
  # nothing else: a new credential with the claims of the session's own, which must be signed
  # by this process's key and be the session's person's. `{:error, :not_renewable}` otherwise,
  # and `{:error, :not_started}` where the mode has not started, which makes no key.
  @spec renew(atom(), String.t(), String.t() | nil) ::
          {:ok, String.t(), DateTime.t()} | {:error, :not_renewable | :not_started}
  def renew(name, subject, token) do
    cond do
      not started?(name) -> {:error, :not_started}
      not is_binary(token) -> {:error, :not_renewable}
      true -> call({:renew, subject, token, EhOsContract.Clock.now()}, name)
    end
  end

  defp call(request, name \\ SignIn) do
    GenServer.call(name, request)
  catch
    :exit, _not_running -> {:error, :not_started}
  end

  @impl GenServer
  def init(opts) do
    # Again in the process that will hold the key: nothing below runs where it is refused.
    :ok = refuse!()
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, private} = JOSE.JWK.to_map(jwk)
    {_, public} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    :ets.new(SignIn, [:named_table, :protected, :set, read_concurrency: true])
    true = :ets.insert(SignIn, {:config, sign_in_config(opts)})
    :ets.new(@marker, [:named_table, :protected, :set, read_concurrency: true])
    true = :ets.insert(@marker, {:mode, %{pid: self(), public: public, token_hash: hash(token)}})

    kid = Keys.pin(public)
    announce(opts[:url], token)
    {:ok, %{private: private, public: public, kid: kid, keys: Process.monitor(Keys)}}
  end

  # A crash report prints a process's state: the private key is never in it.
  @impl GenServer
  def format_status(status), do: Map.update(status, :state, nil, &Map.delete(&1, :private))

  # The key is pinned in the `Keys` process only, and one that restarts has lost it: the mode
  # pins it again there, so its sessions go on and the host's supervisor counts one restart.
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _keys, _reason}, %{keys: ref} = state),
    do: {:noreply, state, {:continue, :pin_again}}

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_continue(:pin_again, state) do
    case wait_for_keys(50) do
      :ok ->
        ref = Process.monitor(Keys)
        Keys.pin(state.public)
        {:noreply, %{state | keys: ref}}

      :gone ->
        {:stop, :keys_not_restarted, state}
    end
  end

  # At most 5 seconds, by 100 ms: its supervisor starts the `Keys` process again.
  defp wait_for_keys(0), do: :gone

  defp wait_for_keys(tries) do
    if Process.whereis(Keys) do
      :ok
    else
      Process.sleep(100)
      wait_for_keys(tries - 1)
    end
  end

  # What `SignIn.config/1` answers for the sign-in this process stands in for. The secret its
  # sessions are encrypted with is made at each start, so a restart ends them.
  defp sign_in_config(opts) do
    secret_key_base = 64 |> :crypto.strong_rand_bytes() |> Base.encode64()
    address = opts[:url] || @placeholder_address
    # Where `SignIn.Router`'s sign-out sends the browser: there is no EHOS to sign out at.
    signed_out = (opts[:url] || "") <> "/"

    %SignIn{
      name: SignIn,
      issuer: Application.fetch_env!(:eh_os_contract_auth, :issuer),
      client_id: "eh-os-contract-auth-development",
      client_key: JOSE.JWK.generate_key({:okp, :Ed25519}),
      address: address,
      redirect_uri: address <> @path,
      post_logout_redirect_uri: signed_out,
      applications: %{},
      secret_key_base: secret_key_base,
      cipher_key: Cipher.key(secret_key_base),
      client_secret: nil,
      request_opts: %{timeout: 10_000, http_adapter: {Http, %{}}},
      absolute_limit: 12 * 60 * 60
    }
  end

  defp announce(url, token) do
    page = (url || "") <> @path <> "?token=" <> token

    IO.puts("""

    [eh_os_contract_auth] Development sign-in, with a key made at this start:
        #{if url, do: page, else: page <> " on this application's address"}
      A credential for curl, with the token in the environment rather than the command:
        export EH_OS_CONTRACT_DEV_TOKEN=#{token}
        mix eh_os_contract.dev.credential --actor <role>
    """)
  end

  @impl GenServer
  def handle_call({:sign, subject, capabilities, scp, now}, _from, state),
    do: {:reply, sign(subject, capabilities, scp, now, state), state}

  def handle_call({:renew, subject, token, now}, _from, state) do
    reply =
      case JOSE.JWT.verify_strict(JOSE.JWK.from_map(state.public), ["Ed25519"], token) do
        {true, %JOSE.JWT{fields: %{"sub" => ^subject} = fields},
         %JOSE.JWS{fields: %{"kid" => kid}}}
        when kid == state.kid ->
          sign(subject, Map.get(fields, "cap", []), Map.get(fields, "scp", %{}), now, state)

        _other ->
          {:error, :not_renewable}
      end

    {:reply, reply, state}
  rescue
    _not_a_jwt -> {:reply, {:error, :not_renewable}, state}
  end

  # `SignIn.refresh/2`, which only a renewal through EHOS asks for: there is no EHOS here.
  def handle_call(:refresh, _from, state), do: {:reply, {:error, :ehos_unavailable}, state}

  defp sign(subject, capabilities, scopes, now, state) do
    {token, expires_at} =
      Signing.credential(state.private, state.kid, subject, capabilities, scopes, now)

    {:ok, token, expires_at}
  end

  defp hash(token), do: :crypto.hash(:sha256, token)
end
