defmodule EhOsContract.Web do
  @moduledoc """
  A conformance dashboard for `EhOsContract`, mounted in the host's own router.

  Two screens: each contract's conformance (the four questions the report answers) and
  the graphs (each domain's context map and system, a contract's full graph and a process
  module's stages and promises, with the log laid over them). Beside them, a read-only JSON API serves the conformance
  report and the generated model, OpenAPI, AsyncAPI and graph documents.

    * `EhOsContract.Web.Router.eh_os_contract_dashboard/2` mounts the screens, and
      `EhOsContract.Web.Router.eh_os_contract_api/2` the JSON API.
    * `EhOsContract.Web.Resolver` is what the host implements to decide who may see
      either. There is no default, no login and no accounts: who somebody is belongs to
      the host.
  """

  # Every module `eh_os_contract_dashboard/2` names in a `live`/`get`/`match` route has
  # to be exported, not just `Router` itself: Phoenix's router macros compile a literal
  # module reference into whatever router calls them, so the reference lands in the
  # caller's compiled code, not this package's. A host with its own strict top-level
  # boundary (`eh_os_contract_host`'s `EhOsContractHost.Application, top_level?: true`
  # found this the first time anything outside this package's own test host mounted the
  # macro) checks that reference like any other.

  use Boundary,
    deps: [EhOsContract, EhOsContract.GraphRenderer],
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
