defmodule EhOsContract.Auth.Testing.Mail do
  @moduledoc """
  The `EhOsContract.Auth.Mail.Sender` of a host's tests: it sends nothing, tells the test
  each message it was asked to send, and answers as
  `EhOsContract.Auth.Testing.stub_mail/1` asked, every message taken when it asked
  nothing.

      # config/test.exs
      config :eh_os_contract_auth, mail_sender: EhOsContract.Auth.Testing.Mail

      # a test
      assert_received {:ehos_mail, message}
      assert message[:to] == [{:person, person_id}]

  The message is the options `deliver/1` was given, as given, `server:` left out. It goes
  to the test's process, also from a process the test started, a LiveView's or a task's,
  whatever the stub answers.
  """

  @behaviour EhOsContract.Auth.Mail.Sender

  alias EhOsContract.Auth.Mail
  alias EhOsContract.Auth.Mail.{Local, Result}
  alias EhOsContract.Auth.Testing

  @impl true
  @doc "Tells the test the message, and answers as the test asked."
  @spec deliver([Mail.option()]) :: {:ok, [Result.t()]} | {:error, Mail.reason()}
  def deliver(message) do
    answer = Testing.stubbed!(:mail, :sent)
    Mail.message!(message)
    send(Testing.test_process(), {:ehos_mail, Keyword.delete(message, :server)})

    case answer do
      :sent -> Local.deliver(message)
      {:error, reason} -> {:error, reason}
    end
  end
end
