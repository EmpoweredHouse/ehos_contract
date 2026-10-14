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

  alias EhOsContract.GraphRenderer.{Lookup, Marks, Panel, View}

  @impl true
  def mount(socket), do: {:ok, assign(socket, selected: nil)}

  # What an update leaves out stays as it was: a `send_update/2` with only an overlay keeps
  # the document and the view, and one without an overlay keeps the overlay. `:given` is
  # the overlay as the host passed it, `:overlay` the one drawn.
  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :document]))
    document = Map.fetch!(socket.assigns, :document)
    spec = Map.get(assigns, :view, socket.assigns[:spec] || :all)
    given = Map.get(assigns, :overlay, socket.assigns[:given])
    overlay = if given && given["document_digest"] == document["digest"], do: given
    view = View.build(document, spec, overlay)
    selected = socket.assigns.selected

    # The panel's joins, made once a document: reused only for the same digest, so a
    # document without one — a host may build one by hand — gets its own each time.
    digest = document["digest"]

    lookup =
      if digest != nil and socket.assigns[:lookup] != nil and
           socket.assigns[:lookup_of] == digest,
         do: socket.assigns.lookup,
         else: Lookup.new(document)

    {:ok,
     assign(socket,
       lookup: lookup,
       lookup_of: document["digest"],
       spec: spec,
       given: given,
       view: view,
       overlay: overlay,
       stale_overlay?: given != nil and overlay == nil,
       selected: if(selected && picked(view, document, selected), do: selected)
     )}
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

  def handle_event("deselect", _params, socket), do: {:noreply, assign(socket, selected: nil)}

  @impl true
  def render(assigns) do
    picked = assigns.selected && picked(assigns.view, assigns.document, assigns.selected)

    assigns =
      assign(assigns,
        near: near(assigns.view, assigns.selected),
        # A node the view does not draw is shown in the panel and fades nothing.
        focus: assigns.selected && element(assigns.view, assigns.selected) && assigns.selected,
        picked: picked
      )

    ~H"""
    <div
      id={@id}
      class="ehg"
      phx-hook="EhOsContractGraph"
      data-direction={@view.direction}
      data-selected={@selected}
    >
      <div class="ehg-canvas">
        <div class="ehg-viewport">
          <div
            :for={group <- @view.groups}
            class={["ehg-group" | classes(group.id, @focus, @near, nil)]}
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
            :for={node <- @view.nodes}
            type="button"
            class={[
              "ehg-card" | classes(node.id, @focus, @near, Marks.node(@overlay, node.id))
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
            <span :if={node.tag} class="ehg-kind">{node.tag}</span>
            <span :if={node.label || node.name} class="ehg-label">{node.label || node.name}</span>
            <span :if={node.label && node.name} class="ehg-name">{node.name}</span>
            <span :for={line <- node.lines} class="ehg-field">{line}</span>
            <.count marks={Marks.node(@overlay, node.id)} />
          </button>
          <button
            :for={relation <- @view.relations}
            type="button"
            class={[
              "ehg-relation",
              blank?(relation, marks(@overlay, relation)) && "ehg-blank"
              | classes(relation.id, @focus, @near, marks(@overlay, relation))
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
            {relation.words}<.count marks={marks(@overlay, relation)} />
          </button>
        </div>
      </div>
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

  # A promise's arrow carries the promise's verdicts, which the overlay keeps on the
  # promise; any other relation, its own numbers.
  defp marks(overlay, %{type: "promise"} = relation), do: Marks.promise(overlay, relation.facts)

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
