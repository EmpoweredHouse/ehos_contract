defmodule Taxvision.Repo do
  @moduledoc """
  One Postgres, one transaction (ADR §5-6).

  This is also where the skeleton of the **deferred** data-ownership check lives.
  Decision 008 defers enforcing boundaries from CI to run time, and the review set
  a condition: the deferral is only safe if the check can be added later.

  Checked on 4 August against Ecto 3.14.1: it can. `prepare_query/3` receives the
  whole `%Ecto.Query{}` before execution, so every touched table comes out
  structurally from `from` and `joins` — without parsing SQL. Retrofitting means
  overriding one callback, not changing how modules reach the repo.

  A limit worth knowing: the hook does **not** fire for `insert/2`, `update/2` or
  `delete/2` on a changeset, nor for raw SQL. The first requires naming another
  module's schema, so `boundary` catches it at compile time. The second is the one
  genuinely invisible entrance — and exactly the case the review deferred on the
  argument that models generate idiomatic Ecto rather than SQL in strings.
  """

  use Boundary, deps: [], exports: []
  use Ecto.Repo, otp_app: :pns_prototype, adapter: Ecto.Adapters.Postgres

  @impl true
  def prepare_query(_operation, query, opts) do
    if Process.get(:pns_trace_tables) do
      Process.put(:pns_touched_tables, tables(query) ++ (Process.get(:pns_touched_tables) || []))
    end

    {query, opts}
  end

  @doc """
  The tables a query touches. The trap that quietly breaks this check: a join's
  table name is not in `source` — a join returns `{nil, SchemaModule}`, so without
  `__schema__(:source)` a join looks like `nil` and the check falls silent exactly
  where it is meant to shout.
  """
  @spec tables(Ecto.Query.t()) :: [String.t()]
  def tables(%Ecto.Query{} = query) do
    [query.from.source | Enum.map(query.joins, & &1.source)]
    |> Enum.map(&source_to_table/1)
    |> Enum.reject(&is_nil/1)
  end

  defp source_to_table({nil, module}) when is_atom(module) and not is_nil(module),
    do: module.__schema__(:source)

  defp source_to_table({table, _module}) when is_binary(table), do: table
  defp source_to_table(%Ecto.SubQuery{query: query}), do: tables(query)
  defp source_to_table(_), do: nil
end
