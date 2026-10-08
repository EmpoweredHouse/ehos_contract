defmodule Taxvision.Processes.AccountingMonth do
  @moduledoc """
  The accounting month as one run (plan DD, P2f, #222): one company's month, from
  its data confirmed and checked against the registries (Registry Watch, 03 §4.2)
  through the month opened to its turnovers matched with invoices (the accounting
  month, 03 §4.4). Until P2f it was `:accounting_month` inside
  `Taxvision.Contracts.AccountingMonth`, whose moduledoc holds the two ways to open
  a month and the matching.

  The promise: two days from the confirmed data to an open month, or a discrepancy
  that blocks it — v1's assertion, on the facts of two contexts.

  Nothing ends a run yet: the month closes past E9c, so the module declares no
  `ends_on`, and no deadline, which would measure a run to its end.

  The scenarios show the promise judged (plan DD, S3 (#256)). None is excused, and
  none can be yet: both endings follow the registry check, which depends on the
  registries, but the library excuses a promise only by what its `eventually` and
  `or_else` depend on themselves, and neither does. An outage of the registries is
  refused in a scenario of this promise; whether it should reach one step upstream is
  recorded on #256.
  """

  use EhOsContract.Process,
    id: "taxvision.accounting_month",
    domain: Taxvision.Domain,
    label: "Cykl miesięczny księgowy",
    accountable: :accountant

  correlate [:company_id, :period_id]

  stage :verification,
    include: [
      {Taxvision.Contracts.RegistryWatch,
       [:data_completeness_confirmed, :registry_data_consistent, :registry_discrepancy_detected]}
    ]

  stage :opening, include: [{Taxvision.Contracts.AccountingMonth, :accounting_month_opened}]

  stage :matching,
    include: [
      {Taxvision.Contracts.AccountingMonth,
       [
         :bank_turnover_list_created,
         :turnover_matched_with_invoice,
         :turnover_without_invoice_flagged
       ]}
    ]

  # A month is settled a month behind and checked on the first [WF 00:34:40]; the
  # process declares no schedule for it, since nothing would read one.

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

  scenario "dane potwierdzone, miesiąc otwarty następnego dnia — dotrzymane",
    verdict: :satisfied,
    via: :eventually do
    given :data_completeness_confirmed, %{company_id: "abilia", period_id: "2025-12"},
      at: "2026-01-01T08:00:00+01:00"

    given :accounting_month_opened, %{company_id: "abilia", period_id: "2025-12"},
      at: "2026-01-02T09:00:00+01:00"

    promise :month_opens_or_is_blocked, at: "2026-01-05T09:00:00+01:00"
  end

  scenario "firma wykreślona z VAT — miesiąc zablokowany, dotrzymane inaczej",
    verdict: :satisfied,
    via: :or_else do
    given :data_completeness_confirmed, %{company_id: "abilia", period_id: "2025-12"},
      at: "2026-01-01T08:00:00+01:00"

    given :registry_discrepancy_detected,
          %{
            company_id: "abilia",
            period_id: "2025-12",
            differences: [%{field: "vat_status", ours: "czynny", theirs: "wykreślony"}]
          },
          at: "2026-01-01T08:05:00+01:00"

    promise :month_opens_or_is_blocked, at: "2026-01-05T09:00:00+01:00"
  end

  scenario "dane potwierdzone, miesiąc nieotwarty po dwóch dniach — niedotrzymane",
    verdict: :violated do
    given :data_completeness_confirmed, %{company_id: "abilia", period_id: "2025-12"},
      at: "2026-01-01T08:00:00+01:00"

    promise :month_opens_or_is_blocked, at: "2026-01-05T09:00:00+01:00"
  end
end
