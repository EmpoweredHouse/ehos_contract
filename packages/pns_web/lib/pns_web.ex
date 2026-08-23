defmodule PNS.Web do
  @moduledoc """
  The dashboard foundation's public surface: a mountable router, a resolver
  behaviour, and the two implementations a host needs to wire itself in —
  nothing about the content of either eventual screen.
  """

  use Boundary,
    deps: [PNS],
    exports: [
      Resolver,
      Resolvers.Default,
      Plug.Authenticate,
      Router
    ]
end
