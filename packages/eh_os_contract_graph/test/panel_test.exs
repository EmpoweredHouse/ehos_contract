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
    for name <- Fixtures.names(),
        document = Fixtures.document(name),
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
      text =
        open(
          "taxvision.registry_watch",
          "command:taxvision.registry_watch:complete_company_profile"
        )

      assert text =~ "Who may issue it Księgowa actor"
      assert text =~ "EHOS grants it as taxvision.complete_company_profile."
      assert text =~ "A grant narrows it to one company_id"
      assert text =~ "legal_form string · required"
    end

    test "a command a timer fires and a reaction issues says so" do
      text = open("taxvision.registry_watch", "command:taxvision.registry_watch:check_registries")
      assert text =~ "Weryfikacja rejestrowa timer, when it fires"
      assert text =~ "May be refused on Rejestry sprawdza się tylko dla firmy z kompletem danych"
    end

    test "an event: who records it, the system it rests on" do
      text = open("rehmed.statutory_reporting", "event:rehmed.statutory_reporting:p1_report_sent")

      assert text =~ "Recorded by Integracja z rejestrem P1 actor"
      assert text =~ "Rests on Rejestr zdarzeń medycznych P1 external"
      refute text =~ "It ends the run."
      refute text =~ "Source:"
    end

    test "an event of another contract says so, and no panel judges what depends on an event" do
      text =
        open(
          "rehmed.statutory_reporting",
          "event:rehmed.statutory_reporting:visit_closed_clinically"
        )

      assert text =~ "Declared in another contract and consumed here."

      # Whether an event is used is `mix eh_os_contract.check`'s to say (event-without-consumer);
      # what follows from it is on the graph's arrows.
      for {contract, event} <- [
            {"rehmed.statutory_reporting", "visit_closed_clinically"},
            {"rehmed.settlement", "settlement_corrected"},
            {"rehmed.external_payers", "visit_excluded_from_invoice"}
          ] do
        text = open(contract, "event:#{contract}:#{event}")
        refute text =~ "depends on", event
      end
    end
  end

  describe "a field, the same everywhere (Pole)" do
    test "personal data, and a pointer at a person, by what keeps them" do
      text =
        open("rehmed.statutory_reporting", "event:rehmed.statutory_reporting:p1_report_queued")

      assert text =~
               "pesel string · required Personal data of Pacjent — encrypted in the log, gone once they are erased."

      assert text =~ "patient_id id · required Points at Pacjent — in the log in the clear."

      # A command is kept nowhere; a read model's rows forget the person.
      text =
        open("rehmed.statutory_reporting", "command:rehmed.statutory_reporting:queue_p1_report")

      assert text =~ "pesel string · required Personal data of Pacjent. "
      assert text =~ "patient_id id · required Points at Pacjent. "

      text = open("messaging", "read_model:messaging:borrowers")

      assert text =~
               "name Name string · required Personal data of Reader — forgotten once they are erased."

      assert text =~ "reader_id id · required Points at Reader."
    end

    test "a domain value's members and unit, an entity, the host" do
      text = open("rehmed.settlement", "command:rehmed.settlement:record_payment")

      assert text =~
               "method payment_method · required payment_method: Karta / Gotówka / Przelew / Bon."

      assert text =~ "amount money · required Kwota: integer, in grosze."

      assert open("rehmed.settlement", "command:rehmed.settlement:add_service_line") =~
               "Identifies Usługa."

      assert open("rehmed.settlement", "command:rehmed.settlement:close_settlement") =~
               "Supplied by the host, not the caller."
    end

    test "a system that gives a field its value, and an inline enum's labels" do
      assert open("edge_cases", "command:edge_cases:back\\slash") =~ "Its value comes from"

      assert open("appunite_equipment.demands", "read_model:appunite_equipment.demands:waiting") =~
               "One of: Otwarte / New."
    end
  end

  # Plan DD, C1 (#304): what a unit's page says, its panel says.
  test "a unit's panel says it records only when the document does, and not otherwise" do
    unit = "unit:taxvision.registry_watch:client"
    document = Fixtures.document("taxvision.registry_watch")

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
        "emits:command:taxvision.registry_watch:complete_company_profile:event:taxvision.registry_watch:company_profile_completed"

      text = open("taxvision.registry_watch", id, {:unit, "unit:taxvision.registry_watch:client"})

      assert text =~ "Scenarios covering it · 1"
      assert text =~ "księgowa uzupełnia profil firmy"
      assert text =~ "When Uzupełnij profil firmy command legal_form JDG vat_status czynny"
      assert text =~ "Then Uzupełniono profil firmy event legal_form JDG"
    end

    test "a refusal names its rule" do
      id =
        "refused_on:command:rehmed.settlement:close_settlement:invariant:rehmed.settlement:unit:visit_settlement:payment_lines_sum_to_total"

      text = open("rehmed.settlement", id, {:unit, "unit:rehmed.settlement:visit_settlement"})
      assert text =~ "zapłacone 150 zł przy należnych 200 — rozliczenie odrzucone"
      assert text =~ "refused on"
    end
  end

  # What a command's decision reads, the one person who may issue it, and a scenario's
  # rows, person and moments, as `graph.v1` has them since main's plan DD (T2a, A1,
  # S2). No fixture's contract declares them, so the settlement's document is given
  # them here as the engine writes them.
  describe "what a command reads, who alone may issue it, a scenario's rows and moments" do
    defp with_main_keys do
      c = "rehmed.settlement"
      hand_over = "command:#{c}:hand_over_visit"
      add_line = "command:#{c}:add_service_line"
      rule = "invariant:#{c}:unit:visit_settlement:handover_only_after_scope_change"
      described = "specjalista dodał usługę — przekazuje wizytę do rozliczenia"
      service = "entity:Rehmed.Domain:service"

      Fixtures.document(c)
      |> update_in(["nodes", "command"], fn commands ->
        for command <- commands do
          case command["id"] do
            ^hand_over ->
              Map.put(command, "actor_is", "specialist_id")

            ^add_line ->
              Map.put(command, "reads", [
                %{"name" => "service", "field" => "service_id", "entity" => service}
              ])

            _ ->
              command
          end
        end
      end)
      |> update_in(["relations", "refused_on"], fn relations ->
        for r <- relations do
          if r["from"] == hand_over and r["to"] == rule, do: Map.put(r, "actor_is", true), else: r
        end
      end)
      |> update_in(["scenarios", "unit"], fn scenarios ->
        for s <- scenarios do
          if s["description"] == described do
            s
            |> Map.merge(%{"actor" => "actor:Rehmed.Domain:specialist", "as" => "specialist-ewa"})
            |> Map.put("given_entities", [
              %{"entity" => service, "data" => %{"service_id" => "service-ultrasound"}}
            ])
            |> update_in(
              ["given"],
              &Enum.map(&1, fn g -> Map.put(g, "at", "2026-10-05T09:00:00+02:00") end)
            )
          else
            s
          end
        end
      end)
    end

    test "a command says what it reads before deciding, and who alone may issue it" do
      document = with_main_keys()

      assert open(document, "command:rehmed.settlement:add_service_line") =~
               "Reads before deciding Usługa entity, the row its service_id names"

      text = open(document, "command:rehmed.settlement:hand_over_visit")
      assert text =~ "Only the person its unit's specialist_id names; anyone else is refused."

      assert text =~
               "when the one issuing it is not the person its unit's specialist_id names"
    end

    test "a refusal of anyone but the person says so" do
      id =
        "refused_on:command:rehmed.settlement:hand_over_visit:invariant:rehmed.settlement:unit:visit_settlement:handover_only_after_scope_change"

      assert open(with_main_keys(), id) =~
               "Refused on it when the one issuing it is not the person its unit's specialist_id names."
    end

    test "a unit's scenario shows the rows the application keeps, the person, and when a given happened" do
      id =
        "emits:command:rehmed.settlement:hand_over_visit:event:rehmed.settlement:visit_handed_over"

      text = open(with_main_keys(), id, {:unit, "unit:rehmed.settlement:visit_settlement"})

      assert text =~ ", at 2026-10-05T09:00:00+02:00"
      assert text =~ "The application keeps Usługa entity service_id service-ultrasound"
      assert text =~ "specialist-ewa issues"
    end
  end

  describe "the reactions (points 9 and 11)" do
    test "a policy: what it takes and issues, its delivery, its scenarios with their data" do
      text =
        open(
          "taxvision.registry_watch",
          "policy:taxvision.registry_watch:compare_with_registries"
        )

      assert text =~ "Takes"
      assert text =~ "Delivery In the transaction that records the event."
      assert text =~ "Scenarios · 1 odpowiedź rejestrów idzie do porównania"
      assert text =~ "it issues"
      assert text =~ "vat_status czynny"
    end

    test "a process manager: one run, its triggers, timers, and scenarios by what triggers them" do
      text =
        open(
          "taxvision.registry_watch",
          "process_manager:taxvision.registry_watch:monthly_registry_check"
        )

      assert text =~ "One run per company_id."
      assert text =~ "Weryfikacja rejestrowa timer — fires at the time in check_at"
      assert text =~ "When Weryfikacja rejestrowa fires"
      assert text =~ "sprawdzenie w styczniu — 1 lutego sprawdza się styczeń"
      assert text =~ "After the transaction, delivered at least once"
    end

    test "an effect: the system and the operation it calls, delivery and idempotency" do
      text =
        open("rehmed.statutory_reporting", "effect:rehmed.statutory_reporting:send_p1_report")

      assert text =~
               "Calls Rejestr zdarzeń medycznych P1 external: Przyjmij zgłoszenie zdarzenia medycznego"

      assert text =~ "After the transaction, delivered at least once"
      assert text =~ "An effect has no scenarios"
    end
  end

  describe "the read side (points 10 and 12)" do
    test "a query: parameters, who may ask, what it reads and returns, a row, its scenarios" do
      text = open("rehmed.settlement", "query:rehmed.settlement:daily_totals_for")

      assert text =~ "Parameters business_date date · required"
      assert text =~ "EHOS grants it as rehmed.daily_totals_for."

      assert text =~
               "Reads Zestawienie dnia per metoda płatności read model Returns a list of rows."

      assert text =~ "What a row holds"
      assert text =~ "Asked with business_date 2026-01-01 It answers method card total 25000"
    end

    test "a read model: what builds it, its fields, who reads it" do
      text = open("rehmed.settlement", "read_model:rehmed.settlement:daily_totals")

      assert text =~ "Built from"
      assert text =~ "Read by Zestawienie dnia dla recepcji query"
    end
  end

  describe "the domain (points 1, 2 and 3)" do
    test "a context: its terms, relations, contracts and entities" do
      text = open("domain.rehmed", "context:Rehmed.Domain:scheduling", :context_map)

      assert text =~
               "Terms Wizyta Zarezerwowany termin z zasobami · CTX-01 en: Visit — A held slot with resources"

      assert text =~ "upstream (customer supplier) of Rozliczenia"
      assert text =~ "Source: CTX-01"

      text = open("domain.rehmed", "context:Rehmed.Domain:configuration", :context_map)
      assert text =~ "Usługa entity, identified by service_id"
      assert text =~ "p1_reported Raportowana do P1 boolean · required"
    end

    # A term's word in code, as the engine gives it since main's L1 (#269); the fixture was
    # taken before, so it is added here as the engine writes it.
    test "a context's term says its word in code, where it has one" do
      document =
        update_in(Fixtures.document("domain.rehmed"), ["nodes", "context"], fn contexts ->
          for c <- contexts do
            update_in(c, ["terms"], fn terms ->
              for t <- terms || [],
                  do: if(t["text"] == "Wizyta", do: Map.put(t, "code", "Visit"), else: t)
            end)
          end
        end)

      text = open(document, "context:Rehmed.Domain:scheduling", :context_map)
      assert text =~ "en: Visit — A held slot with resources In code: Visit"
      refute text =~ "Pacjent wyszedł z gabinetu In code"
    end

    test "an external system: its outage, its operations" do
      text = open("domain.rehmed", "external:Rehmed.Domain:p1", :context_map)

      assert text =~ "Data flows both ways."
      assert text =~ "When it is unavailable odrzucenie zgłoszenia"
      assert text =~ "Przyjmij zgłoszenie zdarzenia medycznego submit_report"
      assert text =~ "Stands behind Integracja z rejestrem P1 actor"
    end

    test "an actor of the domain, selected though no view draws it: what the role may do by contract" do
      text = open("domain.rehmed", "actor:Rehmed.Domain:reception", :context_map)

      assert text =~ "A person"
      assert text =~ "What the role may do"
      assert text =~ "issues rehmed.book_visit"
      assert text =~ "records rehmed.patient_arrived"
    end

    test "an actor of a contract: what it may issue, with each grant" do
      text = open("taxvision.registry_watch", "actor:Taxvision.Domain:accountant")

      assert text =~ "Their role in EHOS is taxvision.accountant."
      assert text =~ "Responsible for Otwiera i prowadzi miesiąc księgowy"
      assert text =~ "May issue Uzupełnij profil firmy command taxvision.complete_company_profile"
    end

    test "a contract's arrow on the system names the events it carries by their labels" do
      id =
        "consumed_by:contract:rehmed.clinical_documentation:contract:rehmed.statutory_reporting"

      text = open("domain.rehmed", id, :system)
      assert text =~ "Zamknięto wizytę przez specjalistę event"
    end

    # Plan DD, L3 (#286): the fixture's relations were added as the engine gives them today.
    test "a contract keeping a sibling's unit's number says which, on its arrow and on both ends" do
      id = "refers_to:contract:rehmed.settlement:contract:rehmed.scheduling"
      assert open("domain.rehmed", id, :system) =~ "It keeps the number of visit, which"

      text = open("domain.rehmed", "contract:rehmed.settlement", :system)
      assert text =~ "Keeps the number of visit of"

      text = open("domain.rehmed", "contract:rehmed.scheduling", :system)
      assert text =~ "Its units' numbers are kept by"
    end

    test "the actors' table, people and systems apart, each row selecting its actor in the canvas" do
      html =
        render_component(&Actors.table/1,
          document: Fixtures.document("domain.rehmed"),
          canvas: "map"
        )
        |> LazyHTML.from_fragment()

      [people, systems] = html |> LazyHTML.query("table") |> Enum.to_list()
      assert text(LazyHTML.to_html(people)) =~ "People Actor Role in EHOS Responsible for Source"
      assert text(LazyHTML.to_html(people)) =~ "Recepcja rehmed.reception"

      assert text(LazyHTML.to_html(systems)) =~
               "Integracja z rejestrem P1 Rejestr zdarzeń medycznych P1"

      assert html
             |> LazyHTML.query("button.ehg-ref")
             |> LazyHTML.attribute("phx-target")
             |> Enum.uniq() ==
               [~s([id="map"])]
    end
  end

  describe "what a view draws as an arrow of its own" do
    test "a lifecycle's start names the event a new one starts on" do
      id =
        "enters:event:appunite_equipment.demands:opened:status:appunite_equipment.demands:demand:open"

      text =
        open(
          "appunite_equipment.demands",
          id,
          {:lifecycle, "unit:appunite_equipment.demands:demand"}
        )

      assert text =~ "On Otwarto zapotrzebowanie na komputer event."
    end

    test "a promise's arrow names the promise, whose own panel stays reachable by its name" do
      document = Fixtures.document("process.rehmed.clinical_visit")
      [arrow] = for %{type: "promise"} = r <- View.process(document).relations, do: r.id

      promise = "promise:rehmed.clinical_visit:medical_event_reported_within_statutory_window"

      text = open(document, arrow, :process)

      assert text =~
               "The promise medical_event_reported_within_statutory_window promise, kept within 2 days"

      assert text =~ "the first event opens it, and the second keeps it."

      text = open(document, promise, :process)
      assert text =~ "Opened by Pacjent wyszedł z gabinetu event"
      assert text =~ "Kept by Wysłano informację do systemu P1 event"
      assert text =~ "Kept the other way by Usługa nie podlega zgłoszeniu do P1 event"
    end

    test "a transition not yet taken says an aggregate still stands where it can be taken" do
      document = Fixtures.document("appunite_equipment.demands")

      id =
        "transition:status:appunite_equipment.demands:demand:open:status:appunite_equipment.demands:demand:ordered:event:appunite_equipment.demands:computer_ordered"

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
            "view" => {:lifecycle, "unit:appunite_equipment.demands:demand"}
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
      document = Fixtures.document("process.rehmed.clinical_visit")
      overlay = Fixtures.overlay("process.rehmed.clinical_visit")
      promise = "promise:rehmed.clinical_visit:medical_event_reported_within_statutory_window"
      [document: document, overlay: overlay, promise: promise]
    end

    test "the process: one run, who answers for it, the contracts, its stages and promises, its runs",
         c do
      overlay = put_in(c.overlay, ["nodes", "process:rehmed.clinical_visit", "runs"], 4)
      text = open(c.document, "process:rehmed.clinical_visit", :process, overlay)

      assert text =~ "One run per visit_id."
      assert text =~ "Accountable Manager gabinetu actor"
      assert text =~ "Includes events of rehmed.scheduling contract"
      assert text =~ "Stages, in order departure stage closing stage reporting stage"
      assert text =~ "Promises medical_event_reported_within_statutory_window promise"
      assert text =~ "From the log 4 runs."
    end

    test "a stage: its place in the process and its events, in no order", c do
      text = open(c.document, "stage:rehmed.clinical_visit:reporting", :process)

      assert text =~ "Stage 3 of 3 of Wizyta"
      assert text =~ "Zgłoszenie P1 zakolejkowane event"
      assert text =~ "No order is claimed among them."
    end

    test "an event: its contract, its stage, whether it ends a run, and where its fields are",
         c do
      text =
        open(c.document, "event:rehmed.statutory_reporting:p1_report_sent", :process, c.overlay)

      assert text =~ "Declared in rehmed.statutory_reporting contract."
      assert text =~ "In the stage reporting stage."

      assert text =~
               "Its fields, and the unit that records it, are in the contract's own document."

      assert text =~ "It ends the run."
      assert text =~ "Rests on Rejestr zdarzeń medycznych P1 external"
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
      text = open(c.document, "process:rehmed.clinical_visit", :process)

      assert text =~
               "Includes events of rehmed.scheduling contract rehmed.clinical_documentation contract rehmed.statutory_reporting contract"

      text = open(put_in(c.document, ["nodes", "stage"], []), "process:rehmed.clinical_visit")
      assert text =~ "Includes events of rehmed.scheduling contract"
      refute text =~ "Stages, in order"

      # In the domain's, only those it includes, of all the domain's contracts.
      text = open("domain.rehmed", "process:rehmed.payer_settlement", :system)

      assert text =~
               "Includes events of rehmed.settlement contract rehmed.external_payers contract"

      refute text =~ "rehmed.scheduling"
    end

    test "in its domain: its module, the contracts whose events it includes, who answers for it" do
      text = open("domain.rehmed", "process:rehmed.clinical_visit", :system)

      assert text =~
               "The process module rehmed.clinical_visit, in the code Rehmed.Processes.ClinicalVisit."

      assert text =~
               "Includes events of rehmed.scheduling contract rehmed.clinical_documentation contract rehmed.statutory_reporting contract"

      assert text =~ "Accountable Manager gabinetu actor"

      text = open("domain.rehmed", "contract:rehmed.statutory_reporting", :system)
      assert text =~ "Processes that include its events Wizyta"
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
            "document" => Fixtures.document("taxvision.registry_watch"),
            "view" => {:unit, "unit:taxvision.registry_watch:client"}
          }
        )

      target = with_target(live, "#graph")

      render_click(target, "select", %{
        "id" => "command:taxvision.registry_watch:complete_company_profile"
      })

      assert render(live) =~ "is-far"

      html = render_click(target, "show", %{"id" => "actor:Taxvision.Domain:accountant"})

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".ehg-panel h4")
             |> LazyHTML.text() == "Księgowa"

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
    document = Fixtures.document("taxvision.registry_watch")
    view = View.contract(document)
    lines = Map.new(view.nodes, &{&1.id, &1.lines})

    assert lines["policy:taxvision.registry_watch:compare_with_registries"] == ["1 scenario"]

    assert lines["process_manager:taxvision.registry_watch:monthly_registry_check"] == [
             "4 scenarios"
           ]

    assert lines["effect:taxvision.registry_watch:look_up_registries"] == []

    # A timer says when it fires (the working plan's point 5).
    assert lines["timer:taxvision.registry_watch:monthly_registry_check:next_month"] == [
             "at check_at"
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
      for name <- Fixtures.names(),
          document = Fixtures.document(name),
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

        refute LazyHTML.text(html) =~
                 ~r/delivered|idempoten|One run per|transaction|In the log as/i,
               where
      end
    end

    test "a process: its deadline, who answers for it and its runs, without the key its runs are told by" do
      document = Fixtures.document("process.rehmed.clinical_visit")

      overlay =
        put_in(
          Fixtures.overlay("process.rehmed.clinical_visit"),
          ["nodes", "process:rehmed.clinical_visit", "runs"],
          4
        )

      text = owner(document, "process:rehmed.clinical_visit", :process, overlay)

      refute text =~ "One run per"
      refute text =~ "rehmed.clinical_visit"
      assert text =~ "Accountable Manager gabinetu actor"
      # A contract by its context's label, a promise by its rule.
      assert text =~ "Includes events of Umawianie i zasoby contract"
      assert text =~ "Promises After Pacjent wyszedł z gabinetu, eventually"
      assert text =~ "within 2 days promise"
      assert text =~ "From the log 4 runs."
    end

    test "a promise is titled by its rule, and keeps its verdicts" do
      promise = "promise:rehmed.clinical_visit:medical_event_reported_within_statutory_window"
      overlay = Fixtures.overlay("process.rehmed.clinical_visit")
      text = owner("process.rehmed.clinical_visit", promise, :process, overlay)

      refute text =~ "medical_event_reported_within_statutory_window"
      assert text =~ "After Pacjent wyszedł z gabinetu, eventually"
      assert text =~ "From the log"
    end

    test "a reaction: what it takes and issues and its scenarios, without delivery or data" do
      text =
        owner(
          "taxvision.registry_watch",
          "policy:taxvision.registry_watch:compare_with_registries"
        )

      assert text =~ "Takes"
      assert text =~ "Scenarios · 1 odpowiedź rejestrów idzie do porównania"
      refute text =~ "Delivery"
      refute text =~ "vat_status"

      text =
        owner(
          "taxvision.registry_watch",
          "process_manager:taxvision.registry_watch:monthly_registry_check"
        )

      refute text =~ "One run per"
      refute text =~ "check_at"
      assert text =~ "fires at a moment the run holds"
      refute text =~ "delivered at least once"
    end

    test "an effect says what it calls, and nothing of its delivery" do
      text =
        owner("rehmed.statutory_reporting", "effect:rehmed.statutory_reporting:send_p1_report")

      assert text =~
               "Calls Rejestr zdarzeń medycznych P1 external: Przyjmij zgłoszenie zdarzenia medycznego"

      refute text =~ "at least once"
      refute text =~ "harmless"
    end

    test "an engineer's panel is as it was" do
      text =
        open("rehmed.statutory_reporting", "effect:rehmed.statutory_reporting:send_p1_report")

      assert text =~ "After the transaction, delivered at least once"
    end
  end
end
