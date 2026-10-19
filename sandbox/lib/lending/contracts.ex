defmodule Lending.Contracts do
  @moduledoc """
  **Invented.** The library's contracts, one per context: membership and
  circulation. The runs across them are process modules, `Lending.Processes`.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{Circulation, []}, {Membership, []}]
end
