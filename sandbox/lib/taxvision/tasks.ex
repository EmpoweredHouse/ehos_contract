defmodule Taxvision.Tasks do
  @moduledoc """
  Monthly tasks. This module **owns its own tables** and nobody else touches them
  (ADR §5-6).

  No joins to another module's tables and no views over them. The prohibition
  raises the query count, and generated code will not notice five hundred — which
  is why N+1 is a named risk rather than a surprise (notes §14).
  """

  use Boundary,
    deps: [EhOsContract, Taxvision.Repo, Taxvision.Contracts, Taxvision.Periods],
    exports: [Task]

  @doc "The task template for a legal form. Changes take effect from the next month (P3)."
  @spec template(String.t()) :: [String.t()]
  def template("JDG"),
    do: [
      "Pobrać wyciągi",
      "Skompletować faktury KSeF",
      "Zaksięgować dokumenty",
      "Wysłać deklarację"
    ]

  def template(_), do: ["Skompletować dokumenty", "Zaksięgować dokumenty", "Wysłać deklarację"]
end

defmodule Taxvision.Tasks.Task do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_tasks" do
    field(:company_id, :string)
    field(:period_id, :binary_id)
    field(:name, :string)
    field(:status, :string, default: "open")
    # A copy from `Taxvision.Periods`, not a join to it. Strategic duplication:
    # there is one named source of truth and there may be many copies.
    field(:due_on, :date)
    field(:inserted_at, :utc_datetime_usec)
  end
end
