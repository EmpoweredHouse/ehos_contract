defmodule Rehmed.Supplier do
  @moduledoc """
  **A stand-in for Rehmed's own systems**, as `Rehmed.StatutoryReporting` stands in for
  the P1 registry (plan T1s): the sandbox builds no integration, so what those systems
  would say about a visit is a table here.

  Two fields a decision depends on are not the caller's to say. Whether a visit's
  service is reported to P1 is a flag of the service catalogue (`AGG-15`), and a
  visit's total is what its priced services come to; a request carrying either could
  close a visit clinically without its codes, or settle it for any amount. Both are
  declared `supplied_by: :host`, and the host answers them from what it knows of the
  visit — here, the table. A visit it does not know is `{:error, :unknown_visit}`,
  which refuses the request with 503.
  """

  @behaviour EhOsContract.Supplier

  # What Rehmed's systems would answer for each visit the sandbox's requests name.
  @visits %{
    "visit-anna" => %{p1_reported: true, total: 20_000}
  }

  @impl true
  def supply(_actor, %{fields: fields, given: %{visit_id: visit_id}}) do
    case Map.fetch(@visits, visit_id) do
      {:ok, known} -> {:ok, Map.take(known, fields)}
      :error -> {:error, :unknown_visit}
    end
  end
end
