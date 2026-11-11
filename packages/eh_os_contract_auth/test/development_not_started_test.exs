defmodule EhOsContract.Auth.DevelopmentNotStartedTest do
  # The development mode in `mix test`, where it never starts: what each part of it answers
  # there, and what the terminal's command refuses before it asks anything.
  use ExUnit.Case, async: true

  alias EhOsContract.Auth.{Development, SignIn}
  alias EhOsContract.Auth.Development.{Credential, Guard}

  test "without the switch, the child starts nothing" do
    assert Application.get_env(:eh_os_contract_auth, :development) == nil
    assert Development.start_link([]) == :ignore
    assert :ets.whereis(Development) == :undefined
  end

  test "where the mode has not started, it signs nothing, renews nothing, and makes no key" do
    assert Development.sign_in("u-dev", []) == {:error, :not_started}
    assert Development.credential("u-dev", []) == {:error, :not_started}
    assert Development.renew(SignIn, "u-dev", "a.b.c") == {:error, :not_started}
    assert Development.sign_in_path(SignIn) == nil
    refute Development.token?("anything")
    refute Development.key?(%{"kty" => "OKP", "crv" => "Ed25519", "x" => "AAAA"})
    assert :ets.whereis(Development) == :undefined
  end

  test "the guard and the endpoint answer 403 where the mode has not started" do
    conn = %{Plug.Test.conn(:get, "/dev/sign-in?token=x") | host: "localhost"}
    assert Guard.check(conn) == {:error, :not_started}
    assert Guard.call(conn, []).status == 403
    assert Credential.call(%{Plug.Test.conn(:post, "/") | host: "localhost"}, []).status == 403
  end

  describe "mix eh_os_contract.dev.credential" do
    test "sends the token only to this computer" do
      for url <- [
            "https://localhost:4000",
            "http://clinic.example:4000",
            "http://user@localhost:4000",
            "http://localhost:4000/elsewhere",
            "http://localhost.example.com"
          ] do
        assert_raise Mix.Error, ~r/the token goes only to this computer/, fn ->
          Mix.Tasks.EhOsContract.Dev.Credential.run(
            ~w(--token t --actor clinic.manager --url #{url})
          )
        end
      end
    end

    test "needs the token and an actor, and a scope as <scope>=<value>" do
      System.delete_env("EH_OS_CONTRACT_DEV_TOKEN")

      assert_raise Mix.Error, ~r/--token <token>/, fn ->
        Mix.Tasks.EhOsContract.Dev.Credential.run(~w(--actor clinic.manager))
      end

      assert_raise Mix.Error, ~r/--actor <domain>.<actor>/, fn ->
        Mix.Tasks.EhOsContract.Dev.Credential.run(~w(--token t))
      end

      assert_raise Mix.Error, ~r/--scope takes <scope>=<value>/, fn ->
        Mix.Tasks.EhOsContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --scope clinic_id)
        )
      end
    end

    test "says when no application answers" do
      assert_raise Mix.Error, ~r/no application answered at http:\/\/127.0.0.1:9/, fn ->
        Mix.Tasks.EhOsContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --url http://127.0.0.1:9)
        )
      end
    end
  end
end
