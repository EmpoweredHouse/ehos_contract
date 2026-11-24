defmodule Lending.Processes.LateFee do
  @moduledoc """
  **Invented.** A late fee, from its charge to its payment, or its waiver. The library
  promises the fee is settled within thirty days of being charged; waiving it is the
  other way of keeping that promise (`or_else`), not a failure to keep it.

  It is a run of its own beside the loan, correlated by the same loan: a fee is charged
  at the return, which ends the loan's run.
  """

  use EhosContract.Process,
    id: "lending.late_fee",
    domain: Lending.Domain,
    label: "A late fee, from its charge to its settlement",
    accountable: :librarian

  correlate :loan_id

  stage :charging, "Charging", include: [{Lending.Contracts.Circulation, :late_fee_charged}]

  stage :settling, "Settling",
    include: [{Lending.Contracts.Circulation, [:late_fee_paid, :late_fee_waived]}]

  ends_on [:late_fee_paid, :late_fee_waived]

  promise :settled_within_thirty_days do
    from :late_fee_charged
    eventually :late_fee_paid
    or_else :late_fee_waived
    within {30, :day}
  end

  deadline {60, :day}

  scenario "paid a week later — kept", verdict: :satisfied, via: :eventually do
    given :late_fee_charged, %{loan_id: "loan-1", fee: 150}, at: "2026-09-25T10:00:00Z"
    given :late_fee_paid, %{loan_id: "loan-1"}, at: "2026-10-02T10:00:00Z"
    promise :settled_within_thirty_days, at: "2026-11-01T10:00:00Z"
  end

  scenario "waived at the desk — kept the other way", verdict: :satisfied, via: :or_else do
    given :late_fee_charged, %{loan_id: "loan-1", fee: 150}, at: "2026-09-25T10:00:00Z"
    given :late_fee_waived, %{loan_id: "loan-1"}, at: "2026-09-26T10:00:00Z"
    promise :settled_within_thirty_days, at: "2026-11-01T10:00:00Z"
  end

  scenario "neither paid nor waived in thirty days — broken", verdict: :violated do
    given :late_fee_charged, %{loan_id: "loan-1", fee: 150}, at: "2026-09-25T10:00:00Z"
    promise :settled_within_thirty_days, at: "2026-10-26T10:00:00Z"
  end

  scenario "a fee charged yesterday — still running", verdict: :pending do
    given :late_fee_charged, %{loan_id: "loan-1", fee: 150}, at: "2026-09-25T10:00:00Z"
    promise :settled_within_thirty_days, at: "2026-09-26T10:00:00Z"
  end
end
