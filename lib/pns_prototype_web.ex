defmodule PnsPrototypeWeb do
  @moduledoc """
  The host's own web layer — plumbing, not content. Everything the
  dashboard renders lives in `packages/pns_web`; this tree is only what a
  host has to supply for it: an `Endpoint`, a session, CSRF, and one route
  calling `PNS.Web.Router.pns_dashboard/2`.

  A separate boundary from `Taxvision`/`Rehmed` for the same reason those
  are separate from each other: this is not client-domain code, and giving
  it its own boundary is what makes that a fact `boundary` checks rather
  than a claim in a moduledoc.
  """

  use Boundary, deps: [PNS, PNS.Web], exports: []
end
