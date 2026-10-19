defmodule Fulfilment.DoorTest do
  @moduledoc """
  Three levels of access on one request path, each with its own answer, on the
  warehouse's pick lists:

  | Level | Whose | Answer on refusal |
  |---|---|---|
  | who is this | the credential, verified by `EhOsContract.Auth.Plug` | 401 |
  | may they confirm a pick at all | the capability granted | 403 `missing_capability` |
  | may they act in **this warehouse** | the grant's scope (`scope: :warehouse_id`) | 403 `outside_scope` |

  and past the door the business's own rule, that a pick list is confirmed by the
  picker it is assigned to (`actor_is`), answered 422 like any other refusal.
  """

  use EhOsContractHost.DataCase, async: false
  use EhOsContract.Auth.Testing

  import Phoenix.ConnTest
  import Plug.Conn

  alias EhOsContract.{Actor, Event, Testing}
  alias Fulfilment.Contracts.{Orders, Shipping, Warehouse}
  alias Fulfilment.Contracts.Orders.Commands.{ConfirmPayment, PlaceOrder}
  alias Fulfilment.Contracts.Warehouse.Commands.AssignPickList

  @endpoint EhOsContractHostWeb.Endpoint

  @confirm "fulfilment.confirm_pick"
  @list %{warehouse_id: "w-1", order_id: "order-1"}

  defp command(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/fulfilment/commands/#{capability}", Jason.encode!(body))
  end

  defp answer(conn), do: {conn.status, Jason.decode!(conn.resp_body)}

  # A picker granted the capabilities in `warehouses`.
  defp picker(id, warehouses) do
    capabilities = ~w(fulfilment.confirm_pick fulfilment.pack_parcel)
    credential(id, capabilities, Map.new(capabilities, &{&1, %{"warehouse_id" => warehouses}}))
  end

  defp picked, do: Repo.all(from(e in Event, where: e.type == "fulfilment.warehouse.picked"))

  # Order 1 placed and paid, its pick list opened by the policy and assigned to Ada, as the
  # desk and the floor would leave it.
  setup do
    Testing.drain()

    desk =
      Actor.credential("desk-cy", ["fulfilment.place_order", "fulfilment.confirm_payment"])

    {:ok, _} =
      EhOsContract.dispatch(
        Orders,
        %PlaceOrder{order_id: "order-1", warehouse_id: "w-1", items: 3},
        actor: desk
      )

    {:ok, _} = EhOsContract.dispatch(Orders, %ConfirmPayment{order_id: "order-1"}, actor: desk)
    Testing.drain()

    {:ok, _} =
      EhOsContract.dispatch(
        Warehouse,
        struct!(AssignPickList, Map.put(@list, :picker_id, "picker-ada")),
        actor:
          Actor.credential("lead-lu", ["fulfilment.assign_pick_list"], %{
            "fulfilment.assign_pick_list" => %{"warehouse_id" => ["w-1"]}
          })
      )

    :ok
  end

  test "no credential: 401, before any decision" do
    decisions = fn -> Repo.query!("SELECT count(*) FROM eh_os_contract_auth_decisions").rows end
    before = decisions.()

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/fulfilment/commands/#{@confirm}", Jason.encode!(@list))

    assert conn.status == 401
    assert decisions.() == before
  end

  test "a credential without the capability: 403, and nothing in the log" do
    assert answer(command(credential("u-clerk", []), @confirm, @list)) ==
             {403, %{"refused" => "missing_capability"}}

    assert picked() == []
  end

  test "a picker of another warehouse: 403 outside the grant, not a rule the business decides" do
    assert answer(command(picker("picker-ada", ["w-2"]), @confirm, @list)) ==
             {403, %{"refused" => "outside_scope"}}

    assert picked() == []
  end

  test "a colleague in the same warehouse: the business refuses, by whom the list is assigned to" do
    assert answer(command(picker("picker-bob", ["w-1"]), @confirm, @list)) ==
             {422, %{"rejected" => "confirmed_by_its_picker"}}

    assert picked() == []
  end

  test "the picker it is assigned to, in their warehouse: confirmed" do
    assert command(picker("picker-ada", ["w-1"]), @confirm, @list).status == 200
    assert [%Event{actor: "actor:picker-ada"}] = picked()
  end

  test "every entry point of the three contracts refuses a credential without its capability" do
    order = %{order_id: "order-2"}

    entries = %{
      "fulfilment.place_order" => %{order_id: "order-2", warehouse_id: "w-1", items: 3},
      "fulfilment.confirm_payment" => order,
      "fulfilment.cancel_order" => order,
      "fulfilment.assign_pick_list" => Map.put(@list, :picker_id, "picker-bob"),
      @confirm => @list,
      "fulfilment.pack_parcel" => Map.put(@list, :weight_grams, 1_200),
      "fulfilment.dispatch_parcel" => %{order_id: "order-1"}
    }

    assert assert_every_entry_refuses(
             [Orders, Warehouse, Shipping],
             Map.new(entries, fn {capability, body} ->
               {capability, &command(&1, capability, body)}
             end)
           ) == :ok
  end

  test "what only the policies and the carrier do is not a door, whatever the credential names" do
    token =
      credential("u-mistaken", [
        "fulfilment.open_pick_list",
        "fulfilment.book_shipment",
        "fulfilment.delivered"
      ])

    assert command(token, "fulfilment.open_pick_list", %{@list | order_id: "order-3"}).status ==
             404

    assert command(token, "fulfilment.book_shipment", %{
             order_id: "order-3",
             service: "parcel",
             weight_grams: 1
           }).status == 404

    # The carrier's recording is its integration's alone: a person's credential that
    # names it is refused.
    delivered =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/fulfilment/records/fulfilment.delivered",
        Jason.encode!(%{order_id: "order-1"})
      )

    assert delivered.status in [403, 404]
    assert Repo.all(from(e in Event, where: e.type == "fulfilment.shipping.delivered")) == []
  end
end
