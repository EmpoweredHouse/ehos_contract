defmodule EhOsContract.GraphRenderer.Panel do
  # The panel of a graph, a sidebar at the right of the window: what the selected node,
  # group or relation is, read from the `graph.v1` document it belongs to (plan E13b,
  # batch 4: the points of the user's working plan for the Graph screen, in `PLAN.md`,
  # that a click answers, and the way it shows a field).
  #
  # Everything here is the document's: a node's own facts, and the joins over relations
  # and scenarios `EhOsContract.GraphRenderer.Lookup` makes — who may issue a command is
  # the `may_issue` relations into it, what a reaction issues the relations out of it,
  # the scenarios behind an arrow those whose `covers` names it. Nothing is derived from
  # the DSL's meaning; that is the engine's, and it is in the document already.
  #
  # The client's words — labels, terms, rules, scenario descriptions — are shown as the
  # client wrote them; the sentences around them are the renderer's, in English. A node
  # named in a panel is a button that shows it, whether or not the view draws it.
  #
  # | Selected | The panel shows |
  # | --- | --- |
  # | a command | its fields, who may issue it (people with the grant EHOS gives, reactions, timers, and the one person its unit's state names, where it says so), its scope, what its decision reads, the statuses it is allowed in, the rules it may be refused on |
  # | an event | its fields, who records it, where it comes from, the systems it rests on; in a process's document, its contract, its stage and whether it ends a run, its fields being in the contract's document |
  # | a policy, a process manager | what it takes and issues, its rules, delivery and idempotency, its scenarios — a manager's by what triggers them |
  # | an effect | the event it handles, the system and the operation it calls, its rules, delivery and idempotency |
  # | a read model, a query | what builds it and its fields; the query's parameters, who may ask, what it reads and returns, its scenarios |
  # | a context, an external system, an actor | the context's terms, relations, contracts and entities; the system's operations, outage and who uses it; the actor's role, responsibilities and what the role may do |
  # | a process, a stage, a promise | the process's run, deadline, who answers for it, the contracts whose events it includes, its stages and promises; a stage's place and events; a promise's window, its events, and its verdicts from the log or that it is unconfirmed |
  # | a relation | its two ends, what it says, and the scenarios that cover it |
  #
  # A field is shown the same way everywhere it appears: its name, label, type, whether
  # it is required, its default, and what it says of a person (personal data, or a
  # pointer to one), of a domain value (its members or unit), of an entity and of the
  # system that gives its value. What keeps a value about a person is the document's word
  # (`kept`): sealed or in the clear in the log, or in a read model's rows.
  #
  # For the owner (plan DD, L4, #326) the document comes without the facts of the code
  # (`EhOsContract.GraphRenderer.Audience`), so what tests for one says nothing of it; what
  # the panel writes itself in code — a name, a field's name and type, a scenario's data —
  # asks `ctx.code?`.
  @moduledoc false

  use Phoenix.Component

  import EhOsContract.GraphRenderer.Words

  alias EhOsContract.GraphRenderer.{Audience, Lookup}

  attr :picked, :any, required: true, doc: "`{:node | :group | :relation, element}` of a view"
  attr :lookup, Lookup, required: true, doc: "the joins over the element's document"
  attr :overlay, :map, default: nil
  attr :target, :any, required: true, doc: "where a click on a reference goes"

  attr :open, :map,
    default: nil,
    doc: "`%{id: id, label: words, target: target}`: a button that opens where the element leads"

  attr :audience, :atom, default: :engineering, doc: "who reads it: `:engineering` or `:owner`"

  @doc "The panel of what is selected."
  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    # Every part takes the joins, the click's target, the overlay and whether the reader
    # reads the code together.
    assigns
    |> assign(:ctx, %{
      lookup: assigns.lookup,
      target: assigns.target,
      overlay: assigns.overlay,
      open: assigns.open,
      code?: Audience.code?(assigns.audience)
    })
    |> selected()
  end

  defp selected(%{picked: {:relation, relation}} = assigns) do
    assigns =
      assign(assigns,
        relation: relation,
        covering: Lookup.covering(assigns.lookup, relation.id),
        log: relation_log(assigns.overlay, relation)
      )

    ~H"""
    <.frame kind="relation" title={words(@relation.type)} ctx={@ctx}>
      <dl>
        <dt>from</dt>
        <dd><.ref id={@relation.from} ctx={@ctx} /></dd>
        <dt>to</dt>
        <dd><.ref id={@relation.to} ctx={@ctx} /></dd>
      </dl>
      <.relation_body type={@relation.type} facts={@relation.facts} ctx={@ctx} />
      <.scenarios :if={@covering != []} title="Scenarios covering it" list={@covering} ctx={@ctx} />
      <.log :if={@log} entry={@log} ctx={@ctx} />
    </.frame>
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
    <.frame
      kind={words(@kind)}
      title={@node["label"] || @node["name"]}
      name={@ctx.code? && @node["label"] && @node["name"]}
      ctx={@ctx}
    >
      <.body kind={@kind} node={@node} ctx={@ctx} />
      <p :if={@node["source"] && @kind not in ["command", "event"]} class="ehg-source">
        Source: {@node["source"]}
      </p>
      <.log :if={@log} entry={@log} ctx={@ctx} />
    </.frame>
    """
  end

  attr :kind, :string, required: true
  attr :title, :string, required: true
  attr :name, :string, default: nil
  attr :ctx, :map, required: true
  slot :inner_block, required: true

  # The sidebar: its left edge, which the hook drags to set its width, a header with the
  # close button, and a body that scrolls.
  defp frame(assigns) do
    ~H"""
    <aside class="ehg-panel" aria-label="Selected">
      <div class="ehg-panel-grip" role="separator" aria-orientation="vertical" aria-label="Panel width">
      </div>
      <div class="ehg-panel-body">
        <header>
          <p class="ehg-panel-kind">{@kind}</p>
          <h4>{@title}</h4>
          <button type="button" phx-click="deselect" phx-target={@ctx.target} aria-label="Close">
            ×
          </button>
          <p :if={@name} class="ehg-panel-name">{@name}</p>
        </header>
        <button
          :if={@ctx.open}
          type="button"
          class="ehg-open"
          phx-click="open"
          phx-value-id={@ctx.open.id}
          phx-target={@ctx.open.target}
        >
          {@ctx.open.label} →
        </button>
        {render_slot(@inner_block)}
      </div>
    </aside>
    """
  end

  # --- a node, by its kind ------------------------------------------------------------------

  attr :kind, :string, required: true
  attr :node, :map, required: true
  attr :ctx, :map, required: true

  defp body(%{kind: "command"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        people: Lookup.into(l, id, "may_issue"),
        reactions: Lookup.into(l, id, "issues"),
        timers: Lookup.into(l, id, "fires"),
        allowed: Lookup.out(l, id, "allowed_in"),
        refused: Lookup.out(l, id, "refused_on"),
        # A read of no entity is named by its binding in code, which the owner does not read.
        reads: for(r <- assigns.node["reads"] || [], assigns.ctx.code? or r["entity"], do: r)
      )

    ~H"""
    <.part title="Fields"><.fields fields={@node["fields"] || []} of="command" ctx={@ctx} /></.part>
    <.part title="Who may issue it">
      <.refs relations={@people} side="from" ctx={@ctx} />
      <.refs relations={@reactions} side="from" then={:phase} ctx={@ctx} />
      <.refs relations={@timers} side="from" then={:fires} ctx={@ctx} />
      <p :if={@node["capability"]}>EHOS grants it as <code>{@node["capability"]}</code>.</p>
      <p :if={@node["actor_is"] && @ctx.code?}>
        Only the person its unit's <code>{@node["actor_is"]}</code> names; anyone else is refused.
      </p>
      <p :if={@node["actor_is"] && !@ctx.code?}>
        Only the person its unit names; anyone else is refused.
      </p>
      <p :if={@people == [] and @reactions == [] and @timers == []} class="ehg-empty">
        Nothing in the contract issues it.
      </p>
    </.part>
    <.part :if={@reads != []} title="Reads before deciding">
      <p :for={r <- @reads}>
        <.ref :if={r["entity"]} id={r["entity"]} ctx={@ctx} />
        <span :if={!r["entity"]}>{r["name"]}</span><span :if={@ctx.code?}>, the row its <code>{r["field"]}</code> names</span>
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
        <.ref id={@node["unit"]} ctx={@ctx} />{if @node["creates"], do: ", which it creates"}
      </p>
    </.part>
    <.part :if={@allowed != []} title="Allowed in">
      <.refs relations={@allowed} side="to" ctx={@ctx} />
    </.part>
    <.part :if={@refused != []} title="May be refused on">
      <.refs relations={@refused} side="to" then={:outside} ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "event"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
    received = Lookup.into(l, id, "received_as")

    assigns =
      assign(assigns,
        people: Lookup.into(l, id, "may_record"),
        received: received,
        rests: Lookup.out(l, id, "depends_on")
      )

    ~H"""
    <.part :if={@node["fields"] not in [nil, []]} title="Fields">
      <.fields fields={@node["fields"]} of="event" ctx={@ctx} />
    </.part>
    <.part title="Where it comes from">
      <p :if={@node["unit"]}>Recorded in <.ref id={@node["unit"]} ctx={@ctx} />.</p>
      <p :if={@node["declared_as"]}>Declared in another contract and consumed here.</p>
      <p :for={r <- @received} :if={@ctx.code?}>
        Received from another application as <.ref id={r["from"]} ctx={@ctx} />.
      </p>
      <p :if={@received != [] and !@ctx.code?}>Received from another application.</p>
      <p :if={@node["contract"]}>Declared in <.ref id={@node["contract"]} ctx={@ctx} />.</p>
      <p :if={@node["type"]}>
        In the log as <code>{@node["type"]}</code>{if @node["schema_version"],
          do: ", schema version #{@node["schema_version"]}"}.
      </p>
      <p :if={@node["stage"]}>In the stage <.ref id={@node["stage"]} ctx={@ctx} />.</p>
      <p :if={@node["stage"] && @node["contract"] && !Map.has_key?(@node, "fields")} class="ehg-quiet">
        Its fields, and the unit that records it, are in the contract's own document.
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
    """
  end

  defp body(%{kind: "policy"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
    handles = Lookup.into(l, id, "handled_by")

    assigns =
      assign(assigns,
        handles: handles,
        inbox?: Enum.any?(handles, &(&1["via_inbox"] == true)),
        issues: Lookup.out(l, id, "issues"),
        scenarios: Lookup.about(l, id)
      )

    ~H"""
    <.part title="Takes"><.refs relations={@handles} side="from" then={:inbox} ctx={@ctx} /></.part>
    <.part title="Issues">
      <.refs relations={@issues} side="to" ctx={@ctx} />
      <p :if={@issues == []}>Nothing.</p>
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} inbox?={@inbox?} />
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "process_manager"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

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
    <.part :if={@ends != []} title="Ends on"><.refs relations={@ends} side="from" ctx={@ctx} /></.part>
    <.part :if={@timers != []} title="Timers">
      <ul class="ehg-list">
        <li :for={t <- @timers}>
          <.ref id={t["id"]} ctx={@ctx} /> — {timer_when(t, @ctx)}<span :for={
            r <- Lookup.out(@ctx.lookup, t["id"], "fires")
          }>, issuing <.ref id={r["to"]} ctx={@ctx} /></span>
        </li>
      </ul>
    </.part>
    <.part :if={@issues != []} title="Issues">
      <.refs relations={@issues} side="to" then={:phase} ctx={@ctx} />
    </.part>
    <.part :if={@node["state"] not in [nil, []]} title="What it remembers">
      <.fields fields={@node["state"]} of="process_manager" ctx={@ctx} />
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} />
    <.part title={count(length(@scenarios), "scenario")}>
      <div :for={{title, group} <- by_trigger(@scenarios, @ctx.lookup)} class="ehg-trigger">
        <p class="ehg-trigger-title">{title}</p>
        <.scenario :for={s <- group} scenario={s} ctx={@ctx} />
      </div>
    </.part>
    """
  end

  defp body(%{kind: "timer"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
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
      A timer of <.ref id={@node["process_manager"]} ctx={@ctx} />: {timer_when(@node, @ctx)}.
    </p>
    <.part title="Set">
      <ul class="ehg-list">
        <li :for={r <- @sets}>{phase(r, @ctx.lookup)}</li>
      </ul>
    </.part>
    <.part :if={@cancels != []} title="Cancelled">
      <ul class="ehg-list">
        <li :for={r <- @cancels}>{phase(r, @ctx.lookup)}</li>
      </ul>
    </.part>
    <.part title="When it fires, issues"><.refs relations={@fires} side="to" ctx={@ctx} /></.part>
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "effect"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        handles: Lookup.into(l, id, "handled_by"),
        calls: Lookup.out(l, id, "calls")
      )

    ~H"""
    <.part title="Takes"><.refs relations={@handles} side="from" ctx={@ctx} /></.part>
    <.part title="Calls"><.refs relations={@calls} side="to" then={:operation} ctx={@ctx} /></.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.delivery node={@node} />
    <p class="ehg-quiet">An effect has no scenarios: what it does is outside the contract.</p>
    """
  end

  defp body(%{kind: "read_model"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        built: Lookup.into(l, id, "projected_into"),
        read: Lookup.into(l, id, "reads")
      )

    ~H"""
    <.part title="Built from"><.refs relations={@built} side="from" ctx={@ctx} /></.part>
    <.part title="Fields"><.fields fields={@node["fields"] || []} of="read_model" ctx={@ctx} /></.part>
    <.part title="Read by">
      <.refs relations={@read} side="from" ctx={@ctx} />
      <p :if={@read == []}>No query.</p>
    </.part>
    <.delivery node={@node} />
    """
  end

  defp body(%{kind: "query"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
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
      <.fields fields={@node["params"] || []} of="query" ctx={@ctx} />
      <p :if={@node["params"] in [nil, []]}>None.</p>
    </.part>
    <.part title="Who may ask">
      <.refs relations={@people} side="from" ctx={@ctx} />
      <p :if={@node["capability"]}>EHOS grants it as <code>{@node["capability"]}</code>.</p>
      <p :if={@people == [] and !@node["capability"]} class="ehg-quiet">No actor may ask it.</p>
    </.part>
    <.part title="Reads">
      <.refs relations={@reads} side="to" ctx={@ctx} />
      <p>{if @node["returns"] == "one", do: "Returns one row.", else: "Returns a list of rows."}</p>
      <p :if={@node["scope"]}>
        A grant narrows the answer to the rows of one <code>{@node["scope"]}</code>.
      </p>
    </.part>
    <.part :if={@answer != []} title="What a row holds">
      <.fields fields={@answer} of="read_model" ctx={@ctx} />
    </.part>
    <.rules of={@node["id"]} ctx={@ctx} />
    <.scenarios title="Scenarios" list={@scenarios} ctx={@ctx} />
    """
  end

  defp body(%{kind: "unit"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

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
      {if @node["unit_kind"] == "dcb", do: "A dynamic consistency boundary", else: "An aggregate"}<span :if={@node["identity"]}>, identified by
      <code>{Enum.join(List.wrap(@node["identity"]), ", ")}</code></span>{if @node["generated"],
        do: ", which the library generates (#{@node["generated"]}) when a command creates one"}.
    </p>
    <p :if={@node["records_only"]}>Records only: no command it takes can be refused.</p>
    <.part :if={@node["state"] not in [nil, []]} title="State">
      <.fields fields={@node["state"]} of="unit" ctx={@ctx} />
    </.part>
    <.part :if={@commands != []} title="Commands"><.nodes list={@commands} ctx={@ctx} /></.part>
    <.part :if={@events != []} title="Events"><.nodes list={@events} ctx={@ctx} /></.part>
    <.part :if={@consulted != []} title="Consults">
      <.refs relations={@consulted} side="from" then={:consulted} ctx={@ctx} />
    </.part>
    <.part :if={@rules != []} title="Rules"><.nodes list={@rules} ctx={@ctx} /></.part>
    <.part :if={@statuses != []} title="Statuses">
      <.nodes list={@statuses} then={:final} ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: kind} = assigns) when kind in ["invariant", "constraint"] do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
    owner = assigns.node["of"]

    # A rule shows in its owner's scenarios, and a command's constraint in its unit's.
    owners = [owner | List.wrap((Lookup.node(l, owner) || %{})["unit"])]

    showing =
      for o <- owners,
          s <- Lookup.about(l, o),
          s["rejected"] == id or id in (s["illustrates"] || []),
          uniq: true,
          do: s

    assigns = assign(assigns, refusing: Lookup.into(l, id, "refused_on"), showing: showing)

    ~H"""
    <p>A rule of <.ref id={@node["of"]} ctx={@ctx} />.</p>
    <.part :if={@refusing != []} title="Refuses">
      <.refs relations={@refusing} side="from" then={:outside} ctx={@ctx} />
    </.part>
    <.scenarios title="Scenarios it shows in" list={@showing} ctx={@ctx} />
    """
  end

  defp body(%{kind: "status"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

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
          from <.ref id={r["from"]} ctx={@ctx} /> on <.ref id={r["event"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@moves_out != []} title="Moves out of it">
      <ul class="ehg-list">
        <li :for={r <- @moves_out}>
          to <.ref id={r["to"]} ctx={@ctx} /> on <.ref id={r["event"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@allowed != []} title="Commands allowed in it">
      <.refs relations={@allowed} side="from" ctx={@ctx} />
    </.part>
    """
  end

  defp body(%{kind: "actor"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

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
    <.part :if={@backed != []} title="Stands for"><.refs relations={@backed} side="to" ctx={@ctx} /></.part>
    <.part :if={@node["responsibilities"] not in [nil, []]} title="Responsible for">
      <ul class="ehg-list">
        <li :for={r <- @node["responsibilities"]}>
          {r["label"] || r["name"]}<span :if={r["source"]} class="ehg-quiet"> · {r["source"]}</span>
        </li>
      </ul>
    </.part>
    <.part :if={@issue != []} title="May issue"><.granted relations={@issue} ctx={@ctx} /></.part>
    <.part :if={@record != []} title="May record"><.granted relations={@record} ctx={@ctx} /></.part>
    <.part :if={@ask != []} title="May ask"><.granted relations={@ask} ctx={@ctx} /></.part>
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
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    gives =
      for kind <- ~w(command event read_model unit),
          node <- Lookup.nodes(l, kind),
          field <- (node["fields"] || []) ++ (node["state"] || []),
          field["issued_by"] == id,
          do: {node["id"], field}

    assigns =
      assign(assigns,
        calls: Lookup.into(l, id, "calls"),
        rests: Lookup.into(l, id, "depends_on"),
        waiting: Lookup.into(l, id, "waits_on"),
        backed: Lookup.into(l, id, "backed_by"),
        gives: gives
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
          {o["label"] || o["name"]} <code :if={@ctx.code?}>{o["name"]}</code>
        </li>
      </ul>
    </.part>
    <.part :if={@calls != []} title="Called by">
      <.refs relations={@calls} side="from" then={:operation} ctx={@ctx} />
    </.part>
    <.part :if={@rests != []} title="Events resting on it">
      <.refs relations={@rests} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@waiting != []} title="Promises waiting on it">
      <.refs relations={@waiting} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@gives != []} title="Gives the value of">
      <ul class="ehg-list">
        <li :for={{node, field} <- @gives}>
          <code :if={@ctx.code?}>{field["name"]}</code><span :if={!@ctx.code?}>{field["label"]}</span>
          of <.ref id={node} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@backed != []} title="Stands behind">
      <.refs relations={@backed} side="from" ctx={@ctx} />
    </.part>
    <.patterns of={@node["id"]} ctx={@ctx} />
    """
  end

  defp body(%{kind: "context"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
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
            <span :if={term["code"]} class="ehg-translation">In code: <code>{term["code"]}</code></span>
          </dd>
        <% end %>
      </dl>
    </.part>
    <.patterns of={@node["id"]} ctx={@ctx} />
    <.part :if={@contracts != []} title="Contracts"><.nodes list={@contracts} ctx={@ctx} /></.part>
    <.part :if={@entities != []} title="Entities">
      <div :for={e <- @entities} class="ehg-trigger">
        <p class="ehg-trigger-title">
          <.ref id={e["id"]} ctx={@ctx} /><span :if={e["identity"]}>, identified by <code>{e["identity"]}</code></span>
        </p>
        <.fields fields={e["fields"] || []} of="entity" ctx={@ctx} />
      </div>
    </.part>
    <.part :if={@values != []} title="Values"><.nodes list={@values} ctx={@ctx} /></.part>
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

  # A process in its own document, with its stages and promises, or in its domain's, with
  # the contracts whose events it includes.
  defp body(%{kind: "process"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        stages: Lookup.owned(l, "stage", "process", id),
        promises: Lookup.owned(l, "promise", "process", id),
        accountable: Lookup.into(l, id, "accountable_for"),
        # A domain's document joins a process to its contracts by `includes`; a process's
        # own holds the contracts its events come from, and no other.
        includes: Lookup.out(l, id, "includes"),
        contracts: if(Lookup.of(l) == "process", do: Lookup.nodes(l, "contract"), else: [])
      )

    ~H"""
    <p :if={@node["module"]}>
      The process module <code>{@node["name"]}</code>, in the code <code>{@node["module"]}</code>.
    </p>
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
    <.part :if={@includes != [] or @contracts != []} title="Includes events of">
      <.refs relations={@includes} side="to" ctx={@ctx} />
      <.nodes list={@contracts} ctx={@ctx} />
    </.part>
    <.part :if={@stages != []} title="Stages, in order"><.nodes list={@stages} ctx={@ctx} /></.part>
    <.part :if={@promises != []} title="Promises"><.nodes list={@promises} ctx={@ctx} /></.part>
    """
  end

  defp body(%{kind: "stage"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}
    stages = Lookup.owned(l, "stage", "process", assigns.node["process"])

    assigns =
      assign(assigns,
        events: Lookup.owned(l, "event", "stage", id),
        position: Enum.find_index(stages, &(&1["id"] == id)),
        of: length(stages)
      )

    ~H"""
    <p>
      Stage {(@position || 0) + 1} of {@of} of <.ref id={@node["process"]} ctx={@ctx} />.
    </p>
    <.part title="Events">
      <.nodes list={@events} ctx={@ctx} />
      <p :if={length(@events) > 1} class="ehg-quiet">No order is claimed among them.</p>
      <p :if={@events == []} class="ehg-empty">No event sits in it.</p>
    </.part>
    """
  end

  defp body(%{kind: "promise"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        opens: Lookup.into(l, id, "opens"),
        fulfils: Lookup.into(l, id, "fulfils"),
        or_else: Lookup.into(l, id, "or_else"),
        waits: Lookup.out(l, id, "waits_on")
      )

    ~H"""
    <p>A promise of <.ref id={@node["process"]} ctx={@ctx} />{promise_window(@node)}.</p>
    <.part title="Opened by"><.refs relations={@opens} side="from" ctx={@ctx} /></.part>
    <.part title="Kept by"><.refs relations={@fulfils} side="from" ctx={@ctx} /></.part>
    <.part :if={@or_else != []} title="Kept the other way by">
      <.refs relations={@or_else} side="from" ctx={@ctx} />
    </.part>
    <.part :if={@waits != []} title="Waits on, through an earlier step">
      <.refs relations={@waits} side="to" ctx={@ctx} />
      <p class="ehg-quiet">An outage of it inside the window excuses the promise.</p>
    </.part>
    <.unconfirmed promise={@node} ctx={@ctx} />
    """
  end

  defp body(%{kind: "publication"} = assigns) do
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

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
          <.ref id={r["from"]} ctx={@ctx} />, with <code>{Enum.join(r["fields"] || [], ", ")}</code>{repeat_key(
            r
          )}
        </li>
      </ul>
    </.part>
    <.part :if={@publishers != []} title="Published by">
      <ul class="ehg-list">
        <li :for={r <- @publishers}>
          <.ref id={r["from"]} ctx={@ctx} /> from <.ref id={r["event"]} ctx={@ctx} />
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
    {id, l} = {assigns.node["id"], assigns.ctx.lookup}

    assigns =
      assign(assigns,
        from: Lookup.into(l, id, "consumed_by"),
        to: Lookup.out(l, id, "consumed_by"),
        refers_to: Lookup.out(l, id, "refers_to"),
        referred_by: Lookup.into(l, id, "refers_to"),
        publishes: Lookup.out(l, id, "publishes"),
        subscribes: Lookup.into(l, id, "subscribed_by"),
        included: Lookup.into(l, id, "includes")
      )

    ~H"""
    <p :if={@ctx.code?}>
      The contract <code>{@node["name"]}</code>, in the code <code>{@node["module"]}</code>.
    </p>
    <p :if={@node["context"]}>In the context <.ref id={@node["context"]} ctx={@ctx} />.</p>
    <.part :if={@included != []} title="Processes that include its events">
      <.refs relations={@included} side="from" ctx={@ctx} />
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
    <.part :if={@refers_to != []} title="Keeps the number of">
      <ul class="ehg-list">
        <li :for={r <- @refers_to}>
          {units_of(r)}<.ref id={r["to"]} ctx={@ctx} />
        </li>
      </ul>
    </.part>
    <.part :if={@referred_by != []} title="Its units' numbers are kept by">
      <ul class="ehg-list">
        <li :for={r <- @referred_by}>
          <.ref id={r["from"]} ctx={@ctx} />{if r["units"] not in [nil, []],
            do: ": #{Enum.join(r["units"], ", ")}"}
        </li>
      </ul>
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
    <p :if={@node["context"]}>Of the context <.ref id={@node["context"]} ctx={@ctx} />.</p>
    <p :if={@node["type"] && value_words(@node, @ctx)}>{value_words(@node, @ctx)}</p>
    <.part :if={@node["fields"] not in [nil, []]} title="Fields">
      <.fields fields={@node["fields"]} of="value" ctx={@ctx} />
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
    <p :if={@node["identity"]}>
      Identified by <code>{@node["identity"]}</code>{if @node["context"], do: ", in the context"}
      <.ref :if={@node["context"]} id={@node["context"]} ctx={@ctx} />.
    </p>
    <p :if={!@node["identity"] && @node["context"]}>
      In the context <.ref id={@node["context"]} ctx={@ctx} />.
    </p>
    <.part :if={@node["fields"] not in [nil, []]} title="Fields">
      <.fields fields={@node["fields"]} of="entity" ctx={@ctx} />
    </.part>
    """
  end

  # Anything else — a subject, a domain service — as the document has it.
  defp body(assigns) do
    ~H"""
    <.facts :if={@ctx.code?} facts={Map.drop(@node, ["id", "label", "name", "source"])} />
    """
  end

  # --- a relation, by its type --------------------------------------------------------------

  attr :type, :string, required: true
  attr :facts, :map, required: true
  attr :ctx, :map, required: true

  # What a view draws as an arrow of its own: a field an external system gives, a move a
  # lifecycle does not allow, a promise between the event that opens it and the one that
  # keeps it, one stage before the next.
  defp relation_body(%{type: "gives"} = assigns) do
    ~H"""
    <p>The system gives the value of this field.</p>
    <.fields fields={[@facts]} of="command" ctx={@ctx} />
    """
  end

  defp relation_body(%{type: "undeclared"} = assigns) do
    ~H"""
    <p class="ehg-empty">
      Seen in the log on <.ref id={@facts["event"]} ctx={@ctx} />, though the lifecycle does
      not allow this move.
    </p>
    """
  end

  # The declared shape's arrow carries the promise itself; the document's `or_else` is an
  # event's relation to it, which the generic clause says.
  defp relation_body(%{type: type, facts: %{"process" => _}} = assigns)
       when type in ["promise", "or_else"] do
    ~H"""
    <p>
      The promise <.ref id={@facts["id"]} ctx={@ctx} />{promise_window(@facts)}: the first event
      opens it, and the second keeps it{if @type == "or_else", do: " the other way"}.
    </p>
    <.unconfirmed promise={@facts} ctx={@ctx} />
    """
  end

  defp relation_body(%{type: "waits_on"} = assigns) do
    ~H"""
    <p>
      The promise <.ref id={@facts["from"]} ctx={@ctx} /> waits on
      <.ref id={@facts["to"]} ctx={@ctx} /> through an earlier step: an outage of it inside
      the promise's window excuses the promise.
    </p>
    """
  end

  defp relation_body(%{type: "out_of_order"} = assigns) do
    ~H"""
    <p>
      {if is_integer(@facts["runs"]), do: count(@facts["runs"], "run"), else: "Runs"} entered <.ref id={@facts["from"]} ctx={@ctx} /> before
      <.ref id={@facts["to"]} ctx={@ctx} />, which the process puts first, in the period the
      log was read for. Which runs is the application's to find.
    </p>
    """
  end

  defp relation_body(%{type: "precedes"} = assigns) do
    ~H"""
    <p>The first stage comes before the second.</p>
    """
  end

  defp relation_body(%{type: "consumed_by"} = assigns) do
    ~H"""
    <.consumed relation={@facts} ctx={@ctx} />
    """
  end

  # A move of a lifecycle, and a new aggregate's first status: on which event. The
  # lifecycle draws a new one's arrow from its start, and the event is where it came from.
  defp relation_body(%{type: type} = assigns) when type in ["transition", "enters"] do
    assigns =
      assign(assigns,
        event: if(type == "enters", do: assigns.facts["from"], else: assigns.facts["event"])
      )

    ~H"""
    <p :if={@event}>On <.ref id={@event} ctx={@ctx} />.</p>
    <p :if={@facts["source"]}>Source: {@facts["source"]}</p>
    """
  end

  defp relation_body(assigns) do
    assigns =
      assign(assigns,
        sentences: relation_sentences(assigns.type, assigns.facts, assigns.ctx)
      )

    ~H"""
    <p :for={sentence <- @sentences}>{sentence}</p>
    <.pairs relation={@facts} />
    """
  end

  defp relation_sentences(type, facts, %{lookup: lookup} = ctx) do
    reaction = Lookup.node(lookup, facts["to"]) || %{}
    issuer = Lookup.node(lookup, facts["from"]) || %{}

    Enum.reject(
      [
        type == "handled_by" && facts["via_inbox"] &&
          "Through the inbox, after the transaction: it was received from another application.",
        type == "handled_by" && !facts["via_inbox"] && delivery_sentence(reaction["delivery"]),
        type == "issues" && sentence(phase(facts, lookup)),
        type == "issues" && delivery_sentence(issuer["delivery"]),
        type in ["sets", "cancels"] && sentence(phase(facts, lookup)),
        type == "calls" && facts["operation"] &&
          "The operation #{operation_title(facts, lookup)}.",
        type == "consulted_by" && sentence(consulted_words(facts)),
        type == "refused_on" && facts["outside_from"] &&
          "Refused on it outside the statuses the command is allowed in.",
        type == "refused_on" && facts["actor_is"] &&
          "Refused on it " <> not_the_person(facts, ctx) <> ".",
        type == "published_as" &&
          "Published as #{facts["name"]}, with #{Enum.join(facts["fields"] || [], ", ")}.",
        type == "publishes" && facts["event"] && "From #{Lookup.title(lookup, facts["event"])}.",
        type == "subscribed_by" && "As #{facts["as"]}#{with_grant(facts)}.",
        type == "refers_to" && facts["units"] not in [nil, []] &&
          "It keeps the number of #{Enum.join(facts["units"], ", ")}, which " <>
            "#{Lookup.title(lookup, facts["to"])} decides.",
        type == "refers_to" && facts["units"] in [nil, []] &&
          "It keeps the number of a unit #{Lookup.title(lookup, facts["to"])} decides.",
        facts["source"] && "Source: #{facts["source"]}"
      ],
      &(&1 in [nil, false])
    )
  end

  # The refusal of a command that one person alone may issue: the field naming them is
  # the command's, which the relation leaves from, and a name in code the owner does not read.
  defp not_the_person(_relation, %{code?: false}),
    do: "when the one issuing it is not the person its unit names"

  defp not_the_person(relation, %{lookup: lookup}) do
    field = (Lookup.node(lookup, relation["from"]) || %{})["actor_is"]
    "when the one issuing it is not the person its unit's #{field} names"
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

  # A node named in a panel: a button that shows it, with its kind; it never closes the
  # panel, even when it names what the panel is of. An id the document does not hold is
  # shown as it is.
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
      phx-click="show"
      phx-value-id={@id}
      phx-target={@ctx.target}
    >{@title}<span class="ehg-ref-kind">{words(@kind)}</span></button><span :if={!@kind} class="ehg-ref">{@title}</span>
    """
  end

  attr :relations, :list, required: true
  attr :side, :string, required: true, doc: "which end of each relation to name"
  attr :then, :atom, default: nil, doc: "what follows each name (`after_ref/3`)"
  attr :ctx, :map, required: true

  defp refs(assigns) do
    ~H"""
    <ul :if={@relations != []} class="ehg-list">
      <li :for={r <- @relations}>
        <.ref id={r[@side]} ctx={@ctx} />{after_ref(@then, r, @ctx)}
      </li>
    </ul>
    """
  end

  attr :list, :list, required: true
  attr :then, :atom, default: nil, doc: "what follows each name (`after_ref/3`)"
  attr :ctx, :map, required: true

  defp nodes(assigns) do
    ~H"""
    <ul :if={@list != []} class="ehg-list">
      <li :for={n <- @list}><.ref id={n["id"]} ctx={@ctx} />{after_ref(@then, n, @ctx)}</li>
    </ul>
    """
  end

  # What follows a name in a list, by what the list is of.
  defp after_ref(nil, _relation_or_node, _ctx), do: nil
  defp after_ref(:phase, r, ctx), do: phase(r, ctx.lookup) && ", " <> phase(r, ctx.lookup)
  defp after_ref(:fires, _r, _ctx), do: ", when it fires"
  defp after_ref(:inbox, r, _ctx), do: if(r["via_inbox"], do: ", through the inbox")

  defp after_ref(:outside, r, ctx) do
    cond do
      r["outside_from"] -> " — outside the statuses it is allowed in"
      r["actor_is"] -> " — " <> not_the_person(r, ctx)
      true -> nil
    end
  end

  defp after_ref(:operation, r, ctx),
    do: if(r["operation"], do: ": " <> operation_title(r, ctx.lookup))

  defp after_ref(:consulted, r, _ctx), do: consulted_words(r) && ", " <> consulted_words(r)
  defp after_ref(:final, node, _ctx), do: if(node["final"], do: " — an end")

  attr :relations, :list, required: true
  attr :ctx, :map, required: true

  # What a role may do here: each declaration, and the grant EHOS gives for it.
  defp granted(assigns) do
    ~H"""
    <ul class="ehg-list">
      <li :for={r <- @relations}>
        <.ref id={r["to"]} ctx={@ctx} /><code :if={capability(@ctx.lookup, r["to"])} class="ehg-grant">{capability(
            @ctx.lookup,
            r["to"]
          )}</code>
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
          :if={e["as"] && e["as"] != (Lookup.node(@ctx.lookup, e["event"]) || %{})["name"]}
          class="ehg-quiet"
        > · as {e["as"]}</span>
      </li>
    </ul>
    """
  end

  attr :of, :string, required: true
  attr :ctx, :map, required: true

  # The context-mapping relations of a context or an external, each with its other end and
  # how this one stands to it, and the pairs of words it translates between.
  defp patterns(assigns) do
    l = assigns.ctx.lookup

    mapped =
      for(
        r <- Lookup.out(l, assigns.of),
        mapping?(l, r["to"]),
        do: {r, r["to"], standing(r, "upstream")}
      ) ++
        for r <- Lookup.into(l, assigns.of),
            mapping?(l, r["from"]),
            do: {r, r["from"], standing(r, "downstream")}

    assigns = assign(assigns, mapped: mapped)

    ~H"""
    <.part :if={@mapped != []} title="Relations">
      <ul class="ehg-list">
        <li :for={{relation, other, words} <- @mapped}>
          {words} <.ref id={other} ctx={@ctx} /><.pairs relation={relation} />
        </li>
      </ul>
    </.part>
    """
  end

  # A context or an external on the other end: a relation between two of them is a
  # context-mapping pattern, the only kind the domain's document holds between them.
  defp mapping?(lookup, id), do: Lookup.kind(lookup, id) in ["context", "external"]

  defp standing(%{"type" => type} = r, side) do
    if r["symmetric"], do: words(type) <> " with", else: "#{side} (#{words(type)}) of"
  end

  attr :relation, :map, required: true

  defp pairs(assigns) do
    ~H"""
    <ul :if={@relation["terms"] not in [nil, []]} class="ehg-list ehg-pairs">
      <li :for={[here, there] <- @relation["terms"]}>{here} ↔ {there}</li>
    </ul>
    """
  end

  attr :of, :string, required: true
  attr :ctx, :map, required: true

  # The rules declared on a reaction or a query: its constraints, and a manager's invariants.
  defp rules(assigns) do
    l = assigns.ctx.lookup

    assigns =
      assign(assigns,
        rules:
          Lookup.owned(l, "constraint", "of", assigns.of) ++
            Lookup.owned(l, "invariant", "of", assigns.of)
      )

    ~H"""
    <.part :if={@rules != []} title="Rules"><.nodes list={@rules} ctx={@ctx} /></.part>
    """
  end

  attr :node, :map, required: true
  attr :inbox?, :boolean, default: false

  # When a reaction or a read model runs, and what makes a second delivery harmless. An event
  # received from another application reaches a policy through the inbox whatever its delivery.
  defp delivery(assigns) do
    ~H"""
    <.part :if={@node["delivery"] || @node["idempotency"] || @inbox?} title="Delivery">
      <p :if={@node["delivery"]}>{delivery_sentence(@node["delivery"])}</p>
      <p :if={@inbox?}>
        An event received from another application reaches it through the inbox, after the
        transaction, whatever its delivery.
      </p>
      <p :if={@node["idempotency"]}>{idempotency(@node["idempotency"])}</p>
    </.part>
    """
  end

  # --- fields -------------------------------------------------------------------------------

  attr :fields, :list, required: true
  attr :of, :string, required: true, doc: "the kind of what the fields are of"
  attr :ctx, :map, required: true

  # Each field the same way, wherever it is: a command's, an event's, a state's, a read
  # model's, a query's parameters.
  defp fields(assigns) do
    ~H"""
    <ul :if={@fields != []} class="ehg-fields">
      <li :for={field <- @fields}>
        <span :if={@ctx.code?} class="ehg-field-name">{field["name"]}</span>
        <span :if={field["label"]} class="ehg-field-label">{field["label"]}</span>
        <span :if={@ctx.code?} class="ehg-field-type">{field_type(field)}</span>
        <span :if={!@ctx.code? and field["required"] == false} class="ehg-field-type">optional</span>
        <span :for={{look, note} <- field_notes(field, @fields, @ctx)} class={look}>
          {note}
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

  # What a field says beyond its type, each as `{class, sentence}`. That the host supplies
  # it is the code's.
  defp field_notes(field, siblings, %{lookup: lookup} = ctx) do
    [
      field["personal_of"] &&
        {"ehg-field-note ehg-personal", personal(field, siblings, ctx)},
      field["subject"] && {"ehg-field-note ehg-personal", pointer(field, lookup)},
      field["value"] && value_words(Lookup.node(lookup, field["value"]), ctx),
      match?(%{"enum" => _}, field["type"]) && "One of: #{members(field["type"])}.",
      field["refers_to"] && "Identifies #{Lookup.title(lookup, field["refers_to"])}.",
      field["issued_by"] && "Its value comes from #{Lookup.title(lookup, field["issued_by"])}.",
      ctx.code? && field["supplied_by"] == "host" && "Supplied by the host, not the caller."
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(fn
      {_class, _sentence} = note -> note
      sentence -> {"ehg-field-note", sentence}
    end)
  end

  # Whose personal data a field is, and what keeps it, as the document says (`kept`). The
  # field naming the person may have no label, so the owner reads its subject only.
  defp personal(field, siblings, %{lookup: lookup} = ctx) do
    holder = Enum.find(siblings, &(&1["name"] == field["personal_of"])) || %{}

    whose =
      case {holder["subject"], ctx.code?} do
        {nil, true} -> "the person in #{field["personal_of"]}"
        {nil, false} -> "a person"
        {subject, _code?} -> Lookup.title(lookup, subject)
      end

    case field["kept"] do
      "log_sealed" ->
        "Personal data of #{whose} — encrypted in the log, gone once they are erased."

      "rows_forgotten" ->
        "Personal data of #{whose} — forgotten once they are erased."

      _ ->
        "Personal data of #{whose}."
    end
  end

  defp pointer(field, lookup) do
    whom = Lookup.title(lookup, field["subject"])

    if field["kept"] == "log_clear",
      do: "Points at #{whom} — in the log in the clear.",
      else: "Points at #{whom}."
  end

  # A domain value in words: its label, and its members, its type or its fields, and its
  # unit; for the owner, the members of one that has them, and nothing of the code's types.
  defp value_words(nil, _ctx), do: nil

  defp value_words(%{"type" => %{"enum" => _} = enum} = value, %{code?: false}),
    do: "#{value["label"] || value["name"]}: #{members(enum)}."

  defp value_words(_value, %{code?: false}), do: nil

  defp value_words(value, _ctx) do
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
      <div :if={@scenario["given_entities"]}>
        <p class="ehg-step">The application keeps</p>
        <.with_data :for={r <- @scenario["given_entities"]} id={r["entity"]} data={r["data"]} ctx={@ctx} />
      </div>
      <p class="ehg-step">When</p>
      <p :if={@scenario["actor"]}>
        <.ref id={@scenario["actor"]} ctx={@ctx} />{if @ctx.code? && @scenario["as"],
          do: " #{@scenario["as"]}"} issues
      </p>
      <.with_data id={@scenario["command"]["command"]} data={@scenario["command"]["data"]} ctx={@ctx} />
      <p class="ehg-step">Then</p>
      <p :if={@scenario["rejected"]} class="ehg-refused">
        refused on <.ref id={@scenario["rejected"]} ctx={@ctx} />
      </p>
      <.with_data :for={e <- @scenario["expect"] || []} id={e["event"]} data={e["data"]} ctx={@ctx} />
      <p :if={!@scenario["rejected"] and @scenario["expect"] in [nil, []]}>nothing is recorded</p>
    </article>
    """
  end

  defp scenario(%{scenario: %{"type" => "policy"}} = assigns) do
    ~H"""
    <article class="ehg-scenario">
      <p class="ehg-scenario-title">{@scenario["description"]}</p>
      <p class="ehg-step">On</p>
      <.with_data id={@scenario["event"]["event"]} data={@scenario["event"]["data"]} ctx={@ctx} />
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
      <p :for={t <- @scenario["sets"] || []}>sets <.ref id={t} ctx={@ctx} /></p>
      <p :for={t <- @scenario["cancels"] || []}>cancels <.ref id={t} ctx={@ctx} /></p>
      <p :if={@scenario["ended"]} class="ehg-strong">the run ends</p>
      <div :if={@ctx.code? and @scenario["state"] not in [nil, %{}]}>
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
      <p :if={@ctx.code?} class="ehg-step">Asked with</p>
      <.data :if={@ctx.code?} data={@scenario["params"] || %{}} />
      <p class="ehg-step">It answers</p>
      <div :for={row <- List.wrap(@scenario["answers"])} :if={@ctx.code?} class="ehg-row">
        <.data data={row} />
      </div>
      <p :if={!@ctx.code? and @scenario["answers"] not in [nil, []]}>
        {count(length(List.wrap(@scenario["answers"])), "row")}
      </p>
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
      <.with_data :for={e <- @list} id={e["event"]} data={e["data"]} at={e["at"]} ctx={@ctx} />
    </div>
    """
  end

  attr :list, :list, required: true
  attr :ctx, :map, required: true

  defp issued(assigns) do
    ~H"""
    <p class="ehg-step">{if @list == [], do: "it issues nothing", else: "it issues"}</p>
    <.with_data :for={c <- @list} id={c["command"]} data={c["data"]} ctx={@ctx} />
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
  attr :at, :string, default: nil, doc: "When it happened, where a scenario dates it."
  attr :ctx, :map, required: true

  defp with_data(assigns) do
    ~H"""
    <div class="ehg-happened">
      <.ref id={@id} ctx={@ctx} />{if @at, do: ", at #{@at}"}
      <.data :if={@ctx.code?} data={@data || %{}} />
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

  # What the log says of the relation a panel is of: a promise's arrow says what the log
  # says of the promise.
  defp relation_log(nil, _relation), do: nil

  defp relation_log(overlay, %{type: type, facts: %{"process" => _} = promise})
       when type in ["promise", "or_else"],
       do: get_in(overlay, ["nodes", promise["id"]])

  defp relation_log(overlay, relation), do: get_in(overlay, ["relations", relation.id])

  attr :promise, :map, required: true
  attr :ctx, :map, required: true

  # A promise the owner has yet to confirm is judged against no run, so the log has
  # nothing to say of it: said so, as the document says it, where a reader would look
  # for its verdicts.
  defp unconfirmed(assigns) do
    ~H"""
    <p :if={@promise["unverified"]} class="ehg-empty">
      Unconfirmed: no run is judged against it until the process owner confirms it.
    </p>
    """
  end

  # The units whose numbers a contract keeps, before the contract that decides them; none
  # where the owner's document leaves their names in code out.
  defp units_of(%{"units" => [_ | _] = units}), do: Enum.join(units, ", ") <> " of "
  defp units_of(_relation), do: nil

  # A promise's verdicts over the runs that opened it, as the report gives them.
  defp log_sentences(%{"instances" => runs} = verdicts, _lookup) do
    n = &(verdicts[&1] || 0)

    Enum.reject(
      [
        if(runs == 0, do: "No run has opened it.", else: "Opened in #{count(runs, "run")}."),
        n.("satisfied") > 0 &&
          "Kept in #{n.("satisfied")}: #{n.("satisfied_via_eventually")} by the event that " <>
            "keeps it, #{n.("satisfied_via_or_else")} the other way.",
        n.("violated") > 0 && "Broken in #{n.("violated")}.",
        n.("pending") > 0 && "Pending in #{n.("pending")}: not kept yet.",
        n.("suspended") > 0 &&
          "Suspended in #{n.("suspended")}: broken while a system it depends on was down."
      ],
      &(&1 in [nil, false])
    )
  end

  defp log_sentences(%{"by_trigger" => by_trigger}, lookup) do
    for {event, step} <- Enum.sort(by_trigger),
        sentence <- log_sentences(step, lookup),
        do: "On #{Lookup.title(lookup, event)}: #{sentence}"
  end

  defp log_sentences(entry, _lookup) do
    # A lifecycle's transition counts moves; anything else with `pending` is a step.
    transition? = Map.has_key?(entry, "count") and Map.has_key?(entry, "untraversed")

    Enum.reject(
      [
        entry["occurrences"] && "Recorded #{times(entry["occurrences"])}.",
        entry["runs"] && "#{count(entry["runs"], "run")}.",
        entry["aggregates"] && "#{count(entry["aggregates"], "aggregate")}.",
        entry["taken"] && "Taken #{times(entry["taken"])}.",
        entry["count"] && "Made #{times(entry["count"])}.",
        entry["events"] && "#{count(entry["events"], "event")} crossed.",
        entry["untraversed"] == true && "Never taken: the report lists it as a path never taken.",
        entry["pending"] == true && transition? &&
          "Not yet taken: an aggregate still stands where it can be taken.",
        entry["pending"] == true && !transition? &&
          "Not yet taken: work is still on its way to it.",
        waiting(entry),
        failing(entry)
      ],
      &(&1 in [nil, false])
    )
  end

  # A step says whether it waits or fails (`waits`, `fails`, the report's reading) and
  # by how much; traffic between contracts gives a count waiting and whether any fails.
  defp waiting(%{"waits" => true, "waiting" => w}),
    do:
      "Waiting: #{w["lag"]} not reached yet, #{w["timers"]} timers not fired, " <>
        "#{w["effects"]} effect jobs not run."

  defp waiting(%{"waiting" => n}) when is_integer(n) and n > 0,
    do: "#{n} waiting at the consumer."

  defp waiting(_entry), do: nil

  defp failing(%{"fails" => true, "failing" => f}) do
    "Failing: #{f["commands"]} commands, #{f["effects"]} effect jobs" <>
      if(f["subscription"], do: ", the subscription #{shown(f["subscription"])}.", else: ".")
  end

  defp failing(%{"failing" => true}), do: "Failing at the consumer."
  defp failing(_entry), do: nil

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

  # A manager's issue, set or cancel: on what, and in which phase of the run; nil for a
  # relation that says neither.
  defp phase(%{"on" => on, "phase" => phase}, lookup) do
    what = Lookup.title(lookup, on)

    cond do
      Lookup.kind(lookup, on) == "timer" -> "when #{what} fires"
      phase == "start" -> "on #{what}, as a run starts"
      true -> "on #{what}, during the run"
    end
  end

  defp phase(_relation, _lookup), do: nil

  # A phrase as a sentence of its own.
  defp sentence(nil), do: nil

  defp sentence(phrase),
    do: String.capitalize(String.first(phrase)) <> String.slice(phrase, 1..-1//1) <> "."

  # When a timer fires: after a wait, or at the time a field of the run holds, which the
  # owner reads without the field's name.
  defp timer_when(%{"wait" => %{} = wait}, _ctx), do: "fires #{duration(wait)} after it is set"

  defp timer_when(%{"at" => at}, ctx) when is_binary(at),
    do: if(ctx.code?, do: "fires at the time in #{at}", else: "fires at a moment the run holds")

  defp timer_when(_timer, _ctx), do: "fires when set"

  defp promise_window(promise) do
    [
      promise["within"] && ", kept within #{duration(promise["within"])}",
      promise["unverified"] && " (not confirmed by the process owner)"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join()
  end

  defp repeat_key(%{"idempotent_on" => [_ | _] = keys}),
    do: ", a repeat recognised by #{Enum.join(keys, ", ")}"

  defp repeat_key(_relation), do: nil

  defp with_grant(%{"capability" => capability}) when is_binary(capability),
    do: ", with #{capability}"

  defp with_grant(_relation), do: nil

  defp operation_title(%{"operation" => op, "to" => external}, lookup) do
    found =
      Enum.find((Lookup.node(lookup, external) || %{})["operations"] || [], &(&1["name"] == op))

    (found && found["label"]) || op
  end

  defp consulted_words(%{"match" => [_ | _] = match}), do: "by #{Enum.join(match, ", ")}"
  defp consulted_words(%{"where" => where}) when is_binary(where), do: "where #{where}"
  defp consulted_words(_relation), do: nil

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

  # The unit a status is of.

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"

  defp shown(value) when is_binary(value), do: value
  defp shown(nil), do: "—"
  defp shown(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp shown(value), do: JSON.encode!(value)
end
