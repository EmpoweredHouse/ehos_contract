defmodule EhOsContract.Auth.Mail.Local do
  @moduledoc """
  Every message answered as taken and none sent, for development: an
  `EhOsContract.Auth.Mail.Sender` that never calls EHOS and keeps nothing.

      # config/dev.exs
      config :eh_os_contract_auth, mail_sender: EhOsContract.Auth.Mail.Local

  It answers one `EhOsContract.Auth.Mail.Result` per recipient, in the order given, each
  taken by the relay, with a message id of its own, and logs that nothing went out. The
  log names how many recipients there were and their message ids, never a recipient, the
  subject or the body, which may be personal data.

  It takes the options `EhOsContract.Auth.Mail.deliver/1` takes, and raises
  `ArgumentError` for the ones it would raise for, so development fails where a release
  would. What only EHOS checks, an agreement's level or a message's size among it, it
  does not, nor does it remember an `idempotency_key:`: a repeat is answered again.
  """

  @behaviour EhOsContract.Auth.Mail.Sender

  require Logger

  alias EhOsContract.Auth.Mail
  alias EhOsContract.Auth.Mail.Result

  @impl true
  @doc "Sends nothing, and answers each recipient as taken."
  @spec deliver([Mail.option()]) :: {:ok, [Result.t()]}
  def deliver(message) do
    Mail.message!(message)

    results =
      for recipient <- Keyword.fetch!(message, :to) do
        %Result{to: recipient, sent?: true, message_id: message_id()}
      end

    Logger.info(
      "EhOsContract.Auth.Mail.Local sent nothing: a message to #{length(results)} " <>
        "recipient(s) answered as taken, #{Enum.map_join(results, ", ", & &1.message_id)}"
    )

    {:ok, results}
  end

  defp message_id,
    do: "<" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower) <> "@local.invalid>"
end
