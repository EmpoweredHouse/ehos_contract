defmodule Rehmed.Supplier do
  @moduledoc """
  **A stand-in for Rehmed's own systems**, as the effect
  `Rehmed.StatutoryReporting.SendP1Report` stands in for the P1 registry (plan T1s):
  the sandbox builds no integration, so what those systems would say about a visit is a
  table here.

  Two fields a decision depends on are not the caller's to say. Whether a visit's
  service is reported to P1 is a flag of the service catalogue (`AGG-15`), and decides
  whether the codes are required; a visit's `total` is what the settlement's payment
  lines must sum to, by the rule `P-31` gives it — the patient's part when a payer
  covers the visit in part, the price when nobody does. A request carrying either
  could close a reported visit without its codes, or settle one for any amount. Both
  are declared `supplied_by: :host`, and the host answers them from what it knows of
  the visit and who pays for it.

  Only the visits in the table are known: a visit booked on the dev host has an
  identity the library generated, and is answered `{:error, :unknown_visit}`, a 503,
  as is a payer the table does not price the visit for. A request of another contract,
  or one that names no visit, is not this host's to answer, `{:error, :not_supplied_here}`.
  """

  @behaviour EhOsContract.Supplier

  alias Rehmed.Contracts.{ClinicalDocumentation, Settlement}

  # What Rehmed's systems would answer for each visit the sandbox's requests name:
  # the service's P1 flag, and the total by who pays — `nil` for the patient alone.
  @visits %{
    "visit-anna" => %{p1_reported: true, totals: %{nil => 20_000, "payer-luxmed" => 5_000}}
  }

  @impl true
  def supply(_actor, %{contract: contract, fields: fields, given: %{visit_id: visit_id} = given})
      when contract in [ClinicalDocumentation, Settlement] do
    with {:ok, visit} <- Map.fetch(@visits, visit_id) |> known(:unknown_visit) do
      Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, supplied} ->
        case value(visit, field, given) do
          {:ok, value} -> {:cont, {:ok, Map.put(supplied, field, value)}}
          error -> {:halt, error}
        end
      end)
    end
  end

  def supply(_actor, _request), do: {:error, :not_supplied_here}

  defp value(visit, :p1_reported, _given), do: {:ok, visit.p1_reported}

  defp value(visit, :total, given),
    do: visit.totals |> Map.fetch(Map.get(given, :payer_id)) |> known(:unknown_payer)

  defp value(_visit, _field, _given), do: {:error, :not_supplied_here}

  defp known({:ok, value}, _reason), do: {:ok, value}
  defp known(:error, reason), do: {:error, reason}
end
