defmodule GraphLab.Domain do
  @moduledoc """
  **A copy of `Rehmed.Domain` changed to test the graph on; not client material**
  (`GraphLab`).

  Rehmed's vocabulary under a name of its own, so that no id collides with Rehmed's, with
  one context added, patient messaging, and what it needs: the SMS gateway, its
  integration and the kinds of message. Why each of Rehmed's declarations is as it is,
  `Rehmed.Domain` says.

  The name is `:"graph-lab"`, with a dash, because it is the name EHOS would know the
  application by: the credential verifier lets a host start only when the audience it is
  configured with names one of the domains it runs, and EHOS never names an application
  with `_`. That is what lets the dashboard show this set alone (`mix graph_lab.traffic`
  prints how).
  """

  use EhOsContract.Domain, name: :"graph-lab", language: :pl, time_zone: "Europe/Warsaw"
  use Boundary, deps: [EhOsContract], exports: [Values]

  subdomain :core, "Rdzeń", type: :core, source: "30-contexts.md, Core Domain Chart"

  subdomain :supporting, "Wsparcie",
    type: :supporting,
    source: "30-contexts.md, Core Domain Chart"

  subdomain :generic, "Ogólne", type: :generic, source: "30-contexts.md, Core Domain Chart"

  context :scheduling, "Umawianie i zasoby", subdomain: :core, source: "CTX-01" do
    term "Wizyta", definition: "Zarezerwowany termin z zasobami", source: "CTX-01" do
      translation :en, "Visit", definition: "A held slot with resources"
    end

    term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu", source: "AGG-01, E-51"
  end

  context :clinical_documentation, "Dokumentacja kliniczna",
    subdomain: :core,
    source: "CTX-03" do
    term "Wizyta", definition: "Spotkanie kliniczne z notatką i kodami", source: "CTX-03" do
      translation :en, "Visit", definition: "A clinical encounter with a note and codes"
    end

    term "Zamknięcie",
      definition: "Kliniczna deklaracja, która uruchamia zgłoszenie do P1",
      source: "CTX-03" do
      translation :en, "Close", definition: "The clinical declaration that fires P1"
    end
  end

  context :statutory_reporting, "Zgodność i sprawozdawczość",
    subdomain: :generic,
    source: "CTX-04"

  context :settlement, "Rozliczenia", subdomain: :supporting, source: "CTX-05" do
    term "Wizyta", definition: "Należna kwota", source: "CTX-01" do
      translation :en, "Visit", definition: "An amount owed"
    end

    term "Zamknięcie", definition: "Zamknięcie komercyjne wizyty przez recepcję", source: "CTX-03" do
      translation :en, "Close", definition: "Reception's commercial close"
    end
  end

  context :external_payers, "Płatnicy zewnętrzni", subdomain: :generic, source: "CTX-06"

  context :configuration, "Konfiguracja i ludzie", subdomain: :supporting, source: "CTX-10"

  # Added for the graph: Rehmed's map has patient messaging as a thread through the
  # other contexts, and no contract for it.
  context :patient_messaging, "Komunikacja z pacjentem",
    subdomain: :generic,
    source: "dodane do testów grafu" do
    term "Wizyta",
      definition: "Termin, o którym piszemy do pacjenta",
      source: "dodane do testów grafu" do
      translation :en, "Visit", definition: "The appointment the patient is told about"
    end

    term "Wiadomość",
      definition: "SMS do pacjenta o jego wizycie",
      source: "dodane do testów grafu"
  end

  relation :partnership,
    between: [:scheduling, :clinical_documentation],
    terms: [{"Wizyta", "Wizyta"}]

  relation :customer_supplier, upstream: :scheduling, downstream: :settlement
  relation :customer_supplier, upstream: :settlement, downstream: :external_payers
  relation :conformist, upstream: :clinical_documentation, downstream: :statutory_reporting
  relation :conformist, upstream: :p1, downstream: :statutory_reporting
  relation :anticorruption_layer, upstream: :payer_system, downstream: :external_payers
  relation :open_host_service, upstream: :configuration, downstream: :scheduling
  relation :open_host_service, upstream: :configuration, downstream: :settlement

  # Added for the graph.
  relation :customer_supplier, upstream: :scheduling, downstream: :patient_messaging
  relation :conformist, upstream: :sms_gateway, downstream: :patient_messaging

  actor :reception, :human, "Recepcja"
  actor :specialist, :human, "Specjalista"

  actor :manager, :human, "Manager gabinetu" do
    responsibility :overdue_reports,
                   "Dostaje przekroczenia terminu zgłoszenia; zaległa praca trafia do niego jako liczba",
                   source: "P-25"
  end

  actor :p1_integration, :system, "Integracja z rejestrem P1",
    backed_by: :p1,
    context: :statutory_reporting

  # Added for the graph.
  actor :sms_integration, :system, "Integracja z bramką SMS",
    backed_by: :sms_gateway,
    context: :patient_messaging

  subject :patient, "Pacjent", source: "A-01"

  entity :service, "Usługa",
    context: :configuration,
    identity: :service_id,
    source: "AGG-15" do
    field :p1_reported, :boolean, label: "Raportowana do P1"
  end

  external :p1, "Rejestr zdarzeń medycznych P1",
    direction: :bidirectional,
    unavailable_looks_like:
      "odrzucenie zgłoszenia albo brak łączności z rejestrem; certyfikat wygasł albo nie został wgrany",
    source: "X-01" do
    operation :submit_report, "Przyjmij zgłoszenie zdarzenia medycznego", source: "X-01, AGG-10"
  end

  external :payer_system,
           "System rozliczeniowy płatnika zewnętrznego (LuxMed, Enelmed, TuZdrowie)",
           direction: :outbound,
           unavailable_looks_like:
             "panel płatnika niedostępny albo wizyta nie została w nim odnotowana przez człowieka — czego nasz system nie widzi",
           source: "X-02, X-03, X-04"

  # Added for the graph: it answers each message with a delivery report.
  external :sms_gateway, "Bramka SMS",
    direction: :bidirectional,
    unavailable_looks_like: "wiadomości wiszą w kolejce albo bramka odrzuca wysyłkę",
    source: "dodane do testów grafu" do
    operation :send_sms, "Wyślij SMS", source: "dodane do testów grafu"
  end

  value :money, :integer, unit: :grosze, label: "Kwota"

  value :payment_method,
        {:enum, [card: "Karta", cash: "Gotówka", transfer: "Przelew", voucher: "Bon"]},
        source: "E-55"

  # Added for the graph.
  value :message_kind,
        {:enum, [reminder: "Przypomnienie", cancellation: "Odwołanie", survey: "Ankieta"]},
        source: "dodane do testów grafu"
end
