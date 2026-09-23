defmodule EhOsContract.Web.TestHost.DataCase do
  @moduledoc """
  The sandbox case for tests that need real conformance data.

  Mirrors `EhOsContract.DataCase` in packages/eh_os_contract, one repo down: checks out the
  sandbox, and rolls back the deployment row `test_helper.exs` wrote outside
  it at boot.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias EhOsContract.Web.TestHost.Repo
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(EhOsContract.Web.TestHost.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    EhOsContract.Registry.load!()
    EhOsContract.Web.TestHost.Repo.delete_all(EhOsContract.Deployment)

    :ok
  end
end
