defmodule EhosContract.Web.TestHost.DataCase do
  @moduledoc """
  The sandbox case for tests that need real conformance data.

  Mirrors `EhosContract.DataCase` in packages/ehos_contract, one repo down: checks out the
  sandbox, and rolls back the deployment row `test_helper.exs` wrote outside
  it at boot.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias EhosContract.Web.TestHost.Repo
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(EhosContract.Web.TestHost.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    EhosContract.Registry.load!()
    EhosContract.Web.TestHost.Repo.delete_all(EhosContract.Deployment)

    :ok
  end
end
