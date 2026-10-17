defmodule EhOsContract.GraphRenderer.View do
  # The six pictures are plan E13b, batch 3, the user's decision of 8 October; a process
  # module's picture replaced a contract's declared shape in plan DD, P2e (#220).
  @moduledoc """
  Which facts of a document are drawn together, and how they read: a view is the
  nodes one picture shows, the groups they sit in, the relations between them with
  their words and their line, and which way the picture runs.

  A document groups its nodes by kind and its relations by type
  (`EhOsContract.Graph.Document` in the engine). A view flattens them into the lists
  the drawing layer takes, and keeps a relation only when both of its ends are in the
  view, so that no arrow points at nothing.

  **The views are the pictures the engine drew before this package**, each chosen here
  from the graph of facts rather than built by the engine:

  | View (`t:spec/0`) | Of | What it shows |
  | --- | --- | --- |
  | `:contract` | a contract | its full graph: commands and events in their units, the reactions and timers between them, read models and queries, and the actors and external systems they touch |
  | `{:unit, id}` | a contract | one unit's state, commands, events and rules, and how many scenarios pin each path |
  | `{:lifecycle, id}` | a contract | an aggregate's statuses and the events that move it between them |
  | `:process` | a process module | the process and who answers for it, its stages in order, the events each includes with the contract that declares them, those that end a run, its promises with their windows, and the systems its events rest on |
  | `:context_map` | a domain | its subdomains, contexts, external systems and their relations |
  | `:system` | a domain | its contracts in their contexts, what one consumes from another, whose units' numbers one keeps, its publications, and its process modules with the contracts whose events each includes |
  | `:landscape` | a landscape | several domains, each a box of the contracts that publish or subscribe, and a card per name on the wire between them (`EhOsContract.GraphRenderer.Landscape`) |

  Each says what the picture said, in its words: an arrow after the transaction is
  dotted and says `async`, a promise is a heavy arrow with its window, a relation
  that is not a delivery has no arrowhead. **Where the facts are finer than the
  picture was**, the view follows the facts: a process manager's start, its end and an
  event it takes during its run are arrows of their own, even where nothing is issued
  on them (`starts`, `ends`, `during the run`), a timer it cancels is drawn as one it
  sets is, and two arrows of one type between the same two cards — a timer set as a run
  starts and again during it — say which is which.

  `:all`, every node and every relation, stays as the drawing layer's test bed.
  `build/3` builds the view a `t:spec/0` names, with what an overlay observed that
  the document does not declare; `views/1` lists the views a document has. A view of
  another kind of document than the one it is of is empty.
  """

  import EhOsContract.GraphRenderer.Words

  alias EhOsContract.GraphRenderer.{Audience, Places}

  @typedoc "A view by name: a unit's and a lifecycle's take the unit's id."
  @type spec ::
          :all
          | :contract
          | {:unit, String.t()}
          | {:lifecycle, String.t()}
          | :process
          | :context_map
          | :system
          | :landscape

  @typedoc """
  A node as the drawing layer takes it. `facts` is the document's node, whole; `group`
  the id of the group the card sits in; `tag` the small line above its label, `lines`
  what the card lists under it, `foot` where the card's element lives when the picture
  does not say it already (the contract that declares an event of a process, or of
  another contract), and `variant` a look of its kind: `"terminal"`, `"final"`.
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
          foot: String.t() | nil,
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

  @typedoc "Who reads a view: the engineer, everything; the business owner, the client's words."
  @type audience :: :engineering | :owner

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
  screen shows the pictures: a domain's context map, then its system where it has
  contracts; a process module's picture; a contract's full graph, then each unit and,
  where it declares one, the unit's lifecycle.

      View.views(process_document)
      #=> [{:process, "Process — A loan, from lending to return"}]
  """
  @spec views(map()) :: [{spec(), String.t()}]
  def views(%{"kind" => "domain"} = document) do
    [{:context_map, "Context map"}] ++
      if nodes(document, "contract") == [], do: [], else: [{:system, "System"}]
  end

  def views(%{"kind" => "landscape"}), do: [{:landscape, "Landscape"}]

  def views(%{"kind" => "process"} = document),
    do: for(p <- nodes(document, "process"), do: {:process, "Process — #{title(p)}"})

  def views(document) do
    lifecycles = MapSet.new(nodes(document, "status"), & &1["unit"])

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
  anyway, and a process's stage a run entered before an earlier one, an arrow from the
  later stage back — where both their ends are in it. A unit or a lifecycle the document does
  not have is an empty view.

  `audience` is who reads it: `:engineering`, the default, or `:owner`, for whom a card
  says its label and not its name in code, a field is its label, and what only the code
  reads — delivery, correlation, the wire between applications — is not drawn.
  """
  @spec build(map(), spec(), map() | nil, audience()) :: t()
  def build(document, spec, overlay \\ nil, audience \\ :engineering) do
    document = Audience.read(document, audience)
    document |> view(spec, audience) |> observed(document, overlay) |> read_by(audience)
  end

  # A card with a label says it alone to the owner; one without says its name, which
  # `mix eh_os_contract.check` notes (`owner-view-without-label`).
  defp read_by(view, :owner),
    do: %{view | nodes: for(n <- view.nodes, do: if(n.label, do: %{n | name: nil}, else: n))}

  defp read_by(view, _engineering), do: view

  # The order a legend lists kinds in: who acts, what is decided, what reacts, what is
  # read, the rules, what is outside, and the domain's own kinds.
  @kinds ~w(actor command unit event status policy process_manager timer effect read_model
            query invariant constraint domain_service external process context contract
            publication)

  # What each look of an arrow means, in the order a legend lists them.
  @lines [
    {"solid", "leads to"},
    {"dotted", "after the transaction, or a relation that causes nothing"},
    {"thick", "a promise, with its window"},
    {"headless", "rests on, belongs to, or goes both ways"},
    {"observed", "seen in the log, and not declared"}
  ]

  # The relations an overlay adds to a view, which the log shows and no declaration says.
  @observed ~w(undeclared out_of_order)

  # What a card drawn other than its kind means.
  @variants [{"terminal", "ends a run"}, {"final", "a final status"}]

  @doc """
  What a legend of `view` lists: the kinds of the cards it draws, in a fixed order, the
  cards drawn other than their kind (an event that ends a run, a final status), and the
  looks of the arrows it draws, each with what it means. Only what the view has is
  listed, so a legend never explains what the picture does not show.

      View.legend(view)
      #=> %{kinds: [{"command", "command"}, {"event", "event"}],
      #     variants: [], lines: [{"solid", "leads to"}]}
  """
  @spec legend(t()) :: %{
          kinds: [{String.t(), String.t()}],
          variants: [{String.t(), String.t()}],
          lines: [{String.t(), String.t()}]
        }
  def legend(view) do
    drawn = MapSet.new(view.nodes, & &1.kind)
    rank = Map.new(Enum.with_index(@kinds))

    kinds =
      drawn
      |> Enum.reject(&(&1 == "start"))
      |> Enum.sort_by(&{Map.get(rank, &1, length(@kinds)), &1})
      |> Enum.map(&{&1, words(&1)})

    # A line's look and whether it has a head are two things to explain: a dotted line with
    # no head is both dotted and headless.
    looks =
      for relation <- view.relations,
          look <-
            [relation.line] ++
              if(relation.head, do: [], else: ["headless"]) ++
              if(observed?(relation), do: ["observed"], else: []),
          into: MapSet.new(),
          do: look

    variants = MapSet.new(view.nodes, & &1.variant)

    %{
      kinds: kinds,
      variants: for({variant, _} = v <- @variants, variant in variants, do: v),
      lines: for({look, _} = line <- @lines, look in looks, do: line)
    }
  end

  @doc """
  `view` narrowed to what is around `id`: the card or the group `id` names, every card
  one of its relations reaches, the boxes those cards sit in, and the relations between
  what is left. A group keeps its cards. How a large picture is read one neighbourhood at
  a time; an `id` the view does not draw leaves it as it is.

      View.around(view, "command:rehmed.settlement:close_settlement")
  """
  @spec around(t(), String.t()) :: t()
  def around(view, id) do
    group? = Enum.any?(view.groups, &(&1.id == id))

    if group? or Enum.any?(view.nodes, &(&1.id == id)) do
      touching = Enum.filter(view.relations, &(&1.from == id or &1.to == id))
      members = if group?, do: for(%{group: ^id} = n <- view.nodes, do: n.id), else: []
      keep = MapSet.new([id | members ++ Enum.flat_map(touching, &[&1.from, &1.to])])

      nodes = Enum.filter(view.nodes, &MapSet.member?(keep, &1.id))
      boxes = MapSet.new(nodes, & &1.group)

      groups =
        Enum.filter(view.groups, &(MapSet.member?(keep, &1.id) or MapSet.member?(boxes, &1.id)))

      kept = MapSet.new(nodes ++ groups, & &1.id)

      %{
        view
        | nodes: nodes,
          groups: groups,
          relations:
            Enum.filter(
              view.relations,
              &(MapSet.member?(kept, &1.from) and MapSet.member?(kept, &1.to))
            )
      }
    else
      view
    end
  end

  @doc """
  The ids of the cards of `view` that `query` finds: those whose label, name in code,
  kind or footer holds it, ignoring case. `nil` for a blank query, which finds nothing and
  dims nothing. The dot where a new aggregate starts says nothing and is never searched.

      View.matches(view, "cancel")
      #=> MapSet.new(["command:scheduling:cancel_visit"])
  """
  @spec matches(t(), String.t() | nil) :: MapSet.t(String.t()) | nil
  def matches(view, query) do
    case String.downcase(String.trim(query || "")) do
      "" ->
        nil

      term ->
        for node <- view.nodes,
            node.kind != "start",
            [node.label, node.name, node.tag, node.foot]
            |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), term))),
            into: MapSet.new(),
            do: node.id
    end
  end

  defp view(document, :all, _audience), do: all(document)
  defp view(document, :contract, audience), do: contract(document, audience)
  defp view(document, :process, _audience), do: process(document)
  defp view(document, {:unit, id}, audience), do: unit(document, id, audience)
  defp view(document, {:lifecycle, id}, _audience), do: lifecycle(document, id)
  defp view(document, :context_map, _audience), do: context_map(document)
  defp view(document, :system, audience), do: system(document, audience)
  defp view(document, :landscape, _audience), do: landscape(document)

  # Every node and every relation of `document`, kinds and types in name order and each
  # group in the document's order, so the same document gives the same view and the
  # same layout. Each relation says its type.
  # Called by `build/3`; public for its tests.
  @doc false
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

  # The full graph of a contract's `document`, left to right: each unit's commands and
  # events in a group of the unit's own, and the policies,
  # process managers, effects and timers between them; its read models with the events
  # they project and the queries over them; the actors who issue, record or ask, and the
  # external systems an effect calls, an event rests on, a system actor is backed by, or
  # a field takes its value from. A policy, a process manager and a query say how many
  # scenarios pin them, "0 scenarios" included, and a timer when it fires.
  # Called by `build/3`; public for its tests.
  @doc false
  @spec contract(map(), audience()) :: t()
  def contract(document, audience \\ :engineering) do
    by_id = index(document)
    own = &(&1.kind == "event" and &1.facts["unit"] != nil)

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
          lines: lines(kind, node, pinned, audience),
          foot: if(kind == "event", do: home(node, audience))
        )
      end

    managers = MapSet.new(nodes(document, "process_manager"), & &1["id"])

    flow =
      for type <- @flow,
          r <- relations(document, type),
          do: flow(type, r, by_id, managers, audience)

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

    outside = calls ++ rests ++ backed ++ gives(cards, audience)

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
          do: group("unit", unit, "#{title(unit)} · #{unit_kind(unit)}")

    finish(
      "LR",
      Enum.filter(cards, &MapSet.member?(drawn, &1.id)),
      apart(flow ++ projected ++ reads ++ access ++ outside),
      groups
    )
  end

  # What a card of the full graph lists under its name: how many scenarios pin a policy, a
  # process manager or a query, "0 scenarios" included, and when a timer fires — for the
  # owner, one set for a moment its run holds without the field that holds it.
  defp lines(kind, node, pinned, _audience) when kind in ~w(policy process_manager query),
    do: [scenarios(pinned[node["id"]] || 0)]

  defp lines("timer", %{"at" => at}, _pinned, :owner) when is_binary(at),
    do: ["at a moment the run holds"]

  defp lines("timer", node, _pinned, _audience), do: List.wrap(fires(node))
  defp lines(_kind, _node, _pinned, _audience), do: []

  # Where an event of a contract is declared, when not in one of its units: the sibling
  # contract it is consumed from (`Places.declared_in/1`), or another application it is
  # received from. The document holds no label of the sibling for the owner to read it by.
  defp home(%{"unit" => unit}, _audience) when is_binary(unit), do: nil

  defp home(consumed, audience)
       when is_map_key(consumed, "declared_as") or is_map_key(consumed, "declared_in"),
       do:
         if(Audience.code?(audience), do: Places.declared_in(consumed), else: "another contract")

  defp home(_received, _audience), do: "another application"

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

  defp flow("emits", r, _by_id, _managers, _audience), do: arrow("emits", r)

  # A process manager takes an event as its run starts, during it, or as it ends.
  defp flow(type, r, by_id, managers, _audience) when type in ~w(handled_by starts ends) do
    words =
      case type do
        "starts" -> "starts"
        "ends" -> "ends"
        "handled_by" -> if MapSet.member?(managers, r["to"]), do: "during the run"
      end

    delivered(arrow(type, r, words: words), async?(r, by_id[r["to"]]))
  end

  defp flow("issues", r, by_id, _managers, _audience),
    do: delivered(arrow("issues", r), async?(r, by_id[r["from"]]))

  defp flow(type, r, _by_id, _managers, _audience) when type in ~w(sets cancels),
    do: arrow(type, r, words: type, line: "dotted", head: false)

  # A timer fires after the transaction that set it, which the owner does not read.
  defp flow("fires", r, _by_id, _managers, audience),
    do: arrow("fires", r, words: if(Audience.code?(audience), do: "async"), line: "dotted")

  # A reaction runs after the transaction when it is delivered at least once, and a
  # received event always does, through the inbox.
  defp async?(relation, reaction),
    do:
      relation["via_inbox"] == true or
        (reaction != nil and reaction["delivery"] == "at_least_once")

  # An arrow after the transaction is dotted and says so.
  defp delivered(arrow, false), do: arrow
  defp delivered(arrow, true), do: %{arrow | line: "dotted", words: join([arrow.words, "async"])}

  # An external gives a field of a command or an event its value: a field's `issued_by`,
  # named by its label for the owner.
  defp gives(cards, audience) do
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
        words: "gives #{if Audience.code?(audience), do: field["name"], else: field["label"]}",
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

  # --- a process module ------------------------------------------------------------------

  # The picture of a process module's `document`, top to bottom: the process as a card,
  # saying what one run is and its deadline, with the actor accountable for it; its
  # stages as boxes in their order, an arrow from each to the next; in each, the events
  # it includes, each saying the contract that declares it, those that end a run in a
  # colour of their own; each promise as a heavy arrow from the event that opens it to
  # the one that keeps it, with its window, and a dotted one to the event that keeps it
  # the other way; and the external systems its events rest on, hung off them by a dotted
  # line, since an outage of one suspends a promise, as are those a promise waits on, off
  # the event that opens it. A stage with more than one event says
  # on its title that it claims no order inside. Empty for another kind of document.
  # Called by `build/3`; public for its tests.
  @doc false
  @spec process(map()) :: t()
  def process(%{"kind" => "process"} = document) do
    by_id = index(document)

    processes =
      for p <- nodes(document, "process"),
          do: card("process", p, lines: Enum.reject([run(p), deadline(p)], &is_nil/1))

    stages = nodes(document, "stage")

    events =
      for e <- nodes(document, "event") do
        card("event", e,
          group: e["stage"],
          foot: by_id[e["contract"]] && title(by_id[e["contract"]]),
          variant: if(e["terminal"] == true, do: "terminal")
        )
      end

    {actors, accountable} = accountable(document, by_id)

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

    promises = for p <- nodes(document, "promise"), arrow <- promise(document, p), do: arrow

    systems = for x <- nodes(document, "external"), do: card("external", x)

    rests =
      for r <- relations(document, "depends_on"),
          do: arrow("depends_on", r, line: "dotted", head: false)

    finish(
      "TB",
      processes ++ actors ++ events ++ systems,
      accountable ++ order ++ promises ++ rests ++ waits(document),
      groups
    )
  end

  def process(_document), do: finish("TB", [], [], [])

  # What one run of a process is, and how long it may take.
  defp run(%{"correlate" => [_ | _] = fields}), do: "one run per #{Enum.join(fields, ", ")}"
  defp run(_process), do: nil

  defp deadline(%{"deadline" => %{} = deadline}),
    do:
      "ends within #{duration(deadline)}" <>
        if(deadline["unverified"] == true, do: " · not confirmed", else: "")

  defp deadline(_process), do: nil

  # The actors who answer for a process, and an arrow from each to it.
  defp accountable(document, by_id) do
    arrows =
      for r <- relations(document, "accountable_for"),
          do: arrow("accountable_for", r, words: "accountable for", head: false)

    actors =
      arrows
      |> Enum.map(& &1.from)
      |> Enum.uniq()
      |> Enum.flat_map(&List.wrap(by_id[&1] && card("actor", by_id[&1])))

    {actors, arrows}
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

  # What a promise waits on through an earlier step: a promise is no card here, so the
  # arrow leaves the event that opens it, where its window starts, for the system.
  defp waits(document) do
    for r <- relations(document, "waits_on"),
        opens <- relations(document, "opens"),
        opens["to"] == r["from"] do
      %{
        id: "waits_on:#{opens["id"]}:#{r["id"]}",
        type: "waits_on",
        from: opens["from"],
        to: r["to"],
        facts: r,
        words: "waits on",
        line: "dotted",
        head: false
      }
    end
  end

  # --- one unit ---------------------------------------------------------------------------

  # Unit `id` of a contract's `document`, left to right: its state as a card listing its
  # fields, its commands and the events they emit, the events from elsewhere a boundary
  # consults, each with a footer saying the unit or the contract it lives in, its
  # invariants and its commands' constraints. An arrow a command
  # may take — an event it emits, a rule it may be refused on — says how many of the
  # unit's scenarios pin it, and says nothing where none does. An aggregate's events
  # build its state; a boundary's consulted events say by which fields.
  # Called by `build/3`; public for its tests.
  @doc false
  @spec unit(map(), String.t(), audience()) :: t()
  def unit(document, id, audience \\ :engineering) do
    case Enum.find(nodes(document, "unit"), &(&1["id"] == id)) do
      nil -> finish("LR", [], [], [])
      unit -> unit(document, unit, index(document), audience)
    end
  end

  defp unit(document, unit, by_id, audience) do
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
          do:
            card("event", by_id[r["from"]],
              foot: consulted_home(by_id[r["from"]], by_id, audience)
            )

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
        tag: unit_kind(unit),
        lines: Enum.map(unit["state"] || [], &field(&1, unit["identity"] || [], audience))
      )

    finish(
      "LR",
      [state] ++ commands ++ own ++ elsewhere ++ invariants ++ constraints,
      emits ++ refused ++ builds ++ consults,
      []
    )
  end

  # Where an event a unit consults lives: another unit of its contract, named by its title,
  # or, for one of another contract, what `home/1` says.
  defp consulted_home(%{"unit" => unit}, by_id, _audience) when is_binary(unit),
    do: by_id[unit] && title(by_id[unit])

  defp consulted_home(event, _by_id, audience), do: home(event, audience)

  # A unit's kind, and that it records only when the document says so: none of its
  # commands can be refused, so it decides nothing (plan DD, C1, #304).
  defp unit_kind(%{"records_only" => true} = unit), do: "#{unit["unit_kind"]} · records only"
  defp unit_kind(unit), do: unit["unit_kind"]

  defp scenarios(nil), do: nil
  defp scenarios(n), do: count(n, "scenario")

  defp consulted(%{"match" => [_ | _] = match}), do: "consulted by #{Enum.join(match, ", ")}"

  defp consulted(%{"where" => where}) when is_binary(where),
    do: "consulted, where stated in prose"

  defp consulted(_relation), do: "consulted"

  # A field of the state as the card lists it: its name, its type, and whether it is the
  # unit's identity or may be absent; for the owner, its label and whether it may be absent.
  defp field(field, _identity, :owner),
    do: field["label"] <> if(field["required"] == false, do: " · optional", else: "")

  defp field(field, identity, _engineering) do
    notes =
      Enum.filter(
        [field["name"] in identity && "identity", field["required"] == false && "optional"],
        & &1
      )

    "#{field["name"]}: #{type(field["type"])}" <>
      if(notes == [], do: "", else: " · " <> Enum.join(notes, ", "))
  end

  # --- an aggregate's lifecycle -----------------------------------------------------------

  # The lifecycle of aggregate `id` in a contract's `document`, top to bottom: a dot where
  # a new one starts, its statuses — an end drawn heavier — and an arrow for each move,
  # named by the event that makes it. The dot is the unit's, so a move the lifecycle does
  # not allow from where the aggregate stood in no status yet starts there. Empty when
  # the unit declares no lifecycle.
  # Called by `build/3`; public for its tests.
  @doc false
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

  # The context map of a domain's `document`, left to right: its subdomains as groups of
  # their contexts, every external system of the domain — one no relation reaches too —
  # and the relations between them, each named by its pattern: one with a direction an
  # arrow from its upstream to its downstream, a symmetric one a line, `separate_ways` a
  # dotted one.
  # Called by `build/3`; public for its tests.
  @doc false
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

  # The system of a domain's `document`, left to right: its contracts in groups of their
  # contexts, each named by its module's last segment, an arrow from a contract to one
  # that consumes its events, carrying their names, a dotted one from a contract to one
  # keeping the number of its unit, naming the units, and the publications on the wire,
  # with an arrow from the contract that publishes one and to the one that subscribes;
  # and its process modules, a dotted arrow from each to every contract whose events it
  # includes, and the actor accountable for it.
  # Called by `build/3`; public for its tests.
  @doc false
  @spec system(map(), audience()) :: t()
  def system(document, audience \\ :engineering) do
    by_id = index(document)

    contracts = for c <- nodes(document, "contract"), do: contract_card(c, c["context"])

    processes = for p <- nodes(document, "process"), do: card("process", p)

    includes =
      for r <- relations(document, "includes"),
          do: arrow("includes", r, words: "includes", line: "dotted")

    {actors, accountable} = accountable(document, by_id)

    publications = for p <- nodes(document, "publication"), do: card("publication", p)

    # An event a contract consumes, by its name, or its label for the owner.
    name =
      if Audience.code?(audience),
        do: &((by_id[&1] || %{})["name"] || &1),
        else: &title(by_id[&1] || %{"name" => &1})

    consumed =
      for r <- relations(document, "consumed_by") do
        arrow("consumed_by", r,
          words: Enum.map_join(r["events"] || [], ", ", &name.(&1["event"]))
        )
      end

    # Drawn the way the number travels, from the unit's contract to the one keeping it,
    # as a consumed event is: against `refers_to`, a consumer keeping its source's unit
    # would close a cycle the layout breaks by turning the source's arrows around.
    referring =
      for r <- relations(document, "refers_to"),
          do:
            arrow("refers_to", r,
              from: r["to"],
              to: r["from"],
              # The owner's document leaves the units' names in code out.
              words:
                if(r["units"] in [nil, []],
                  do: "number",
                  else: "number of #{Enum.join(r["units"], ", ")}"
                ),
              line: "dotted"
            )

    groups = for c <- nodes(document, "context"), do: group("context", c, "#{title(c)} · context")

    finish(
      "LR",
      contracts ++ publications ++ processes ++ actors,
      consumed ++ referring ++ wire(document, by_id) ++ includes ++ accountable,
      groups
    )
  end

  # A landscape's `document` (`EhOsContract.GraphRenderer.Landscape`), left to right: a box
  # per domain, titled with its application and saying how many contracts it leaves out,
  # its contracts on the wire in it, each named by its module's last segment, and a card
  # per name on the wire, with a dotted arrow from each contract that publishes it and to
  # each that subscribes, as the system draws them.
  # Called by `build/3`; public for its tests.
  @doc false
  @spec landscape(map()) :: t()
  def landscape(%{"kind" => "landscape"} = document) do
    contracts = for c <- nodes(document, "contract"), do: contract_card(c, c["in"])

    publications =
      for p <- nodes(document, "publication") do
        outside = if p["outside"], do: [tag: "publication · from outside the set"], else: []
        card("publication", p, outside)
      end

    groups =
      for d <- nodes(document, "domain") do
        others = d["others"] || 0
        group("domain", d, join([d["label"], others > 0 && count(others, "more contract")]))
      end

    finish("LR", contracts ++ publications, wire(document, index(document)), groups)
  end

  def landscape(_document), do: finish("LR", [], [], [])

  # A contract's card on a map of contracts, in `group`: named by its module's last segment,
  # or by the label the owner's document gives it.
  defp contract_card(contract, group) do
    short =
      case contract["module"] do
        module when is_binary(module) and module != "" ->
          module |> String.split(".") |> List.last()

        _none ->
          contract["name"]
      end

    %{card("contract", contract, group: group) | label: contract["label"] || short}
  end

  # The publications' arrows: a dotted one from a contract to what it publishes, naming the
  # event, and from a publication to a contract that subscribes, naming what it takes it as.
  defp wire(document, by_id) do
    name = &((by_id[&1] || %{})["name"] || &1)

    for(
      r <- relations(document, "publishes"),
      do: arrow("publishes", r, words: "publishes #{name.(r["event"])}", line: "dotted")
    ) ++
      for r <- relations(document, "subscribed_by"),
          do: arrow("subscribed_by", r, words: "as #{r["as"]}", line: "dotted")
  end

  # --- what the log saw -------------------------------------------------------------------

  # Without an overlay, the view as it is. With one, a move a lifecycle does not allow,
  # and a process's stages runs entered the wrong way round (plan DD, O2, #319): an arrow
  # from the later stage back to the earlier one.
  defp observed(view, _document, nil), do: view

  defp observed(view, document, overlay) do
    by_id = index(document)

    arrows =
      for r <- seen(overlay, "undeclared") do
        event = by_id[r["event"]] || (r["event"] && %{"name" => r["event"]})

        arrow("undeclared", r,
          words: join([event && title(event), "not declared"]),
          line: "dotted"
        )
      end

    order =
      for r <- seen(overlay, "out_of_order"),
          do: arrow("out_of_order", r, words: "entered first", line: "dotted")

    # An overlay may come from another application, so an entry that is not a relation, or
    # that names one the view already draws, or another entry's, is left out.
    taken = MapSet.new(view.relations, & &1.id)

    added =
      (arrows ++ order) |> Enum.reject(&MapSet.member?(taken, &1.id)) |> Enum.uniq_by(& &1.id)

    %{view | relations: view.relations ++ within(view, added)}
  end

  defp seen(%{"observed" => %{"relations" => %{} = relations}}, type) do
    case relations[type] do
      list when is_list(list) -> Enum.filter(list, &relation?(&1, type))
      _ -> []
    end
  end

  defp seen(_overlay, _type), do: []

  # An entry of the shape its type has: string ends and id, and for stages out of order,
  # a count of runs, so a broken entry never takes the place of a good one of its id.
  defp relation?(%{} = r, type) do
    Enum.all?(~w(id from to), &is_binary(r[&1])) and
      (type != "out_of_order" or (is_integer(r["runs"]) and r["runs"] > 0))
  end

  defp relation?(_entry, _type), do: false

  @doc """
  Whether `relation` is one the log shows and the document does not declare — a move a
  lifecycle does not allow, stages entered the wrong way round — rather than one the
  document draws. Such an arrow is drawn where its ends are, and lays nothing out.

      View.observed?(%{type: "out_of_order"})
      #=> true
      View.observed?(%{type: "precedes"})
      #=> false
  """
  @spec observed?(relation()) :: boolean()
  def observed?(%{type: type}), do: type in @observed
  def observed?(_relation), do: false

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
        foot: nil,
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
