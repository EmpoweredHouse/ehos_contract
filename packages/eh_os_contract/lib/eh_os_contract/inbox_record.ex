defmodule EhOsContract.InboxRecord do
  # A row of `eh_os_contract_inbox`: one event another application published, taken by
  # one inbox (`EhOsContract.Inbox`, D12). `consumer` is the inbox's key, `key` the
  # message's, and `id` what the commands its policies dispatched name as their cause.
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "eh_os_contract_inbox" do
    field(:consumer, :string, primary_key: true)
    field(:key, :string, primary_key: true)
    field(:id, :binary_id)
    field(:message_id, :string)
    field(:received_at, :utc_datetime_usec, read_after_writes: true)
  end
end
