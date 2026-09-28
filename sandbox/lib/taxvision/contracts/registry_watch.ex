defmodule Taxvision.Contracts.RegistryWatch do
  @moduledoc """
  Client lifecycle and Registry Watch (03 §4.2): whether what TaxVision holds about
  a company agrees with the public registries, checked once a month.

  Written on 28 September 2026 (v2 plan, E9c) from `03-ddd-architecture.md` §4.2
  and §5 and phase 3.1 of `02-event-storming.md`, whose event names these are.

  ## The first of the month

  P1: when a month starts, check the registries. The month is settled one month
  behind, so on 1 September August is checked (WF 00:34:40). A process manager does
  it: every check that starts — the company's data confirmed — sets a timer for the
  first of the month after the next period, which checks that period. The name of
  the period is its identifier, so it works "2026-09" and 1 October out of "2026-08"
  itself. The period it keeps only moves forward, so the accountant retrying an
  older month does not set the watch back, and the registries being down for one
  check leaves that month to be retried while the next one is still checked. The
  first check is the accountant's (`RetriggerVerification`, the one command on the
  workshop's diagram); a check refused because the company's data is incomplete
  starts nothing, so the watch waits for the accountant too.

  ## A check is three steps, and the middle one is the registries'

  The check confirms the company's data is complete (`DataCompletenessConfirmed`),
  the registries are asked outside any transaction and their answer recorded by the
  integration (`RegistryStatusChecked`, D6), and the answer is compared with what
  TaxVision holds, which logs the check and says whether the data agrees. An outage
  of the registries is a suspension, not a negative check (v1, ADR §11–12).

  ## What TaxVision holds

  The company's legal form and VAT status come from its profile, which is
  onboarding's (03 §4.1, `CompleteCompanyProfile`). Onboarding is outside E9, so the
  profile's completion is recorded here, where the check reads it — ours, and said
  so. The historical-data checkbox (`ConfirmDataCompleteness`) is part of it.

  ## Left out

  The service status (lead / active / suspended for non-payment) and the VAT
  restoration process (`VatStatusRestored`), which have no reader in E9, and the
  notification with the diff, which is E9c-2's (Notifications).
  """

  use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :client_lifecycle

  aggregate :client, "Firma klienta" do
    identity :company_id

    state do
      field :profile_complete, :boolean, default: false
      field :legal_form, :string, optional: true
      field :vat_status, :string, optional: true
    end

    invariant :checked_only_with_complete_data,
              "Rejestry sprawdza się tylko dla firmy z kompletem danych",
              source: "02 §3.1 (DataCompletenessConfirmed przed sprawdzeniem); 03 §4.1"

    command :complete_company_profile, "Uzupełnij profil firmy",
      by: :accountant,
      scope: :company_id,
      emits: :company_profile_completed,
      source: "03 §4.1 CompleteCompanyProfile, ConfirmDataCompleteness" do
      field :legal_form, :string
      field :vat_status, :string
    end

    # Issued by the timer on the first of the month, never by a person.
    command :check_registries, "Sprawdź rejestry",
      emits: :data_completeness_confirmed,
      rejects: :checked_only_with_complete_data,
      source: "03 §4.2 CheckRegistries; P1" do
      field :period_id, :period
    end

    command :retrigger_verification, "Ponów weryfikację",
      by: :accountant,
      scope: :company_id,
      emits: :data_completeness_confirmed,
      rejects: :checked_only_with_complete_data,
      source: "02 §3.1 RetriggerVerification, jedyna komenda na diagramie" do
      field :period_id, :period
    end

    # Issued by the policy on the registries' answer, never by a person.
    command :log_registry_check, "Zapisz wynik sprawdzenia rejestrów",
      emits: [:registry_check_logged, :registry_data_consistent, :registry_discrepancy_detected],
      source: "02 §3.1 RegistryCheckLogged; WF 00:31:42" do
      field :period_id, :period
      field :legal_form, :string
      field :vat_status, :string
    end

    stage :profile do
      event :company_profile_completed, "Uzupełniono profil firmy",
        source: "03 §4.1 CompanyProfileCompleted" do
        field :legal_form, :string
        field :vat_status, :string
      end
    end

    stage :verification do
      event :data_completeness_confirmed, "Potwierdzono komplet danych firmy na miesiąc",
        source: "02 §3.1 DataCompletenessConfirmed" do
        field :period_id, :period
      end

      event :registry_status_checked,
            "Sprawdzono status w CEIDG/KRS, białym rejestrze VAT i VIES",
            recorded_by: :registry_integration,
            depends_on: :registries,
            source: "02 §3.1 RegistryStatusChecked; WF 00:30:54" do
        field :period_id, :period
        field :legal_form, :string
        field :vat_status, :string
        field :vies_status, :string
      end

      event :registry_check_logged, "Zapisano datę ostatniego sprawdzenia rejestrów",
        source: "02 §3.1 RegistryCheckLogged" do
        field :period_id, :period
      end

      event :registry_data_consistent, "Dane firmy zgadzają się z rejestrami",
        source: "02 §3.1 RegistryDataConsistent" do
        field :period_id, :period
      end

      # The differences, not the company's whole data set: legal form and VAT status
      # are public registry data, not a person's, so nothing here is sealed.
      event :registry_discrepancy_detected, "Dane firmy nie zgadzają się z rejestrami",
        source: "02 §3.1 RegistryDiscrepancyDetected; WF 00:32:27" do
        field :period_id, :period
        field :differences, {:list, :registry_difference}
      end
    end
  end

  # 03 §4.2, P: "kiedy 1. dzień miesiąca (cron) -> CheckRegistries".
  effect :look_up_registries, "Zapytaj rejestry publiczne",
    handles: :data_completeness_confirmed,
    calls: :registries,
    idempotency: :event_id

  policy :compare_with_registries, "Porównaj odpowiedź rejestrów z danymi firmy",
    handles: :registry_status_checked,
    issues: :log_registry_check

  process_manager :monthly_registry_check, "Sprawdzenie rejestrów na początku miesiąca" do
    correlate :company_id

    state do
      field :period_id, :period, optional: true
      field :check_at, :timestamp, optional: true
    end

    starts_on :data_completeness_confirmed, sets: :next_month
    on :data_completeness_confirmed, sets: :next_month
    timer :next_month, at: :check_at, issues: :check_registries
  end

  process :client, "Firma klienta: dane i zgodność z rejestrami", accountable: :accountant do
    correlate :company_id
    stage :profile
    stage :verification
  end

  scenario "księgowa uzupełnia profil firmy" do
    command :complete_company_profile, %{legal_form: "JDG", vat_status: "czynny"}
    expect :company_profile_completed, %{legal_form: "JDG"}
  end

  scenario "profil nieuzupełniony — rejestrów się nie sprawdza" do
    command :check_registries, %{period_id: "2026-08"}
    rejected :checked_only_with_complete_data
  end

  scenario "1 września — sprawdzenie sierpnia zaczyna się od potwierdzenia kompletu danych" do
    given :company_profile_completed, %{legal_form: "JDG", vat_status: "czynny"}
    command :check_registries, %{period_id: "2026-08"}
    expect :data_completeness_confirmed, %{period_id: "2026-08"}
  end

  scenario "rejestry mówią to samo co Abilia — dane zgodne" do
    given :company_profile_completed, %{legal_form: "JDG", vat_status: "czynny"}

    command :log_registry_check, %{
      period_id: "2026-08",
      legal_form: "JDG",
      vat_status: "czynny"
    }

    expect :registry_check_logged, %{period_id: "2026-08"}
    expect :registry_data_consistent, %{period_id: "2026-08"}
  end

  scenario "firma wykreślona z VAT — rozjazd z różnicą" do
    given :company_profile_completed, %{legal_form: "JDG", vat_status: "czynny"}

    command :log_registry_check, %{
      period_id: "2026-08",
      legal_form: "JDG",
      vat_status: "wykreślony"
    }

    expect :registry_check_logged

    expect :registry_discrepancy_detected, %{
      differences: [%{field: "vat_status", ours: "czynny", theirs: "wykreślony"}]
    }
  end

  scenario "odpowiedź rejestrów idzie do porównania" do
    scope :compare_with_registries

    on :registry_status_checked, %{
      period_id: "2026-08",
      legal_form: "JDG",
      vat_status: "czynny",
      vies_status: "aktywny"
    }

    issues :log_registry_check, %{period_id: "2026-08", vat_status: "czynny"}
  end

  scenario "po sprawdzeniu sierpnia 1 października sprawdza się wrzesień" do
    scope :monthly_registry_check
    given :data_completeness_confirmed, %{period_id: "2026-08"}
    on :next_month
    issues :check_registries, %{period_id: "2026-09"}
  end

  scenario "ponowienie starszego miesiąca nie cofa sprawdzania" do
    scope :monthly_registry_check
    given :data_completeness_confirmed, %{period_id: "2026-08"}
    given :data_completeness_confirmed, %{period_id: "2026-03"}
    on :next_month
    issues :check_registries, %{period_id: "2026-09"}
  end
end
