defmodule EhOsContract.Web.Live.GraphPreview do
  @moduledoc """
  **Temporary** (plan E13b, batch 1): the renderer of `eh_os_contract_graph` drawing
  one `graph.v1` document of the registry at a time, with its overlay once the socket
  is connected, so its drawing layer can be looked at in a browser under the host's
  policy before any screen is built on it. Not in the nav; reached at
  `<mount>/graph/preview`. The Graph screen moves onto the renderer in batch 4, and
  this screen goes then.

  `?document=contract:<id>` picks a contract by its `id:`, `?document=domain:<module>`
  a domain; without one, the first contract.
  """

  use Phoenix.LiveView

  alias EhOsContract.Graph.{Document, Overlay}

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

    {:noreply, assign(socket, [selected: key] ++ drawn(socket, key, module))}
  end

  @impl true
  def handle_event("pick", %{"document" => key}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to:
           "#{socket.assigns.eh_os_contract_web_base_path}/graph/preview?" <>
             URI.encode_query(document: key)
       )}

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

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:graph_preview} />

      <section>
        <h3>Graph renderer — preview</h3>
        <p>
          Every node and relation of one document, drawn by the renderer that will replace the
          diagrams on the Graph screen. A test bed, not a picture to read from.
        </p>

        <form :if={@choices != []} id="document-select" phx-change="pick">
          <select name="document">
            <option :for={{key, _module} <- @choices} value={key} selected={key == @selected}>
              {key}
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
        overlay={@overlay || nil}
      />
    </div>
    """
  end
end
