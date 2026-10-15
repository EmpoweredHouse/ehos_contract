defmodule EhOsContract.Web.Live.Graph do
  # The second screen: the pictures of the contract model, live in the dashboard. See
  # PLAN.md, "23 sierpnia (10)" for why this was parked, then unparked. From the top:
  # each domain's context map and system, then the selected contract's pictures and its
  # units, or the selected process module's.
  #
  # **Drawn by `eh_os_contract_graph`** (plan E13b, batch 4): each picture is a view of
  # the engine's `graph.v1` document (`EhOsContract.Graph.Document`), the one the API
  # serves, drawn by `EhOsContract.GraphRenderer.Canvas`, with what the log says
  # (`EhOsContract.Graph.Overlay`) over the full graph, a lifecycle and the system. The
  # views are the pictures this screen drew before the renderer, the user's decision of
  # 8 October (`EhOsContract.GraphRenderer.View`). The log is read
  # once the socket is connected, once per document: the first, static render draws
  # the pictures declared, and the mount that follows lays the log over them. A click
  # on a card or an arrow opens the renderer's panel (`EhOsContract.GraphRenderer.Panel`).
  #
  # The selector picks a contract or a process module, each by its id, in two groups
  # (plan DD, P1b, #186, for contracts; P2e, #220, for process modules), a value naming
  # its kind too, since a process module may share its id with a contract. A contract's
  # picture is **declared versus observed** — its full graph with the log laid over it
  # (v2 plan E7c, plan EG1): the steps, and the actors, read models, queries and external
  # systems around them. A process module's is its stages, the events each includes and
  # its promises, with its runs, each event's occurrences and each promise's verdicts
  # over them (the renderer's `:process` view). A contract declares no process (plan DD,
  # P2h, #221).
  #
  # **Above it, each domain** (plan EG2): its context map — subdomains, contexts,
  # externals and their relations — with its actors under it, people and systems apart,
  # a row opening the actor's panel; and, where it has a v2 contract, its system: the
  # contracts in their contexts, what one consumes from another, its process modules
  # with the contracts each includes, and the log over it.
  # **Below it, the units** of the selected contract, each its own picture: state,
  # commands, events, invariants and the scenarios that pin each path. The map and the
  # units describe the model rather than the log; they are here since 28 September at
  # the user's word, beside the pages `mix eh_os_contract.pages` writes (plan, "Przed
  # EG"). An aggregate that declares a lifecycle has it drawn beside its unit (plan
  # LC4b), with the log over it.
  @moduledoc false

  use Phoenix.LiveView

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.{Actors, Canvas, View}

  @impl true
  def mount(_params, _session, socket) do
    registered = EhOsContract.Registry.contracts()
    processes = EhOsContract.Registry.processes()

    # Plan DD, P1b (#186) and P2e (#220): every contract and every process module, by id.
    pickable =
      Enum.sort_by(for(c <- registered, do: pickable(:contract, c)), & &1.id) ++
        Enum.sort_by(for(p <- processes, do: pickable(:process, p)), & &1.id)

    # The domain's document and overlay are the ones the API serves, with the process
    # modules beside the contracts (plan DD, P2e, #220), so one digest names them.
    modules = registered ++ processes

    # Every registered domain has a map; one with a v2 contract has a system too.
    domains =
      for domain <- EhOsContract.Registry.domains() do
        document = Document.domain(domain, modules)

        %{
          name: document["name"],
          document: document,
          system?: List.keymember?(View.views(document), :system, 0),
          overlay: if(connected?(socket), do: Overlay.domain(domain, modules))
        }
      end

    socket =
      socket
      |> assign(:domains, domains)
      |> assign(:pickable, pickable)
      |> select(List.first(pickable))

    {:ok, socket}
  end

  # What the selector lists: its kind, its id and the value its option has.
  defp pickable(kind, module) do
    id = EhOsContract.Model.fetch(module).id
    %{kind: kind, module: module, id: id, value: "#{kind}:#{id}"}
  end

  @impl true
  def handle_event("select", %{"selected" => value}, socket) do
    # A value the page did not list keeps what is selected rather than blanking it.
    case Enum.find(socket.assigns.pickable, &(&1.value == value)) do
      nil -> {:noreply, socket}
      selected -> {:noreply, select(socket, selected)}
    end
  end

  # An event the page does not send — another name, or without `selected` — is ignored
  # rather than crashing the viewer's page.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @spec select(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  defp select(socket, nil) do
    assign(socket, selected: nil, kind: nil, document: nil, overlay: nil, units: [])
  end

  defp select(socket, %{kind: :process} = selected) do
    assign(socket,
      selected: selected.value,
      kind: :process,
      document: Document.process(selected.module),
      overlay: if(connected?(socket), do: Overlay.process(selected.module)),
      units: []
    )
  end

  defp select(socket, selected) do
    document = Document.contract(selected.module)
    views = View.views(document)

    # Each unit by its id in the document, which is also its canvas's: another contract's
    # unit of the same name is another canvas.
    units =
      for {{:unit, id}, title} <- views,
          do: %{id: id, title: title, lifecycle?: List.keymember?(views, {:lifecycle, id}, 0)}

    assign(socket,
      selected: selected.value,
      kind: :contract,
      document: document,
      overlay: if(connected?(socket), do: Overlay.contract(selected.module)),
      units: units
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:graph} />
      <p class="access-badge">Access: {access_label(@eh_os_contract_web_access)}</p>

      <%= for domain <- @domains do %>
        <section>
          <h3>Context map — domain {domain.name}</h3>
          <.live_component
            module={Canvas}
            id={"map-graph-#{domain.name}"}
            document={domain.document}
            view={:context_map}
          />
          <Actors.table document={domain.document} canvas={"map-graph-#{domain.name}"} />
        </section>

        <section :if={domain.system?}>
          <h3>The system, declared versus observed — domain {domain.name}</h3>
          <.live_component
            module={Canvas}
            id={"system-graph-#{domain.name}"}
            document={domain.document}
            overlay={domain.overlay}
            view={:system}
          />
        </section>
      <% end %>

      <section>
        <h3>Contract or process</h3>

        <form :if={@pickable != []} id="graph-select" phx-change="select">
          <select name="selected">
            <optgroup
              :for={{label, kind} <- [{"Contracts", :contract}, {"Processes", :process}]}
              :if={Enum.any?(@pickable, &(&1.kind == kind))}
              label={label}
            >
              <option
                :for={item <- Enum.filter(@pickable, &(&1.kind == kind))}
                value={item.value}
                selected={item.value == @selected}
              >
                {item.id}
              </option>
            </optgroup>
          </select>
        </form>

        <p :if={@pickable == []}>No contract or process module is registered.</p>
      </section>

      <section :if={@kind == :contract}>
        <h3>Declared versus observed, this contract</h3>
        <.live_component
          module={Canvas}
          id="overlay-graph"
          document={@document}
          overlay={@overlay}
          view={:contract}
        />
      </section>

      <section :if={@kind == :process}>
        <h3>Declared versus observed, this process</h3>
        <.live_component
          module={Canvas}
          id="process-graph"
          document={@document}
          overlay={@overlay}
          view={:process}
        />
      </section>

      <section :for={unit <- @units}>
        <h3>{unit.title}</h3>
        <.live_component
          module={Canvas}
          id={"unit-graph-#{unit.id}"}
          document={@document}
          view={{:unit, unit.id}}
        />

        <div :if={unit.lifecycle?}>
          <h4>Lifecycle, declared versus observed</h4>
          <.live_component
            module={Canvas}
            id={"lifecycle-graph-#{unit.id}"}
            document={@document}
            overlay={@overlay}
            view={{:lifecycle, unit.id}}
          />
        </div>
      </section>
    </div>
    """
  end

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end
