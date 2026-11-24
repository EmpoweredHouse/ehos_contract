defmodule Lending.Circulation do
  @moduledoc """
  **Invented.** The implementation of `Lending.Contracts.Circulation`: the copy's, the
  loan's and the hold's decisions, which are pure, and the overdue chase.
  """

  use Boundary,
    deps: [EhosContract, Lending.Contracts],
    exports: [Copy, Loan, CopyHold, OverdueChase]
end
