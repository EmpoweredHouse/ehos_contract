defmodule ReadRig.Orders do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  Placing an order reads the product it names: the order is refused for a product no
  longer on sale, and its total is the product's price as read. A gift order reads it
  too, and adds the wrapping; the host supplies both the product and the wrapping. Cancelling one reads nothing, so
  its decision keeps two arguments.
  """

  use EhosContract.Contract, domain: ReadRig.Domain, context: :shop, id: "read_rig.orders"

  aggregate :order, "Order" do
    identity :order_id

    state do
      field :placed, :boolean, default: false
    end

    invariant :product_on_sale, "An order is placed only for a product on sale"
    invariant :order_placed_first, "Only a placed order is cancelled"

    command :place_order, "Place an order",
      by: :clerk,
      emits: :placed,
      rejects: :product_on_sale,
      reads: [product: :product_id] do
      field :product_id, {:id, :product}
      field :quantity, :integer
    end

    command :place_gift_order, "Place a gift order",
      by: :clerk,
      emits: :placed,
      rejects: :product_on_sale,
      reads: [product: :product_id] do
      field :product_id, {:id, :product}, supplied_by: :host
      field :quantity, :integer
      field :wrapping, :integer, supplied_by: :host
    end

    command :cancel_order, "Cancel the order",
      by: :clerk,
      emits: :cancelled,
      rejects: :order_placed_first

    event :placed, "Order placed" do
      field :product_id, {:id, :product}
      field :total, :integer
    end

    event :cancelled, "Order cancelled"
  end

  read_model :orders, "Orders", projects: [:placed, :cancelled] do
    field :order_id, :id
  end

  query :orders_of_shop, "Orders of the shop", reads: :orders, by: :clerk

  scenario "an order totals the price of the product as read" do
    given_entity(:product, %{product_id: "product-tea", price: 4, on_sale: true})
    command :place_order, %{product_id: "product-tea", quantity: 3}
    expect :placed, %{product_id: "product-tea", total: 12}
  end

  scenario "a discount on the product lowers the total" do
    given_entity :product, %{product_id: "product-tea", price: 4, on_sale: true, discount: 1}
    command :place_order, %{product_id: "product-tea", quantity: 3}
    expect :placed, %{total: 9}
  end

  scenario "a gift order adds the wrapping to the total" do
    given_entity(:product, %{product_id: "product-tea", price: 4, on_sale: true})
    command :place_gift_order, %{product_id: "product-tea", quantity: 3, wrapping: 2}
    expect :placed, %{product_id: "product-tea", total: 14}
  end

  scenario "a product no longer on sale is not ordered" do
    given_entity(:product, %{product_id: "product-tea", price: 4, on_sale: false})
    command :place_order, %{product_id: "product-tea", quantity: 3}
    rejected :product_on_sale
  end

  scenario "an order never placed is not cancelled" do
    command :cancel_order, %{}
    rejected :order_placed_first
  end

  scenario "a placed order can be cancelled" do
    given :placed, %{product_id: "product-tea", total: 12}
    command :cancel_order, %{}
    expect :cancelled
  end

  # The read model keeps nothing: it is here so that the events have a reader.
  scenario "the shop's orders are nothing, since nothing is kept" do
    given :placed, %{product_id: "product-tea", total: 12}
    query :orders_of_shop, %{}
    answers []
  end
end

defmodule ReadRig.Order do
  @moduledoc """
  **Invented.** Decides an order on the product it read. A test can make the next
  order's append meet a stream that moved, `Process.put(:read_rig_race, true)`, so that
  dispatch decides again.
  """

  use ReadRig.Orders, aggregate: :order

  @impl true
  def place_order(%PlaceOrder{} = c, _state, %{product: product}) do
    if Process.delete(:read_rig_race), do: race(c.order_id)

    if product.on_sale do
      emit(%Placed{
        order_id: c.order_id,
        product_id: c.product_id,
        total: (product.price - (product.discount || 0)) * c.quantity
      })
    else
      reject(:product_on_sale)
    end
  end

  @impl true
  def place_gift_order(%PlaceGiftOrder{} = c, _state, %{product: product}) do
    if product.on_sale do
      emit(%Placed{
        order_id: c.order_id,
        product_id: c.product_id,
        total: product.price * c.quantity + c.wrapping
      })
    else
      reject(:product_on_sale)
    end
  end

  @impl true
  def cancel_order(%CancelOrder{order_id: id}, %State{placed: true}),
    do: emit(%Cancelled{order_id: id})

  def cancel_order(_command, _state), do: reject(:order_placed_first)

  @impl true
  def evolve(state, %Placed{}), do: %{state | placed: true}
  def evolve(state, %Cancelled{}), do: %{state | placed: false}

  # A cancellation of the same, new order, appended behind the decision's back.
  defp race(order) do
    repo = Application.fetch_env!(:ehos_contract, :repo)
    stream = EhosContract.Key.stream(:order, [order])

    {:ok, _} =
      EhosContract.Store.append(
        repo,
        [
          %{
            type: "read_rig.orders.cancelled",
            contract: "read_rig.orders",
            contract_version: "race",
            tags: ["order_id:#{order}"],
            correlation_id: Ecto.UUID.generate(),
            actor: "system:race",
            occurred_at: EhosContract.Clock.now(),
            payload: %{"order_id" => order}
          }
        ],
        {:stream, stream, 0}
      )
  end
end

defmodule ReadRig.OrdersReadModel do
  @moduledoc "**Invented.** Keeps nothing."

  use ReadRig.Orders, read_model: :orders

  @impl true
  def placed(_event), do: :ok

  @impl true
  def cancelled(_event), do: :ok
end

defmodule ReadRig.OrdersOfShop do
  @moduledoc "**Invented.** Answers nothing: nothing is kept."

  use ReadRig.Orders, query: :orders_of_shop

  @impl true
  def orders_of_shop(%OrdersOfShop{}, _ctx), do: []
end
