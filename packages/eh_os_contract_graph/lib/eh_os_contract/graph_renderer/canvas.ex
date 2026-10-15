defmodule EhOsContract.GraphRenderer.Canvas do
  @moduledoc """
  A `graph.v1` document drawn as an interactive graph, with a panel for what is
  selected: the component a host renders.

      <.live_component
        module={EhOsContract.GraphRenderer.Canvas}
        id="contract-graph"
        document={@document}
        overlay={@overlay}
        view={:contract}
      />

  `document` is a `graph.v1` document with string keys, as the engine gives it and
  as JSON decodes it. `overlay` is optional: an `eh_os_contract.graph_overlay.v1` of
  the same document, laid over it — an overlay whose `document_digest` is not the
  document's `digest` is of another version and is not drawn, as its schema says. `id`
  is the root element's DOM id, so it is unique on the page.

  **What it draws** is the view `view` names (`EhOsContract.GraphRenderer.View`,
  `t:EhOsContract.GraphRenderer.View.spec/0`): `:contract`, `{:unit, id}`,
  `{:lifecycle, id}`, `:process`, `:context_map`, `:system`, or `:all`, every node
  and relation, which it draws when `view` is left out. Each node is a card, each
  group a box with its title, and each relation a label, all rendered here in HEEx;
  the hook (`EhOsContractGraph`, in `priv/static/eh_os_contract_graph.esm.js`) reads
  them from the page, lays them out in the view's direction and draws the arrows, each
  with the line and the head its label names. The overlay's marks are a count on the
  card or the label and a class per state, which the hook copies onto the arrow; on a
  process's promise, the runs that kept it, broke it or wait, or that it is unconfirmed,
  which no run is judged against.

  **A bar over the canvas** holds what the reader moves through the picture with:

  - a search, which dims the cards it does not find as the reader types — by label, name in
    code, kind or footer, ignoring case — and on Enter selects the first one it finds and
    moves the view to it;
  - with an overlay of this version of the document, a switch between the declaration
    alone and the declaration with what the log says;
  - "Focus on the selection", which draws only the selected card or group and what its
    relations reach, laid out again (`EhOsContract.GraphRenderer.View.around/2`), until
    "Show the whole picture" or the panel closes;
  - the zoom's buttons, which the hook answers alone: closer, farther, "Readable" and
    "Whole picture".

  **A picture starts readable.** It is never drawn larger than its own size, nor smaller
  than a scale its words can be read at: one that does not fit starts where reading
  starts, at its left edge (its top, drawn top to bottom), and the reader pans to the
  rest or asks for the whole picture, however small. A wheel with Ctrl or ⌘, or a pinch,
  zooms; a drag pans.

  **A click** on a card, a group's title, a label or an arrow selects it: the card, the
  title and the label are buttons with `phx-click`, the arrow is pushed by the hook,
  and both reach
  `handle_event("select", %{"id" => id}, …)` here. The selected element and what
  touches it are classes on the cards and the labels, everything else is drawn
  faint, and the panel says what it is.
  Clicking it again, the panel's close button, or Escape clears the selection.

  **The panel is a sidebar** at the right of the window, as tall as it, whose left
  edge the reader drags to set its width, kept in the browser between visits. One is
  open at a time: selecting in one canvas clears the selection of the others on the
  page (the hook does it). It lies over the page rather than narrowing it, so opening
  it resizes no canvas. It opens `--eh-os-contract-graph-panel-width` wide, which a
  host may set.
  A node the view does not draw can be selected too — from a name in the panel, or
  from outside the component, `phx-target` naming its root — and the panel shows it
  while the graph stays as it is.

  **Nothing here renders a `style` attribute**, and the hook sets none: the host's
  Content-Security-Policy of `default-src 'self'` refuses one, and LiveView takes
  away on its next patch one the server did not render. Positions and sizes live in
  the hook's constructed stylesheets; the zoom, and the panel's width while its edge
  is dragged, are Web Animations, since WebKit styles the whole page again whenever a
  stylesheet changes, which on every frame made Safari stutter. `test/canvas_test.exs` holds the
  template to it, `test/assets_test.exs` the hook. The one style anything sets is
  d3-zoom's tap highlight on the canvas, on a touch device, through the CSSOM, which
  the policy allows; the stylesheet sets the same, so LiveView taking it away changes
  nothing.

  **An id with a carriage return or a NUL cannot be selected**: the browser's HTML
  parser rewrites both in the `phx-value-id` a click sends, so the id that comes back
  is not the document's. Nothing a client declares today has either.
  """

  use Phoenix.LiveComponent

  alias EhOsContract.GraphRenderer.{Icons, Lookup, Marks, Panel, View}

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, selected: nil, query: "", focus: nil, log: true, reveal: 0)}

  # What an update leaves out stays as it was: a `send_update/2` with only an overlay keeps
  # the document and the view, and one without an overlay keeps the overlay. `:given` is
  # the overlay as the host passed it, `:overlay` the one drawn.
  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :document]))
    document = Map.fetch!(socket.assigns, :document)
    spec = Map.get(assigns, :view, socket.assigns[:spec] || :all)
    given = Map.get(assigns, :overlay, socket.assigns[:given])

    # The panel's joins, made once a document: reused only for the same digest, so a
    # document without one — a host may build one by hand — gets its own each time.
    digest = document["digest"]

    lookup =
      if digest != nil and socket.assigns[:lookup] != nil and
           socket.assigns[:lookup_of] == digest,
         do: socket.assigns.lookup,
         else: Lookup.new(document)

    socket =
      socket
      |> assign(lookup: lookup, lookup_of: digest, spec: spec, given: given)
      |> build()

    selected = socket.assigns.selected
    view = socket.assigns.view

    {:ok,
     socket
     |> assign(selected: if(selected && picked(view, document, selected), do: selected))
     |> assign(
       focus:
         if(socket.assigns.focus && element(view, socket.assigns.focus), do: socket.assigns.focus)
     )
     |> show()}
  end

  # The view and what the log says over it: the overlay the host gave, when it is of this
  # version of the document and the reader has the log on.
  defp build(socket) do
    %{document: document, spec: spec, given: given, log: log} = socket.assigns
    current = given && given["document_digest"] == document["digest"]
    overlay = if current && log, do: given
    view = View.build(document, spec, overlay)

    assign(socket,
      view: view,
      overlay: overlay,
      # What the overlay says of each card and arrow, read once per view and overlay
      # rather than at every render a selection makes.
      node_marks: Map.new(view.nodes, &{&1.id, Marks.node(overlay, &1.id)}),
      relation_marks: Map.new(view.relations, &{&1.id, marks(overlay, &1)}),
      stale_overlay?: given != nil and not current,
      logged?: current == true
    )
  end

  # What is drawn: the view, or the neighbourhood of what the reader focuses on; and which
  # of its cards the search finds.
  defp show(socket) do
    %{view: view, focus: focus, query: query} = socket.assigns
    shown = if focus, do: View.around(view, focus), else: view
    assign(socket, shown: shown, matches: View.matches(shown, query))
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    selected =
      cond do
        id == socket.assigns.selected -> nil
        picked(socket.assigns.view, socket.assigns.document, id) -> id
        true -> socket.assigns.selected
      end

    {:noreply, assign(socket, selected: selected)}
  end

  # A name in the panel shows its node, and never closes the panel, even when it names what
  # the panel is of.
  def handle_event("show", %{"id" => id}, socket) do
    if picked(socket.assigns.view, socket.assigns.document, id),
      do: {:noreply, assign(socket, selected: id)},
      else: {:noreply, socket}
  end

  def handle_event("deselect", _params, socket),
    do: {:noreply, socket |> assign(selected: nil, focus: nil) |> show()}

  # The search dims what it does not find as the reader types; Enter selects the first card
  # it finds and moves the view to it.
  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, socket |> assign(query: query) |> show()}

  def handle_event("find", %{"q" => query}, socket) do
    socket = socket |> assign(query: query) |> show()

    case Enum.find(
           socket.assigns.shown.nodes,
           &(socket.assigns.matches && MapSet.member?(socket.assigns.matches, &1.id))
         ) do
      nil -> {:noreply, socket}
      node -> {:noreply, assign(socket, selected: node.id, reveal: socket.assigns.reveal + 1)}
    end
  end

  # Focus keeps the selection and what touches it, laid out again; the whole picture comes
  # back with the button, a new selection's Escape, or the close of the panel.
  def handle_event("focus", _params, socket) do
    selected = socket.assigns.selected

    if selected && element(socket.assigns.view, selected),
      do: {:noreply, socket |> assign(focus: selected) |> show()},
      else: {:noreply, socket}
  end

  def handle_event("unfocus", _params, socket),
    do: {:noreply, socket |> assign(focus: nil) |> show()}

  # The declaration alone, or with what the log says over it.
  def handle_event("log", _params, socket),
    do: {:noreply, socket |> assign(log: not socket.assigns.log) |> build() |> show()}

  @impl true
  def render(assigns) do
    picked = assigns.selected && picked(assigns.view, assigns.document, assigns.selected)

    assigns =
      assign(assigns,
        near: near(assigns.shown, assigns.selected),
        # A node the picture does not draw is shown in the panel and fades nothing.
        lit: assigns.selected && element(assigns.shown, assigns.selected) && assigns.selected,
        focusable?: assigns.selected != nil and element(assigns.view, assigns.selected) != nil,
        picked: picked
      )

    ~H"""
    <div
      id={@id}
      class="ehg"
      phx-hook="EhOsContractGraph"
      data-direction={@view.direction}
      data-selected={@selected}
      data-reveal={@reveal}
    >
      <div class="ehg-bar">
        <form id={"#{@id}-search"} class="ehg-search" role="search" phx-change="search" phx-submit="find" phx-target={@myself}>
          <input
            type="search"
            name="q"
            value={@query}
            placeholder="Search this picture"
            aria-label="Search this picture"
            autocomplete="off"
            phx-debounce="150"
          />
          <span :if={@matches} class="ehg-found" aria-live="polite">{found(@matches)}</span>
        </form>
        <label :if={@logged?} class="ehg-switch">
          <input type="checkbox" checked={@log} phx-click="log" phx-target={@myself} />
          What the log says
        </label>
        <button :if={@focus} type="button" class="ehg-tool" phx-click="unfocus" phx-target={@myself}>
          Show the whole picture
        </button>
        <button
          :if={!@focus and @focusable?}
          type="button"
          class="ehg-tool"
          phx-click="focus"
          phx-target={@myself}
        >
          Focus on the selection
        </button>
        <span class="ehg-zoom" role="group" aria-label="Zoom">
          <button type="button" class="ehg-tool" data-ehg-zoom="out" aria-label="Zoom out">−</button>
          <button type="button" class="ehg-tool" data-ehg-zoom="in" aria-label="Zoom in">+</button>
          <button type="button" class="ehg-tool" data-ehg-zoom="read">Readable</button>
          <button type="button" class="ehg-tool" data-ehg-zoom="all">Whole picture</button>
        </span>
      </div>
      <div class="ehg-canvas">
        <div class="ehg-viewport">
          <div
            :for={group <- @shown.groups}
            class={["ehg-group" | classes(group.id, @lit, @near, nil)]}
            data-ehg-group={group.id}
            data-kind={group.kind}
          >
            <button
              type="button"
              class="ehg-group-title"
              title={group.title}
              phx-click="select"
              phx-value-id={group.id}
              phx-target={@myself}
            >
              {group.title}
            </button>
          </div>
          <svg id={"#{@id}-arrows"} class="ehg-arrows" phx-update="ignore" aria-hidden="true"></svg>
          <button
            :for={node <- @shown.nodes}
            type="button"
            class={[
              "ehg-card",
              @matches && not MapSet.member?(@matches, node.id) && "is-unmatched"
              | classes(node.id, @lit, @near, @node_marks[node.id])
            ]}
            data-ehg-node={node.id}
            data-kind={node.kind}
            data-variant={node.variant}
            data-group={node.group}
            aria-label={if node.kind == "start", do: "start"}
            phx-click="select"
            phx-value-id={node.id}
            phx-target={@myself}
          >
            <span :if={node.tag || @node_marks[node.id].count} class="ehg-top">
              <span :if={node.tag} class="ehg-kind"><Icons.icon kind={node.kind} />{node.tag}</span>
              <.count marks={@node_marks[node.id]} />
            </span>
            <span :if={node.label || node.name} class="ehg-label">{node.label || node.name}</span>
            <span :if={node.label && node.name} class="ehg-name"><.breakable text={node.name} /></span>
            <span :for={line <- node.lines} class="ehg-field">{line}</span>
            <span :if={node.foot} class="ehg-foot"><.breakable text={node.foot} /></span>
          </button>
          <button
            :for={relation <- @shown.relations}
            type="button"
            class={[
              "ehg-relation",
              blank?(relation, @relation_marks[relation.id]) && "ehg-blank"
              | classes(relation.id, @lit, @near, @relation_marks[relation.id])
            ]}
            data-ehg-relation={relation.id}
            data-from={relation.from}
            data-to={relation.to}
            data-line={relation.line}
            data-head={if relation.head, do: "arrow", else: "none"}
            phx-click="select"
            phx-value-id={relation.id}
            phx-target={@myself}
          >
            {relation.words}<.count marks={@relation_marks[relation.id]} />
          </button>
        </div>
      </div>
      <.legend legend={View.legend(@shown)} />
      <p :if={@stale_overlay?} class="ehg-note">
        The numbers from the log are of another version of this document and are not shown.
      </p>
      <Panel.panel :if={@picked} picked={@picked} lookup={@lookup} overlay={@overlay} target={@myself} />
    </div>
    """
  end

  attr :marks, :map, required: true

  defp count(assigns) do
    ~H"""
    <span :if={@marks.count} class="ehg-count">×{@marks.count}</span><span
      :if={@marks[:verdict]}
      class="ehg-count"
    >· {@marks[:verdict]}</span>
    """
  end

  defp found(matches) do
    case MapSet.size(matches) do
      0 -> "nothing found"
      1 -> "1 found"
      n -> "#{n} found"
    end
  end

  attr :legend, :map, required: true

  # What a swatch of each look shows, said for a reader who cannot see it.
  @looks %{
    "solid" => "a solid arrow",
    "dotted" => "a dotted arrow",
    "thick" => "a heavy arrow",
    "headless" => "a line with no head"
  }

  # What the cards' colours and icons and the arrows' looks mean, for what this view draws.
  defp legend(assigns) do
    assigns = assign(assigns, :looks, @looks)

    ~H"""
    <ul :if={@legend.kinds != [] or @legend.lines != []} class="ehg-legend" aria-label="Legend">
      <li :for={{kind, words} <- @legend.kinds} class="ehg-legend-kind" data-kind={kind}>
        <Icons.icon kind={kind} />{words}
      </li>
      <li :for={{variant, words} <- @legend.variants} class="ehg-legend-variant" data-variant={variant}>
        <span class="ehg-legend-swatch" aria-hidden="true"></span>{words}
      </li>
      <li :for={{look, words} <- @legend.lines} class="ehg-legend-line" data-look={look}>
        <svg viewBox="0 0 24 8" aria-hidden="true" focusable="false"><path d="M1 4h19" /><path
            :if={look != "headless"}
            class="ehg-legend-head"
            d="M18 1l5 3-5 3z"
          /></svg><span class="ehg-hidden">{@looks[look]}: </span>{words}
      </li>
    </ul>
    """
  end

  attr :text, :string, required: true

  # A name in code that may break after a dot, an underscore or a colon, and inside a word
  # only where one word alone is wider than the card.
  defp breakable(assigns) do
    assigns = assign(assigns, :parts, Regex.split(~r/(?<=[._:])/u, assigns.text))

    ~H"""
    <%= for {part, i} <- Enum.with_index(@parts) do %><wbr :if={i > 0} />{part}<% end %>
    """
  end

  # Both arrows of a promise are the promise's, which the overlay keeps the verdicts of, as
  # their panel says: each takes its state — a broken promise in the error colour — and
  # the heavy one alone says the verdicts in words, so they are read once. Any other
  # relation, its own numbers.
  defp marks(overlay, %{type: "promise"} = relation), do: Marks.promise(overlay, relation.facts)

  defp marks(overlay, %{type: "or_else", facts: %{"process" => _} = promise}),
    do: overlay |> Marks.promise(promise) |> Map.delete(:verdict)

  defp marks(overlay, relation), do: Marks.relation(overlay, relation.id)

  # The element `id` names, a node, a group or a relation of the view; nil when it has
  # none of them.
  defp element(view, id) do
    Enum.find_value([node: view.nodes, group: view.groups, relation: view.relations], fn
      {kind, elements} ->
        with %{} = found <- Enum.find(elements, &(&1.id == id)), do: {kind, found}
    end)
  end

  # What `id` names for the panel: an element of the view, or else a node of the document,
  # shown as the view would show it; nil when the document has no such node either.
  defp picked(view, document, id) do
    element(view, id) ||
      Enum.find_value(document["nodes"] || %{}, fn {kind, group} ->
        with %{} = node <- Enum.find(group, &(&1["id"] == id)),
             do: {:node, %{kind: kind, facts: node}}
      end)
  end

  # What touches the selection: a node's relations, the nodes at their other ends and the
  # group it sits in; a group's cards and relations; a relation's two ends. Empty without
  # a selection, and for a node the view does not draw.
  defp near(_view, nil), do: MapSet.new()

  defp near(view, selected) do
    touching = fn id -> Enum.filter(view.relations, &(&1.from == id or &1.to == id)) end

    case element(view, selected) do
      nil ->
        MapSet.new()

      {:node, node} ->
        MapSet.new([node.group | Enum.flat_map(touching.(node.id), &[&1.id, &1.from, &1.to])])

      {:group, group} ->
        members = for %{group: ^selected} = node <- view.nodes, do: node.id
        MapSet.new(members ++ Enum.flat_map(touching.(group.id), &[&1.id, &1.from, &1.to]))

      {:relation, relation} ->
        MapSet.new([relation.from, relation.to])
    end
  end

  defp classes(id, selected, near, marks) do
    focus =
      cond do
        selected == nil -> []
        id == selected -> ["is-selected"]
        MapSet.member?(near, id) -> ["is-near"]
        true -> ["is-far"]
      end

    focus ++ Enum.map((marks && marks.states) || [], &"is-#{&1}")
  end

  # A label with nothing to say is there for the hook, which reads the relation from it,
  # and takes no room: the arrow alone is drawn, and takes the click.
  defp blank?(relation, marks),
    do: relation.words in [nil, ""] and marks.count == nil and marks[:verdict] == nil
end
