defmodule Taxvision.RegistryWatch.LookUpRegistries do
  @moduledoc """
  Asks the public registries about the company whose data was confirmed, and
  records what they answered as the integration (D6), outside any transaction.

  An unavailable registry is not a negative check: the effect fails, and is tried
  again, and a promise whose window saw the registries down is suspended (ADR
  §11–12). The confirmation's identifier is the idempotency key, so a second
  delivery records nothing new.
  """

  use Taxvision.Contracts.RegistryWatch, effect: :look_up_registries

  alias EhOsContract.Actor
  alias Taxvision.Adapters.RegistryLookup
  alias Taxvision.Contracts.RegistryWatch.Events.RegistryStatusChecked

  @impl true
  def data_completeness_confirmed(%DataCompletenessConfirmed{} = confirmed) do
    %DataCompletenessConfirmed{company_id: id, period_id: period, __meta__: meta} = confirmed

    with {:ok, answer} <- RegistryLookup.lookup(id),
         {:ok, _receipt} <-
           EhOsContract.record(
             Taxvision.Contracts.RegistryWatch,
             %RegistryStatusChecked{
               company_id: id,
               period_id: period,
               legal_form: answer.legal_form,
               vat_status: answer.vat_status,
               vies_status: answer.vies_status
             },
             actor: Actor.system(:registry_integration),
             idempotency_key: "registry-status-checked:#{meta.id}",
             causation_id: meta.id,
             correlation_id: meta.correlation_id
           ),
         do: :ok
  end
end
