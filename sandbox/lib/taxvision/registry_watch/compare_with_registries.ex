defmodule Taxvision.RegistryWatch.CompareWithRegistries do
  @moduledoc "The registries' answer goes to the company's decision, which logs the check."

  use Taxvision.Contracts.RegistryWatch, policy: :compare_with_registries

  @impl true
  def registry_status_checked(%RegistryStatusChecked{} = answer) do
    issue(%LogRegistryCheck{
      company_id: answer.company_id,
      period_id: answer.period_id,
      legal_form: answer.legal_form,
      vat_status: answer.vat_status
    })
  end
end
