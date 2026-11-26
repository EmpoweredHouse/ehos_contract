defmodule SeedRig.Shop do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A clerk places an order in their shop, hands it to a keeper, and refunds it; only the
  keeper releases it. The nightly job archives orders and counts stock; a clerk notes
  what a client said. Sample data may place, hand over and note, and nothing else.
  """

  use EhosContract.Contract, domain: SeedRig.Domain, context: :shop, id: "seed_rig.shop"

  aggregate :order, "Order" do
    identity :order_id

    state do
      field :keeper_id, :id, optional: true
    end

    invariant :only_its_keeper_releases, "An order is released by the clerk who keeps it"

    command :place_order, "Place the order", by: :clerk, scope: :shop_id, emits: :placed do
      field :shop_id, :id
    end

    command :hand_over, "Hand the order to a keeper", by: :clerk, emits: :handed_over do
      field :keeper_id, :id
    end

    command :release_order, "Release the order",
      by: :clerk,
      emits: :released,
      rejects: :only_its_keeper_releases do
      actor_is :keeper_id, or_rejects: :only_its_keeper_releases
    end

    command :refund_order, "Refund the order", by: :clerk, emits: :refunded
    command :archive_order, "Archive the order", by: :nightly_job, emits: :archived

    event :placed, "Order placed" do
      field :shop_id, :id
    end

    event :handed_over, "Order handed over" do
      field :keeper_id, :id
    end

    event :released, "Order released"
    event :refunded, "Order refunded"
    event :archived, "Order archived"
    event :note_taken, "Client's note taken", recorded_by: :clerk
    event :stock_counted, "Stock counted", recorded_by: :nightly_job
  end

  read_model :orders, "Orders",
    projects: [
      :placed,
      :handed_over,
      :released,
      :refunded,
      :archived,
      :note_taken,
      :stock_counted
    ] do
    field :order_id, :id
  end

  query :orders_of_shop, "Orders of the shop", reads: :orders, by: :clerk

  scenario "a clerk places an order" do
    command :place_order, %{shop_id: "shop-1"}
    expect :placed, %{shop_id: "shop-1"}
  end

  scenario "a clerk hands the order over" do
    command :hand_over, %{keeper_id: "clerk-ada"}
    expect :handed_over, %{keeper_id: "clerk-ada"}
  end

  scenario "the keeper releases it" do
    actor :clerk
    as "clerk-ada"
    given :handed_over, %{keeper_id: "clerk-ada"}
    command :release_order
    expect :released
  end

  scenario "another clerk does not" do
    actor :clerk
    as "clerk-bo"
    given :handed_over, %{keeper_id: "clerk-ada"}
    command :release_order
    rejected :only_its_keeper_releases
  end

  scenario "a clerk refunds it" do
    command :refund_order
    expect :refunded
  end

  scenario "the nightly job archives it" do
    actor :nightly_job
    command :archive_order
    expect :archived
  end

  scenario "a clerk notes what the client said" do
    actor :clerk
    record :note_taken
    expect :note_taken
  end

  scenario "the nightly job counts stock" do
    actor :nightly_job
    record :stock_counted
    expect :stock_counted
  end

  # The read model keeps nothing: it is here so that the events have a reader.
  scenario "the shop's orders are nothing, since nothing is kept" do
    given :placed, %{shop_id: "shop-1"}
    query :orders_of_shop, %{}
    answers []
  end
end

defmodule SeedRig.Order do
  @moduledoc "**Invented.** Decides every command of an order; who may issue it is the contract's."

  use SeedRig.Shop, aggregate: :order

  @impl true
  def place_order(%PlaceOrder{order_id: id, shop_id: shop}, _state),
    do: emit(%Placed{order_id: id, shop_id: shop})

  @impl true
  def hand_over(%HandOver{order_id: id, keeper_id: keeper}, _state),
    do: emit(%HandedOver{order_id: id, keeper_id: keeper})

  @impl true
  def release_order(%ReleaseOrder{order_id: id}, _state), do: emit(%Released{order_id: id})

  @impl true
  def refund_order(%RefundOrder{order_id: id}, _state), do: emit(%Refunded{order_id: id})

  @impl true
  def archive_order(%ArchiveOrder{order_id: id}, _state), do: emit(%Archived{order_id: id})

  @impl true
  def evolve(state, %HandedOver{keeper_id: keeper}), do: %{state | keeper_id: keeper}
  def evolve(state, _event), do: state
end

defmodule SeedRig.Orders do
  @moduledoc "**Invented.** Keeps nothing."

  use SeedRig.Shop, read_model: :orders

  @impl true
  def placed(_event), do: :ok
  @impl true
  def handed_over(_event), do: :ok
  @impl true
  def released(_event), do: :ok
  @impl true
  def refunded(_event), do: :ok
  @impl true
  def archived(_event), do: :ok
  @impl true
  def note_taken(_event), do: :ok
  @impl true
  def stock_counted(_event), do: :ok
end

defmodule SeedRig.OrdersOfShop do
  @moduledoc "**Invented.** Answers nothing: nothing is kept."

  use SeedRig.Shop, query: :orders_of_shop

  @impl true
  def orders_of_shop(%OrdersOfShop{}, _ctx), do: []
end
