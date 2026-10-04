defmodule EhOsContract.Lifecycle do
  @moduledoc """
  An aggregate's status, computed from its stream (plan LC2, #99).

  A contract declares the lifecycle (`lifecycle do status …; initial …; transition …
  end`, checked by T1–T4); the engine computes where one aggregate stands from the
  names of the events in its stream alone, in order, and nothing else sets it:

  - before any event the status is `nil`; an `initial` event starts it;
  - a declared transition out of the current status moves it;
  - any other event leaves it where it is — an event no transition names, or one
    recorded (`recorded_by:`) that does not fit, which happened all the same.

  Dispatch and `EhOsContract.ScenarioCase` read it through the same functions, so a
  scenario holds the implementation to what dispatch will do. A command's `from:`
  is checked against the status before the decision (`admits?/2`); what a decision
  emits is checked after it (`decided!/4`), where an event the graph does not allow
  is a defect, as one outside `emits:` is.
  """

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
  An event no transition names is allowed in every status that is not terminal, once
  the aggregate has started: before, only an initial event may be decided.
  """
  @spec decided!(t(), status(), atom(), [atom()]) :: status()
  def decided!(lifecycle, status, command, events) do
    Enum.reduce(events, status, fn event, status ->
      case allowed(lifecycle, status, event) do
        {:ok, next} ->
          next

        {:error, why} ->
          raise ArgumentError,
                "command #{inspect(command)} decided #{inspect(event)} #{why}. Nothing was " <>
                  "appended."
      end
    end)
  end

  @doc """
  What the aggregates' streams did with the lifecycle (plan LC3): each stream is its
  events in order, as `{name, counted?}`, and only a counted event — one in the
  report's period — is tallied, though every event moves the status.

  `taken` counts each declared move by `{from, event, to}`, an initial one with
  `from` `nil`; `undeclared` counts by `{status, event}` each event the graph does not
  allow where the aggregate stood — history from before the lifecycle was declared,
  a recorded event that did not fit, an event after the aggregate's life ended. Such
  an event moves nothing, as it moved nothing when it was appended. An event no
  transition names, in a status that is not terminal, is neither.
  """
  @spec tally(t(), [[{atom() | nil, boolean()}]]) :: %{
          taken: %{{status(), atom(), atom()} => pos_integer()},
          undeclared: %{{status(), atom()} => pos_integer()}
        }
  def tally(lifecycle, streams) do
    Enum.reduce(streams, %{taken: %{}, undeclared: %{}}, fn stream, acc ->
      {acc, _status} =
        Enum.reduce(stream, {acc, nil}, fn
          {nil, _counted?}, {acc, status} ->
            {acc, status}

          {event, counted?}, {acc, status} ->
            case allowed(lifecycle, status, event) do
              {:ok, next} ->
                moved? =
                  if status == nil,
                    do: true,
                    else:
                      Enum.any?(lifecycle.transitions, &(&1.from == status and &1.event == event))

                acc =
                  if moved? and counted?, do: bump(acc, :taken, {status, event, next}), else: acc

                {acc, next}

              {:error, _why} ->
                acc = if counted?, do: bump(acc, :undeclared, {status, event}), else: acc
                {acc, status}
            end
        end)

      acc
    end)
  end

  defp bump(acc, key, at), do: Map.update!(acc, key, &Map.update(&1, at, 1, fn n -> n + 1 end))

  defp allowed(lifecycle, status, event) do
    terminal = for s <- lifecycle.statuses, s.terminal, do: s.name
    starts = Enum.any?(lifecycle.initial, &(&1.on == event))
    moves = Enum.any?(lifecycle.transitions, &(&1.event == event))

    cond do
      status in terminal ->
        {:error,
         "in status #{inspect(status)}, which is terminal: the aggregate's life has ended"}

      status == nil and starts ->
        {:ok, step(lifecycle, nil, event)}

      status == nil and not starts ->
        {:error, "before the aggregate has a status; it is not an initial event"}

      starts and not moves ->
        {:error, "in status #{inspect(status)}; it starts an aggregate, and this one has started"}

      moves ->
        case step(lifecycle, status, event) do
          ^status ->
            if Enum.any?(lifecycle.transitions, &(&1.from == status and &1.event == event)),
              do: {:ok, status},
              else: {:error, "in status #{inspect(status)}, which no transition leaves with it"}

          next ->
            {:ok, next}
        end

      true ->
        {:ok, status}
    end
  end
end
