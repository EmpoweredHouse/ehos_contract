defmodule EhOsContract.Auth.TestingTest do
  @moduledoc """
  `EhOsContract.Auth.Testing.assert_every_entry_refuses/3` asks a door for every
  capability a person may hold, and none for `<name>.subscribe` (plan E12c), which is
  the application's.
  """

  use ExUnit.Case, async: true

  defmodule Domain do
    @moduledoc false
    use EhOsContract.Domain, name: :testing_rig, language: :en

    subdomain(:core, "Core", type: :core)
    context(:stock, "Stock", subdomain: :core)

    actor(:keeper, :human, "Keeper")
    actor(:scheduler, :system, "Scheduler")
  end

  defmodule Stock do
    @moduledoc false
    use EhOsContract.Contract, domain: Domain, context: :stock

    consumes "other_shop.order.placed.v1", as: :order_placed do
      field(:order_id, :id)
    end

    aggregate :reservation, "Reservation" do
      identity(:order_id)
      command(:reserve, "Reserve", by: :scheduler, emits: :reserved)
      event(:reserved, "Reserved", terminal: true)
    end

    policy(:reserve_for_order, "Reserve for an order", handles: :order_placed, issues: :reserve)

    process :reservation, "Reservation", accountable: :keeper do
      correlate(:order_id)
    end
  end

  test "a contract that consumes another application's event needs no door for it" do
    assert Map.keys(EhOsContract.Model.capabilities(Stock)) == [
             "other_shop.order.placed.subscribe"
           ]

    assert EhOsContract.Auth.Testing.assert_every_entry_refuses(Stock, %{}) == :ok
  end
end
