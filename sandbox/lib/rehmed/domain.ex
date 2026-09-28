defmodule Rehmed.Domain do
  @moduledoc """
  The vocabulary Rehmed's contracts share: subdomains, contexts and how they relate,
  actors, the patient whose data the contracts carry, the service catalogue, the P1
  registry, and the values.

  Written anew on 28 September 2026 (v2 plan, E9) from the client's own context map,
  `2-Solution/30-contexts.md` in `rehmed-process-native`, rather than translated
  from the domain E3 wrote for v2 §4.5. The identifiers in comments and in `source:`
  point into that material: `CTX-` are its contexts, `AGG-` its aggregates, `A-` its
  actors, `X-` its external systems. `docs/rehmed-2026-08-18-distillation.md` reads
  the same material for contracts.

  Only the contexts E9 writes contracts for are declared, plus configuration, which
  owns the service catalogue the other contracts point at (`AGG-15`). The map has
  ten; patient messaging, work coordination and analytics are threads through the
  others, and nothing in the stage needs them (plan, "Przed E9").
  """

  use EhOsContract.Domain, name: :rehmed, language: :pl
  use Boundary, deps: [EhOsContract], exports: [Values]

  # The map names no subdomain, only a classification per context (30-contexts.md,
  # "Core Domain Chart"), so each classification is one subdomain. `CTX-03` is
  # "core-adjacent" there, which is not a kind of its own: it sits with the core.
  subdomain :core, "Rdzeń", type: :core, source: "30-contexts.md, Core Domain Chart"

  subdomain :supporting, "Wsparcie",
    type: :supporting,
    source: "30-contexts.md, Core Domain Chart"

  subdomain :generic, "Ogólne", type: :generic, source: "30-contexts.md, Core Domain Chart"

  # The terms are the map's own table, where one Polish word means a different thing
  # in each context. The definitions are its English column in Polish, and the
  # English is kept as the translation.
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

  # Plain CRUD by the map's own account; it is here because it owns the catalogue.
  context :configuration, "Konfiguracja i ludzie", subdomain: :supporting, source: "CTX-10"

  # 30-contexts.md, "Context map": the relations between the declared contexts, as the
  # map types them. The partnership is the only one there: "the visit exists; the two
  # closes are independent".
  relation :partnership, between: [:scheduling, :clinical_documentation], terms: ["Wizyta"]
  relation :customer_supplier, upstream: :scheduling, downstream: :settlement
  relation :conformist, upstream: :clinical_documentation, downstream: :statutory_reporting
  relation :conformist, upstream: :p1, downstream: :statutory_reporting
  relation :open_host_service, upstream: :configuration, downstream: :scheduling
  relation :open_host_service, upstream: :configuration, downstream: :settlement

  # A-02, A-03
  actor :reception, :human, "Recepcja"
  actor :specialist, :human, "Specjalista"

  # The material names no actor for it: `AGG-10` has no commands and `X-01` answers
  # the send. It is the integration that records what the registry answered (D6).
  actor :p1_integration, :system, "Integracja z rejestrem P1",
    backed_by: :p1,
    context: :statutory_reporting

  # A-01. The patient never uses the system, and is the person whose data the
  # contracts carry: a PESEL and the codes of what was diagnosed.
  subject :patient, "Pacjent"

  # AGG-15. The one attribute the contracts read is the P1 flag, "one flag, not two"
  # (2026-08-17): whether a service is reported decides whether a visit is.
  entity :service, "Usługa",
    context: :configuration,
    identified_by: :service_id,
    source: "AGG-15" do
    field :service_id, :id
    field :p1_reported, :boolean, label: "Raportowana do P1"
  end

  # X-01. It answers each report, which is why it is bidirectional: out goes the
  # medical event, back comes an acceptance or a rejection (`AGG-10`, state `Błąd`).
  # Its outage is the distillation's sentence, and v2 §13 reads it as suspension.
  external :p1, "Rejestr zdarzeń medycznych P1",
    direction: :bidirectional,
    unavailable_looks_like:
      "odrzucenie zgłoszenia albo brak łączności z rejestrem; certyfikat wygasł albo nie został wgrany"

  value :money, :integer, unit: :grosze, label: "Kwota"

  # E-55: "K / G / przelew / bon"
  value :payment_method,
        {:enum, [card: "Karta", cash: "Gotówka", transfer: "Przelew", voucher: "Bon"]}
end
