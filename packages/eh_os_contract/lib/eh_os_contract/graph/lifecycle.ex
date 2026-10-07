defmodule EhOsContract.Graph.Lifecycle do
  @moduledoc """
  An aggregate's lifecycle as a graph (plan LC4b, #99): where a new aggregate starts,
  its statuses in the client's words, an end drawn heavier, and each declared
  transition as an arrow named by the event that makes it.

  A process's picture goes forward through stages; this one goes round, as the
  aggregate does — a computer issued, returned, cleaned and issued again for years.
  It is the reader's picture of what the contract says can happen to one thing.

  **With the log over it** (`overlay: true`) each arrow says how often it was taken in
  the period, or `never` / `not yet` as the report says it (`EhOsContract.Conformance`
  `lifecycles`), and a move the lifecycle does not allow that happened anyway is a
  dotted arrow from where the aggregate stood to the status it stayed in. The numbers
  are the report's: this module counts nothing of its own.
  """

  alias EhOsContract.Graph.{Document, Mermaid}
  alias EhOsContract.Model

  @doc """
  The lifecycle of aggregate `name` of `contract` as data:
  `EhOsContract.Graph.Document.graph()`. `opts`: `overlay: true` lays the log over it,
  over `:since` and `:until`; `lifecycles:` gives the report's `lifecycles` already
  computed (`EhOsContract.Conformance.lifecycles/2`), so a screen drawing several
  reads the log once. Raises when the contract has no such aggregate, or it declares
  no lifecycle.
  """
  @spec build(module() | map(), atom(), keyword()) :: Document.graph()
  def build(contract, name, opts \\ []) do
    model = Model.fetch(contract)

    unit =
      Enum.find(model.units, &(&1.name == name)) ||
        raise ArgumentError,
              "#{inspect(model.module)} has no unit #{inspect(name)}; " <>
                "it has #{inspect(Enum.map(model.units, & &1.name))}"

    lifecycle =
      EhOsContract.Lifecycle.of(unit) ||
        raise ArgumentError,
              "unit #{inspect(name)} of #{inspect(model.module)} declares no lifecycle; " <>
                "those that do: #{inspect(for u <- model.units, EhOsContract.Lifecycle.of(u), do: u.name)}"

    labels = Map.new(for e <- model.events, e.unit == name, do: {e.name, e.label})
    observed = if Keyword.get(opts, :overlay, false), do: observed(model, name, opts)

    # A lifecycle's statuses are its aggregate's: two aggregates may name theirs alike.
    id = fn
      nil -> Document.id([:start, model.id, name])
      status -> Document.id([:status, model.id, name, status])
    end

    nodes =
      [%{id: id.(nil), kind: :start, name: nil, label: nil}] ++
        for s <- lifecycle.statuses do
          %{id: id.(s.name), kind: :status, name: s.name, label: s.label, final: s.final}
        end

    declared =
      for(i <- lifecycle.initial, do: {nil, i.on, i.status}) ++
        for t <- lifecycle.transitions, do: {t.from, t.event, t.to}

    edges =
      for {from, event, to} <- declared do
        Document.edge(id.(from), id.(to), :transition,
          event: event,
          label: Map.get(labels, event, "#{event}"),
          overlay: taken(observed, from, event, to)
        )
      end

    undeclared =
      for %{from: from, event: event, count: count} <- (observed && observed.undeclared) || [] do
        at = from && from.name

        Document.edge(id.(at), id.(at), :undeclared,
          event: event.name,
          label: Map.get(labels, event.name, "#{event.name}"),
          overlay: %{count: count}
        )
      end

    %{nodes: nodes, edges: edges ++ undeclared}
  end

  @doc "The same graph as a Mermaid flowchart, laid out top to bottom."
  @spec to_mermaid(module() | map(), atom(), keyword()) :: String.t()
  def to_mermaid(contract, name, opts \\ []),
    do: contract |> build(name, opts) |> Mermaid.render("TB")

  defp observed(model, name, opts) do
    opts
    |> Keyword.get_lazy(:lifecycles, fn ->
      EhOsContract.Conformance.lifecycles(model, Keyword.take(opts, [:since, :until]))
    end)
    |> Enum.find(&(&1.unit == name))
  end

  # The report's reading of an arrow: how many times it was taken, and whether it is
  # not taken yet while an aggregate still stands where it can be, or never.
  defp taken(nil, _from, _event, _to), do: nil

  defp taken(observed, from, event, to) do
    same = fn t -> {t.from && t.from.name, t.event.name, t.to.name} == {from, event, to} end

    case Enum.find(observed.transitions, same) do
      # A report of another declaration than the one drawn: no number rather than a crash.
      nil ->
        nil

      transition ->
        %{
          count: transition.count,
          pending: Enum.any?(observed.pending, same),
          untraversed: Enum.any?(observed.untraversed, same)
        }
    end
  end
end
