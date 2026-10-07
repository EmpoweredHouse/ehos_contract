defmodule EhOsContract.GraphRenderer.TestEndpoint do
  @moduledoc false
  # What `Phoenix.LiveViewTest.live_isolated/3` drives the component through. No server.
  use Phoenix.Endpoint, otp_app: :eh_os_contract_graph

  socket "/live", Phoenix.LiveView.Socket
end

defmodule EhOsContract.GraphRenderer.TestLive do
  @moduledoc false
  # A LiveView that renders the component over the document and the overlay its session
  # names, as a host would; `{:overlay, _}` and `{:document, _}` change them, as a host's update would.
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"document" => document} = session, socket),
    do: {:ok, assign(socket, document: document, overlay: session["overlay"])}

  @impl true
  def handle_info({:overlay, overlay}, socket), do: {:noreply, assign(socket, overlay: overlay)}

  def handle_info({:document, document}, socket),
    do: {:noreply, assign(socket, document: document)}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EhOsContract.GraphRenderer.Canvas}
      id="graph"
      document={@document}
      overlay={@overlay}
    />
    """
  end
end
