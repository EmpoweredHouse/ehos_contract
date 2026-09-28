defmodule Taxvision.Domain do
  @moduledoc """
  The vocabulary TaxVision's contracts share: subdomains, contexts and how they
  relate, actors, the public registries, and the values.

  Written on 28 September 2026 (v2 plan, E9c) from the workshop's context map,
  `workshop_output/03-ddd-architecture.md` §2–4 in `taxvision-process-native`, with
  the event names of `02-event-storming.md`. Only the contexts E9c writes contracts
  for are declared: Registry Watch and the accounting month now, work orchestration
  and notifications with E9c-2 (plan, the decisions before E9c).
  """

  use EhOsContract.Domain, name: :taxvision, language: :pl
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  # 03 §2: the office wins on standardisation at scale, so the month is the core,
  # and watching the registries is support for it.
  subdomain :core, "Rdzeń", type: :core, source: "03-ddd-architecture.md §2"
  subdomain :supporting, "Wsparcie", type: :supporting, source: "03-ddd-architecture.md §2"

  context :client_lifecycle, "Cykl życia klienta i obserwacja rejestrów",
    subdomain: :supporting,
    source: "03 §4.2 Client Lifecycle + Registry Watch"

  context :accounting_month, "Cykl miesięczny księgowy",
    subdomain: :core,
    source: "03 §4.4 Accounting Month" do
    term "Miesiąc księgowy",
      definition: "Miesiąc jednej firmy, rozliczany miesiąc w tył",
      source: "02 §3.1; WF 00:34:40" do
      translation :en, "Accounting month",
        definition: "One company's month, settled a month behind"
    end
  end

  # 03 §3 draws the arrow and names what crosses it, "RegistryDataConsistent /
  # DiscrepancyDetected", but gives it no pattern; the month is the customer of
  # those facts, so it is written as customer–supplier.
  relation :customer_supplier, upstream: :client_lifecycle, downstream: :accounting_month

  # 03 §4.10: one type of TaxVision employee, "because the work comes from duties,
  # not permissions"; the month and the check are the accountant's. The company is
  # the dimension a grant names (HS28, and the rule "the month is opened by the
  # accountant of this company", plan, 27 September).
  actor :accountant, :human, "Księgowa", scope: [:company_id]

  # The material names no actor for it: 03 §4.2's port "adapter trzyma limity i
  # retry". It records what the registries answered (D6).
  actor :registry_integration, :system, "Integracja z rejestrami publicznymi",
    backed_by: :registries,
    context: :client_lifecycle

  external :registries, "Rejestry publiczne: CEIDG/KRS, biały rejestr VAT, VIES",
    direction: :bidirectional,
    expected_latency: {10, :second},
    unavailable_looks_like: "timeout albo pusta odpowiedź — weryfikacja zawieszona, nie negatywna"

  # A period is named by its month, and the name is its identifier (plan, the
  # decisions before E9c): the timer that checks the registries on the first of the
  # month works the next one out itself. `Taxvision.Periods` keeps its dates.
  value :period, :id, label: "Okres rozliczeniowy" do
    invariant :named_by_month, "Okres to miesiąc zapisany jako RRRR-MM",
      violated_by: ["2026-7", "2026-13", "lipiec 2026", "2026-07-01"],
      satisfied_by: ["2026-07", "2026-12"]
  end

  # WF 00:32:27: "to mamy w Abilii, to mówią systemy", one row per field that differs.
  value :registry_difference, label: "Różnica między Abilią a rejestrami" do
    field :field, :string
    field :ours, :string
    field :theirs, :string
  end
end
