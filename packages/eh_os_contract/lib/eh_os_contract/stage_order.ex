defmodule EhOsContract.StageOrder do
  # Plan DD, O1 (#260), its definition agreed with EHOS in EmpoweredHouse/eh-os#297.
  @moduledoc """
  Which runs of a process reached a later stage before an earlier one.

  A process's stages are in an order: a shop's order goes from its placing, through
  picking in the warehouse, to shipping. A run whose parcel was booked with the carrier
  before it was picked did something the process does not say. This counts such runs,
  and names the pairs of stages that were out of order:

      %{runs: 3,
        pairs: [%{earlier: :picking, later: :shipping, runs: 3,
                  earlier_label: "Picking", later_label: "Shipping"}]}

  A stage's label is its name where it declares none.

  The rules, each a choice made on purpose:

  - **A stage is entered by its first event.** A run that was picked, booked and picked
    again counts its picking by the first one, so a repacked order does not show here.
  - **Order is the log's, not the clock's.** The first event of each stage is the one
    at the smallest position in the log, so clocks that disagree never decide it. A
    process includes only contracts of its own application, so all its stages are in
    one log and the order can always be judged.
  - **Only stages a run reached are compared.** A stage a run never reached, because it
    was skipped or because a reaction to it still waits in a queue, is no finding: the
    run has not done anything out of order, it has not done that yet.
  - **The period does not cut a run.** A run belongs to the period by its first event,
    as a run is measured against its deadline: by the first event of any type the
    process includes. It is judged on all its events, including those
    after `until`.

  - **The stages are today's.** After a deploy that reorders stages, a run is judged by
    the order declared now, not by the one it ran under.

  The count says how many runs, never which: those runs are the business's data, and
  finding them is the client application's job.
  """

  import Ecto.Query

  alias EhOsContract.{Event, EventRun, Model}

  @typedoc "A pair of stages out of order, and in how many runs."
  @type pair :: %{
          earlier: atom(),
          later: atom(),
          runs: pos_integer(),
          earlier_label: String.t(),
          later_label: String.t()
        }

  @typedoc "The runs out of order, and the pairs of stages they were out of order in."
  @type t :: %{runs: non_neg_integer(), pairs: [pair()]}

  @doc """
  The runs of the process module `model` that reached a later stage before an earlier
  one, in the period `since:` and `until:` name.

  Pairs are listed in the stages' order, the earlier stage first.
  """
  @spec evaluate(map(), keyword()) :: t()
  def evaluate(model, opts \\ []) do
    process = Model.process(model)
    order = process.stages |> Enum.map(& &1.name) |> Enum.with_index() |> Map.new()
    label = Map.new(process.stages, &{&1.name, &1.label || to_string(&1.name)})

    events = Model.process_events(model)

    stage_of =
      for %{type: type, stage: stage} <- events,
          Map.has_key?(order, stage),
          into: %{},
          do: {type, stage}

    out_of_order =
      process.name
      |> firsts(comparable(stage_of), Enum.map(events, & &1.type), opts)
      |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))
      |> Enum.map(fn {_run, rows} -> pairs(rows, stage_of, order) end)
      |> Enum.reject(&(&1 == []))

    %{
      runs: length(out_of_order),
      pairs:
        out_of_order
        |> List.flatten()
        |> Enum.frequencies()
        |> Enum.sort_by(fn {{earlier, later}, _} -> {order[earlier], order[later]} end)
        |> Enum.map(fn {{earlier, later}, runs} ->
          %{
            earlier: earlier,
            later: later,
            runs: runs,
            earlier_label: label[earlier],
            later_label: label[later]
          }
        end)
    }
  end

  # The staged types, or none when they make fewer than two stages: no pair to compare.
  defp comparable(stage_of) do
    if stage_of |> Map.values() |> Enum.uniq() |> length() < 2, do: [], else: Map.keys(stage_of)
  end

  # The pairs one run was out of order in: a later stage entered before an earlier one
  # that the run also entered.
  @spec pairs([{String.t(), integer()}], map(), map()) :: [{atom(), atom()}]
  defp pairs(rows, stage_of, order) do
    entered =
      rows
      |> Enum.group_by(fn {type, _} -> stage_of[type] end, fn {_, position} -> position end)
      |> Map.new(fn {stage, positions} -> {stage, Enum.min(positions)} end)

    for {earlier, at} <- entered,
        {later, later_at} <- entered,
        order[earlier] < order[later],
        later_at < at,
        do: {earlier, later}
  end

  # Per run and type, the first position. A run is in the period by its first event,
  # so the bound is on the run, never on a row: a row outside the period still counts
  # in a run that began inside it.
  #
  # `staged` are the types whose stage is compared; `all`, every type of the run, decides
  # which runs are in the period, so a run that began with an unstaged event began then.
  @spec firsts(String.t(), [String.t()], [String.t()], keyword()) ::
          [{String.t(), String.t(), integer()}]
  defp firsts(process, staged, all, opts) do
    if staged == [], do: [], else: query(process, staged, all, opts)
  end

  defp query(process, staged, all, opts) do
    of = fn types ->
      from(r in EventRun,
        join: e in Event,
        as: :event,
        on: e.position == r.position,
        where: r.process == ^process,
        where: e.type in ^types
      )
    end

    rows = of.(staged)

    runs =
      case {Keyword.get(opts, :since), Keyword.get(opts, :until)} do
        {nil, nil} ->
          rows

        {since, until} ->
          in_period =
            all
            |> of.()
            |> group_by([r], r.instance_id)
            |> bound(:>=, since)
            |> bound(:<=, until)
            |> select([r], r.instance_id)

          where(rows, [r], r.instance_id in subquery(in_period))
      end

    runs
    |> group_by([r, e], [r.instance_id, e.type])
    |> select([r, e], {r.instance_id, e.type, min(r.position)})
    |> repo().all()
  end

  @spec bound(Ecto.Query.t(), :>= | :<=, DateTime.t() | nil) :: Ecto.Query.t()
  defp bound(query, _direction, nil), do: query
  defp bound(query, :>=, at), do: having(query, [event: e], min(e.occurred_at) >= ^at)
  defp bound(query, :<=, at), do: having(query, [event: e], min(e.occurred_at) <= ^at)

  @spec repo() :: module()
  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
