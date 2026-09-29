defmodule EhOsContract.ClockTest do
  @moduledoc """
  **The parts of `EhOsContract.Clock.at/2` that are not about any contract**: a zone
  other than UTC is refused at the call, calls nest and restore, and outside `at/2`
  it is now.

  That the time reaches the events a command, a policy and a drained subscription
  write is pinned on a contract, in `conformance/clock_contract_test.exs`.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Clock

  @nine ~U[2026-09-01 09:00:00.000000Z]
  @noon ~U[2026-09-01 12:00:00.000000Z]

  test "a time in another zone is refused at the call, not later at the append" do
    # Built by hand, because a zone other than UTC needs a time zone database and this
    # suite has none. The log stores UTC; the caller converts.
    warsaw = %{
      ~U[2026-07-01 11:00:00.000000Z]
      | time_zone: "Europe/Warsaw",
        zone_abbr: "CEST",
        utc_offset: 3600,
        std_offset: 3600
    }

    assert_raise ArgumentError, ~r/Europe\/Warsaw.*UTC/, fn ->
      Clock.at(warsaw, fn -> flunk("ran with a time the log cannot store") end)
    end
  end

  test "outside at/2 it is now, and calls nest and restore" do
    before = DateTime.utc_now()
    assert DateTime.compare(Clock.now(), before) != :lt

    Clock.at(@nine, fn ->
      assert Clock.now() == @nine
      Clock.at(@noon, fn -> assert Clock.now() == @noon end)
      assert Clock.now() == @nine
    end)

    assert DateTime.compare(Clock.now(), before) != :lt
  end
end
