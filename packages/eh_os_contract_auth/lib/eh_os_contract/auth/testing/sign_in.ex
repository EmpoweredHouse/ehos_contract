defmodule EhOsContract.Auth.Testing.SignIn do
  @moduledoc false

  # A sign-in child for a host's tests, started by `EhOsContract.Auth.Testing.sign_in/3` under the
  # name `EhOsContract.Auth.SignIn` takes when none runs there. It holds what `SignIn.config/1`
  # answers and nothing of EHOS's: no discovery document and no keys, so it never calls EHOS, and
  # a renewal through it answers `:ehos_unavailable`. One per test run, like the test key: it is
  # started outside the test's supervisor, since its name is the application's and an async test
  # beside it would ask for it too.

  use GenServer

  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.{Cipher, Http}

  @placeholder_address "https://application.test"

  @doc false
  # Starts the stub under `name`, unless something already runs there; either way, `name` answers
  # `SignIn.config/1` when this returns.
  @spec ensure_started(atom()) :: :ok
  def ensure_started(name) do
    if Process.whereis(name) do
      :ok
    else
      case GenServer.start(__MODULE__, name, name: name) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end

  @impl GenServer
  def init(name) do
    sign_in = Application.get_env(:eh_os_contract_auth, :sign_in, [])
    sign_in = if Keyword.keyword?(sign_in), do: sign_in, else: []
    address = Keyword.get(sign_in, :address) || @placeholder_address
    secret_key_base = 64 |> :crypto.strong_rand_bytes() |> Base.encode64()

    config = %SignIn{
      name: name,
      issuer: Application.get_env(:eh_os_contract_auth, :issuer, "https://ehos.test"),
      client_id: "eh-os-contract-auth-test",
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
end
