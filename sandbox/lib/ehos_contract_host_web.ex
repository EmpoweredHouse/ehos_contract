defmodule EhosContractHostWeb do
  @moduledoc """
  The host's own web layer — plumbing, not content. Everything the
  dashboard renders lives in `packages/ehos_contract_web`; this tree is only what a
  host has to supply for it: an `Endpoint`, a session, CSRF, and one route
  calling `EhosContract.Web.Router.ehos_contract_dashboard/2`.

  A separate boundary from the case studies' (`Lending`, `Billing`, `Fulfilment`) for the
  same reason those are separate from each other: this is not domain code, and giving
  it its own boundary is what makes that a fact `boundary` checks rather
  than a claim in a moduledoc.
  """

  use Boundary, deps: [EhosContract, EhosContract.Auth, EhosContract.Web], exports: []
end
