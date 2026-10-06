defmodule EhOsContract.Web do
  @moduledoc """
  The dashboard's public surface: a mountable router, the screens it routes
  to, and a resolver behaviour through which the host decides who may see
  them. No login and no accounts: who somebody is belongs to the host.

  **Every module `eh_os_contract_dashboard/2` names in a `live`/`get`/`match` route has
  to be exported, not just `Router` itself** — Phoenix's router macros
  compile a literal module reference into whatever router calls them, so
  the reference lands in the *caller's* compiled code, not this package's.
  A host with its own strict top-level boundary (`eh_os_contract_host`'s own
  `EhOsContractHost.Application, top_level?: true` found this the first time
  anything outside `packages/eh_os_contract_web`'s own test host actually mounted the
  macro for real) checks that reference like any other — there is no way
  to route to a LiveView Phoenix does not know the name of.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      Api.AsyncAPI,
      Api.Conformance,
      Api.Graph,
      Api.Model,
      Api.OpenAPI,
      Resolver,
      Router,
      Router.RedirectToContract,
      Authentication,
      Live.ContractStatus,
      Live.Graph
    ]
end
