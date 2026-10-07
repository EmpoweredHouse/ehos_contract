defmodule EhOsContract.GraphRenderer.Marks do
  @moduledoc """
  What an overlay (`eh_os_contract.graph_overlay.v1`) says about one node or one
  relation, in the terms the drawing layer draws: a count, and the states it is in.

  The overlay holds only the numbers the conformance report computes, keyed by the
  document's ids, so this reads them and recounts nothing:

  | Entry | Count | States |
  | --- | --- | --- |
  | an event's `occurrences`, a process's `runs`, a unit's `aggregates` | that number | — |
  | a step (`taken`, `waiting`, `failing`, `untraversed`, `pending`) | `taken`, none for an effect | `:untraversed`, `:pending`, `:waiting` where anything waits, `:failing` where anything fails |
  | a lifecycle's transition | `count` | `:untraversed`, `:pending` |
  | a move the lifecycle does not allow | `count` | `:undeclared` |
  | traffic between two contracts | `events` | `:waiting`, `:failing` |
  | a relation several steps end at (`by_trigger`) | none | none |

  The last row is left empty on purpose: which trigger's numbers a picture shows is
  a view's choice, and the views are not specified yet (plan E13b, batch 2).
  """

  @type state :: :untraversed | :pending | :waiting | :failing | :undeclared
  @type t :: %{count: non_neg_integer() | nil, states: [state()]}

  @none %{count: nil, states: []}

  @doc "The marks of node `id`; none without an overlay or an entry."
  @spec node(map() | nil, String.t()) :: t()
  def node(nil, _id), do: @none

  def node(overlay, id) do
    case get_in(overlay, ["nodes", id]) do
      %{"occurrences" => n} -> %{count: n, states: []}
      %{"runs" => n} -> %{count: n, states: []}
      %{"aggregates" => n} -> %{count: n, states: []}
      _ -> @none
    end
  end

  @doc "The marks of relation `id`; none without an overlay or an entry."
  @spec relation(map() | nil, String.t()) :: t()
  def relation(nil, _id), do: @none

  def relation(overlay, id) do
    case get_in(overlay, ["relations", id]) do
      %{"taken" => taken} = step ->
        %{
          count: taken,
          states:
            flags(
              untraversed: step["untraversed"],
              pending: step["pending"],
              waiting: waiting?(step["waiting"]),
              failing: failing?(step["failing"])
            )
        }

      %{"count" => count, "untraversed" => untraversed, "pending" => pending} ->
        %{count: count, states: flags(untraversed: untraversed, pending: pending)}

      %{"count" => count} ->
        %{count: count, states: [:undeclared]}

      %{"events" => events, "waiting" => waiting, "failing" => failing} ->
        %{count: events, states: flags(waiting: waiting > 0, failing: failing)}

      _ ->
        @none
    end
  end

  defp waiting?(%{"lag" => lag, "timers" => timers, "effects" => effects}),
    do: lag + timers + effects > 0

  defp failing?(%{"commands" => commands, "effects" => effects, "subscription" => subscription}),
    do: commands + effects > 0 or subscription != nil

  defp flags(flags), do: for({state, true} <- flags, do: state)
end
