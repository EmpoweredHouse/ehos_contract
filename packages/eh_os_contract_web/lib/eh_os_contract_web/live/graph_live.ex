defmodule EhOsContract.Web.Live.Graph do
  @moduledoc """
  Screen 3: the pictures of the contract model, live in the dashboard — the second
  half of a plan `packages/eh_os_contract/lib/mix/tasks/eh_os_contract.graph.ex`'s own
  moduledoc called out from the start ("this is the seed of the dashboard"). See
  PLAN.md, "23 sierpnia (10)" for why this was parked, then unparked. From the top: each
  domain's context map and system, then the selected contract's pictures, then its
  units.

  **Drawn by `eh_os_contract_graph`** (plan E13b, batch 4): each picture is a view of
  the engine's `graph.v1` document (`EhOsContract.Graph.Document`), the one the API
  serves, drawn by `EhOsContract.GraphRenderer.Canvas`, with what the log says
  (`EhOsContract.Graph.Overlay`) over the views the Mermaid diagrams laid it over: the
  full graph, a lifecycle and the system. The views are those diagrams' pictures, the
  user's decision of 8 October (`EhOsContract.GraphRenderer.View`). The log is read
  once the socket is connected, once per document: the first, static render draws
  the pictures declared, and the mount that follows lays the log over them. A click
  on a card or an arrow opens the renderer's panel (`EhOsContract.GraphRenderer.Panel`).

  The selector picks a contract, by its id, whether or not it has a process (plan DD,
  P1b, #186; until then it picked a process, and a contract without one could not be
  reached). Its pictures, per ADR §9 ("navigation is per-process, never global"; the
  domain's pictures above them are a dated exception there):

    * **Declared shape of its process**, only when it has one: the structural view —
      stages, endings, promise windows — true even for a process with zero runs.
    * **Declared versus observed** — the contract's full graph with the log laid over
      it (v2 plan E7c, plan EG1): the steps, and the actors, read models, queries and
      external systems around them.

  **Above both, each domain** (plan EG2): its context map — subdomains, contexts,
  externals and their relations — with its actors under it, people and systems apart,
  a row opening the actor's panel; and, where it has a v2 contract, its system: the
  contracts in their contexts, what one consumes from another, and the log over it.
  **Below both, the units** of the selected contract, each its own picture: state,
  commands, events, invariants and the scenarios that pin each path. The map and the
  units describe the model rather than the log; they are here since 28 September at
  the user's word, beside the pages `mix eh_os_contract.pages` writes (plan, "Przed
  EG"). An aggregate that declares a lifecycle has it drawn beside its unit (plan
  LC4b), with the log over it.
  """

  use Phoenix.LiveView

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.{Actors, Canvas, View}

  @impl true
  def mount(_params, _session, socket) do
    registered = EhOsContract.Registry.contracts()

    # Plan DD, P1b (#186): every contract, by its id, whether or not it has a process.
    contracts =
      for(
        contract <- registered,
        model = EhOsContract.Model.fetch(contract),
        do: %{contract: contract, id: model.id, process: EhOsContract.Model.process(model)}
      )
      |> Enum.sort_by(& &1.id)

    # Every registered domain has a map; one with a v2 contract has a system too.
    domains =
      for domain <- EhOsContract.Registry.domains() do
        document = Document.domain(domain, registered)

        %{
          name: document["name"],
          document: document,
          system?: List.keymember?(View.views(document), :system, 0),
          overlay: if(connected?(socket), do: Overlay.domain(domain, registered))
        }
      end

    socket =
      socket
      |> assign(:domains, domains)
      |> assign(:contracts, contracts)
      |> select_contract(List.first(contracts))

    {:ok, socket}
  end

  @impl true
  def handle_event("select_contract", %{"contract" => id}, socket) do
    # An id the page did not list keeps what is selected rather than blanking it.
    case Enum.find(socket.assigns.contracts, &(&1.id == id)) do
      nil -> {:noreply, socket}
      selected -> {:noreply, select_contract(socket, selected)}
    end
  end

  @spec select_contract(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  defp select_contract(socket, nil) do
    assign(socket, selected: nil, document: nil, overlay: nil, declared?: false, units: [])
  end

  defp select_contract(socket, selected) do
    document = Document.contract(selected.contract)
    views = View.views(document)

    # Each unit by its id in the document, which is also its canvas's: another contract's
    # unit of the same name is another canvas.
    units =
      for {{:unit, id}, title} <- views,
          do: %{id: id, title: title, lifecycle?: List.keymember?(views, {:lifecycle, id}, 0)}

    assign(socket,
      selected: selected.id,
      document: document,
      overlay: if(connected?(socket), do: Overlay.contract(selected.contract)),
      declared?: List.keymember?(views, :declared, 0),
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
        <h3>Contract</h3>

        <form :if={@contracts != []} id="contract-select" phx-change="select_contract">
          <select name="contract">
            <option
              :for={contract <- @contracts}
              value={contract.id}
              selected={contract.id == @selected}
            >
              {option_label(contract)}
            </option>
          </select>
        </form>

        <p :if={@contracts == []}>No contract is registered.</p>
      </section>

      <section :if={@declared?}>
        <h3>Declared shape of its process</h3>
        <.live_component module={Canvas} id="declared-graph" document={@document} view={:declared} />
      </section>

      <section :if={@document}>
        <h3>Declared versus observed, this contract</h3>
        <.live_component
          module={Canvas}
          id="overlay-graph"
          document={@document}
          overlay={@overlay}
          view={:contract}
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

  # A contract by its id, and its process's label where it has one.
  @spec option_label(map()) :: String.t()
  defp option_label(%{id: id, process: nil}), do: id
  defp option_label(%{id: id, process: process}), do: "#{id} — #{process.label}"

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end
