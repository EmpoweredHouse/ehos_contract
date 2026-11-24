defmodule EhosContractHost.DataCase do
  @moduledoc false

  use Boundary, top_level?: true, deps: [EhosContract, EhosContractHost.Repo], exports: []
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query

      alias EhosContractHost.Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EhosContractHost.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    EhosContract.Registry.load!()

    # Deployments are written by the **application boot**, that is, outside the
    # sandbox — those rows commit to the test database permanently and would leak
    # into every test that claims anything about deployments. The cleanup runs
    # inside the sandbox transaction, so it rolls back after the test, and
    # production behaviour is untouched: there, writing at boot is exactly right.
    EhosContractHost.Repo.delete_all(EhosContract.Deployment)

    :ok
  end
end
