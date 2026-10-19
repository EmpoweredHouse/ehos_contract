defmodule Lending.Processes.Loan do
  @moduledoc """
  **Invented.** A loan, from the copy going out to its return, with the notices that
  chase it. The library promises a copy back within three weeks, its standard loan
  period, whatever due date the desk gave: a loan the desk lent for longer still counts
  against it. A loan longer than three months is overdue.
  """

  use EhOsContract.Process,
    id: "lending.loan",
    domain: Lending.Domain,
    label: "A loan, from lending to return",
    accountable: :librarian

  correlate :loan_id

  @lent %{
    loan_id: "loan-1",
    copy_id: "copy-1",
    member_id: "member-ada",
    card_id: "card-ada",
    due_at: "2026-09-22T10:00:00Z"
  }

  stage :lending, "Lending", include: [{Lending.Contracts.Circulation, :copy_lent}]
  stage :chasing, "Chasing", include: [{Lending.Contracts.Circulation, :overdue_notice_sent}]
  stage :return, "Return", include: [{Lending.Contracts.Circulation, :copy_returned}]

  ends_on :copy_returned

  promise :back_within_three_weeks do
    from :copy_lent
    eventually :copy_returned
    within {21, :day}
  end

  deadline {90, :day}

  scenario "back on the twentieth day — kept", verdict: :satisfied, via: :eventually do
    given :copy_lent, @lent, at: "2026-09-01T10:00:00Z"
    given :copy_returned, %{loan_id: "loan-1"}, at: "2026-09-20T10:00:00Z"
    promise :back_within_three_weeks, at: "2026-10-01T10:00:00Z"
  end

  scenario "still out after three weeks — broken", verdict: :violated do
    given :copy_lent, @lent, at: "2026-09-01T10:00:00Z"
    given :overdue_notice_sent, %{loan_id: "loan-1"}, at: "2026-09-22T10:00:00Z"
    promise :back_within_three_weeks, at: "2026-09-23T10:00:00Z"
  end

  scenario "a week out — still running", verdict: :pending do
    given :copy_lent, @lent, at: "2026-09-01T10:00:00Z"
    promise :back_within_three_weeks, at: "2026-09-08T10:00:00Z"
  end
end
