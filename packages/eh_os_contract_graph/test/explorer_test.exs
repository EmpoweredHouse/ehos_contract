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

    assert "contract:rehmed.settlement" in cards(view)
    assert text(page(view), ".ehg-path [aria-current]") =~ "rehmed"
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
    view = tap(view, &open(&1, "contract:rehmed.settlement"))

    assert "command:rehmed.settlement:close_settlement" in cards(view)
    assert text(page(view), ".ehg-path [aria-current]") =~ "rehmed.settlement"

    view |> element(".ehg-path button", "rehmed") |> render_click()
    assert "contract:rehmed.settlement" in cards(view)
  end

  test "a unit opens from the contract, with a switch to its lifecycle only where it declares one" do
    view = start()
    open(view, "contract:rehmed.settlement")
    # A unit is the box its commands and events sit in: its title selects it.
    view
    |> element(
      ~s([data-ehg-group="unit:rehmed.settlement:visit_settlement"] button.ehg-group-title)
    )
    |> render_click()

    view |> element("button.ehg-open") |> render_click()
    render_async(view)

    assert text(page(view), ".ehg-path [aria-current]") =~ "visit_settlement"
    assert "command:rehmed.settlement:close_settlement" in cards(view)
    refute has_element?(view, ".ehg-lenses")
  end

  test "the processes are the other viewpoint, and an event opens its contract across them" do
    view = start()
    go(view, "Processes")

    assert text(page(view), ".ehg-tab.is-current") =~ "Processes"
    view |> element(".ehg-places button", "rehmed.clinical_visit") |> render_click()
    render_async(view)

    assert "event:rehmed.statutory_reporting:p1_report_sent" in cards(view)
    # The log's numbers follow the document.
    assert view |> page() |> LazyHTML.query(".ehg-card .ehg-count") |> Enum.count() > 0

    open(view, "event:rehmed.statutory_reporting:p1_report_sent")

    assert text(page(view), ".ehg-tab.is-current") =~ "Structure"
    assert text(page(view), ".ehg-path [aria-current]") =~ "rehmed.statutory_reporting"
    assert "command:rehmed.statutory_reporting:queue_p1_report" in cards(view)
  end

  test "each document is loaded once, however often the reader goes back to it" do
    view = start(%{"opts" => [notify: self()]})
    open(view, "contract:rehmed.settlement")
    view |> element(".ehg-path button", "rehmed") |> render_click()
    open(view, "contract:rehmed.settlement")

    assert_received {:loaded, {:domain, "Rehmed.Domain"}}
    assert_received {:loaded, {:contract, "rehmed.settlement"}}
    refute_received {:loaded, _}
  end

  @tag :capture_log
  test "a picture that fails to load says so, and a loader that raises does not crash the page" do
    view = start(%{"opts" => [raise: {:contract, "rehmed.settlement"}]})
    open(view, "contract:rehmed.settlement")

    assert has_element?(view, ".ehg-failed")

    open_missing = start()
    open(open_missing, "contract:rehmed.scheduling")
    assert has_element?(open_missing, ".ehg-failed")
  end

  test "a picture drawn without the log says nothing about the log's version" do
    view = start()
    view |> element(".ehg-lenses button", "Contexts and their relations") |> render_click()

    refute render(view) =~ "another version"
  end

  test "a picture that failed to load is loaded again when the reader comes back" do
    {:ok, agent} = Agent.start_link(fn -> [{:contract, "rehmed.settlement"}] end)
    view = start(%{"opts" => [fail_once: agent]})

    open(view, "contract:rehmed.settlement")
    assert has_element?(view, ".ehg-failed")

    view |> element(".ehg-path button", "rehmed") |> render_click()
    open(view, "contract:rehmed.settlement")
    refute has_element?(view, ".ehg-failed")
    assert "command:rehmed.settlement:close_settlement" in cards(view)
  end

  test "a document answered as nothing is a picture that could not be loaded" do
    view = start(%{"opts" => [nil_for: {:contract, "rehmed.settlement"}]})
    open(view, "contract:rehmed.settlement")

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

    assert "contract:rehmed.settlement" in cards(view)
  end

  test "a place the domain does not hold is never loaded" do
    view = start(%{"opts" => [notify: self()]})
    view |> with_target("#explorer") |> render_click("go", %{"to" => "contract\u001Fnone.such"})

    view
    |> with_target("#explorer")
    |> render_click("go", %{"to" => "unit\u001Frehmed.settlement\u001Fx"})

    render_async(view)

    refute_received {:loaded, {:contract, "none.such"}}
    refute_received {:loaded, {:contract, "rehmed.settlement"}}
    assert "contract:rehmed.settlement" in cards(view)
  end

  test "the log is read only for a picture that draws it" do
    start(%{"opts" => [notify: self(), bare: true]})

    assert_received {:loaded, {:domain, "Rehmed.Domain"}}
    refute_received {:overlay, _}
  end

  test "the panel offers no way to where the reader already is" do
    view = start()
    open(view, "contract:rehmed.settlement")

    view
    |> element(
      ~s([data-ehg-group="unit:rehmed.settlement:visit_settlement"] button.ehg-group-title)
    )
    |> render_click()

    view |> element("button.ehg-open") |> render_click()
    render_async(view)

    view
    |> element(~s(button[data-ehg-node="command:rehmed.settlement:close_settlement"]))
    |> render_click()

    view
    |> element(~s(button[data-ehg-node="event:rehmed.settlement:payment_recorded"]))
    |> render_click()

    refute has_element?(view, "button.ehg-open")
  end

  test "an event a contract consumes opens the contract its document says declares it" do
    view = start()
    open(view, "contract:rehmed.external_payers")

    # The payer's period consults it, so its unit's picture draws it.
    view
    |> element(
      ~s([data-ehg-group="unit:rehmed.external_payers:payer_period"] button.ehg-group-title)
    )
    |> render_click()

    view |> element("button.ehg-open") |> render_click()
    render_async(view)
    open(view, "event:rehmed.external_payers:visit_charged_to_payer")

    assert text(page(view), ".ehg-path [aria-current]") =~ "rehmed.settlement"
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
      view |> element(".ehg-places button", "Wizyta") |> render_click()
      render_async(view)

      process = "process:rehmed.clinical_visit"
      assert panel_of(view, process) =~ "One run per"

      read_as(view, "Owner")
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Owner"
      owner = text(page(view), ".ehg-panel")

      refute owner =~ "One run per"
      refute owner =~ "visit_id"
      # The log's numbers stay.
      assert owner =~ "From the log"
      assert view |> page() |> LazyHTML.query(".ehg-card .ehg-count") |> Enum.count() > 0
      # The path names the process by its label.
      assert text(page(view), ".ehg-path [aria-current]") =~ "Wizyta"

      read_as(view, "Engineering")
      assert text(page(view), ".ehg-panel") =~ "One run per"
    end

    test "a host starts it for the owner, and its next render keeps the reader's switch" do
      view = start(%{"audience" => :owner})
      assert text(page(view), ".ehg-audience [aria-pressed=true]") =~ "Owner"

      # A contract is read by its context's label, and has no name in code under it.
      settlement =
        view |> page() |> LazyHTML.query(~s([data-ehg-node="contract:rehmed.settlement"]))

      assert LazyHTML.text(settlement) =~ "Rozliczenia"
      assert settlement |> LazyHTML.query(".ehg-name") |> Enum.count() == 0
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
