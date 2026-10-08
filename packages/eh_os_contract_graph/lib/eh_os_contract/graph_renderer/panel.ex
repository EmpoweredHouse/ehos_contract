defmodule EhOsContract.GraphRenderer.Panel do
  @moduledoc """
  The panel beside a graph: what the selected node, group or relation is, read from
  the `graph.v1` document it belongs to (plan E13b, batch 4; the working plan's points
  1, 2, 6 and 8 to 12, and "Pole", in "Szczegóły ekranu Graph").

  Everything here is the document's: a node's own facts, and the joins over relations
  and scenarios `EhOsContract.GraphRenderer.Lookup` makes — who may issue a command is
  the `may_issue` relations into it, what depends on an event the relations out of it,
  the scenarios behind an arrow those whose `covers` names it. Nothing is derived from
  the DSL's meaning; that is the engine's, and it is in the document already.

  The client's words — labels, terms, rules, scenario descriptions — are shown as the
  client wrote them; the sentences around them are the renderer's, in English. A node
  named in a panel is a button that selects it, whether or not the view draws it.

  | Selected | The panel shows |
  | --- | --- |
  | a command | its fields, who may issue it (people with the grant EHOS gives, reactions, timers), its scope, the statuses it is allowed in, the rules it may be refused on |
  | an event | its fields, who records it, where it comes from, whether it ends the run, the systems it rests on, everything that depends on it, where it leaves for other applications |
  | a policy, a process manager | what it takes and issues, its rules, delivery and idempotency, its scenarios — a manager's by what triggers them |
  | an effect | the event it handles, the system and the operation it calls, its rules, delivery and idempotency |
  | a read model, a query | what builds it and its fields; the query's parameters, who may ask, what it reads and returns, its scenarios |
  | a context, an external system, an actor | the context's terms, relations, contracts and entities; the system's operations, outage and who uses it; the actor's role, responsibilities and what the role may do |
  | a relation | its two ends, what it says, and the scenarios that cover it |

  A field is shown the same way everywhere it appears: its name, label, type, whether
  it is required, its default, and what it says of a person (personal data, or a
  pointer to one), of a domain value (its members or unit), of an entity and of the
  system that gives its value.
  """

  use Phoenix.Component

  alias EhOsContract.GraphRenderer.Lookup

  attr :picked, :any, required: true, doc: "`{:node | :group | :relation, element}` of a view"
  attr :lookup, Lookup, required: true, doc: "the joins over the element's document"
  attr :overlay, :map, default: nil
  attr :target, :any, required: true, doc: "where a click on a reference goes"

  @doc "The panel of what is selected."
  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    # Every part takes the joins and the click's target together.
    assigns |> assign(:ctx, %{lookup: assigns.lookup, target: assigns.target}) |> selected()
  end

  defp selected(%{picked: {:relation, relation}} = assigns) do
    assigns =
      assign(assigns,
        relation: relation,
        covering: Lookup.covering(assigns.lookup, relation.id),
        log: get_in(assigns.overlay || %{}, ["relations", relation.id])
      )

    ~H"""
    <aside class="ehg-panel" aria-label="Selected">
      <header>
        <p class="ehg-panel-kind">relation</p>
        <h4>{words(@relation.type)}</h4>
        <button type="button" phx-click="deselect" phx-target={@ctx.target} aria-label="Close">×</button>
      </header>
      <dl>
        <dt>from</dt>
        <dd><.ref id={@relation.from} ctx={@ctx} /></dd>
        <dt>to</dt>
        <dd><.ref id={@relation.to} ctx={@ctx} /></dd>
      </dl>
      <.relation_body
        type={@relation.type}
        relation={@relation}
        facts={@relation.facts}
        ctx={@ctx}
      />
      <.scenarios :if={@covering != []} title="Scenarios covering it" list={@covering} ctx={@ctx} />
      <.log :if={@log} entry={@log} ctx={@ctx} />
    </aside>
    """
  end

  defp selected(%{picked: {_node_or_group, element}} = assigns) do
    # A lifecycle's start is drawn as a dot of its own, and is the unit's.
    kind = if element.kind == "start", do: "unit", else: element.kind
    node = element.facts

    assigns =
      assign(assigns,
        kind: kind,
        node: node,
        log: get_in(assigns.overlay || %{}, ["nodes", node["id"]])
      )

    ~H"""
    <aside class="ehg-panel" aria-label="Selected">
      <header>
        <p class="ehg-panel-kind">{words(@kind)}</p>
        <h4>{@node["label"] || @node["name"]}</h4>
        <button type="button" phx-click="deselect" phx-target={@ctx.target} aria-label="Close">×</button>
        <p :if={@node["label"] && @node["name"]} class="ehg-panel-name">{@node["name"]}</p>
      </header>
      <.body kind={@kind} node={@node} ctx={@ctx} />
      <p :if={@node["source"] && @kind not in ["command", "event"]} class="ehg-source">
        Source: {@node["source"]}
      </p>
      <.log :if={@log} entry={@log} ctx={@ctx} />
    </aside>
    """
  end

  # --- a node, by its kind ------------------------------------------------------------------

  attr :kind, :string, required: true
  attr :node, :map, required: true
  attr :ctx, :map, required: true

  defp body(%{kind: "command"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        people: Lookup.into(l, id, "may_issue"),
        reactions: Lookup.into(l, id, "issues"),
        timers: Lookup.into(l, id, "fires"),
        allowed: Lookup.out(l, id, "allowed_in"),
        refused: Lookup.out(l, id, "refused_on")
      )

    ~H"""
    <.part title="Fields"><.fields fields={@node["fields"] || []} ctx={@ctx} /></.part>
    <.part title="Who may issue it">
      <ul class="ehg-list">
        <li :for={r <- @people}>
          <.ref id={r["from"]} ctx={@ctx} />
        </li>
        <li :for={r <- @reactions}>
          <.ref id={r["from"]} ctx={@ctx} />{on_phase(r, @ctx.lookup)}
        </li>
        <li :for={r <- @timers}>
          <.ref id={r["from"]} ctx={@ctx} />, when it fires
        </li>
      </ul>
      <p :if={@node["capability"]}>EHOS grants it as <code>{@node["capability"]}</code>.</p>
      <p :if={@people == [] and @reactions == [] and @timers == []} class="ehg-empty">
        Nothing in the contract issues it.
      </p>
    </.part>
    <.part :if={@node["scope"]} title="Scope">
      <p>
        A grant narrows it to one <code>{@node["scope"]}</code>: a person may issue it only for
        the one their grant names.
      </p>
    </.part>
    <.part title="Decided by">
      <p>
        <.ref id={@node["unit"]} ctx={@ctx} />{if @node["creates"],
          do: ", which it creates"}
      </p>
    </.part>
    <.part :if={@allowed != []} title="Allowed in">
      <.refs relations={@allowed} side="to" ctx={@ctx} />
    </.part>
    <.part :if={@refused != []} title="May be refused on">
      <ul class="ehg-list">
        <li :for={r <- @refused}>
          <.ref id={r["to"]} ctx={@ctx} />{if r["outside_from"],
            do: " — outside the statuses it is allowed in"}
        </li>
      </ul>
    </.part>
    """
  end

  defp body(%{kind: "event"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup
    received = Lookup.into(l, id, "received_as")

    depends =
      Lookup.out(l, id, ~w(handled_by starts ends projected_into builds consulted_by
                           opens fulfils or_else enters published_as)) ++
        Enum.filter(Lookup.relations(l, "transition"), &(&1["event"] == id))

    assigns =
      assign(assigns,
        people: Lookup.into(l, id, "may_record"),
        received: received,
        rests: Lookup.out(l, id, "depends_on"),
        depends: depends
      )

    ~H"""
    <.part title="Fields"><.fields fields={@node["fields"] || []} ctx={@ctx} /></.part>
    <.part title="Where it comes from">
      <p :if={@node["unit"]}>
        Recorded in <.ref id={@node["unit"]} ctx={@ctx} />.
      </p>
      <p :if={@node["declared_as"]}>Declared in another contract and consumed here.</p>
      <p :for={r <- @received}>
        Received from another application as <.ref id={r["from"]} ctx={@ctx} />.
      </p>
      <p :if={@node["contract"]}>
        Declared in <.ref id={@node["contract"]} ctx={@ctx} />.
      </p>
      <p :if={@node["type"]}>
        In the log as <code>{@node["type"]}</code>{if @node["schema_version"],
          do: ", schema version #{@node["schema_version"]}"}.
      </p>
      <p :if={@node["stage"]}>
        In the stage <.ref id={@node["stage"]} ctx={@ctx} />.
      </p>
    </.part>
    <.part :if={@people != [] or (@node["capability"] && @received == [])} title="Recorded by">
      <.refs relations={@people} side="from" ctx={@ctx} />
      <p :if={@node["capability"] && @received == []}>
        EHOS grants it as <code>{@node["capability"]}</code>.
      </p>
    </.part>
    <p :if={@node["capability"] && @received != []}>
      The application takes it with <code>{@node["capability"]}</code>.
    </p>
    <p :if={@node["terminal"]} class="ehg-strong">It ends the run.</p>
    <.part :if={@rests != []} title="Rests on">
      <.refs relations={@rests} side="to" ctx={@ctx} />
    </.part>
    <.part :if={!@node["contract"]} title="What depends on it">
      <ul :if={@depends != []} class="ehg-list">
        <li :for={r <- @depends}><.depends relation={r} ctx={@ctx} /></li>
      </ul>
      <p :if={@depends == [] and !@node["terminal"]} class="ehg-empty">Nothing depends on it.</p>
    </.part>
    """
  end

  defp body(%{kind: "policy"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        handles: Lookup.into(l, id, "handled_by"),
        issues: Lookup.out(l, id, "issues"),
        scenarios: Lookup.about(l, id)
      )

    ~H"""
    <.part title="Takes">
      <ul class="ehg-list">
        <li :for={r <- @handles}>
          <.ref id={r["from"]} ctx={@ctx} />{if r["via_inbox"],
            do: ", through the inbox"}
        </li>
      </ul>
    </.part>
    <.part title="Issues">
      <.refs relations={@issues} side="to" ctx={@ctx} />
      <p :if={@issues == []}>Nothing.</p>
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} />
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "process_manager"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        starts: Lookup.into(l, id, "starts"),
        during: Lookup.into(l, id, "handled_by"),
        ends: Lookup.into(l, id, "ends"),
        timers: Lookup.owned(l, "timer", "process_manager", id),
        issues: Lookup.out(l, id, "issues"),
        scenarios: Lookup.about(l, id)
      )

    ~H"""
    <p :if={@node["correlate"] not in [nil, []]}>
      One run per <code>{Enum.join(@node["correlate"], ", ")}</code>.
    </p>
    <.part title="Starts on"><.refs relations={@starts} side="from" ctx={@ctx} /></.part>
    <.part :if={@during != []} title="During the run, takes">
      <.refs relations={@during} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@ends != []} title="Ends on">
      <.refs relations={@ends} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@timers != []} title="Timers">
      <ul class="ehg-list">
        <li :for={t <- @timers}>
          <.ref id={t["id"]} ctx={@ctx} /> — {timer_when(t)}<span :for={
            r <- Lookup.out(@ctx.lookup, t["id"], "fires")
          }>, issuing <.ref id={r["to"]} ctx={@ctx} /></span>
        </li>
      </ul>
    </.part>
    <.part :if={@issues != []} title="Issues">
      <ul class="ehg-list">
        <li :for={r <- @issues}>
          <.ref id={r["to"]} ctx={@ctx} />{on_phase(r, @ctx.lookup)}
        </li>
      </ul>
    </.part>
    <.part :if={@node["state"] not in [nil, []]} title="What it remembers">
      <.fields fields={@node["state"]} ctx={@ctx} />
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} />
    <.part title={count(@scenarios, "scenario")}>
      <div :for={{title, group} <- by_trigger(@scenarios, @ctx.lookup)} class="ehg-trigger">
        <p class="ehg-trigger-title">{title}</p>
        <.scenario :for={s <- group} scenario={s} ctx={@ctx} />
      </div>
    </.part>
    """
  end

  defp body(%{kind: "timer"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup
    manager = assigns.node["process_manager"]

    assigns =
      assign(assigns,
        sets: Lookup.into(l, id, "sets"),
        cancels: Lookup.into(l, id, "cancels"),
        fires: Lookup.out(l, id, "fires"),
        scenarios:
          Enum.filter(Lookup.about(l, manager), &(get_in(&1, ["trigger", "timer"]) == id))
      )

    ~H"""
    <p>
      A timer of <.ref id={@node["process_manager"]} ctx={@ctx} />: {timer_when(@node)}.
    </p>
    <.part title="Set">
      <ul class="ehg-list">
        <li :for={r <- @sets}>{on_phase_words(r, @ctx.lookup)}</li>
      </ul>
    </.part>
    <.part :if={@cancels != []} title="Cancelled">
      <ul class="ehg-list">
        <li :for={r <- @cancels}>{on_phase_words(r, @ctx.lookup)}</li>
      </ul>
    </.part>
    <.part title="When it fires, issues">
      <.refs relations={@fires} side="to" ctx={@ctx} />
    </.part>
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "effect"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        handles: Lookup.into(l, id, "handled_by"),
        calls: Lookup.out(l, id, "calls")
      )

    ~H"""
    <.part title="Takes"><.refs relations={@handles} side="from" ctx={@ctx} /></.part>
    <.part title="Calls">
      <ul class="ehg-list">
        <li :for={r <- @calls}>
          <.ref id={r["to"]} ctx={@ctx} />{operation(r, @ctx.lookup)}
        </li>
      </ul>
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} />
    <p class="ehg-quiet">An effect has no scenarios: what it does is outside the contract.</p>
    """
  end

  defp body(%{kind: "read_model"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        built: Lookup.into(l, id, "projected_into"),
        read: Lookup.into(l, id, "reads")
      )

    ~H"""
    <.part title="Built from"><.refs relations={@built} side="from" ctx={@ctx} /></.part>
    <.part title="Fields"><.fields fields={@node["fields"] || []} ctx={@ctx} /></.part>
    <.part title="Read by">
      <.refs relations={@read} side="from" ctx={@ctx} />
      <p :if={@read == []}>No query.</p>
    </.part>
    <.delivery node={@node} />
    """
  end

  defp body(%{kind: "query"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup
    reads = Lookup.out(l, id, "reads")

    assigns =
      assign(assigns,
        people: Lookup.into(l, id, "may_ask"),
        reads: reads,
        answer: Enum.flat_map(reads, &((Lookup.node(l, &1["to"]) || %{})["fields"] || [])),
        scenarios: Lookup.about(l, id)
      )

    ~H"""
    <.part title="Parameters">
      <.fields fields={@node["params"] || []} ctx={@ctx} />
      <p :if={@node["params"] in [nil, []]}>None.</p>
    </.part>
    <.part title="Who may ask">
      <.refs relations={@people} side="from" ctx={@ctx} />
      <p :if={@node["capability"]}>EHOS grants it as <code>{@node["capability"]}</code>.</p>
    </.part>
    <.part title="Reads">
      <.refs relations={@reads} side="to" ctx={@ctx} />
      <p>{if @node["returns"] == "one", do: "Returns one row.", else: "Returns a list of rows."}</p>
      <p :if={@node["scope"]}>
        A grant narrows the answer to the rows of one <code>{@node["scope"]}</code>.
      </p>
    </.part>
    <.part :if={@answer != []} title="What a row holds"><.fields fields={@answer} ctx={@ctx} /></.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "unit"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        commands: Lookup.owned(l, "command", "unit", id),
        events: Lookup.owned(l, "event", "unit", id),
        rules: Lookup.owned(l, "invariant", "of", id),
        statuses: Lookup.owned(l, "status", "unit", id),
        consulted: Lookup.into(l, id, "consulted_by")
      )

    ~H"""
    <p>
      {if @node["unit_kind"] == "dcb", do: "A dynamic consistency boundary", else: "An aggregate"}, identified by
      <code>{Enum.join(List.wrap(@node["identity"]), ", ")}</code>{if @node["generated"],
        do: ", which the library generates (#{@node["generated"]}) when a command creates one"}.
    </p>
    <.part :if={@node["state"] not in [nil, []]} title="State">
      <.fields fields={@node["state"]} ctx={@ctx} />
    </.part>
    <.part :if={@commands != []} title="Commands">
      <.nodes list={@commands} ctx={@ctx} />
    </.part>
    <.part :if={@events != []} title="Events">
      <.nodes list={@events} ctx={@ctx} />
    </.part>
    <.part :if={@consulted != []} title="Consults">
      <ul class="ehg-list">
        <li :for={r <- @consulted}>
          <.ref id={r["from"]} ctx={@ctx} />{consulted(r)}
        </li>
      </ul>
    </.part>
    <.part :if={@rules != []} title="Rules">
      <.nodes list={@rules} ctx={@ctx} />
    </.part>
    <.part :if={@statuses != []} title="Statuses">
      <ul class="ehg-list">
        <li :for={s <- @statuses}>
          <.ref id={s["id"]} ctx={@ctx} />{if s["final"], do: " — an end"}
        </li>
      </ul>
    </.part>
    """
  end

  defp body(%{kind: kind} = assigns) when kind in ["invariant", "constraint"] do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    illustrating =
      for s <- Lookup.about(l, assigns.node["of"]) ++ owners_scenarios(l, assigns.node["of"]),
          s["rejected"] == id or id in (s["illustrates"] || []),
          uniq: true,
          do: s

    assigns =
      assign(assigns, refusing: Lookup.into(l, id, "refused_on"), illustrating: illustrating)

    ~H"""
    <p>A rule of <.ref id={@node["of"]} ctx={@ctx} />.</p>
    <.part :if={@refusing != []} title="Refuses">
      <ul class="ehg-list">
        <li :for={r <- @refusing}>
          <.ref id={r["from"]} ctx={@ctx} />{if r["outside_from"],
            do: " — outside the statuses it is allowed in"}
        </li>
      </ul>
    </.part>
    <.scenarios title="Scenarios it shows in" list={@illustrating} ctx={@ctx} />
    """
  end

  defp body(%{kind: "status"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        enters: Lookup.into(l, id, "enters"),
        moves_in: Lookup.into(l, id, "transition"),
        moves_out: Lookup.out(l, id, "transition"),
        allowed: Lookup.into(l, id, "allowed_in")
      )

    ~H"""
    <p>
      A status of <.ref id={@node["unit"]} ctx={@ctx} />{if @node["final"],
        do: ", and an end: nothing moves it on"}.
    </p>
    <.part :if={@enters != []} title="A new one starts in it on">
      <.refs relations={@enters} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@moves_in != []} title="Moves into it">
      <ul class="ehg-list">
        <li :for={r <- @moves_in}>
          from <.ref id={r["from"]} ctx={@ctx} /> on
          <.ref id={r["event"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@moves_out != []} title="Moves out of it">
      <ul class="ehg-list">
        <li :for={r <- @moves_out}>
          to <.ref id={r["to"]} ctx={@ctx} /> on
          <.ref id={r["event"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@allowed != []} title="Commands allowed in it">
      <.refs relations={@allowed} side="from" ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "actor"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        issue: Lookup.out(l, id, "may_issue"),
        record: Lookup.out(l, id, "may_record"),
        ask: Lookup.out(l, id, "may_ask"),
        accountable: Lookup.out(l, id, "accountable_for"),
        backed: Lookup.out(l, id, "backed_by"),
        capabilities: Enum.group_by(assigns.node["capabilities"] || [], & &1["contract"])
      )

    ~H"""
    <p :if={!@node["context"]}>{actor_kind(@node)}.</p>
    <p :if={@node["context"]}>
      {actor_kind(@node)}, of <.ref id={@node["context"]} ctx={@ctx} />.
    </p>
    <p :if={@node["role"]}>Their role in EHOS is <code>{@node["role"]}</code>.</p>
    <p :if={@node["scope"] not in [nil, []]}>
      A grant to this role narrows answers by <code>{Enum.join(@node["scope"], ", ")}</code>.
    </p>
    <.part :if={@backed != []} title="Stands for">
      <.refs relations={@backed} side="to" ctx={@ctx} />
    </.part>
    <.part :if={@node["responsibilities"] not in [nil, []]} title="Responsible for">
      <ul class="ehg-list">
        <li :for={r <- @node["responsibilities"]}>
          {r["label"] || r["name"]}<span :if={r["source"]} class="ehg-quiet"> · {r["source"]}</span>
        </li>
      </ul>
    </.part>
    <.part :if={@issue != []} title="May issue">
      <.granted relations={@issue} ctx={@ctx} />
    </.part>
    <.part :if={@record != []} title="May record">
      <.granted relations={@record} ctx={@ctx} />
    </.part>
    <.part :if={@ask != []} title="May ask">
      <.granted relations={@ask} ctx={@ctx} />
    </.part>
    <.part :if={@capabilities != %{}} title="What the role may do">
      <div :for={{contract, granted} <- @capabilities} class="ehg-trigger">
        <p class="ehg-trigger-title"><.ref id={contract} ctx={@ctx} /></p>
        <ul class="ehg-list">
          <li :for={c <- granted}>{grant_kind(c["kind"])} <code>{c["capability"]}</code></li>
        </ul>
      </div>
    </.part>
    <.part :if={@accountable != []} title="Accountable for">
      <.refs relations={@accountable} side="to" ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "external"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    gives =
      for kind <- ~w(command event read_model unit),
          node <- Lookup.nodes(l, kind),
          field <- (node["fields"] || []) ++ (node["state"] || []),
          field["issued_by"] == id,
          do: {node["id"], field["name"]}

    assigns =
      assign(assigns,
        calls: Lookup.into(l, id, "calls"),
        rests: Lookup.into(l, id, "depends_on"),
        backed: Lookup.into(l, id, "backed_by"),
        gives: gives,
        patterns: patterns(l, id)
      )

    ~H"""
    <p :if={@node["direction"]}>{direction(@node["direction"])}</p>
    <.part :if={@node["unavailable_looks_like"]} title="When it is unavailable">
      <p>{@node["unavailable_looks_like"]}</p>
    </.part>
    <p :if={@node["expected_latency"]}>
      It usually answers within {duration(@node["expected_latency"])}.
    </p>
    <.part :if={@node["operations"] not in [nil, []]} title="Operations">
      <ul class="ehg-list">
        <li :for={o <- @node["operations"]}>
          {o["label"] || o["name"]} <code>{o["name"]}</code>
        </li>
      </ul>
    </.part>
    <.part :if={@calls != []} title="Called by">
      <ul class="ehg-list">
        <li :for={r <- @calls}>
          <.ref id={r["from"]} ctx={@ctx} />{operation(r, @ctx.lookup)}
        </li>
      </ul>
    </.part>
    <.part :if={@rests != []} title="Events resting on it">
      <.refs relations={@rests} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@gives != []} title="Gives the value of">
      <ul class="ehg-list">
        <li :for={{node, field} <- @gives}>
          <code>{field}</code> of <.ref id={node} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@backed != []} title="Stands behind">
      <.refs relations={@backed} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@patterns != []} title="Relations">
      <ul class="ehg-list">
        <li :for={{relation, other, words} <- @patterns}>
          {words} <.ref id={other} ctx={@ctx} /><.pairs relation={relation} />
        </li>
      </ul>
    </.part>
    """
  end

  defp body(%{kind: "context"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        patterns: patterns(l, id),
        contracts: Lookup.owned(l, "contract", "context", id),
        entities: Lookup.owned(l, "entity", "context", id),
        values: Lookup.owned(l, "value", "context", id)
      )

    ~H"""
    <p :if={@node["subdomain"]}>
      In the subdomain <.ref id={@node["subdomain"]} ctx={@ctx} />{subdomain_type(
        @node["subdomain"],
        @ctx.lookup
      )}.
    </p>
    <p :if={@node["language"]}>Its own language: {@node["language"]}.</p>
    <.part :if={@node["terms"] not in [nil, []]} title="Terms">
      <dl class="ehg-terms">
        <%= for term <- @node["terms"] do %>
          <dt>{term["text"]}</dt>
          <dd>
            <span :if={term["definition"] || term["source"]}>
              {term["definition"]}<span :if={term["source"]} class="ehg-quiet"> · {term["source"]}</span>
            </span>
            <span :for={a <- term["avoid"] || []} class="ehg-avoid">
              Not “{a["text"]}”{if a["reason"], do: ": #{a["reason"]}"}
            </span>
            <span :for={t <- term["translations"] || []} class="ehg-translation">
              {t["language"]}: {t["text"]}{if t["definition"], do: " — #{t["definition"]}"}
            </span>
          </dd>
        <% end %>
      </dl>
    </.part>
    <.part :if={@patterns != []} title="Relations">
      <ul class="ehg-list">
        <li :for={{relation, other, words} <- @patterns}>
          {words} <.ref id={other} ctx={@ctx} /><.pairs relation={relation} />
        </li>
      </ul>
    </.part>
    <.part :if={@contracts != []} title="Contracts">
      <.nodes list={@contracts} ctx={@ctx} />
    </.part>
    <.part :if={@entities != []} title="Entities">
      <div :for={e <- @entities} class="ehg-trigger">
        <p class="ehg-trigger-title">
          <.ref id={e["id"]} ctx={@ctx} />, identified by <code>{e["identity"]}</code>
        </p>
        <.fields fields={e["fields"] || []} ctx={@ctx} />
      </div>
    </.part>
    <.part :if={@values != []} title="Values">
      <.nodes list={@values} ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "subdomain"} = assigns) do
    assigns =
      assign(assigns,
        contexts: Lookup.owned(assigns.ctx.lookup, "context", "subdomain", assigns.node["id"])
      )

    ~H"""
    <p :if={@node["type"]}>A {@node["type"]} subdomain.</p>
    <.part title="Contexts"><.nodes list={@contexts} ctx={@ctx} /></.part>
    """
  end

  defp body(%{kind: "process"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        stages: Lookup.owned(l, "stage", "process", id),
        promises: Lookup.owned(l, "promise", "process", id),
        accountable: Lookup.into(l, id, "accountable_for")
      )

    ~H"""
    <p :if={@node["correlate"] not in [nil, []]}>
      One run per <code>{Enum.join(@node["correlate"], ", ")}</code>.
    </p>
    <p :if={@node["deadline"]}>
      A run ends within {duration(@node["deadline"])}{if @node["deadline"]["unverified"],
        do: " (not confirmed by the process owner)"}.
    </p>
    <.part :if={@accountable != []} title="Accountable">
      <.refs relations={@accountable} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@stages != []} title="Stages, in order">
      <.nodes list={@stages} ctx={@ctx} />
    </.part>
    <.part :if={@promises != []} title="Promises">
      <.nodes list={@promises} ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "stage"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup
    stages = Lookup.owned(l, "stage", "process", assigns.node["process"])

    assigns =
      assign(assigns,
        events: Lookup.owned(l, "event", "stage", id),
        position: Enum.find_index(stages, &(&1["id"] == id)),
        of: length(stages)
      )

    ~H"""
    <p>
      Stage {(@position || 0) + 1} of {@of} of
      <.ref id={@node["process"]} ctx={@ctx} />.
    </p>
    <.part title="Events">
      <.nodes list={@events} ctx={@ctx} />
      <p :if={length(@events) > 1} class="ehg-quiet">No order is claimed among them.</p>
      <p :if={@events == []} class="ehg-empty">No event sits in it.</p>
    </.part>
    """
  end

  defp body(%{kind: "promise"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        opens: Lookup.into(l, id, "opens"),
        fulfils: Lookup.into(l, id, "fulfils"),
        or_else: Lookup.into(l, id, "or_else")
      )

    ~H"""
    <p>
      A promise of <.ref id={@node["process"]} ctx={@ctx} />{promise_window(@node)}.
    </p>
    <.part title="Opened by"><.refs relations={@opens} side="from" ctx={@ctx} /></.part>
    <.part title="Kept by"><.refs relations={@fulfils} side="from" ctx={@ctx} /></.part>
    <.part :if={@or_else != []} title="Kept the other way by">
      <.refs relations={@or_else} side="from" ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "publication"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        published: Lookup.into(l, id, "published_as"),
        received: Lookup.out(l, id, "received_as"),
        publishers: Lookup.into(l, id, "publishes"),
        subscribers: Lookup.out(l, id, "subscribed_by")
      )

    ~H"""
    <p>On the wire as <code>{@node["name"]}</code>.</p>
    <.part :if={@published != []} title="Published from">
      <ul class="ehg-list">
        <li :for={r <- @published}>
          <.ref id={r["from"]} ctx={@ctx} />, with
          <code>{Enum.join(r["fields"] || [], ", ")}</code>{if r["idempotent_on"] not in [nil, []],
            do: ", a repeat recognised by #{Enum.join(r["idempotent_on"], ", ")}"}
        </li>
      </ul>
    </.part>
    <.part :if={@publishers != []} title="Published by">
      <ul class="ehg-list">
        <li :for={r <- @publishers}>
          <.ref id={r["from"]} ctx={@ctx} /> from
          <.ref id={r["event"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@received != []} title="Received as">
      <.refs relations={@received} side="to" ctx={@ctx} />
    </.part>
    <.part :if={@subscribers != []} title="Subscribed by">
      <ul class="ehg-list">
        <li :for={r <- @subscribers}>
          <.ref id={r["to"]} ctx={@ctx} />, as <code>{r["as"]}</code>{with_grant(r)}
        </li>
      </ul>
    </.part>
    """
  end

  defp body(%{kind: "contract"} = assigns) do
    id = assigns.node["id"]
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        from: Lookup.into(l, id, "consumed_by"),
        to: Lookup.out(l, id, "consumed_by"),
        publishes: Lookup.out(l, id, "publishes"),
        subscribes: Lookup.into(l, id, "subscribed_by"),
        accountable: Lookup.into(l, id, "accountable_for")
      )

    ~H"""
    <p>The contract <code>{@node["name"]}</code>, in the code <code>{@node["module"]}</code>.</p>
    <p :if={@node["process"]}>
      Its process: {@node["process"]["label"] || @node["process"]["name"]}.
    </p>
    <p :if={@node["correlate"] not in [nil, []]}>
      One run per <code>{Enum.join(@node["correlate"], ", ")}</code>.
    </p>
    <p :if={@node["context"]}>
      In the context <.ref id={@node["context"]} ctx={@ctx} />.
    </p>
    <.part :if={@accountable != []} title="Accountable">
      <.refs relations={@accountable} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@from != []} title="Takes events from">
      <div :for={r <- @from} class="ehg-trigger">
        <p class="ehg-trigger-title"><.ref id={r["from"]} ctx={@ctx} /></p>
        <.consumed relation={r} ctx={@ctx} />
      </div>
    </.part>
    <.part :if={@to != []} title="Its events go to">
      <div :for={r <- @to} class="ehg-trigger">
        <p class="ehg-trigger-title"><.ref id={r["to"]} ctx={@ctx} /></p>
        <.consumed relation={r} ctx={@ctx} />
      </div>
    </.part>
    <.part :if={@publishes != []} title="Publishes">
      <.refs relations={@publishes} side="to" ctx={@ctx} />
    </.part>
    <.part :if={@subscribes != []} title="Subscribes to">
      <.refs relations={@subscribes} side="from" ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "value"} = assigns) do
    ~H"""
    <p :if={@node["context"]}>
      Of the context <.ref id={@node["context"]} ctx={@ctx} />.
    </p>
    <p :if={@node["type"]}>{value_words(@node)}</p>
    <.part :if={@node["fields"] not in [nil, []]} title="Fields">
      <.fields fields={@node["fields"]} ctx={@ctx} />
    </.part>
    <.part :if={@node["invariants"] not in [nil, []]} title="Rules">
      <div :for={i <- @node["invariants"]} class="ehg-trigger">
        <p class="ehg-trigger-title">{i["label"] || i["name"]}</p>
        <p :if={i["satisfied_by"] not in [nil, []]} class="ehg-quiet">
          For example: {Enum.map_join(i["satisfied_by"], ", ", &shown/1)}
        </p>
        <p :if={i["violated_by"] not in [nil, []]} class="ehg-quiet">
          Not: {Enum.map_join(i["violated_by"], ", ", &shown/1)}
        </p>
      </div>
    </.part>
    """
  end

  defp body(%{kind: "entity"} = assigns) do
    ~H"""
    <p>
      Identified by <code>{@node["identity"]}</code>{if @node["context"], do: ", in the context"}
      <.ref :if={@node["context"]} id={@node["context"]} ctx={@ctx} />.
    </p>
    <.part :if={@node["fields"] not in [nil, []]} title="Fields">
      <.fields fields={@node["fields"]} ctx={@ctx} />
    </.part>
    """
  end

  # Anything else — a subject, a domain service — as the document has it.
  defp body(assigns) do
    ~H"""
    <.facts facts={Map.drop(@node, ["id", "label", "name", "source"])} />
    """
  end

  # --- a relation, by its type --------------------------------------------------------------

  attr :type, :string, required: true
  attr :relation, :map, required: true
  attr :facts, :map, required: true
  attr :ctx, :map, required: true

  defp relation_body(%{type: "gives"} = assigns) do
    ~H"""
    <p>The system gives the value of this field.</p>
    <.fields fields={[@facts]} ctx={@ctx} />
    """
  end

  defp relation_body(%{type: "undeclared"} = assigns) do
    ~H"""
    <p class="ehg-empty">
      Seen in the log on <.ref id={@facts["event"]} ctx={@ctx} />, though the
      lifecycle does not allow this move.
    </p>
    """
  end

  defp relation_body(%{type: "consumed_by"} = assigns) do
    ~H"""
    <.consumed relation={@facts} ctx={@ctx} />
    """
  end

  defp relation_body(assigns) do
    assigns =
      assign(assigns,
        sentences: relation_sentences(assigns.type, assigns.facts, assigns.ctx.lookup)
      )

    ~H"""
    <p :for={sentence <- @sentences}>{sentence}</p>
    <.pairs relation={@facts} />
    """
  end

  defp relation_sentences(type, facts, lookup) do
    reaction = Lookup.node(lookup, facts["to"]) || %{}
    issuer = Lookup.node(lookup, facts["from"]) || %{}

    Enum.reject(
      [
        type == "handled_by" && facts["via_inbox"] &&
          "Through the inbox, after the transaction: it was received from another application.",
        type == "handled_by" && !facts["via_inbox"] && delivery_sentence(reaction["delivery"]),
        type == "issues" && on_phase_sentence(facts, lookup),
        type == "issues" && delivery_sentence(issuer["delivery"]),
        type in ["sets", "cancels"] && on_phase_sentence(facts, lookup),
        type == "calls" && facts["operation"] &&
          "The operation #{operation_title(facts, lookup)}.",
        type == "consulted_by" && consulted_sentence(facts),
        type == "refused_on" && facts["outside_from"] &&
          "Refused on it outside the statuses the command is allowed in.",
        type in ["transition", "enters"] && facts["event"] &&
          "On #{Lookup.title(lookup, facts["event"])}.",
        type == "published_as" &&
          "Published as #{facts["name"]}, with #{Enum.join(facts["fields"] || [], ", ")}.",
        type == "publishes" && facts["event"] &&
          "From #{Lookup.title(lookup, facts["event"])}.",
        type == "subscribed_by" &&
          "As #{facts["as"]}#{if facts["capability"], do: ", with #{facts["capability"]}"}.",
        facts["source"] && "Source: #{facts["source"]}"
      ],
      &(&1 in [nil, false])
    )
  end

  # --- parts --------------------------------------------------------------------------------

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp part(assigns) do
    ~H"""
    <div class="ehg-part">
      <p class="ehg-part-title">{@title}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :ctx, :map, required: true

  # A node named in a panel: a button that selects it, with its kind. An id the document
  # does not hold is shown as it is.
  defp ref(assigns) do
    assigns =
      assign(assigns,
        kind: Lookup.kind(assigns.ctx.lookup, assigns.id),
        title: Lookup.title(assigns.ctx.lookup, assigns.id)
      )

    ~H"""
    <button
      :if={@kind}
      type="button"
      class="ehg-ref"
      phx-click="select"
      phx-value-id={@id}
      phx-target={@ctx.target}
    >{@title}<span class="ehg-ref-kind">{words(@kind)}</span></button><span :if={!@kind} class="ehg-ref">{@title}</span>
    """
  end

  attr :relations, :list, required: true
  attr :side, :string, required: true, doc: "which end of each relation to name"
  attr :ctx, :map, required: true

  defp refs(assigns) do
    ~H"""
    <ul :if={@relations != []} class="ehg-list">
      <li :for={r <- @relations}><.ref id={r[@side]} ctx={@ctx} /></li>
    </ul>
    """
  end

  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp nodes(assigns) do
    ~H"""
    <ul :if={@list != []} class="ehg-list">
      <li :for={n <- @list}><.ref id={n["id"]} ctx={@ctx} /></li>
    </ul>
    """
  end

  attr :relations, :list, required: true
  attr :ctx, :map, required: true

  # What a role may do here: each declaration, and the grant EHOS gives for it.
  defp granted(assigns) do
    ~H"""
    <ul class="ehg-list">
      <li :for={r <- @relations}>
        <.ref id={r["to"]} ctx={@ctx} /><code
          :if={capability(@ctx.lookup, r["to"])}
          class="ehg-grant"
        >{capability(@ctx.lookup, r["to"])}</code>
      </li>
    </ul>
    """
  end

  attr :relation, :map, required: true
  attr :ctx, :map, required: true

  # The events one contract takes from another: each by its label, and the name it has in
  # the consumer where that is another.
  defp consumed(assigns) do
    ~H"""
    <ul class="ehg-list">
      <li :for={e <- @relation["events"] || []}>
        <.ref id={e["event"]} ctx={@ctx} /><span
          :if={e["as"] != (Lookup.node(@ctx.lookup, e["event"]) || %{})["name"]}
          class="ehg-quiet"
        > · as {e["as"]}</span>
      </li>
    </ul>
    """
  end

  attr :relation, :map, required: true

  # The pairs of words a context-mapping relation translates between.
  defp pairs(assigns) do
    ~H"""
    <ul :if={@relation["terms"] not in [nil, []]} class="ehg-list ehg-pairs">
      <li :for={[here, there] <- @relation["terms"]}>{here} ↔ {there}</li>
    </ul>
    """
  end

  attr :relation, :map, required: true
  attr :ctx, :map, required: true

  # One thing that depends on an event, in a sentence.
  defp depends(%{relation: %{"type" => "transition"}} = assigns) do
    ~H"""
    moves <.ref id={unit_of(@ctx.lookup, @relation["from"])} ctx={@ctx} /> from
    <.ref id={@relation["from"]} ctx={@ctx} /> to
    <.ref id={@relation["to"]} ctx={@ctx} />
    """
  end

  defp depends(%{relation: %{"type" => "published_as"}} = assigns) do
    ~H"""
    leaves for other applications as <.ref id={@relation["to"]} ctx={@ctx} />
    """
  end

  defp depends(assigns) do
    assigns = assign(assigns, words: depends_words(assigns.relation, assigns.ctx.lookup))

    ~H"""
    {@words} <.ref id={@relation["to"]} ctx={@ctx} />{depends_after(
      @relation,
      @ctx.lookup
    )}
    """
  end

  defp depends_words(%{"type" => type}, _lookup) do
    case type do
      "handled_by" -> "handled by"
      "starts" -> "starts a run of"
      "ends" -> "ends the run of"
      "projected_into" -> "projected into"
      "builds" -> "builds the state of"
      "consulted_by" -> "consulted by"
      "opens" -> "opens the promise"
      "fulfils" -> "keeps the promise"
      "or_else" -> "keeps the other way the promise"
      "enters" -> "a new one starts in"
      other -> words(other)
    end
  end

  defp depends_after(%{"type" => "handled_by", "via_inbox" => true}, _lookup),
    do: ", through the inbox"

  defp depends_after(%{"type" => type} = r, lookup) when type in ~w(handled_by starts ends) do
    case (Lookup.node(lookup, r["to"]) || %{})["delivery"] do
      "at_least_once" -> ", after the transaction"
      "in_transaction" -> ", in the transaction"
      _ -> nil
    end
  end

  defp depends_after(%{"type" => "consulted_by"} = r, _lookup), do: consulted(r)
  defp depends_after(_relation, _lookup), do: nil

  attr :of, :string, required: true
  attr :ctx, :map, required: true

  # The rules declared on a reaction or a query: its constraints, and a manager's invariants.
  defp rules(assigns) do
    assigns =
      assign(assigns,
        rules:
          Lookup.owned(assigns.ctx.lookup, "constraint", "of", assigns.of) ++
            Lookup.owned(assigns.ctx.lookup, "invariant", "of", assigns.of)
      )

    ~H"""
    <.part :if={@rules != []} title="Rules">
      <.nodes list={@rules} ctx={@ctx} />
    </.part>
    """
  end

  attr :node, :map, required: true

  # When a reaction or a read model runs, and what makes a second delivery harmless.
  defp delivery(assigns) do
    ~H"""
    <.part title="Delivery">
      <p>{delivery_sentence(@node["delivery"])}</p>
      <p :if={@node["idempotency"]}>{idempotency(@node["idempotency"])}</p>
    </.part>
    """
  end

  # --- fields -------------------------------------------------------------------------------

  attr :fields, :list, required: true
  attr :ctx, :map, required: true

  # Each field the same way, wherever it is: a command's, an event's, a state's, a read
  # model's, a query's parameters.
  defp fields(assigns) do
    ~H"""
    <ul :if={@fields != []} class="ehg-fields">
      <li :for={field <- @fields}>
        <span class="ehg-field-name">{field["name"]}</span>
        <span :if={field["label"]} class="ehg-field-label">{field["label"]}</span>
        <span class="ehg-field-type">{field_type(field)}</span>
        <span :for={note <- field_notes(field, @fields, @ctx.lookup)} class={note_class(note)}>
          {elem(note, 1)}
        </span>
      </li>
    </ul>
    """
  end

  defp field_type(field) do
    [
      type(field["type"]),
      if(field["required"] == false, do: "optional", else: "required"),
      Map.has_key?(field, "default") && "default #{shown(field["default"])}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  # What a field says beyond its type, each as `{kind, sentence}`.
  defp field_notes(field, siblings, lookup) do
    [
      field["personal_of"] && {:personal, personal(field, siblings, lookup)},
      field["subject"] &&
        {:subject,
         "Points at #{Lookup.title(lookup, field["subject"])} — in the log in the clear."},
      field["value"] && {:plain, value_words(Lookup.node(lookup, field["value"]))},
      match?(%{"enum" => _}, field["type"]) && {:plain, "One of: #{members(field["type"])}."},
      field["refers_to"] && {:plain, "Identifies #{Lookup.title(lookup, field["refers_to"])}."},
      field["issued_by"] &&
        {:plain, "Its value comes from #{Lookup.title(lookup, field["issued_by"])}."},
      field["supplied_by"] == "host" && {:plain, "Supplied by the host, not the caller."}
    ]
    |> Enum.reject(&(&1 in [nil, false]))
  end

  defp personal(field, siblings, lookup) do
    holder = Enum.find(siblings, &(&1["name"] == field["personal_of"])) || %{}

    whose =
      case holder["subject"] do
        nil -> "the person in #{field["personal_of"]}"
        subject -> Lookup.title(lookup, subject)
      end

    "Personal data of #{whose} — encrypted in the log, gone once they are erased."
  end

  defp note_class({:personal, _}), do: "ehg-field-note ehg-personal"
  defp note_class({:subject, _}), do: "ehg-field-note ehg-personal"
  defp note_class(_note), do: "ehg-field-note"

  # A domain value in words: its label, and its members, its type or its fields, and its unit.
  defp value_words(nil), do: nil

  defp value_words(value) do
    what =
      case value["type"] do
        %{"enum" => _} = enum -> members(enum)
        nil -> "fields #{Enum.map_join(value["fields"] || [], ", ", & &1["name"])}"
        type -> type(type)
      end

    "#{value["label"] || value["name"]}: #{what}#{if value["unit"], do: ", in #{value["unit"]}"}."
  end

  defp members(%{"enum" => members}),
    do: Enum.map_join(members, " / ", &(&1["label"] || &1["value"]))

  defp type(%{"list" => inner}), do: "list of #{type(inner)}"
  defp type(%{"enum" => members}), do: "one of #{Enum.map_join(members, ", ", & &1["value"])}"
  defp type(type) when is_binary(type), do: type
  defp type(_unknown), do: "?"

  # --- scenarios ----------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp scenarios(assigns) do
    ~H"""
    <.part title={"#{@title} · #{length(@list)}"}>
      <.scenario :for={s <- @list} scenario={s} ctx={@ctx} />
      <p :if={@list == []} class="ehg-quiet">None.</p>
    </.part>
    """
  end

  attr :scenario, :map, required: true
  attr :ctx, :map, required: true

  defp scenario(%{scenario: %{"type" => "unit"}} = assigns) do
    ~H"""
    <article class="ehg-scenario">
      <p class="ehg-scenario-title">{@scenario["description"]}</p>
      <.happened title="Given" list={@scenario["given"] || []} ctx={@ctx} />
      <p class="ehg-step">When</p>
      <p :if={@scenario["actor"]}><.ref id={@scenario["actor"]} ctx={@ctx} /> issues</p>
      <.with_data
        id={@scenario["command"]["command"]}
        data={@scenario["command"]["data"]}
        ctx={@ctx}
      />
      <p class="ehg-step">Then</p>
      <p :if={@scenario["rejected"]} class="ehg-refused">
        refused on <.ref id={@scenario["rejected"]} ctx={@ctx} />
      </p>
      <.with_data
        :for={e <- @scenario["expect"] || []}
        id={e["event"]}
        data={e["data"]}
        ctx={@ctx}
      />
      <p :if={!@scenario["rejected"] and @scenario["expect"] in [nil, []]}>nothing is recorded</p>
    </article>
    """
  end

  defp scenario(%{scenario: %{"type" => "policy"}} = assigns) do
    ~H"""
    <article class="ehg-scenario">
      <p class="ehg-scenario-title">{@scenario["description"]}</p>
      <p class="ehg-step">On</p>
      <.with_data
        id={@scenario["event"]["event"]}
        data={@scenario["event"]["data"]}
        ctx={@ctx}
      />
      <.issued list={@scenario["issues"] || []} ctx={@ctx} />
      <.illustrates list={@scenario["illustrates"] || []} ctx={@ctx} />
    </article>
    """
  end

  defp scenario(%{scenario: %{"type" => "process_manager"}} = assigns) do
    trigger = assigns.scenario["trigger"] || %{}

    assigns =
      assign(assigns, trigger: trigger["event"] || trigger["timer"], data: trigger["data"])

    ~H"""
    <article class="ehg-scenario">
      <p class="ehg-scenario-title">{@scenario["description"]}</p>
      <.happened title="Given" list={@scenario["given"] || []} ctx={@ctx} />
      <p class="ehg-step">{if @scenario["phase"] == "start", do: "As a run starts on", else: "On"}</p>
      <.with_data id={@trigger} data={@data || %{}} ctx={@ctx} />
      <.issued list={@scenario["issues"] || []} ctx={@ctx} />
      <p :for={t <- @scenario["sets"] || []}>
        sets <.ref id={t} ctx={@ctx} />
      </p>
      <p :for={t <- @scenario["cancels"] || []}>
        cancels <.ref id={t} ctx={@ctx} />
      </p>
      <p :if={@scenario["ended"]} class="ehg-strong">the run ends</p>
      <div :if={@scenario["state"] not in [nil, %{}]}>
        <p class="ehg-step">It then remembers</p>
        <.data data={@scenario["state"]} />
      </div>
      <.illustrates list={@scenario["illustrates"] || []} ctx={@ctx} />
    </article>
    """
  end

  defp scenario(%{scenario: %{"type" => "query"}} = assigns) do
    ~H"""
    <article class="ehg-scenario">
      <p class="ehg-scenario-title">{@scenario["description"]}</p>
      <.happened title="Given" list={@scenario["given"] || []} ctx={@ctx} />
      <p class="ehg-step">Asked with</p>
      <.data data={@scenario["params"] || %{}} />
      <p class="ehg-step">It answers</p>
      <div :for={row <- List.wrap(@scenario["answers"])} class="ehg-row"><.data data={row} /></div>
      <p :if={@scenario["answers"] in [nil, []]}>nothing</p>
      <.illustrates list={@scenario["illustrates"] || []} ctx={@ctx} />
    </article>
    """
  end

  attr :title, :string, required: true
  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp happened(assigns) do
    ~H"""
    <div :if={@list != []}>
      <p class="ehg-step">{@title}</p>
      <.with_data
        :for={e <- @list}
        id={e["event"]}
        data={e["data"]}
        ctx={@ctx}
      />
    </div>
    """
  end

  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp issued(assigns) do
    ~H"""
    <p class="ehg-step">{if @list == [], do: "it issues nothing", else: "it issues"}</p>
    <.with_data
      :for={c <- @list}
      id={c["command"]}
      data={c["data"]}
      ctx={@ctx}
    />
    """
  end

  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp illustrates(assigns) do
    ~H"""
    <p :if={@list != []} class="ehg-quiet">
      Shows <.ref :for={rule <- @list} id={rule} ctx={@ctx} />
    </p>
    """
  end

  attr :id, :string, required: true
  attr :data, :map, required: true
  attr :ctx, :map, required: true

  defp with_data(assigns) do
    ~H"""
    <div class="ehg-happened">
      <.ref id={@id} ctx={@ctx} />
      <.data data={@data || %{}} />
    </div>
    """
  end

  attr :data, :map, required: true

  # A scenario's data as the document has it, redacted: a personal value is null there.
  defp data(assigns) do
    ~H"""
    <dl :if={@data != %{}} class="ehg-data">
      <%= for {key, value} <- Enum.sort(@data) do %>
        <dt>{key}</dt>
        <dd>{shown(value)}</dd>
      <% end %>
    </dl>
    """
  end

  # A manager's scenarios by what triggers them, in the order they first appear: as a run
  # starts on an event, when a timer fires, on an event during the run.
  defp by_trigger(scenarios, lookup) do
    keyed =
      for s <- scenarios do
        trigger = s["trigger"] || %{}

        title =
          cond do
            trigger["timer"] ->
              "When #{Lookup.title(lookup, trigger["timer"])} fires"

            s["phase"] == "start" ->
              "As a run starts on #{Lookup.title(lookup, trigger["event"])}"

            true ->
              "On #{Lookup.title(lookup, trigger["event"])} during the run"
          end

        {title, s}
      end

    keyed
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.map(fn title -> {title, for({^title, s} <- keyed, do: s)} end)
  end

  # --- the log ------------------------------------------------------------------------------

  attr :entry, :map, required: true
  attr :ctx, :map, required: true

  # What the overlay says of the node or relation, in sentences, recounting nothing.
  defp log(assigns) do
    assigns = assign(assigns, sentences: log_sentences(assigns.entry, assigns.ctx.lookup))

    ~H"""
    <.part title="From the log">
      <p :for={sentence <- @sentences}>{sentence}</p>
    </.part>
    """
  end

  defp log_sentences(%{"by_trigger" => by_trigger}, lookup) do
    for {event, step} <- Enum.sort(by_trigger),
        sentence <- log_sentences(step, lookup),
        do: "On #{Lookup.title(lookup, event)}: #{sentence}"
  end

  defp log_sentences(entry, _lookup) do
    Enum.reject(
      [
        entry["occurrences"] && "Recorded #{times(entry["occurrences"])}.",
        entry["runs"] && "#{count(entry["runs"], "run")}.",
        entry["aggregates"] && "#{count(entry["aggregates"], "aggregate")}.",
        Map.has_key?(entry, "taken") && entry["taken"] && "Taken #{times(entry["taken"])}.",
        entry["count"] && "Made #{times(entry["count"])}.",
        entry["events"] && "#{count(entry["events"], "event")} crossed.",
        entry["untraversed"] == true && "Never taken: the report lists it as a path never taken.",
        entry["pending"] == true && "Not yet taken: work is still on its way to it.",
        waiting(entry["waiting"]),
        failing(entry["failing"])
      ],
      &(&1 in [nil, false])
    )
  end

  defp waiting(%{"lag" => lag, "timers" => timers, "effects" => effects})
       when lag + timers + effects > 0,
       do:
         "Waiting: #{lag} not reached yet, #{timers} timers not fired, #{effects} effect jobs not run."

  defp waiting(n) when is_integer(n) and n > 0, do: "#{n} waiting at the consumer."
  defp waiting(_none), do: nil

  defp failing(%{"commands" => commands, "effects" => effects} = failing)
       when commands + effects > 0 or is_map_key(failing, "subscription") do
    subscription = failing["subscription"]

    if commands + effects == 0 and subscription == nil,
      do: nil,
      else:
        "Failing: #{commands} commands, #{effects} effect jobs" <>
          if(subscription, do: ", the subscription #{shown(subscription)}.", else: ".")
  end

  defp failing(true), do: "Failing at the consumer."
  defp failing(_none), do: nil

  # --- words --------------------------------------------------------------------------------

  attr :facts, :map, required: true

  defp facts(assigns) do
    ~H"""
    <dl :if={@facts != %{}}>
      <%= for {key, value} <- Enum.sort(@facts) do %>
        <dt>{key}</dt>
        <dd>{shown(value)}</dd>
      <% end %>
    </dl>
    """
  end

  defp delivery_sentence("in_transaction"), do: "In the transaction that records the event."

  defp delivery_sentence("at_least_once"),
    do: "After the transaction, delivered at least once: a failure is retried."

  defp delivery_sentence(_none), do: nil

  defp idempotency(%{"key" => key, "owner" => owner}) do
    who =
      case owner do
        "self" -> "the reaction itself"
        "downstream" -> "the system it calls"
        "infrastructure" -> "the infrastructure"
        other -> other
      end

    "A second delivery is recognised by #{key} and kept harmless by #{who}."
  end

  defp idempotency(_none), do: nil

  # A manager's issue, set or cancel says on what, and in which phase of the run.
  defp on_phase(%{"on" => _} = relation, lookup), do: ", " <> on_phase_words(relation, lookup)
  defp on_phase(_relation, _lookup), do: nil

  defp on_phase_words(%{"on" => on, "phase" => phase}, lookup) do
    what = Lookup.title(lookup, on)

    cond do
      Lookup.kind(lookup, on) == "timer" -> "when #{what} fires"
      phase == "start" -> "on #{what}, as a run starts"
      true -> "on #{what}, during the run"
    end
  end

  defp on_phase_words(_relation, _lookup), do: nil

  defp on_phase_sentence(%{"on" => _} = relation, lookup) do
    words = on_phase_words(relation, lookup)
    String.upcase(String.first(words)) <> String.slice(words, 1..-1//1) <> "."
  end

  defp on_phase_sentence(_relation, _lookup), do: nil

  defp promise_window(promise) do
    [
      promise["within"] && ", kept within #{duration(promise["within"])}",
      promise["unverified"] && " (not confirmed by the process owner)"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join()
  end

  defp with_grant(%{"capability" => capability}) when is_binary(capability),
    do: ", with #{capability}"

  defp with_grant(_relation), do: nil

  defp timer_when(%{"wait" => %{} = wait}), do: "fires #{duration(wait)} after it is set"
  defp timer_when(%{"at" => at}) when is_binary(at), do: "fires at the time in #{at}"
  defp timer_when(_timer), do: "fires when set"

  defp operation(%{"operation" => op} = relation, lookup) when is_binary(op),
    do: ": " <> operation_title(relation, lookup)

  defp operation(_relation, _lookup), do: nil

  defp operation_title(%{"operation" => op, "to" => external}, lookup) do
    found =
      Enum.find((Lookup.node(lookup, external) || %{})["operations"] || [], &(&1["name"] == op))

    (found && found["label"]) || op
  end

  defp consulted(%{"match" => [_ | _] = match}), do: ", by #{Enum.join(match, ", ")}"
  defp consulted(%{"where" => where}) when is_binary(where), do: ", where #{where}"
  defp consulted(_relation), do: nil

  defp consulted_sentence(relation) do
    case consulted(relation) do
      nil -> nil
      ", " <> rest -> "Consulted #{rest}."
    end
  end

  defp direction("inbound"), do: "Data flows in from it."
  defp direction("outbound"), do: "Data flows out to it."
  defp direction("bidirectional"), do: "Data flows both ways."
  defp direction(other), do: other

  defp subdomain_type(id, lookup) do
    case (Lookup.node(lookup, id) || %{})["type"] do
      nil -> nil
      type -> ", #{type}"
    end
  end

  defp actor_kind(%{"actor_kind" => "system"}), do: "A system"
  defp actor_kind(_actor), do: "A person"

  defp grant_kind("command"), do: "issues"
  defp grant_kind("query"), do: "asks"
  defp grant_kind("record"), do: "records"
  defp grant_kind(other), do: other

  defp capability(lookup, id), do: (Lookup.node(lookup, id) || %{})["capability"]

  # The status a transition leaves names its unit.
  defp unit_of(lookup, status), do: (Lookup.node(lookup, status) || %{})["unit"]

  # The context-mapping relations of a context or an external, each with its other end and
  # how this one stands to it.
  @symmetric ~w(partnership shared_kernel separate_ways)
  @patterns ~w(partnership shared_kernel separate_ways customer_supplier conformist
               anticorruption_layer open_host_service published_language)

  defp patterns(lookup, id) do
    out =
      for r <- Lookup.out(lookup, id, @patterns) do
        {r, r["to"],
         if(r["type"] in @symmetric,
           do: words(r["type"]) <> " with",
           else: "upstream (#{words(r["type"])}) of"
         )}
      end

    into =
      for r <- Lookup.into(lookup, id, @patterns) do
        {r, r["from"],
         if(r["type"] in @symmetric,
           do: words(r["type"]) <> " with",
           else: "downstream (#{words(r["type"])}) of"
         )}
      end

    out ++ into
  end

  # The scenarios of a rule's owner's owner: a command's constraint shows in its unit's.
  defp owners_scenarios(lookup, owner) do
    case Lookup.node(lookup, owner) do
      %{"unit" => unit} -> Lookup.about(lookup, unit)
      _ -> []
    end
  end

  defp duration(%{"amount" => amount, "unit" => unit}),
    do: "#{amount} #{if amount == 1, do: unit, else: unit <> "s"}"

  defp duration(_other), do: "?"

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"

  defp count(list, noun) when is_list(list), do: count(length(list), noun)
  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"

  defp words(name), do: String.replace(name, "_", " ")

  defp shown(value) when is_binary(value), do: value
  defp shown(nil), do: "—"
  defp shown(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp shown(value), do: JSON.encode!(value)
end
