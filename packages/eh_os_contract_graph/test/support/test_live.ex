defmodule EhOsContract.GraphRenderer.TestEndpoint do
  @moduledoc false
  # What `Phoenix.LiveViewTest.live_isolated/3` drives the component through. No server.
  use Phoenix.Endpoint, otp_app: :eh_os_contract_graph

  socket "/live", Phoenix.LiveView.Socket
end

defmodule EhOsContract.GraphRenderer.TestLive do
  @moduledoc false
  # A LiveView that renders the component over the document, the overlay, the view and the
  # audience its session names, as a host would; `{:overlay, _}`, `{:document, _}` and
  # `{:audience, _}` change them, as a host's render would.
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"document" => document} = session, socket),
    do:
      {:ok,
       assign(socket,
         document: document,
         overlay: session["overlay"],
         view: session["view"] || :all,
         audience: session["audience"] || :engineering
       )}

  @impl true
  def handle_info({:overlay, overlay}, socket), do: {:noreply, assign(socket, overlay: overlay)}

  def handle_info({:document, document}, socket),
    do: {:noreply, assign(socket, document: document)}

  def handle_info({:audience, audience}, socket),
    do: {:noreply, assign(socket, audience: audience)}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EhOsContract.GraphRenderer.Canvas}
      id="graph"
      document={@document}
      overlay={@overlay}
      view={@view}
      audience={@audience}
    />
    """
  end
end

defmodule EhOsContract.GraphRenderer.FixtureLoader do
  @moduledoc false
  # A loader over the fixture documents, as a host's would be over its engine or its API:
  # the fulfilment domain, two of its three contracts and its order process; anything else
  # fails, and `opts` may name a ref that raises.
  @behaviour EhOsContract.GraphRenderer.Loader

  alias EhOsContract.GraphRenderer.Fixtures

  @documents %{
    {:domain, "Fulfilment.Domain"} => "domain.fulfilment",
    {:contract, "fulfilment.warehouse"} => "fulfilment.warehouse",
    {:contract, "fulfilment.shipping"} => "fulfilment.shipping",
    {:process, "fulfilment.order"} => "process.fulfilment.order"
  }

  # `opts`: `raise:` a ref whose load raises, `nil_for:` one answered `{:ok, nil}`,
  # `fail_once:` an Agent holding refs whose first load fails, `notify:` a pid told of
  # every load, `bare: true` a domain with no contract, so no system to draw, and `labels:`
  # labels by node id for every document it loads (`Fixtures.relabel/2`).
  @impl true
  def document(ref, opts) do
    if ref == opts[:raise], do: raise("the loader failed")
    if pid = opts[:notify], do: send(pid, {:loaded, ref})

    cond do
      ref == opts[:nil_for] ->
        {:ok, nil}

      (agent = opts[:fail_once]) &&
          Agent.get_and_update(agent, &{ref in &1, List.delete(&1, ref)}) ->
        {:error, :timeout}

      opts[:bare] && match?({:domain, _}, ref) ->
        {:ok, put_in(Fixtures.document("domain.fulfilment"), ["nodes", "contract"], [])}

      name = @documents[ref] ->
        {:ok, Fixtures.relabel(Fixtures.document(name), opts[:labels] || %{})}

      true ->
        {:error, :not_found}
    end
  end

  @impl true
  def overlay(ref, opts) do
    if pid = opts[:notify], do: send(pid, {:overlay, ref})

    case ref do
      {:process, "fulfilment.order"} ->
        {:ok, Fixtures.overlay("process.fulfilment.order")}

      _other ->
        {:ok, nil}
    end
  end
end

defmodule EhOsContract.GraphRenderer.ExplorerLive do
  @moduledoc false
  # A LiveView that renders the explorer over the fixture loader, as a host would, starting
  # where its session's `audience` says; `:render` renders it again, as a host's would.
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket),
    do:
      {:ok,
       assign(socket,
         opts: session["opts"] || [],
         domain: session["domain"] || "Fulfilment.Domain",
         audience: session["audience"] || :engineering,
         renders: 0
       )}

  @impl true
  def handle_info(:render, socket), do: {:noreply, update(socket, :renders, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EhOsContract.GraphRenderer.Explorer}
      id="explorer"
      domain={@domain}
      loader={{EhOsContract.GraphRenderer.FixtureLoader, @opts}}
      audience={@audience}
      renders={@renders}
    />
    """
  end
end
