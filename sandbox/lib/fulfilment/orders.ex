defmodule Fulfilment.Orders do
  @moduledoc "**Invented.** The implementation of `Fulfilment.Contracts.Orders`."
  use Boundary, deps: [EhOsContract, Fulfilment.Contracts], exports: [Order]
end
