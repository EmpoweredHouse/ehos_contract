defmodule Taxvision.Contracts.AccountingMonth do
  @moduledoc """
  Opening the accounting month — phase 3.1 of the TaxVision workshop.

  Every event name comes from the workshop; none is invented. Source:
  `workshop_output/02-event-storming.md`, section 3.1, policy P1 from section 10,
  and the invariants of the `AccountingMonth` aggregate from section 12.

  The contract registers itself — there is no aggregating module. A parent module
  including its children looks tidy and brings the problem back: the parent has a
  compile dependency on every child, handlers depend on the parent, so one event
  recompiles everything.

  The Polish strings here are deliberate and are the only Polish in the codebase:
  `label`, the example descriptions, `source` and `unavailable_looks_like` are
  read as sentences by the process owner, so they are written in their language.
  Everything else — event names, stage names, field names — is an identifier.
  """

  use EhOsContract.Contract

  # --- phase 3.1: implemented ---

  event :data_completeness_confirmed,
    label: "Potwierdzono komplet danych historycznych",
    owner: Taxvision.RegistryCheck,
    # There is no `confirmed_by` here. Who confirmed is known to the **engine** —
    # `actor` is a column of the log, carried by every event, passing through
    # causation and across the job boundary. A payload field would duplicate the
    # same truth in a second place, and two sources of truth about one fact drift
    # apart exactly when they are needed for an audit.
    payload: %{company_id: :id, period_id: :id},
    process: :accounting_month,
    stage: :verification

  event :registry_status_checked,
    label: "Sprawdzono status w CEIDG/KRS, białym rejestrze VAT i VIES",
    owner: Taxvision.RegistryCheck,
    depends_on: :registries,
    payload: %{company_id: :id, period_id: :id, checked_at: :timestamp},
    process: :accounting_month,
    stage: :verification

  event :registry_check_logged,
    label: "Zapisano datę ostatniego sprawdzenia rejestrów",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period_id: :id, checked_at: :timestamp},
    process: :accounting_month,
    stage: :verification

  event :registry_data_consistent,
    label: "Dane firmy zgadzają się z rejestrami",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period_id: :id},
    process: :accounting_month,
    stage: :verification

  event :registry_discrepancy_detected,
    label: "Dane firmy nie zgadzają się z rejestrami",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period_id: :id, diff: :string},
    # The diff carries the company's data set against the public registries. A
    # hash goes to the log: proof that a divergence happened and which one,
    # without keeping the content forever.
    retain: %{diff: :hash},
    # A fact's identity covers the **content** of the divergence, not only the
    # company and the month. The version without `diff` had a hole that is hard to
    # see: if on 1 July the divergence is on VAT status and on 5 July on legal
    # form, the second problem would be swallowed by the first one's key. The same
    # divergence = one notification, a different divergence = a new one.
    #
    # `diff` is hashed by `retain`, and that is an advantage here: the key is
    # deterministic, so idempotency works, while it does not contain the company's
    # data set against the registries.
    identity: [:company_id, :period_id, :diff],
    process: :accounting_month,
    stage: :verification

  event :monthly_tasks_generated,
    label: "Utworzono taski z szablonu na nowy miesiąc",
    owner: Taxvision.Tasks,
    payload: %{company_id: :id, period_id: :id, task_count: :integer},
    process: :accounting_month,
    stage: :opening

  event :accounting_month_opened,
    label: "Otwarto miesiąc księgowy",
    owner: Taxvision.AccountingMonth,
    payload: %{company_id: :id, period_id: :id},
    process: :accounting_month,
    stage: :opening

  event :discrepancy_notification_sent,
    label: "Wysłano powiadomienie o rozjeździe do księgowej i klienta",
    owner: Taxvision.Notifications,
    payload: %{company_id: :id, period_id: :id, recipients: :integer},
    process: :accounting_month,
    stage: :verification,
    terminal: true

  # --- later phases: declared, deliberately unimplemented ---
  #
  # This is not unfinished work. It is a demonstration of the "declared, never
  # observed" state (notes §5, §9): `mix eh_os_contract.check` and `mix eh_os_contract.graph --overlay`
  # are meant to list them as dead paths, because that is exactly what a contract
  # running ahead of its implementation looks like — the normal state mid-rollout.

  event :bank_statement_received,
    label: "Otrzymano wyciąg bankowy (MT940/CSV; PDF nie wchodzi)",
    owner: Taxvision.Matching,
    payload: %{company_id: :id, period_id: :id, format: :enum},
    process: :accounting_month,
    stage: :collection

  event :turnover_matched_with_invoice,
    label: "Sparowano obrót z fakturą",
    owner: Taxvision.Matching,
    # The period was added by the instance gate and is **not cosmetic**: without it
    # a matched turnover does not say which month it belongs to, so matching from
    # July would count as progress in the August run. This is the only event in
    # this contract that failed that gate.
    payload: %{company_id: :id, period_id: :id, turnover_id: :id, invoice_id: :id},
    process: :accounting_month,
    stage: :matching

  event :month_closed,
    label: "Zamknięto miesiąc księgowy",
    owner: Taxvision.AccountingMonth,
    payload: %{company_id: :id, period_id: :id},
    process: :accounting_month,
    stage: :closing,
    terminal: true

  # --- the process ---

  # **One process, several stages — and order exists only between stages.**
  #
  # The workshop says: this is one long process, from the registry check at the
  # start of the month to closing the month; phase 3.1 is the opening gate and the
  # rest are the stepper's steps. And immediately after: the stages are not fully
  # sequential, the gates are — without a positive check the month does not open,
  # without a statement there is no matching, without matching there is no export.
  #
  # So order is declared between stages, and within a stage there is none at all.
  # Backward-edge detection rests on this, so it is not cosmetic: a check can only
  # be as true as the model it stands on.
  #
  # **The process does not list its events** — every event says for itself which
  # process and which stage it belongs to. The previous version had a list of
  # eleven names here, that is, every event name in the contract written twice.
  # **No `source:`, and that is a finding rather than an omission.** The workshop's
  # own diagram for §3.1 opens the month as a cron-triggered chain of system checks
  # and marks exactly one command on it, `RetriggerVerification`. Nobody in the room
  # named the opening itself as an action somebody takes. It is declared here because
  # the rules below are written as refusals of it — so the command exists in the
  # contract while its provenance does not, and an empty `source:` says so.
  command :open_month,
    label: "Otwarcie miesiąca księgowego",
    process: :accounting_month,
    principals: [:human],
    payload: %{company_id: :id, period: :string}

  # The command the workshop named and this contract omitted — recorded as debt in
  # `PLAN.md` since August. Source: `02-event-storming.md` §3.1, where it is the only
  # command on the accounting-month diagram: after a discrepancy notice goes out, the
  # accountant may re-run the registry check.
  #
  # Actor is Księgowa, so `[:human]`. The rest of that diagram is `cron` and system
  # checks, which is why this process has two commands and not eight.
  command :retrigger_verification,
    label: "Ponowienie weryfikacji rejestrowej",
    process: :accounting_month,
    principals: [:human],
    payload: %{company_id: :id, period: :string},
    source: "Warsztat: 02-event-storming.md §3.1, jedyna komenda na tym diagramie"

  process :accounting_month,
    label: "Cykl miesięczny księgowy",
    # Stage names are **identifiers, not labels** — they go into `eh_os_contract.check`, into
    # the graph and into the contract's version key, so they are in English like
    # the rest of the code. What is in Polish is what the client reads: `label`
    # and the example descriptions.
    #
    # All that remains here is the **order** of stages, because that is the one
    # thing an event cannot say about itself.
    stages: [:verification, :opening, :collection, :matching, :closing],
    # One run is **one company in one month**. It is the same key the workshop
    # settles by ("the month is settled one month behind"), and it is the boundary
    # within which an assertion is counted: opening the month for c-2 credits
    # nothing to c-1's run.
    instance: [:company_id, :period_id],
    # Settlement is one month behind, and a check on the first day of the month is
    # enough [WF 00:34:40]. The "never observed" window is computed from this —
    # without a cadence a monthly process reads as dead six days after its last
    # run.
    cadence: {1, :month},
    deadline: {25, :day},
    # The 25th is the real statutory JPK_V7 deadline, so the number is plausible —
    # but **nobody from TaxVision supplied it**, and the deadline for filing a
    # return is not the same as the deadline for finishing work in the office.
    # Until the process owner confirms it, this does not count towards the
    # evidence report.
    unverified: [:deadline]

  # --- the assertion ---

  trace :month_opens_or_is_blocked do
    from :data_completeness_confirmed
    eventually :accounting_month_opened, within: {2, :day}
    or_else :discrepancy_notification_sent
  end

  # --- external dependencies, named after the fact rather than the vendor ---

  external :registries,
    label: "Rejestry publiczne: CEIDG/KRS, biały rejestr VAT, VIES",
    expected_latency: {10, :second},
    unavailable_looks_like: "timeout albo pusta odpowiedź — weryfikacja zawieszona, nie negatywna"

  # --- rules and examples (ADR §18) ---

  rule :month_opens_only_on_consistent_registry,
    label: "Bez zgodnej weryfikacji rejestrowej miesiąc się nie otwiera",
    function: {Taxvision.RegistryCheck, :decide, 1},
    source: "Warsztat WF 00:34:17-00:36:07 (polityka P1), WF 00:35:41"

  # **The command carries the period's name; `given:` carries its identifier.**
  #
  # These stopped being the same shape on 6 August, when a fact began carrying
  # `period_id`. A command is what a person issues, so it reads "2026-07"; a decision
  # function receives the input the request edge has already resolved. `given:` is what
  # stands in for that machinery, which is what it was always for.
  #
  # The identifier here is legible on purpose. `:id` means *an identifier*, not *a uuid* —
  # what it refers to is the client application's business — so an example may use one a
  # person can read aloud. Runtime uses the uuid the periods table generates. Putting a
  # real uuid in a contract would trade §18's whole property, that an example is readable
  # to the process owner, for a consistency nothing needs.
  example "komplet danych i zgodne rejestry — miesiąc się otwiera",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      period_id: "period-2026-07",
      completeness_confirmed: true,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    # Only this event is the substance of this rule. `then:` means "among those
    # emitted, in this order" — not "exactly these".
    then: [:registry_data_consistent]

  example "rozjazd statusu VAT — blokada i powiadomienie zamiast otwarcia",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      period_id: "period-2026-07",
      completeness_confirmed: true,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    then: [:registry_discrepancy_detected]

  example "brak potwierdzenia kompletu danych — komenda odrzucona",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      period_id: "period-2026-07",
      completeness_confirmed: false,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    rejected_with: :data_completeness_not_confirmed

  # The third IAM level: the domain rule. Inexpressible in an identity provider's
  # configuration, because the provider knows nothing about an accounting month or
  # about whose company this is.
  rule :only_company_accountant_opens_month,
    label:
      "Miesiąc otwiera księgowa przypisana do tej firmy, nie klient i nie księgowa innej firmy",
    function: {Taxvision.Authorization, :authorize_open_month, 1},
    source: "Warsztat: aktor fazy 3.1 to Księgowa + System; HS28 (model dwóch osi dostępu)"

  example "księgowa własnej firmy — wolno",
    rule: :only_company_accountant_opens_month,
    given: %{actor_roles: ["accounting"], actor_company: "c-1"},
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    then: []

  example "księgowa innej firmy — nie wolno, i to nie jest 403 od providera",
    rule: :only_company_accountant_opens_month,
    given: %{actor_roles: ["accounting"], actor_company: "c-2"},
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    rejected_with: :not_this_company
end
