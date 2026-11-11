defmodule EhOsContract.Auth.DevelopmentCredentialTaskTest do
  # What the terminal's command refuses before it asks anything. Not async: a test unsets
  # `EH_OS_CONTRACT_DEV_TOKEN`, which the whole node shares.
  use ExUnit.Case, async: false

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

      assert_raise Mix.Error, ~r/EH_OS_CONTRACT_DEV_TOKEN=<token>/, fn ->
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

    test "takes the address with a trailing slash" do
      assert_raise Mix.Error, ~r/no application answered at http:\/\/127.0.0.1:9 /, fn ->
        Mix.Tasks.EhOsContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --url http://127.0.0.1:9/)
        )
      end
    end
  end
end
