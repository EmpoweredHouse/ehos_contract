defmodule Taxvision.Contracts.AccountingMonth do
  @moduledoc """
  The accounting month (03 §4.4, core): one company's month, opened once the
  registries agree with what TaxVision holds.

  Written anew on 28 September 2026 (v2 plan, E9c) from `03-ddd-architecture.md`
  §4.4 and §5 and phase 3.1 of `02-event-storming.md`. It replaces the v1 contract
  of the same name. Matching was added with E9c-2 (phase 3.3); the rest of the
  stepper — collection, clarifications, the result — is not in E9.

  ## Two ways to open, one rule

  §5: when the data agrees, a policy opens the month (`OpenMonth` after
  `RegistryDataConsistent`). The accountant can open it by hand as well, as the
  company's own accountant only (the user's decision before E9c, `scope`). Either
  way the month opens only when the latest check of that month agreed (WF
  00:35:41), and once: a boundary over one company's month that consults
  Registry Watch's verdicts, since the month cannot see another context's facts
  otherwise (v2 §2, "opening a month by hand").

  ## Before the tasks, not after

  The workshop's §3.1 diagram generates the tasks before the month opens; the
  architecture of 03 §5 and §4.5 opens it first and generates tasks only for a
  month that is open. The later document is followed here, and the tasks are
  E9c-2's.

  ## Matching

  P6: a bank statement becomes a list of turnovers, and every turnover is matched.
  The accountant uploads the statement already parsed — parsers are the client's
  cost, not the library's — and a policy issues one `run_matching` per turnover.
  P7: the turnover is paired with an invoice KSeF gave for that company and month,
  by a domain service, `:pairing`. Pairing here is by amount alone; an invoice pairs
  once, and a turnover is decided once, so a statement uploaded again changes
  nothing already decided. The material's margin of days, one turnover paying many
  invoices and an invoice arriving after its turnover are left out (plan, the
  decisions before E9c-2: the kinds, not the domain's detail).

  ## Out to Shugyo

  Shugyo reads the month's events (03 §3, the event stream from every context to Shugyo, A9); the opening
  leaves as `taxvision.accounting_month.opened.v1`. The relay is E12's, so nothing
  leaves yet.

  ## The promise

  Two days from the confirmed data to an open month, or a discrepancy that blocks
  it — v1's assertion, now on the facts of two contexts. `accounting_month_opened`
  keeps the workshop's name, and `check` says it starts with the unit's
  (`event-name-with-aggregate-prefix`, kept by decision before E9).
  """

  use EhOsContract.Contract,
    domain: Taxvision.Domain,
    context: :accounting_month,
    id: "taxvision.accounting_month"

  consumes Taxvision.Contracts.RegistryWatch, [
    :data_completeness_confirmed,
    :registry_data_consistent,
    :registry_discrepancy_detected
  ]

  consumes Taxvision.Contracts.DocumentIntake, [:invoice_pulled_from_ksef]

  dcb :accounting_month, "Miesiąc księgowy firmy" do
    identity [:company_id, :period_id]

    consults :registry_data_consistent, match: [:company_id, :period_id]
    consults :registry_discrepancy_detected, match: [:company_id, :period_id]

    state do
      field :consistent, :boolean, default: false
      field :opened, :boolean, default: false
    end

    invariant :opens_only_on_consistent_registry,
              "Bez zgodnej weryfikacji rejestrowej miesiąc się nie otwiera",
              source: "WF 00:34:17-00:36:07 (P1), WF 00:35:41; 03 §4.4"

    # Both the policy and the accountant may open the month; the second is refused.
    invariant :opens_once, "Miesiąc otwiera się raz", source: "03 §4.4, stepper"

    command :open_month, "Otwórz miesiąc księgowy",
      by: :accountant,
      scope: :company_id,
      emits: :accounting_month_opened,
      rejects: [:opens_once, :opens_only_on_consistent_registry],
      source: "03 §4.4 OpenMonth; ręcznie przez księgową tej firmy (decyzja przed E9c)"

    stage :opening do
      event :accounting_month_opened, "Otwarto miesiąc księgowy",
        source: "02 §3.1 AccountingMonthOpened"
    end
  end

  # 03 §4.4: TurnoverInvoiceMatch, "tabela ciągła" of one company's month.
  dcb :turnover_matching, "Dopasowywanie obrotów z fakturami" do
    identity [:company_id, :period_id]

    consults :invoice_pulled_from_ksef, match: [:company_id, :period_id]

    state do
      field :invoices, {:list, :invoice}, default: []
      field :paired, {:list, :ksef_number}, default: []
      field :decided, {:list, :id}, default: []
    end

    # A statement uploaded again, or one overlapping the last, issues a match for a
    # turnover already decided; the first answer stands.
    invariant :a_turnover_is_matched_once, "Obrót dopasowuje się raz",
      source: "02 §3.3 (tabela ciągła; obroty doklejają się na bieżąco)"

    command :ingest_bank_statement, "Wgraj wyciąg bankowy",
      by: :accountant,
      scope: :company_id,
      emits: :bank_turnover_list_created,
      source: "03 §4.4 IngestBankStatement; 02 §3.3 (MT940/CSV)" do
      field :turnovers, {:list, :turnover}
    end

    # Issued by the policy, one per turnover, never by a person.
    command :run_matching, "Dopasuj obrót do faktury",
      emits: [:turnover_matched_with_invoice, :turnover_without_invoice_flagged],
      rejects: :a_turnover_is_matched_once,
      source: "03 §4.4 RunMatching; P7" do
      field :turnover, :turnover
    end

    stage :matching do
      event :bank_turnover_list_created, "Utworzono listę obrotów z wyciągu",
        source: "02 §3.3 BankTurnoverListCreated; WF 01:05:01" do
        field :turnovers, {:list, :turnover}
      end

      event :turnover_matched_with_invoice, "Połączono obrót z fakturą",
        source: "02 §3.3 TurnoverMatchedWithInvoice; WF 01:07:12" do
        field :turnover_id, :id
        field :ksef_number, :ksef_number
      end

      event :turnover_without_invoice_flagged, "Obrót bez faktury",
        source: "02 §3.3 TurnoverWithoutInvoiceFlagged; WF 01:19:25" do
        field :turnover_id, :id
      end
    end
  end

  domain_service :pairing, "Parowanie obrotów z fakturami" do
    function :invoice_for, "Faktura, z którą paruje się obrót" do
      argument :amount_minor, :integer, label: "Kwota obrotu"
      argument :invoices, {:list, :invoice}, label: "Faktury bez pary"
      returns :ksef_number, optional: true

      rule :same_amount, "Obrót paruje się z fakturą na tę samą kwotę",
        examples: [
          {[
             12_300,
             [%{ksef_number: "5265877635-20260714-0A1B2C3D4E5F-9A", amount_minor: 12_300}]
           ], "5265877635-20260714-0A1B2C3D4E5F-9A"}
        ]

      rule :none_without_same_amount, "Bez faktury na tę samą kwotę obrót zostaje bez pary",
        examples: [
          {[12_300, [%{ksef_number: "5265877635-20260714-0A1B2C3D4E5F-9A", amount_minor: 9_900}]],
           nil},
          {[12_300, []], nil}
        ]
    end
  end

  policy :month_opens_on_consistent_registry, "Zgodne rejestry — miesiąc się otwiera",
    handles: :registry_data_consistent,
    issues: :open_month,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure],
    source: "03 §5, step 2"

  # P6: when a statement (CSV/MT940) is uploaded, parse it into turnovers and match them.
  policy :match_each_turnover, "Wyciąg wgrany — dopasuj każdy obrót",
    handles: :bank_turnover_list_created,
    issues: :run_matching,
    source: "P6"

  publish :month_opened,
    as: "taxvision.accounting_month.opened.v1",
    from: :accounting_month_opened,
    fields: [:company_id, :period_id],
    idempotent_on: [:company_id, :period_id]

  process :accounting_month, "Cykl miesięczny księgowy", accountable: :accountant do
    correlate [:company_id, :period_id]

    stage :verification do
      include :data_completeness_confirmed
      include :registry_data_consistent
      include :registry_discrepancy_detected
    end

    stage :opening
    stage :matching

    # A month is settled a month behind and checked on the first [WF 00:34:40]; the
    # contract declares no schedule for it, since nothing would read one.

    # v1's `deadline {25, :day}` is not here: nothing ends a run until the month
    # closes, which is past E9c, so there is nothing for it to measure; and nobody
    # from TaxVision gave the 25th for the office's work.

    promise :month_opens_or_is_blocked do
      from :data_completeness_confirmed
      eventually :accounting_month_opened
      within {2, :day}
      or_else :registry_discrepancy_detected
      source "WF 00:34:17-00:36:07 (P1)"
    end
  end

  scenario "dane zgodne — miesiąc się otwiera" do
    given :registry_data_consistent, %{company_id: "c-1", period_id: "2026-08"}
    command :open_month
    expect :accounting_month_opened
  end

  scenario "rozjazd statusu VAT — miesiąc zablokowany" do
    given :registry_discrepancy_detected, %{
      company_id: "c-1",
      period_id: "2026-08",
      differences: [%{field: "vat_status", ours: "czynny", theirs: "wykreślony"}]
    }

    command :open_month
    rejected :opens_only_on_consistent_registry
  end

  scenario "ponowiona weryfikacja zgodna — zablokowany miesiąc się otwiera" do
    given :registry_discrepancy_detected, %{
      company_id: "c-1",
      period_id: "2026-08",
      differences: [%{field: "vat_status", ours: "czynny", theirs: "wykreślony"}]
    }

    given :registry_data_consistent, %{company_id: "c-1", period_id: "2026-08"}
    command :open_month
    expect :accounting_month_opened
  end

  scenario "miesiąc już otwarty — drugie otwarcie odrzucone" do
    given :registry_data_consistent, %{company_id: "c-1", period_id: "2026-08"}
    given :accounting_month_opened
    command :open_month
    rejected :opens_once
  end

  scenario "obrót na kwotę faktury z KSeF — sparowany" do
    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A",
      amount_minor: 12_300,
      issued_on: "2026-08-14"
    }

    command :run_matching, %{
      turnover: %{turnover_id: "t-1", amount_minor: 12_300, booked_on: "2026-08-20"}
    }

    expect :turnover_matched_with_invoice, %{
      turnover_id: "t-1",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A"
    }
  end

  scenario "faktura już sparowana — drugi obrót na tę kwotę bez faktury" do
    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A",
      amount_minor: 12_300,
      issued_on: "2026-08-14"
    }

    given :turnover_matched_with_invoice, %{
      turnover_id: "t-1",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A"
    }

    command :run_matching, %{
      turnover: %{turnover_id: "t-2", amount_minor: 12_300, booked_on: "2026-08-21"}
    }

    expect :turnover_without_invoice_flagged, %{turnover_id: "t-2"}
  end

  scenario "obrót już rozstrzygnięty — ponowne dopasowanie odrzucone" do
    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A",
      amount_minor: 12_300,
      issued_on: "2026-08-14"
    }

    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260815-0A1B2C3D4E60-3C",
      amount_minor: 12_300,
      issued_on: "2026-08-15"
    }

    given :turnover_matched_with_invoice, %{
      turnover_id: "t-1",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A"
    }

    command :run_matching, %{
      turnover: %{turnover_id: "t-1", amount_minor: 12_300, booked_on: "2026-08-20"}
    }

    rejected :a_turnover_is_matched_once
  end

  scenario "faktura pobrana z KSeF drugi raz — sparowana nie paruje się ponownie" do
    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A",
      amount_minor: 12_300,
      issued_on: "2026-08-14"
    }

    given :turnover_matched_with_invoice, %{
      turnover_id: "t-1",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A"
    }

    given :invoice_pulled_from_ksef, %{
      company_id: "c-1",
      period_id: "2026-08",
      ksef_number: "5265877635-20260814-0A1B2C3D4E5F-9A",
      amount_minor: 12_300,
      issued_on: "2026-08-14"
    }

    command :run_matching, %{
      turnover: %{turnover_id: "t-2", amount_minor: 12_300, booked_on: "2026-08-21"}
    }

    expect :turnover_without_invoice_flagged, %{turnover_id: "t-2"}
  end

  scenario "wyciąg z dwoma obrotami — dwa dopasowania" do
    target :match_each_turnover

    on :bank_turnover_list_created, %{
      company_id: "c-1",
      period_id: "2026-08",
      turnovers: [
        %{turnover_id: "t-1", amount_minor: 12_300, booked_on: "2026-08-20"},
        %{turnover_id: "t-2", amount_minor: 4_500, booked_on: "2026-08-21"}
      ]
    }

    issues :run_matching, %{
      turnover: %{turnover_id: "t-1", amount_minor: 12_300, booked_on: "2026-08-20"}
    }

    issues :run_matching, %{
      turnover: %{turnover_id: "t-2", amount_minor: 4_500, booked_on: "2026-08-21"}
    }
  end

  scenario "zgodne rejestry otwierają miesiąc" do
    target :month_opens_on_consistent_registry
    on :registry_data_consistent, %{company_id: "c-1", period_id: "2026-08"}
    issues :open_month, %{company_id: "c-1", period_id: "2026-08"}
  end
end
