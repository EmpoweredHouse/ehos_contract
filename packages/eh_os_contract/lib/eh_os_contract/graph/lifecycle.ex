defmodule EhOsContract.Graph.Lifecycle do
  # An aggregate's lifecycle as a graph (plan LC4b, #99): where a new aggregate starts,
  # its statuses in the client's words, an end drawn heavier, and each declared
  # transition as an arrow named by the event that makes it.
  #
  # A process's picture goes forward through stages; this one goes round, as the
  # aggregate does — a computer issued, returned, cleaned and issued again for years.
  # It is the reader's picture of what the contract says can happen to one thing.
  #
  # **With the log over it** (`overlay: true`) each arrow says how often it was taken in
  # the period, or `never` / `not yet` as the report says it (`EhOsContract.Conformance`
  # `lifecycles`), and a move the lifecycle does not allow that happened anyway is a
  # dotted arrow from where the aggregate stood to the status it stayed in. The numbers
  # are the report's: this module counts nothing of its own.
  @moduledoc false

  alias EhOsContract.Graph.Mermaid
  alias EhOsContract.Model

  @start "start"

  @doc """
  The lifecycle of aggregate `name` of `contract` as data:
  `EhOsContract.Graph.Mermaid.graph()`. `opts`: `overlay: true` lays the log over it,
  over `:since` and `:until`; `lifecycles:` gives the report's `lifecycles` already
  computed (`EhOsContract.Conformance.lifecycles/2`), so a screen drawing several
  reads the log once. Raises when the contract has no such aggregate, or it declares
  no lifecycle.
  """
  @spec build(module() | map(), atom(), keyword()) :: Mermaid.graph()
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

    nodes =
      [%{id: @start, kind: :start, label: " "}] ++
        for s <- lifecycle.statuses do
          # One id for a status whatever its kind, so an arrow finds an end too.
          %{
            Mermaid.graph_node(:status, s.name, s.label)
            | kind: if(s.final, do: :status_end, else: :status)
          }
        end

    declared =
      for(i <- lifecycle.initial, do: {nil, i.on, i.status}) ++
        for t <- lifecycle.transitions, do: {t.from, t.event, t.to}

    edges =
      for {from, event, to} <- declared do
        Mermaid.edge(id(from), id(to),
          label: label(labels, event, count(observed, from, event, to))
        )
      end

    undeclared =
      for %{from: from, event: event, count: count} <- (observed && observed.undeclared) || [] do
        at = from && from.name

        Mermaid.edge(id(at), id(at),
          line: :dotted,
          label: label(labels, event.name, "not declared, #{count}x")
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

  # How the report reads an arrow: taken so many times, not taken yet while an
  # aggregate still stands where it can be, or never.
  defp count(nil, _from, _event, _to), do: nil

  defp count(observed, from, event, to) do
    same = fn t -> {t.from && t.from.name, t.event.name, t.to.name} == {from, event, to} end
    transition = Enum.find(observed.transitions, same)

    cond do
      # A report of another declaration than the one drawn: no number rather than a crash.
      transition == nil -> nil
      transition.count > 0 -> "#{transition.count}x"
      Enum.any?(observed.pending, same) -> "not yet"
      Enum.any?(observed.untraversed, same) -> "never"
      true -> "0x"
    end
  end

  defp id(nil), do: @start
  defp id(status), do: Mermaid.id(:status, status)

  defp label(labels, event, nil), do: ~s("#{Mermaid.escape(Map.get(labels, event, "#{event}"))}")

  defp label(labels, event, count),
    do: ~s("#{Mermaid.escape(Map.get(labels, event, "#{event}"))} · #{count}")
end
