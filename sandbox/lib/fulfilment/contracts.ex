defmodule Fulfilment.Contracts do
  @moduledoc """
  **Invented.** The fulfilment contracts, one per context: orders, warehouse and
  shipping. The run across them is a process module, `Fulfilment.Processes.Order`.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{Orders, []}, {Shipping, []}, {Warehouse, []}]
end
