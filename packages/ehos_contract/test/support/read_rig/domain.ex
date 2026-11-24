defmodule ReadRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `ReadRig`. The catalogue keeps the products, outside
  the log; an order names one.
  """

  use EhosContract.Domain, name: :read_rig, language: :en

  context :shop, "Shop", subdomain: :core

  actor :clerk, :human, "Clerk"

  subdomain :core, "Core", type: :core

  entity :product, "Product", context: :shop, identity: :product_id do
    field :price, :integer, label: "Price"
    field :on_sale, :boolean, label: "On sale"
    field :discount, :integer, label: "Discount per item", optional: true
  end
end
