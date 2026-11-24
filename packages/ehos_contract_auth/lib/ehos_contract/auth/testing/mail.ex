defmodule EhosContract.Auth.Testing.Mail do
  @moduledoc """
  The `EhosContract.Auth.Mail.Sender` of a host's tests: it sends nothing, tells the test
  each message it was asked to send, and answers as
  `EhosContract.Auth.Testing.stub_mail/1` asked, every message taken when it asked
  nothing.

      # config/test.exs
      config :ehos_contract_auth, mail_sender: EhosContract.Auth.Testing.Mail

      # a test
      assert_received {:ehos_mail, message}
      assert message[:to] == [{:person, person_id}]

  The message is the options `deliver/1` was given, as given, `server:` left out. It goes
  to the test's process, also from a process the test started, a LiveView's or a task's,
  whatever the stub answers. A message from a server the test did not start, which names
  no test among its `$callers`, goes nowhere: it is answered, and not told.
  """

  @behaviour EhosContract.Auth.Mail.Sender

  alias EhosContract.Auth.Mail
  alias EhosContract.Auth.Mail.Result
  alias EhosContract.Auth.Testing

  @impl true
  @doc "Tells the test the message, and answers as the test asked."
  @spec deliver([Mail.option()]) :: {:ok, [Result.t()]} | {:error, Mail.reason()}
  def deliver(message) do
    answer = Testing.stubbed!(:mail, :sent)
    Mail.message!(message)

    if test = Testing.test_process(),
      do: send(test, {:ehos_mail, Keyword.delete(message, :server)})

    case answer do
      :sent -> {:ok, Enum.map(Keyword.fetch!(message, :to), &taken/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  # As `EhosContract.Auth.Mail.Local` answers, without its log: the test is told instead.
  defp taken(recipient) do
    id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    %Result{to: recipient, sent?: true, message_id: "<#{id}@local.invalid>"}
  end
end
