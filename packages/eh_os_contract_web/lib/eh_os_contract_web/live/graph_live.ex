defmodule EhOsContract.Web.Live.Graph do
  @moduledoc """
  Screen 3: the Mermaid diagrams `mix eh_os_contract.graph` draws, live in the
  dashboard instead of dev-only CLI output — the second half of a plan
  `packages/eh_os_contract/lib/mix/tasks/eh_os_contract.graph.ex`'s own moduledoc called
  out from the start ("this is the seed of the dashboard"). See PLAN.md, "23 sierpnia
  (10)" for why this was parked, then unparked. From the top: each domain's context
  map and system, then the selected process's two panels, then its contract's units.

  Both of the process's panels are scoped to whichever process the selector picks,
  per ADR §9 ("navigation is per-process, never global"; the domain's pictures above
  them are a dated exception there):

    * **Declared shape** — `EhOsContract.Graph.declared_to_mermaid/2`. The
      structural view: stages, endings, promise windows — true even for a contract
      with zero runs.
    * **Declared versus observed** — its contract's full graph with the log laid
      over it (`EhOsContract.Graph.contract_to_mermaid/2`, v2 plan E7c, plan EG1):
      the steps, and the actors, read models, queries and external systems around
      them. A contract is one process, so its overlay is that process's alone.

  **Above both, each domain** (plan EG2): its context map —
  `EhOsContract.Graph.context_map_to_mermaid/1`, subdomains, contexts, externals and
  their relations — and its system, the v2 contracts in their contexts, what one
  consumes from another, and the log over it (`EhOsContract.Graph.system_to_mermaid/3`).
  **Below both, the units** of the selected v2 process's contract, each its own
  picture (`EhOsContract.Graph.unit_to_mermaid/2`): state, commands, events,
  invariants and the scenarios that pin each path. The map and the units describe
  the model rather than the log; they are here since 28 September at the user's
  word, beside the pages `mix eh_os_contract.pages` writes (plan, "Przed EG").

  Rendering is client-side, through `app.js`'s `MermaidRender` hook: every
  diagram strings reach the template as plain data in a `data-graph`
  attribute, never as trusted HTML — HEEx escapes them like any other
  interpolated value, and the hook reads the attribute back out before
  handing it to Mermaid.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    processes =
      for(
        contract <- EhOsContract.Registry.contracts(),
        %{process: %{} = process} <- [EhOsContract.Model.fetch(contract)],
        do: %{contract: contract, name: process.name, label: process.label}
      )
      |> Enum.sort_by(& &1.label)

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
      |> assign(:processes, processes)
      |> select_process(List.first(processes))

    {:ok, socket}
  end

  @impl true
  def handle_event("select_process", %{"process" => key}, socket) do
    process = Enum.find(socket.assigns.processes, &(key(&1) == key))
    {:noreply, select_process(socket, process)}
  end

  @spec select_process(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  defp select_process(socket, nil) do
    assign(socket, selected: nil, declared_mermaid: nil, overlay_mermaid: nil, units: [])
  end

  defp select_process(socket, process) do
    units =
      for unit <- EhOsContract.Model.fetch(process.contract).units do
        %{
          name: unit.name,
          label: unit.label,
          kind: unit.kind,
          mermaid: EhOsContract.Graph.unit_to_mermaid(process.contract, unit.name)
        }
      end

    assign(socket,
      selected: key(process),
      declared_mermaid: EhOsContract.Graph.declared_to_mermaid(process.contract, process.name),
      overlay_mermaid: EhOsContract.Graph.contract_to_mermaid(process.contract, overlay: true),
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
        <h3>Declared shape</h3>

        <form :if={@processes != []} id="process-select" phx-change="select_process">
          <select name="process">
            <option
              :for={process <- @processes}
              value={key(process)}
              selected={key(process) == @selected}
            >
              {process.label}
            </option>
          </select>
        </form>

        <p :if={@processes == []}>No process is declared in any registered contract.</p>

        <pre
          :if={@declared_mermaid}
          class="mermaid"
          phx-hook="MermaidRender"
          phx-update="ignore"
          id="declared-graph"
          data-graph={@declared_mermaid}
        ></pre>
      </section>

      <section :if={@overlay_mermaid}>
        <h3>Declared versus observed, this process</h3>
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
      </section>
    </div>
    """
  end

  # A process by its contract and its name: two contracts may name their processes
  # alike, and each has to be reachable.
  @spec key(map()) :: String.t()
  defp key(process), do: "#{inspect(process.contract)}:#{process.name}"

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end
