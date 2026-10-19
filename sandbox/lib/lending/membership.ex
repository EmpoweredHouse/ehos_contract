defmodule Lending.Membership do
  @moduledoc """
  **Invented.** The implementation of `Lending.Contracts.Membership`: the membership's
  decision, which is pure, and the member directory with its query, the one table of
  this tree.
  """

  use Boundary,
    deps: [EhOsContract, Lending.Contracts],
    exports: [Registration, Directory, MemberContact]
end
