defmodule EhOsContract.EntityReadsTest do
  @moduledoc """
  Plan DD, T2a (#240): a command that `reads:` an entity is decided with the row the
  host's `EhOsContract.Entities` gives, asked once per command and before the
  transaction; a row not there refuses the command as a field naming nothing; a row
  that does not fit its entity raises; and what was read is kept on the command's row.
  On the invented `ReadRig.Orders`, with `ReadRig.Entities` configured for the suite.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, CommandRecord, Entities, Event, Receipt, Rejection}
  alias ReadRig.Orders.Commands.{CancelOrder, PlaceOrder}
  alias ReadRig.Orders.Events.Placed

  @clerk Actor.credential("u-1", ["read_rig.place_order", "read_rig.cancel_order"])

  defp place(order, opts \\ []) do
    EhOsContract.dispatch(
      ReadRig.Orders,
      %PlaceOrder{order_id: order, product_id: "product-tea", quantity: 3},
      Keyword.merge([actor: @clerk], opts)
    )
  end

  defp row!(type), do: Repo.one!(from(c in CommandRecord, where: c.type == ^type))
  defp fetched, do: Process.get(:read_rig_fetched, [])

  test "the decision gets the entity's declared fields, and the row keeps what was read" do
    assert {:ok, %Receipt{events: [%Placed{total: 12}]}} = place("order-1")
    assert fetched() == ["product-tea"]

    # `shelf`, which the host's row has and the domain does not declare, is not kept.
    assert row!("place_order").inputs == %{
             "product" => %{"product_id" => "product-tea", "price" => 4, "on_sale" => true}
           }
  end

  test "a rejection is decided on the row too, and keeps it" do
    Process.put(
      {:read_rig_row, "product-tea"},
      {:ok, %{product_id: "product-tea", price: 4, on_sale: false}}
    )

    assert {:error, %Rejection{invariant: :product_on_sale}} = place("order-1")

    assert %{outcome: "rejected", inputs: %{"product" => %{"on_sale" => false}}} =
             row!("place_order")
  end

  test "a row not found refuses the command by its field, and writes nothing" do
    Process.put({:read_rig_row, "product-tea"}, :not_found)

    assert place("order-1") == {:error, {:invalid, [product_id: :unknown]}}
    assert Repo.all(Event) == []
    assert Repo.all(CommandRecord) == []
  end

  test "through call/3, a row not found is the field's problem, as a 422 shows it" do
    Process.put({:read_rig_row, "product-nothing"}, :not_found)

    assert EhOsContract.call(
             {:command, "read_rig.place_order"},
             %{"order_id" => "order-1", "product_id" => "product-nothing", "quantity" => 1},
             actor: @clerk
           ) == {:error, {:invalid, [product_id: :unknown]}}
  end

  test "a row that does not fit the entity raises, naming the field and not its value" do
    Process.put(
      {:read_rig_row, "product-tea"},
      {:ok, %{product_id: "product-tea", price: "four"}}
    )

    error = assert_raise Entities.UnfitRowError, fn -> place("order-1") end
    assert error.message =~ "ReadRig.Entities.fetch/3 returned a row of entity :product"
    assert error.message =~ "price: :type"
    assert error.message =~ "on_sale: :required"
    refute error.message =~ "four"
  end

  test "an answer of another shape raises" do
    Process.put({:read_rig_row, "product-tea"}, {:error, :down})

    assert_raise ArgumentError, ~r/returned a tuple of 2 for entity :product/, fn ->
      place("order-1")
    end
  end

  test "a conflict's retry decides on the rows read the first time, without asking again" do
    Process.put(:read_rig_race, true)

    assert {:ok, %Receipt{}} = place("order-1")
    assert fetched() == ["product-tea"], "asked once, though decided twice"
  end

  test "a command already accepted under its key gets its receipt without a read" do
    assert {:ok, %Receipt{duplicate: false}} = place("order-1", idempotency_key: "k-1")
    Process.put({:read_rig_row, "product-tea"}, :not_found)

    assert {:ok, %Receipt{duplicate: true}} = place("order-1", idempotency_key: "k-1")
    assert fetched() == ["product-tea"]
  end

  test "control: a command that reads nothing asks nothing, and its row keeps no inputs" do
    assert {:error, %Rejection{invariant: :order_placed_first}} =
             EhOsContract.dispatch(ReadRig.Orders, %CancelOrder{order_id: "order-1"},
               actor: @clerk
             )

    assert fetched() == []
    assert row!("cancel_order").inputs == nil
  end

  describe "at boot" do
    @models [EhOsContract.Model.fetch(ReadRig.Orders)]

    setup do
      entities = Application.fetch_env!(:eh_os_contract, :entities)
      on_exit(fn -> Application.put_env(:eh_os_contract, :entities, entities) end)
    end

    test "a command that reads and no implementation: the node does not start, naming both" do
      Application.delete_env(:eh_os_contract, :entities)
      error = assert_raise ArgumentError, fn -> Entities.check!(@models) end

      assert error.message =~
               "ReadRig.Orders declares commands [:place_order] that read entities, and no " <>
                 "entities implementation is configured"
    end

    test "an implementation that is no module exporting fetch/3 is refused as well" do
      for impl <- [ReadRig.NoSuchEntities, ReadRig.Domain] do
        Application.put_env(:eh_os_contract, :entities, impl)
        error = assert_raise ArgumentError, fn -> Entities.check!(@models) end
        assert error.message =~ "the configured implementation #{inspect(impl)} is not a module"
      end
    end

    test "control: the suite's implementation, and contracts that read nothing" do
      assert Entities.check!(@models) == :ok
      Application.delete_env(:eh_os_contract, :entities)
      assert Entities.check!([EhOsContract.Model.fetch(SupplyRig.Desk)]) == :ok
    end
  end
end
