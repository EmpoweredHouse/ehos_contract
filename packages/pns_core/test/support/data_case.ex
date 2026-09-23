defmodule PNS.DataCase do
  @moduledoc """
  The sandbox case for the engine's own tests.

  The counterpart of what used to be `Taxvision.DataCase` and is now only the
  client's. The difference is not cosmetic: this one knows nothing about a
  company, a period or an accounting month, so a test using it cannot accidentally
  depend on the client tree being there.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  using do
    quote do
      import Ecto.Query
      import PNS.DataCase

      alias PNS.TestRepo, as: Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PNS.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    PNS.Registry.load!()

    # Deployments are written by the **boot**, that is, outside the sandbox — those
    # rows commit to the test database permanently and would leak into every test
    # that claims anything about deployments. The cleanup runs inside the sandbox
    # transaction, so it rolls back after the test, and production behaviour is
    # untouched: there, writing at boot is exactly right.
    PNS.TestRepo.delete_all(PNS.Deployment)

    :ok
  end

  @doc "Every event of a type, oldest first."
  def events_of(type) do
    name = to_string(type)
    PNS.TestRepo.all(from(e in PNS.Event, where: e.type == ^name, order_by: e.occurred_at))
  end
end
