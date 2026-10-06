defmodule EhOsContract.Graph.Overlay do
  @moduledoc """
  What the log says over a `graph.v1` document (plan E13a, batch 5): a document of
  its own, joined onto the graph of facts by id and never copied into it, so the
  facts keep their digest whatever the log holds.

  It carries **only the numbers the pictures and the report compute today** (the
  user's decision 2 before batch 4): an event's occurrences and runs, a process's
  runs, a step's runs out of the process's, what waits and what fails there and
  whether the report counts it as never taken or not yet; a lifecycle transition's
  count, "not yet" and "never", and an aggregate's count; between contracts, the
  events the log holds and what waits or fails at the consumer, and each contract's
  runs. They come from `EhOsContract.Paths`, `EhOsContract.Conformance` and, between
  contracts, `EhOsContract.Graph.System`'s overlay, whose arithmetic moves here when
  E13b takes that picture away. Nothing is counted here but the sum of a pair of
  contracts' arrows where one consumes from the other twice.

  Its JSON Schema is at `schema_path/0`, beside the document's.

  ## The shape

  `nodes` and `relations` are maps from an id of the facts document to its numbers
  (decision 3). The overlay says what it was computed against (decision 4): its
  period (`since`, `until`), the contract's or domain's `version`, and
  `document_digest`, the digest of the facts document — the ids change with the
  declarations and with how the engine makes them, and only that digest moves every
  time they do, so a reader joins an overlay only onto the document it names.

  **A move a lifecycle does not allow** exists only with the log, so the overlay
  defines it (decision 5) in the facts' own shape, under `observed`: `%{relations:
  %{undeclared: [%{id, from, to, event}]}}`, from and to the status the aggregate
  stood in and stayed in — the unit itself where it stood in none yet — and its count
  sits in `relations` with every other relation's.

  ## Where a step's numbers sit

  A step of `EhOsContract.Paths` is one arrow or two in the facts; its numbers sit
  on the relation that ends it: a command's `emits`, a reaction's `issues` (a
  manager's with the step's event as its `on`), a timer's `fires`, and an effect's
  `handled_by` — where a step and a relation match one to one. A policy that handles
  several events reaches one `issues` by several steps, each with its own numbers,
  and a manager issuing one command on one event both as it starts a run and during
  it ends one step at two relations the log cannot tell apart: those relations get
  no numbers rather than numbers that belong to something else.
  """

  alias EhOsContract.{Conformance, Model, Paths}
  alias EhOsContract.Graph.{Document, System}

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
    c = model.module
    id = &Document.id([&1, c, &2])

    steps =
      period
      |> then(&Conformance.steps(model, &1))
      |> Enum.uniq()

    lifecycles = Conformance.lifecycles(model, period)

    events =
      for {name, {occurrences, runs}} <- Paths.occurrences(model, period),
          do: {id.(:event, name), %{occurrences: occurrences, runs: runs}}

    process =
      for p <- List.wrap(model.process),
          do:
            {id.(:process, p.name), %{runs: Paths.runs_of(model, Atom.to_string(p.name), period)}}

    units = for l <- lifecycles, do: {id.(:unit, l.unit), %{aggregates: l.aggregates}}

    {undeclared, moved} = undeclared(c, lifecycles)

    seal(
      %{
        "kind" => "contract",
        "contract" => Model.json_data(c),
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
    picture = System.build(model, contracts, [overlay: true] ++ period)

    runs = for %{kind: :contract, runs: runs} = n <- picture.nodes, do: {n.id, %{runs: runs}}

    # One relation per pair of contracts in the facts, every `consumes` of one sibling
    # merged; the picture draws one arrow per `consumes`, each over its own events, so
    # the pair's numbers are their sum.
    traffic =
      for %{relation: :consumed_by, overlay: %{} = o} = e <- picture.edges,
          rid <- find(document, "consumed_by", e.from, e.to, %{}) do
        {rid, o}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn
        {id, [one]} ->
          {id, one}

        {id, many} ->
          {id,
           %{
             events: Enum.sum(Enum.map(many, & &1.events)),
             waiting: Enum.sum(Enum.map(many, & &1.waiting)),
             failing: Enum.any?(many, & &1.failing)
           }}
      end)

    seal(
      %{
        "kind" => "domain",
        "domain" => Model.json_data(model.module),
        "version" => model.version,
        "document_digest" => document["digest"],
        "nodes" => Map.new(runs),
        "relations" => Map.new(traffic),
        "observed" => %{"relations" => %{"undeclared" => []}}
      },
      period
    )
  end

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
  # ends — where step and relation match one to one. A relation several steps end at
  # gets none rather than one step's for all, and so do the relations one step ends at,
  # which no step's numbers can tell apart.
  defp on_steps(document, c, steps) do
    find = fn type, from, to, on ->
      find(document, type, from, to, if(on, do: %{"on" => on}, else: %{}))
    end

    ref = fn %{kind: kind, name: name} -> Document.id([kind, c, name]) end

    ended = for step <- steps, do: {step, ends(step, ref, find, c)}
    reached = ended |> Enum.flat_map(&elem(&1, 1)) |> Enum.frequencies()

    for {step, [rid]} <- ended, reached[rid] == 1, do: {rid, numbers(step)}
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
      runs: step.runs,
      of_runs: step.of_runs,
      waiting: step.in_flight,
      failing: step.failing,
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
