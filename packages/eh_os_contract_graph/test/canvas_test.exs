defmodule EhOsContract.GraphRenderer.CanvasTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.{Canvas, Fixtures, TestLive, View}

  @endpoint EhOsContract.GraphRenderer.TestEndpoint

  defp draw(document, overlay \\ nil, view \\ :all),
    do:
      render_component(Canvas, id: "graph", document: document, overlay: overlay, view: view)
      |> LazyHTML.from_fragment()

  # Every view of every fixture, the test bed among them.
  defp every_view do
    for name <- Fixtures.names(),
        document = Fixtures.document(name),
        {spec, _title} <- [{:all, nil} | View.views(document)],
        do: {"#{name} #{inspect(spec)}", document, spec}
  end

  defp at(html, attribute, id), do: LazyHTML.query(html, ~s([#{attribute}="#{escape(id)}"]))

  # A value inside a quoted attribute selector.
  defp escape(value), do: value |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))

  defp classes(html), do: html |> LazyHTML.attribute("class") |> Enum.flat_map(&String.split/1)

  describe "what it renders" do
    test "a card per node and a label per relation of the view, with the ids the hook reads" do
      for name <- Fixtures.names() do
        document = Fixtures.document(name)
        view = View.all(document)
        html = draw(document)

        cards = LazyHTML.query(html, "button.ehg-card[data-ehg-node]")
        labels = LazyHTML.query(html, "button.ehg-relation[data-ehg-relation]")

        assert LazyHTML.attribute(cards, "data-ehg-node") == Enum.map(view.nodes, & &1.id), name
        assert LazyHTML.attribute(cards, "data-kind") == Enum.map(view.nodes, & &1.kind), name

        assert Enum.zip([
                 LazyHTML.attribute(labels, "data-ehg-relation"),
                 LazyHTML.attribute(labels, "data-from"),
                 LazyHTML.attribute(labels, "data-to")
               ]) == Enum.map(view.relations, &{&1.id, &1.from, &1.to}),
               name
      end
    end

    test "no element has a style attribute, and the arrows' layer is left to the hook" do
      for {name, document, spec} <- every_view() do
        html = draw(document, nil, spec)

        assert Enum.count(LazyHTML.query(html, "[style]")) == 0, name

        assert LazyHTML.attribute(LazyHTML.query(html, "svg.ehg-arrows"), "phx-update") == [
                 "ignore"
               ]

        assert LazyHTML.attribute(LazyHTML.query(html, ".ehg"), "phx-hook") == [
                 "EhOsContractGraph"
               ]
      end
    end

    test "each view's groups as boxes with their titles, each card naming its group" do
      for {name, document, spec} <- every_view() do
        view = View.build(document, spec)
        html = draw(document, nil, spec)
        boxes = LazyHTML.query(html, "div.ehg-group[data-ehg-group]")

        assert LazyHTML.attribute(boxes, "data-ehg-group") == Enum.map(view.groups, & &1.id), name

        assert boxes |> LazyHTML.query("button.ehg-group-title") |> LazyHTML.attribute("title") ==
                 Enum.map(view.groups, & &1.title),
               name

        grouped = for node <- view.nodes, node.group, do: {node.id, node.group}
        cards = LazyHTML.query(html, "[data-ehg-node][data-group]")

        assert Enum.zip(
                 LazyHTML.attribute(cards, "data-ehg-node"),
                 LazyHTML.attribute(cards, "data-group")
               ) == grouped,
               name

        assert LazyHTML.attribute(LazyHTML.query(html, ".ehg"), "data-direction") == [
                 view.direction
               ]
      end
    end

    test "a label names its arrow's line and head, and one with nothing to say is blank" do
      document = Fixtures.document("process.rehmed.clinical_visit")
      html = draw(document, nil, :process)
      relations = View.process(document).relations
      [promise] = for %{type: "promise"} = r <- relations, do: r.id
      [precedes | _] = for %{type: "precedes"} = r <- relations, do: r.id
      [accountable] = for %{type: "accountable_for"} = r <- relations, do: r.id

      label = at(html, "data-ehg-relation", promise)
      assert LazyHTML.attribute(label, "data-line") == ["thick"]
      assert LazyHTML.attribute(label, "data-head") == ["arrow"]
      assert LazyHTML.text(label) =~ "within 2 days"
      refute "ehg-blank" in classes(label)

      assert "ehg-blank" in classes(at(html, "data-ehg-relation", precedes))

      assert at(html, "data-ehg-relation", accountable) |> LazyHTML.attribute("data-head") == [
               "none"
             ]
    end

    test "a state card lists its fields, an end of a lifecycle and its start have their looks" do
      html =
        draw(
          Fixtures.document("rehmed.settlement"),
          nil,
          {:unit, "unit:rehmed.settlement:visit_settlement"}
        )

      fields =
        html
        |> at("data-ehg-node", "unit:rehmed.settlement:visit_settlement")
        |> LazyHTML.query(".ehg-field")
        |> Enum.map(&LazyHTML.text/1)

      assert "visit_id: id · identity" in fields

      unit = "unit:appunite_equipment.demands:demand"
      html = draw(Fixtures.document("appunite_equipment.demands"), nil, {:lifecycle, unit})
      start = at(html, "data-ehg-node", unit)

      assert LazyHTML.attribute(start, "data-kind") == ["start"]
      assert String.trim(LazyHTML.text(start)) == ""

      assert html
             |> at("data-ehg-node", "status:appunite_equipment.demands:demand:fulfilled")
             |> LazyHTML.attribute("data-variant") == ["final"]
    end

    # Plan DD, C1 (#304): a unit the document says records only says so on its card and on
    # its box, beside its kind; one it does not, not.
    test "a unit that records only says so beside its kind, on its card and on its box" do
      unit = "unit:taxvision.registry_watch:client"
      document = Fixtures.document("taxvision.registry_watch")

      recording =
        update_in(document, ["nodes", "unit"], fn units ->
          for u <- units, do: if(u["id"] == unit, do: Map.put(u, "records_only", true), else: u)
        end)

      tag = fn doc ->
        doc
        |> draw(nil, {:unit, unit})
        |> at("data-ehg-node", unit)
        |> LazyHTML.query(".ehg-kind")
        |> LazyHTML.text()
      end

      title = fn doc ->
        doc
        |> draw(nil, :contract)
        |> LazyHTML.query("div.ehg-group[data-ehg-group] button.ehg-group-title")
        |> LazyHTML.attribute("title")
        |> Enum.find(&(&1 =~ "aggregate"))
      end

      assert tag.(recording) == "aggregate · records only"
      assert title.(recording) =~ ~r/ · aggregate · records only$/u
      assert tag.(document) == "aggregate"
      refute title.(document) =~ "records only"
    end

    test "a card shows its kind as a badge with an icon, and where it lives in a footer" do
      document = Fixtures.document("process.rehmed.clinical_visit")
      html = draw(document, nil, :process)
      card = at(html, "data-ehg-node", "event:rehmed.statutory_reporting:p1_report_sent")

      assert card |> LazyHTML.query(".ehg-kind") |> LazyHTML.text() == "event"
      assert Enum.count(LazyHTML.query(card, ".ehg-kind svg.ehg-icon[aria-hidden]")) == 1

      assert card |> LazyHTML.query(".ehg-foot") |> LazyHTML.text() ==
               "rehmed.statutory_reporting"
    end

    test "a name in code may break after a dot or an underscore, and keeps its text" do
      document = Fixtures.document("process.rehmed.clinical_visit")
      html = draw(document, nil, :process)
      card = at(html, "data-ehg-node", "event:rehmed.statutory_reporting:p1_report_sent")

      assert card |> LazyHTML.query(".ehg-name") |> LazyHTML.text() == "p1_report_sent"
      assert Enum.count(LazyHTML.query(card, ".ehg-name wbr")) == 2
      assert Enum.count(LazyHTML.query(card, ".ehg-foot wbr")) == 2
    end

    test "a legend under the canvas lists what the view draws" do
      document = Fixtures.document("process.rehmed.clinical_visit")
      legend = document |> draw(nil, :process) |> LazyHTML.query("dl.ehg-legend")

      assert LazyHTML.attribute(LazyHTML.query(legend, ".ehg-legend-kind"), "data-kind") ==
               ~w(actor event external process)

      assert "thick" in LazyHTML.attribute(
               LazyHTML.query(legend, ".ehg-legend-line"),
               "data-look"
             )
    end

    test "a client's text is text, and an id of any characters survives into the page" do
      document = Fixtures.document("edge_cases")
      html = draw(document)

      assert Enum.count(LazyHTML.query(html, "script")) == 0

      assert html |> at("data-ehg-node", ~s(command:edge_cases:say "hi")) |> LazyHTML.text() =~
               "<script>"

      assert Enum.count(at(html, "data-ehg-node", "command:edge_cases:back\\slash")) == 1
      assert Enum.count(at(html, "data-ehg-node", "event:edge_cases:zażółć gęślą jaźń")) == 1
    end

    test "a card shows the client's label and the name under it, or the name alone" do
      html = draw(Fixtures.document("edge_cases"))

      named = at(html, "data-ehg-node", "unit:edge_cases:1st")
      assert named |> LazyHTML.query(".ehg-label") |> LazyHTML.text() == "1st"
      assert Enum.count(LazyHTML.query(named, ".ehg-name")) == 0

      labelled = at(html, "data-ehg-node", "status:edge_cases:1st:closed")
      assert labelled |> LazyHTML.query(".ehg-label") |> LazyHTML.text() == "Zamknięta"
      assert labelled |> LazyHTML.query(".ehg-name") |> LazyHTML.text() == "closed"
    end
  end

  describe "the overlay" do
    setup do
      document = Fixtures.document("taxvision.registry_watch")
      [step | _] = document["relations"]["emits"]
      [event | _] = document["nodes"]["event"]

      overlay = %{
        "document_digest" => document["digest"],
        "nodes" => %{event["id"] => %{"occurrences" => 5}},
        "relations" => %{
          step["id"] => %{
            "taken" => 0,
            "waiting" => %{"lag" => 0, "timers" => 0, "effects" => 0},
            "failing" => %{"commands" => 1, "effects" => 0, "subscription" => nil},
            "waits" => false,
            "fails" => true,
            "untraversed" => true,
            "pending" => false
          }
        },
        "observed" => %{"relations" => %{"undeclared" => []}}
      }

      [document: document, overlay: overlay, step: step["id"], event: event["id"]]
    end

    test "its counts and states are on the cards and the labels", c do
      html = draw(c.document, c.overlay)
      label = at(html, "data-ehg-relation", c.step)

      assert "is-untraversed" in classes(label)
      assert "is-failing" in classes(label)
      assert label |> LazyHTML.query(".ehg-count") |> LazyHTML.text() == "×0"

      assert html
             |> at("data-ehg-node", c.event)
             |> LazyHTML.query(".ehg-count")
             |> LazyHTML.text() == "×5"

      assert Enum.count(LazyHTML.query(html, ".ehg-note")) == 0
    end

    test "an overlay of another version of the document is not drawn, and the page says so", c do
      html = draw(c.document, %{c.overlay | "document_digest" => "ffffffffffff"})

      refute "is-untraversed" in classes(at(html, "data-ehg-relation", c.step))
      assert Enum.count(LazyHTML.query(html, ".ehg-count")) == 0
      assert html |> LazyHTML.query(".ehg-note") |> LazyHTML.text() =~ "another version"
    end
  end

  # Plan DD, P2e (#220).
  describe "a process's overlay" do
    setup do
      document = Fixtures.document("process.rehmed.clinical_visit")
      overlay = Fixtures.overlay("process.rehmed.clinical_visit")
      relations = View.process(document).relations
      [promise] = for %{type: "promise"} = r <- relations, do: r
      [other_way] = for %{type: "or_else"} = r <- relations, do: r.id

      [
        document: document,
        overlay: overlay,
        arrow: promise.id,
        other_way: other_way,
        promise: promise.facts["id"]
      ]
    end

    defp count(html, attribute, id),
      do: html |> at(attribute, id) |> LazyHTML.query(".ehg-count") |> Enum.map(&LazyHTML.text/1)

    test "its runs on the process, and each event's occurrences, 0 included", c do
      overlay =
        c.overlay
        |> put_in(["nodes", "process:rehmed.clinical_visit", "runs"], 3)
        |> put_in(["nodes", "event:rehmed.scheduling:visit_completed"], %{"occurrences" => 3})

      html = draw(c.document, overlay, :process)

      assert count(html, "data-ehg-node", "process:rehmed.clinical_visit") == ["×3"]
      assert count(html, "data-ehg-node", "event:rehmed.scheduling:visit_completed") == ["×3"]

      assert count(html, "data-ehg-node", "event:rehmed.statutory_reporting:p1_report_sent") == [
               "×0"
             ]

      # Nothing the log counts is not an event.
      assert count(html, "data-ehg-node", "actor:Rehmed.Domain:manager") == []
    end

    test "a promise's verdicts on its arrow, a broken one in the error colour", c do
      verdicts = %{
        "instances" => 6,
        "satisfied" => 3,
        "satisfied_via_eventually" => 3,
        "satisfied_via_or_else" => 0,
        "violated" => 1,
        "pending" => 2,
        "suspended" => 0
      }

      html = draw(c.document, put_in(c.overlay, ["nodes", c.promise], verdicts), :process)
      label = at(html, "data-ehg-relation", c.arrow)

      assert count(html, "data-ehg-relation", c.arrow) == ["· 3 kept, 1 broken, 2 pending"]
      assert "is-failing" in classes(label)

      # The dotted arrow is the same promise's: its state, as its panel's verdicts, and the
      # words once, on the heavy one.
      other_way = at(html, "data-ehg-relation", c.other_way)
      assert "is-failing" in classes(other_way)
      assert count(html, "data-ehg-relation", c.other_way) == []

      # Over an empty log: no run opened it.
      html = draw(c.document, c.overlay, :process)
      assert count(html, "data-ehg-relation", c.arrow) == ["· none opened"]
      refute "is-failing" in classes(at(html, "data-ehg-relation", c.arrow))
    end

    test "a promise the owner has yet to confirm is unconfirmed, overlay or not", c do
      unverified =
        update_in(c.document, ["nodes", "promise"], fn [p] -> [Map.put(p, "unverified", true)] end)

      overlay = update_in(c.overlay, ["nodes"], &Map.delete(&1, c.promise))

      for overlay <- [overlay, nil] do
        assert count(draw(unverified, overlay, :process), "data-ehg-relation", c.arrow) ==
                 ["· unconfirmed"]
      end

      # One merely missing from the overlay is not claimed unconfirmed, and with no overlay
      # a confirmed one says nothing.
      assert count(draw(c.document, overlay, :process), "data-ehg-relation", c.arrow) == []
      assert count(draw(c.document, nil, :process), "data-ehg-relation", c.arrow) == []
    end
  end

  describe "a selection" do
    setup do
      document = Fixtures.document("edge_cases")

      {:ok, view, _html} =
        live_isolated(build_conn(), TestLive, session: %{"document" => document})

      [view: view, document: document]
    end

    defp page(view), do: view |> render() |> LazyHTML.from_fragment()

    # A host may build a document by hand, without a digest: it is drawn, and the panel's
    # joins are made for each such document rather than kept from the one before.
    test "a document without a digest is drawn, and the next one's panel is its own", %{
      view: view,
      document: document
    } do
      first = Map.delete(document, "digest")
      assert draw(first) |> LazyHTML.query(".ehg-canvas") |> Enum.count() == 1

      send(view.pid, {:document, first})
      send(view.pid, {:document, first})
      view |> element(~s(button[data-ehg-node="unit:edge_cases:1st"])) |> render_click()
      refute page(view) |> LazyHTML.query(".ehg-panel") |> LazyHTML.text() =~ "Later"

      # The unit's events are the panel's joins: an event the next document adds to it
      # is listed only if they are made again.
      later = %{
        "id" => "event:edge_cases:later",
        "name" => "later",
        "label" => "Later",
        "source" => nil,
        "fields" => [],
        "unit" => "unit:edge_cases:1st"
      }

      send(view.pid, {:document, update_in(first, ["nodes", "event"], &(&1 ++ [later]))})
      assert page(view) |> LazyHTML.query(".ehg-panel") |> LazyHTML.text() =~ "Later"
    end

    test "a click on a card selects it, marks what touches it, and opens its panel", %{view: view} do
      view |> element(~s(button[data-ehg-node="unit:edge_cases:1st"])) |> render_click()
      html = page(view)

      assert "is-selected" in classes(at(html, "data-ehg-node", "unit:edge_cases:1st"))
      assert "is-near" in classes(at(html, "data-ehg-relation", "builds:a"))
      assert "is-near" in classes(at(html, "data-ehg-node", "event:edge_cases:zażółć gęślą jaźń"))
      assert "is-far" in classes(at(html, "data-ehg-node", "status:edge_cases:1st:open"))
      assert html |> LazyHTML.query(".ehg-panel h4") |> LazyHTML.text() == "1st"
      assert html |> LazyHTML.query(".ehg-panel") |> LazyHTML.text() =~ "aggregate"
    end

    test "an arrow's click, pushed by the hook, selects the relation and names its ends", %{
      view: view
    } do
      view |> with_target("#graph") |> render_click("select", %{"id" => "transition:open:closed"})
      panel = view |> page() |> LazyHTML.query(".ehg-panel")

      assert panel |> LazyHTML.query("h4") |> LazyHTML.text() == "transition"
      assert LazyHTML.text(panel) =~ "Otwarta"
      assert LazyHTML.text(panel) =~ "Zamknięta"
    end

    test "a group's title selects the group, and marks its cards" do
      document = Fixtures.document("rehmed.settlement")
      unit = "unit:rehmed.settlement:visit_settlement"

      {:ok, view, _html} =
        live_isolated(build_conn(), TestLive,
          session: %{"document" => document, "view" => :contract}
        )

      view |> element(~s(button.ehg-group-title)) |> render_click()
      html = page(view)

      assert "is-selected" in classes(at(html, "data-ehg-group", unit))

      assert "is-near" in classes(
               at(html, "data-ehg-node", "command:rehmed.settlement:close_settlement")
             )

      assert "is-far" in classes(at(html, "data-ehg-node", "actor:Rehmed.Domain:reception"))
      assert html |> LazyHTML.query(".ehg-panel h4") |> LazyHTML.text() == "Rozliczenie wizyty"
    end

    test "a second click, the close button, or an unknown id leave nothing new selected", %{
      view: view
    } do
      target = with_target(view, "#graph")

      render_click(target, "select", %{"id" => "builds:a"})
      render_click(target, "select", %{"id" => "builds:a"})
      assert Enum.count(LazyHTML.query(page(view), ".ehg-panel")) == 0

      render_click(target, "select", %{"id" => "builds:a"})
      view |> element(".ehg-panel header button") |> render_click()
      assert Enum.count(LazyHTML.query(page(view), ".ehg-panel")) == 0

      render_click(target, "select", %{"id" => "no such id"})
      assert Enum.count(LazyHTML.query(page(view), ".ehg-panel, .is-selected")) == 0
    end

    test "survives a new overlay, and goes when its element leaves the view", %{
      view: view,
      document: document
    } do
      view |> with_target("#graph") |> render_click("select", %{"id" => "emits:a"})

      overlay = %{"document_digest" => document["digest"], "nodes" => %{}, "relations" => %{}}
      send(view.pid, {:overlay, overlay})
      assert "is-selected" in classes(at(page(view), "data-ehg-relation", "emits:a"))

      send(view.pid, {:document, Map.update!(document, "relations", &Map.put(&1, "emits", []))})
      assert Enum.count(LazyHTML.query(page(view), ".ehg-panel, .is-selected")) == 0
    end

    test "an update that names only some attributes keeps the rest", %{
      view: view,
      document: document
    } do
      overlay = %{
        "document_digest" => document["digest"],
        "nodes" => %{"event:edge_cases:zażółć gęślą jaźń" => %{"occurrences" => 3}},
        "relations" => %{}
      }

      Phoenix.LiveView.send_update(view.pid, Canvas, id: "graph", overlay: overlay)
      assert page(view) |> LazyHTML.query(".ehg-count") |> LazyHTML.text() == "×3"

      Phoenix.LiveView.send_update(view.pid, Canvas, id: "graph", document: document)
      assert page(view) |> LazyHTML.query(".ehg-count") |> LazyHTML.text() == "×3"
    end
  end
end
