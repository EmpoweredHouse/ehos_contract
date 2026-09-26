defmodule EhOsContract.Web.Live.Graph do
  @moduledoc """
  Screen 3: the two Mermaid diagrams `mix eh_os_contract.graph` could already draw, now
  live in the dashboard instead of dev-only CLI output — the second half of
  a plan `packages/eh_os_contract/lib/mix/tasks/eh_os_contract.graph.ex`'s own moduledoc
  called out from the start ("this is the seed of the dashboard"). See
  PLAN.md, "23 sierpnia (10)" for why this was parked, then unparked.

  Two panels, asymmetric on purpose, per ADR §9 ("navigation is per-process,
  never global"):

    * **Declared shape** — `EhOsContract.Graph.declared_to_mermaid/2`, scoped to
      whichever process the selector picks. The structural view: stages,
      endings, `trace` windows — true even for a contract with zero runs.
    * **Declared versus observed** — `EhOsContract.Graph.overlay/1` +
      `EhOsContract.Graph.to_mermaid/2`, every contract at once. This one stays
      global: `to_mermaid/2` always derives its node set from the full
      static graph regardless of which edges are passed in, so filtering
      the overlay list first would drop edges without dropping nodes,
      leaving orphaned boxes rather than a scoped picture. Narrowing that is
      engine work, not something this screen should paper over.

  **A v2 contract's process** (v2 plan, E7c) is drawn as its steps in both panels —
  `EhOsContract.Graph.steps_to_mermaid/2`, declared and with the log laid over it —
  since a v2 contract is one process and its overlay is that process's alone.

  Rendering is client-side, through `app.js`'s `MermaidRender` hook: both
  diagram strings reach the template as plain data in a `data-graph`
  attribute, never as trusted HTML — HEEx escapes them like any other
  interpolated value, and the hook reads the attribute back out before
  handing it to Mermaid.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    v1 =
      for contract <- EhOsContract.Registry.contracts(),
          process <- EhOsContract.Model.processes(contract) do
        %{contract: contract, name: process.name, label: process.label, v2: false}
      end

    v2 =
      for contract <- EhOsContract.Registry.v2_contracts(),
          %{process: %{} = process} <- [EhOsContract.Model.fetch(contract)] do
        %{contract: contract, name: process.name, label: process.label, v2: true}
      end

    processes = Enum.sort_by(v1 ++ v2, & &1.label)

    socket =
      socket
      |> assign(:processes, processes)
      |> assign(:every_contract, EhOsContract.Graph.overlay() |> EhOsContract.Graph.to_mermaid())
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
    assign(socket,
      selected: nil,
      declared_mermaid: nil,
      overlay_mermaid: socket.assigns.every_contract,
      overlay_heading: nil
    )
  end

  defp select_process(socket, %{v2: true} = process) do
    assign(socket,
      selected: key(process),
      declared_mermaid: EhOsContract.Graph.steps_to_mermaid(process.contract),
      overlay_mermaid: EhOsContract.Graph.steps_to_mermaid(process.contract, overlay: true),
      overlay_heading: "Declared versus observed, this process"
    )
  end

  defp select_process(socket, process) do
    mermaid = EhOsContract.Graph.declared_to_mermaid(process.contract, process.name)

    assign(socket,
      selected: key(process),
      declared_mermaid: mermaid,
      overlay_mermaid: socket.assigns.every_contract,
      overlay_heading: nil
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:graph} />
      <p class="access-badge">Access: {access_label(@eh_os_contract_web_access)}</p>

      <section>
        <h3>Declared shape</h3>

        <form :if={@processes != []} phx-change="select_process">
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
          id="declared-graph"
          data-graph={@declared_mermaid}
        ></pre>
      </section>

      <section>
        <h3>{assigns[:overlay_heading] || "Declared versus observed, every contract"}</h3>
        <pre
          class="mermaid"
          phx-hook="MermaidRender"
          id="overlay-graph"
          data-graph={@overlay_mermaid}
        ></pre>
      </section>
    </div>
    """
  end

  # A process by its contract and its name: two contracts may name their processes
  # alike — a v2 port beside its v1 original — and each has to be reachable.
  @spec key(map()) :: String.t()
  defp key(process), do: "#{inspect(process.contract)}:#{process.name}"

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end
