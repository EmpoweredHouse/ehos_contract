defmodule Taxvision.AccountingMonth do
  @moduledoc """
  The core aggregate from section 12 of the workshop: a Collection -> Matching ->
  Result stepper, opening conditional on a positive registry check, a deadline on
  every step, and settlement one month behind.

  Only the opening is implemented in this slice. The later steps are declared in
  the contract and unhandled — deliberately.
  """

  use Boundary,
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts, Taxvision.Periods],
    exports: [Month]
end

defmodule Taxvision.AccountingMonth.Month do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_accounting_months" do
    field(:company_id, :string)
    field(:period_id, :binary_id)
    field(:status, :string)
    # The same answer as `Taxvision.Tasks.Task.due_on`, from the same source, in a
    # second copy. This is the "two modules needing the same data" shape — and the
    # price of the no-join rule: a second query for the same period.
    field(:closes_on, :date)
    field(:opened_at, :utc_datetime_usec)
  end
end

defmodule Taxvision.AccountingMonth.OnMonthlyTasksGenerated do
  @moduledoc """
  A synchronous handler. The order from the workshop matters here and is not
  accidental: tasks are created **before** the month opens (checks first, then
  tasks, and the opening last) — so a month without tasks does not exist.
  """

  use PNS.Handler,
    contract: Taxvision.Contracts.AccountingMonth,
    event: :monthly_tasks_generated,
    publishes: [:accounting_month_opened]

  alias Taxvision.AccountingMonth.Month

  @impl PNS.Handler
  def handle(%{company_id: company_id, period_id: period_id}, _ctx) do
    accounting_period = Taxvision.Periods.fetch_by_id!(period_id)

    Taxvision.Repo.insert!(%Month{
      company_id: company_id,
      period_id: period_id,
      status: "open",
      closes_on: accounting_period.ends_on,
      opened_at: DateTime.utc_now()
    })

    {:ok, [PNS.event(:accounting_month_opened, %{company_id: company_id, period_id: period_id})]}
  end
end
