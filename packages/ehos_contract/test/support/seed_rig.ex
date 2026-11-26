defmodule SeedRig do
  @moduledoc """
  **An engine fixture, and invented.** A shop whose environments for previews load sample
  orders as the domain's seed actor, written to exercise what dispatch permits that actor
  (#683) and nothing more: no workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhosContract], exports: [Domain, Shop]
end
