defmodule EhOsContract.LifecycleTest do
  @moduledoc "Plan LC2: the status, computed from event names alone."

  use ExUnit.Case, async: true

  alias EhOsContract.Lifecycle

  @lifecycle %{
    statuses: [
      %{name: :booked, final: false},
      %{name: :in_progress, final: false},
      %{name: :closed, final: true}
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
          {:closed, [:note_added], "in status :closed, which is final"},
          {:booked, [:visit_booked], "it starts an aggregate, and this one has started"},
          {nil, [:patient_arrived], "before the aggregate has a status"},
          {nil, [:note_added], "before the aggregate has a status"},
          {:booked, [:visit_closed], "in status :booked, which no transition leaves with it"}
        ] do
      error =
        assert_raise ArgumentError, fn -> Lifecycle.decided!(@lifecycle, status, :c, events) end

      assert error.message =~ message
      assert error.message =~ "Nothing was appended."
    end
  end

  test "tally counts the moves taken and the events the graph did not allow, in the period only" do
    streams = [
      [
        {:visit_booked, true},
        {:patient_arrived, true},
        {:visit_closed, true},
        {:note_added, true}
      ],
      [{:visit_booked, false}, {:visit_closed, true}, {:patient_arrived, true}, {nil, true}],
      [{:visit_booked, false}]
    ]

    assert Lifecycle.tally(@lifecycle, streams) == %{
             aggregates: 2,
             standing: MapSet.new([:in_progress]),
             taken: %{
               {nil, :visit_booked, :booked} => 1,
               {:booked, :patient_arrived, :in_progress} => 2,
               {:in_progress, :visit_closed, :closed} => 1
             },
             undeclared: %{{:closed, :note_added} => 1, {:booked, :visit_closed} => 1}
           }
  end

  test "tally counts a self-loop, and an initial event that is a transition too, as dispatch moves" do
    lifecycle = %{
      statuses: [%{name: :open, final: false}, %{name: :done, final: true}],
      initial: [%{status: :open, on: :noted}],
      transitions: [
        %{from: :open, event: :noted, to: :open},
        %{from: :open, event: :finished, to: :done}
      ]
    }

    assert %{
             taken: %{{nil, :noted, :open} => 1, {:open, :noted, :open} => 2},
             undeclared: %{},
             standing: standing
           } = Lifecycle.tally(lifecycle, [[{:noted, true}, {:noted, true}, {:noted, true}]])

    assert standing == MapSet.new([:open])
    assert Lifecycle.decided!(lifecycle, :open, :c, [:noted, :finished]) == :done
  end
end
