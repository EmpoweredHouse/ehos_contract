defmodule Taxvision.Periods do
  @moduledoc """
  The named source of truth for what an accounting period is.

  This module exists to answer one question — *when does "2026-07" start and
  end* — for every other module that needs it, without any of them touching this
  table.

  ## Why `exports: []` is the whole point

  Every other module in this tree exports its schema, so a sibling that declares
  the dependency could join to it. This one exports **nothing**. The schema
  `Period` is unreachable from outside, which makes a cross-module join not
  forbidden but **inexpressible** — the same move that turned "an event in two
  processes" from a check into an impossibility.

  What siblings get instead is `fetch!/1`: a function call, not a join. That is
  the answer to the open question of whether the no-join rule is bearable. It is,
  and its price is named rather than hidden: one extra query per caller per run,
  which is the N+1 the technology notes predicted. `Taxvision.Tasks` and
  `Taxvision.AccountingMonth` both need the closing date of the same period, and
  both pay for it separately.

  The alternative the doctrine rejects is a shared table read by everyone, which
  buys one query and sells the ability to ever change this shape.

  > **28 September 2026, E9c.** The section below describes v1. Since E9c a period's
  > **name** is its identifier (plan, the decisions before E9c): the facts carry
  > "2026-07", the domain's `:period` holds it to YYYY-MM (`name?/1`), and the timer on
  > the first of the month works the next one out with `next/1`. The row keeps the
  > dates. What follows is kept as it was written, since it is what E9c changed.

  ## Names at the edge, identifiers inside

  A name is what a person has: someone types or selects "2026-07". An identifier is what
  a fact carries. The translation happens **once, at the request edge**, and everything
  downstream — payloads, the run key, the module tables — holds the identifier.

  That is what makes canonicalisation complete rather than advisory. While events carried
  the name, `"2026-7"` beside `"2026-07"` was merely discouraged; with a foreign key it
  stops being possible. The price is that a run key reads `accounting_month|c-1|<uuid>`
  and no longer says which month, so reading the log by eye needs a join. Accepted, and
  narrower than it first sounds: the engine's promise is that the key is **reproducible**
  from the log, not that it is legible — and the evidence report never prints a run key,
  because which runs are silent is a question about one company.
  """

  use Boundary, deps: [Taxvision.Repo, Taxvision.Domain], exports: []

  import Ecto.Query

  alias Taxvision.Periods.Period

  @type name :: String.t()
  @type id :: Ecto.UUID.t()
  @type t :: %{id: id(), name: name(), starts_on: Date.t(), ends_on: Date.t()}

  @doc """
  The period identified by its canonical name, raising when it does not exist.

  Raising rather than returning `nil` is deliberate: a handler that derives a
  deadline from a period cannot sensibly continue without one, and a silent `nil`
  would travel into a date column as a missing deadline nobody notices.
  """
  @spec fetch!(name()) :: t()
  def fetch!(name) do
    one(dynamic([p], p.name == ^name)) ||
      raise ArgumentError,
            "no period named #{inspect(name)}. Periods are canonical rows, not strings " <>
              "parsed on the fly, so a period has to exist before anything can be booked into it."
  end

  @spec one(Ecto.Query.dynamic_expr()) :: t() | nil
  defp one(condition) do
    Taxvision.Repo.one(
      from(p in Period,
        where: ^condition,
        select: %{id: p.id, name: p.name, starts_on: p.starts_on, ends_on: p.ends_on}
      )
    )
  end

  @doc """
  Creates the period if it is not there yet, and returns it either way.

  Derives the date range from a `YYYY-MM` name, which is the one place in this
  module that knows the naming convention. Everything else works off the row.
  """
  @spec ensure!(name()) :: t()
  def ensure!(name) do
    with {:ok, starts_on} <- month_start(name) do
      Taxvision.Repo.insert_all(
        Period,
        [
          %{
            id: Ecto.UUID.generate(),
            name: name,
            starts_on: starts_on,
            ends_on: Date.end_of_month(starts_on)
          }
        ],
        on_conflict: :nothing,
        conflict_target: :name
      )

      fetch!(name)
    else
      :error ->
        raise ArgumentError, "period name #{inspect(name)} is not in YYYY-MM form"
    end
  end

  @doc """
  The name of the month after `name`: "2026-08" after "2026-07", "2027-01" after
  "2026-12". Pure, so a process manager's timer can work out the next period to
  check without asking the database (plan, the decisions before E9c).
  """
  @spec next(name()) :: name()
  def next(name) do
    case month_start(name) do
      {:ok, start} -> start |> Date.end_of_month() |> Date.add(1) |> Calendar.strftime("%Y-%m")
      :error -> raise ArgumentError, "period name #{inspect(name)} is not in YYYY-MM form"
    end
  end

  @doc """
  Whether `name` names a month, "YYYY-MM": the invariant of the domain's `:period`
  (`Taxvision.Periods.Name`), and the one place that knows the convention.
  """
  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name),
    do: Regex.match?(~r/^\d{4}-\d{2}$/u, name) and month_start(name) != :error

  def name?(_name), do: false

  @spec month_start(name()) :: {:ok, Date.t()} | :error
  defp month_start(name) do
    with [year, month] <- String.split(name, "-"),
         {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {:ok, date} <- Date.new(year, month, 1) do
      {:ok, date}
    else
      _ -> :error
    end
  end
end

defmodule Taxvision.Periods.Name do
  @moduledoc "The invariant of `Taxvision.Domain`'s value `:period`: a month, named YYYY-MM."

  use Taxvision.Domain, value: :period

  @impl true
  def named_by_month(name), do: Taxvision.Periods.name?(name)
end

defmodule Taxvision.Periods.Period do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_periods" do
    field(:name, :string)
    field(:starts_on, :date)
    field(:ends_on, :date)
  end
end
