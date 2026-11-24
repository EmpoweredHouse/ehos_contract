defmodule PhaseRig.Visits do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A visit is booked, moved and closed, and may be booked again. A policy reminds on a
  booking and on a move — one command, two triggering events. A process manager notes
  a booking whether it starts the visit's run or comes during it, notes a move, and
  ends on the close; a close with no run open starts one and ends it at once.
  """

  use EhosContract.Contract, id: "phase_rig.visits", domain: PhaseRig.Domain, context: :visits

  aggregate :visit, "Visit" do
    identity :visit_id

    command :book, "Book a visit", by: :clerk, emits: :booked
    command :move, "Move a visit", by: :clerk, emits: :moved
    command :close, "Close a visit", by: :clerk, emits: :closed

    command :remind, "Remind of a visit", emits: :reminded

    command :note, "Note a visit", emits: :noted

    event :booked, "Visit booked"
    event :moved, "Visit moved"
    event :closed, "Visit closed"
    event :reminded, "Reminded of a visit"

    event :noted, "Visit noted"
  end

  policy :remind_on_change, "Remind on a booking or a move",
    handles: [:booked, :moved],
    issues: :remind

  process_manager :watch, "Watch a visit" do
    correlate :visit_id
    starts_on :booked, issues: :note
    starts_on :closed
    on :booked, issues: :note
    on :moved, issues: :note
    ends_on :closed
  end

  scenario "a visit is booked" do
    command :book
    expect :booked
  end
end

defmodule PhaseRig.VisitDecider do
  @moduledoc "**Invented.** The decider of `PhaseRig.Visits`: every command emits its event."

  use PhaseRig.Visits, aggregate: :visit

  @impl true
  def book(%Book{visit_id: id}, _state), do: emit(%Booked{visit_id: id})

  @impl true
  def move(%Move{visit_id: id}, _state), do: emit(%Moved{visit_id: id})

  @impl true
  def close(%Close{visit_id: id}, _state), do: emit(%Closed{visit_id: id})

  @impl true
  def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

  @impl true
  def note(%Note{visit_id: id}, _state), do: emit(%Noted{visit_id: id})
end

defmodule PhaseRig.RemindOnChange do
  @moduledoc "**Invented.** Reminds on every booking and every move."

  use PhaseRig.Visits, policy: :remind_on_change

  @impl true
  def booked(%Booked{visit_id: id}), do: issue(%Remind{visit_id: id})

  @impl true
  def moved(%Moved{visit_id: id}), do: issue(%Remind{visit_id: id})
end

defmodule PhaseRig.Watch do
  @moduledoc "**Invented.** Notes each booking and move, at the start of a run or during it."

  use PhaseRig.Visits, process_manager: :watch

  @impl true
  def booked(%Booked{visit_id: id}, _state), do: issue(%Note{visit_id: id})

  @impl true
  def moved(%Moved{visit_id: id}, _state), do: issue(%Note{visit_id: id})
end
