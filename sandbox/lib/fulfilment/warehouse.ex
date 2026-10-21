defmodule Fulfilment.Warehouse do
  @moduledoc """
  **Invented.** The implementation of `Fulfilment.Contracts.Warehouse`: the pick list's
  decision, and the policy that opens one for a paid order.
  """

  use Boundary,
    deps: [EhOsContract, Fulfilment.Contracts],
    exports: [PickList, OpenPickListWhenPaid]
end
