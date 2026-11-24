defmodule KeyRig.Shelves do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A shelf stocked, in a run of its site alone, `KeyRig.Shelving`'s: the run's key is
  at most a field long and the stream's three, so a refusal of a shelf is its stream's
  (issue #98). The run was `:shelving` inside this contract until plan DD, P2g (#228).
  """

  use EhosContract.Contract, domain: KeyRig.Domain, context: :stock, id: "key_rig.shelves"

  aggregate :shelf, "Shelf" do
    identity [:site_id, :aisle_id, :shelf_id]

    command :stock_shelf, "Stock a shelf", by: :stocker, emits: :loaded

    event :loaded, "Shelf loaded"
  end

  scenario "a shelf is stocked" do
    command :stock_shelf
    expect :loaded
  end
end

defmodule KeyRig.ShelfDecider do
  @moduledoc "**Invented.** The decider of `KeyRig.Shelves`."

  use KeyRig.Shelves, aggregate: :shelf

  @impl true
  def stock_shelf(%StockShelf{} = command, _state),
    do:
      emit(%Loaded{
        site_id: command.site_id,
        aisle_id: command.aisle_id,
        shelf_id: command.shelf_id
      })
end
