defmodule AppuniteEquipment.Contracts.Demands do
  @moduledoc """
  A person who needs a computer, from the need to the computer issued to them.

  Written on 4 October 2026 from the process owner's sketch of that day (cf.pdf)
  and their answers: a new person, a theft, a failure or an exchange opens a need,
  and it ends only when a computer is issued — from the shelf, or bought from the
  reseller for it (E: never closed without an issue). The spreadsheet's `New`, a
  computer ordered for someone and not yet delivered, is this demand's status: the
  computer itself enters `AppuniteEquipment.Contracts.Computers` only when it is
  registered from the invoice, with no one yet.

  A new person, a failure and an exchange are opened by the person who manages the
  equipment; a theft opens one by itself. Both policies on the computer's events
  are delivered `:in_transaction`: the consequence is decided in the event's own
  transaction, and a crash rolls both back. A refusal does not: an issue naming a
  demand that is not open stands, and the demand stays on the waiting list — an open
  question for the process owner (PLAN.md, 4 October (2)).

  What is left out: which computer the shelf holds for which demand. The person,
  the account and the courier are one move with the issue (E), so a demand is
  never "assigned" before it is fulfilled.
  """

  use EhOsContract.Contract, domain: AppuniteEquipment.Domain, context: :equipment

  consumes AppuniteEquipment.Contracts.Computers, [:issued, :lost]

  aggregate :demand, "Zapotrzebowanie na komputer" do
    identity :demand_id, generated: :uuid

    invariant :ordered_only_while_open,
              "Komputer zamawia się w Innergo dla zapotrzebowania, które czeka i nic jeszcze dla niego nie zamówiono",
              source: "cf.pdf: „Nowa osoba” → „zakup komputera z innergo”"

    invariant :fulfilled_once,
              "Zapotrzebowanie zamyka jedno wydanie komputera, i tylko otwarte albo zamówione",
              source: "E (2026-10-04): bez zamknięcia bez wydania"

    lifecycle do
      status :open, "Otwarte"
      status :ordered, "New"
      status :fulfilled, "Zaspokojone", final: true

      initial :open, on: :opened
      transition :open, :computer_ordered, :ordered
      transition [:open, :ordered], :fulfilled, :fulfilled
    end

    command :open_demand, "Otwórz zapotrzebowanie na komputer",
      by: :equipment_manager,
      emits: :opened,
      creates: true,
      source: "cf.pdf, E (2026-10-04)" do
      field :employee_id, :id, subject: :employee
      field :reason, :demand_reason
      field :starts_on, :date, optional: true
    end

    # Ordered in the reseller's panel; the hire is known in advance (E, 3 October).
    command :order_computer, "Zamów komputer w Innergo",
      by: :equipment_manager,
      emits: :computer_ordered,
      from: :open,
      or_rejects: :ordered_only_while_open,
      rejects: :ordered_only_while_open,
      source: "cf.pdf, A:F „New”, E" do
      field :profile, :hardware_profile
    end

    # No one closes a demand by hand: the issue of a computer does, through the
    # policy below.
    command :fulfil_demand, "Zamknij zapotrzebowanie wydaniem komputera",
      emits: :fulfilled,
      from: [:open, :ordered],
      or_rejects: :fulfilled_once,
      rejects: :fulfilled_once,
      source: "E (2026-10-04)" do
      field :computer_id, :id
    end

    # A start date is known for a new person (T l.58: who comes, and when), not
    # for a theft or a failure.
    event :opened, "Otwarto zapotrzebowanie na komputer", source: "cf.pdf, E (2026-10-04)" do
      field :employee_id, :id, subject: :employee
      field :reason, :demand_reason
      field :starts_on, :date, optional: true
    end

    event :computer_ordered, "Zamówiono komputer w Innergo", source: "cf.pdf, A:F „New”, E" do
      field :profile, :hardware_profile
    end

    event :fulfilled, "Wydano komputer — zapotrzebowanie zaspokojone",
      terminal: true,
      source: "cf.pdf, E (2026-10-04)" do
      field :computer_id, :id
    end
  end

  policy :fulfil_on_issue, "Wydanie komputera zamyka zapotrzebowanie, na które odpowiada",
    handles: :issued,
    issues: :fulfil_demand,
    source: "cf.pdf: „wydanie komputera”, E (2026-10-04)"

  policy :open_after_theft, "Kradzież otwiera zapotrzebowanie osoby, której ukradziono komputer",
    handles: :lost,
    issues: :open_demand,
    source: "cf.pdf: „ukradziono komputer” → zakup albo półka"

  # What the person who manages the equipment asks every few days (T l.78): who is
  # waiting for a computer, from when, and whether one is already ordered for them.
  read_model :waiting, "Zapotrzebowania — kto czeka na komputer",
    projects: [:opened, :computer_ordered, :fulfilled] do
    field :demand_id, :id
    field :employee_id, :id, subject: :employee
    field :reason, :demand_reason
    field :starts_on, :date, optional: true
    field :status, {:enum, [open: "Otwarte", ordered: "New"]}
    field :profile, :hardware_profile, optional: true
  end

  query :waiting_list, "Kto czeka na komputer", reads: :waiting, by: :equipment_manager

  process :demand, "Zapotrzebowanie: od potrzeby do wydania komputera",
    accountable: :equipment_manager do
    correlate :demand_id
  end

  scenario "Ola zaczyna 1 listopada — zapotrzebowanie otwarte" do
    command :open_demand, %{
      employee_id: "employee-ola",
      reason: :new_hire,
      starts_on: "2026-11-01"
    }

    expect :opened, %{reason: :new_hire, starts_on: "2026-11-01"}
  end

  scenario "na półce nic dla Oli — zamówiono MacBooka Pro" do
    given :opened, %{employee_id: "employee-ola", reason: :new_hire, starts_on: "2026-11-01"}
    command :order_computer, %{profile: :developer}
    expect :computer_ordered, %{profile: :developer}
  end

  scenario "komputer dla Oli już zamówiony — drugi raz się nie zamawia" do
    given :opened, %{employee_id: "employee-ola", reason: :new_hire, starts_on: "2026-11-01"}
    given :computer_ordered, %{profile: :developer}
    command :order_computer, %{profile: :developer}
    rejected :ordered_only_while_open
  end

  scenario "Ola dostała komputer — zapotrzebowanie zamyka się raz" do
    given :opened, %{employee_id: "employee-ola", reason: :new_hire, starts_on: "2026-11-01"}
    given :fulfilled, %{computer_id: "computer-1"}
    command :fulfil_demand, %{computer_id: "computer-2"}
    rejected :fulfilled_once
  end

  scenario "wydano komputer Oli — jej zapotrzebowanie się zamyka" do
    target :fulfil_on_issue

    on :issued, %{
      computer_id: "computer-1",
      demand_id: "demand-ola-1",
      assignment_id: "assignment-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-30",
      as_replacement: false
    }

    issues :fulfil_demand, %{demand_id: "demand-ola-1", computer_id: "computer-1"}
  end

  scenario "Bartkowi ukradziono komputer — Bartek czeka na nowy" do
    target :open_after_theft

    on :lost, %{
      computer_id: "computer-1",
      assignment_id: "assignment-bartek-2",
      employee_id: "employee-bartek"
    }

    issues :open_demand, %{employee_id: "employee-bartek", reason: :theft}
  end

  scenario "kto czeka: Ola z zamówionym komputerem, Bartek po kradzieży; Maja już dostała" do
    given :opened, %{
      demand_id: "demand-1",
      employee_id: "employee-ola",
      reason: :new_hire,
      starts_on: "2026-11-01"
    }

    given :computer_ordered, %{demand_id: "demand-1", profile: :developer}
    given :opened, %{demand_id: "demand-2", employee_id: "employee-bartek", reason: :theft}
    given :opened, %{demand_id: "demand-3", employee_id: "employee-maja", reason: :failure}
    given :fulfilled, %{demand_id: "demand-3", computer_id: "computer-7"}
    query :waiting_list

    answers [
      %{
        demand_id: "demand-1",
        employee_id: "employee-ola",
        status: :ordered,
        profile: :developer
      },
      %{demand_id: "demand-2", employee_id: "employee-bartek", status: :open, reason: :theft}
    ]
  end
end
