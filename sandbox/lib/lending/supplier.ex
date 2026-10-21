defmodule Lending.Supplier do
  @moduledoc """
  **Invented. A stand-in for the desk's tariff**: what a late copy costs is the
  library's rule, not the caller's to say, so a return's `late_fee` is
  `supplied_by: :host`. The sandbox builds no tariff, so what it would answer for each
  loan the sandbox's requests name is a table here.

  A loan the table does not know is answered `{:error, :unknown_loan}`, a 503. A
  request of another contract is not this module's to answer.
  """

  @behaviour EhOsContract.Supplier

  alias Lending.Contracts.Circulation

  # The fee, in pence, the tariff charges for each loan's return as of today.
  @fees %{"loan-on-time" => 0, "loan-late" => 150}

  @impl true
  def supply(_actor, %{contract: Circulation, fields: [:late_fee], given: %{loan_id: loan}}) do
    case Map.fetch(@fees, loan) do
      {:ok, fee} -> {:ok, %{late_fee: fee}}
      :error -> {:error, :unknown_loan}
    end
  end

  def supply(_actor, _request), do: {:error, :not_supplied_here}
end
