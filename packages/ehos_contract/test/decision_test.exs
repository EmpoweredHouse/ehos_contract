defmodule EhosContract.DecisionTest do
  @moduledoc """
  **`EhosContract.Decision`, without a database** (plan W4): the rules dispatch holds a
  decision to, called on their own. Dispatch's own tests (`test/runtime/dispatch_*`)
  pin that it applies them; this file pins what each says, on `LifecycleRig.Visits`.
  """

  use ExUnit.Case, async: true

  alias EhosContract.{Decision, Model}

  @model Model.fetch(LifecycleRig.Visits)
  @unit Enum.find(@model.units, &(&1.name == :visit))

  defp declaration(name), do: Enum.find(@model.commands, &(&1.name == name))
  defp event(name, fields), do: struct(Model.module_for(@model, :event, name), fields)
  defp command(name, fields), do: struct(Model.module_for(@model, :command, name), fields)

  describe "admitted/4" do
    test "names each struct by its declaration, in order" do
      booked = event(:booked, visit_id: "v-1")
      note = event(:note_added, visit_id: "v-1")

      assert Decision.admitted(@model, :event, [booked, note], [:booked, :note_added]) ==
               {:ok, [{:booked, booked}, {:note_added, note}]}
    end

    test "says which struct is not allowed, and which is not a struct at all" do
      closed = event(:closed, visit_id: "v-1", notes_before_arrival: 0)

      assert Decision.admitted(@model, :event, [event(:booked, visit_id: "v"), closed], [:booked]) ==
               {:error, {:not_allowed, closed}}

      assert Decision.admitted(@model, :event, [%{visit_id: "v"}], [:booked]) ==
               {:error, {:not_a_struct, %{visit_id: "v"}}}
    end

    test "a command is named among a reaction's issues the same way" do
      add_note = command(:add_note, visit_id: "v-1")

      assert {:ok, [{:add_note, ^add_note}]} =
               Decision.admitted(@model, :command, [add_note], [:add_note])
    end
  end

  describe "held!/6" do
    test "returns each event with its declaration, and the status after them" do
      book = command(:book_visit, visit_id: "v-1")
      booked = event(:booked, visit_id: "v-1")

      assert {[{%{name: :booked}, ^booked}], :booked} =
               Decision.held!(@model, declaration(:book_visit), @unit, nil, book, [booked])
    end

    test "refuses an event outside emits, for another unit, with unfit fields, or off the graph" do
      book = command(:book_visit, visit_id: "v-1")
      close = command(:close_visit, visit_id: "v-1")

      for {declaration, status, command, events, message} <- [
            {:book_visit, nil, book, [event(:note_added, visit_id: "v-1")],
             "which is not among the events it emits"},
            {:book_visit, nil, book, [event(:booked, visit_id: "v-2")],
             "for another unit: its visit_id is not the command's"},
            {:close_visit, :in_progress, close,
             [event(:closed, visit_id: "v-1", notes_before_arrival: "three")],
             "with fields that do not fit"},
            {:close_visit, :booked, close,
             [event(:closed, visit_id: "v-1", notes_before_arrival: 0)],
             "in status :booked, which no transition leaves with it"}
          ] do
        error =
          assert_raise ArgumentError, fn ->
            Decision.held!(@model, declaration(declaration), @unit, status, command, events)
          end

        assert error.message =~ message
        assert error.message =~ "Nothing was appended."
      end
    end
  end

  describe "lifecycle!/4" do
    test "a unit with no lifecycle stays where it stood" do
      assert Decision.lifecycle!(%{name: :ledger}, nil, :post, [:posted]) == nil
    end

    test "a unit with one moves as the graph says" do
      assert Decision.lifecycle!(@unit, :booked, :admit_patient, [:patient_arrived]) ==
               :in_progress
    end
  end
end
