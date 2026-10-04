defmodule EhOsContract.LifecycleTest do
  @moduledoc "Plan LC2: the status, computed from event names alone."

  use ExUnit.Case, async: true

  alias EhOsContract.Lifecycle

  @lifecycle %{
    statuses: [
      %{name: :booked, terminal: false},
      %{name: :in_progress, terminal: false},
      %{name: :closed, terminal: true}
    ],
    initial: [%{status: :booked, on: :visit_booked}],
    transitions: [
      %{from: :booked, event: :patient_arrived, to: :in_progress},
      %{from: :in_progress, event: :visit_closed, to: :closed}
    ]
  }

  test "the status follows the stream: started, moved, left alone by what no transition names" do
    assert Lifecycle.status(@lifecycle, []) == nil
    assert Lifecycle.status(@lifecycle, [:visit_booked]) == :booked

    assert Lifecycle.status(@lifecycle, [:visit_booked, :note_added, :patient_arrived]) ==
             :in_progress

    # Out of the graph, as a recorded event may be: nothing moves.
    assert Lifecycle.status(@lifecycle, [:visit_booked, :visit_closed]) == :booked
    assert Lifecycle.status(@lifecycle, [:patient_arrived]) == nil
  end

  test "walk gives the status before each event, and after the last" do
    assert Lifecycle.walk(@lifecycle, [:visit_booked, :note_added, :patient_arrived]) ==
             {[nil, :booked, :booked], :in_progress}
  end

  test "admits? holds a command to its from:, and lets one without from: through" do
    assert Lifecycle.admits?(%{from: [:booked]}, :booked)
    refute Lifecycle.admits?(%{from: [:booked]}, :in_progress)
    refute Lifecycle.admits?(%{from: [:booked]}, nil)
    assert Lifecycle.admits?(%{name: :add_note}, :closed)
  end

  test "decided! returns the status after what was decided, and raises on what the graph forbids" do
    assert Lifecycle.decided!(@lifecycle, nil, :book, [:visit_booked, :patient_arrived]) ==
             :in_progress

    assert Lifecycle.decided!(@lifecycle, :booked, :note, [:note_added]) == :booked

    for {status, events, message} <- [
          {:closed, [:note_added], "in status :closed, which is terminal"},
          {:booked, [:visit_booked], "it starts an aggregate, and this one has started"},
          {nil, [:patient_arrived], "before the aggregate has a status"},
          {:booked, [:visit_closed], "in status :booked, which no transition leaves with it"}
        ] do
      error =
        assert_raise ArgumentError, fn -> Lifecycle.decided!(@lifecycle, status, :c, events) end

      assert error.message =~ message
      assert error.message =~ "Nothing was appended."
    end
  end
end
