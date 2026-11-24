defmodule EhosContract.Auth.Testing.SignIn do
  @moduledoc false

  # A sign-in child for a host's tests, started by `EhosContract.Auth.Testing.sign_in/3` under the
  # name `EhosContract.Auth.SignIn` takes when none runs there. It holds what `SignIn.config/1`
  # answers and nothing of EHOS's: no discovery document and no keys, so it never calls EHOS, and
  # a renewal through it answers `:ehos_unavailable`. One per test run, like the test key: it is
  # started outside the test's supervisor, since its name is the application's and an async test
  # beside it would ask for it too.

  use GenServer

  alias EhosContract.Auth.{Keys, SignIn}
  alias EhosContract.Auth.SignIn.{Cipher, Http}

  @placeholder_address "https://application.test"

  @doc false
  # Starts the stand-in under `name`, unless something already runs there; either way, `name`
  # answers `SignIn.config/1` when this returns. Only where test keys may be pinned.
  @spec ensure_started(atom()) :: :ok
  def ensure_started(name) do
    :ok = Keys.test_only!("a stand-in for EhosContract.Auth.SignIn")

    # A name is registered before `init/1` has made its table, so a test that finds it taken by a
    # stand-in still starting waits for it: a call is answered only once `init/1` has returned.
    if Process.whereis(name) do
      if :ets.whereis(name) == :undefined, do: :sys.get_state(name)
      :ok
    else
      case GenServer.start(__MODULE__, name, name: name) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, pid}} ->
          _state = :sys.get_state(pid)
          :ok
      end
    end
  end

  @impl GenServer
  def init(name) do
    sign_in = Application.get_env(:ehos_contract_auth, :sign_in, [])
    sign_in = if Keyword.keyword?(sign_in), do: sign_in, else: []
    address = Keyword.get(sign_in, :address) || @placeholder_address
    secret_key_base = 64 |> :crypto.strong_rand_bytes() |> Base.encode64()

    config = %SignIn{
      name: name,
      issuer: Application.fetch_env!(:ehos_contract_auth, :issuer),
      client_id: "ehos-contract-auth-test",
      client_key: JOSE.JWK.generate_key({:okp, :Ed25519}),
      address: address,
      redirect_uri: address <> "/auth/ehos/callback",
      post_logout_redirect_uri: address <> "/",
      applications: Keyword.get(sign_in, :applications) || %{},
      secret_key_base: secret_key_base,
      cipher_key: Cipher.key(secret_key_base),
      client_secret: nil,
      request_opts: %{timeout: 10_000, http_adapter: {Http, %{}}},
      absolute_limit: 12 * 60 * 60
    }

    :ets.new(name, [:named_table, :protected, :set, read_concurrency: true])
    true = :ets.insert(name, {:config, config})
    {:ok, name}
  end

  # `SignIn.refresh/2` asked of the stand-in: there is no EHOS to fetch from, and the stand-in
  # stays, with the key every session written so far is sealed with.
  @impl GenServer
  def handle_call(:refresh, _from, name), do: {:reply, {:error, :ehos_unavailable}, name}
end
