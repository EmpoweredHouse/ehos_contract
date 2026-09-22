defmodule ProcessShapes.Timed do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes.Rig`.

  **The shape of a process that promises how long it takes.**

  A run starts, is acknowledged, and ends. The process declares `deadline: {1, :hour}`
  and the ending is declared `terminal: true`, which together are the two halves the
  duration aggregate needs: the log supplies the start, the terminal event supplies
  the end, and the declaration supplies what was agreed.

  ## Why a fifth fixture rather than confirming a deadline that already exists

  Every `deadline:` in this repository is `unverified` — `ProcessShapes.Promised`'s,
  `UniversalityGate.TreatmentEpisode`'s and TaxVision's alike — and the aggregate
  deliberately skips unconfirmed declarations, so none of them can exercise it.

  Confirming `Promised`'s would have been the cheap route and it would have broken
  the sharpest test in `report_test.exs`. That fixture's unconfirmed deadline is the
  reason the fixture exists: a report that must be able to leave a declaration out
  cannot be shown to do so by a contract with nothing to leave out. Confirming it
  turns that acceptance criterion into a tautology.

  A fifth fixture is a real cost — registry counts, `pns.check` output, anything
  that iterates contracts — and it is paid here rather than paid by weakening a
  test that already earns its keep.

  ## One hour, not one day

  The window has to be short enough that a test can place a run on either side of
  it without arithmetic, and long enough to read as a promise rather than as a
  timeout. `PNS.Duration` supports hours; nothing else in the repository uses one,
  which makes this fixture the only cover for that unit in a `deadline`.
  """

  use PNS.Contract

  event :run_started,
    label: "Run started",
    owner: ProcessShapes.Timed,
    # Arrives from outside, so it carries the run identity on its own.
    payload: %{run_id: :id},
    process: :timed_run,
    stage: :opening

  event :run_acknowledged,
    label: "Run acknowledged",
    owner: ProcessShapes.Timed,
    payload: %{run_id: :id},
    process: :timed_run,
    stage: :opening

  event :run_finished,
    label: "Run finished",
    owner: ProcessShapes.Timed,
    payload: %{run_id: :id},
    process: :timed_run,
    stage: :closing,
    # The half of this fixture the aggregate actually reads. Without it a run has
    # no observable end and the whole question is unanswerable — which is its own
    # finding, and `mix pns.check` reports it.
    terminal: true

  process :timed_run,
    label: "Timed run",
    stages: [:opening, :closing],
    instance: [:run_id],
    # Confirmed, in the fiction of this fixture — and it is the only confirmed
    # `deadline` in the repository, which is the entire reason this file exists.
    deadline: {1, :hour}
end

defmodule ProcessShapes.Timed.OnRunStarted do
  @moduledoc """
  Acknowledges the start. One declared path, taken by every run.

  Synchronous, and it does **not** publish the ending. A handler that finished the
  run would make every run finish in the same instant it started, so the fixture
  could never hold a run that is still open — and an open run past its deadline is
  the case the aggregate exists to separate from a breach.
  """

  use PNS.Handler,
    contract: ProcessShapes.Timed,
    event: :run_started,
    publishes: [:run_acknowledged]

  @impl PNS.Handler
  def handle(%{run_id: id}, _ctx), do: {:ok, [PNS.event(:run_acknowledged, %{run_id: id})]}
end
