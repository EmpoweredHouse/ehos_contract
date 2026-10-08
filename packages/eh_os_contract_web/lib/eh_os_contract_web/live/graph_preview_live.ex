defmodule EhOsContract.Web.Live.GraphPreview do
  @moduledoc """
  **Temporary** (plan E13b, batches 1 and 3): the renderer of `eh_os_contract_graph`
  drawing one view of one `graph.v1` document of the registry at a time, with its
  overlay once the socket is connected, so its drawing layer and its views can be
  looked at in a browser under the host's policy before any screen is built on them.
  Not in the nav; reached at `<mount>/graph/preview`. The Graph screen moves onto the
  renderer in batch 4, and this screen goes then.

  Under each view it draws the Mermaid diagram of the same picture, as the Graph screen
  draws it — with the log over the full graph, a lifecycle and the system, and over no
  other view — so the two can be compared on one page: the views are those pictures,
  drawn by the renderer (the user's decision of 8 October). The view `all`, every node
  and relation, has no diagram.

  `?document=contract:<id>` picks a contract by its `id:`, `?document=domain:<module>`
  a domain; without one, the first contract. `?view=` picks one of the document's views
  (`EhOsContract.GraphRenderer.View.views/1`) by its key — `contract`, `declared`,
  `unit:<unit id>`, `lifecycle:<unit id>`, `context_map`, `system` or `all`; without
  one, the document's first.
  """

  use Phoenix.LiveView

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.View

  @impl true
  def mount(_params, _session, socket) do
    contracts = EhOsContract.Registry.contracts()

    choices =
      Enum.sort(for c <- contracts, do: {"contract:" <> EhOsContract.Model.fetch(c).id, c}) ++
        Enum.sort(for d <- EhOsContract.Registry.domains(), do: {"domain:" <> inspect(d), d})

    {:ok, assign(socket, contracts: contracts, choices: choices)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    choices = socket.assigns.choices

    {key, module} =
      List.keyfind(choices, params["document"], 0) || List.first(choices) || {nil, nil}

    drawn = drawn(socket, key, module)
    views = if drawn[:document], do: views(drawn[:document]), else: []

    {view, spec, _title} =
      List.keyfind(views, params["view"], 0) || List.first(views) || {nil, nil, nil}

    {:noreply,
     assign(
       socket,
       [selected: key, module: module, views: views, view: view, spec: spec] ++
         drawn ++ [mermaid: mermaid(module, spec)]
     )}
  end

  @impl true
  def handle_event("pick", %{"document" => key} = params, socket) do
    # Another document starts at its first view; the same one keeps the view picked.
    query =
      if key == socket.assigns.selected,
        do: [document: key, view: params["view"]],
        else: [document: key]

    {:noreply,
     push_patch(socket,
       to:
         "#{socket.assigns.eh_os_contract_web_base_path}/graph/preview?" <>
           URI.encode_query(query)
     )}
  end

  defp drawn(_socket, nil, _module), do: [document: nil, overlay: nil]

  defp drawn(socket, "contract:" <> _, contract) do
    [
      document: Document.contract(contract),
      overlay: connected?(socket) && Overlay.contract(contract)
    ]
  end

  defp drawn(socket, "domain:" <> _, domain) do
    contracts = socket.assigns.contracts

    [
      document: Document.domain(domain, contracts),
      overlay: connected?(socket) && Overlay.domain(domain, contracts)
    ]
  end

  # The document's views by a key for the query string, and `all` last.
  defp views(document) do
    for({spec, title} <- View.views(document), do: {key(spec), spec, title}) ++
      [{"all", :all, "Every node and relation (test bed)"}]
  end

  defp key({kind, id}), do: "#{kind}:#{id}"
  defp key(kind), do: Atom.to_string(kind)

  # The Mermaid diagram of the same picture, with the log over it where the Graph screen
  # lays it: the full graph, a lifecycle and the system.
  defp mermaid(nil, _spec), do: nil
  defp mermaid(_module, nil), do: nil
  defp mermaid(_module, :all), do: nil

  defp mermaid(contract, :contract),
    do: EhOsContract.Graph.contract_to_mermaid(contract, overlay: true)

  defp mermaid(contract, :declared),
    do:
      EhOsContract.Graph.declared_to_mermaid(
        contract,
        EhOsContract.Model.process(EhOsContract.Model.fetch(contract)).name
      )

  defp mermaid(contract, {:unit, id}),
    do: EhOsContract.Graph.unit_to_mermaid(contract, unit(contract, id))

  defp mermaid(contract, {:lifecycle, id}),
    do: EhOsContract.Graph.lifecycle_to_mermaid(contract, unit(contract, id), overlay: true)

  defp mermaid(domain, :context_map), do: EhOsContract.Graph.context_map_to_mermaid(domain)

  defp mermaid(domain, :system) do
    contracts =
      Enum.filter(
        EhOsContract.Registry.contracts(),
        &(EhOsContract.Model.fetch(&1).domain == domain)
      )

    EhOsContract.Graph.system_to_mermaid(domain, contracts, overlay: true)
  end

  # The views the Graph screen lays the log over: the full graph, a lifecycle, the system,
  # and the test bed, which has it all.
  defp logged?(spec), do: spec in [:all, :contract, :system] or match?({:lifecycle, _}, spec)

  # The unit a view's id names: `unit:<contract id>:<name>`.
  defp unit(contract, id) do
    model = EhOsContract.Model.fetch(contract)
    Enum.find_value(model.units, &(id == "unit:#{model.id}:#{&1.name}" && &1.name))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:graph_preview} />

      <section>
        <h3>Graph renderer — preview</h3>
        <p>
          One view of one document, drawn by the renderer that will replace the diagrams on the
          Graph screen, and under it the same picture as the Graph screen draws it today.
        </p>

        <form :if={@choices != []} id="document-select" phx-change="pick">
          <select name="document">
            <option :for={{key, _module} <- @choices} value={key} selected={key == @selected}>
              {key}
            </option>
          </select>
          <select :if={@views != []} name="view">
            <option :for={{key, _spec, title} <- @views} value={key} selected={key == @view}>
              {title}
            </option>
          </select>
        </form>

        <p :if={@choices == []}>No contract or domain is registered.</p>
      </section>

      <.live_component
        :if={@document}
        module={EhOsContract.GraphRenderer.Canvas}
        id="graph-preview"
        document={@document}
        overlay={(logged?(@spec) && @overlay) || nil}
        view={@spec}
      />

      <section :if={@mermaid}>
        <h3>The same picture, as the Graph screen draws it</h3>
        <pre
          class="mermaid"
          phx-hook="MermaidRender"
          phx-update="ignore"
          id="preview-mermaid"
          data-graph={@mermaid}
        ></pre>
      </section>
    </div>
    """
  end
end
