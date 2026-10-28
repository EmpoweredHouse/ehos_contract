defmodule EhOsContract.GraphRenderer.LandscapeTest do
  # Joining applications by the names on the wire: plan DD, stage G1 (#297). The billing
  # domain publishes its issued invoice; domain.ledger.json, hand-made, subscribes to it and to
  # a name nobody in the set publishes.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.{Canvas, Fixtures, Landscape, Lookup, Panel, View}

  @issued "publication:billing.invoice.issued.v1"
  @subscriptions "0/contract:billing.subscriptions"
  @bookkeeping "1/contract:ledger.bookkeeping"

  defp landscape,
    do:
      Landscape.join([
        {"billing", Fixtures.document("domain.billing")},
        {"ledger", Fixtures.document("domain.ledger")}
      ])

  defp ids(list), do: list |> Enum.map(& &1.id) |> Enum.sort()

  # The ledger with nothing on the wire: no publication, nothing it publishes or subscribes to.
  defp quiet_ledger do
    Fixtures.document("domain.ledger")
    |> put_in(["nodes", "publication"], [])
    |> put_in(["relations", "publishes"], [])
    |> put_in(["relations", "subscribed_by"], [])
  end

  test "joins a publication and its subscriber across applications into one card with an arrow on each side" do
    view = View.build(landscape(), :landscape)

    assert [publishes] = Enum.filter(view.relations, &(&1.to == @issued))
    assert publishes.from == @subscriptions
    assert publishes.words == "publishes issued"

    assert [subscribed] = Enum.filter(view.relations, &(&1.from == @issued))
    assert subscribed.to == @bookkeeping
    assert subscribed.words == "as invoice_issued"

    assert [_one] = Enum.filter(view.nodes, &(&1.id == @issued))
  end

  test "draws a box per domain with only the contracts on the wire, and says how many it leaves out" do
    view = View.build(landscape(), :landscape)

    assert ids(view.nodes) ==
             Enum.sort([
               @subscriptions,
               @bookkeeping,
               @issued,
               "publication:ledger.month.booked.v1",
               "publication:payroll.run.closed.v1"
             ])

    titles = Map.new(view.groups, &{&1.id, &1.title})

    assert titles["0/domain:Billing.Domain"] == "billing · billing · 1 more contract"
    assert titles["1/domain:Ledger.Domain"] == "ledger · ledger · 1 more contract"

    subscriptions = Enum.find(view.nodes, &(&1.id == @subscriptions))

    assert {subscriptions.group, subscriptions.label} ==
             {"0/domain:Billing.Domain", "Subscriptions"}
  end

  test "draws a domain with nothing on the wire as an empty box, saying how many contracts it has" do
    joined =
      Landscape.join([
        {"billing", Fixtures.document("domain.billing")},
        {"ledger", quiet_ledger()}
      ])

    view = View.build(joined, :landscape)
    titles = Map.new(view.groups, &{&1.id, &1.title})

    assert titles["1/domain:Ledger.Domain"] == "ledger · ledger · 2 contracts"
    assert titles["0/domain:Billing.Domain"] == "billing · billing · 1 more contract"
    assert Enum.filter(view.nodes, &(&1.group == "1/domain:Ledger.Domain")) == []
  end

  test "a landscape of one domain with nothing on the wire is its box alone" do
    view = View.build(Landscape.join([{"ledger", quiet_ledger()}]), :landscape)

    assert [%{id: "0/domain:Ledger.Domain", title: "ledger · ledger · 2 contracts"}] = view.groups
    assert view.nodes == []
    assert view.relations == []
  end

  describe "an application the host has no domain document of" do
    # Billing with its document, an application the host knows of without one, and the
    # ledger: the boxes in the order of the entries.
    defp with_undescribed,
      do:
        Landscape.join([
          {"billing", Fixtures.document("domain.billing")},
          {"office", :none},
          {"ledger", Fixtures.document("domain.ledger")}
        ])

    test "has a box of its own, saying no graph describes it, in the place of its entry" do
      view = View.build(with_undescribed(), :landscape)

      assert Enum.map(view.groups, &{&1.id, &1.kind, &1.title}) == [
               {"0/domain:Billing.Domain", "domain", "billing · billing · 1 more contract"},
               {"1/application:office", "application", "office · no graph described"},
               {"2/domain:Ledger.Domain", "domain", "ledger · ledger · 1 more contract"}
             ]

      assert Enum.filter(view.nodes, &(&1.group == "1/application:office")) == []
      refute Enum.any?(view.relations, &("1/application:office" in [&1.from, &1.to]))
    end

    test "joins the others as it would without it" do
      without =
        Landscape.join([
          {"billing", Fixtures.document("domain.billing")},
          {"ledger", Fixtures.document("domain.ledger")}
        ])

      shown = View.build(with_undescribed(), :landscape)
      relabelled = &String.replace(&1, ~r{^2/}, "1/")

      assert Enum.map(shown.relations, &{relabelled.(&1.from), relabelled.(&1.to)}) ==
               Enum.map(View.build(without, :landscape).relations, &{&1.from, &1.to})
    end

    test "is in the digest" do
      refute with_undescribed()["digest"] == landscape()["digest"]
      assert with_undescribed()["digest"] == with_undescribed()["digest"]
    end

    test "a landscape of such applications alone is their boxes" do
      view = View.build(Landscape.join([{"office", :none}]), :landscape)

      assert [%{id: "0/application:office", kind: "application"}] = view.groups
      assert view.nodes == []
    end

    test "its panel says why it is drawn without its contracts" do
      document = with_undescribed()
      group = Enum.find(View.build(document, :landscape).groups, &(&1.kind == "application"))

      html =
        render_component(&Panel.panel/1,
          picked: {:group, group},
          lookup: Lookup.new(document),
          target: "#graph"
        )
        |> LazyHTML.from_fragment()

      assert LazyHTML.text(LazyHTML.query(html, "header h4")) == "office"
      assert LazyHTML.text(LazyHTML.query(html, ".ehg-panel-kind")) == "application"
      assert LazyHTML.text(html) =~ "No document describes this application's domain"
      # Nothing in it is a finding, which `ehg-empty` draws in the colour of an error.
      assert Enum.to_list(LazyHTML.query(html, ".ehg-empty")) == []
    end

    test "the canvas draws its box apart from a domain's" do
      html =
        render_component(Canvas, id: "landscape", document: with_undescribed(), view: :landscape)
        |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(html, ~s([data-ehg-group][data-kind="application"]))) == 1
      assert Enum.count(LazyHTML.query(html, ~s([data-ehg-group][data-kind="domain"]))) == 2
    end

    test "refuses anything but a document or :none beside an application" do
      assert_raise ArgumentError,
                   ~r/joins \{application, domain document\} and \{application, :none\} pairs, got nil/,
                   fn ->
                     Landscape.join([{"office", nil}])
                   end

      assert_raise ArgumentError, ~r/names each application by a string, got :office/, fn ->
        Landscape.join([{:office, :none}])
      end
    end
  end

  test "says a name nobody in the set publishes comes from outside it, and no other" do
    tags = Map.new(View.build(landscape(), :landscape).nodes, &{&1.id, &1.tag})

    assert tags["publication:payroll.run.closed.v1"] == "publication · from outside the set"
    assert tags[@issued] == "publication"
    assert tags["publication:ledger.month.booked.v1"] == "publication"
  end

  test "joins two domains of one application as it joins two applications" do
    joined =
      Landscape.join([
        {"one", Fixtures.document("domain.billing")},
        {"one", Fixtures.document("domain.ledger")}
      ])

    view = View.build(joined, :landscape)

    assert [%{from: "0/contract:billing.subscriptions"}] =
             Enum.filter(view.relations, &(&1.to == @issued))

    assert length(view.groups) == 2
  end

  test "keeps contracts of the same id in two applications apart" do
    billing = Fixtures.document("domain.billing")
    view = View.build(Landscape.join([{"a", billing}, {"b", billing}]), :landscape)

    assert "0/contract:billing.subscriptions" in ids(view.nodes)
    assert "1/contract:billing.subscriptions" in ids(view.nodes)
    assert length(Enum.filter(view.relations, &(&1.to == @issued))) == 2
  end

  test "a domain on its own is a landscape too, its publication with nobody to take it" do
    view =
      View.build(
        Landscape.join([{"billing", Fixtures.document("domain.billing")}]),
        :landscape
      )

    assert ids(view.nodes) == Enum.sort([@subscriptions, @issued])
    assert [%{type: "publishes"}] = view.relations
  end

  test "keeps the same document given twice apart, every id once" do
    billing = Fixtures.document("domain.billing")
    view = View.build(Landscape.join([{"a", billing}, {"a", billing}]), :landscape)
    ids = Enum.map(view.nodes ++ view.groups ++ view.relations, & &1.id)

    assert ids == Enum.uniq(ids)
    assert length(view.groups) == 2
  end

  test "takes a publication's words from the document that publishes it, not from a subscriber" do
    ledger =
      update_in(Fixtures.document("domain.ledger"), ["nodes", "publication"], fn ps ->
        for p <- ps, do: %{p | "label" => "Spoofed", "source" => "spoofed"}
      end)

    billing =
      update_in(Fixtures.document("domain.billing"), ["nodes", "publication"], fn ps ->
        for p <- ps, do: %{p | "label" => "Invoice issued"}
      end)

    joined = Landscape.join([{"ledger", ledger}, {"billing", billing}])
    issued = Enum.find(joined["nodes"]["publication"], &(&1["id"] == @issued))

    assert issued["label"] == "Invoice issued"
    assert issued["source"] == nil
  end

  test "leaves out what a document holds in a shape graph.v1 does not give it, and draws the rest" do
    broken = %{
      "kind" => "domain",
      "name" => %{"not" => "text"},
      "domain" => "Broken.Domain",
      "nodes" => %{
        "contract" => [
          nil,
          7,
          %{"name" => "no id"},
          %{"id" => "contract:broken.c", "name" => "broken.c", "module" => %{"x" => 1}}
        ],
        "publication" => [
          %{"id" => "publication:Broken.Domain:", "name" => ""},
          %{"id" => "publication:Broken.Domain:x", "name" => %{}},
          %{
            "id" => "publication:Broken.Domain:ok",
            "name" => "billing.invoice.issued.v1"
          }
        ],
        "event" => "not a list"
      },
      "relations" => %{
        "publishes" => [nil, %{"id" => "p", "from" => nil, "to" => "publication:Broken.Domain:x"}],
        "subscribed_by" => [
          %{
            "id" => "s",
            "from" => "publication:Broken.Domain:ok",
            "to" => "contract:broken.c",
            "as" => %{"x" => 1}
          }
        ]
      }
    }

    joined =
      Landscape.join([{"billing", Fixtures.document("domain.billing")}, {"broken", broken}])

    view = View.build(joined, :landscape)

    assert "1/contract:broken.c" in ids(view.nodes)
    assert Enum.map(joined["nodes"]["publication"], & &1["id"]) == [@issued]
    assert [%{to: "1/contract:broken.c"}] = Enum.filter(view.relations, &(&1.from == @issued))

    assert render_component(Canvas, id: "landscape", document: joined, view: :landscape) =~
             "broken.c"

    assert Landscape.join([{"broken", %{"kind" => "domain", "nodes" => [], "relations" => "x"}}])[
             "nodes"
           ]["contract"] == []
  end

  test "has a digest that names the documents it is of" do
    assert landscape()["digest"] == landscape()["digest"]

    refute Landscape.join([{"billing", Fixtures.document("domain.billing")}])["digest"] ==
             landscape()["digest"]
  end

  test "refuses an application named by anything but a string, saying so" do
    assert_raise ArgumentError, ~r/names each application by a string, got :billing/, fn ->
      Landscape.join([{:billing, Fixtures.document("domain.billing")}])
    end
  end

  test "refuses a document that is not a domain's" do
    assert_raise ArgumentError,
                 ~r/joins \{application, domain document\} and \{application, :none\} pairs, got "contract"/,
                 fn ->
                   Landscape.join([{"billing", Fixtures.document("billing.payments")}])
                 end
  end

  test "names an application's first box, a domain's or one no graph describes, for a host to select" do
    joined =
      Landscape.join([
        {"billing", Fixtures.document("domain.billing")},
        {"office", :none},
        {"ledger", Fixtures.document("domain.ledger")}
      ])

    assert Landscape.box(joined, "ledger") == "2/domain:Ledger.Domain"
    assert Landscape.box(joined, "office") == "1/application:office"
    assert Landscape.box(joined, "nobody") == nil
    assert Landscape.box(%{"kind" => "landscape"}, "ledger") == nil
    # A host may pass what a reader's address gave it: anything but a name names no box.
    assert Landscape.box(joined, ["ledger"]) == nil
  end

  # A landscape a host built or read back holds ids it did not make: one led by more digits than
  # a place has is read as none, never parsed into a number too large for the VM.
  test "reads an id led by too many digits as no place, in its view and its box" do
    long = String.duplicate("9", 2_000_000) <> "/application:office"

    landscape = %{
      "kind" => "landscape",
      "nodes" => %{
        "domain" => [],
        "application" => [%{"id" => long, "application" => "office", "label" => "office"}]
      }
    }

    assert [%{id: ^long}] = View.build(landscape, :landscape).groups
    assert Landscape.box(landscape, "office") == long
  end

  test "is the one view of a landscape, which no other view draws" do
    assert View.views(landscape()) == [{:landscape, "Landscape"}]
    assert View.build(Fixtures.document("domain.billing"), :landscape).nodes == []
  end

  test "every element has a panel, naming only what the landscape holds, the events it names among them" do
    document = landscape()
    lookup = Lookup.new(document)
    view = View.build(document, :landscape)

    events =
      for e <- document["nodes"]["event"],
          do: {:node, View.all(document).nodes |> Enum.find(&(&1.id == e["id"]))}

    for picked <-
          Enum.map(view.nodes, &{:node, &1}) ++
            Enum.map(view.groups, &{:group, &1}) ++
            Enum.map(view.relations, &{:relation, &1}) ++ events do
      html =
        render_component(&Panel.panel/1, picked: picked, lookup: lookup, target: "#graph")
        |> LazyHTML.from_fragment()

      where = elem(picked, 1).id
      assert Enum.count(LazyHTML.query(html, "aside.ehg-panel")) == 1, where
      assert html |> LazyHTML.query("span.ehg-ref") |> Enum.to_list() == [], where
    end
  end

  describe "a host's link out of the landscape" do
    import Phoenix.ConnTest, only: [build_conn: 0]

    @endpoint EhOsContract.GraphRenderer.TestEndpoint

    # A host's page per domain of an application, and a contract in it; and links a host
    # could get wrong. Public, since the test LiveView calls them.
    def to_page(application, domain, nil), do: "/apps/#{application}/domains/#{domain}"

    def to_page(application, domain, contract),
      do: "/apps/#{application}/domains/#{domain}?contract=#{contract}"

    def to_application(application, nil, nil), do: "/apps/#{application}"
    def contracts_only(_application, _domain, contract), do: contract && "/c/#{contract}"
    def script(_application, _domain, _contract), do: "javascript:alert(1)"
    def shouted_script(_application, _domain, _contract), do: "JavaScript:alert(1)"
    def not_an_address(_application, _domain, _contract), do: :not_an_address
    def elsewhere(_application, _domain, _contract), do: "https://console.example/x"
    def off_site(_application, _domain, _contract), do: "//evil.example/x"
    def hostless(_application, _domain, _contract), do: "https:evil.example"
    def raising(_application, _domain, _contract), do: raise("no such application")

    defp drawn(link, document \\ landscape()) do
      {:ok, view, _html} =
        live_isolated(build_conn(), EhOsContract.GraphRenderer.TestLive,
          session: %{"document" => document, "view" => :landscape, "link" => link}
        )

      view
    end

    defp offered(view, selector) do
      view |> element(selector) |> render_click()

      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".ehg-panel a.ehg-open")
      |> Enum.map(&{LazyHTML.attribute(&1, "href") |> hd(), LazyHTML.text(&1)})
    end

    @box ~s([data-ehg-group="1/domain:Ledger.Domain"] button.ehg-group-title)
    @card ~s(button[data-ehg-node="1/contract:ledger.bookkeeping"])

    test "a domain's box and a contract in it open the host's page of that domain" do
      view = drawn({__MODULE__, :to_page})

      assert offered(view, @box) == [{"/apps/ledger/domains/Ledger.Domain", "Open this domain →"}]

      assert offered(view, @card) == [
               {"/apps/ledger/domains/Ledger.Domain?contract=ledger.bookkeeping",
                "Open this contract →"}
             ]

      # A publication is between the domains, and leads to none of them.
      assert offered(view, ~s(button[data-ehg-node="#{@issued}"])) == []
      refute has_element?(view, "[style]")
    end

    test "an empty box opens the host's page of its domain" do
      view = drawn({__MODULE__, :to_page}, Landscape.join([{"ledger", quiet_ledger()}]))
      box = ~s([data-ehg-group="0/domain:Ledger.Domain"] button.ehg-group-title)

      assert offered(view, box) == [{"/apps/ledger/domains/Ledger.Domain", "Open this domain →"}]
    end

    test "a box of an application with no document opens the host's page of the application" do
      document = Landscape.join([{"ledger", quiet_ledger()}, {"office", :none}])
      box = ~s([data-ehg-group="1/application:office"] button.ehg-group-title)

      assert offered(drawn({__MODULE__, :to_application}, document), box) ==
               [{"/apps/office", "Open this application →"}]

      # A host whose link raises for an application offers nothing for it.
      assert offered(drawn({__MODULE__, :raising}, document), box) == []
    end

    test "offers nothing where the host's link raises, and the page goes on" do
      view = drawn({__MODULE__, :raising})

      assert offered(view, @card) == []
      assert has_element?(view, ".ehg-panel")
    end

    test "offers nothing without a link, where the host has no page, or for an address that is not one" do
      assert offered(drawn(nil), @box) == []
      refute has_element?(drawn(nil), "button.ehg-open")

      assert offered(drawn({__MODULE__, :contracts_only}), @box) == []
      assert offered(drawn({__MODULE__, :script}), @card) == []
      assert offered(drawn({__MODULE__, :shouted_script}), @card) == []
      assert offered(drawn({__MODULE__, :not_an_address}), @card) == []
      assert offered(drawn({__MODULE__, :off_site}), @card) == []
      assert offered(drawn({__MODULE__, :hostless}), @card) == []

      assert offered(drawn({__MODULE__, :elsewhere}), @card) == [
               {"https://console.example/x", "Open this contract →"}
             ]
    end
  end

  test "the canvas draws it, the publication's card between the two boxes" do
    html =
      render_component(Canvas, id: "landscape", document: landscape(), view: :landscape)
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(html, ~s([data-ehg-node="#{@issued}"]))) == 1
    assert Enum.count(LazyHTML.query(html, "[data-ehg-group]")) == 2
    assert Enum.count(LazyHTML.query(html, "[style]")) == 0
  end

  test "the canvas draws a domain with nothing on the wire as its box" do
    html =
      render_component(Canvas,
        id: "landscape",
        document: Landscape.join([{"ledger", quiet_ledger()}]),
        view: :landscape
      )
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(html, ~s([data-ehg-group="0/domain:Ledger.Domain"]))) == 1
    assert Enum.count(LazyHTML.query(html, "[data-ehg-node]")) == 0
  end
end
