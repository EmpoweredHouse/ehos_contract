defmodule EhOsContract.CommandRecord do
  @moduledoc """
  One row of `eh_os_contract_commands` (v2 §10.3): what became of a command.

  `outcome` is `"accepted"`, `"rejected"` or `"failed"`. An accepted row binds its
  idempotency key and names the positions it appended; a rejected one names the
  invariant; a failed one names where it failed and the exception's module, never
  its message, which may quote a value (v2 §17). The exception itself is re-raised
  to the caller, whose logger sees all of it.

  A command refused by the `EhOsContract.Authorizer` has no row: the row that
  records a refusal belongs to the implementation (D14).
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "eh_os_contract_commands" do
    field(:contract, :string)
    field(:type, :string)
    field(:issued_by, :string)
    field(:idempotency_key, :string)
    field(:causation_event_id, :binary_id)
    field(:correlation_id, :binary_id)
    field(:outcome, :string)
    field(:invariant, :string)
    field(:failed_in, :string)
    field(:error, :string)
    field(:given_types, {:array, :string}, default: [])
    field(:emitted_types, {:array, :string}, default: [])
    field(:first_position, :integer)
    field(:last_position, :integer)
    field(:process, :string)
    field(:instance_id, :string)
    field(:recorded_at, :utc_datetime_usec, read_after_writes: true)
  end
end
