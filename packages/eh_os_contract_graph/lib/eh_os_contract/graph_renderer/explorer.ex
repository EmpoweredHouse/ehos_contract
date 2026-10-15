defmodule EhOsContract.GraphRenderer.Explorer do
  # Plan DD, stage G1 (#297): one canvas with two viewpoints, the user's decisions of
  # 15 October — the renderer holds the navigation, so the EHOS Console draws what the
  # dashboard draws, and a host gives it a loader the explorer calls in the background.
  @moduledoc """
  An application's contracts as one canvas the reader moves through: the component a host
  renders to show a domain's graph, with its documents from a loader
  (`EhOsContract.GraphRenderer.Loader`).

      <.live_component
        module={EhOsContract.GraphRenderer.Explorer}
        id="graph"
        domain="Rehmed.Domain"
        loader={MyAppWeb.GraphLoader}
      />

  `domain` names the domain as its documents do, by its module; `loader` is a module, or
  `{module, opts}` to hand the loader `opts`.

  **Two viewpoints**, as tabs over the canvas, share a path ("Rehmed.Domain ›
  rehmed.scheduling › visit") that goes back up:

  - **Structure:** the domain's system — its contracts in their contexts, what one consumes
    from another, the drift's numbers on each — with a switch to its context map; a
    contract's full graph; one of its units, with a switch to its lifecycle when it
    declares one.
  - **Processes:** the domain's process modules, and one's picture: its stages, the events
    in them and its promises.

  Each picture is an `EhOsContract.GraphRenderer.Canvas`, with its search, focus and
  panel. **The panel opens where a card leads:** a contract or a process of the map, a
  unit of a contract, and an event's unit or contract — from a process's event to the
  contract that declares it, across the two viewpoints.

  **Documents load in the background**, each the first time the reader enters a picture
  of it, its overlay beside it: the picture is drawn declared as soon as its document
  arrives, and the log's numbers follow. One that fails to load says so in place of the
  picture. Each document is loaded once per explorer.
  """

  use Phoenix.LiveComponent

  alias EhOsContract.GraphRenderer.{Actors, Canvas, Places, View}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       place: :domain,
       lens: :graph,
       documents: %{},
       overlays: %{}
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.take(assigns, [:id, :domain]))
      |> assign(:loader, loader(Map.fetch!(assigns, :loader)))

    {:ok, socket |> load(Places.ref(:domain, socket.assigns.domain)) |> load_place()}
  end

  defp loader({module, opts}) when is_atom(module), do: {module, opts}
  defp loader(module) when is_atom(module), do: {module, []}

  # The documents the place is drawn from, each loaded once: the domain's, which names
  # what there is, and the place's own.
  defp load_place(socket),
    do: load(socket, Places.ref(socket.assigns.place, socket.assigns.domain))

  defp load(socket, ref) do
    if Map.has_key?(socket.assigns.documents, ref) do
      socket
    else
      {module, opts} = socket.assigns.loader

      socket
      |> assign(documents: Map.put(socket.assigns.documents, ref, :loading))
      |> start_async({:document, ref}, fn -> module.document(ref, opts) end)
      |> start_async({:overlay, ref}, fn -> module.overlay(ref, opts) end)
    end
  end

  @impl true
  def handle_async({:document, ref}, result, socket),
    do:
      {:noreply,
       assign(socket, documents: Map.put(socket.assigns.documents, ref, loaded(result)))}

  def handle_async({:overlay, ref}, result, socket) do
    overlay =
      case loaded(result) do
        {:ok, overlay} -> overlay
        _failed -> nil
      end

    {:noreply, assign(socket, overlays: Map.put(socket.assigns.overlays, ref, overlay))}
  end

  # What a loader answered, or what became of a loader that raised or exited: a picture it
  # could not load, never a crash of the host's page.
  defp loaded({:ok, {:ok, %{} = document}}), do: {:ok, document}
  defp loaded({:ok, {:ok, nil}}), do: {:ok, nil}
  defp loaded({:ok, {:error, reason}}), do: {:error, reason}
  defp loaded({:ok, other}), do: {:error, {:unexpected, other}}
  defp loaded({:exit, reason}), do: {:error, reason}

  @impl true
  def handle_event("go", %{"to" => to}, socket) do
    case place(to) do
      nil -> {:noreply, socket}
      place -> {:noreply, go(socket, place)}
    end
  end

  def handle_event("lens", %{"to" => lens}, socket) when lens in ~w(graph lifecycle map),
    do: {:noreply, assign(socket, lens: String.to_existing_atom(lens))}

  # The panel's "Open": where the selected card of the drawn picture leads.
  def handle_event("open", %{"id" => id}, socket) do
    with {:ok, document} <- Map.get(socket.assigns.documents, ref(socket)),
         {kind, node} <- node(document, id),
         {place, _words} <- Places.destination(document, kind, node) do
      {:noreply, go(socket, place)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp go(socket, place), do: socket |> assign(place: place, lens: :graph) |> load_place()

  # A place as the page sends it back: what `key/1` wrote.
  defp place("domain"), do: :domain
  defp place("processes"), do: :processes

  defp place(key) do
    case String.split(key, "\u001F") do
      ["contract", id] -> {:contract, id}
      ["process", id] -> {:process, id}
      ["unit", contract, unit] -> {:unit, contract, unit}
      _unknown -> nil
    end
  end

  # A place below the domain or the list as one value of an attribute; the separator is a
  # control character no id holds.
  defp key(place), do: place |> Tuple.to_list() |> Enum.map_join("\u001F", &to_string/1)

  defp ref(socket), do: Places.ref(socket.assigns.place, socket.assigns.domain)

  defp node(document, id) do
    Enum.find_value(document["nodes"] || %{}, fn {kind, nodes} ->
      with %{} = node <- Enum.find(nodes, &(&1["id"] == id)), do: {kind, node}
    end)
  end

  @impl true
  def render(assigns) do
    %{documents: documents, overlays: overlays, place: place, domain: domain} = assigns
    ref = Places.ref(place, domain)
    domain_document = ok(documents[Places.ref(:domain, domain)])

    assigns =
      assign(assigns,
        tab: Places.tab(place),
        state: documents[ref],
        document: ok(documents[ref]),
        overlay: overlays[ref],
        domain_document: domain_document,
        trail: trail(place, domain, domain_document, ok(documents[ref])),
        canvas: "#{assigns.id}-#{:erlang.phash2(place)}"
      )

    assigns = assign(assigns, picture: picture(assigns))

    ~H"""
    <div id={@id} class="ehg-explorer">
      <div class="ehg-tabs" role="tablist" aria-label="Viewpoint">
        <button
          :for={{tab, words, to} <- [{:structure, "Structure", "domain"}, {:processes, "Processes", "processes"}]}
          type="button"
          role="tab"
          aria-selected={to_string(@tab == tab)}
          class={["ehg-tab", @tab == tab && "is-current"]}
          phx-click="go"
          phx-value-to={to}
          phx-target={@myself}
        >
          {words}
        </button>
      </div>

      <nav class="ehg-path" aria-label="Where you are">
        <ol>
          <li :for={{words, to} <- @trail}>
            <button :if={to} type="button" phx-click="go" phx-value-to={to} phx-target={@myself}>
              {words}
            </button>
            <span :if={!to} aria-current="location">{words}</span>
          </li>
        </ol>
      </nav>

      <div :if={@picture && @picture.lenses != []} class="ehg-lenses" role="group" aria-label="Show as">
        <button
          :for={{lens, words} <- @picture.lenses}
          type="button"
          class={["ehg-tool", @lens == lens && "is-current"]}
          aria-pressed={to_string(@lens == lens)}
          phx-click="lens"
          phx-value-to={lens}
          phx-target={@myself}
        >
          {words}
        </button>
      </div>

      <p :if={@state in [nil, :loading]} class="ehg-note">Loading…</p>
      <p :if={match?({:error, _}, @state)} class="ehg-note ehg-failed">
        This picture could not be loaded.
      </p>

      <ul :if={@place == :processes and @domain_document} class="ehg-places">
        <li :for={process <- processes(@domain_document)}>
          <button type="button" phx-click="go" phx-value-to={process.to} phx-target={@myself}>
            <span class="ehg-label">{process.title}</span>
            <span class="ehg-name">{process.id}</span>
          </button>
        </li>
        <li :if={processes(@domain_document) == []} class="ehg-note">
          This domain declares no process module.
        </li>
      </ul>

      <.live_component
        :if={@picture}
        module={Canvas}
        id={@canvas}
        document={@document}
        overlay={@picture.overlay && @overlay}
        view={@picture.view}
        open={@myself}
      />

      <Actors.table :if={@place == :domain and @document} document={@document} canvas={@canvas} />
    </div>
    """
  end

  defp ok({:ok, document}), do: document
  defp ok(_other), do: nil

  # What the canvas draws at the place, through which lens, and whether the log's numbers
  # go over it; nil where nothing is drawn yet, or on the list of processes.
  defp picture(%{place: :processes}), do: nil
  defp picture(%{document: nil}), do: nil

  defp picture(%{place: :domain, lens: lens, document: document}) do
    if List.keymember?(View.views(document), :system, 0) do
      map? = lens == :map

      %{
        view: if(map?, do: :context_map, else: :system),
        overlay: not map?,
        lenses: [{:graph, "Contracts"}, {:map, "Contexts and their relations"}]
      }
    else
      %{view: :context_map, overlay: false, lenses: []}
    end
  end

  defp picture(%{place: {:contract, _id}}), do: %{view: :contract, overlay: true, lenses: []}

  defp picture(%{place: {:unit, _contract, unit}, lens: lens, document: document}) do
    if List.keymember?(View.views(document), {:lifecycle, unit}, 0) do
      lifecycle? = lens == :lifecycle

      %{
        view: if(lifecycle?, do: {:lifecycle, unit}, else: {:unit, unit}),
        overlay: lifecycle?,
        lenses: [{:graph, "Commands and events"}, {:lifecycle, "Lifecycle"}]
      }
    else
      %{view: {:unit, unit}, overlay: false, lenses: []}
    end
  end

  defp picture(%{place: {:process, _id}}), do: %{view: :process, overlay: true, lenses: []}

  # The path from the domain to the place, each step a button back to it but the last.
  defp trail(place, domain, domain_document, document) do
    root = (domain_document && domain_document["name"]) || domain

    steps =
      case place do
        :domain ->
          [{root, nil}]

        :processes ->
          [{root, "domain"}, {"Processes", nil}]

        {:contract, id} ->
          [{root, "domain"}, {id, nil}]

        {:unit, c, u} ->
          [{root, "domain"}, {c, key({:contract, c})}, {unit_name(document, u), nil}]

        {:process, id} ->
          [{root, "domain"}, {"Processes", "processes"}, {id, nil}]
      end

    steps
  end

  defp unit_name(nil, unit), do: unit

  defp unit_name(document, unit) do
    case Enum.find(get_in(document, ["nodes", "unit"]) || [], &(&1["id"] == unit)) do
      %{"name" => name} -> name
      nil -> unit
    end
  end

  defp processes(document) do
    for p <- get_in(document, ["nodes", "process"]) || [] do
      %{id: p["name"], title: p["label"] || p["name"], to: key({:process, p["name"]})}
    end
  end
end
