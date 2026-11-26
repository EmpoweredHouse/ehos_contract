defmodule EhosContract.SeedActorTest do
  @moduledoc """
  The domain's seed actor (#683): the application's own code loading sample data, which
  no `by:` names. Dispatch permits it what a person of the domain may do and the domain's
  `not_seeded` does not name, in every scope and with no `Authorizer`; it refuses
  `:not_declared`, before the transaction and with no row, a declaration it may not use.
  On the invented `SeedRig.Shop`.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.{Actor, CommandRecord, Event, Receipt}
  alias SeedRig.Shop
  alias SeedRig.Shop.Commands.{ArchiveOrder, HandOver, PlaceOrder, RefundOrder, ReleaseOrder}
  alias SeedRig.Shop.Events.{NoteTaken, StockCounted}
  alias SeedRig.Shop.Queries.OrdersOfShop

  defp seed, do: Actor.seed(:sample_data)
  defp log, do: Repo.all(from(e in Event, order_by: e.position))
  defp rows, do: Repo.all(from(c in CommandRecord))

  defp place!(order, shop, opts \\ []) do
    {:ok, receipt} =
      EhosContract.dispatch(
        Shop,
        %PlaceOrder{order_id: order, shop_id: shop},
        [actor: seed()] ++ opts
      )

    receipt
  end

  test "the seed issues a command a person may issue, in any shop, with no Authorizer" do
    # A clerk's grant would narrow `place_order` to its shops; the seed's has none.
    place!("order-1", "shop-1")
    place!("order-2", "shop-9")

    assert {:ok, %Receipt{events: [_]}} =
             EhosContract.dispatch(Shop, %HandOver{order_id: "order-1", keeper_id: "clerk-ada"},
               actor: seed()
             )

    assert Enum.map(log(), & &1.actor) == List.duplicate("system:sample_data", 3)
  end

  test "the seed records an event a person may record" do
    place!("order-1", "shop-1")

    assert {:ok, %Receipt{}} =
             EhosContract.record(Shop, %NoteTaken{order_id: "order-1"}, actor: seed())

    assert %{type: "seed_rig.shop.note_taken", actor: "system:sample_data"} = List.last(log())
  end

  describe "refused :not_declared, with no row" do
    setup do
      place!("order-1", "shop-1")

      {:ok, _} =
        EhosContract.dispatch(Shop, %HandOver{order_id: "order-1", keeper_id: "clerk-ada"},
          actor: seed()
        )

      %{before: {length(log()), length(rows())}}
    end

    test "a command the domain's not_seeded names", %{before: before} do
      assert EhosContract.dispatch(Shop, %RefundOrder{order_id: "order-1"}, actor: seed()) ==
               {:error, :not_declared}

      assert {length(log()), length(rows())} == before
    end

    test "a command only a :system actor issues", %{before: before} do
      assert EhosContract.dispatch(Shop, %ArchiveOrder{order_id: "order-1"}, actor: seed()) ==
               {:error, :not_declared}

      assert {length(log()), length(rows())} == before
    end

    test "a command kept for the person its unit names, though nothing lists it", %{
      before: before
    } do
      assert EhosContract.dispatch(Shop, %ReleaseOrder{order_id: "order-1"}, actor: seed()) ==
               {:error, :not_declared}

      assert {length(log()), length(rows())} == before

      # Control: the :system actor passes that check, as it always has; here it is refused
      # only because the command does not name it.
      assert EhosContract.dispatch(Shop, %ReleaseOrder{order_id: "order-1"},
               actor: Actor.system(:nightly_job)
             ) == {:error, :not_declared}
    end

    test "an event only a :system actor records", %{before: before} do
      assert EhosContract.record(Shop, %StockCounted{order_id: "order-1"}, actor: seed()) ==
               {:error, :not_declared}

      assert {length(log()), length(rows())} == before
    end

    test "a query" do
      assert EhosContract.query(Shop, %OrdersOfShop{}, actor: seed()) == {:error, :not_declared}
    end
  end

  test "the seed is labelled system:<name>, so a step seeded as a :system actor replays" do
    assert Actor.label(seed()) == "system:sample_data"
    assert Actor.label(seed()) == Actor.label(Actor.system(:sample_data))

    # The row a :system actor of the same name wrote carries the same key and label as
    # this one, so the step is not issued again: the replay finds it and appends nothing.
    first = place!("order-1", "shop-1", idempotency_key: "seed:order-1")
    assert [%{issued_by: "system:sample_data", outcome: "accepted"}] = rows()

    again = place!("order-1", "shop-1", idempotency_key: "seed:order-1")
    assert again.positions == first.positions
    assert length(log()) == 1
  end

  test "a :system actor of the seed's name is no longer permitted once the kind is :seed" do
    assert EhosContract.dispatch(Shop, %PlaceOrder{order_id: "order-1", shop_id: "shop-1"},
             actor: Actor.system(:sample_data)
           ) == {:error, :not_declared}
  end
end
