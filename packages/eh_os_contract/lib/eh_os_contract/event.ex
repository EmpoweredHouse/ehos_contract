defmodule EhOsContract.Event do
  @moduledoc """
  The event log (notes §3). Append-only.

  `contract_version` is what keeps the report honest: the contract describes the
  code deployed now, while the log spans every version since the first deploy.
  An event removed last month is legitimate history, not drift. Cheap now,
  impossible to add later.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "eh_os_contract_events" do
    field(:type, :string)
    field(:contract, :string)
    field(:contract_version, :string)
    # Which run this event belongs to. `correlation_id` answers a different
    # question — "from which command" — and is per request, so a month opened by
    # two commands has two correlations and one run.
    field(:process, :string)
    field(:instance_id, :string)
    field(:correlation_id, :binary_id)
    field(:causation_id, :binary_id)
    field(:payload, :map)
    field(:actor, :string)
    field(:occurred_at, :utc_datetime_usec)

    # The store's columns (v2 §10.3, migration V03). `position` is the order of
    # appends and the table's primary key; `id` stays this schema's primary key, so
    # every lookup by id works as before. Both `position` and `recorded_at` are the
    # database's to assign.
    field(:position, :integer, read_after_writes: true)
    field(:recorded_at, :utc_datetime_usec, read_after_writes: true)
    field(:schema_version, :integer, default: 1)
    field(:stream_id, :string)
    field(:stream_version, :integer)
    field(:tags, {:array, :string}, default: [])
    field(:command_id, :binary_id)
    field(:metadata, :map, default: %{})
  end

  @doc """
  The explicit stand-in for "no human actor" — a scheduled job, a backfill, an
  import — used wherever an event is written without a person behind it.

  A nil actor conflates two different facts: "we asked and there genuinely is no
  person" and "nobody supplied one." The second is a caller that forgot, and the
  first should read as a positive statement, not an absence — `actor` never stores
  `nil` for exactly this reason.

  Who the actor is otherwise is the host's business. The engine receives an opaque
  subject string and verifies nothing about it: authentication, roles and tenants
  belong to the application.
  """
  @spec system_actor() :: String.t()
  def system_actor, do: "system"
end
