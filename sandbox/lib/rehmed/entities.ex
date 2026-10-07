defmodule Rehmed.Entities do
  @moduledoc """
  **A stand-in for Rehmed's service catalogue**, as `Rehmed.Supplier` stands in for its
  other systems (plan DD, T2s, #245): the sandbox builds no integration, so the catalogue
  a booking reads is a table here.

  Whether a service is reported to P1 is a flag of the catalogue (`AGG-15`):
  physiotherapy is, by default, and fitness never is (`H21`, `DEC-20`). A booking reads
  the service it names, and the visit keeps the flag as it stood then. Any other service
  is not in the catalogue, `:not_found`, and the booking is refused. The catalogue is the
  clinic's own, so it answers every actor alike.
  """

  @behaviour EhOsContract.Entities

  @services %{
    "service-physiotherapy" => %{service_id: "service-physiotherapy", p1_reported: true},
    "service-fitness" => %{service_id: "service-fitness", p1_reported: false}
  }

  @impl true
  def fetch(_actor, Rehmed.Domain, :service, id) do
    case Map.fetch(@services, id) do
      {:ok, service} -> {:ok, service}
      :error -> :not_found
    end
  end
end
