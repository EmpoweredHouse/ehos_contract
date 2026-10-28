defmodule EhOsContract.Web.Live.Graph do
  # The second screen: the pictures of the contract model, live in the dashboard.
  #
  # **One explorer per domain** (plan DD, stage G1, #297, the user's decisions of
  # 15 October): the renderer's `EhOsContract.GraphRenderer.Explorer`, with the structure
  # (the domain's system, a contract, a unit) and the processes as two branches of one
  # path back up (#490), and the panel opening where a card leads. Its documents and
  # overlays come from `EhOsContract.Web.GraphLoader`, the same the API serves, each built
  # in the background when the reader enters its picture — so mounting the screen counts
  # nothing in the log, and a host with only the API draws the same explorer from it. Before
  # G1 this screen stacked every domain's map and system, a selector, the selected
  # contract's pictures and each of its units on one page (plan E13b, P1b #186, P2e #220).
  @moduledoc false

  use Phoenix.LiveView

  alias EhOsContract.GraphRenderer.Explorer

  @impl true
  def mount(_params, _session, socket) do
    domains = for domain <- EhOsContract.Registry.domains(), do: inspect(domain)
    {:ok, assign(socket, :domains, domains)}
  end

  # An event the page does not send is ignored rather than crashing the viewer's page.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:graph} />
      <p class="access-badge">Access: {access_label(@eh_os_contract_web_access)}</p>

      <section :for={domain <- @domains}>
        <h3>Domain {domain}</h3>
        <.live_component
          module={Explorer}
          id={"graph-#{domain}"}
          domain={domain}
          loader={EhOsContract.Web.GraphLoader}
        />
      </section>

      <p :if={@domains == []}>No domain is registered.</p>
    </div>
    """
  end

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end
