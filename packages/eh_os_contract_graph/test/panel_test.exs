defmodule EhOsContract.GraphRenderer.PanelTest do
  # The panels of plan E13b, batch 4, on the fixture documents: each says what the working
  # plan's point asks of it, from the document alone. The client's words are the fixtures'.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.{Actors, Fixtures, Lookup, Panel, TestLive, View}

  @endpoint EhOsContract.GraphRenderer.TestEndpoint

  # The panel of an element of `view`, as the canvas shows it.
  defp panel(document, picked) do
    render_component(&Panel.panel/1,
      picked: picked,
      lookup: Lookup.new(document),
      target: "#graph"
    )
  end

  # What a reader sees in the panel `id` opens in `spec`, through a canvas, with `overlay`,
  # as `audience` reads it.
  defp open(name_or_document, id, spec \\ :all, overlay \\ nil, audience \\ :engineering) do
    document =
      if is_map(name_or_document),
        do: name_or_document,
        else: Fixtures.document(name_or_document)

    {:ok, live, _html} =
      live_isolated(build_conn(), TestLive,
        session: %{
          "document" => document,
          "view" => spec,
          "overlay" => overlay,
          "audience" => audience
        }
      )

    live |> with_target("#graph") |> render_click("select", %{"id" => id})
    live |> element(".ehg-panel") |> render() |> text()
  end

  # The text a reader sees, each element's apart, with its entities read back.
  defp text(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.split()
    |> Enum.join(" ")
    |> String.replace(~r/ ([,.:])/, "\\1")
    |> String.replace(["&amp;", "&lt;", "&gt;", "&quot;", "&#39;"], fn
      "&amp;" -> "&"
      "&lt;" -> "<"
      "&gt;" -> ">"
      "&quot;" -> ~s(")
      "&#39;" -> "'"
    end)
  end

  test "every element of every view of every fixture has a panel, naming only what can be selected" do
    for {name, document} <- Fixtures.documents(),
        lookup = Lookup.new(document),
        {spec, _title} <- [{:all, nil} | View.views(document)],
        view = View.build(document, spec),
        picked <-
          Enum.map(view.nodes, &{:node, &1}) ++
            Enum.map(view.groups, &{:group, &1}) ++ Enum.map(view.relations, &{:relation, &1}) do
      html = panel(document, picked) |> LazyHTML.from_fragment()
      where = "#{name} #{inspect(spec)} #{elem(picked, 1).id}"

      assert Enum.count(LazyHTML.query(html, "aside.ehg-panel")) == 1, where
      assert Enum.count(LazyHTML.query(html, "[style]")) == 0, where

      # A name the document does not hold is text, not a button; edge_cases.json holds one on
      # purpose, a relation to a policy it does not have.
      unresolved = html |> LazyHTML.query("span.ehg-ref") |> Enum.map(&LazyHTML.text/1)
      assert unresolved -- ["policy:edge_cases:not in this document"] == [], where

      for id <- html |> LazyHTML.query("button.ehg-ref") |> LazyHTML.attribute("phx-value-id"),
          do: assert(Lookup.kind(lookup, id), "#{where} names #{id}")
    end
  end

  describe "a command and an event (point 6)" do
    test "a command: who may issue it with the grant EHOS gives, its scope, its fields" do
      text = open("fulfilment.warehouse", "command:fulfilment.warehouse:assign_pick_list")

      assert text =~ "Who may issue it Warehouse lead actor"
      assert text =~ "EHOS grants it as fulfilment.assign_pick_list."
      assert text =~ "A grant narrows it to one warehouse_id"
      assert text =~ "picker_id id · required"
    end

    test "a command a timer fires and a reaction issues says so" do
      text = open("lending.circulation", "command:lending.circulation:send_overdue_notice")
      assert text =~ "Reminder timer, when it fires"
      assert text =~ "May be refused on Only a copy still out is chased"
    end

    test "an event: who records it, the system it rests on" do
      text = open("billing.payments", "event:billing.payments:collected")

      assert text =~ "Recorded by Payment gateway integration actor"
      assert text =~ "Rests on Payment gateway external"
      refute text =~ "It ends the run."
      refute text =~ "Source:"
    end

    test "an event of another contract says so, and no panel judges what depends on an event" do
      text = open("fulfilment.shipping", "event:fulfilment.shipping:parcel_packed")

      assert text =~ "Declared in another contract and consumed here."

      # Whether an event is used is `mix eh_os_contract.check`'s to say (event-without-consumer);
      # what follows from it is on the graph's arrows.
      for {contract, event} <- [
            {"fulfilment.shipping", "parcel_packed"},
            {"billing.payments", "written_off"},
            {"lending.circulation", "late_fee_charged"}
          ] do
        text = open(contract, "event:#{contract}:#{event}")
        refute text =~ "depends on", event
      end
    end
  end

  describe "a field, the same everywhere" do
    test "personal data, and a pointer at a person, by what keeps them" do
      text = open("lending.membership", "event:lending.membership:member_registered")

      assert text =~
               "name string · required Personal data of Member — encrypted in the log, gone once they are erased."

      assert text =~ "member_id id · required Points at Member — in the log in the clear."

      # A command is kept nowhere; a read model's rows forget the person.
      text = open("lending.membership", "command:lending.membership:register_member")

      assert text =~ "name string · required Personal data of Member. "
      assert text =~ "member_id id · required Points at Member. "

      text = open("messaging", "read_model:messaging:borrowers")

      assert text =~
               "name Name string · required Personal data of Reader — forgotten once they are erased."

      assert text =~ "reader_id id · required Points at Reader."
    end

    test "a domain value's members and unit, an entity, the host" do
      assert open("fulfilment.shipping", "command:fulfilment.shipping:book_shipment") =~
               "service service · required Carrier service: Parcel / Freight."

      text = open("lending.circulation", "command:lending.circulation:return_copy")
      assert text =~ "late_fee money · required Amount: integer, in pence."
      assert text =~ "Supplied by the host, not the caller."

      assert open("lending.circulation", "command:lending.circulation:lend_copy") =~
               "Identifies Membership card."
    end

    # No field of the case studies is an enum of its own, so the member directory is given
    # one here, as the engine writes it.
    test "a system that gives a field its value, and an inline enum's labels" do
      assert open("edge_cases", "command:edge_cases:back\\slash") =~ "Its value comes from"

      status = %{
        "name" => "status",
        "label" => nil,
        "required" => true,
        "type" => %{
          "enum" => [
            %{"label" => "Active", "value" => "active"},
            %{"label" => "Lapsed", "value" => "lapsed"}
          ]
        }
      }

      document =
        update_in(Fixtures.document("lending.membership"), ["nodes", "read_model"], fn [m] ->
          [update_in(m, ["fields"], &(&1 ++ [status]))]
        end)

      assert open(document, "read_model:lending.membership:member_directory") =~
               "One of: Active / Lapsed."
    end
  end

  # Plan DD, C1 (#304): what a unit's page says, its panel says.
  test "a unit's panel says it records only when the document does, and not otherwise" do
    unit = "unit:fulfilment.warehouse:pick_list"
    document = Fixtures.document("fulfilment.warehouse")

    recording =
      update_in(document, ["nodes", "unit"], fn units ->
        for u <- units, do: if(u["id"] == unit, do: Map.put(u, "records_only", true), else: u)
      end)

    said = "Records only: no command it takes can be refused."
    assert open(recording, unit) =~ said
    refute open(document, unit) =~ said
  end

  describe "scenarios" do
    test "an arrow of a unit lists the scenarios behind its count, with their data (point 8)" do
      id =
        "emits:command:lending.circulation:lend_copy:event:lending.circulation:copy_lent"

      text = open("lending.circulation", id, {:unit, "unit:lending.circulation:loan"})

      assert text =~ "Scenarios covering it · 1"
      assert text =~ "a copy is lent on a card in good standing"
      assert text =~ "When Lend a copy command card_id card-ada copy_id copy-1"
      assert text =~ "Then Copy lent event copy_id copy-1 member_id member-ada"
    end

    test "a refusal names its rule" do
      id =
        "refused_on:command:lending.circulation:lend_copy:invariant:lending.circulation:unit:loan:suspended_card_borrows_nothing"

      text = open("lending.circulation", id, {:unit, "unit:lending.circulation:loan"})
      assert text =~ "a suspended card borrows nothing"
      assert text =~ "refused on"
    end
  end

  # What a command's decision reads, the one person who may issue it, and a scenario's
  # rows, person and moments, as `graph.v1` has them since main's plan DD (T2a, A1,
  # S2): lending's loan reads the membership card, the warehouse's pick list is confirmed
  # by its picker alone, and billing's subscription closes a period after usage recorded
  # at given moments.
  describe "what a command reads, who alone may issue it, a scenario's rows and moments" do
    test "a command says what it reads before deciding, and who alone may issue it" do
      assert open("lending.circulation", "command:lending.circulation:lend_copy") =~
               "Reads before deciding Membership card entity, the row its card_id names"

      # Circulation's variant adds a read whose field names no entity, said by its name.
      assert open(Fixtures.circulation_variant(), "command:lending.circulation:lend_copy") =~
               "tariff, the row its copy_id names"

      text = open("fulfilment.warehouse", "command:fulfilment.warehouse:confirm_pick")
      assert text =~ "Only the person its unit's picker_id names; anyone else is refused."

      assert text =~
               "when the one issuing it is not the person its unit's picker_id names"
    end

    test "a refusal of anyone but the person says so" do
      id =
        "refused_on:command:fulfilment.warehouse:confirm_pick:invariant:fulfilment.warehouse:unit:pick_list:confirmed_by_its_picker"

      assert open("fulfilment.warehouse", id) =~
               "Refused on it when the one issuing it is not the person its unit's picker_id names."
    end

    test "a unit's scenario shows the rows the application keeps, the person, and when a given happened" do
      id =
        "emits:command:billing.subscriptions:close_billing_period:event:billing.subscriptions:billing_period_closed"

      text = open("billing.subscriptions", id, {:unit, "unit:billing.subscriptions:subscription"})
      assert text =~ "Subscription started event, at 2026-01-01T09:00:00Z"

      id = "emits:command:lending.circulation:lend_copy:event:lending.circulation:copy_lent"
      text = open("lending.circulation", id, {:unit, "unit:lending.circulation:loan"})
      assert text =~ "The application keeps Membership card entity card_id card-ada"

      id = "emits:command:fulfilment.warehouse:confirm_pick:event:fulfilment.warehouse:picked"
      text = open("fulfilment.warehouse", id, {:unit, "unit:fulfilment.warehouse:pick_list"})
      assert text =~ "picker-ada issues"
    end

    # Plan DD, L4 (#326): the person a scenario issues as, and the field a read follows, are
    # names the owner does not read.
    test "for the owner, a scenario names its actor alone, and a read its entity alone" do
      id = "emits:command:fulfilment.warehouse:confirm_pick:event:fulfilment.warehouse:picked"
      unit = {:unit, "unit:fulfilment.warehouse:pick_list"}

      text = open("fulfilment.warehouse", id, unit, nil, :owner)
      assert text =~ "Picker actor issues"
      refute text =~ "picker-ada"

      lend = "command:lending.circulation:lend_copy"
      text = open(Fixtures.circulation_variant(), lend, :all, nil, :owner)

      assert text =~ "Reads before deciding Membership card entity"
      refute text =~ "card_id"
      refute text =~ "tariff"
    end
  end

  describe "the reactions (points 9 and 11)" do
    test "a policy: what it takes and issues, its delivery, its scenarios with their data" do
      text = open("billing.subscriptions", "policy:billing.subscriptions:invoice_the_period")

      assert text =~ "Takes"
      assert text =~ "Delivery In the transaction that records the event."

      assert text =~
               "Scenarios · 1 a closed period is invoiced: the fee, and a line per usage record"

      assert text =~ "it issues"
      assert text =~ "line_id fee"
    end

    test "a process manager: one run, its triggers, timers, and scenarios by what triggers them" do
      text = open("lending.circulation", "process_manager:lending.circulation:overdue_chase")

      assert text =~ "One run per loan_id."
      assert text =~ "Reminder timer — fires at the time in remind_at"
      assert text =~ "When Reminder fires"
      assert text =~ "the reminder sends the notice"
      assert text =~ "After the transaction, delivered at least once"
    end

    test "an effect: the system and the operation it calls, delivery and idempotency" do
      text = open("billing.payments", "effect:billing.payments:collect_payment")

      assert text =~ "Calls Payment gateway external: Charge a customer's card"
      assert text =~ "After the transaction, delivered at least once"
      assert text =~ "An effect has no scenarios"
    end
  end

  describe "the read side (points 10 and 12)" do
    test "a query: parameters, who may ask, what it reads and returns, a row, its scenarios" do
      text = open("lending.membership", "query:lending.membership:member_contact")

      assert text =~ "Parameters member_id id · required"
      assert text =~ "EHOS grants it as lending.member_contact."
      assert text =~ "Reads Member directory read model Returns a list of rows."
      assert text =~ "What a row holds"
      # The member's e-mail is personal, so the document holds none to show.
      assert text =~ "Asked with member_id member-ada It answers email — member_id member-ada"
    end

    test "a read model: what builds it, its fields, who reads it" do
      text = open("lending.membership", "read_model:lending.membership:member_directory")

      assert text =~ "Built from"
      assert text =~ "Read by How to reach a member query"
    end
  end

  describe "the domain (points 1, 2 and 3)" do
    test "a context: its terms, relations, contracts and entities" do
      text = open("domain.lending", "context:Lending.Domain:membership", :context_map)

      assert text =~
               "Terms Membership A member's registration, with how to reach them de: Mitgliedschaft — Die Anmeldung eines Mitglieds, mit seinen Kontaktdaten"

      assert text =~ "upstream (customer supplier) of Circulation"
      assert text =~ "Membership card entity, identified by card_id"
      assert text =~ "suspended Suspended boolean · required"
      refute text =~ "Source:"

      # The case studies cite no source, so the context and a term are given one here.
      sourced =
        update_in(Fixtures.document("domain.lending"), ["nodes", "context"], fn contexts ->
          for c <- contexts do
            if c["name"] == "membership" do
              c
              |> Map.put("source", "the desk's handbook")
              |> update_in(["terms"], fn [first | rest] ->
                [Map.put(first, "source", "board 2") | rest]
              end)
            else
              c
            end
          end
        end)

      text = open(sourced, "context:Lending.Domain:membership", :context_map)
      assert text =~ "Membership A member's registration, with how to reach them · board 2 de:"
      assert text =~ "Source: the desk's handbook"
    end

    # A term's word in code, as the engine gives it since main's L1 (#269).
    test "a context's term says its word in code, where it has one" do
      text = open("domain.lending", "context:Lending.Domain:circulation", :context_map)
      assert text =~ "de: Exemplar — Ein einzelnes Stück eines Titels In code: Copy"

      document =
        update_in(Fixtures.document("domain.lending"), ["nodes", "context"], fn contexts ->
          for c <- contexts do
            update_in(c, ["terms"], fn terms ->
              for t <- terms || [],
                  do: if(t["text"] == "Loan", do: Map.delete(t, "code"), else: t)
            end)
          end
        end)

      text = open(document, "context:Lending.Domain:circulation", :context_map)
      assert text =~ "In code: Copy"
      refute text =~ "bis zur Rückgabe verliehen ist In code"
    end

    test "an external system: its outage, its operations" do
      text = open("domain.billing", "external:Billing.Domain:payment_gateway", :context_map)

      assert text =~ "Data flows both ways."
      assert text =~ "When it is unavailable the gateway answers that it is unavailable"
      assert text =~ "Charge a customer's card charge"
      assert text =~ "Stands behind Payment gateway integration actor"
    end

    # No person of the case studies records an event. In this variant of the lending domain
    # the librarian records a late fee paid at the desk, a grant as the engine writes one.
    test "an actor of the domain, selected though no view draws it: what the role may do by contract" do
      text = open("domain.lending", "actor:Lending.Domain:librarian", :context_map)

      assert text =~ "A person"
      assert text =~ "What the role may do"
      assert text =~ "issues lending.lend_copy"
      assert text =~ "asks lending.member_contact"

      paid = %{
        "capability" => "lending.late_fee_paid",
        "contract" => "contract:lending.circulation",
        "declaration" => "event:lending.circulation:late_fee_paid",
        "kind" => "record"
      }

      document =
        update_in(Fixtures.document("domain.lending"), ["nodes", "actor"], fn actors ->
          for a <- actors do
            if a["name"] == "librarian",
              do: update_in(a, ["capabilities"], &(&1 ++ [paid])),
              else: a
          end
        end)

      assert open(document, "actor:Lending.Domain:librarian", :context_map) =~
               "records lending.late_fee_paid"
    end

    # No actor of the case studies has a responsibility. In this variant of the warehouse's
    # document the lead has one, as the engine writes it.
    test "an actor of a contract: what it may issue, with each grant" do
      lead = "actor:Fulfilment.Domain:lead"

      responsibility = %{
        "name" => "pick_lists",
        "label" => "Keeps the pick lists moving",
        "source" => nil
      }

      document =
        update_in(Fixtures.document("fulfilment.warehouse"), ["nodes", "actor"], fn actors ->
          for a <- actors do
            if a["id"] == lead,
              do: Map.put(a, "responsibilities", [responsibility]),
              else: a
          end
        end)

      text = open(document, lead)

      assert text =~ "Their role in EHOS is fulfilment.lead."
      assert text =~ "A grant to this role narrows answers by warehouse_id."
      assert text =~ "Responsible for Keeps the pick lists moving"

      assert text =~
               "May issue Assign a pick list to a picker command fulfilment.assign_pick_list"
    end

    test "a contract's arrow on the system names the events it carries by their labels" do
      id = "consumed_by:contract:fulfilment.warehouse:contract:fulfilment.shipping"

      text = open("domain.fulfilment", id, :system)
      assert text =~ "Parcel packed event"
    end

    # Plan DD, L3 (#286).
    test "a contract keeping a sibling's unit's number says which, on its arrow and on both ends" do
      id = "refers_to:contract:fulfilment.shipping:contract:fulfilment.orders"
      assert open("domain.fulfilment", id, :system) =~ "It keeps the number of order, which"

      text = open("domain.fulfilment", "contract:fulfilment.shipping", :system)
      assert text =~ "Keeps the number of order of"

      text = open("domain.fulfilment", "contract:fulfilment.orders", :system)
      assert text =~ "Its units' numbers are kept by"
    end

    test "the actors' table, people and systems apart, each row selecting its actor in the canvas" do
      html =
        render_component(&Actors.table/1,
          document: Fixtures.document("domain.fulfilment"),
          canvas: "map"
        )
        |> LazyHTML.from_fragment()

      [people, systems] = html |> LazyHTML.query("table") |> Enum.to_list()
      assert text(LazyHTML.to_html(people)) =~ "People Actor Role in EHOS Responsible for Source"
      assert text(LazyHTML.to_html(people)) =~ "Dispatcher fulfilment.dispatcher"
      assert text(LazyHTML.to_html(systems)) =~ "Carrier integration Carrier"

      assert html
             |> LazyHTML.query("button.ehg-ref")
             |> LazyHTML.attribute("phx-target")
             |> Enum.uniq() ==
               [~s([id="map"])]
    end
  end

  describe "what a view draws as an arrow of its own" do
    test "a lifecycle's start names the event a new one starts on" do
      id = "enters:event:fulfilment.shipping:booked:status:fulfilment.shipping:shipment:booked"
      text = open("fulfilment.shipping", id, {:lifecycle, "unit:fulfilment.shipping:shipment"})

      assert text =~ "On Shipment booked event."
    end

    test "a promise's arrow names the promise, whose own panel stays reachable by its name" do
      document = Fixtures.order_with_other_way()
      [arrow] = for %{type: "promise"} = r <- View.process(document).relations, do: r.id

      promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"

      text = open(document, arrow, :process)

      assert text =~
               "The promise dispatched_within_a_day_of_payment promise, kept within 24 hours"

      assert text =~ "the first event opens it, and the second keeps it."

      text = open(document, promise, :process)
      assert text =~ "Opened by Payment confirmed event"
      assert text =~ "Kept by Parcel handed to the carrier event"
      assert text =~ "Kept the other way by Order cancelled event"
    end

    test "a transition not yet taken says an aggregate still stands where it can be taken" do
      document = Fixtures.document("fulfilment.shipping")

      id =
        "transition:status:fulfilment.shipping:shipment:booked:status:fulfilment.shipping:shipment:dispatched:event:fulfilment.shipping:dispatched"

      overlay = %{
        "document_digest" => document["digest"],
        "nodes" => %{},
        "relations" => %{id => %{"count" => 0, "pending" => true, "untraversed" => false}},
        "observed" => %{"relations" => %{"undeclared" => []}}
      }

      {:ok, live, _html} =
        live_isolated(build_conn(), TestLive,
          session: %{
            "document" => document,
            "overlay" => overlay,
            "view" => {:lifecycle, "unit:fulfilment.shipping:shipment"}
          }
        )

      live |> with_target("#graph") |> render_click("select", %{"id" => id})
      text = live |> element(".ehg-panel") |> render() |> text()

      assert text =~
               "From the log Made 0 times. Not yet taken: an aggregate still stands where it can be taken."
    end
  end

  # Plan DD, P2e (#220): a process module's document, and its processes in its domain's.
  describe "a process module" do
    setup do
      document = Fixtures.order_with_other_way()
      overlay = Fixtures.overlay("process.fulfilment.order")
      promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"
      [document: document, overlay: overlay, promise: promise]
    end

    test "the process: one run, who answers for it, the contracts, its stages and promises, its runs",
         c do
      overlay = put_in(c.overlay, ["nodes", "process:fulfilment.order", "runs"], 4)
      text = open(c.document, "process:fulfilment.order", :process, overlay)

      assert text =~ "One run per order_id."
      assert text =~ "Accountable Dispatcher actor"
      assert text =~ "Includes events of fulfilment.orders contract"
      assert text =~ "Stages, in order Ordering stage Picking stage Shipping stage"
      assert text =~ "Promises dispatched_within_a_day_of_payment promise"
      assert text =~ "From the log 4 runs."
    end

    test "a stage: its place in the process and its events, in no order", c do
      text = open(c.document, "stage:fulfilment.order:shipping", :process)

      assert text =~ "Stage 3 of 3 of An order, from its placing to its delivery"
      assert text =~ "Shipment booked event"
      assert text =~ "No order is claimed among them."
    end

    test "an event: its contract, its stage, whether it ends a run, and where its fields are",
         c do
      text = open(c.document, "event:fulfilment.shipping:delivered", :process, c.overlay)

      assert text =~ "Declared in fulfilment.shipping contract."
      assert text =~ "In the stage Shipping stage."

      assert text =~
               "Its fields, and the unit that records it, are in the contract's own document."

      assert text =~ "It ends the run."
      assert text =~ "Rests on Carrier external"
      # The overlay gives 0 for an event that did not happen.
      assert text =~ "From the log Recorded 0 times."
    end

    test "a promise: its verdicts from the log, on its card and its arrow", c do
      verdicts = %{
        "instances" => 7,
        "satisfied" => 4,
        "satisfied_via_eventually" => 3,
        "satisfied_via_or_else" => 1,
        "violated" => 1,
        "pending" => 2,
        "suspended" => 0
      }

      overlay = put_in(c.overlay, ["nodes", c.promise], verdicts)
      text = open(c.document, c.promise, :process, overlay)

      assert text =~
               "From the log Opened in 7 runs. Kept in 4: 3 by the event that keeps it, 1 the other way. Broken in 1. Pending in 2: not kept yet."

      refute text =~ "Suspended"
      refute text =~ "Unconfirmed"

      [arrow] = for %{type: "promise"} = r <- View.process(c.document).relations, do: r.id
      assert open(c.document, arrow, :process, overlay) =~ "From the log Opened in 7 runs."
    end

    test "a promise the owner has yet to confirm says so, overlay or not", c do
      unverified =
        update_in(c.document, ["nodes", "promise"], fn [p] -> [Map.put(p, "unverified", true)] end)

      overlay = update_in(c.overlay, ["nodes"], &Map.delete(&1, c.promise))

      for overlay <- [overlay, nil] do
        text = open(unverified, c.promise, :process, overlay)

        assert text =~
                 "Unconfirmed: no run is judged against it until the process owner confirms it."

        refute text =~ "From the log"
      end

      text = open(c.document, c.promise, :process, c.overlay)
      assert text =~ "From the log No run has opened it."

      # A confirmed one missing from an overlay is not claimed unconfirmed.
      refute open(c.document, c.promise, :process, overlay) =~ "Unconfirmed"
    end

    test "its contracts are its document's, whether or not it has stages", c do
      text = open(c.document, "process:fulfilment.order", :process)

      assert text =~
               "Includes events of fulfilment.orders contract fulfilment.warehouse contract fulfilment.shipping contract"

      text = open(put_in(c.document, ["nodes", "stage"], []), "process:fulfilment.order")
      assert text =~ "Includes events of fulfilment.orders contract"
      refute text =~ "Stages, in order"

      # In the domain's, only those it includes, of all the domain's contracts.
      text = open("domain.lending", "process:lending.loan", :system)
      assert text =~ "Includes events of lending.circulation contract"
      refute text =~ "lending.membership"
    end

    test "in its domain: its module, the contracts whose events it includes, who answers for it" do
      text = open("domain.fulfilment", "process:fulfilment.order", :system)

      assert text =~
               "The process module fulfilment.order, in the code Fulfilment.Processes.Order."

      assert text =~
               "Includes events of fulfilment.orders contract fulfilment.warehouse contract fulfilment.shipping contract"

      assert text =~ "Accountable Dispatcher actor"

      text = open("domain.fulfilment", "contract:fulfilment.warehouse", :system)

      assert text =~
               "Processes that include its events An order, from its placing to its delivery"
    end
  end

  describe "another application, the inbox, a manager's end (messaging.json)" do
    test "a publication: where it is published from, and what it is received as" do
      text = open("messaging", "publication:Messaging.Domain:library.copy_lent")

      assert text =~ "On the wire as library.copy_lent."

      assert text =~
               "Published from Copy lent event, with copy_id, a repeat recognised by copy_id"

      assert text =~ "Received as A copy lent elsewhere event"
    end

    test "a received event, and the policy that takes it through the inbox whatever its delivery" do
      text = open("messaging", "event:messaging:copy_lent")
      assert text =~ "Received from another application as library.copy_lent publication."
      assert text =~ "The application takes it with messaging.copy_lent.subscribe."

      text = open("messaging", "policy:messaging:release_hold")
      assert text =~ "Takes A copy lent elsewhere event, through the inbox"

      assert text =~
               "An event received from another application reaches it through the inbox, after the transaction, whatever its delivery."
    end

    test "a manager that ends, and a timer it sets and cancels" do
      text = open("messaging", "process_manager:messaging:loan")
      assert text =~ "Ends on Copy returned event"

      assert text =~
               "Due back timer — fires 14 days after it is set, issuing Remind the reader command"

      text = open("messaging", "timer:messaging:loan:due")
      assert text =~ "Set on Copy lent, as a run starts"
      assert text =~ "Cancelled on Copy returned, during the run"
    end
  end

  describe "a selection from a panel" do
    test "a name in the panel selects its node, though the view does not draw it, and fades nothing" do
      {:ok, live, _html} =
        live_isolated(build_conn(), TestLive,
          session: %{
            "document" => Fixtures.document("fulfilment.warehouse"),
            "view" => {:unit, "unit:fulfilment.warehouse:pick_list"}
          }
        )

      target = with_target(live, "#graph")

      render_click(target, "select", %{"id" => "command:fulfilment.warehouse:assign_pick_list"})

      assert render(live) =~ "is-far"

      html = render_click(target, "show", %{"id" => "actor:Fulfilment.Domain:lead"})

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".ehg-panel h4")
             |> LazyHTML.text() == "Warehouse lead"

      refute html =~ "is-far"
      refute html =~ "is-selected"
    end

    test "a name of what the panel is of keeps it open; the root says what is selected, while it is" do
      {:ok, live, _html} =
        live_isolated(build_conn(), TestLive,
          session: %{"document" => Fixtures.document("messaging")}
        )

      target = with_target(live, "#graph")

      selected = fn ->
        live
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#graph")
        |> LazyHTML.attribute("data-selected")
      end

      assert selected.() == []

      render_click(target, "select", %{"id" => "timer:messaging:loan:due"})
      assert selected.() == ["timer:messaging:loan:due"]

      render_click(target, "show", %{"id" => "timer:messaging:loan:due"})
      assert selected.() == ["timer:messaging:loan:due"]
      assert has_element?(live, ".ehg-panel")

      render_click(target, "deselect", %{})
      assert selected.() == []
      refute has_element?(live, ".ehg-panel")
    end
  end

  test "a policy, a process manager and a query say on their card how many scenarios pin them" do
    lines = fn name ->
      view = name |> Fixtures.document() |> View.contract()
      Map.new(view.nodes, &{&1.id, &1.lines})
    end

    subscriptions = lines.("billing.subscriptions")

    assert subscriptions["policy:billing.subscriptions:invoice_the_period"] == ["1 scenario"]

    assert subscriptions["process_manager:billing.subscriptions:monthly_billing"] == [
             "6 scenarios"
           ]

    assert lines.("billing.payments")["effect:billing.payments:collect_payment"] == []

    # A timer says when it fires (the working plan's point 5).
    assert subscriptions["timer:billing.subscriptions:monthly_billing:period_end"] == [
             "at close_at"
           ]

    messaging = "messaging" |> Fixtures.document() |> View.contract()

    assert Enum.find(messaging.nodes, &(&1.id == "timer:messaging:loan:due")).lines == [
             "after 14 days"
           ]
  end

  # Plan DD, L4 (#326): the panel as the business owner reads it.
  describe "the owner's view" do
    alias EhOsContract.GraphRenderer.Audience

    # Every source a document cites, wherever it sits.
    defp sources(%{} = map),
      do:
        Enum.flat_map(map, fn
          {"source", s} when is_binary(s) -> [s]
          {_k, v} -> sources(v)
        end)

    defp sources(list) when is_list(list), do: Enum.flat_map(list, &sources/1)
    defp sources(_other), do: []

    defp owner(name, id, spec \\ :all, overlay \\ nil), do: open(name, id, spec, overlay, :owner)

    test "every panel of every fixture, read by the owner, shows no code, no field's name and no scenario's data" do
      for {name, document} <- Fixtures.documents(),
          read = Audience.read(document, :owner),
          lookup = Lookup.new(read),
          {spec, _title} <- [{:all, nil} | View.views(document)],
          view = View.build(document, spec, nil, :owner),
          picked <-
            Enum.map(view.nodes, &{:node, &1}) ++
              Enum.map(view.groups, &{:group, &1}) ++ Enum.map(view.relations, &{:relation, &1}) do
        html =
          render_component(&Panel.panel/1,
            picked: picked,
            lookup: lookup,
            target: "#graph",
            audience: :owner
          )
          |> LazyHTML.from_fragment()

        where = "#{name} #{inspect(spec)} #{elem(picked, 1).id}"

        for selector <- ["code", ".ehg-field-name", ".ehg-data", ".ehg-panel-name"],
            do: assert(Enum.count(LazyHTML.query(html, selector)) == 0, "#{where}: #{selector}")

        # A name in code is left only where its declaration has no label, which `check`
        # notes.
        unlabelled =
          for {_kind, group} <- read["nodes"],
              n <- group,
              n["label"] == nil,
              into: MapSet.new(),
              do: n["name"]

        # A source is the client's reference, which may read like code ("cf.pdf").
        text =
          Enum.reduce(
            sources(read) |> Enum.uniq() |> Enum.sort_by(&(-String.length(&1))),
            LazyHTML.text(html),
            &String.replace(&2, &1, "")
          )

        leaked =
          Regex.scan(~r/\b[a-z][a-z0-9]*(?:[_.][a-z][a-z0-9]*)+\b/u, text)
          |> List.flatten()
          |> Enum.reject(&MapSet.member?(unlabelled, &1))

        assert leaked == [], "#{where}: #{inspect(leaked)}"

        # The panel's words for how a reaction is delivered, not the business's: a parcel
        # may well be delivered.
        refute LazyHTML.text(html) =~
                 ~r/delivered at least once|idempoten|One run per|transaction|In the log as/i,
               where
      end
    end

    test "a process: its deadline, who answers for it and its runs, without the key its runs are told by" do
      # Each case study's context is labelled as its contract's module is named, so orders is
      # labelled apart here, and the contract cannot be read by the module's last segment.
      document =
        Fixtures.relabel(Fixtures.order_with_other_way(), %{
          "context:Fulfilment.Domain:orders" => "Customer orders"
        })

      overlay =
        put_in(
          Fixtures.overlay("process.fulfilment.order"),
          ["nodes", "process:fulfilment.order", "runs"],
          4
        )

      text = owner(document, "process:fulfilment.order", :process, overlay)

      refute text =~ "One run per"
      refute text =~ "fulfilment.order"
      assert text =~ "A run ends within 14 days."
      assert text =~ "Accountable Dispatcher actor"
      # A contract by its context's label, a promise by its rule.
      assert text =~ "Includes events of Customer orders contract"
      assert text =~ "Promises After Payment confirmed, eventually"
      assert text =~ "within 24 hours, or else Order cancelled promise"
      assert text =~ "From the log 4 runs."
    end

    test "a promise is titled by its rule, and keeps its verdicts" do
      promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"
      overlay = Fixtures.overlay("process.fulfilment.order")
      text = owner(Fixtures.order_with_other_way(), promise, :process, overlay)

      refute text =~ "dispatched_within_a_day_of_payment"

      # The other way it may be kept is part of the rule, as the owner's pages write it.
      assert text =~
               "After Payment confirmed, eventually Parcel handed to the carrier " <>
                 "within 24 hours, or else Order cancelled"

      assert text =~ "From the log"
    end

    test "a reaction: what it takes and issues and its scenarios, without delivery or data" do
      text = owner("billing.subscriptions", "policy:billing.subscriptions:invoice_the_period")

      assert text =~ "Takes"

      assert text =~
               "Scenarios · 1 a closed period is invoiced: the fee, and a line per usage record"

      refute text =~ "Delivery"
      refute text =~ "line_id"

      text = owner("lending.circulation", "process_manager:lending.circulation:overdue_chase")

      refute text =~ "One run per"
      refute text =~ "remind_at"
      assert text =~ "fires at a moment the run holds"
      refute text =~ "delivered at least once"
    end

    test "an effect says what it calls, and nothing of its delivery" do
      text = owner("billing.payments", "effect:billing.payments:collect_payment")

      assert text =~ "Calls Payment gateway external: Charge a customer's card"

      refute text =~ "at least once"
      refute text =~ "harmless"
    end

    test "an engineer's panel is as it was" do
      text = open("billing.payments", "effect:billing.payments:collect_payment")

      assert text =~ "After the transaction, delivered at least once"
    end
  end

  describe "a promise that waits on a system through an earlier step" do
    setup do
      promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"
      carrier = "external:Fulfilment.Domain:carrier"

      document =
        put_in(
          Fixtures.document("process.fulfilment.order"),
          ["relations", "waits_on"],
          [%{"id" => "waits_on:#{promise}:#{carrier}", "from" => promise, "to" => carrier}]
        )

      %{document: document, promise: promise, carrier: carrier}
    end

    test "the promise says what it waits on, and the system which promises wait on it", %{
      document: document,
      promise: promise,
      carrier: carrier
    } do
      assert open(document, promise) =~ "Waits on, through an earlier step Carrier external"
      assert open(document, carrier) =~ "Promises waiting on it"
    end
  end
end
