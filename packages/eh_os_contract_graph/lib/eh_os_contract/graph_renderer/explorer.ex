defmodule EhOsContract.GraphRenderer.Explorer do
  # Plan DD, stage G1 (#297): one canvas with two viewpoints, the user's decisions of
  # 15 October — the renderer holds the navigation, so any host draws what the dashboard
  # draws, and a host gives it a loader the explorer calls in the background. The EHOS
  # Console draws the landscape from the domain documents of each deployment, and opens a
  # deployment's domain from it here, at the contract the reader chose (#404).
  @moduledoc """
  An application's contracts as one canvas the reader moves through: the component a host
  renders to show a domain's graph, with its documents from a loader
  (`EhOsContract.GraphRenderer.Loader`).

      <.live_component
        module={EhOsContract.GraphRenderer.Explorer}
        id="graph"
        domain="Lending.Domain"
        loader={MyAppWeb.GraphLoader}
      />

  `domain` names the domain as its documents do, by its module; `loader` is a module, or
  `{module, opts}` to hand the loader `opts`.

  **Who reads it** is the host's to say, not a switch of the reader's: every card
  leads with the client's label and keeps its name in code small under it, for engineer
  and owner alike, unless the host draws it for the owner alone, `audience={:owner}` —
  each declaration by its label, with the numbers from the log, and nothing of the
  engineering (`EhOsContract.GraphRenderer.Canvas`, its `audience`). `:engineering` when it
  is left out:

      <.live_component
        module={EhOsContract.GraphRenderer.Explorer}
        id="graph"
        domain="Lending.Domain"
        loader={MyAppWeb.GraphLoader}
        audience={:owner}
      />

  `audience` is read when the explorer starts, so a host rendering it again with another
  does not change it, and anything but `:engineering` or `:owner` raises an
  `ArgumentError`.

  **Where it starts** is `at`: the domain's system, `:domain`, when it is left out; a
  contract by its id, `{:contract, "lending.circulation"}`; a process module by its id,
  `{:process, "fulfilment.order"}`; or the list of process modules, `:processes`. A host
  that opens the explorer from a contract drawn elsewhere, say the landscape's
  (`EhOsContract.GraphRenderer.Canvas`, its `link`), starts it there:

      <.live_component
        module={EhOsContract.GraphRenderer.Explorer}
        id="graph"
        domain="Lending.Domain"
        loader={MyAppWeb.GraphLoader}
        at={{:contract, "lending.circulation"}}
      />

  The explorer goes there once the domain's document has arrived and names it, and the
  path leads back up from it. A contract or a process module the domain's document does
  not name, and anything else given as `at`, starts at the domain: never a crash, and
  nothing loaded that the domain does not name. Like `audience`, `at` is read when the
  explorer starts; a host rendering it again with another does not move the reader.

  **The path** is the one way through: from the domain down, each step a way back up
  ("Lending.Domain › lending.circulation › loan"), along two branches:

  - **the structure:** the domain's system — its contracts in their contexts, what one
    consumes from another, the drift's numbers on each — or its context map; a contract's
    full graph; one of its units, or its lifecycle when it declares one;
  - **the processes**, a step beside the domain ("Lending.Domain › Processes"): the domain's
    process modules, and one's picture — its stages, the events in them and its promises.

  **Each place says what it shows**, in a line under the path. Where it can be drawn two
  ways — the domain's contracts or its contexts and their relations, a unit's commands and
  events or its lifecycle — both are offered there, and the line says what the chosen one
  shows.

  Each picture is an `EhOsContract.GraphRenderer.Canvas`, with its search, focus and
  panel. **The panel opens where a card leads:** a contract or a process of the map, a
  unit of a contract, and an event's unit or contract — from a process's event to the
  contract that declares it, from one branch to the other.

  **Documents load in the background**, each the first time the reader enters a picture
  of it, and its overlay only where the picture draws the log's numbers: the picture is
  drawn declared as soon as its document arrives, and the numbers follow. One that fails
  to load says so in place of the picture, and is loaded again when the reader comes
  back to it. A place the domain's documents do not hold is never loaded, and an event
  the page could not have sent is ignored.
  """

  use Phoenix.LiveComponent

  alias EhOsContract.GraphRenderer.{Actors, Audience, Canvas, Places, View}

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

  # `audience` is the host's, read when the explorer starts; the reader has no switch of it (#490).
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.take(assigns, [:id, :domain]))
      |> assign(:loader, loader(Map.fetch!(assigns, :loader)))
      |> assign_new(:audience, fn -> Audience.cast(Map.get(assigns, :audience, :engineering)) end)
      |> assign_new(:start, fn -> start(Map.get(assigns, :at)) end)

    {:ok, socket |> load(Places.ref(:domain, socket.assigns.domain)) |> enter() |> started()}
  end

  # Where the host asked the explorer to start, as a place; the domain for anything else.
  # Below the domain it waits for the domain's document, which says whether it holds it.
  defp start({kind, id}) when kind in [:contract, :process] and is_binary(id), do: {kind, id}
  defp start(:processes), do: :processes
  defp start(_domain_or_unknown), do: nil

  # Goes where the explorer was asked to start, once the domain's document says whether it
  # is there; a place it does not hold, or a document that failed, leaves the reader at the
  # domain.
  defp started(%{assigns: %{start: nil}} = socket), do: socket

  defp started(socket) do
    case socket.assigns.documents[Places.ref(:domain, socket.assigns.domain)] do
      {:ok, _document} -> socket |> assign(start: nil) |> go(socket.assigns.start)
      {:error, _reason} -> assign(socket, start: nil)
      _loading -> socket
    end
  end

  defp loader({module, opts}) when is_atom(module), do: {module, opts}
  defp loader(module) when is_atom(module), do: {module, []}

  # The documents and the overlay the place is drawn from: the domain's document, which
  # names what there is, and the place's own; its overlay only where its picture draws
  # one. Each is loaded once, and again on coming back to it after it failed.
  defp enter(socket), do: socket |> load(ref(socket)) |> logged()

  # The place's overlay, where its picture, now known, draws one.
  defp logged(socket) do
    socket = derive(socket)

    if socket.assigns.picture && socket.assigns.picture.overlay,
      do: socket |> overlay(ref(socket)) |> derive(),
      else: socket
  end

  defp load(socket, ref) do
    case socket.assigns.documents[ref] do
      known when known == :loading or elem(known, 0) == :ok ->
        socket

      _missing_or_failed ->
        {module, opts} = socket.assigns.loader

        socket
        |> assign(documents: Map.put(socket.assigns.documents, ref, :loading))
        |> start_async({:document, ref}, fn -> module.document(ref, opts) end)
    end
  end

  defp overlay(socket, ref) do
    if Map.has_key?(socket.assigns.overlays, ref) and socket.assigns.overlays[ref] != :failed do
      socket
    else
      {module, opts} = socket.assigns.loader

      socket
      |> assign(overlays: Map.put(socket.assigns.overlays, ref, :loading))
      |> start_async({:overlay, ref}, fn -> module.overlay(ref, opts) end)
    end
  end

  @impl true
  def handle_async({:document, ref}, result, socket) do
    socket = assign(socket, documents: Map.put(socket.assigns.documents, ref, document(result)))

    # The place's own document arrived: what it draws decides whether its log is wanted. A
    # failure is retried only when the reader comes back to it. The domain's says whether
    # the place the explorer was asked to start at is there, before the domain's own log is
    # asked for a picture the reader would not see.
    socket = started(socket)
    if ref == ref(socket), do: {:noreply, logged(socket)}, else: {:noreply, derive(socket)}
  end

  def handle_async({:overlay, ref}, result, socket) do
    overlay =
      case result do
        {:ok, {:ok, overlay}} when is_map(overlay) or is_nil(overlay) -> overlay
        _failed -> :failed
      end

    {:noreply,
     socket |> assign(overlays: Map.put(socket.assigns.overlays, ref, overlay)) |> derive()}
  end

  # What a loader answered, or what became of a loader that raised or exited: a picture it
  # could not load, never a crash of the host's page. A document of nothing is one too.
  defp document({:ok, {:ok, %{} = document}}), do: {:ok, document}
  defp document({:ok, {:error, reason}}), do: {:error, reason}
  defp document({:ok, other}), do: {:error, {:unexpected, other}}
  defp document({:exit, reason}), do: {:error, reason}

  @impl true
  def handle_event("go", %{"to" => to}, socket) when is_binary(to) do
    case place(to) do
      nil -> {:noreply, socket}
      place -> {:noreply, socket |> go(place) |> moved(socket)}
    end
  end

  def handle_event("lens", %{"to" => lens}, socket) when lens in ~w(graph lifecycle map),
    do:
      {:noreply,
       socket |> assign(lens: String.to_existing_atom(lens)) |> enter() |> moved(socket)}

  # The panel's "Open": where the selected card of the drawn picture leads.
  def handle_event("open", %{"id" => id}, socket) when is_binary(id) do
    with document when document != nil <- socket.assigns.document,
         {kind, node} <- node(document, id),
         {place, _words} <- Places.destination(document, kind, node) do
      {:noreply, socket |> go(place) |> moved(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # An event the page does not send — another name, or without what it needs — is ignored
  # rather than crashing the host's page.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The reader moved before the domain's document arrived — to another place, or another
  # lens on it: where they went wins over where the host asked the explorer to start. A
  # click that left them where they were does not.
  defp moved(socket, before) do
    if {socket.assigns.place, socket.assigns.lens} == {before.assigns.place, before.assigns.lens},
      do: socket,
      else: assign(socket, start: nil)
  end

  # A place the domain holds, and nothing else: a contract or a process module its document
  # names, a unit of a contract already drawn. Anything a page could not have offered is
  # never loaded.
  defp go(socket, place) do
    if holds?(socket, place),
      do: socket |> assign(place: place, lens: :graph) |> enter(),
      else: socket
  end

  defp holds?(_socket, place) when place in [:domain, :processes], do: true

  defp holds?(socket, {:unit, contract, unit}) do
    case socket.assigns.documents[{:contract, contract}] do
      {:ok, document} -> Enum.any?(get_in(document, ["nodes", "unit"]) || [], &(&1["id"] == unit))
      _other -> false
    end
  end

  defp holds?(socket, {kind, id}) when kind in [:contract, :process] do
    case socket.assigns.documents[Places.ref(:domain, socket.assigns.domain)] do
      {:ok, document} ->
        Enum.any?(get_in(document, ["nodes", to_string(kind)]) || [], &(&1["name"] == id))

      _other ->
        false
    end
  end

  # Anything else a card could lead to — out of a landscape, say — is no place of a domain.
  defp holds?(_socket, _place), do: false

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

  # What the page shows, worked out when the state changes rather than at every render, so
  # that a render with the same picture sends the canvas nothing new.
  defp derive(socket) do
    %{documents: documents, overlays: overlays, place: place, domain: domain} = socket.assigns
    ref = Places.ref(place, domain)
    domain_document = ok(documents[Places.ref(:domain, domain)])
    document = ok(documents[ref])

    # What the explorer writes itself — the path, the list of processes, the actors — is
    # read as the reader reads the canvas.
    read = &Audience.read(&1, socket.assigns.audience)

    socket =
      assign(socket,
        state: documents[ref],
        document: document,
        domain_document: domain_document,
        read: read.(document),
        trail: trail(place, domain, read.(domain_document), document, socket.assigns.audience),
        canvas: "#{socket.assigns.id}-#{:erlang.phash2(place)}",
        open: %{target: socket.assigns.myself, here: place}
      )

    picture = picture(socket.assigns)
    overlay = overlays[ref]

    assign(socket,
      picture: picture,
      overlay: if(picture && picture.overlay && is_map(overlay), do: overlay),
      about: about(place, picture, socket.assigns.lens)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ehg-explorer">
      <%!-- #490: the path is the one way through: from the domain down to a contract and a
      unit, and along its other branch to the processes and one of them. --%>
      <nav class="ehg-path" aria-label="Where you are">
        <ol>
          <li :for={{words, to} <- @trail}>
            <button :if={to} type="button" phx-click="go" phx-value-to={to} phx-target={@myself}>
              {words}
            </button>
            <span :if={!to} aria-current="location">{words}</span>
          </li>
        </ol>
        <button
          :if={@place == :domain and @domain_document && processes(@domain_document) != []}
          type="button"
          class="ehg-branch"
          phx-click="go"
          phx-value-to="processes"
          phx-target={@myself}
        >
          Processes ›
        </button>
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

      <%!-- What the place shows, or the way of drawing it the reader chose (#490). --%>
      <p :if={@about} class="ehg-about">{@about}</p>

      <p :if={@state in [nil, :loading]} class="ehg-note">Loading…</p>
      <p :if={match?({:error, _}, @state)} class="ehg-note ehg-failed">
        This picture could not be loaded.
      </p>

      <ul :if={@place == :processes and @domain_document} class="ehg-places">
        <li :for={process <- processes(@domain_document)}>
          <button type="button" phx-click="go" phx-value-to={process.to} phx-target={@myself}>
            <span class="ehg-label">{process.title}</span>
            <span :if={Audience.code?(@audience) or process.title == process.id} class="ehg-name">
              {process.id}
            </span>
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
        overlay={@overlay}
        view={@picture.view}
        open={@open}
        audience={@audience}
      />

      <Actors.table
        :if={@place == :domain and @read}
        document={@read}
        canvas={@canvas}
        audience={@audience}
      />
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

  # What a place shows, in a line under the path (#490): where it can be drawn two ways, what
  # the way the reader chose shows; otherwise what the place itself does.
  defp about(_place, %{lenses: [_ | _] = lenses}, lens) do
    Map.fetch!(
      %{
        graph: about_graph(lenses),
        map:
          "The domain's areas of language, its bounded contexts, and how each depends on the " <>
            "others: who supplies, who conforms, who translates.",
        lifecycle: "The statuses the unit moves through, and the events that move it."
      },
      if(List.keymember?(lenses, lens, 0), do: lens, else: :graph)
    )
  end

  defp about(:domain, _picture, _lens),
    do:
      "The domain's areas of language, its bounded contexts, and how each depends on the others."

  defp about(:processes, _picture, _lens),
    do:
      "How work runs over time here: each process's stages, the events that move it, and what " <>
        "it promises to finish by."

  defp about({:contract, _id}, _picture, _lens),
    do:
      "One part of the business: the units that decide in it, the commands they take, the " <>
        "events they record, and what reacts to them."

  defp about({:process, _id}, _picture, _lens),
    do:
      "One process: its stages in order, the events each includes and the contracts that " <>
        "record them, and what it promises."

  defp about(_place, _picture, _lens), do: nil

  # The first way of drawing a place with two: the domain's contracts, or a unit's commands.
  defp about_graph([{:graph, "Contracts"} | _]),
    do:
      "Which contracts there are, in which context each sits, and what one takes from " <>
        "another."

  defp about_graph(_unit),
    do: "What the unit takes, what it records, and the rules that may refuse a command."

  # The path from the domain to the place, each step a button back to it but the last: by
  # its name in code, or for the owner by its label (`step/3`).
  defp trail(place, domain, domain_document, document, audience) do
    root = (domain_document && domain_document["name"]) || domain
    named = &step(audience, find(&1, &2, &3), &3)

    case place do
      :domain ->
        [{root, nil}]

      :processes ->
        [{root, "domain"}, {"Processes", nil}]

      {:contract, id} ->
        [{root, "domain"}, {named.(domain_document, "contract", id), nil}]

      {:unit, c, u} ->
        [
          {root, "domain"},
          {named.(domain_document, "contract", c), key({:contract, c})},
          {unit_name(document, u, audience), nil}
        ]

      {:process, id} ->
        [
          {root, "domain"},
          {"Processes", "processes"},
          {named.(domain_document, "process", id), nil}
        ]
    end
  end

  defp unit_name(document, unit, audience) do
    case Enum.find(get_in(document || %{}, ["nodes", "unit"]) || [], &(&1["id"] == unit)) do
      %{"name" => name} = node -> step(audience, node, name)
      nil -> unit
    end
  end

  # The node of `kind` a domain's document names `name`.
  defp find(document, kind, name),
    do: Enum.find(get_in(document || %{}, ["nodes", kind]) || [], &(&1["name"] == name))

  defp step(audience, node, name) do
    if Audience.code?(audience) or node == nil, do: name, else: node["label"] || name
  end

  defp processes(document) do
    for p <- get_in(document, ["nodes", "process"]) || [] do
      %{id: p["name"], title: p["label"] || p["name"], to: key({:process, p["name"]})}
    end
  end
end
