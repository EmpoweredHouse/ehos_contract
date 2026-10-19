defmodule Fulfilment.Processes do
  @moduledoc "**Invented.** Fulfilment's run: one order, from its placing to its delivery."
  use Boundary, deps: [EhOsContract, Fulfilment.Contracts], exports: []
end
