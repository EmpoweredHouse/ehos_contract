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

  # What a reader sees in the panel `id` opens in `spec`, through a canvas.
  defp open(name, id, spec \\ :all) do
    {:ok, live, _html} =
      live_isolated(build_conn(), TestLive,
        session: %{"document" => Fixtures.document(name), "view" => spec}
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

    test "an event: who records it, the system it rests on, whether it ends the run, what depends on it" do
      text = open("rehmed.statutory_reporting", "event:rehmed.statutory_reporting:p1_report_sent")

      assert text =~ "Recorded by Integracja z rejestrem P1 actor"
      assert text =~ "It ends the run."
      assert text =~ "Rests on Rejestr zdarzeń medycznych P1 external"
      assert text =~ "keeps the promise medical_event_reported_within_statutory_window"
      refute text =~ "Source:"

      text =
        open("rehmed.statutory_reporting", "event:rehmed.statutory_reporting:p1_report_queued")

      assert text =~ "handled by Wyślij zgłoszenie do rejestru P1 effect, after the transaction"
    end

    test "an event of another contract says so, and one nothing depends on says that" do
      text =
        open("rehmed.statutory_reporting", "event:rehmed.statutory_reporting:visit_completed")

      assert text =~ "Declared in another contract and consumed here."
      assert text =~ "opens the promise"

      text = open("rehmed.settlement", "event:rehmed.settlement:settlement_corrected")
      assert text =~ "builds the state of Rozliczenie wizyty unit"
    end
  end

  describe "a field, the same everywhere (Pole)" do
    test "personal data, and a pointer at a person" do
      text =
        open("rehmed.statutory_reporting", "command:rehmed.statutory_reporting:queue_p1_report")

      assert text =~
               "pesel string · required Personal data of Pacjent — encrypted in the log, gone once they are erased."

      assert text =~ "patient_id id · required Points at Pacjent — in the log in the clear."
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
               ["#map"]
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

      html = render_click(target, "select", %{"id" => "actor:Taxvision.Domain:accountant"})

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".ehg-panel h4")
             |> LazyHTML.text() == "Księgowa"

      refute html =~ "is-far"
      refute html =~ "is-selected"
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
  end
end
