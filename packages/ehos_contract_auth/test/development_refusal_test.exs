defmodule EhosContract.Auth.DevelopmentRefusalTest do
  # Each case in a child process of its own, started from the fixture project with the
  # environment the case needs: a `mix test` process always has Mix, a project and `:test`. With
  # the switch set, each case is refused alone, every other condition holding.
  use ExUnit.Case, async: true

  alias EhosContract.Auth.Child

  @start """
  {:ok, _} = Supervisor.start_link([EhosContract.Auth], strategy: :one_for_one)

  try do
    {:ok, _} = EhosContract.Auth.Development.start_link([])
    {:started, EhosContract.Auth.Development.started?(EhosContract.Auth.SignIn)}
  rescue
    error in ArgumentError -> {:refused, Exception.message(error)}
  end
  """

  test "with every condition holding, the mode starts" do
    assert Child.run(@start) == {:started, true}
  end

  # Each refused case: the options of its child, and the one reason the refusal names.
  @cases [
    {":mix not started", [mix: :none], "the :mix application is not started"},
    {":mix started with no project loaded", [mix: :started], "no Mix project is loaded"},
    {"a project with Mix's environment :prod", [env: [{"MIX_ENV", "prod"}]],
     "Mix's environment is :prod, not :dev"},
    {"a project with Mix's environment :test", [env: [{"MIX_ENV", "test"}]],
     "Mix's environment is :test, not :dev"},
    {"RELEASE_NAME set", [env: [{"RELEASE_NAME", "clinic"}]], "RELEASE_NAME is set"},
    {"RELEASE_ROOT set", [env: [{"RELEASE_ROOT", "/app"}]], "RELEASE_ROOT is set"},
    {"EHOS_ISSUER set", [env: [{"EHOS_ISSUER", "https://ehos.test"}]], "EHOS_ISSUER is set"},
    {"EHOS_AUDIENCE set", [env: [{"EHOS_AUDIENCE", "clinic/test"}]], "EHOS_AUDIENCE is set"},
    {"sign_in: configured", [config: [ehos_contract_auth: [sign_in: [client_id: "clinic"]]]],
     "sign_in: is configured"},
    {"workload: configured", [config: [ehos_contract_auth: [workload: [client_id: "clinic"]]]],
     "workload: is configured"},
    {"people: configured", [config: [ehos_contract_auth: [people: [client_id: "clinic"]]]],
     "people: is configured"}
  ]

  for {name, opts, reason} <- @cases do
    test "the mode is refused with #{name} alone" do
      assert {:refused, message} = Child.run(@start, unquote(opts))
      assert message =~ "the development mode refuses to start here"
      assert [only] = Regex.scan(~r/^  \* (.*)$/m, message, capture: :all_but_first)
      assert hd(only) =~ unquote(reason)
    end
  end

  test "pin_keys: true without the switch does not start the mode" do
    body = """
    {EhosContract.Auth.Development.start_link([]), :ets.whereis(EhosContract.Auth.Development)}
    """

    config = [ehos_contract_auth: [development: :unset, pin_keys: true]]
    assert Child.run(body, config: config) == {:ignore, :undefined}
  end

  test "Keys.pin/2 refuses a key where the mode has not started" do
    body = """
    {:ok, _} = Supervisor.start_link([EhosContract.Auth], strategy: :one_for_one)
    {_, public} = JOSE.JWK.generate_key({:okp, :Ed25519}) |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    try do
      EhosContract.Auth.Keys.pin(public)
    rescue
      error in ArgumentError -> {:refused, Exception.message(error)}
    end
    """

    assert {:refused, message} = Child.run(body)
    assert message =~ "pinning a key: for tests only"
  end

  test "where the mode has started, Keys.pin/2 admits no key but the mode's, nor the test's trust" do
    body = """
    {:ok, _} = Supervisor.start_link([EhosContract.Auth, EhosContract.Auth.Development], strategy: :one_for_one)
    {_, public} = JOSE.JWK.generate_key({:okp, :Ed25519}) |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    refused = fn fun ->
      try do
        fun.()
        :admitted
      rescue
        error in ArgumentError -> {:refused, Exception.message(error)}
      end
    end

    %{
      another_key: refused.(fn -> EhosContract.Auth.Keys.pin(public) end),
      test_credential: refused.(fn -> EhosContract.Auth.Testing.credential("u-anna", []) end),
      test_people: refused.(fn -> EhosContract.Auth.Testing.People.list([]) end),
      plug: refused.(fn -> EhosContract.Auth.Keys.check!(url: "https://ehos.test/jwks", plug: fn conn -> conn end) end)
    }
    """

    assert %{
             another_key: {:refused, another_key},
             test_credential: {:refused, test_credential},
             test_people: {:refused, test_people},
             plug: {:refused, plug}
           } = Child.run(body)

    assert another_key =~ "pinning a key: for tests only"
    assert test_credential =~ "pinning a key: for tests only"
    assert test_people =~ "for tests only"
    assert plug =~ "takes plug: only where Mix's environment is :test"
  end
end
