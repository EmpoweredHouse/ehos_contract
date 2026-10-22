defmodule EhOsContract.GraphRenderer.ExplorerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.ExplorerLive

  @endpoint EhOsContract.GraphRenderer.TestEndpoint

  defp start(session \\ %{}) do
    {:ok, view, _html} = live_isolated(build_conn(), ExplorerLive, session: session)
    render_async(view)
    view
  end

  defp page(view), do: view |> render() |> LazyHTML.from_fragment()
  defp text(html, selector), do: html |> LazyHTML.query(selector) |> LazyHTML.text()

  defp cards(view),
    do: view |> page() |> LazyHTML.query("button.ehg-card") |> LazyHTML.attribute("data-ehg-node")

  defp go(view, words) do
    view |> element(".ehg-explorer button", words) |> render_click()
    render_async(view)
  end

  defp open(view, id) do
    view |> element(~s(button[data-ehg-node="#{id}"])) |> render_click()
    view |> element("button.ehg-open") |> render_click()
    render_async(view)
  end

  test "starts at the domain's system, its contracts in their contexts, with the path at its root" do
    view = start()

    assert "contract:fulfilment.warehouse" in cards(view)
    assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment"
    assert text(page(view), ".ehg-tab.is-current") =~ "Structure"
  end

  test "the context map is a switch on the domain's level" do
    view = start()
    view |> element(".ehg-lenses button", "Contexts and their relations") |> render_click()

    assert Enum.any?(cards(view), &String.starts_with?(&1, "context:"))
    refute Enum.any?(cards(view), &String.starts_with?(&1, "contract:"))
  end

  test "a contract opens from its card, and the path goes back up" do
    view = start()
    view = tap(view, &open(&1, "contract:fulfilment.warehouse"))

    assert "command:fulfilment.warehouse:confirm_pick" in cards(view)
    assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.warehouse"

    view |> element(".ehg-path button", "fulfilment") |> render_click()
    assert "contract:fulfilment.warehouse" in cards(view)
  end

  test "a unit opens from the contract, with a switch to its lifecycle only where it declares one" do
    view = start()
    open(view, "contract:fulfilment.warehouse")
    # A unit is the box its commands and events sit in: its title selects it.
    view
    |> element(~s([data-ehg-group="unit:fulfilment.warehouse:pick_list"] button.ehg-group-title))
    |> render_click()

    view |> element("button.ehg-open") |> render_click()
    render_async(view)

    assert text(page(view), ".ehg-path [aria-current]") =~ "pick_list"
    assert "command:fulfilment.warehouse:confirm_pick" in cards(view)
    refute has_element?(view, ".ehg-lenses")
  end

  test "the processes are the other viewpoint, and an event opens its contract across them" do
    view = start()
    go(view, "Processes")

    assert text(page(view), ".ehg-tab.is-current") =~ "Processes"
    view |> element(".ehg-places button", "fulfilment.order") |> render_click()
    render_async(view)

    assert "event:fulfilment.warehouse:picked" in cards(view)
    # The log's numbers follow the document: the explorer asks for them once the document
    # has arrived, so a second wait.
    render_async(view)
    assert view |> page() |> LazyHTML.query(".ehg-card .ehg-count") |> Enum.count() > 0

    open(view, "event:fulfilment.warehouse:picked")

    assert text(page(view), ".ehg-tab.is-current") =~ "Structure"
    assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.warehouse"
    assert "command:fulfilment.warehouse:confirm_pick" in cards(view)
  end

  test "each document is loaded once, however often the reader goes back to it" do
    view = start(%{"opts" => [notify: self()]})
    open(view, "contract:fulfilment.warehouse")
    view |> element(".ehg-path button", "fulfilment") |> render_click()
    open(view, "contract:fulfilment.warehouse")

    assert_received {:loaded, {:domain, "Fulfilment.Domain"}}
    assert_received {:loaded, {:contract, "fulfilment.warehouse"}}
    refute_received {:loaded, _}
  end

  @tag :capture_log
  test "a picture that fails to load says so, and a loader that raises does not crash the page" do
    view = start(%{"opts" => [raise: {:contract, "fulfilment.warehouse"}]})
    open(view, "contract:fulfilment.warehouse")

    assert has_element?(view, ".ehg-failed")

    open_missing = start()
    open(open_missing, "contract:fulfilment.orders")
    assert has_element?(open_missing, ".ehg-failed")
  end

  test "a picture drawn without the log says nothing about the log's version" do
    view = start()
    view |> element(".ehg-lenses button", "Contexts and their relations") |> render_click()

    refute render(view) =~ "another version"
  end

  test "a picture that failed to load is loaded again when the reader comes back" do
    {:ok, agent} = Agent.start_link(fn -> [{:contract, "fulfilment.warehouse"}] end)
    view = start(%{"opts" => [fail_once: agent]})

    open(view, "contract:fulfilment.warehouse")
    assert has_element?(view, ".ehg-failed")

    view |> element(".ehg-path button", "fulfilment") |> render_click()
    open(view, "contract:fulfilment.warehouse")
    refute has_element?(view, ".ehg-failed")
    assert "command:fulfilment.warehouse:confirm_pick" in cards(view)
  end

  test "a document answered as nothing is a picture that could not be loaded" do
    view = start(%{"opts" => [nil_for: {:contract, "fulfilment.warehouse"}]})
    open(view, "contract:fulfilment.warehouse")

    assert has_element?(view, ".ehg-failed")
  end

  test "an event the page could not have sent is ignored, and the page lives on" do
    view = start(%{"opts" => [notify: self()]})

    for {event, params} <- [
          {"lens", %{"to" => "bogus"}},
          {"go", %{"to" => ["contract"]}},
          {"go", %{}},
          {"open", %{}},
          {"nothing", %{}}
        ],
        do: view |> with_target("#explorer") |> render_click(event, params)

    assert "contract:fulfilment.warehouse" in cards(view)
  end

  describe "where it starts" do
    # The place is loaded once the domain's document has arrived: a second wait.
    defp start_at(session) do
      view = start(session)
      render_async(view)
      view
    end

    test "at a contract the host names, with the path back up to the domain" do
      view = start_at(%{"at" => {:contract, "fulfilment.warehouse"}})

      assert "command:fulfilment.warehouse:confirm_pick" in cards(view)
      assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.warehouse"
      assert text(page(view), ".ehg-tab.is-current") =~ "Structure"

      view |> element(".ehg-path button", "fulfilment") |> render_click()
      assert "contract:fulfilment.warehouse" in cards(view)
    end

    test "at a process module, in the processes' viewpoint, or at their list" do
      view = start_at(%{"at" => {:process, "fulfilment.order"}})

      assert text(page(view), ".ehg-tab.is-current") =~ "Processes"
      assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.order"

      view = start_at(%{"at" => :processes})
      assert has_element?(view, ".ehg-places button", "fulfilment.order")
    end

    test "at the domain for a place the domain does not name, or anything else, loading nothing of it" do
      for at <- [{:contract, "none.such"}, {:process, "none.such"}, {:unit, "a", "b"}, "x", 7] do
        view = start_at(%{"at" => at, "opts" => [notify: self()]})

        assert "contract:fulfilment.warehouse" in cards(view), inspect(at)
        assert_received {:loaded, {:domain, "Fulfilment.Domain"}}
        refute_received {:loaded, _}
      end
    end

    test "at the domain when the domain's document could not be loaded, and the reader stays there" do
      {:ok, agent} = Agent.start_link(fn -> [{:domain, "Fulfilment.Domain"}] end)

      view =
        start_at(%{"at" => {:contract, "fulfilment.warehouse"}, "opts" => [fail_once: agent]})

      assert has_element?(view, ".ehg-failed")
      assert text(page(view), ".ehg-path [aria-current]") =~ "Fulfilment.Domain"
    end

    test "asks the log of nothing but the place it starts at" do
      start_at(%{"at" => {:contract, "fulfilment.warehouse"}, "opts" => [notify: self()]})

      assert_receive {:overlay, {:contract, "fulfilment.warehouse"}}
      refute_received {:overlay, _}
    end

    test "gives way to where the reader went before the domain's document arrived" do
      {:ok, view, _html} =
        live_isolated(build_conn(), ExplorerLive,
          session: %{"at" => {:contract, "fulfilment.warehouse"}, "opts" => [hold: self()]}
        )

      assert_receive {:held, loader}
      # The tab the reader is already on moves nothing; the other one does.
      view |> element(".ehg-tab", "Structure") |> render_click()
      view |> element(".ehg-tab", "Processes") |> render_click()
      send(loader, :go)
      render_async(view)
      render_async(view)

      assert text(page(view), ".ehg-tab.is-current") =~ "Processes"
    end

    test "holds through a click that leaves the reader where they were" do
      {:ok, view, _html} =
        live_isolated(build_conn(), ExplorerLive,
          session: %{"at" => {:contract, "fulfilment.warehouse"}, "opts" => [hold: self()]}
        )

      assert_receive {:held, loader}
      view |> element(".ehg-tab", "Structure") |> render_click()
      send(loader, :go)
      render_async(view)
      render_async(view)

      assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.warehouse"
    end

    test "is read when it starts: a host rendering it again does not move the reader" do
      view = start_at(%{"at" => {:contract, "fulfilment.warehouse"}})
      view |> element(".ehg-path button", "fulfilment") |> render_click()

      send(view.pid, :render)
      render_async(view)

      assert "contract:fulfilment.warehouse" in cards(view)
    end
  end

  test "a place the domain does not hold is never loaded" do
    view = start(%{"opts" => [notify: self()]})
    view |> with_target("#explorer") |> render_click("go", %{"to" => "contract\u001Fnone.such"})

    view
    |> with_target("#explorer")
    |> render_click("go", %{"to" => "unit\u001Ffulfilment.warehouse\u001Fx"})

    render_async(view)

    refute_received {:loaded, {:contract, "none.such"}}
    refute_received {:loaded, {:contract, "fulfilment.warehouse"}}
    assert "contract:fulfilment.warehouse" in cards(view)
  end

  test "the log is read only for a picture that draws it" do
    start(%{"opts" => [notify: self(), bare: true]})

    assert_received {:loaded, {:domain, "Fulfilment.Domain"}}
    refute_received {:overlay, _}
  end

  test "the panel offers no way to where the reader already is" do
    view = start()
    open(view, "contract:fulfilment.warehouse")

    view
    |> element(~s([data-ehg-group="unit:fulfilment.warehouse:pick_list"] button.ehg-group-title))
    |> render_click()

    view |> element("button.ehg-open") |> render_click()
    render_async(view)

    view
    |> element(~s(button[data-ehg-node="command:fulfilment.warehouse:confirm_pick"]))
    |> render_click()

    view
    |> element(~s(button[data-ehg-node="event:fulfilment.warehouse:picked"]))
    |> render_click()

    refute has_element?(view, "button.ehg-open")
  end

  test "an event a contract consumes opens the contract its document says declares it" do
    view = start()
    open(view, "contract:fulfilment.shipping")

    # A policy of shipping takes it, so the contract's picture draws it.
    open(view, "event:fulfilment.shipping:parcel_packed")

    assert text(page(view), ".ehg-path [aria-current]") =~ "fulfilment.warehouse"
    assert "command:fulfilment.warehouse:pack_parcel" in cards(view)
  end

  # Plan DD, L4 (#326): the switch of who reads, over the canvas.
  describe "the owner's view" do
    defp read_as(view, words) do
      view |> element(".ehg-audience button", words) |> render_click()
      render_async(view)
    end

    defp panel_of(view, id) do
      view |> element(~s(button[data-ehg-node="#{id}"])) |> render_click()
      text(page(view), ".ehg-panel")
    end

    test "starts as the engineer reads it, and the switch reads the process for the owner and back" do
      view = start()
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Engineering"

      go(view, "Processes")
      view |> element(".ehg-places button", "An order") |> render_click()
      render_async(view)

      process = "process:fulfilment.order"
      assert panel_of(view, process) =~ "One run per"

      read_as(view, "Owner")
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Owner"
      owner = text(page(view), ".ehg-panel")

      refute owner =~ "One run per"
      refute owner =~ "order_id"
      # The log's numbers stay.
      assert owner =~ "From the log"
      assert view |> page() |> LazyHTML.query(".ehg-card .ehg-count") |> Enum.count() > 0
      # The path names the process by its label.
      assert text(page(view), ".ehg-path [aria-current]") =~ "An order"

      read_as(view, "Engineering")
      assert text(page(view), ".ehg-panel") =~ "One run per"
    end

    test "a host starts it for the owner, and its next render keeps the reader's switch" do
      # Each case study's context is labelled as its contract's module is named, so the
      # warehouse is labelled apart here.
      labels = %{"context:Fulfilment.Domain:warehouse" => "Stock room"}
      view = start(%{"audience" => :owner, "opts" => [labels: labels]})
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Owner"

      # A contract is read by its context's label, and has no name in code under it.
      warehouse =
        view |> page() |> LazyHTML.query(~s([data-ehg-node="contract:fulfilment.warehouse"]))

      assert LazyHTML.text(warehouse) =~ "Stock room"
      refute LazyHTML.text(warehouse) =~ "Warehouse"
      assert warehouse |> LazyHTML.query(".ehg-name") |> Enum.count() == 0
      refute text(page(view), ".ehg-actors") =~ "Role in EHOS"

      read_as(view, "Engineering")
      send(view.pid, :render)
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Engineering"
    end

    test "an audience the explorer does not know is refused by name" do
      assert_raise ArgumentError, ~r/:engineering or :owner, got: :manager/, fn ->
        EhOsContract.GraphRenderer.Audience.cast(:manager)
      end

      view = start()
      view |> with_target("#explorer") |> render_click("audience", %{"to" => "manager"})
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Engineering"
    end
  end
end
