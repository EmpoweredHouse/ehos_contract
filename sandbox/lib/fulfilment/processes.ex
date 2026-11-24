defmodule Fulfilment.Processes do
  @moduledoc "**Invented.** Fulfilment's run: one order, from its placing to its delivery."
  use Boundary, deps: [EhosContract, Fulfilment.Contracts], exports: []
end
