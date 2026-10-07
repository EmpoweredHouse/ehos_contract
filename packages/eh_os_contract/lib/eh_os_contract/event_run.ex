defmodule EhOsContract.EventRun do
  @moduledoc """
  One run an event belongs to: a row of `eh_os_contract_event_runs`.

  An event's home run is the process of the contract that decided it, and the
  event's own `process` and `instance_id` say which. A contract may also `include`
  a sibling's event in its own process, and then the event belongs to that run too,
  keyed by that process's correlation. Every run is a row, the home run included, so
  a reader asking for the runs of a process reads one table whichever contract decided
  the events.

  `EhOsContract.Store` writes the rows with the events, in the same append, so an
  event cannot be in the log without its runs.
  """

  # The table of v2 §10.3 and §13, decision D7 of the design record.

  use Ecto.Schema

  @primary_key false
  schema "eh_os_contract_event_runs" do
    field :position, :integer, primary_key: true
    field :process, :string, primary_key: true
    field :instance_id, :string
  end

  @typedoc "One run of one event."
  @type t :: %__MODULE__{
          position: pos_integer(),
          process: String.t(),
          instance_id: String.t()
        }
end
