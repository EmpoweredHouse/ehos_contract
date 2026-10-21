defmodule EhOsContract.GraphRenderer.ViewTest do
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer.{Fixtures, View}

  defp card(view, id), do: Enum.find(view.nodes, &(&1.id == id))
  defp kinds(view), do: view.nodes |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()

  defp between(view, from, to),
    do: Enum.filter(view.relations, &(&1.from == from and &1.to == to))

  defp without_declared_in(document),
    do:
      update_in(document, ["nodes", "event"], fn events ->
        for e <- events, do: Map.delete(e, "declared_in")
      end)

  describe "all/1" do
    test "keeps every node of every fixture, each with the kind of its group" do
      for {name, document} <- Fixtures.documents() do
        view = View.all(document)

        assert Enum.map(view.nodes, & &1.id) |> Enum.sort() ==
                 Fixtures.nodes(document) |> Enum.map(& &1["id"]) |> Enum.sort(),
               name

        for node <- view.nodes,
            do: assert(node.facts in document["nodes"][node.kind], "#{name}: #{node.id}")
      end
    end

    test "keeps every relation whose two ends are nodes, and only those" do
      for {name, document} <- Fixtures.documents() do
        ids = MapSet.new(Fixtures.nodes(document), & &1["id"])
        view = View.all(document)

        expected =
          for r <- Fixtures.relations(document),
              r["from"] in ids and r["to"] in ids,
              do: r["id"]

        assert Enum.sort(Enum.map(view.relations, & &1.id)) == Enum.sort(expected), name
      end

      relations = View.all(Fixtures.document("edge_cases")).relations
      refute Enum.any?(relations, &(&1.id == "handled_by:dangling"))
    end

    test "takes kinds and types in name order, whatever order the map holds them in" do
      # A map of more than 32 keys is a hash map, whose order is not its keys': forty kinds of
      # one node each, and as many types of one relation, make the document's maps that large.
      many = for i <- 1..40, do: "kind_#{String.pad_leading("#{i}", 2, "0")}"
      nodes = Map.new(many, &{&1, [%{"id" => &1, "name" => &1, "label" => nil}]})

      relations =
        Map.new(many, &{"type_" <> &1, [%{"id" => "r_" <> &1, "from" => &1, "to" => "kind_01"}]})

      refute Map.keys(nodes) == Enum.sort(Map.keys(nodes))

      view = View.all(%{"nodes" => nodes, "relations" => relations})
      assert Enum.map(view.nodes, & &1.kind) == Enum.sort(many)
      assert Enum.map(view.relations, & &1.type) == Enum.sort(Map.keys(relations))
    end

    test "keeps each group in the document's order" do
      document = Fixtures.document("lending.circulation")
      commands = for %{kind: "command"} = node <- View.all(document).nodes, do: node.id

      assert commands == Enum.map(document["nodes"]["command"], & &1["id"])
    end
  end

  describe "views/1" do
    test "lists a contract's full graph, and each unit with its lifecycle" do
      assert View.views(Fixtures.document("lending.membership")) == [
               {:contract, "Full graph"},
               {{:unit, "unit:lending.membership:membership"},
                "aggregate membership — Membership"}
             ]

      assert {{:lifecycle, "unit:fulfilment.shipping:shipment"}, "Lifecycle — Shipment"} in View.views(
               Fixtures.document("fulfilment.shipping")
             )
    end

    test "lists a process module's picture" do
      assert View.views(Fixtures.document("process.fulfilment.order")) == [
               {:process, "Process — An order, from its placing to its delivery"}
             ]
    end

    test "lists a domain's context map and system" do
      assert View.views(Fixtures.document("domain.fulfilment")) == [
               {:context_map, "Context map"},
               {:system, "System"}
             ]
    end

    test "every view a fixture lists is built, and a unit it does not have is empty" do
      for {name, document} <- Fixtures.documents(), {spec, _title} <- View.views(document) do
        assert View.build(document, spec).nodes != [], "#{name}: #{inspect(spec)}"
      end

      document = Fixtures.document("lending.membership")
      assert View.build(document, {:unit, "unit:nowhere"}).nodes == []

      assert View.build(document, {:lifecycle, "unit:lending.membership:membership"}).nodes == []

      # A view of another kind of document than its own is empty.
      assert View.build(document, :process).nodes == []
      assert View.build(Fixtures.document("domain.fulfilment"), :process).nodes == []
    end
  end

  describe "around/2" do
    test "keeps a card, every card its relations reach, their boxes, and the relations between them" do
      view = View.contract(Fixtures.document("lending.circulation"))
      id = "command:lending.circulation:return_copy"
      around = View.around(view, id)

      reached =
        for r <- view.relations, r.from == id or r.to == id, end_id <- [r.from, r.to], do: end_id

      assert MapSet.new(around.nodes, & &1.id) ==
               MapSet.new([id | reached]) |> MapSet.intersection(MapSet.new(view.nodes, & &1.id))

      kept = MapSet.new(around.nodes ++ around.groups, & &1.id)
      boxes = MapSet.new(around.groups, & &1.id)
      assert Enum.all?(around.relations, &(&1.from in kept and &1.to in kept))
      assert Enum.all?(around.nodes, &(&1.group == nil or &1.group in boxes))
      assert length(around.nodes) < length(view.nodes)
    end

    test "keeps a group's cards, and leaves a view as it is for an id it does not draw" do
      view = View.contract(Fixtures.document("lending.circulation"))
      unit = "unit:lending.circulation:loan"
      members = for %{group: ^unit} = n <- view.nodes, do: n.id

      assert Enum.all?(
               members,
               &(&1 in MapSet.new(View.around(view, unit).nodes, fn n -> n.id end))
             )

      assert View.around(view, "nothing:here") == view
    end
  end

  describe "matches/2" do
    test "finds cards by label, name, kind or footer, ignoring case, and nothing for a blank query" do
      view = View.process(Fixtures.document("process.fulfilment.order"))

      assert View.matches(view, "  ") == nil
      assert View.matches(view, nil) == nil

      assert "event:fulfilment.warehouse:parcel_packed" in View.matches(view, "PARCEL_PACKED")
      assert "event:fulfilment.shipping:dispatched" in View.matches(view, "handed to the")

      by_contract = View.matches(view, "fulfilment.warehouse")
      assert by_contract != MapSet.new()
      assert Enum.all?(by_contract, &String.contains?(&1, "fulfilment.warehouse"))

      # An id's kind and context path are not the card's words: "event:" finds no card by
      # its id alone.
      assert View.matches(view, "event:fulfilment") == MapSet.new()
      assert View.matches(view, "no such thing") == MapSet.new()
    end
  end

  describe "legend/1" do
    test "lists the kinds of the cards the view draws, in a fixed order, and only those" do
      legend = View.legend(View.process(Fixtures.document("process.fulfilment.order")))

      assert legend.kinds == [
               {"actor", "actor"},
               {"event", "event"},
               {"external", "external"},
               {"process", "process"}
             ]
    end

    test "lists each look of an arrow the view draws, with what it means" do
      legend = View.legend(View.process(Fixtures.document("process.fulfilment.order")))
      looks = Enum.map(legend.lines, &elem(&1, 0))

      assert "thick" in looks
      assert "headless" in looks

      refute View.legend(View.contract(Fixtures.document("lending.circulation"))).lines
             |> Enum.any?(&(elem(&1, 0) == "thick"))
    end

    test "lists a card drawn other than its kind, only where the view has one" do
      process = View.legend(View.process(Fixtures.document("process.fulfilment.order")))
      assert process.variants == [{"terminal", "ends a run"}]

      assert View.legend(View.contract(Fixtures.document("lending.circulation"))).variants == []
    end

    test "explains a dotted line with no head as both dotted and headless" do
      view = %{nodes: [], relations: [%{line: "dotted", head: false}], groups: []}

      assert Enum.map(View.legend(view).lines, &elem(&1, 0)) == ["dotted", "headless"]
    end

    test "leaves out the start of a lifecycle, which says nothing" do
      document = Fixtures.document("fulfilment.shipping")
      [unit | _] = for u <- document["nodes"]["unit"], do: u["id"]
      kinds = Enum.map(View.legend(View.lifecycle(document, unit)).kinds, &elem(&1, 0))

      refute "start" in kinds
    end
  end

  describe "contract/1, the full graph" do
    test "puts each unit's commands and events in its group, and draws no other kind of fact" do
      document = Fixtures.document("lending.membership")
      view = View.contract(document)
      [unit] = document["nodes"]["unit"]

      assert view.direction == "LR"
      assert [%{id: id, kind: "unit", title: "Membership · aggregate"}] = view.groups
      assert id == unit["id"]

      members = for node <- view.nodes, node.group == id, do: node.id

      own =
        for kind <- ~w(command event), n <- document["nodes"][kind], n["unit"] == id, do: n["id"]

      assert Enum.sort(members) == Enum.sort(own)

      assert kinds(view) == ~w(actor command event query read_model)
    end

    test "says where an event is declared when no unit of the contract holds it" do
      packed = "event:fulfilment.shipping:parcel_packed"
      consumed = Fixtures.document("fulfilment.shipping")

      assert card(View.contract(consumed), packed).foot == "fulfilment.warehouse"

      # A document from before `declared_in` says it by the id `declared_as` names.
      before = without_declared_in(consumed)
      assert card(View.contract(before), packed).foot == "fulfilment.warehouse"

      received = View.contract(Fixtures.document("messaging"))
      assert card(received, "event:messaging:copy_lent").foot == "another application"

      bare =
        update_in(before, ["nodes", "event"], fn events ->
          for e <- events,
              do:
                if(e["declared_as"], do: %{e | "declared_as" => "event::parcel_packed"}, else: e)
        end)

      assert card(View.contract(bare), packed).foot == nil

      own = View.contract(Fixtures.document("lending.membership"))
      assert for(%{kind: "event"} = e <- own.nodes, do: e.foot) |> Enum.uniq() == [nil]
    end

    test "takes the contract an event is declared in from declared_in, before its id" do
      document =
        update_in(Fixtures.document("fulfilment.shipping"), ["nodes", "event"], fn events ->
          for e <- events,
              do: if(e["declared_as"], do: Map.put(e, "declared_in", "said.here"), else: e)
        end)

      assert card(View.contract(document), "event:fulfilment.shipping:parcel_packed").foot ==
               "said.here"
    end

    test "draws an event of another contract only where a reaction takes it" do
      view = View.contract(Fixtures.document("fulfilment.shipping"))
      packed = card(view, "event:fulfilment.shipping:parcel_packed")

      assert packed.group == nil

      assert [%{type: "handled_by", line: "dotted", words: "async"}] =
               between(view, packed.id, "policy:fulfilment.shipping:book_carrier")
    end

    test "says async on a dotted arrow after the transaction, and which of a manager's two is which" do
      view = View.contract(Fixtures.document("lending.circulation"))
      pm = "process_manager:lending.circulation:overdue_chase"
      timer = "timer:lending.circulation:overdue_chase:reminder"

      assert view |> between(pm, timer) |> Enum.map(&{&1.words, &1.line, &1.head}) |> Enum.sort() ==
               [{"sets · at start", "dotted", false}, {"sets · during the run", "dotted", false}]

      assert [%{words: "starts · async"}] =
               between(view, "event:lending.circulation:copy_lent", pm)

      assert [%{words: "during the run · async"}] =
               between(view, "event:lending.circulation:overdue_notice_sent", pm)

      assert [%{words: "ends · async"}] =
               between(view, "event:lending.circulation:copy_returned", pm)

      assert [%{words: "async", line: "dotted"}] =
               between(view, timer, "command:lending.circulation:send_overdue_notice")

      # A reaction in the transaction that records the event is a solid arrow saying nothing.
      view = View.contract(Fixtures.document("billing.subscriptions"))
      policy = "policy:billing.subscriptions:invoice_the_period"

      assert [%{line: "solid", words: nil}] =
               between(view, "event:billing.subscriptions:billing_period_closed", policy)

      assert [%{line: "solid", words: nil}] =
               between(view, policy, "command:billing.subscriptions:add_invoice_line")

      view = View.contract(Fixtures.document("billing.payments"))
      gateway = "external:Billing.Domain:payment_gateway"
      integration = "actor:Billing.Domain:gateway_integration"

      assert [%{words: "calls", line: "dotted", head: true}] =
               between(view, "effect:billing.payments:collect_payment", gateway)

      assert [%{words: "backed by", head: false}] = between(view, integration, gateway)

      assert [%{words: "records"}] =
               between(view, integration, "event:billing.payments:collected")
    end

    test "draws an external that gives a field its value, with the field on the arrow" do
      view = View.contract(Fixtures.document("edge_cases"))
      external = "external:EdgeCases.Domain:rejestr"

      assert [%{type: "gives", words: "gives numer", line: "dotted", head: true}] =
               between(view, external, "command:edge_cases:back\\slash")

      assert card(view, external)
    end
  end

  describe "process/1, a process module" do
    setup do
      document = Fixtures.document("process.fulfilment.order")
      [document: document, view: View.process(document)]
    end

    test "draws the stages top to bottom, in order, each after the one before", %{
      document: document,
      view: view
    } do
      stages = for s <- ~w(ordering picking shipping), do: "stage:fulfilment.order:#{s}"

      assert view.direction == "TB"
      assert Enum.map(view.groups, & &1.id) == stages

      assert Enum.map(view.groups, & &1.title) == [
               "Ordering · no order claimed inside",
               "Picking · no order claimed inside",
               "Shipping · no order claimed inside"
             ]

      assert for(%{type: "precedes"} = r <- view.relations, do: {r.from, r.to}) ==
               Enum.zip(Enum.drop(stages, -1), Enum.drop(stages, 1))

      # A stage of one event claims no order inside it, as it has none to claim.
      placed_alone =
        update_in(document, ["nodes", "event"], fn events ->
          Enum.reject(
            events,
            &(&1["stage"] == "stage:fulfilment.order:ordering" and
                &1["name"] != "placed")
          )
        end)

      assert hd(View.process(placed_alone).groups).title == "Ordering"
    end

    test "puts each event in its stage with its contract, the ends in a colour of their own", %{
      view: view
    } do
      delivered = card(view, "event:fulfilment.shipping:delivered")
      assert delivered.group == "stage:fulfilment.order:shipping"
      assert delivered.variant == "terminal"
      assert delivered.foot == "fulfilment.shipping"
      assert card(view, "event:fulfilment.shipping:booked").variant == nil

      placed = card(view, "event:fulfilment.orders:placed")
      assert placed.group == "stage:fulfilment.order:ordering"
      assert placed.foot == "fulfilment.orders"

      assert kinds(view) == ~w(actor event external process)
    end

    test "hangs the external system off the events resting on it, with no arrowhead", %{
      view: view
    } do
      carrier = "external:Fulfilment.Domain:carrier"
      assert card(view, carrier).group == nil
      resting = for r <- view.relations, r.to == carrier, do: {r.from, r.line, r.head}

      assert resting == [{"event:fulfilment.shipping:delivered", "dotted", false}]
    end

    test "hangs what a promise waits on off the event that opens it, with no arrowhead" do
      promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"
      carrier = "external:Fulfilment.Domain:carrier"
      waits = %{"id" => "waits_on:#{promise}:#{carrier}", "from" => promise, "to" => carrier}

      document =
        put_in(
          Fixtures.document("process.fulfilment.order"),
          ["relations", "waits_on"],
          [waits]
        )

      assert [arrow] = for(r <- View.process(document).relations, r.type == "waits_on", do: r)

      assert {arrow.from, arrow.to, arrow.words, arrow.line, arrow.head, arrow.facts} ==
               {"event:fulfilment.orders:payment_confirmed", carrier, "waits on", "dotted", false,
                waits}
    end

    test "draws the process with its run, and the actor accountable for it", %{view: view} do
      process = card(view, "process:fulfilment.order")
      assert process.group == nil
      assert process.lines == ["one run per order_id", "ends within 14 days"]

      assert [%{words: "accountable for", head: false}] =
               between(view, "actor:Fulfilment.Domain:dispatcher", process.id)
    end

    test "says a process's deadline, and that it is not confirmed", %{document: document} do
      timed =
        update_in(document, ["nodes", "process"], fn [p] ->
          [Map.put(p, "deadline", %{"amount" => 30, "unit" => "day", "unverified" => true})]
        end)

      assert card(View.process(timed), "process:fulfilment.order").lines ==
               ["one run per order_id", "ends within 30 days · not confirmed"]
    end

    test "draws the promise as a heavy arrow with its window, and its other way dotted" do
      view = View.process(Fixtures.order_with_other_way())
      opened = "event:fulfilment.orders:payment_confirmed"

      assert [%{type: "promise", words: "within 24 hours", line: "thick"} = promise] =
               between(view, opened, "event:fulfilment.shipping:dispatched")

      assert promise.facts["id"] ==
               "promise:fulfilment.order:dispatched_within_a_day_of_payment"

      assert [%{type: "or_else", words: "or else", line: "dotted"}] =
               between(view, opened, "event:fulfilment.orders:cancelled")
    end

    test "draws a stage nothing sits in", %{document: document} do
      emptied = put_in(document, ["nodes", "event"], [])

      view = View.process(emptied)
      assert length(view.groups) == 3
      assert view.nodes |> Enum.filter(&(&1.kind == "event")) == []
      assert Enum.count(view.relations, &(&1.type == "precedes")) == 2
    end
  end

  describe "unit/2, one unit" do
    # No unit of the case studies consults an event of another contract; in circulation's
    # variant the hold on a copy consults membership's member_registered.
    test "says which contract an event it consults from elsewhere is declared in" do
      hold = "unit:lending.circulation:copy_hold"
      event = "event:lending.circulation:member_registered"

      view = View.unit(Fixtures.circulation_variant(), hold)
      assert card(view, event).foot == "lending.membership"

      assert [%{words: "consulted by member_id"}] = between(view, event, hold)

      own = for %{kind: "event", facts: %{"unit" => ^hold}} = e <- view.nodes, do: e
      assert own != []
      assert Enum.all?(own, &(&1.foot == nil))
    end

    test "says which unit of the contract an event it consults from another unit is in" do
      hold = "unit:lending.circulation:copy_hold"
      view = View.unit(Fixtures.document("lending.circulation"), hold)

      assert card(view, "event:lending.circulation:copy_lent").foot == "Loan"
      assert card(view, "event:lending.circulation:withdrawn_from_circulation").foot == "Copy"
    end

    # Circulation's variant gives lending a copy a constraint, which no command of the case
    # studies has.
    test "lists the state's fields on its card, and counts the scenarios on each arrow" do
      document = Fixtures.circulation_variant()
      id = "unit:lending.circulation:loan"
      view = View.unit(document, id)
      state = card(view, id)

      assert state.tag == "aggregate"
      assert "loan_id: id · identity" in state.lines
      assert "fee_owed: boolean" in state.lines
      assert kinds(view) == ~w(command constraint event invariant unit)

      pinned =
        for s <- document["scenarios"]["unit"], c <- s["covers"], reduce: %{} do
          acc -> Map.update(acc, c, 1, &(&1 + 1))
        end

      for %{type: type} = r <- view.relations, type in ~w(emits refused_on) do
        count =
          case pinned[r.id] do
            nil -> nil
            1 -> "1 scenario"
            n -> "#{n} scenarios"
          end

        expected =
          if type == "refused_on",
            do: Enum.join(Enum.reject(["may be refused", count], &is_nil/1), " · "),
            else: count

        assert r.words == expected, r.id
      end

      assert Enum.all?(
               for(%{type: "builds"} = r <- view.relations, do: r.to == id and r.line == "dotted")
             )
    end

    test "draws a boundary's consulted events by the fields that match them" do
      id = "unit:lending.circulation:copy_hold"
      view = View.unit(Fixtures.document("lending.circulation"), id)

      assert card(view, id).tag == "dcb"

      assert [%{type: "consulted_by", words: "consulted by copy_id", line: "dotted"}] =
               between(view, "event:lending.circulation:copy_lent", id)

      assert card(view, "event:lending.circulation:copy_lent")
    end
  end

  describe "lifecycle/2" do
    setup do
      document = Fixtures.document("fulfilment.shipping")
      id = "unit:fulfilment.shipping:shipment"
      [document: document, id: id, view: View.lifecycle(document, id)]
    end

    test "starts at a dot of the unit's, and names each move by its event", %{view: view, id: id} do
      assert view.direction == "TB"
      assert [%{id: ^id, kind: "start", label: nil, name: nil, tag: nil} | statuses] = view.nodes
      assert Enum.map(statuses, & &1.kind) == ~w(status status status)
      assert card(view, "status:fulfilment.shipping:shipment:delivered").variant == "final"

      assert [%{type: "enters", words: "Shipment booked"}] =
               between(view, id, "status:fulfilment.shipping:shipment:booked")

      assert [%{type: "transition", words: "Parcel handed to the carrier", line: "solid"}] =
               between(
                 view,
                 "status:fulfilment.shipping:shipment:booked",
                 "status:fulfilment.shipping:shipment:dispatched"
               )
    end

    test "draws a move it does not allow, which the log saw, dotted from where it stood", c do
      overlay = %{
        "observed" => %{
          "relations" => %{
            "undeclared" => [
              %{
                "id" => "undeclared:a",
                "from" => c.id,
                "to" => c.id,
                "event" => "event:fulfilment.shipping:delivered"
              },
              %{
                "id" => "undeclared:b",
                "from" => "status:gone",
                "to" => c.id,
                "event" => "event:fulfilment.shipping:delivered"
              }
            ]
          }
        }
      }

      view = View.build(c.document, {:lifecycle, c.id}, overlay)

      assert [%{id: "undeclared:a", words: words, line: "dotted"}] =
               Enum.filter(view.relations, &(&1.type == "undeclared"))

      assert words == "Parcel delivered · not declared"
      assert View.build(c.document, {:lifecycle, c.id}, nil) == c.view
    end
  end

  describe "context_map/1 and system/1" do
    setup do
      [document: Fixtures.document("domain.fulfilment")]
    end

    test "draws the subdomains around their contexts, every external, and the patterns", c do
      view = View.context_map(c.document)

      assert Enum.map(view.groups, & &1.title) == ["Fulfilment · core", "Logistics · supporting"]

      assert card(view, "context:Fulfilment.Domain:orders").group ==
               "subdomain:Fulfilment.Domain:core"

      assert Enum.count(view.nodes, &(&1.kind == "external")) ==
               length(c.document["nodes"]["external"])

      assert kinds(view) == ~w(context external)

      assert [%{words: "customer supplier", head: true, line: "solid"}] =
               between(
                 view,
                 "context:Fulfilment.Domain:orders",
                 "context:Fulfilment.Domain:warehouse"
               )

      assert [%{words: "conformist", head: true}] =
               between(
                 view,
                 "external:Fulfilment.Domain:carrier",
                 "context:Fulfilment.Domain:shipping"
               )

      # No context of the case studies is in a pattern declared between its two ends, nor
      # keeps an anticorruption layer; the domain's variant has both.
      view = View.context_map(Fixtures.fulfilment_variant())

      assert [%{words: "partnership", head: false, line: "solid"}] =
               view
               |> between(
                 "context:Fulfilment.Domain:warehouse",
                 "context:Fulfilment.Domain:shipping"
               )
               |> Enum.filter(&(&1.type == "partnership"))

      assert [%{words: "anticorruption layer", head: true}] =
               between(
                 view,
                 "external:Fulfilment.Domain:carrier",
                 "context:Fulfilment.Domain:warehouse"
               )
    end

    test "draws the contracts in their contexts, and what one consumes from another", c do
      view = View.system(c.document)
      shipping = card(view, "contract:fulfilment.shipping")

      assert shipping.label == "Shipping"

      assert card(view, "contract:fulfilment.warehouse").label == "Warehouse"
      assert shipping.group == "context:Fulfilment.Domain:shipping"
      assert kinds(view) == ~w(actor contract process)

      assert Enum.find(view.groups, &(&1.id == shipping.group)).title == "Shipping · context"

      assert [%{words: "parcel_packed", line: "solid", head: true}] =
               view
               |> between("contract:fulfilment.warehouse", shipping.id)
               |> Enum.filter(&(&1.type == "consumed_by"))

      # Plan DD, L3 (#286): a contract keeping the number of a sibling's unit, drawn the
      # way the number travels, as a consumed event is.
      assert [%{words: "number of order", line: "dotted", head: true}] =
               between(view, "contract:fulfilment.orders", shipping.id)
    end

    # Plan DD, P2e (#220).
    test "draws each process module, the contracts whose events it includes, and who answers for it",
         c do
      view = View.system(c.document)
      order = card(view, "process:fulfilment.order")

      assert order.label == "An order, from its placing to its delivery"
      assert order.group == nil

      included =
        for %{type: "includes", from: "process:fulfilment.order"} = r <- view.relations,
            do: {r.to, r.words, r.line, r.head}

      assert Enum.sort(included) == [
               {"contract:fulfilment.orders", "includes", "dotted", true},
               {"contract:fulfilment.shipping", "includes", "dotted", true},
               {"contract:fulfilment.warehouse", "includes", "dotted", true}
             ]

      assert [%{words: "accountable for", head: false}] =
               between(view, "actor:Fulfilment.Domain:dispatcher", order.id)

      # Only an actor who answers for a process is drawn.
      assert for(%{kind: "actor"} = a <- view.nodes, do: a.id) == [
               "actor:Fulfilment.Domain:dispatcher"
             ]
    end
  end

  # Plan DD, L4 (#326): what a view draws for the business owner.
  describe "build/4 for the owner" do
    test "a card says its label alone, and nothing only the code reads is drawn" do
      for {name, document} <- Fixtures.documents(),
          {spec, _title} <- View.views(document),
          view = View.build(document, spec, nil, :owner) do
        where = "#{name} #{inspect(spec)}"

        assert Enum.all?(view.nodes, &(&1.label == nil or &1.name == nil)), where
        refute Enum.any?(view.nodes, &(&1.kind == "publication")), where
        refute Enum.any?(view.nodes, &(&1.foot && &1.foot =~ ~r/^[a-z_]+\.[a-z_.]+$/)), where
        refute Enum.any?(view.relations, &(&1.words && &1.words =~ ~r/async|one run per/)), where

        refute Enum.any?(view.nodes, fn n -> Enum.any?(n.lines, &(&1 =~ "one run per")) end),
               where
      end
    end

    test "a process's event says the context of its contract, and its card no key of a run" do
      # Each case study's context is labelled as its contract's module is named, so shipping
      # is labelled apart here, and the foot cannot be the module's last segment.
      document =
        Fixtures.relabel(Fixtures.document("process.fulfilment.order"), %{
          "context:Fulfilment.Domain:shipping" => "Dispatch"
        })

      view = View.build(document, :process, nil, :owner)

      event = Enum.find(view.nodes, &(&1.id == "event:fulfilment.shipping:dispatched"))
      assert event.label == "Parcel handed to the carrier"
      assert event.name == nil
      assert event.foot == "Dispatch"

      process = Enum.find(view.nodes, &(&1.kind == "process"))
      # The engineer reads "one run per order_id" there too; the owner reads the deadline alone.
      assert process.lines == ["ends within 14 days"]
    end

    test "an event received from another application, with no label, says where it comes from" do
      document =
        update_in(Fixtures.document("messaging"), ["nodes", "event"], fn events ->
          for e <- events,
              do: if(e["id"] == "event:messaging:copy_lent", do: %{e | "label" => nil}, else: e)
        end)

      card = card(View.build(document, :contract, nil, :owner), "event:messaging:copy_lent")

      assert card.label == "An event from another application"
      assert card.name == nil
    end

    test "the engineer's view is the one before the switch" do
      for {_name, document} <- Fixtures.documents(),
          {spec, _title} <- View.views(document),
          do: assert(View.build(document, spec, nil, :engineering) == View.build(document, spec))
    end
  end
end
