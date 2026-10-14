defmodule GraphLab.Contracts.ExternalPayers do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  External payers: one payer's period, a consistency boundary over the visits settlement
  charged to the payer in it. Each is marked settled with the payer or excluded with a
  reason before the period is invoiced, and nothing in the period changes after the
  invoice.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :external_payers,
    id: "graph-lab.external_payers"

  consumes GraphLab.Contracts.Settlement, :visit_charged_to_payer

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

    # Counting too much is the other way the invoice fails: a mark for a visit the
    # payer was never charged for in this period — a typo, another payer's visit, the
    # wrong month — would be billed.
    invariant :only_a_charged_visit_is_marked_or_excluded,
              "Oznacza się albo wyklucza tylko wizytę obciążającą płatnika w tym okresie, i tylko raz",
              source: "AGG-11 niezmiennik 4: „jeśli wyliczy za dużo to będzie problem z LuxMed”"

    # An invoice for a period nothing was marked in — invoiced before the first close
    # of the month, or the wrong month — would close the period to every visit charged
    # after it, and the month would go unbilled.
    invariant :an_invoice_covers_a_marked_visit,
              "Faktura obejmuje co najmniej jedną wizytę oznaczoną u płatnika",
              source: "AGG-11; S-60: moduł miesięczny po weryfikacji danych"

    # `S-58`: at reception, per visit, at the moment of settlement — a step on the
    # settlement screen, not a monthly sweep (2026-08-14).
    command :mark_settled_with_payer, "Oznacz rozliczenie u płatnika",
      by: :reception,
      emits: :visit_marked_settled_with_payer,
      rejects: [:invoiced_period_does_not_change, :only_a_charged_visit_is_marked_or_excluded],
      source: "C-48, aktor A-02; S-58" do
      field :visit_id, {:id, :visit}
    end

    # The mockup's exclude on the monthly screen. The event model has no command
    # for it; the invariant it serves has the reason in it.
    command :exclude_visit_from_invoice, "Wyłącz wizytę z rozliczenia",
      by: :manager,
      emits: :visit_excluded_from_invoice,
      rejects: [:invoiced_period_does_not_change, :only_a_charged_visit_is_marked_or_excluded],
      source: "51-mock.md §4.8; AGG-11 niezmiennik 4" do
      field :visit_id, {:id, :visit}
      field :reason, :string
    end

    command :issue_payer_invoice, "Wystaw fakturę płatnikowi",
      by: :manager,
      emits: :payer_invoice_issued,
      rejects: [
        :invoiced_period_does_not_change,
        :an_invoice_covers_a_marked_visit,
        :every_delivered_visit_settled_or_excluded
      ],
      source: "C-49, aktor A-05 (2026-08-14); S-121" do
      field :invoice_id, :id
    end

    # `E-86`, the load-bearing click: if it is not made, the payer never pays.
    event :visit_marked_settled_with_payer, "Oznaczono wizytę jako rozliczoną u płatnika",
      source: "E-86" do
      field :visit_id, {:id, :visit}
    end

    # A delivered visit that will not be invoiced has to say why. The reason is
    # accounting prose about a visit, not clinical content.
    event :visit_excluded_from_invoice,
          "Wykluczono wizytę z rozliczenia okresu, z podanym powodem",
          source: "AGG-11 niezmiennik 4" do
      field :visit_id, {:id, :visit}
      field :reason, :string
    end

    event :payer_invoice_issued, "Wystawiono fakturę miesięczną dla płatnika", source: "E-87" do
      field :invoice_id, :id
    end
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
      reason: "the patient used up the payer's allowance elsewhere"
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

  scenario "wizyta nieobciążona w tym okresie — oznaczenie odrzucone" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    command :mark_settled_with_payer, %{visit_id: "visit-ben"}
    rejected :only_a_charged_visit_is_marked_or_excluded
  end

  scenario "wizyta już oznaczona — wykluczenie jej odrzucone" do
    given :visit_charged_to_payer, %{
      visit_id: "visit-anna",
      payer_id: "payer-luxmed",
      period_id: "2026-09"
    }

    given :visit_marked_settled_with_payer, %{visit_id: "visit-anna"}
    command :exclude_visit_from_invoice, %{visit_id: "visit-anna", reason: "duplicate"}
    rejected :only_a_charged_visit_is_marked_or_excluded
  end

  scenario "nic nie oznaczono we wrześniu — faktura odrzucona, okres zostaje otwarty" do
    command :issue_payer_invoice, %{
      payer_id: "payer-luxmed",
      period_id: "2026-09",
      invoice_id: "invoice-luxmed-2026-09"
    }

    rejected :an_invoice_covers_a_marked_visit
  end
end
