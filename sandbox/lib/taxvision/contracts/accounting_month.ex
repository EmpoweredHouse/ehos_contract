defmodule Taxvision.Contracts.AccountingMonth do
  @moduledoc """
  The accounting month (03 §4.4, core): one company's month, opened once the
  registries agree with what TaxVision holds.

  Written anew on 28 September 2026 (v2 plan, E9c) from `03-ddd-architecture.md`
  §4.4 and §5 and phase 3.1 of `02-event-storming.md`. It replaces the v1 contract
  of the same name; its stepper past the opening — collection, matching, result — is
  E9c-2's and later.

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

  ## The promise

  Two days from the confirmed data to an open month, or a discrepancy that blocks
  it — v1's assertion, now on the facts of two contexts. `accounting_month_opened`
  keeps the workshop's name, and `check` says it starts with the unit's
  (`event-name-with-aggregate-prefix`, kept by decision before E9).
  """

  use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :accounting_month

  consumes Taxvision.Contracts.RegistryWatch, [
    :data_completeness_confirmed,
    :registry_data_consistent,
    :registry_discrepancy_detected
  ]

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

  # 03 §5, step 2.
  policy :month_opens_on_consistent_registry, "Zgodne rejestry — miesiąc się otwiera",
    handles: :registry_data_consistent,
    issues: :open_month

  process :accounting_month, "Cykl miesięczny księgowy", accountable: :accountant do
    correlate [:company_id, :period_id]

    stage :verification do
      include :data_completeness_confirmed
      include :registry_data_consistent
      include :registry_discrepancy_detected
    end

    stage :opening

    # Settled a month behind, checked on the first [WF 00:34:40].
    cadence {1, :month}

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

  scenario "zgodne rejestry otwierają miesiąc" do
    scope :month_opens_on_consistent_registry
    on :registry_data_consistent, %{company_id: "c-1", period_id: "2026-08"}
    issues :open_month, %{company_id: "c-1", period_id: "2026-08"}
  end
end
