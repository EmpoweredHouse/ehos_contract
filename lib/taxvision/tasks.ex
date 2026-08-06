defmodule Taxvision.Tasks do
  @moduledoc """
  Monthly tasks. This module **owns its own tables** and nobody else touches them
  (ADR §5-6).

  No joins to another module's tables and no views over them. The prohibition
  raises the query count, and generated code will not notice five hundred — which
  is why N+1 is a named risk rather than a surprise (notes §14).
  """

  use Boundary,
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts, Taxvision.Periods],
    exports: [Task]

  @doc "The task template for a legal form. Changes take effect from the next month (P3)."
  @spec template(String.t()) :: [String.t()]
  def template("JDG"),
    do: ["Pobrać wyciągi", "Skompletować faktury KSeF", "Zaksięgować dokumenty", "Wysłać deklarację"]

  def template(_), do: ["Skompletować dokumenty", "Zaksięgować dokumenty", "Wysłać deklarację"]
end

defmodule Taxvision.Tasks.Task do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_tasks" do
    field :company_id, :string
    field :period_id, :binary_id
    field :name, :string
    field :status, :string, default: "open"
    # A copy from `Taxvision.Periods`, not a join to it. Strategic duplication:
    # there is one named source of truth and there may be many copies.
    field :due_on, :date
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Taxvision.Tasks.OnRegistryDataConsistent do
  @moduledoc """
  A **synchronous** handler: it touches only its own tables in the same database,
  so it runs inside the state change's transaction.

  If it raised, the whole transaction would roll back and the caller would get an
  error. That is correct precisely because there is no outside I/O here: there is
  nothing to retry, because nothing happened. The same mechanism applied to
  sending mail would let a side concern veto a business operation — which is why
  such handlers cannot be synchronous.
  """

  use PNS.Handler,
    contract: Taxvision.Contracts.AccountingMonth,
    event: :registry_data_consistent,
    publishes: [:monthly_tasks_generated]

  alias Taxvision.Tasks.Task

  @impl PNS.Handler
  def handle(%{company_id: company_id, period_id: period_id}, _ctx) do
    names = Taxvision.Tasks.template("JDG")
    now = DateTime.utc_now()
    # **A function call, not a join.** The no-cross-module-join rule costs exactly
    # this one query, and that is the whole truth of it: it cannot be worked
    # around, because `Taxvision.Periods` does not export its schema.
    accounting_period = Taxvision.Periods.fetch_by_id!(period_id)

    entries =
      for name <- names do
        %{
          id: Ecto.UUID.generate(),
          company_id: company_id,
          period_id: period_id,
          name: name,
          status: "open",
          due_on: accounting_period.ends_on,
          inserted_at: now
        }
      end

    {count, _} = Taxvision.Repo.insert_all(Task, entries)

    {:ok,
     [
       PNS.event(:monthly_tasks_generated, %{
         company_id: company_id,
         period_id: period_id,
         task_count: count
       })
     ]}
  end
end

