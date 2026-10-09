defmodule EhOsContract.GraphRenderer.View do
  @moduledoc """
  Which facts of a document are drawn together, and how they read: a view is the
  nodes one picture shows, the groups they sit in, the relations between them with
  their words and their line, and which way the picture runs.

  A document groups its nodes by kind and its relations by type
  (`EhOsContract.Graph.Document` in the engine). A view flattens them into the lists
  the drawing layer takes, and keeps a relation only when both of its ends are in the
  view, so that no arrow points at nothing.

  **The views are the six pictures the engine drew before this package** (plan E13b,
  batch 3, the user's decision of 8 October), each chosen here from the graph of
  facts rather than built by the engine:

  | View | What it shows |
  | --- | --- |
  | `contract/1` | a contract's full graph: commands and events in their units, the reactions and timers between them, read models and queries, and the actors and external systems they touch |
  | `declared/1` | a process's declared shape: its stages in order, the events in them, its promises with their windows, the systems its events rest on |
  | `unit/2` | one unit's state, commands, events and rules, and how many scenarios pin each path |
  | `lifecycle/2` | an aggregate's statuses and the events that move it between them |
  | `context_map/1` | a domain's subdomains, contexts, external systems and their relations |
  | `system/1` | a domain's contracts in their contexts, what one consumes from another, and its publications |

  Each says what the picture said, in its words: an arrow after the transaction is
  dotted and says `async`, a promise is a heavy arrow with its window, a relation
  that is not a delivery has no arrowhead. **Where the facts are finer than the
  picture was**, the view follows the facts: a process manager's start, its end and an
  event it takes during its run are arrows of their own, even where nothing is issued
  on them (`starts`, `ends`, `during the run`), a timer it cancels is drawn as one it
  sets is, and two arrows of one type between the same two cards — a timer set as a run
  starts and again during it — say which is which.

  `all/1`, every node and every relation, stays as the drawing layer's test bed.
  `build/3` builds the view a `t:spec/0` names, with what an overlay observed that
  the document does not declare; `views/1` lists the views a document has.
  """

  import EhOsContract.GraphRenderer.Words

  @typedoc "A view by name: a unit's and a lifecycle's take the unit's id."
  @type spec ::
          :all
          | :contract
          | :declared
          | {:unit, String.t()}
          | {:lifecycle, String.t()}
          | :context_map
          | :system

  @typedoc """
  A node as the drawing layer takes it. `facts` is the document's node, whole; `group`
  the id of the group the card sits in; `tag` the small line above its label, `lines`
  what the card lists under it, and `variant` a look of its kind: `"terminal"`,
  `"final"`.
  """
  @type graph_node :: %{
          id: String.t(),
          kind: String.t(),
          name: String.t() | nil,
          label: String.t() | nil,
          facts: map(),
          group: String.t() | nil,
          tag: String.t() | nil,
          lines: [String.t()],
          variant: String.t() | nil
        }

  @typedoc """
  A relation as the drawing layer takes it. `facts` is the document's relation, or for
  one a view makes, the facts it stands for; `words` what the arrow says, `line`
  `"solid"`, `"dotted"` or `"thick"`, and `head` whether it has an arrowhead. Either end
  may be a group.
  """
  @type relation :: %{
          id: String.t(),
          type: String.t(),
          from: String.t(),
          to: String.t(),
          facts: map(),
          words: String.t() | nil,
          line: String.t(),
          head: boolean()
        }

  @typedoc "A box around cards, titled; `facts` is the document's node it is."
  @type group :: %{id: String.t(), kind: String.t(), title: String.t(), facts: map()}

  @type t :: %{
          direction: String.t(),
          nodes: [graph_node()],
          relations: [relation()],
          groups: [group()]
        }

  @doc """
  The views `document` has, each with its title, in the order the dashboard's Graph
  screen showed the pictures: a domain's context map, then its system where it has
  contracts; a contract's declared shape where it has a process, its full graph, then
  each unit and, where it declares one, the unit's lifecycle.
  """
  @spec views(map()) :: [{spec(), String.t()}]
  def views(%{"kind" => "domain"} = document) do
    [{:context_map, "Context map"}] ++
      if nodes(document, "contract") == [], do: [], else: [{:system, "System"}]
  end

  def views(document) do
    lifecycles = MapSet.new(nodes(document, "status"), & &1["unit"])

    for(p <- nodes(document, "process"), do: {:declared, "Declared shape — #{title(p)}"}) ++
      [{:contract, "Full graph"}] ++
      Enum.flat_map(nodes(document, "unit"), fn unit ->
        [{{:unit, unit["id"]}, "#{unit["unit_kind"]} #{unit["name"]} — #{title(unit)}"}] ++
          if MapSet.member?(lifecycles, unit["id"]),
            do: [{{:lifecycle, unit["id"]}, "Lifecycle — #{title(unit)}"}],
            else: []
      end)
  end

  @doc """
  The view `spec` names of `document`, with the moves `overlay` observed and the
  document does not declare — a move a lifecycle does not allow, which happened
  anyway — where both their ends are in it. A unit or a lifecycle the document does
  not have is an empty view.
  """
  @spec build(map(), spec(), map() | nil) :: t()
  def build(document, spec, overlay \\ nil),
    do: document |> view(spec) |> observed(document, overlay)

  defp view(document, :all), do: all(document)
  defp view(document, :contract), do: contract(document)
  defp view(document, :declared), do: declared(document)
  defp view(document, {:unit, id}), do: unit(document, id)
  defp view(document, {:lifecycle, id}), do: lifecycle(document, id)
  defp view(document, :context_map), do: context_map(document)
  defp view(document, :system), do: system(document)

  @doc """
  Every node and every relation of `document`, kinds and types in name order and each
  group in the document's order, so the same document gives the same view and the
  same layout. Each relation says its type.
  """
  @spec all(map()) :: t()
  def all(%{"nodes" => nodes, "relations" => relations}) do
    cards = for {kind, group} <- Enum.sort(nodes), node <- group, do: card(kind, node)

    arrows =
      for {type, group} <- Enum.sort(relations),
          relation <- group,
          do: arrow(type, relation, words: words(type))

    finish("LR", cards, arrows, [])
  end

  # --- a contract's full graph ------------------------------------------------------------

  # Drawn whenever the contract has them; an actor, an external and an event of another
  # contract only when something drawn touches them.
  @always ~w(command policy process_manager effect timer read_model query)
  @flow ~w(emits handled_by starts ends issues sets cancels fires)

  @doc """
  The full graph of a contract's `document`, left to right: each unit's commands and
  events in a group of the unit's own, the events it includes, and the policies,
  process managers, effects and timers between them; its read models with the events
  they project and the queries over them; the actors who issue, record or ask, and the
  external systems an effect calls, an event rests on, a system actor is backed by, or
  a field takes its value from. A policy, a process manager and a query say how many
  scenarios pin them, "0 scenarios" included, and a timer when it fires.
  """
  @spec contract(map()) :: t()
  def contract(document) do
    by_id = index(document)
    own = &(&1.kind == "event" and (&1.facts["unit"] != nil or &1.facts["included"] == true))

    # How many scenarios pin each policy, process manager and query (`lines/3`).
    pinned =
      for {_type, group} <- document["scenarios"] || %{},
          s <- group,
          reduce: %{} do
        acc -> Map.update(acc, s["target"], 1, &(&1 + 1))
      end

    cards =
      for kind <- @always ++ ~w(event actor external),
          node <- nodes(document, kind) do
        card(kind, node,
          group: if(kind in ~w(command event), do: node["unit"]),
          lines: lines(kind, node, pinned)
        )
      end

    managers = MapSet.new(nodes(document, "process_manager"), & &1["id"])
    flow = for type <- @flow, r <- relations(document, type), do: flow(type, r, by_id, managers)

    projected =
      for r <- relations(document, "projected_into") do
        model = by_id[r["to"]]
        delivered(arrow("projected_into", r), async?(r, model))
      end

    reads = for r <- relations(document, "reads"), do: arrow("reads", r, words: "reads")

    access =
      for {type, words} <- [may_issue: nil, may_record: "records", may_ask: nil],
          r <- relations(document, to_string(type)),
          do: arrow(to_string(type), r, words: words)

    # An event of another contract carries its own `depends_on`; the picture draws the
    # systems this contract's events rest on.
    owned = MapSet.new(for c <- cards, own.(c), do: c.id)

    calls =
      for r <- relations(document, "calls"), do: arrow("calls", r, words: "calls", line: "dotted")

    rests =
      for r <- relations(document, "depends_on"),
          MapSet.member?(owned, r["from"]),
          do: arrow("depends_on", r, line: "dotted", head: false)

    backed =
      for r <- relations(document, "backed_by"),
          do: arrow("backed_by", r, words: "backed by", line: "dotted", head: false)

    outside = calls ++ rests ++ backed ++ gives(cards)

    # Who is drawn: what always is, then the events a reaction or a read model takes,
    # then the actors acting on those, then the systems any of them touch.
    drawn =
      cards
      |> Enum.filter(&(&1.kind in @always or own.(&1)))
      |> MapSet.new(& &1.id)
      |> touched(cards, flow ++ projected, "event")
      |> touched(cards, access, "actor")
      |> touched(cards, outside, "external")

    groups =
      for unit <- nodes(document, "unit"),
          do: group("unit", unit, "#{title(unit)} · #{unit["unit_kind"]}")

    finish(
      "LR",
      Enum.filter(cards, &MapSet.member?(drawn, &1.id)),
      apart(flow ++ projected ++ reads ++ access ++ outside),
      groups
    )
  end

  # What a card of the full graph lists under its name: how many scenarios pin a policy, a
  # process manager or a query, "0 scenarios" included, and when a timer fires.
  defp lines(kind, node, pinned) when kind in ~w(policy process_manager query),
    do: [scenarios(pinned[node["id"]] || 0)]

  defp lines("timer", node, _pinned), do: List.wrap(fires(node))
  defp lines(_kind, _node, _pinned), do: []

  # `drawn`, the ids of the cards drawn so far, with those of `kind` one of `arrows` joins
  # to one of them.
  defp touched(drawn, cards, arrows, kind) do
    of_kind = for %{kind: ^kind} = card <- cards, into: MapSet.new(), do: card.id

    for a <- arrows,
        {end_id, other} <- [{a.from, a.to}, {a.to, a.from}],
        MapSet.member?(drawn, other) and MapSet.member?(of_kind, end_id),
        into: drawn,
        do: end_id
  end

  defp flow("emits", r, _by_id, _managers), do: arrow("emits", r)

  # A process manager takes an event as its run starts, during it, or as it ends.
  defp flow(type, r, by_id, managers) when type in ~w(handled_by starts ends) do
    words =
      case type do
        "starts" -> "starts"
        "ends" -> "ends"
        "handled_by" -> if MapSet.member?(managers, r["to"]), do: "during the run"
      end

    delivered(arrow(type, r, words: words), async?(r, by_id[r["to"]]))
  end

  defp flow("issues", r, by_id, _managers),
    do: delivered(arrow("issues", r), async?(r, by_id[r["from"]]))

  defp flow(type, r, _by_id, _managers) when type in ~w(sets cancels),
    do: arrow(type, r, words: type, line: "dotted", head: false)

  defp flow("fires", r, _by_id, _managers), do: arrow("fires", r, words: "async", line: "dotted")

  # A reaction runs after the transaction when it is delivered at least once, and a
  # received event always does, through the inbox.
  defp async?(relation, reaction),
    do:
      relation["via_inbox"] == true or
        (reaction != nil and reaction["delivery"] == "at_least_once")

  # An arrow after the transaction is dotted and says so.
  defp delivered(arrow, false), do: arrow
  defp delivered(arrow, true), do: %{arrow | line: "dotted", words: join([arrow.words, "async"])}

  # An external gives a field of a command or an event its value: a field's `issued_by`.
  defp gives(cards) do
    for %{kind: kind} = card <- cards,
        kind in ~w(command event),
        field <- card.facts["fields"] || [],
        external = field["issued_by"],
        external != nil do
      %{
        id: "gives:#{external}:#{card.id}:#{field["name"]}",
        type: "gives",
        from: external,
        to: card.id,
        facts: field,
        words: "gives #{field["name"]}",
        line: "dotted",
        head: true
      }
    end
  end

  # Two arrows of one type between the same two cards — a manager's, set or issued on
  # two triggers — say which is which.
  defp apart(arrows) do
    parallel = Enum.frequencies_by(arrows, &{&1.type, &1.from, &1.to})

    for a <- arrows do
      if parallel[{a.type, a.from, a.to}] > 1,
        do: %{a | words: join([a.words, phase(a.facts["phase"])])},
        else: a
    end
  end

  defp phase("start"), do: "at start"
  defp phase("run"), do: "during the run"
  defp phase(_none), do: nil

  # --- a process's declared shape ---------------------------------------------------------

  @doc """
  The declared shape of the process in a contract's `document`, top to bottom: its
  stages as boxes in their order, an arrow from each to the next, the events in them —
  those that end it in a colour of their own — each promise as a heavy arrow from the
  event that opens it to the one that keeps it, with its window, and a dotted one to
  the event that keeps it the other way, and the external systems its events rest on.
  A stage with more than one event says on its title that it claims no order inside.
  Without stages every event of the process is drawn; with them, those in a stage.
  Empty without a process.
  """
  @spec declared(map()) :: t()
  def declared(document) do
    case nodes(document, "process") do
      [] -> finish("TB", [], [], [])
      [process | _] -> declared(document, process)
    end
  end

  defp declared(document, process) do
    by_id = index(document)
    stages = for s <- nodes(document, "stage"), s["process"] == process["id"], do: s
    staged = MapSet.new(stages, & &1["id"])

    events =
      for e <- nodes(document, "event"),
          e["unit"] != nil or e["included"] == true,
          stages == [] or MapSet.member?(staged, e["stage"]),
          do:
            card("event", e,
              group: e["stage"],
              variant: if(e["terminal"] == true, do: "terminal")
            )

    shown = MapSet.new(events, & &1.id)
    resting = for r <- relations(document, "depends_on"), MapSet.member?(shown, r["from"]), do: r

    systems =
      resting
      |> Enum.map(& &1["to"])
      |> Enum.uniq()
      |> Enum.flat_map(&List.wrap(by_id[&1] && card("external", by_id[&1])))

    groups =
      for stage <- stages do
        inside = Enum.count(events, &(&1.group == stage["id"]))

        group(
          "stage",
          stage,
          if(inside > 1, do: "#{title(stage)} · no order claimed inside", else: title(stage))
        )
      end

    order =
      for [a, b] <- Enum.chunk_every(stages, 2, 1, :discard) do
        %{
          id: "precedes:#{a["id"]}:#{b["id"]}",
          type: "precedes",
          from: a["id"],
          to: b["id"],
          facts: %{},
          words: nil,
          line: "solid",
          head: true
        }
      end

    promises =
      for p <- nodes(document, "promise"),
          p["process"] == process["id"],
          arrow <- promise(document, p),
          do: arrow

    rests = for r <- resting, do: arrow("depends_on", r, line: "dotted", head: false)

    finish("TB", events ++ systems, order ++ promises ++ rests, groups)
  end

  # A promise as the picture drew it: from the event that opens it to the one that keeps
  # it, and to the one that keeps it the other way. Each arrow has an id of its own, made
  # of the two relations it joins: the promise's id stays the promise node's, whose panel
  # a reader opens from a name.
  defp promise(document, p) do
    at = fn type -> for r <- relations(document, type), r["to"] == p["id"], do: r end
    window = if p["within"], do: "within #{duration(p["within"])}", else: "eventually"

    for opens <- at.("opens"),
        {type, r} <-
          Enum.map(at.("fulfils"), &{"promise", &1}) ++ Enum.map(at.("or_else"), &{"or_else", &1}) do
      %{
        id: "#{type}:#{opens["id"]}:#{r["id"]}",
        type: type,
        from: opens["from"],
        to: r["from"],
        facts: p,
        words: if(type == "promise", do: window, else: "or else"),
        line: if(type == "promise", do: "thick", else: "dotted"),
        head: true
      }
    end
  end

  # --- one unit ---------------------------------------------------------------------------

  @doc """
  Unit `id` of a contract's `document`, left to right: its state as a card listing its
  fields, its commands and the events they emit, the events of other contracts a
  boundary consults, its invariants and its commands' constraints. An arrow a command
  may take — an event it emits, a rule it may be refused on — says how many of the
  unit's scenarios pin it, and says nothing where none does. An aggregate's events
  build its state; a boundary's consulted events say by which fields.
  """
  @spec unit(map(), String.t()) :: t()
  def unit(document, id) do
    case Enum.find(nodes(document, "unit"), &(&1["id"] == id)) do
      nil -> finish("LR", [], [], [])
      unit -> unit(document, unit, index(document))
    end
  end

  defp unit(document, unit, by_id) do
    id = unit["id"]
    commands = for c <- nodes(document, "command"), c["unit"] == id, do: card("command", c)
    own = for e <- nodes(document, "event"), e["unit"] == id, do: card("event", e)
    consulted = for r <- relations(document, "consulted_by"), r["to"] == id, do: r
    owned = MapSet.new(own, & &1.id)

    elsewhere =
      for r <- consulted,
          not MapSet.member?(owned, r["from"]),
          by_id[r["from"]] != nil,
          uniq: true,
          do: card("event", by_id[r["from"]])

    its_commands = MapSet.new(commands, & &1.id)
    invariants = for i <- nodes(document, "invariant"), i["of"] == id, do: card("invariant", i)

    constraints =
      for k <- nodes(document, "constraint"),
          MapSet.member?(its_commands, k["of"]),
          do: card("constraint", k)

    pinned =
      for s <- get_in(document, ["scenarios", "unit"]) || [],
          s["target"] == id,
          covered <- s["covers"] || [],
          reduce: %{} do
        acc -> Map.update(acc, covered, 1, &(&1 + 1))
      end

    from_command = fn type ->
      for r <- relations(document, type), MapSet.member?(its_commands, r["from"]), do: r
    end

    emits =
      for r <- from_command.("emits"),
          do: arrow("emits", r, words: scenarios(pinned[r["id"]]))

    refused =
      for r <- from_command.("refused_on"),
          do:
            arrow("refused_on", r,
              words: join(["may be refused", scenarios(pinned[r["id"]])]),
              line: "dotted"
            )

    builds =
      for r <- relations(document, "builds"),
          r["to"] == id,
          do: arrow("builds", r, line: "dotted")

    consults =
      for r <- consulted, do: arrow("consulted_by", r, words: consulted(r), line: "dotted")

    state =
      card("unit", unit,
        tag: unit["unit_kind"],
        lines: Enum.map(unit["state"] || [], &field(&1, unit["identity"] || []))
      )

    finish(
      "LR",
      [state] ++ commands ++ own ++ elsewhere ++ invariants ++ constraints,
      emits ++ refused ++ builds ++ consults,
      []
    )
  end

  defp scenarios(nil), do: nil
  defp scenarios(n), do: count(n, "scenario")

  defp consulted(%{"match" => [_ | _] = match}), do: "consulted by #{Enum.join(match, ", ")}"
  defp consulted(_where_in_prose), do: "consulted, where stated in prose"

  # A field of the state as the card lists it: its name, its type, and whether it is the
  # unit's identity or may be absent.
  defp field(field, identity) do
    notes =
      Enum.filter(
        [field["name"] in identity && "identity", field["required"] == false && "optional"],
        & &1
      )

    "#{field["name"]}: #{type(field["type"])}" <>
      if(notes == [], do: "", else: " · " <> Enum.join(notes, ", "))
  end

  # --- an aggregate's lifecycle -----------------------------------------------------------

  @doc """
  The lifecycle of aggregate `id` in a contract's `document`, top to bottom: a dot where
  a new one starts, its statuses — an end drawn heavier — and an arrow for each move,
  named by the event that makes it. The dot is the unit's, so a move the lifecycle does
  not allow from where the aggregate stood in no status yet starts there. Empty when
  the unit declares no lifecycle.
  """
  @spec lifecycle(map(), String.t()) :: t()
  def lifecycle(document, id) do
    unit = Enum.find(nodes(document, "unit"), &(&1["id"] == id))
    statuses = for s <- nodes(document, "status"), s["unit"] == id, do: s

    if unit == nil or statuses == [] do
      finish("TB", [], [], [])
    else
      by_id = index(document)
      at = MapSet.new(statuses, & &1["id"])
      event = &title(by_id[&1] || %{"name" => &1})

      start = %{card("start", unit) | name: nil, label: nil, tag: nil}

      cards =
        [start] ++
          for s <- statuses,
              do: card("status", s, variant: if(s["final"] == true, do: "final"))

      enters =
        for r <- relations(document, "enters"),
            MapSet.member?(at, r["to"]),
            do: %{arrow("enters", r, words: event.(r["from"])) | from: id}

      moves =
        for r <- relations(document, "transition"),
            MapSet.member?(at, r["to"]),
            do: arrow("transition", r, words: event.(r["event"]))

      finish("TB", cards, enters ++ moves, [])
    end
  end

  # --- a domain's context map and system --------------------------------------------------

  @doc """
  The context map of a domain's `document`, left to right: its subdomains as groups of
  their contexts, every external system of the domain — one no relation reaches too —
  and the relations between them, each named by its pattern: one with a direction an
  arrow from its upstream to its downstream, a symmetric one a line, `separate_ways` a
  dotted one.
  """
  @spec context_map(map()) :: t()
  def context_map(document) do
    contexts = for c <- nodes(document, "context"), do: card("context", c, group: c["subdomain"])
    externals = for x <- nodes(document, "external"), do: card("external", x)

    groups =
      for s <- nodes(document, "subdomain"),
          do: group("subdomain", s, "#{title(s)} · #{s["type"]}")

    # A relation between two contexts, or a context and an external, is a pattern: the
    # only kind the domain's document holds between them. One declared `between:` its
    # ends is symmetric, and has no head.
    mapped = MapSet.new(contexts ++ externals, & &1.id)

    arrows =
      for {type, group} <- document["relations"] || %{},
          r <- group,
          MapSet.member?(mapped, r["from"]) and MapSet.member?(mapped, r["to"]) do
        arrow(type, r,
          words: words(type),
          line: if(type == "separate_ways", do: "dotted", else: "solid"),
          head: r["symmetric"] != true
        )
      end

    finish("LR", contexts ++ externals, arrows, groups)
  end

  @doc """
  The system of a domain's `document`, left to right: its contracts in groups of their
  contexts, each named by its module's last segment and its process, an arrow from a
  contract to one that consumes its events, carrying their names, and the publications
  on the wire, with an arrow from the contract that publishes one and to the one that
  subscribes.
  """
  @spec system(map()) :: t()
  def system(document) do
    by_id = index(document)

    contracts =
      for c <- nodes(document, "contract") do
        short = c["module"] |> to_string() |> String.split(".") |> List.last()
        label = join([short, get_in(c, ["process", "label"])])
        %{card("contract", c, group: c["context"]) | label: label}
      end

    publications = for p <- nodes(document, "publication"), do: card("publication", p)
    name = &((by_id[&1] || %{})["name"] || &1)

    consumed =
      for r <- relations(document, "consumed_by") do
        arrow("consumed_by", r,
          words: Enum.map_join(r["events"] || [], ", ", &name.(&1["event"]))
        )
      end

    published =
      for r <- relations(document, "publishes"),
          do: arrow("publishes", r, words: "publishes #{name.(r["event"])}", line: "dotted")

    subscribed =
      for r <- relations(document, "subscribed_by"),
          do: arrow("subscribed_by", r, words: "as #{r["as"]}", line: "dotted")

    groups = for c <- nodes(document, "context"), do: group("context", c, "#{title(c)} · context")

    finish("LR", contracts ++ publications, consumed ++ published ++ subscribed, groups)
  end

  # --- what the log saw -------------------------------------------------------------------

  # Without an overlay, the view as it is.
  defp observed(view, _document, nil), do: view

  defp observed(view, document, overlay) do
    by_id = index(document)

    arrows =
      for r <- get_in(overlay, ["observed", "relations", "undeclared"]) || [] do
        event = by_id[r["event"]] || (r["event"] && %{"name" => r["event"]})

        arrow("undeclared", r,
          words: join([event && title(event), "not declared"]),
          line: "dotted"
        )
      end

    %{view | relations: view.relations ++ within(view, arrows)}
  end

  # --- building blocks --------------------------------------------------------------------

  defp nodes(document, kind), do: get_in(document, ["nodes", kind]) || []
  defp relations(document, type), do: get_in(document, ["relations", type]) || []

  # Every node of the document by its id.
  defp index(document) do
    for {_kind, group} <- document["nodes"] || %{},
        node <- group,
        into: %{},
        do: {node["id"], node}
  end

  defp card(kind, node, extra \\ []) do
    Map.merge(
      %{
        id: node["id"],
        kind: kind,
        name: node["name"],
        label: node["label"],
        facts: node,
        group: nil,
        tag: words(kind),
        lines: [],
        variant: nil
      },
      Map.new(extra)
    )
  end

  defp arrow(type, relation, extra \\ []) do
    Map.merge(
      %{
        id: relation["id"],
        type: type,
        from: relation["from"],
        to: relation["to"],
        facts: relation,
        words: nil,
        line: "solid",
        head: true
      },
      Map.new(extra)
    )
  end

  defp group(kind, node, title), do: %{id: node["id"], kind: kind, title: title, facts: node}

  # The view: the groups some card sits in, a card naming no group of the view in none,
  # and the relations whose two ends are in it. A stage nothing sits in is drawn all the
  # same: it is still a stage of the process — a finding, which a picture hiding it would
  # be the wrong tool to find.
  defp finish(direction, cards, arrows, groups) do
    filled = MapSet.new(cards, & &1.group)
    groups = Enum.filter(groups, &(&1.kind == "stage" or MapSet.member?(filled, &1.id)))
    present = MapSet.new(groups, & &1.id)

    cards =
      for c <- cards, do: if(MapSet.member?(present, c.group), do: c, else: %{c | group: nil})

    view = %{direction: direction, nodes: cards, relations: [], groups: groups}
    %{view | relations: within(view, arrows)}
  end

  defp within(view, arrows) do
    ids = MapSet.new(view.nodes ++ view.groups, & &1.id)
    Enum.filter(arrows, &(MapSet.member?(ids, &1.from) and MapSet.member?(ids, &1.to)))
  end

  defp title(node), do: node["label"] || node["name"]

  defp join(parts) do
    case Enum.reject(parts, &(&1 in [nil, false, ""])) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end
end
