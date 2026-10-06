defmodule ProcessShapes.Timed do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  A timed run (v2 plan, E7c). A run starts, is acknowledged, and ends, and the
  process promises it takes an hour: the confirmed `deadline`, and the terminal
  event it is measured to.

  The acknowledgement is a policy inside the transaction and does not end the run: a
  run that ended as it started could never be open past its hour.
  """

  use EhOsContract.Contract,
    domain: ProcessShapes.Domain,
    context: :timing,
    id: "process_shapes.timed"

  aggregate :timed, "Timed run" do
    identity :run_id

    command :start_run, "Start a run", by: :run_owner, emits: :run_started
    command :acknowledge_run, "Acknowledge a run", emits: :run_acknowledged
    command :finish_run, "Finish a run", by: :run_owner, emits: :run_finished

    stage :opening do
      event :run_started, "Run started"
      event :run_acknowledged, "Run acknowledged"
    end

    stage :closing do
      event :run_finished, "Run finished", terminal: true
    end
  end

  policy :acknowledge_start, "Acknowledge a run as it starts",
    handles: :run_started,
    issues: :acknowledge_run

  process :timed_run, "Timed run" do
    correlate :run_id
    accountable :run_owner

    stage :opening
    stage :closing

    deadline {1, :hour}
  end
end

defmodule ProcessShapes.TimedRun do
  @moduledoc "The decider of `ProcessShapes.Timed`'s run."

  use ProcessShapes.Timed, aggregate: :timed

  @impl true
  def start_run(%StartRun{run_id: id}, _state), do: emit(%RunStarted{run_id: id})

  @impl true
  def acknowledge_run(%AcknowledgeRun{run_id: id}, _state),
    do: emit(%RunAcknowledged{run_id: id})

  @impl true
  def finish_run(%FinishRun{run_id: id}, _state), do: emit(%RunFinished{run_id: id})
end

defmodule ProcessShapes.AcknowledgeStart do
  @moduledoc "Acknowledges the start. One declared path, taken by every run."

  use ProcessShapes.Timed, policy: :acknowledge_start

  @impl true
  def run_started(%RunStarted{run_id: id}), do: issue(%AcknowledgeRun{run_id: id})
end
