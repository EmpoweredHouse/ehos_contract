defmodule EhOsContract.GraphRenderer.Marks do
  # What an overlay (`eh_os_contract.graph_overlay.v1`) says about one node or one
  # relation, in the terms the drawing layer draws: a count, and the states it is in.
  #
  # The overlay holds only the numbers the conformance report computes, keyed by the
  # document's ids, so this reads them and recounts nothing:
  #
  # | Entry | Count | States |
  # | --- | --- | --- |
  # | an event's `occurrences`, a process's `runs`, a unit's `aggregates` | that number | — |
  # | a contract's drift on the domain's map (`untraversed`, `undeclared`) | none: the drift in words, nothing where there is none | `:untraversed`, `:undeclared` where there is some |
  # | a promise's verdicts | none: the verdicts in words | `:failing` when a run broke it |
  # | a promise the owner has yet to confirm (`unverified`), with or without an overlay | none: "unconfirmed" | — |
  # | a step (`taken`, `waits`, `fails`, `untraversed`, `pending`) | `taken`, none for an effect | `:untraversed`, `:pending`, `:waiting`, `:failing`, each as the overlay reads the step |
  # | a lifecycle's transition | `count` | `:untraversed`, `:pending` |
  # | a move the lifecycle does not allow | `count` | `:undeclared` |
  # | traffic between two contracts | `events` | `:waiting`, `:failing` |
  # | a relation several steps end at (`by_trigger`) | none | none |
  #
  # The last row is left empty on purpose: a relation several steps end at has a number
  # for each trigger, and the panel lists them; no one number stands for the relation.
  #
  @moduledoc false

  @type state :: :untraversed | :pending | :waiting | :failing | :undeclared
  @type t :: %{
          required(:count) => non_neg_integer() | nil,
          required(:states) => [state()],
          optional(:verdict) => String.t(),
          optional(:drift) => String.t()
        }

  @none %{count: nil, states: []}

  @doc "The marks of node `id`; none without an overlay or an entry."
  @spec node(map() | nil, String.t()) :: t()
  def node(nil, _id), do: @none

  def node(overlay, id) do
    case get_in(overlay, ["nodes", id]) do
      %{"occurrences" => n} -> %{count: n, states: []}
      %{"runs" => n} -> %{count: n, states: []}
      %{"aggregates" => n} -> %{count: n, states: []}
      %{"untraversed" => u, "undeclared" => d} -> drift(u, d)
      _ -> @none
    end
  end

  # A contract's drift in words, where it says where to go in: "2 never taken, 1 move not
  # allowed"; nothing where the log found none. A number that is not a count says nothing.
  defp drift(untraversed, undeclared) do
    some = &(is_integer(&1) and &1 > 0)
    moves = if undeclared == 1, do: "move not allowed", else: "moves not allowed"

    said =
      for {n, words} <- [{untraversed, "never taken"}, {undeclared, moves}],
          some.(n),
          do: "#{n} #{words}"

    if said == [],
      do: @none,
      else: %{
        count: nil,
        states: flags(untraversed: some.(untraversed), undeclared: some.(undeclared)),
        drift: Enum.join(said, ", ")
      }
  end

  @doc """
  The marks of `promise`, a promise node: `unconfirmed` when the document says the owner
  has yet to confirm it, which no run is judged against, overlay or not; otherwise its
  verdicts in words — `2 kept, 1 broken`, `none opened` — and `:failing` when a run broke
  it; none without an overlay or an entry.
  """
  @spec promise(map() | nil, map()) :: t()
  def promise(_overlay, %{"unverified" => true}),
    do: %{count: nil, states: [], verdict: "unconfirmed"}

  def promise(nil, _promise), do: @none

  def promise(overlay, promise) do
    case get_in(overlay, ["nodes", promise["id"]]) do
      %{"instances" => _} = verdicts ->
        %{
          count: nil,
          states: flags(failing: (verdicts["violated"] || 0) > 0),
          verdict: verdict(verdicts)
        }

      _ ->
        @none
    end
  end

  @verdicts [satisfied: "kept", violated: "broken", pending: "pending", suspended: "suspended"]

  defp verdict(verdicts) do
    said =
      for {key, words} <- @verdicts,
          n = verdicts[to_string(key)],
          is_integer(n) and n > 0,
          do: "#{n} #{words}"

    if said == [], do: "none opened", else: Enum.join(said, ", ")
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
              waiting: step["waits"],
              failing: step["fails"]
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

  defp flags(flags), do: for({state, true} <- flags, do: state)
end
