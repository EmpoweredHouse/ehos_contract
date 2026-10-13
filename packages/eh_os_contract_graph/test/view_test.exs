defmodule EhOsContract.GraphRenderer.ViewTest do
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer.{Fixtures, View}

  defp card(view, id), do: Enum.find(view.nodes, &(&1.id == id))
  defp kinds(view), do: view.nodes |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()

  defp between(view, from, to),
    do: Enum.filter(view.relations, &(&1.from == from and &1.to == to))

  describe "all/1" do
    test "keeps every node of every fixture, each with the kind of its group" do
      for name <- Fixtures.names() do
        document = Fixtures.document(name)
        view = View.all(document)

        assert Enum.map(view.nodes, & &1.id) |> Enum.sort() ==
                 Fixtures.nodes(document) |> Enum.map(& &1["id"]) |> Enum.sort(),
               name

        for node <- view.nodes,
            do: assert(node.facts in document["nodes"][node.kind], "#{name}: #{node.id}")
      end
    end

    test "keeps every relation whose two ends are nodes, and only those" do
      for name <- Fixtures.names() do
        document = Fixtures.document(name)
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
      document = Fixtures.document("rehmed.settlement")
      commands = for %{kind: "command"} = node <- View.all(document).nodes, do: node.id

      assert commands == Enum.map(document["nodes"]["command"], & &1["id"])
    end
  end

  describe "views/1" do
    test "lists a contract's declared shape, its full graph, and each unit with its lifecycle" do
      assert View.views(Fixtures.document("rehmed.statutory_reporting")) == [
               {:declared,
                "Declared shape — Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego"},
               {:contract, "Full graph"},
               {{:unit, "unit:rehmed.statutory_reporting:p1_report"},
                "aggregate p1_report — Zgłoszenie P1"}
             ]

      assert {{:lifecycle, "unit:appunite_equipment.demands:demand"},
              "Lifecycle — Zapotrzebowanie na komputer"} in View.views(
               Fixtures.document("appunite_equipment.demands")
             )
    end

    test "lists a domain's context map and system" do
      assert View.views(Fixtures.document("domain.rehmed")) == [
               {:context_map, "Context map"},
               {:system, "System"}
             ]
    end

    test "every view a fixture lists is built, and a unit it does not have is empty" do
      for name <- Fixtures.names(), {spec, _title} <- View.views(Fixtures.document(name)) do
        assert View.build(Fixtures.document(name), spec).nodes != [], "#{name}: #{inspect(spec)}"
      end

      document = Fixtures.document("rehmed.settlement")
      assert View.build(document, {:unit, "unit:nowhere"}).nodes == []

      assert View.build(document, {:lifecycle, "unit:rehmed.settlement:visit_settlement"}).nodes ==
               []

      assert View.build(document, :declared).nodes == []
    end
  end

  describe "contract/1, the full graph" do
    test "puts each unit's commands and events in its group, and draws no other kind of fact" do
      document = Fixtures.document("rehmed.settlement")
      view = View.contract(document)
      [unit] = document["nodes"]["unit"]

      assert view.direction == "LR"
      assert [%{id: id, kind: "unit", title: "Rozliczenie wizyty · aggregate"}] = view.groups
      assert id == unit["id"]

      members = for node <- view.nodes, node.group == id, do: node.id

      own =
        for kind <- ~w(command event), n <- document["nodes"][kind], n["unit"] == id, do: n["id"]

      assert Enum.sort(members) == Enum.sort(own)

      assert kinds(view) == ~w(actor command event query read_model)
    end

    test "draws an event of another contract only where a reaction takes it" do
      view = View.contract(Fixtures.document("appunite_equipment.demands"))
      issued = card(view, "event:appunite_equipment.demands:issued")

      assert issued.group == nil

      assert [%{line: "solid", words: nil}] =
               between(view, issued.id, "policy:appunite_equipment.demands:fulfil_on_issue")
    end

    test "says async on a dotted arrow after the transaction, and which of a manager's two is which" do
      view = View.contract(Fixtures.document("taxvision.registry_watch"))
      pm = "process_manager:taxvision.registry_watch:monthly_registry_check"
      timer = "timer:taxvision.registry_watch:monthly_registry_check:next_month"
      event = "event:taxvision.registry_watch:data_completeness_confirmed"

      assert view |> between(pm, timer) |> Enum.map(&{&1.words, &1.line, &1.head}) |> Enum.sort() ==
               [{"sets · at start", "dotted", false}, {"sets · during the run", "dotted", false}]

      assert view |> between(event, pm) |> Enum.map(& &1.words) |> Enum.sort() ==
               ["during the run · async", "starts · async"]

      assert [%{words: "async", line: "dotted"}] =
               between(view, timer, "command:taxvision.registry_watch:check_registries")

      assert [%{words: "calls", line: "dotted", head: true}] =
               between(
                 view,
                 "effect:taxvision.registry_watch:look_up_registries",
                 "external:Taxvision.Domain:registries"
               )

      assert [%{words: "backed by", head: false}] =
               between(
                 view,
                 "actor:Taxvision.Domain:registry_integration",
                 "external:Taxvision.Domain:registries"
               )

      assert [%{words: "records"}] =
               between(
                 view,
                 "actor:Taxvision.Domain:registry_integration",
                 "event:taxvision.registry_watch:registry_status_checked"
               )
    end

    test "draws an external that gives a field its value, with the field on the arrow" do
      view = View.contract(Fixtures.document("edge_cases"))
      external = "external:EdgeCases.Domain:rejestr"

      assert [%{type: "gives", words: "gives numer", line: "dotted", head: true}] =
               between(view, external, "command:edge_cases:back\\slash")

      assert card(view, external)
    end
  end

  describe "declared/1, the declared shape" do
    setup do
      [view: View.declared(Fixtures.document("rehmed.statutory_reporting"))]
    end

    test "draws the stages top to bottom, in order, each after the one before", %{view: view} do
      stages =
        for s <- ~w(departure closing reporting),
            do: "stage:rehmed.statutory_reporting:clinical_visit:#{s}"

      assert view.direction == "TB"
      assert Enum.map(view.groups, & &1.id) == stages

      assert Enum.map(view.groups, & &1.title) ==
               ["departure", "closing", "reporting · no order claimed inside"]

      assert for(%{type: "precedes"} = r <- view.relations, do: {r.from, r.to}) ==
               Enum.zip(Enum.drop(stages, -1), Enum.drop(stages, 1))
    end

    test "puts each event in its stage, the ends in a colour of their own", %{view: view} do
      sent = card(view, "event:rehmed.statutory_reporting:p1_report_sent")
      assert sent.group == "stage:rehmed.statutory_reporting:clinical_visit:reporting"
      assert sent.variant == "terminal"
      assert card(view, "event:rehmed.statutory_reporting:p1_report_queued").variant == nil
      assert card(view, "event:rehmed.statutory_reporting:visit_completed").group =~ "departure"
      assert kinds(view) == ~w(event external)
    end

    test "draws the promise as a heavy arrow with its window, and its other way dotted", %{
      view: view
    } do
      opened = "event:rehmed.statutory_reporting:visit_completed"

      assert [%{type: "promise", words: "within 2 days", line: "thick"}] =
               between(view, opened, "event:rehmed.statutory_reporting:p1_report_sent")

      assert [%{type: "or_else", words: "or else", line: "dotted"}] =
               between(view, opened, "event:rehmed.statutory_reporting:p1_reporting_not_required")
    end

    test "hangs the external system off the events resting on it, with no arrowhead", %{
      view: view
    } do
      p1 = "external:Rehmed.Domain:p1"
      resting = for r <- view.relations, r.to == p1, do: {r.from, r.line, r.head}

      assert Enum.sort(resting) == [
               {"event:rehmed.statutory_reporting:p1_report_failed", "dotted", false},
               {"event:rehmed.statutory_reporting:p1_report_sent", "dotted", false}
             ]
    end

    test "draws a stage nothing sits in" do
      document = Fixtures.document("rehmed.statutory_reporting")

      emptied =
        update_in(document, ["nodes", "event"], fn events ->
          Enum.map(events, &Map.put(&1, "stage", nil))
        end)

      view = View.declared(emptied)
      assert length(view.groups) == 3
      assert view.nodes |> Enum.filter(&(&1.kind == "event")) == []
      assert Enum.count(view.relations, &(&1.type == "precedes")) == 2
    end
  end

  describe "unit/2, one unit" do
    test "lists the state's fields on its card, and counts the scenarios on each arrow" do
      document = Fixtures.document("rehmed.settlement")
      id = "unit:rehmed.settlement:visit_settlement"
      view = View.unit(document, id)
      state = card(view, id)

      assert state.tag == "aggregate"
      assert "visit_id: id · identity" in state.lines
      assert "scope_changed: boolean" in state.lines
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
      id = "unit:rehmed.external_payers:payer_period"
      view = View.unit(Fixtures.document("rehmed.external_payers"), id)

      assert card(view, id).tag == "dcb"

      assert [%{type: "consulted_by", words: "consulted by payer_id, period_id", line: "dotted"}] =
               between(view, "event:rehmed.external_payers:visit_charged_to_payer", id)

      assert card(view, "event:rehmed.external_payers:visit_charged_to_payer")
    end
  end

  describe "lifecycle/2" do
    setup do
      document = Fixtures.document("appunite_equipment.demands")
      id = "unit:appunite_equipment.demands:demand"
      [document: document, id: id, view: View.lifecycle(document, id)]
    end

    test "starts at a dot of the unit's, and names each move by its event", %{view: view, id: id} do
      assert view.direction == "TB"
      assert [%{id: ^id, kind: "start", label: nil, name: nil, tag: nil} | statuses] = view.nodes
      assert Enum.map(statuses, & &1.kind) == ~w(status status status)
      assert card(view, "status:appunite_equipment.demands:demand:fulfilled").variant == "final"

      assert [%{type: "enters", words: "Otwarto zapotrzebowanie na komputer"}] =
               between(view, id, "status:appunite_equipment.demands:demand:open")

      assert [%{type: "transition", words: "Zamówiono komputer w Innergo", line: "solid"}] =
               between(
                 view,
                 "status:appunite_equipment.demands:demand:open",
                 "status:appunite_equipment.demands:demand:ordered"
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
                "event" => "event:appunite_equipment.demands:fulfilled"
              },
              %{
                "id" => "undeclared:b",
                "from" => "status:gone",
                "to" => c.id,
                "event" => "event:appunite_equipment.demands:fulfilled"
              }
            ]
          }
        }
      }

      view = View.build(c.document, {:lifecycle, c.id}, overlay)

      assert [%{id: "undeclared:a", words: words, line: "dotted"}] =
               Enum.filter(view.relations, &(&1.type == "undeclared"))

      assert words == "Wydano komputer — zapotrzebowanie zaspokojone · not declared"
      assert View.build(c.document, {:lifecycle, c.id}, nil) == c.view
    end
  end

  describe "context_map/1 and system/1" do
    setup do
      [document: Fixtures.document("domain.rehmed")]
    end

    test "draws the subdomains around their contexts, every external, and the patterns", c do
      view = View.context_map(c.document)

      assert Enum.map(view.groups, & &1.title) == [
               "Rdzeń · core",
               "Wsparcie · supporting",
               "Ogólne · generic"
             ]

      assert card(view, "context:Rehmed.Domain:scheduling").group ==
               "subdomain:Rehmed.Domain:core"

      assert Enum.count(view.nodes, &(&1.kind == "external")) ==
               length(c.document["nodes"]["external"])

      assert kinds(view) == ~w(context external)

      assert [%{words: "partnership", head: false, line: "solid"}] =
               between(
                 view,
                 "context:Rehmed.Domain:scheduling",
                 "context:Rehmed.Domain:clinical_documentation"
               )

      assert [%{words: "anticorruption layer", head: true}] =
               between(
                 view,
                 "external:Rehmed.Domain:payer_system",
                 "context:Rehmed.Domain:external_payers"
               )
    end

    test "draws the contracts in their contexts, and what one consumes from another", c do
      view = View.system(c.document)
      reporting = card(view, "contract:rehmed.statutory_reporting")

      assert reporting.label ==
               "StatutoryReporting · Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego"

      assert card(view, "contract:rehmed.settlement").label == "Settlement"
      assert reporting.group == "context:Rehmed.Domain:statutory_reporting"
      assert kinds(view) == ~w(contract)

      assert Enum.find(view.groups, &(&1.id == reporting.group)).title ==
               "Zgodność i sprawozdawczość · context"

      assert [%{words: "visit_completed", line: "solid", head: true}] =
               view
               |> between("contract:rehmed.scheduling", reporting.id)
               |> Enum.filter(&(&1.type == "consumed_by"))

      # Plan DD, L3 (#286): a contract keeping the number of a sibling's unit, drawn the
      # way the number travels, as a consumed event is.
      assert [%{words: "number of visit", line: "dotted", head: true}] =
               between(view, "contract:rehmed.scheduling", "contract:rehmed.settlement")
    end
  end
end
