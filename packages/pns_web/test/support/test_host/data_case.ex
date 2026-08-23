defmodule PNS.Web.TestHost.DataCase do
  @moduledoc """
  The sandbox case for tests that need real conformance data.

  Mirrors `PNS.DataCase` in packages/pns_core, one repo down: checks out the
  sandbox, and rolls back the deployment row `test_helper.exs` wrote outside
  it at boot.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias PNS.Web.TestHost.Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PNS.Web.TestHost.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    PNS.Registry.load!()
    PNS.Web.TestHost.Repo.delete_all(PNS.Deployment)

    :ok
  end
end
