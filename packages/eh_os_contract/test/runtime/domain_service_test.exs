defmodule EhOsContract.DomainServiceTest do
  @moduledoc """
  A domain service called through the module its contract generates (plan EM2), on
  the invented `BoundaryRig`: the arguments and the result are held to their declared
  types, and a mismatch raises without the value in the message.
  """

  use ExUnit.Case, async: true

  alias BoundaryRig.Enrolment.DomainServices.Seating

  test "a call runs the implementation and returns its result" do
    assert Seating.free_seats(3, 1) == 2
    assert Seating.free_seats(1, 4) == 0
  end

  test "an argument that does not fit its type is refused before the implementation runs" do
    error = assert_raise ArgumentError, fn -> Seating.free_seats("three-seats", 1) end

    assert error.message =~
             "function :free_seats of domain service :seating of BoundaryRig.Enrolment was called " <>
               "with arguments that do not fit their declared types: [capacity: :type]"

    refute error.message =~ "three-seats"
  end

  test "a result that does not fit the declared type is refused" do
    Process.put(:boundary_rig_seating_misbehaves, true)
    error = assert_raise ArgumentError, fn -> Seating.free_seats(3, 1) end

    assert error.message =~ "returned a result that does not fit :integer (type)"
    refute error.message =~ "none"
  end

  test "the generated module is the behaviour the implementation binds to" do
    assert BoundaryRig.SeatingRules.__eh_os_implementation__() |> Map.take([:kind, :name]) ==
             %{kind: :domain_service, name: :seating}

    assert {:free_seats, 2} in Seating.behaviour_info(:callbacks)
  end
end
