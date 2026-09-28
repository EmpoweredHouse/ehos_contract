defmodule Rehmed.Contracts.ExternalPayers do
  @moduledoc """
  External payers (`CTX-06`): a visit a payer covers is marked settled with the
  payer, and once a month the period is invoiced with every such visit either
  marked or excluded with a reason.

  Written anew on 28 September 2026 (v2 plan, E9b) from `AGG-11` in
  `2-Solution/20-aggregates.md`, process 5 of `docs/rehmed-2026-08-18-distillation.md`
  and the mockup's payer settlement screen (`51-mock.md` §4.8, `EK-N3`). It replaces
  `Rehmed.Contracts.PayerSettlement`, the v1 contract, whose four findings are in
  the plan.

  ## One payer in one month, over visits that are another unit's

  The invariant that protects the money (`AGG-11`, added 2026-08-14) is a quantifier
  over a set: *every delivered payer-funded visit in a settlement period is either
  included in that period's invoice, or excluded with a stated reason.* The client
  names both ways it fails: leave a visit out and the clinic loses the money, count
  too much and LuxMed disputes it. v1 could not write it, because the visit is one
  run and the payer-month another.

  Here it is a dynamic consistency boundary, one payer in one period. It consults
  the visits settlement charged to that payer in that period — the fact the map says
  crosses CTX-05 → CTX-06, "which visits a payer owes for" — and reads its own marks,
  exclusions and invoice. A visit is on the invoice when reception marked it settled
  with the payer (`E-86`), since a visit the payer never saw marked is a visit the
  payer does not pay for (`AGG-11` invariant 2), so an invoice waits until each
  charged visit is marked or excluded: the mockup's two exception lists, "delivered
  but not invoiced" and "invoiced but never confirmed at the payer", become one
  refusal. `C-49`'s own rejection in the event model is "data fails verification".

  The boundary is what makes the refusal hold while reception is still closing
  visits: a visit charged to the payer between the manager's read and the invoice
  moves the boundary, and the invoice is decided again.

  ## Invoiced outside the system

  Invoicing is out of scope (`H62`): the mockup exports the period and the manager
  marks it invoiced by hand, with no "issue invoice" button (`S-121`). `C-49` keeps
  the catalogue's name and means that mark, with the number of the invoice made
  elsewhere, and "invoiced blocks inclusion again": a period is invoiced once, and
  nothing in it changes afterwards.

  ## Left out, and why

  - **Registration with the payer before delivery** (`E-85`, `C-47`) and the PESEL
    it needs at booking (`AGG-01` invariant 4, `H159`): a reminder at booking
    (`S-117`), not a rule on the invoice. The registration still cannot carry this
    run's period, as v1 found: a visit booked two months ahead can move.
  - **Restoring an excluded visit** (the mockup's restore), and a visit charged
    after its period was invoiced: settlement's fact cannot be refused here, so a
    late close lands outside an invoiced period. Both are the next command, not a
    new kind.
  - **`H47`**, whether reception clicks anything in the payer's panel after the
    visit: the mark stays, since without it the payer does not pay.
  - **`H38`**, seeing a LuxMed patient within seven days: unconfirmed, and it
    belongs to booking.
  - **The payer's system** (`X-02`–`X-04`) is in the domain, behind the map's
    anticorruption layer, and nothing depends on it: its outage is a person who did
    not retype something, which nothing here can observe (v1, finding 4).
  """

  use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :external_payers

  consumes Rehmed.Contracts.Settlement, :visit_charged_to_payer

  dcb :payer_period, "Rozliczenie płatnika za okres" do
    identity [:payer_id, :period_id]

    consults :visit_charged_to_payer, match: [:payer_id, :period_id]

    state do
      field :charged, {:list, :id}, default: []
      field :marked, {:list, :id}, default: []
      field :excluded, {:list, :id}, default: []
      field :invoiced, :boolean, default: false
    end

    invariant :every_delivered_visit_settled_or_excluded,
              "Każda wykonana wizyta płatnika w okresie jest oznaczona u płatnika albo wykluczona z podanym powodem",
              source: "AGG-11 niezmiennik 4 (2026-08-14); C-49: dane nie przechodzą weryfikacji"

    invariant :invoiced_period_does_not_change,
              "Zafakturowanego okresu się nie zmienia — faktura jest jedna, a oznaczenia i wykluczenia są przed nią",
              source: "51-mock.md §4.8: stan „zafakturowana” blokuje ponowne ujęcie"

    # `S-58`: at reception, per visit, at the moment of settlement — a step on the
    # settlement screen, not a monthly sweep (2026-08-14).
    command :mark_settled_with_payer, "Oznacz rozliczenie u płatnika",
      by: :reception,
      emits: :visit_marked_settled_with_payer,
      rejects: :invoiced_period_does_not_change,
      source: "C-48, aktor A-02; S-58" do
      field :visit_id, :id
    end

    # The mockup's exclude on the monthly screen. The event model has no command
    # for it; the invariant it serves has the reason in it.
    command :exclude_visit_from_invoice, "Wyłącz wizytę z rozliczenia",
      by: :manager,
      emits: :visit_excluded_from_invoice,
      rejects: :invoiced_period_does_not_change,
      source: "51-mock.md §4.8; AGG-11 niezmiennik 4" do
      field :visit_id, :id
      field :reason, :string
    end

    command :issue_payer_invoice, "Wystaw fakturę płatnikowi",
      by: :manager,
      emits: :payer_invoice_issued,
      rejects: [:invoiced_period_does_not_change, :every_delivered_visit_settled_or_excluded],
      source: "C-49, aktor A-05 (2026-08-14); S-121" do
      field :invoice_id, :id
    end

    stage :reconciliation do
      # `E-86`, the load-bearing click: if it is not made, the payer never pays.
      event :visit_marked_settled_with_payer, "Oznaczono wizytę jako rozliczoną u płatnika",
        source: "E-86" do
        field :visit_id, :id
      end

      # A delivered visit that will not be invoiced has to say why. The reason is
      # accounting prose about a visit, not clinical content.
      event :visit_excluded_from_invoice,
            "Wykluczono wizytę z rozliczenia okresu, z podanym powodem",
            source: "AGG-11 niezmiennik 4" do
        field :visit_id, :id
        field :reason, :string
      end
    end

    stage :invoicing do
      event :payer_invoice_issued, "Wystawiono fakturę miesięczną dla płatnika",
        terminal: true,
        source: "E-87" do
        field :invoice_id, :id
      end
    end
  end

  # One run is one payer in one month; LuxMed, Enelmed and TuZdrowie settle
  # independently and identically (2026-08-14). Once a month the practice manager
  # opens the module, verifies and invoices: human-initiated, so the cadence is a
  # declaration nothing enforces.
  process :payer_settlement, "Miesięczne rozliczenie z płatnikiem zewnętrznym",
    accountable: :manager do
    correlate [:payer_id, :period_id]

    stage :charging do
      include :visit_charged_to_payer
    end

    stage :reconciliation
    stage :invoicing
    cadence {1, :month}
  end

  scenario "obie wizyty LuxMed z września oznaczone u płatnika — faktura wystawiona" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_charged_to_payer, %{
      visit_id: "visit-ben",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}
    given :visit_marked_settled_with_payer, %{visit_id: "visit-ben"}
    command :issue_payer_invoice, %{invoice_id: "invoice-luxmed-2026-09"}
    expect :payer_invoice_issued, %{invoice_id: "invoice-luxmed-2026-09"}
  end

  # Leave a visit out and the clinic loses the money.
  scenario "wizyta Bena nieoznaczona i niewykluczona — faktura odrzucona" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_charged_to_payer, %{
      visit_id: "visit-ben",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}
    command :issue_payer_invoice, %{invoice_id: "invoice-luxmed-2026-09"}
    rejected :every_delivered_visit_settled_or_excluded
  end

  scenario "wizyta Bena wykluczona z powodem — faktura za resztę wystawiona" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_charged_to_payer, %{
      visit_id: "visit-ben",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}

    given :visit_excluded_from_invoice, %{
      visit_id: "visit-ben",
      reason: "pacjent wykorzystał limit sesji u płatnika"
    }

    command :issue_payer_invoice, %{invoice_id: "invoice-luxmed-2026-09"}
    expect :payer_invoice_issued
  end

  scenario "okres zafakturowany — oznaczenie po fakturze odrzucone" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}
    given :payer_invoice_issued, %{invoice_id: "invoice-luxmed-2026-09"}
    command :mark_settled_with_payer, %{visit_id: "visit-ben"}
    rejected :invoiced_period_does_not_change
  end

  scenario "recepcja oznacza wizytę u płatnika przy rozliczeniu" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    command :mark_settled_with_payer, %{visit_id: "visit-anna"}
    expect :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}
  end
end
