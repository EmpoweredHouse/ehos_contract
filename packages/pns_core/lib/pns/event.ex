defmodule PNS.Event do
  @moduledoc """
  The event log (notes §3). Append-only.

  `contract_version` is what keeps the overlay honest: the static graph describes
  the code deployed now, while the log spans every version since the first deploy.
  An event removed last month is legitimate history, not drift. Cheap now,
  impossible to add later.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "pns_events" do
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
  end

  @doc """
  The explicit stand-in for "no human actor" — a scheduled job, a backfill, an
  import — used wherever `PNS.emit`/`emit_all` is called without a `ctx.actor`.

  A nil actor conflates two different facts: "we asked and there genuinely is no
  person" and "nobody supplied one." The second is a caller that forgot, and the
  first should read as a positive statement, not an absence — `actor` never stores
  `nil` for exactly this reason.

  Who the actor is otherwise is the host's business. The engine receives an opaque
  subject string in `ctx.actor` and verifies nothing about it: authentication, roles
  and tenants belong to the application that emits.
  """
  @spec system_actor() :: String.t()
  def system_actor, do: "system"
end

defmodule PNS.EventHandling do
  @moduledoc """
  The outcome of handling belongs to the handler, not to the event (notes §3).

  An event does not fail — the handler processing it does. A status on the event
  would give a dashboard unable to say which handler is broken.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "pns_event_handlings" do
    field(:event_id, :binary_id)
    field(:handler, :string)
    # "Succeeded after three attempts" is a different state from "succeeded", and
    # a flapping handler is a useful signal.
    field(:attempt, :integer, default: 1)
    field(:status, :string)
    field(:duration_us, :integer)
    field(:error, :string)
    field(:inserted_at, :utc_datetime_usec)
  end
end
