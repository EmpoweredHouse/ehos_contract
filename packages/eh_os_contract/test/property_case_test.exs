defmodule EhOsContract.PropertyCaseTest do
  @moduledoc """
  Plan DD, PC2 (#266): **a unit's code tried on legal histories of its contract**. The
  engine's invented rigs carry defects on purpose; each is found, with a short history
  that shows it, and a unit without one passes.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias EhOsContract.PropertyCase

  defp decides(contract, unit, command, max_runs \\ 100) do
    check all(
            {events, command, rows} <- PropertyCase.decisions(contract, unit, command),
            max_runs: max_runs
          ) do
      PropertyCase.decide(contract, unit, events, {command, rows})
    end
  end

  defp failure(fun) do
    error = assert_raise ExUnit.AssertionError, fun
    Exception.message(error)
  end

  describe "a decision outside the contract is found" do
    test "reopening a visit in progress, which the lifecycle forbids" do
      message = failure(fn -> decides(LifecycleRig.Visits, :visit, :reopen_visit) end)

      assert message =~ "command :reopen_visit"
      assert message =~ "decided what the contract does not allow"
      # Shrunk to a history no longer than the visit's booking and arrival.
      assert [history] =
               Regex.run(~r/after the history (\[[^\]]*\])/, message, capture: :all_but_first)

      assert length(Code.eval_string(history) |> elem(0)) <= 2
    end

    test "an event the command does not emit" do
      assert failure(fn -> decides(DispatchRig.Ledger, :account, :misbehave) end) =~
               "which is not among the events it emits"
    end

    test "an event whose value breaks its domain's invariant" do
      assert failure(fn -> decides(ValueRig.Till, :till, :short_change) end) =~
               "with fields that do not fit"
    end

    test "control: the commands of the rigs with no defect decide within the contract" do
      for {contract, unit, command} <- [
            {LifecycleRig.Visits, :visit, :admit_patient},
            {LifecycleRig.Visits, :visit, :close_visit},
            {DispatchRig.Ledger, :account, :withdraw},
            {ValueRig.Till, :till, :pay_in}
          ] do
        decides(contract, unit, command, 50)
      end
    end
  end

  describe "folding" do
    property "every legal history of the rigs folds into the unit's state" do
      check all(events <- EhOsContract.Generators.history(LifecycleRig.Visits, :visit)) do
        assert %LifecycleRig.Visits.Aggregates.Visit.State{} =
                 PropertyCase.fold(LifecycleRig.Visits, :visit, events)
      end
    end

    test "an evolve/2 that returns a map is found" do
      Process.put(:lifecycle_rig_evolve_returns_map, true)

      message =
        failure(fn ->
          check all(events <- EhOsContract.Generators.history(LifecycleRig.Visits, :visit)) do
            PropertyCase.fold(LifecycleRig.Visits, :visit, events)
          end
        end)

      assert message =~ "and it returns the unit's state"
    after
      Process.delete(:lifecycle_rig_evolve_returns_map)
    end
  end

  describe "invariants over decided commands" do
    defmodule HoldsVisit do
      @moduledoc false
      # The rig's decider with `holds?/2`: a note before the patient arrives is counted,
      # and a test asks it to say an open visit holds only without one.
      use LifecycleRig.Visits, aggregate: :visit

      @impl true
      def book_visit(%BookVisit{visit_id: id}, _state), do: emit(%Booked{visit_id: id})
      @impl true
      def admit_patient(
            %AdmitPatient{visit_id: id, __meta__: %{occurred_at: %DateTime{}}},
            _state
          ),
          do: emit(%PatientArrived{visit_id: id})

      @impl true
      def cancel_visit(%CancelVisit{visit_id: id}, _state), do: emit(%Cancelled{visit_id: id})
      @impl true
      def close_visit(%CloseVisit{visit_id: id}, %State{notes_before_arrival: n}),
        do: emit(%Closed{visit_id: id, notes_before_arrival: n})

      @impl true
      def add_note(%AddNote{visit_id: id}, _state), do: emit(%NoteAdded{visit_id: id})
      @impl true
      def reopen_visit(%ReopenVisit{visit_id: id}, _state),
        do: emit(%PatientArrived{visit_id: id})

      @impl true
      def evolve(%State{status: :booked} = state, %NoteAdded{}),
        do: %{state | notes_before_arrival: state.notes_before_arrival + 1}

      def evolve(state, _event), do: state

      def holds?(:only_an_open_visit, state),
        do: not Process.get(:holds_visit_strict, false) or state.notes_before_arrival == 0

      def holds?(_invariant, _state), do: true
    end

    @commands [
      {%LifecycleRig.Visits.Commands.BookVisit{visit_id: "v-1"}, %{}},
      {%LifecycleRig.Visits.Commands.AddNote{visit_id: "v-1"}, %{}},
      {%LifecycleRig.Visits.Commands.AdmitPatient{visit_id: "v-1"}, %{}}
    ]

    test "an invariant holds?/2 says is broken after a command is found, naming the commands" do
      Process.put(:holds_visit_strict, true)

      message =
        failure(fn ->
          PropertyCase.walk(LifecycleRig.Visits, :visit, @commands, implementations: [HoldsVisit])
        end)

      assert message =~
               "invariant :only_an_open_visit of :visit does not hold after the commands " <>
                 "[:book_visit, :add_note]"
    after
      Process.delete(:holds_visit_strict)
    end

    test "control: invariants that hold leave the state the commands reached" do
      assert %{status: :in_progress, notes_before_arrival: 1} =
               PropertyCase.walk(LifecycleRig.Visits, :visit, @commands,
                 implementations: [HoldsVisit]
               )
    end
  end

  describe "as dispatch decides" do
    property "a command reaches its decision with __meta__, as dispatch hands it over" do
      check all(
              {events, command, rows} <-
                PropertyCase.decisions(LifecycleRig.Visits, :visit, :admit_patient)
            ) do
        PropertyCase.decide(LifecycleRig.Visits, :visit, events, {command, rows})
        assert command.__meta__ == nil
      end

      # The decision itself sees one: `HoldsVisit` admits a patient only by a command that
      # says when it was issued, and raises on one that does not.
      check all(
              {events, command, rows} <-
                PropertyCase.decisions(LifecycleRig.Visits, :visit, :admit_patient)
            ) do
        PropertyCase.decide(LifecycleRig.Visits, :visit, events, {command, rows},
          implementations: [EhOsContract.PropertyCaseTest.HoldsVisit]
        )
      end
    end

    property "a unit a command creates starts its walk with that command, and its identity" do
      check all(commands <- PropertyCase.walks(BoundaryRig.Waitlist, :entry), max_runs: 50) do
        assert [{%BoundaryRig.Waitlist.Commands.JoinWaitlist{entry_id: id}, _} | rest] = commands
        assert is_binary(id)
        assert Enum.all?(rest, fn {command, _} -> command.entry_id == id end)
      end
    end
  end

  describe "the case" do
    test "plans a property per command of every aggregate with an implementation" do
      assert [{:visit, commands, false, [LifecycleRig.Visit]}] =
               PropertyCase.plan(LifecycleRig.Visits, nil)

      assert :reopen_visit in commands
    end

    test "an aggregate the contract lacks is refused by name" do
      assert_raise ArgumentError, ~r/declares no aggregate :appointment/, fn ->
        PropertyCase.fold(LifecycleRig.Visits, :appointment, [])
      end
    end
  end
end
