defmodule Taxvision.RegistryWatch.Client do
  @moduledoc """
  Decides for one company (`Company / Client`, 02 §12): the registries are checked
  only once its profile is complete, and their answer is held against the profile —
  legal form and VAT status, the fields the check compares (WF 00:35:41).
  """

  use Taxvision.Contracts.RegistryWatch, aggregate: :client

  # The fields the workshop compares, in the order a diff reads them.
  @compared [:legal_form, :vat_status]

  @impl true
  def complete_company_profile(%CompleteCompanyProfile{} = profile, _state) do
    %CompleteCompanyProfile{company_id: id, legal_form: form, vat_status: vat} = profile
    emit(%CompanyProfileCompleted{company_id: id, legal_form: form, vat_status: vat})
  end

  @impl true
  def check_registries(%CheckRegistries{company_id: id, period_id: period}, state),
    do: confirm(id, period, state)

  @impl true
  def retrigger_verification(%RetriggerVerification{company_id: id, period_id: period}, state),
    do: confirm(id, period, state)

  @impl true
  def log_registry_check(%LogRegistryCheck{company_id: id, period_id: period} = answer, state) do
    case differences(state, answer) do
      [] ->
        emit([
          %RegistryCheckLogged{company_id: id, period_id: period},
          %RegistryDataConsistent{company_id: id, period_id: period}
        ])

      differences ->
        emit([
          %RegistryCheckLogged{company_id: id, period_id: period},
          %RegistryDiscrepancyDetected{
            company_id: id,
            period_id: period,
            differences: differences
          }
        ])
    end
  end

  defp confirm(_id, _period, %State{profile_complete: false}),
    do: reject(:checked_only_with_complete_data)

  defp confirm(id, period, _state),
    do: emit(%DataCompletenessConfirmed{company_id: id, period_id: period})

  # "This is what we hold, this is what the registries say" [WF 00:32:27].
  defp differences(state, answer) do
    for field <- @compared,
        ours = Map.fetch!(state, field),
        theirs = Map.fetch!(answer, field),
        ours != theirs,
        do: %{field: Atom.to_string(field), ours: ours, theirs: theirs}
  end

  @impl true
  def evolve(state, %CompanyProfileCompleted{legal_form: form, vat_status: vat}),
    do: %{state | profile_complete: true, legal_form: form, vat_status: vat}

  def evolve(state, _changes_nothing), do: state
end
