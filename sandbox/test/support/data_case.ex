defmodule Taxvision.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Ecto.Query

  using do
    quote do
      import Ecto.Query
      import Taxvision.DataCase

      alias Taxvision.Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Taxvision.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    EhOsContract.Registry.load!()

    # Deployments are written by the **application boot**, that is, outside the
    # sandbox — those rows commit to the test database permanently and would leak
    # into every test that claims anything about deployments. The cleanup runs
    # inside the sandbox transaction, so it rolls back after the test, and
    # production behaviour is untouched: there, writing at boot is exactly right.
    Taxvision.Repo.delete_all(EhOsContract.Deployment)

    # A period's dates are its row's (`Taxvision.Periods`); its name is what the
    # facts carry since E9c, held to a format by the domain's `:period`. The rows
    # the tests read are made here, and `periods_test.exs` makes its own.
    for month <- ~w(2026-05 2026-06 2026-07 2026-08), do: Taxvision.Periods.ensure!(month)

    :ok
  end

  @doc "A canonical period, by name. Created in setup for the months the tests use."
  def period!(name), do: Taxvision.Periods.ensure!(name)

  def events_of(type) do
    name = to_string(type)

    Taxvision.Repo.all(
      from(e in EhOsContract.Event, where: e.type == ^name, order_by: e.occurred_at)
    )
  end
end
