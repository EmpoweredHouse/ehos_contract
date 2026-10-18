defmodule AppuniteEquipment.DemandsDispatchTest do
  @moduledoc """
  The demand dispatched across the two contracts it spans: issuing a computer in
  `Computers` closes the demand it answers in `Demands`, and a theft recorded in
  `Computers` opens a demand for the person, both in the transaction of the event.
  """

  use EhOsContractHost.DataCase, async: false

  alias AppuniteEquipment.Contracts.{Computers, Demands}

  alias AppuniteEquipment.Contracts.Computers.Commands.{
    IssueComputer,
    ReceiveComputer,
    SetUpComputer
  }

  alias AppuniteEquipment.Contracts.Computers.Events.Lost
  alias AppuniteEquipment.Contracts.Demands.Commands.{OpenDemand, OrderComputer}
  alias AppuniteEquipment.Contracts.Demands.Queries.WaitingList
  alias EhOsContract.{Actor, Event}

  @manager Actor.credential("manager-1", [
             "appunite_equipment.open_demand",
             "appunite_equipment.order_computer",
             "appunite_equipment.receive_computer",
             "appunite_equipment.set_up_computer",
             "appunite_equipment.issue_computer",
             "appunite_equipment.waiting_list",
             "appunite_equipment.lost"
           ])

  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  defp waiting do
    {:ok, rows} = EhOsContract.query(Demands, %WaitingList{}, actor: @manager)
    rows
  end

  defp computer_in_office do
    {:ok, %{identity: %{computer_id: computer}}} =
      EhOsContract.dispatch(
        Computers,
        %ReceiveComputer{
          profile: :developer,
          serial_number: "K7HQ2F9X4M",
          chip: :m5,
          price: 1_199_900,
          purchased_on: ~D[2026-10-20],
          invoice_number: "FV/2026/10/7"
        },
        actor: @manager,
        idempotency_key: "invoice:FV/2026/10/7"
      )

    {:ok, _} =
      EhOsContract.dispatch(Computers, %SetUpComputer{computer_id: computer}, actor: @manager)

    computer
  end

  test "Ola's demand: opened, a computer ordered, then issued to her — and she waits no more" do
    {:ok, %{identity: %{demand_id: demand}}} =
      EhOsContract.dispatch(
        Demands,
        %OpenDemand{employee_id: "employee-ola", reason: :new_hire, starts_on: ~D[2026-11-01]},
        actor: @manager,
        idempotency_key: "demand:employee-ola"
      )

    {:ok, _} =
      EhOsContract.dispatch(Demands, %OrderComputer{demand_id: demand, profile: :developer},
        actor: @manager
      )

    assert [%{employee_id: "employee-ola", status: :ordered}] = waiting()

    computer = computer_in_office()

    {:ok, _} =
      EhOsContract.dispatch(
        Computers,
        %IssueComputer{
          computer_id: computer,
          demand_id: demand,
          assignment_id: "assignment-ola-1",
          employee_id: "employee-ola",
          shipped_on: ~D[2026-10-30],
          as_replacement: false
        },
        actor: @manager
      )

    assert waiting() == []

    assert types() == [
             "appunite_equipment.demands.opened",
             "appunite_equipment.demands.computer_ordered",
             "appunite_equipment.computers.received",
             "appunite_equipment.computers.set_up",
             "appunite_equipment.computers.issued",
             "appunite_equipment.demands.fulfilled"
           ]
  end

  test "a computer stolen from Bartek opens a demand for him" do
    computer = computer_in_office()

    {:ok, %{identity: %{demand_id: demand}}} =
      EhOsContract.dispatch(
        Demands,
        %OpenDemand{employee_id: "employee-bartek", reason: :new_hire},
        actor: @manager,
        idempotency_key: "demand:employee-bartek"
      )

    {:ok, _} =
      EhOsContract.dispatch(
        Computers,
        %IssueComputer{
          computer_id: computer,
          demand_id: demand,
          assignment_id: "assignment-bartek-1",
          employee_id: "employee-bartek",
          shipped_on: ~D[2026-10-30],
          as_replacement: false
        },
        actor: @manager
      )

    {:ok, _} =
      EhOsContract.record(
        Computers,
        %Lost{
          computer_id: computer,
          assignment_id: "assignment-bartek-1",
          employee_id: "employee-bartek"
        },
        actor: @manager
      )

    assert [%{employee_id: "employee-bartek", reason: :theft, status: :open}] = waiting()
  end
end
