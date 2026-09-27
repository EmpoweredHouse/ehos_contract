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

  test "a result declared optional may be nil, and one that is not may not" do
    assert Seating.next_seat(2, 1) == 2
    assert Seating.next_seat(2, 2) == nil

    Process.put(:boundary_rig_seating_misbehaves_with_nil, true)
    error = assert_raise ArgumentError, fn -> Seating.free_seats(3, 1) end
    assert error.message =~ "returned a result that does not fit :integer (required)"
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

  test "a call with the wrong number of arguments, or to an undeclared service, says so" do
    error =
      assert_raise ArgumentError, fn ->
        EhOsContract.DomainService.call(BoundaryRig.Enrolment, :seating, :free_seats, [3, 1, 9])
      end

    assert error.message =~ "takes 2 arguments and was called with 3"

    assert_raise ArgumentError, ~r/declares no domain service :parking/, fn ->
      EhOsContract.DomainService.call(BoundaryRig.Enrolment, :parking, :free_seats, [3, 1])
    end
  end

  test "the generated module is the behaviour the implementation binds to" do
    assert BoundaryRig.SeatingRules.__eh_os_implementation__() |> Map.take([:kind, :name]) ==
             %{kind: :domain_service, name: :seating}

    assert {:free_seats, 2} in Seating.behaviour_info(:callbacks)
  end
end

defmodule EhOsContract.DomainServiceLookupTest do
  @moduledoc """
  The EL2b review: a call finds its implementation once, not in the index on every
  call, whose lookup scans the loaded applications. Shown by taking the
  implementation out of the index after a first call: the next call still runs.
  """

  use ExUnit.Case, async: false

  alias BoundaryRig.Enrolment.DomainServices.Seating
  alias EhOsContract.Implementations

  test "the implementation is looked up once" do
    assert Seating.free_seats(3, 1) == 2

    apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)))
    key = {Implementations, apps}
    index = Implementations.index(nil)
    on_exit(fn -> :persistent_term.put(key, index) end)

    declarations =
      Map.delete(index.declarations, {BoundaryRig.Enrolment, :domain_service, :seating})

    :persistent_term.put(key, %{index | declarations: declarations})

    assert Seating.free_seats(3, 2) == 1
  end
end
