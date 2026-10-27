defmodule EhOsContract.Auth.Mail.Unconfigured do
  @moduledoc """
  The `EhOsContract.Auth.Mail.Sender` of a release started without EHOS's credentials,
  and `EhOsContract.Auth.Mail.sender/0`'s answer there: every call answers
  `{:error, :unavailable}`, nothing was sent and the call may be made again, so the
  application never says a message went when none did.
  """

  @behaviour EhOsContract.Auth.Mail.Sender

  @impl true
  @doc "`{:error, :unavailable}`."
  @spec deliver(term()) :: {:error, :unavailable}
  def deliver(_message), do: {:error, :unavailable}
end
