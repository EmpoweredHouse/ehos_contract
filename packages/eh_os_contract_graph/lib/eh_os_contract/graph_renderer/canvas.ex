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
  `t:EhOsContract.GraphRenderer.View.spec/0`): `:contract`, `:declared`,
  `{:unit, id}`, `{:lifecycle, id}`, `:context_map`, `:system`, or `:all`, every node
  and relation, which it draws when `view` is left out. Each node is a card, each
  group a box with its title, and each relation a label, all rendered here in HEEx;
  the hook (`EhOsContractGraph`, in `priv/static/eh_os_contract_graph.esm.js`) reads
  them from the page, lays them out in the view's direction and draws the arrows, each
  with the line and the head its label names. The overlay's marks
  (`EhOsContract.GraphRenderer.Marks`) are a count on the card or the label and a
  class per state, which the hook copies onto the arrow.

  **A click** on a card, a group's title, a label or an arrow selects it: the card, the
  title and the label are buttons with `phx-click`, the arrow is pushed by the hook,
  and both reach
  `handle_event("select", %{"id" => id}, …)` here. The selected element and what
  touches it are classes on the cards and the labels, everything else is drawn
  faint, and the panel beside the graph shows it. Clicking it again, or the panel's
  close button, clears the selection. The panel is raw for now — the facts of the
  node or relation as the document has them — until the panels are specified with
  the views (plan E13b, batch 4).

  **Nothing here renders a `style` attribute**, and the hook sets none: the host's
  Content-Security-Policy of `default-src 'self'` refuses one, and LiveView takes
  away on its next patch one the server did not render. Positions, sizes and the zoom
  live in the hook's constructed stylesheets. `test/canvas_test.exs` holds the
  template to it, `test/assets_test.exs` the hook. The one style anything sets is
  d3-zoom's tap highlight on the canvas, on a touch device, through the CSSOM, which
  the policy allows; the stylesheet sets the same, so LiveView taking it away changes
  nothing.

  **An id with a carriage return or a NUL cannot be selected**: the browser's HTML
  parser rewrites both in the `phx-value-id` a click sends, so the id that comes back
  is not the document's. Nothing a client declares today has either.
  """

  use Phoenix.LiveComponent

  alias EhOsContract.GraphRenderer.{Marks, View}

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

    {:ok,
     assign(socket,
       spec: spec,
       given: given,
       view: view,
       overlay: overlay,
       stale_overlay?: given != nil and overlay == nil,
       selected: if(selected && element(view, selected), do: selected)
     )}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    selected =
      cond do
        id == socket.assigns.selected -> nil
        element(socket.assigns.view, id) -> id
        true -> socket.assigns.selected
      end

    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("deselect", _params, socket), do: {:noreply, assign(socket, selected: nil)}

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        near: near(assigns.view, assigns.selected),
        picked: assigns.selected && element(assigns.view, assigns.selected)
      )

    ~H"""
    <div id={@id} class="ehg" phx-hook="EhOsContractGraph" data-direction={@view.direction}>
      <div class="ehg-canvas">
        <div class="ehg-viewport">
          <div
            :for={group <- @view.groups}
            class={["ehg-group" | classes(group.id, @selected, @near, nil)]}
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
            class={["ehg-card" | classes(node.id, @selected, @near, Marks.node(@overlay, node.id))]}
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
              blank?(relation, Marks.relation(@overlay, relation.id)) && "ehg-blank"
              | classes(relation.id, @selected, @near, Marks.relation(@overlay, relation.id))
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
            {relation.words}<.count marks={Marks.relation(@overlay, relation.id)} />
          </button>
        </div>
      </div>
      <p :if={@stale_overlay?} class="ehg-note">
        The numbers from the log are of another version of this document and are not shown.
      </p>
      <.panel :if={@picked} picked={@picked} view={@view} overlay={@overlay} myself={@myself} />
    </div>
    """
  end

  attr :marks, :map, required: true

  defp count(assigns) do
    ~H"""
    <span :if={@marks.count} class="ehg-count">×{@marks.count}</span>
    """
  end

  attr :picked, :map, required: true
  attr :view, :map, required: true
  attr :overlay, :map
  attr :myself, :any, required: true

  defp panel(%{picked: {kind, node}} = assigns) when kind in [:node, :group] do
    assigns = assign(assigns, node: node, log: get_in(assigns.overlay || %{}, ["nodes", node.id]))

    ~H"""
    <aside class="ehg-panel" aria-label="Selected">
      <header>
        <p class="ehg-panel-kind">{words(@node.kind)}</p>
        <h4>{@node.facts["label"] || @node.facts["name"]}</h4>
        <button type="button" phx-click="deselect" phx-target={@myself} aria-label="Close">×</button>
      </header>
      <.facts facts={Map.drop(@node.facts, ["id", "label"])} />
      <.log :if={@log} entry={@log} />
    </aside>
    """
  end

  defp panel(%{picked: {:relation, relation}} = assigns) do
    by_id = Map.new(assigns.view.nodes ++ assigns.view.groups, &{&1.id, &1})

    assigns =
      assign(assigns,
        relation: relation,
        from: Map.fetch!(by_id, relation.from),
        to: Map.fetch!(by_id, relation.to),
        log: get_in(assigns.overlay || %{}, ["relations", relation.id])
      )

    ~H"""
    <aside class="ehg-panel" aria-label="Selected">
      <header>
        <p class="ehg-panel-kind">relation</p>
        <h4>{words(@relation.type)}</h4>
        <button type="button" phx-click="deselect" phx-target={@myself} aria-label="Close">×</button>
      </header>
      <dl>
        <dt>from</dt>
        <dd>{words(@from.kind)} {@from.facts["label"] || @from.facts["name"]}</dd>
        <dt>to</dt>
        <dd>{words(@to.kind)} {@to.facts["label"] || @to.facts["name"]}</dd>
      </dl>
      <.facts facts={Map.drop(@relation.facts, ["id", "from", "to"])} />
      <.log :if={@log} entry={@log} />
    </aside>
    """
  end

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

  attr :entry, :map, required: true

  defp log(assigns) do
    ~H"""
    <p class="ehg-panel-kind">from the log</p>
    <.facts facts={@entry} />
    """
  end

  # The element `id` names, a node, a group or a relation of the view; nil when it has
  # none of them.
  defp element(view, id) do
    Enum.find_value([node: view.nodes, group: view.groups, relation: view.relations], fn
      {kind, elements} ->
        with %{} = found <- Enum.find(elements, &(&1.id == id)), do: {kind, found}
    end)
  end

  # What touches the selection: a node's relations, the nodes at their other ends and the
  # group it sits in; a group's cards and relations; a relation's two ends. Empty without
  # a selection.
  defp near(_view, nil), do: MapSet.new()

  defp near(view, selected) do
    touching = fn id -> Enum.filter(view.relations, &(&1.from == id or &1.to == id)) end

    case element(view, selected) do
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
  defp blank?(relation, marks), do: relation.words in [nil, ""] and marks.count == nil

  # A kind or a type in the panel: the name, spaced.
  defp words(name), do: String.replace(name, "_", " ")

  defp shown(value) when is_binary(value), do: value
  defp shown(nil), do: "—"
  defp shown(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp shown(value), do: JSON.encode!(value)
end
