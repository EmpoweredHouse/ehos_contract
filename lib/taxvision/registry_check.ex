defmodule Taxvision.RegistryCheck do
  @moduledoc """
  The business logic is a pure function: a command goes in, an error or a list of
  events comes out. Side effects live only in handlers.

  Testable with no setup at all — and that is the shape a model generates most
  reliably: bounded input, explicit rules, explicit output, no environment.

  The registry adapter is called **outside** this function. If it were inside, the
  check could not separate "we broke the rule" from "the registry was down", and
  for an accounting client that is the whole question (ADR §11-12).
  """

  use Boundary, deps: [PNS], exports: []

  @doc """
  Policy P1 from the workshop: when a month starts, check the registries; when the
  data agrees, generate the tasks; when it does not, block and notify.

  The precondition for inserting the template is the absence of a legal-status
  divergence [WF 00:35:41].
  """
  @spec decide(map()) :: [PNS.Emission.t()] | {:error, atom()}
  def decide(%{command: :open_month} = input) do
    %{company_id: company_id, period: period} = input

    base = %{company_id: company_id, period: period}
    checked_at = input[:checked_at] || "1970-01-01T00:00:00Z"

    cond do
      not input.completeness_confirmed ->
        {:error, :data_completeness_not_confirmed}

      true ->
        prefix = [
          PNS.event(:data_completeness_confirmed, base),
          PNS.event(:registry_status_checked, Map.put(base, :checked_at, checked_at)),
          PNS.event(:registry_check_logged, Map.put(base, :checked_at, checked_at))
        ]

        case diff(input.abilia, input.registries) do
          [] ->
            prefix ++ [PNS.event(:registry_data_consistent, base)]

          differences ->
            # The system shows a diff: "this is what we hold, this is what the
            # registries say" [WF 00:32:27].
            prefix ++ [PNS.event(:registry_discrepancy_detected, Map.put(base, :diff, render(differences)))]
        end
    end
  end

  @doc "Divergences between what we hold locally and what the registries say."
  @spec diff(map(), map()) :: [{atom(), term(), term()}]
  def diff(abilia, registries) do
    for {field, registry_field} <- [legal_form: :legal_form, vat_status: :vat_status],
        ours = Map.get(abilia, field),
        theirs = Map.get(registries, registry_field),
        ours != theirs do
      {field, ours, theirs}
    end
  end

  defp render(differences) do
    Enum.map_join(differences, "; ", fn {field, ours, theirs} ->
      "#{field}: Abilia=#{ours}, rejestry=#{theirs}"
    end)
  end
end
