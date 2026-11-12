defmodule EhOsContract.Auth.PinKeysRefusalTest do
  # Each case in a child process of its own, started from the fixture project with Mix's
  # environment `:test` and `pin_keys: true`: a `mix test` process cannot unset what it runs
  # under. Each sign of a release or of a container EHOS started is refused alone, whatever Mix's
  # environment is (#620).
  use ExUnit.Case, async: true

  alias EhOsContract.Auth.Child

  @body """
  attempt = fn fun ->
    try do
      fun.()
      :admitted
    rescue
      error in ArgumentError -> {:refused, Exception.message(error)}
    end
  end

  {_, public} = JOSE.JWK.generate_key({:okp, :Ed25519}) |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

  %{
    trust: EhOsContract.Auth.Keys.test_trust?(),
    boot: attempt.(fn -> Supervisor.start_link([EhOsContract.Auth], strategy: :one_for_one) end),
    pin: attempt.(fn -> EhOsContract.Auth.Keys.pin(public) end),
    plug: attempt.(fn -> EhOsContract.Auth.Keys.check!(url: "https://ehos.test/jwks", plug: fn conn -> conn end) end)
  }
  """

  @config [eh_os_contract_auth: [development: :unset, pin_keys: true]]

  defp run(opts) do
    {env, opts} = Keyword.pop(opts, :env, [])
    {config, []} = Keyword.pop(opts, :config, [])
    config = Keyword.merge(@config, config, fn _app, a, b -> Keyword.merge(a, b) end)
    Child.run(@body, env: [{"MIX_ENV", "test"} | env], config: config)
  end

  test "where a test runs, pin_keys: true trusts a pinned key and a plug" do
    assert run([]) == %{trust: true, boot: :admitted, pin: :admitted, plug: :admitted}
  end

  # What a test configures to test what reads it, and the development mode refuses on, does not
  # refuse a test.
  test "sign_in: configured in a test does not refuse pin_keys: true" do
    config = [eh_os_contract_auth: [sign_in: [client_id: "clinic"]]]
    assert %{trust: true, boot: :admitted, pin: :admitted} = run(config: config)
  end

  @cases [
    {"RELEASE_NAME", "clinic", "RELEASE_NAME is set, as it is in a release"},
    {"RELEASE_ROOT", "/app", "RELEASE_ROOT is set, as it is in a release"},
    {"EHOS_ISSUER", "https://ehos.test", "EHOS_ISSUER is set, as EHOS sets it"},
    {"EHOS_AUDIENCE", "clinic/test", "EHOS_AUDIENCE is set, as EHOS sets it"}
  ]

  for {variable, value, reason} <- @cases do
    test "pin_keys: true is refused with #{variable} set alone, though Mix's environment is :test" do
      assert %{trust: false, boot: {:refused, boot}, pin: {:refused, pin}, plug: {:refused, plug}} =
               run(env: [{unquote(variable), unquote(value)}])

      assert [_, only] = Regex.run(~r/where no test runs: (.*?)\. The line/, boot)
      assert only =~ unquote(reason)
      refute only =~ "; "
      assert pin =~ "pinning a key: for tests only"
      assert plug =~ "pin_keys: true is set where no test runs"
    end
  end
end
