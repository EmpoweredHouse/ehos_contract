defmodule EhOsContract.GraphRenderer.TestEndpoint do
  @moduledoc false
  # What `Phoenix.LiveViewTest.live_isolated/3` drives the component through. No server.
  use Phoenix.Endpoint, otp_app: :eh_os_contract_graph

  socket "/live", Phoenix.LiveView.Socket
end

defmodule EhOsContract.GraphRenderer.TestLive do
  @moduledoc false
  # A LiveView that renders the component over the document, the overlay and the view its
  # session names, as a host would; `{:overlay, _}` and `{:document, _}` change them, as a host's render would.
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"document" => document} = session, socket),
    do:
      {:ok,
       assign(socket,
         document: document,
         overlay: session["overlay"],
         view: session["view"] || :all
       )}

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
      view={@view}
    />
    """
  end
end

defmodule EhOsContract.GraphRenderer.FixtureLoader do
  @moduledoc false
  # A loader over the fixture documents, as a host's would be over its engine or its API:
  # Rehmed's domain, three of its contracts and its clinical visit; anything else fails,
  # and `opts` may name a ref that raises.
  @behaviour EhOsContract.GraphRenderer.Loader

  alias EhOsContract.GraphRenderer.Fixtures

  @documents %{
    {:domain, "Rehmed.Domain"} => "domain.rehmed",
    {:contract, "rehmed.settlement"} => "rehmed.settlement",
    {:contract, "rehmed.statutory_reporting"} => "rehmed.statutory_reporting",
    {:contract, "rehmed.external_payers"} => "rehmed.external_payers",
    {:process, "rehmed.clinical_visit"} => "process.rehmed.clinical_visit"
  }

  @impl true
  def document(ref, opts) do
    if ref == opts[:raise], do: raise("the loader failed")
    if pid = opts[:notify], do: send(pid, {:loaded, ref})

    case @documents[ref] do
      nil -> {:error, :not_found}
      name -> {:ok, Fixtures.document(name)}
    end
  end

  @impl true
  def overlay({:process, "rehmed.clinical_visit"}, _opts),
    do: {:ok, Fixtures.overlay("process.rehmed.clinical_visit")}

  def overlay(_ref, _opts), do: {:ok, nil}
end

defmodule EhOsContract.GraphRenderer.ExplorerLive do
  @moduledoc false
  # A LiveView that renders the explorer over the fixture loader, as a host would.
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket),
    do:
      {:ok,
       assign(socket, opts: session["opts"] || [], domain: session["domain"] || "Rehmed.Domain")}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EhOsContract.GraphRenderer.Explorer}
      id="explorer"
      domain={@domain}
      loader={{EhOsContract.GraphRenderer.FixtureLoader, @opts}}
    />
    """
  end
end
