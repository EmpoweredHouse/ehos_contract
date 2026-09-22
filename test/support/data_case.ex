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
    PNS.Registry.load!()

    # Deployments are written by the **application boot**, that is, outside the
    # sandbox — those rows commit to the test database permanently and would leak
    # into every test that claims anything about deployments. The cleanup runs
    # inside the sandbox transaction, so it rolls back after the test, and
    # production behaviour is untouched: there, writing at boot is exactly right.
    Taxvision.Repo.delete_all(PNS.Deployment)

    # A period is a **canonical row**, not a string parsed on the fly, so it has to
    # exist before anything can be booked into it. In production an admin or a
    # schedule creates it; here the setup does, because requiring it of every test
    # separately would add noise without signal.
    #
    # That the requirement actually holds is guarded by one test in
    # `periods_test.exs` — and only that one creates a period itself.
    for month <- ~w(2026-05 2026-06 2026-07 2026-08), do: Taxvision.Periods.ensure!(month)

    :ok
  end

  @doc "A token for dev and tests. A real provider does not hand out its signing secret."
  def token(claims), do: PNS.Auth.LocalToken.sign(claims)

  # `sub` is an **opaque, stable identifier**, not an email address. The first
  # version of this fixture put an email here, and because of that every event in
  # the log carried personal data in the `actor` column — even though the seam was
  # designed correctly. An email changes when somebody changes their name and a
  # `sub` does not, so an email in this role also breaks audit continuity.
  @accountant_sub "018f2a3c-7b4e-7c21-9d55-0a1b2c3d4e5f"
  @client_sub "018f2a3c-9d10-7f88-b402-6e7f8a9b0c1d"

  def accountant_sub, do: @accountant_sub
  def client_sub, do: @client_sub

  def accountant(company_id \\ "c-1"),
    do: token(%{"sub" => @accountant_sub, "company_id" => company_id, "roles" => ["accounting"]})

  def client(company_id \\ "c-1"),
    do: token(%{"sub" => @client_sub, "company_id" => company_id, "roles" => ["client"]})

  @doc "A canonical period. Created in setup, because without one no month can be opened."
  def period!(name), do: Taxvision.Periods.ensure!(name)

  @doc """
  The identifier of a canonical period, by name.

  Since 6 August a payload carries `period_id`, so a test that emits an event needs the
  identifier rather than the name. It lives here rather than in each test file for the
  reason that motivated the change: a uuid written by hand is a uuid that can be written
  slightly wrong, which is the class of mistake a foreign key exists to end.

  A command still takes the **name** — `Taxvision.Api.open_month/2` resolves it — because
  that is the edge where a person's input arrives.
  """
  def period_id!(name), do: period!(name).id

  @doc """
  The run key for a company and a period name.

  Built here from the period's identifier rather than spelled out in an assertion, so the
  tests say *which run* they mean and not *which uuid* — the readability that moving to an
  identifier cost is recovered in the fixture rather than paid for in every test.
  """
  def instance(company_id, period_name),
    do: "accounting_month|#{company_id}|#{period_id!(period_name)}"

  def events_of(type) do
    name = to_string(type)
    Taxvision.Repo.all(from(e in PNS.Event, where: e.type == ^name, order_by: e.occurred_at))
  end
end
