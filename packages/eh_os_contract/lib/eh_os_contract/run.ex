defmodule EhOsContract.Run do
  @moduledoc """
  How long a run took, against the duration its process declared.

  A process may declare `deadline: {n, unit}` — how long a run is agreed to take.
  Until now nothing read it: the only mentions were a filter that excluded it when
  unconfirmed and a renderer that printed it. A declaration nobody reads is the
  thing stage 2 existed to delete, and this was the last one left.

  ## Where a run starts and where it ends

  **Start is the earliest event of the run.** Not the first event of the first
  stage: `stages:` declares order *between* gates rather than a starting event, and
  a process with no `stages:` has no first stage at all. The log's own minimum is
  the only definition covering every process shape the engine already claims to
  handle — and it is the one the report's existing sentence already promises,
  *"Deadline: 2 days from the start."*

  **End is the earliest event declared `terminal: true`.** Three alternatives were
  rejected for stateable reasons:

    * *The last event.* A run in progress always has one, so every open run would
      get a duration and be compared against the deadline. This report may not turn
      an absence of an answer into the answer "no", and that would do exactly that.
    * *A promise's `eventually`.* A different promise with a different window,
      which already has its own verdict in `EhOsContract.Trace`.
    * *The latest terminal occurrence.* A run that reached its ending has ended; a
      later event does not un-end it. Taking the earliest also means `ended_at` is a
      minimum over a subset of the same rows the start is a minimum over, so
      `start <= end` holds by construction rather than by a guard.

  ## Four outcomes, because two would be a lie

  | outcome | condition | in the report |
  | --- | --- | --- |
  | `:within` | ended, inside the declared duration | the denominator |
  | `:exceeded` | ended, outside it | the numerator |
  | `:overdue` | not ended, already past it | its own sentence |
  | `:open` | not ended, still inside it | nothing at all |

  `:overdue` is a finding, not an absence: the run has already taken longer than
  agreed whatever it does next. It must not be folded into `:exceeded`, because
  there the duration is known and here only a lower bound is — *"took four days"*
  and *"has taken at least four days"* are different sentences. `:open` produces no
  finding at all: a run inside its time is the normal case, and printing it would be
  the same violation by a different route.

  ## The period bound is on the start, not on the rows

  `:since` and `:until` select runs that **started** in the period, as a `having`
  over the run's minimum. Never as a `where` on `occurred_at`: that would drop the
  run's early rows, so a run started in June and reported for July would appear to
  have started in July and come out `:within` a duration it blew. Membership and
  measurement are different questions, and the duration comes from the run's whole
  history however narrow the window on it.

  ## The runs

  A contract's one `process` declares its `deadline` (v2 §13, plan E7c), and its runs are the rows of
  `eh_os_contract_event_runs` for that process, over its own events' types and the
  ones it includes (D7): an included event can start a run, and an included one
  declared `terminal:` ends it.

  Like `EhOsContract.Trace`, this counts runs and never names them. Which client is late is a
  question for the client's own application, which already knows.
  """

  import Ecto.Query

  alias EhOsContract.{Event, EventRun, Model}

  @typedoc """
  One run, measured against its process's declared duration.

  `ended_at` is `nil` for a run with no terminal event yet, which is what separates
  `:overdue` from `:exceeded`.
  """
  @type outcome :: %{
          instance_id: String.t(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          outcome: :within | :exceeded | :overdue | :open
        }

  @doc """
  Every run of one process, measured against its declared duration.

  Returns `[]` when the process declares no `deadline`, which is the ordinary case
  — most processes promise nothing about how long they take.

  `opts`: `:since`, `:until`, `:instance`, and `:now` for the comparison, which is
  what makes `:overdue` testable without waiting.
  """
  @spec evaluate(module(), atom(), keyword()) :: [outcome()]
  def evaluate(contract, process_name, opts \\ []) do
    model = Model.fetch(contract)

    case {model, Model.process(model)} do
      {%{units: _}, %{name: ^process_name, deadline: %{} = deadline}} ->
        measure(runs_of(model), {deadline.amount, deadline.unit}, opts)

      {%{units: _}, _none} ->
        []
    end
  end

  @doc """
  The counts a report prints, from the outcomes above.

  `runs` counts every run in the period, including the open ones that produce no
  finding, so the numbers can be checked against each other: the four outcomes sum
  to it.
  """
  @spec summary([outcome()]) :: %{
          runs: non_neg_integer(),
          within: non_neg_integer(),
          exceeded: non_neg_integer(),
          overdue: non_neg_integer(),
          open: non_neg_integer()
        }
  def summary(outcomes) do
    counts = Enum.frequencies_by(outcomes, & &1.outcome)

    %{
      runs: length(outcomes),
      within: Map.get(counts, :within, 0),
      exceeded: Map.get(counts, :exceeded, 0),
      overdue: Map.get(counts, :overdue, 0),
      open: Map.get(counts, :open, 0)
    }
  end

  @spec measure(source(), EhOsContract.Duration.t(), keyword()) :: [outcome()]
  defp measure(source, deadline, opts) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()

    source
    |> spans(opts)
    |> Enum.map(fn {instance_id, started_at, ended_at} ->
      %{
        instance_id: instance_id,
        started_at: started_at,
        ended_at: ended_at,
        outcome: outcome(started_at, ended_at, deadline, now)
      }
    end)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  # `EhOsContract.Duration.shift/2` rather than a second arithmetic: the same function
  # computes a promise's window, so a duration cannot come to mean one thing in a
  # promise and another in a deadline.
  @spec outcome(DateTime.t(), DateTime.t() | nil, EhOsContract.Duration.t(), DateTime.t()) ::
          :within | :exceeded | :overdue | :open
  defp outcome(started_at, ended_at, deadline, now) do
    due = EhOsContract.Duration.shift(started_at, deadline)

    case ended_at do
      nil -> if DateTime.compare(now, due) == :gt, do: :overdue, else: :open
      at -> if DateTime.compare(at, due) == :gt, do: :exceeded, else: :within
    end
  end

  # One grouped query per process. The terminal end is a filtered aggregate over the
  # same rows rather than a second query, so a run cannot be seen to start in one
  # snapshot and end in another.
  # Which rows make the runs of a process, and which of their types end one: the rows
  # of `eh_os_contract_event_runs` of its events' types, its own and the ones it
  # includes (D7), so an event another contract decided starts or ends a run too.
  @typep source :: {:runs, String.t(), [String.t()], [String.t()]}

  @spec runs_of(map()) :: source()
  defp runs_of(model) do
    events = Model.process_events(model)

    {:runs, Atom.to_string(Model.process(model).name), Enum.map(events, & &1.type),
     for(%{type: type, terminal: true} <- events, do: type)}
  end

  @spec spans(source(), keyword()) :: [{String.t(), DateTime.t(), DateTime.t() | nil}]
  defp spans({:runs, process, types, terminal}, opts) do
    from(r in EventRun,
      join: e in Event,
      as: :event,
      on: e.position == r.position,
      where: r.process == ^process,
      where: e.type in ^types,
      group_by: r.instance_id,
      select:
        {r.instance_id, min(e.occurred_at),
         type(
           # `type/2` is not decoration here: a bare fragment has no Ecto type, so
           # this comes back as a `NaiveDateTime` and every comparison against a
           # `DateTime` raises. Silent in the query, loud one function later.
           fragment("min(?) FILTER (WHERE ? = ANY(?))", e.occurred_at, e.type, ^terminal),
           :utc_datetime_usec
         )}
    )
    |> bound(:>=, Keyword.get(opts, :since))
    |> bound(:<=, Keyword.get(opts, :until))
    |> maybe_run(Keyword.get(opts, :instance))
    |> repo().all()
  end

  # `having` on the run's minimum, never `where` on the row — see the moduledoc.
  @spec bound(Ecto.Query.t(), :>= | :<=, DateTime.t() | nil) :: Ecto.Query.t()
  defp bound(query, _direction, nil), do: query
  defp bound(query, :>=, at), do: having(query, [event: e], min(e.occurred_at) >= ^at)
  defp bound(query, :<=, at), do: having(query, [event: e], min(e.occurred_at) <= ^at)

  @spec maybe_run(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_run(query, nil), do: query
  defp maybe_run(query, id), do: where(query, [r], r.instance_id == ^id)

  @spec repo() :: module()
  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
