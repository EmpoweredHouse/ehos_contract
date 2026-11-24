defmodule EhosContract.Auth.DevelopmentCredentialTaskTest do
  # What the terminal's command refuses before it asks anything. Not async: a test unsets
  # `EHOS_CONTRACT_DEV_TOKEN`, which the whole node shares.
  use ExUnit.Case, async: false

  alias EhosContract.Auth.Development
  alias Mix.Tasks.EhosContract.Dev.Credential

  # The file the mode writes, in this project's build directory, holding `token` in the page's
  # address at `origin`.
  defp address_file(token, origin \\ "http://localhost:4000") do
    file = Development.address_file()
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "#{origin}/dev/sign-in?token=#{token}\n")
    on_exit(fn -> File.rm(file) end)
  end

  # An application at a loopback port that answers one request with a credential, and sends
  # this process the token the request carried.
  defp application do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
      [_, token] = Regex.run(~r/x-dev-sign-in-token: (\S+)/i, request)
      send(test, {:token, token})
      body = ~s({"credential":"signed"})

      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: " <>
          "#{byte_size(body)}\r\nconnection: close\r\n\r\n" <> body
      )

      :gen_tcp.close(socket)
    end)

    "http://127.0.0.1:#{port}"
  end

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
  end

  describe "mix ehos_contract.dev.credential" do
    test "sends the token only to this computer" do
      for url <- [
            "https://localhost:4000",
            "http://clinic.example:4000",
            "http://user@localhost:4000",
            "http://localhost:4000/elsewhere",
            "http://localhost.example.com"
          ] do
        assert_raise Mix.Error, ~r/the token goes only to this computer/, fn ->
          Mix.Tasks.EhosContract.Dev.Credential.run(
            ~w(--token t --actor clinic.manager --url #{url})
          )
        end
      end
    end

    test "needs the token and an actor, and a scope as <scope>=<value>" do
      System.delete_env("EHOS_CONTRACT_DEV_TOKEN")
      File.rm(Development.address_file())

      assert_raise Mix.Error,
                   ~r/ehos_contract_auth\/dev_sign_in does not hold one.*EHOS_CONTRACT_DEV_TOKEN=<token>/,
                   fn ->
                     Mix.Tasks.EhosContract.Dev.Credential.run(~w(--actor clinic.manager))
                   end

      assert_raise Mix.Error, ~r/--actor <domain>.<actor>/, fn ->
        Mix.Tasks.EhosContract.Dev.Credential.run(~w(--token t))
      end

      assert_raise Mix.Error, ~r/--scope takes <scope>=<value>/, fn ->
        Mix.Tasks.EhosContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --scope clinic_id)
        )
      end
    end

    test "without the variable, reads the token from the file the running application writes" do
      System.delete_env("EHOS_CONTRACT_DEV_TOKEN")
      address_file("from-the-file")

      Credential.run(~w(--actor clinic.manager --url #{application()}))

      assert_receive {:token, "from-the-file"}
      assert_received {:mix_shell, :info, ["signed"]}
    end

    test "without --url, sends the token from the file to the address in the file" do
      System.delete_env("EHOS_CONTRACT_DEV_TOKEN")
      address_file("from-the-file", application())

      Credential.run(~w(--actor clinic.manager))

      assert_receive {:token, "from-the-file"}
    end

    test "does not send the token to an address in the file it would refuse, but to the default" do
      System.delete_env("EHOS_CONTRACT_DEV_TOKEN")

      for origin <- ["http://clinic.example:4000", "https://localhost:4001"] do
        address_file("from-the-file", origin)

        error =
          assert_raise Mix.Error, fn ->
            Credential.run(~w(--actor clinic.manager --scope clinic_id))
          end

        refute error.message =~ "--url takes"
        assert error.message =~ "--scope takes"
      end
    end

    test "takes the variable before the file, and refuses a file without a token" do
      address_file("from-the-file")
      System.put_env("EHOS_CONTRACT_DEV_TOKEN", "from-the-variable")
      on_exit(fn -> System.delete_env("EHOS_CONTRACT_DEV_TOKEN") end)

      Credential.run(~w(--actor clinic.manager --url #{application()}))
      assert_receive {:token, "from-the-variable"}

      System.delete_env("EHOS_CONTRACT_DEV_TOKEN")
      File.write!(Development.address_file(), "/dev/sign-in\n")

      assert_raise Mix.Error, ~r/does not hold one/, fn ->
        Credential.run(~w(--actor clinic.manager --url http://127.0.0.1:9))
      end
    end

    test "says when no application answers" do
      assert_raise Mix.Error, ~r/no application answered at http:\/\/127.0.0.1:9/, fn ->
        Mix.Tasks.EhosContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --url http://127.0.0.1:9)
        )
      end
    end

    test "takes the address with a trailing slash" do
      assert_raise Mix.Error, ~r/no application answered at http:\/\/127.0.0.1:9 /, fn ->
        Mix.Tasks.EhosContract.Dev.Credential.run(
          ~w(--token t --actor clinic.manager --url http://127.0.0.1:9/)
        )
      end
    end
  end
end
