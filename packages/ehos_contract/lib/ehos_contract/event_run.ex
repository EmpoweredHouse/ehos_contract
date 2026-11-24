defmodule EhosContract.EventRun do
  @moduledoc """
  One run an event belongs to: a row of `ehos_contract_event_runs`.

  A process module (`EhosContract.Process`) includes events of the contracts of its
  domain, and each event belongs to a run of every process that includes it: `process`
  is the module's `id:`, and `instance_id` the run's key, made of the values of the
  fields the process correlates on. Every run is a row, so a reader asking for the
  runs of a process reads one table whichever contract decided the events.

  `EhosContract.Store` writes the rows with the events, in the same append, so an
  event cannot be in the log without its runs.
  """

  # The table of v2 §10.3 and §13, decision D7 of the design record.

  use Ecto.Schema

  @primary_key false
  schema "ehos_contract_event_runs" do
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
