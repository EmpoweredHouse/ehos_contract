defmodule EhOsContract.Graph.Overlay do
  # Plan E13a, batch 5. Only the report's numbers is the user's decision 2 before
  # batch 4; the shape, decisions 3 to 5; where a step's numbers sit, the user's
  # decisions of 6 and 7 October (`PLAN.md`, "E13a").
  @moduledoc """
  What the log says over a `graph.v1` document: a document of its own, joined onto
  the graph of facts by id and never copied into it, so the facts keep their digest
  whatever the log holds.

  It carries **only the numbers the conformance report computes**, and its readings
  of them, so a reader recounts nothing: an event's occurrences, a process's runs,
  how often a step was taken, what waits and what fails there and whether the report
  counts it as never taken or not yet; a lifecycle transition's count, "not yet" and
  "never", and an aggregate's count; between contracts, the events the log holds and
  what waits or fails at the consumer, and each contract's runs. They are counted as
  `EhOsContract.Conformance.report/2` counts them; between contracts, from the
  consumer's steps and one count of the consumed events.

  Its JSON Schema is at `schema_path/0`, beside the document's.

  ## The shape

  `nodes` and `relations` are maps from an id of the facts document to its numbers.
  The overlay says what it was computed against: its period (`since`, `until`), the contract's or domain's `version`, and
  `document_digest`, the digest of the facts document — the ids change with the
  declarations and with how the engine makes them, and only that digest moves every
  time they do, so a reader joins an overlay only onto the document it names.

  **A move a lifecycle does not allow** exists only with the log, so the overlay
  defines it in the facts' own shape, under `observed`: `%{relations:
  %{undeclared: [%{id, from, to, event}]}}`, from and to the status the aggregate
  stood in and stayed in — the unit itself where it stood in none yet — and its count
  sits in `relations` with every other relation's.

  ## Where a step's numbers sit

  A step of the report (`EhOsContract.Conformance.steps/2`) is one arrow or two in the
  facts; its numbers sit on the relation that ends it: a command's `emits`, a
  reaction's `issues` (a manager's with the step's event as its `on`), a timer's
  `fires`, and an effect's `handled_by`. A step's numbers are the report's reading of
  it: `waits` and `fails` say whether the report lists it as waiting or failing
  (`EhOsContract.Conformance.waiting?/1`, `EhOsContract.Conformance.failing?/1`),
  `untraversed` is the report's "never" — the step listed as untraversed — and
  `pending` its "not yet". They sit on a relation in one of two ways:

  - **One step, one relation:** the step's numbers, flat — `taken`, `waiting`,
    `failing`, `waits`, `fails`, `untraversed`, `pending`.
  - **Several steps, one relation** — a policy handling several events, which the
    facts hold as one `issues`: `%{by_trigger: %{event id => numbers}}`, each step's
    numbers under the id of the event it starts from, as the report has one line per
    step, and no total, which the report does not give either. An entry is flat or
    `by_trigger`, never both.

  **One step, two relations get no numbers:** a manager issuing one command on one
  event both as the event starts a run and during it has two `issues` (`phase` start
  and run) and one step in the report. The log does not record which phase a command
  was issued in, so no number of the step belongs to either relation alone. For the
  same reason a manager whose `starts_on` and `on` of one event issue different
  commands is read by its declarations: dispatch lets its callback issue either
  command in either phase, and a command issued in the other phase still counts on
  the relation that declares it.

  A step the facts end at no relation, or at two that are not such a manager's
  phases, is a shape of the DSL this module does not know: its relations get no
  numbers and a warning is logged, and a test over every fixture fails on it.
  """

  require Logger

  import Ecto.Query

  alias EhOsContract.{Conformance, Event, Model, Paths}
  alias EhOsContract.Graph.Document

  @schema "eh_os_contract.graph_overlay.v1"

  @doc """
  The overlay of `contract` over the period `opts` names (`:since`, `:until`, as in
  the report), against `Document.contract/1` of the same contract.
  """
  @spec contract(module() | map(), keyword()) :: map()
  def contract(contract, opts \\ []) do
    model = Model.fetch(contract)
    document = Document.contract(model)
    period = Keyword.take(opts, [:since, :until])
    c = model.id
    id = &Document.id([&1, c, &2])

    steps = model |> Conformance.steps(period) |> Enum.uniq()

    lifecycles = Conformance.lifecycles(model, period)

    events =
      for {name, occurrences} <- Paths.occurrences(model, period),
          do: {id.(:event, name), %{occurrences: occurrences}}

    process =
      for p <- List.wrap(Model.process(model)),
          do:
            {id.(:process, p.name), %{runs: Paths.runs_of(model, Atom.to_string(p.name), period)}}

    units = for l <- lifecycles, do: {id.(:unit, l.unit), %{aggregates: l.aggregates}}

    {undeclared, moved} = undeclared(c, lifecycles)

    seal(
      %{
        "kind" => "contract",
        "contract" => c,
        "module" => Model.json_data(model.module),
        "version" => model.version,
        "document_digest" => document["digest"],
        "nodes" => Map.new(events ++ process ++ units),
        "relations" =>
          Map.new(on_steps(document, c, steps) ++ transitions(document, c, lifecycles) ++ moved),
        "observed" => %{"relations" => %{"undeclared" => undeclared}}
      },
      period
    )
  end

  @doc """
  The overlay of `domain` over `contracts` (those naming another domain are left
  out) and the period `opts` names, against `Document.domain/2` of the same: each
  contract's runs, and what crosses between two contracts.
  """
  @spec domain(module() | map(), [module() | map()], keyword()) :: map()
  def domain(domain, contracts, opts \\ []) do
    model = Model.fetch(domain)
    document = Document.domain(model, contracts)
    period = Keyword.take(opts, [:since, :until])

    models =
      contracts
      |> Enum.map(&Model.fetch/1)
      |> Enum.filter(&(&1.domain == model.module))

    id = &Document.id([:contract, &1.id])

    runs =
      for m <- models,
          p = Model.process(m),
          do: {id.(m), %{runs: Paths.runs_of(m, Atom.to_string(p.name), period)}}

    seal(
      %{
        "kind" => "domain",
        "domain" => Model.json_data(model.module),
        "version" => model.version,
        "document_digest" => document["digest"],
        "nodes" => Map.new(runs),
        "relations" => Map.new(between(document, models, id, period)),
        "observed" => %{"relations" => %{"undeclared" => []}}
      },
      period
    )
  end

  # What crosses from one contract to another, on the one relation the facts have for
  # the pair: how many of the consumed events the log holds, and what waits or fails at
  # the consumer's steps that start from them. A contract that consumes from a sibling
  # twice has one relation and the sum of both. Only a consumer's steps are read, once
  # however many siblings it consumes from, and the consumed events are counted in one
  # query for every pair.
  defp between(document, models, id, period) do
    pairs =
      for m <- models,
          %{kind: :contract, from: from} = c <- m.consumes,
          sibling = Enum.find(models, &(&1.module == from)),
          do: {sibling, m, c}

    consumers = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq_by(& &1.module)
    steps = Map.new(consumers, &{&1.module, Paths.observe(&1, period)})
    types = for {sibling, _m, c} <- pairs, e <- sibling.events, e.name in c.events, do: e.type
    counts = counts(types, period)

    for {sibling, m, c} <- pairs,
        rid <- find(document, "consumed_by", id.(sibling), id.(m), %{}) do
      {rid, traffic(sibling, c, steps[m.module], counts)}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {rid, many} ->
      {rid,
       %{
         events: Enum.sum(Enum.map(many, & &1.events)),
         waiting: Enum.sum(Enum.map(many, & &1.waiting)),
         failing: Enum.any?(many, & &1.failing)
       }}
    end)
  end

  # How many events of each type the log holds, in the period. `count(position)`
  # rather than of the id, so the `(type, position)` index answers it alone.
  defp counts([], _period), do: %{}

  defp counts(types, period) do
    from(e in Event,
      as: :event,
      where: e.type in ^Enum.uniq(types),
      group_by: e.type,
      select: {e.type, count(e.position)}
    )
    |> since(period[:since])
    |> until(period[:until])
    |> repo().all()
    |> Map.new()
  end

  defp since(query, nil), do: query
  defp since(query, at), do: where(query, [event: e], e.occurred_at >= ^at)

  defp until(query, nil), do: query
  defp until(query, at), do: where(query, [event: e], e.occurred_at <= ^at)

  # One `consumes` of a sibling: how many of its events the log holds, and what waits or
  # fails at the consumer's steps that start from them, under the names they have there.
  defp traffic(sibling, c, steps, counts) do
    types = for e <- sibling.events, e.name in c.events, do: e.type
    local = MapSet.new(c.events, &Map.get(c.renames, &1, &1))

    steps =
      for step <- steps,
          step.from.kind == :event,
          MapSet.member?(local, step.from.name),
          do: step

    %{
      events: types |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum(),
      waiting: steps |> Enum.map(&Enum.sum(Map.values(&1.in_flight))) |> Enum.sum(),
      failing: Enum.any?(steps, &Conformance.failing?/1)
    }
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)

  @doc "Where the JSON Schema of an overlay is: in the package's `priv/schema`."
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:eh_os_contract, "priv/schema/graph_overlay.v1.json")

  defp seal(body, period) do
    body
    |> Map.merge(%{
      "schema" => @schema,
      "since" => iso(period[:since]),
      "until" => iso(period[:until])
    })
    |> Map.update!("nodes", &Model.json_data/1)
    |> Map.update!("relations", &Model.json_data/1)
    |> Map.update!("observed", &Model.json_data/1)
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  # Each step's numbers on the relation that ends it, found in the document by its
  # ends. A relation one step ends at carries that step's numbers; one several steps end
  # at — a policy handling several events — carries each step's under `by_trigger`, by
  # the id of the event the step starts from.
  defp on_steps(document, c, steps) do
    find = fn type, from, to, on ->
      find(document, type, from, to, if(on, do: %{"on" => on}, else: %{}))
    end

    ref = fn %{kind: kind, name: name} -> Document.id([kind, c, name]) end
    phase = for r <- document["relations"]["issues"], into: %{}, do: {r["id"], r["phase"]}

    for step <- steps, rid <- ended(step, ends(step, ref, find, c), phase) do
      {rid, {trigger(step, ref, c), numbers(step)}}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn
      {rid, [{_trigger, numbers}]} -> {rid, numbers}
      {rid, many} -> {rid, %{by_trigger: Map.new(many)}}
    end)
  end

  # The id of what a step starts from: a timer's carries its manager.
  defp trigger(%{from: %{kind: :timer}} = s, _ref, c),
    do: Document.id([:timer, c, s.via.name, s.from.name])

  defp trigger(s, ref, _c), do: ref.(s.from)

  defp ended(_step, [rid], _phase), do: [rid]

  # A manager's step at its two phases' relations: the log cannot tell them apart.
  defp ended(step, rids, phase) do
    unless Enum.sort(Enum.map(rids, &phase[&1])) == ["run", "start"] do
      Logger.warning(
        "the step #{inspect(Map.take(step, [:from, :via, :to]))} ends at #{length(rids)} " <>
          "relations of the graph document, where its numbers need one; they get none"
      )
    end

    []
  end

  defp ends(%{via: nil} = s, ref, find, _c), do: find.("emits", ref.(s.from), ref.(s.to), nil)

  defp ends(%{from: %{kind: :timer}} = s, _ref, find, c),
    do:
      find.(
        "fires",
        Document.id([:timer, c, s.via.name, s.from.name]),
        Document.id([:command, c, s.to.name]),
        nil
      )

  defp ends(%{to: nil} = s, ref, find, _c),
    do: find.("handled_by", ref.(s.from), ref.(s.via), nil)

  defp ends(%{via: %{kind: :process_manager}} = s, ref, find, _c),
    do: find.("issues", ref.(s.via), ref.(s.to), ref.(s.from))

  defp ends(s, ref, find, _c), do: find.("issues", ref.(s.via), ref.(s.to), nil)

  # The ids of the relations of `type` between two nodes with these attributes.
  defp find(document, type, from, to, attrs) do
    for r <- document["relations"][type],
        r["from"] == from and r["to"] == to,
        Enum.all?(attrs, fn {k, v} -> r[k] == v end),
        do: r["id"]
  end

  defp numbers(step) do
    %{
      taken: step.taken,
      waiting: step.in_flight,
      failing: step.failing,
      waits: Conformance.waiting?(step),
      fails: Conformance.failing?(step),
      untraversed: step.untraversed,
      pending: step.pending
    }
  end

  # A lifecycle's transitions, found in the document: an initial one is its event's
  # `enters`, any other the `transition` between two statuses by its event.
  defp transitions(document, c, lifecycles) do
    for l <- lifecycles, t <- l.transitions do
      same = &(&1 == t)
      status = &Document.id([:status, c, l.unit, &1.name])
      event = Document.id([:event, c, t.event.name])

      found =
        case t.from do
          nil -> find(document, "enters", event, status.(t.to), %{})
          from -> find(document, "transition", status.(from), status.(t.to), %{"event" => event})
        end

      numbers = %{
        count: t.count,
        pending: Enum.any?(l.pending, same),
        untraversed: Enum.any?(l.untraversed, same)
      }

      for rid <- found, do: {rid, numbers}
    end
    |> List.flatten()
  end

  defp undeclared(c, lifecycles) do
    moves =
      for l <- lifecycles, u <- l.undeclared do
        at =
          if u.from,
            do: Document.id([:status, c, l.unit, u.from.name]),
            else: Document.id([:unit, c, l.unit])

        event = Document.id([:event, c, u.event.name])

        {%{id: Document.id([:undeclared, at, at, event]), from: at, to: at, event: event},
         u.count}
      end

    {Enum.map(moves, &elem(&1, 0)), for({m, count} <- moves, do: {m.id, %{count: count}})}
  end
end
