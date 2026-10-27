defmodule EhOsContract.Auth.MailSenderTest do
  @moduledoc """
  #477: who sends the application's mail where EHOS does not, as #475 chose who answers
  about people and grants, and the choice read at each call.

  Not async: the choice is `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  require Logger

  import ExUnit.CaptureLog
  import EhOsContract.Auth.Testing, only: [stub_mail: 1]

  alias EhOsContract.Auth.Mail
  alias EhOsContract.Auth.Mail.{Local, Result, Sender, Unconfigured}
  alias EhOsContract.Auth.Testing

  @ada "6f1c0a1e-0000-4000-8000-000000000001"
  @message [
    to: [{:person, @ada}, {:address, "alan@example.com"}],
    subject: "A document waits for Ada Lovelace",
    text: "Open it at https://office.example.org/d/42."
  ]

  setup do
    previous = Application.get_all_env(:eh_os_contract_auth)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
          not Keyword.has_key?(previous, key),
          do: Application.delete_env(:eh_os_contract_auth, key)

      Application.put_all_env(eh_os_contract_auth: previous)
    end)

    for key <- [:mail_sender, :workload, :people],
        do: Application.delete_env(:eh_os_contract_auth, key)

    :ok
  end

  describe "the choice" do
    test "EHOS's when the workload is configured, the unconfigured one when not" do
      assert Mail.sender() == Unconfigured

      Application.put_env(:eh_os_contract_auth, :workload, client_id: "x")
      assert Mail.sender() == Mail

      Application.delete_env(:eh_os_contract_auth, :workload)
      Application.put_env(:eh_os_contract_auth, :people, client_id: "x")
      assert Mail.sender() == Mail
    end

    test "the configured one, read at each call" do
      Application.put_env(:eh_os_contract_auth, :mail_sender, Local)
      assert Mail.sender() == Local

      Application.put_env(:eh_os_contract_auth, :workload, client_id: "x")
      Application.put_env(:eh_os_contract_auth, :mail_sender, Unconfigured)
      assert Mail.sender() == Unconfigured
    end

    test "a stand-in where the workload is configured raises, as a release answering for EHOS" do
      Application.put_env(:eh_os_contract_auth, :workload, client_id: "x")

      for sender <- [Local, Testing.Mail] do
        Application.put_env(:eh_os_contract_auth, :mail_sender, sender)
        assert_raise ArgumentError, ~r/a stand-in for development or tests/, &Mail.sender/0
      end
    end

    test "anything but a module of the behaviour raises" do
      for value <- ["Local", false, NoSuchModule, EhOsContract.Auth.Grants.Local] do
        Application.put_env(:eh_os_contract_auth, :mail_sender, value)
        assert_raise ArgumentError, ~r/mail_sender:/, &Mail.sender/0
      end
    end
  end

  test "the unconfigured one answers :unavailable, never sent" do
    assert Unconfigured.deliver(@message) == {:error, :unavailable}
  end

  describe "Local" do
    test "answers each recipient as taken, in order, and logs no recipient or subject" do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log([level: :info], fn ->
          assert {:ok, [%Result{} = ada, %Result{} = alan]} = Local.deliver(@message)
          send(self(), {:results, ada, alan})
        end)

      assert_received {:results, ada, alan}
      assert %Result{to: {:person, @ada}, sent?: true, reason: nil} = ada
      assert %Result{to: {:address, "alan@example.com"}, sent?: true} = alan
      assert ada.message_id =~ ~r/\A<[0-9a-f]{32}@local\.invalid>\z/
      assert ada.message_id != alan.message_id

      assert log =~ "sent nothing"
      assert log =~ ada.message_id
      refute log =~ @ada
      refute log =~ "alan"
      refute log =~ "Lovelace"
    end

    test "raises where EHOS's raises, so development fails where a release would" do
      for message <- [
            Keyword.delete(@message, :subject),
            [{:cc, ["x"]} | @message],
            Keyword.put(@message, :to, [{:phone, "1"}]),
            @message ++ [subject: "twice"]
          ] do
        assert_raise ArgumentError, ~r/deliver\/1 takes/, fn -> Local.deliver(message) end
      end
    end
  end

  describe "the tests' stand-in" do
    test "tells the test each message, and answers every one as taken until told otherwise" do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log([level: :info], fn ->
          assert {:ok, [%Result{sent?: true} = ada, %Result{sent?: true}]} =
                   Testing.Mail.deliver([{:server, :ignored} | @message])

          assert ada.message_id =~ ~r/\A<[0-9a-f]{32}@local\.invalid>\z/
        end)

      assert log == ""

      assert_received {:ehos_mail, message}
      assert message == @message

      stub_mail({:error, :not_agreed})
      assert Testing.Mail.deliver(@message) == {:error, :not_agreed}
      assert_received {:ehos_mail, _message}

      stub_mail({:error, {:beyond_agreement, ["to[1]: an address the agreement does not allow"]}})
      assert {:error, {:beyond_agreement, [_reason]}} = Testing.Mail.deliver(@message)
    end

    @tag capture_log: true
    test "a message from a process the test started comes to the test" do
      stub_mail({:error, :mail_disabled})

      task = Task.async(fn -> Testing.Mail.deliver(@message) end)
      assert Task.await(task) == {:error, :mail_disabled}
      assert_received {:ehos_mail, _message}
    end

    @tag capture_log: true
    test "a message from a server the test did not start goes nowhere, not into its mailbox" do
      test = self()

      :proc_lib.spawn(fn ->
        {:ok, _results} = Testing.Mail.deliver(@message)

        receive do
          {:ehos_mail, _message} -> send(test, :kept)
        after
          0 -> send(test, :not_kept)
        end
      end)

      assert_receive :not_kept
      refute_received {:ehos_mail, _message}
    end

    test "a stub no call could answer is refused when it is made" do
      for stub <- [{:error}, {:error, "unavailable"}, {:error, {:invalid, "x"}}, :made] do
        assert_raise FunctionClauseError, fn -> stub_mail(stub) end
      end
    end

    test "answers only where test keys may be pinned" do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)
      assert_raise ArgumentError, ~r/for tests only/, fn -> Testing.Mail.deliver(@message) end
      refute_received {:ehos_mail, _message}
    end
  end

  describe "the callback's types" do
    @tag capture_log: true
    test "each stand-in answers within them, as a host's Hammox mock would check" do
      stub_mail({:error, {:invalid, ["the message is larger than EHOS reads"]}})

      for sender <- [Local, Unconfigured, Testing.Mail] do
        %{deliver_1: deliver} = Hammox.protect(sender, Sender, deliver: 1)
        deliver.(@message)
      end
    end

    test "a reason outside them is caught" do
      stub_mail({:error, :timeout})
      %{deliver_1: deliver} = Hammox.protect(Testing.Mail, Sender, deliver: 1)
      assert_raise Hammox.TypeMatchError, fn -> deliver.(@message) end
    end
  end
end
