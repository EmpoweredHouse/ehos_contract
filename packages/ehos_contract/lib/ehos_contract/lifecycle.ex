defmodule EhosContract.Lifecycle do
  # An aggregate's status, computed from its stream (plan LC2, #99).
  #
  # A contract declares the lifecycle (`lifecycle do status …; initial …; transition …
  # end`, checked by T1–T4); the engine computes where one aggregate stands from the
  # names of the events in its stream alone, in order, and nothing else sets it:
  #
  # - before any event the status is `nil`; an `initial` event starts it;
  # - a declared transition out of the current status moves it;
  # - any other event leaves it where it is — an event no transition names, or one
  #   recorded (`recorded_by:`) that does not fit, which happened all the same.
  #
  # Dispatch and `EhosContract.ScenarioCase` read it through the same functions, so a
  # scenario holds the implementation to what dispatch will do. A command's `from:`
  # is checked against the status before the decision (`admits?/2`); what a decision
  # emits is checked after it (`decided!/4`), where an event the graph does not allow
  # is a defect, as one outside `emits:` is.
  @moduledoc false

  @typedoc "A unit's lifecycle as the model holds it."
  @type t :: %{statuses: [map()], initial: [map()], transitions: [map()]}

  @typedoc "Where one aggregate stands: a declared status, or `nil` before its first event."
  @type status :: atom() | nil

  @doc "The lifecycle of `unit` (a unit of a model), or `nil` when it declares none."
  @spec of(map()) :: t() | nil
  def of(unit), do: Map.get(unit, :lifecycle)

  @doc """
  The status after `event`, from `status`: the initial status `event` starts in when
  `status` is `nil`, the status a declared transition leads to, or `status` itself.
  """
  @spec step(t(), status(), atom()) :: status()
  def step(lifecycle, nil, event) do
    Enum.find_value(lifecycle.initial, fn
      %{on: ^event, status: status} -> status
      _other -> nil
    end)
  end

  def step(lifecycle, status, event) do
    Enum.find_value(lifecycle.transitions, status, fn
      %{from: ^status, event: ^event, to: to} -> to
      _other -> nil
    end)
  end

  @doc "The status after `events`, names in their stream's order, from no status."
  @spec status(t(), [atom()]) :: status()
  def status(lifecycle, events), do: Enum.reduce(events, nil, &step(lifecycle, &2, &1))

  @doc """
  The status before each of `events` and after the last: `{befores, after}`, so a
  fold can show `evolve/2` where the aggregate stood when each event happened.
  """
  @spec walk(t(), [atom()]) :: {[status()], status()}
  def walk(lifecycle, events) do
    Enum.map_reduce(events, nil, fn event, status -> {status, step(lifecycle, status, event)} end)
  end

  @doc """
  Whether a command declared with `from:` may be issued in `status`. A command with
  no `from:` is admitted in every status; its decision is still held to the graph.
  """
  @spec admits?(map(), status()) :: boolean()
  def admits?(command, status) do
    case Map.get(command, :from, []) do
      [] -> true
      from -> status in from
    end
  end

  @doc """
  Holds what a decision emitted, event names in order, to the graph from `status`,
  and returns the status after them. An event the graph does not allow raises
  `ArgumentError` naming `command`: an event of an aggregate whose life has ended, an
  event that starts an aggregate already started or one not yet started without
  starting it, or an event a transition names out of other statuses than this one.
  An event no transition names is allowed in every status that is not final, once
  the aggregate has started: before, only an initial event may be decided.
  """
  @spec decided!(t(), status(), atom(), [atom()]) :: status()
  def decided!(lifecycle, status, command, events) do
    graph = index(lifecycle)

    Enum.reduce(events, status, fn event, status ->
      case allowed_in(graph, status, event) do
        {:error, why} ->
          raise ArgumentError,
                "command #{inspect(command)} decided #{inspect(event)} #{why}. Nothing was " <>
                  "appended."

        {_moved_or_stayed, next} ->
          next
      end
    end)
  end

  @doc """
  What the graph does with `event` in `status`: `{:moved, next}` when it starts the
  aggregate or a declared transition takes it out of `status`, `{:stayed, status}`
  when no transition names it and the aggregate has started and not ended, and
  `{:error, why}` when the graph does not allow it there — `why` completes a sentence
  about the event, as `decided!/4` writes it.

  This is the rule dispatch holds a decision to, one event at a time.
  """
  @spec allowed(t(), status(), atom()) ::
          {:moved, atom()} | {:stayed, status()} | {:error, String.t()}
  def allowed(lifecycle, status, event), do: lifecycle |> index() |> allowed_in(status, event)

  @doc """
  The events among `events` the graph allows in `status`, each with the status it
  leaves the aggregate in, in the order given — the next steps of a legal history.
  An aggregate whose life has ended has none.
  """
  @spec moves(t(), status(), [atom()]) :: [{atom(), status()}]
  def moves(lifecycle, status, events) do
    graph = index(lifecycle)

    for event <- events,
        {kind, next} <- [allowed_in(graph, status, event)],
        kind != :error,
        do: {event, next}
  end

  @doc """
  What the aggregates' streams did with the lifecycle (plan LC3): each stream is its
  events in order, as `{name, counted?}`, and only a counted event — one in the
  report's period — is tallied, though every event moves the status. `streams` may be
  a lazy `Stream`: it is read once, one stream at a time.

  `aggregates` counts the streams with a counted event, and `standing` holds the
  statuses those that have not ended stand in at their last event; `taken` counts each declared
  move by `{from, event, to}`, an initial one with `from` `nil`; `undeclared` counts
  by `{status, event}` each event the graph does not allow where the aggregate stood —
  history from before the lifecycle was declared, a recorded event that did not fit,
  an event after the aggregate's life ended. Such an event moves nothing, as it moved
  nothing when it was appended. An event no transition names, in a status that is not
  final, is neither. A `nil` name — a type the contract no longer declares — is
  skipped.
  """
  @spec tally(t(), Enumerable.t()) :: %{
          aggregates: non_neg_integer(),
          standing: MapSet.t(atom()),
          taken: %{{status(), atom(), atom()} => pos_integer()},
          undeclared: %{{status(), atom()} => pos_integer()}
        }
  def tally(lifecycle, streams) do
    graph = index(lifecycle)
    empty = %{aggregates: 0, standing: MapSet.new(), taken: %{}, undeclared: %{}}

    Enum.reduce(streams, empty, fn stream, acc ->
      counted? = Enum.any?(stream, &elem(&1, 1))
      acc = if counted?, do: %{acc | aggregates: acc.aggregates + 1}, else: acc

      {acc, status} =
        Enum.reduce(stream, {acc, nil}, fn
          {nil, _counted?}, {acc, status} ->
            {acc, status}

          {event, counted?}, {acc, status} ->
            case allowed_in(graph, status, event) do
              {:moved, next} ->
                acc = if counted?, do: bump(acc, :taken, {status, event, next}), else: acc
                {acc, next}

              {:stayed, status} ->
                {acc, status}

              {:error, _why} ->
                acc = if counted?, do: bump(acc, :undeclared, {status, event}), else: acc
                {acc, status}
            end
        end)

      if counted? and status != nil and not MapSet.member?(graph.final, status),
        do: %{acc | standing: MapSet.put(acc.standing, status)},
        else: acc
    end)
  end

  defp bump(acc, key, at), do: Map.update!(acc, key, &Map.update(&1, at, 1, fn n -> n + 1 end))

  # The graph once per call, so a long stream does not scan the lifecycle per event.
  defp index(lifecycle) do
    %{
      final: MapSet.new(for s <- lifecycle.statuses, s.final, do: s.name),
      starts: Map.new(lifecycle.initial, &{&1.on, &1.status}),
      moves: MapSet.new(lifecycle.transitions, & &1.event),
      next: Map.new(lifecycle.transitions, &{{&1.from, &1.event}, &1.to})
    }
  end

  defp allowed_in(graph, status, event) do
    starts = Map.has_key?(graph.starts, event)
    moves = MapSet.member?(graph.moves, event)

    cond do
      MapSet.member?(graph.final, status) ->
        {:error, "in status #{inspect(status)}, which is final: the aggregate's life has ended"}

      status == nil and starts ->
        {:moved, Map.fetch!(graph.starts, event)}

      status == nil ->
        {:error, "before the aggregate has a status; it is not an initial event"}

      starts and not moves ->
        {:error, "in status #{inspect(status)}; it starts an aggregate, and this one has started"}

      moves ->
        case Map.fetch(graph.next, {status, event}) do
          {:ok, next} -> {:moved, next}
          :error -> {:error, "in status #{inspect(status)}, which no transition leaves with it"}
        end

      true ->
        {:stayed, status}
    end
  end
end
