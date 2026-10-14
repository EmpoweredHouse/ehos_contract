defmodule GraphLab.Processes.TillDay do
  @moduledoc """
  **Added to the test set to test the graph on; not client material** (`GraphLab`).

  Reception's till from its opening to its close: a process whose every event is one
  contract's, `GraphLab.Contracts.Till`, with a promise and a deadline.
  """

  use EhOsContract.Process,
    id: "graph-lab.till_day",
    domain: GraphLab.Domain,
    label: "Dzień kasowy recepcji",
    accountable: :manager

  correlate :day_id

  stage :opening, include: [{GraphLab.Contracts.Till, :day_opened}]
  stage :counting, include: [{GraphLab.Contracts.Till, :cash_counted}]
  stage :closing, include: [{GraphLab.Contracts.Till, :day_closed}]

  ends_on :day_closed

  promise :closed_the_same_day do
    from :day_opened
    eventually :day_closed
    within {16, :hour}
    source "dodane do testów grafu"
  end

  deadline {2, :day}

  scenario "kasa otwarta rano, zamknięta wieczorem — termin dotrzymany",
    verdict: :satisfied,
    via: :eventually do
    given :day_opened, %{day_id: "2026-09-07"}, at: "2026-09-07T08:00:00+02:00"

    given :cash_counted, %{day_id: "2026-09-07", counted: 120_000},
      at: "2026-09-07T19:00:00+02:00"

    given :day_closed, %{day_id: "2026-09-07", counted: 120_000}, at: "2026-09-07T19:10:00+02:00"
    promise :closed_the_same_day, at: "2026-09-08T08:00:00+02:00"
  end

  scenario "kasa niezamknięta do rana — termin przekroczony", verdict: :violated do
    given :day_opened, %{day_id: "2026-09-07"}, at: "2026-09-07T08:00:00+02:00"
    promise :closed_the_same_day, at: "2026-09-08T08:00:00+02:00"
  end
end
