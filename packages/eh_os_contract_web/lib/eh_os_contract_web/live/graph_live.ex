defmodule EhOsContract.Web.Live.Graph do
  # The second screen: the Mermaid diagrams `mix eh_os_contract.graph` draws, live in the
  # dashboard instead of dev-only CLI output — the second half of a plan
  # `packages/eh_os_contract/lib/mix/tasks/eh_os_contract.graph.ex`'s own moduledoc called
  # out from the start ("this is the seed of the dashboard"). See PLAN.md, "23 sierpnia
  # (10)" for why this was parked, then unparked. From the top: each domain's context
  # map and system, then the selected contract's panels, then its units.
  #
  # The selector picks a contract, by its id, whether or not it has a process (plan DD,
  # P1b, #186; until then it picked a process, and a contract without one could not be
  # reached). Its panels, per ADR §9 ("navigation is per-process, never global"; the
  # domain's pictures above them are a dated exception there):
  #
  #   * **Declared shape of its process**, only when it has one —
  #     `EhOsContract.Graph.declared_to_mermaid/2`. The structural view: stages,
  #     endings, promise windows — true even for a process with zero runs.
  #   * **Declared versus observed** — the contract's full graph with the log laid
  #     over it (`EhOsContract.Graph.contract_to_mermaid/2`, v2 plan E7c, plan EG1):
  #     the steps, and the actors, read models, queries and external systems around
  #     them.
  #
  # **Above both, each domain** (plan EG2): its context map —
  # `EhOsContract.Graph.context_map_to_mermaid/1`, subdomains, contexts, externals and
  # their relations — and its system, the v2 contracts in their contexts, what one
  # consumes from another, and the log over it (`EhOsContract.Graph.system_to_mermaid/3`).
  # **Below both, the units** of the selected contract, each its own
  # picture (`EhOsContract.Graph.unit_to_mermaid/2`): state, commands, events,
  # invariants and the scenarios that pin each path. The map and the units describe
  # the model rather than the log; they are here since 28 September at the user's
  # word, beside the pages `mix eh_os_contract.pages` writes (plan, "Przed EG"). An
  # aggregate that declares a lifecycle has it drawn beside its unit
  # (`EhOsContract.Graph.lifecycle_to_mermaid/3`, plan LC4b), with the log over it once
  # the socket is connected — the report's own counts, read once per contract.
  #
  # Rendering is client-side, through `app.js`'s `MermaidRender` hook: every
  # diagram strings reach the template as plain data in a `data-graph`
  # attribute, never as trusted HTML — HEEx escapes them like any other
  # interpolated value, and the hook reads the attribute back out before
  # handing it to Mermaid.
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    # Plan DD, P1b (#186): every contract, by its id, whether or not it has a process.
    contracts =
      for(
        contract <- EhOsContract.Registry.contracts(),
        model = EhOsContract.Model.fetch(contract),
        do: %{contract: contract, id: model.id, process: EhOsContract.Model.process(model)}
      )
      |> Enum.sort_by(& &1.id)

    # Every registered domain has a map; one with a v2 contract has a system too.
    by_domain =
      Enum.group_by(EhOsContract.Registry.contracts(), &EhOsContract.Model.fetch(&1).domain)

    domains =
      for domain <- EhOsContract.Registry.domains() do
        contracts = Map.get(by_domain, domain, [])

        %{
          name: EhOsContract.Model.fetch(domain).name,
          map: EhOsContract.Graph.context_map_to_mermaid(domain),
          system:
            contracts != [] &&
              EhOsContract.Graph.system_to_mermaid(domain, contracts, overlay: true)
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
    assign(socket, selected: nil, declared_mermaid: nil, overlay_mermaid: nil, units: [])
  end

  defp select_contract(socket, selected) do
    model = EhOsContract.Model.fetch(selected.contract)

    # The log under the lifecycles is read once per contract, and only once the socket
    # is connected: the first, static render draws them declared, and the mount that
    # follows lays the log over them (plan LC4b).
    lifecycles =
      if connected?(socket) and Enum.any?(model.units, &Map.get(&1, :lifecycle)),
        do: EhOsContract.Conformance.lifecycles(model, [])

    units =
      for unit <- model.units do
        %{
          name: unit.name,
          label: unit.label,
          kind: unit.kind,
          mermaid: EhOsContract.Graph.unit_to_mermaid(selected.contract, unit.name),
          lifecycle: lifecycle(selected.contract, unit, lifecycles)
        }
      end

    # A process's declared shape only where the contract has one.
    declared =
      selected.process &&
        EhOsContract.Graph.declared_to_mermaid(selected.contract, selected.process.name)

    assign(socket,
      selected: selected.id,
      declared_mermaid: declared,
      overlay_mermaid: EhOsContract.Graph.contract_to_mermaid(selected.contract, overlay: true),
      units: units
    )
  end

  defp lifecycle(contract, unit, lifecycles) do
    cond do
      Map.get(unit, :lifecycle) == nil ->
        nil

      lifecycles == nil ->
        EhOsContract.Graph.lifecycle_to_mermaid(contract, unit.name)

      true ->
        EhOsContract.Graph.lifecycle_to_mermaid(contract, unit.name,
          overlay: true,
          lifecycles: lifecycles
        )
    end
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
          <pre
            class="mermaid"
            phx-hook="MermaidRender"
          phx-update="ignore"
            id={"map-graph-#{domain.name}"}
            data-graph={domain.map}
          ></pre>
        </section>

        <section :if={domain.system}>
          <h3>The system, declared versus observed — domain {domain.name}</h3>
          <pre
            class="mermaid"
            phx-hook="MermaidRender"
          phx-update="ignore"
            id={"system-graph-#{domain.name}"}
            data-graph={domain.system}
          ></pre>
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

      <section :if={@declared_mermaid}>
        <h3>Declared shape of its process</h3>

        <pre
          class="mermaid"
          phx-hook="MermaidRender"
          phx-update="ignore"
          id="declared-graph"
          data-graph={@declared_mermaid}
        ></pre>
      </section>

      <section :if={@overlay_mermaid}>
        <h3>Declared versus observed, this contract</h3>
        <pre
          class="mermaid"
          phx-hook="MermaidRender"
          phx-update="ignore"
          id="overlay-graph"
          data-graph={@overlay_mermaid}
        ></pre>
      </section>

      <section :for={unit <- @units}>
        <h3>{unit.kind} {unit.name} — {unit.label}</h3>
        <pre
          class="mermaid"
          phx-hook="MermaidRender"
          phx-update="ignore"
          id={"unit-graph-#{unit.name}"}
          data-graph={unit.mermaid}
        ></pre>

        <div :if={unit.lifecycle}>
          <h4>Lifecycle, declared versus observed</h4>
          <pre
            class="mermaid"
            phx-hook="MermaidRender"
            phx-update="ignore"
            id={"lifecycle-graph-#{unit.name}"}
            data-graph={unit.lifecycle}
          ></pre>
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
