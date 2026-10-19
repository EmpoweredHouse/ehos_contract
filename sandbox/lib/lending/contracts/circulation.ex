defmodule Lending.Contracts.Circulation do
  @moduledoc """
  **Invented.** Circulation: copies lent, chased when late, returned, charged for
  and held.

  - **A loan** is lent against a membership card, which the library's card system
    keeps, outside this log (`reads: [card: :card_id]`): a suspended card borrows
    nothing. A copy back after its due date is charged a late fee. The fee is the
    desk's tariff, so the host supplies it (`supplied_by: :host`), and a caller who
    sends one is refused. The fee is then paid or waived.
  - **The overdue chase** sets a reminder at the loan's due date and, once a notice
    is sent, another a week after the last one, until the copy comes back.
  - **A hold** keeps a copy for one member. It is a dynamic consistency boundary
    over the copy's loans, its withdrawal and every hold on it, since none of them is
    the hold's own stream: two members asking for one copy at once get one hold
    between them, and a copy withdrawn while a hold waits to be appended refuses it.
  """

  use EhOsContract.Contract,
    domain: Lending.Domain,
    context: :circulation,
    id: "lending.circulation"

  aggregate :copy, "Copy" do
    identity :copy_id

    state do
      field :withdrawn, :boolean, default: false
    end

    invariant :withdrawn_once, "A copy is withdrawn from circulation once"

    command :withdraw_copy, "Withdraw a copy from circulation",
      by: :librarian,
      emits: :withdrawn_from_circulation,
      rejects: :withdrawn_once

    event :withdrawn_from_circulation, "Copy withdrawn from circulation"
  end

  aggregate :loan, "Loan" do
    identity :loan_id

    state do
      field :lent, :boolean, default: false
      field :returned, :boolean, default: false
      field :fee_owed, :boolean, default: false
    end

    invariant :lent_once, "A loan is lent once"
    invariant :suspended_card_borrows_nothing, "A suspended card borrows nothing"
    invariant :returned_once, "A lent copy comes back once"
    invariant :only_a_copy_out_is_chased, "Only a copy still out is chased"
    invariant :only_an_owed_fee_is_settled, "Only a fee still owed is paid or waived"

    command :lend_copy, "Lend a copy",
      by: :librarian,
      emits: :copy_lent,
      rejects: [:lent_once, :suspended_card_borrows_nothing],
      reads: [card: :card_id] do
      field :copy_id, {:id, :copy}
      field :member_id, :id
      field :card_id, {:id, :card}
      field :due_at, :timestamp
    end

    command :return_copy, "Take a copy back",
      by: :librarian,
      emits: [:copy_returned, :late_fee_charged],
      rejects: :returned_once do
      field :late_fee, :money, supplied_by: :host
    end

    command :send_overdue_notice, "Send an overdue notice",
      emits: :overdue_notice_sent,
      rejects: :only_a_copy_out_is_chased

    command :pay_late_fee, "Take payment of a late fee",
      by: :librarian,
      emits: :late_fee_paid,
      rejects: :only_an_owed_fee_is_settled

    command :waive_late_fee, "Waive a late fee",
      by: :librarian,
      emits: :late_fee_waived,
      rejects: :only_an_owed_fee_is_settled

    event :copy_lent, "Copy lent" do
      field :copy_id, {:id, :copy}
      field :member_id, :id
      field :card_id, {:id, :card}
      field :due_at, :timestamp
    end

    event :copy_returned, "Copy returned"

    event :late_fee_charged, "Late fee charged" do
      field :fee, :money
    end

    event :overdue_notice_sent, "Overdue notice sent"
    event :late_fee_paid, "Late fee paid"
    event :late_fee_waived, "Late fee waived"
  end

  dcb :copy_hold, "Hold on a copy" do
    identity [:member_id, copy_id: {:id, :copy}]

    consults :hold_placed, match: :copy_id
    consults :copy_lent, match: :copy_id
    consults :withdrawn_from_circulation, match: :copy_id

    state do
      field :held_by, :id, optional: true
      field :withdrawn, :boolean, default: false
    end

    invariant :one_hold_per_copy, "A copy is held for one member at a time"
    invariant :withdrawn_copy_takes_no_hold, "A withdrawn copy takes no hold"

    command :place_hold, "Place a hold on a copy",
      by: :patron,
      emits: :hold_placed,
      rejects: [:one_hold_per_copy, :withdrawn_copy_takes_no_hold]

    event :hold_placed, "Hold placed"
  end

  process_manager :overdue_chase, "Overdue chase" do
    correlate :loan_id

    state do
      field :remind_at, :timestamp, optional: true
    end

    starts_on :copy_lent, sets: :reminder
    on :overdue_notice_sent, sets: :reminder

    timer :reminder, "Reminder", at: :remind_at, issues: :send_overdue_notice

    ends_on :copy_returned
  end

  # The loan

  scenario "a copy is lent on a card in good standing" do
    given_entity :card, %{card_id: "card-ada", suspended: false}

    command :lend_copy, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    expect :copy_lent, %{copy_id: "copy-1", member_id: "member-ada"}
  end

  scenario "a suspended card borrows nothing" do
    given_entity :card, %{card_id: "card-bob", suspended: true}

    command :lend_copy, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-bob",
      card_id: "card-bob",
      due_at: "2026-01-22T17:00:00Z"
    }

    rejected :suspended_card_borrows_nothing
  end

  scenario "a loan is not lent twice" do
    given_entity :card, %{card_id: "card-ada", suspended: false}

    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    command :lend_copy, %{
      copy_id: "copy-2",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    rejected :lent_once
  end

  scenario "back on time — no fee" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    command :return_copy, %{late_fee: 0}
    expect :copy_returned
  end

  scenario "back late — the desk's fee is charged" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    command :return_copy, %{late_fee: 150}
    expect :copy_returned
    expect :late_fee_charged, %{fee: 150}
  end

  scenario "a copy comes back once" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    given :copy_returned
    command :return_copy, %{late_fee: 0}
    rejected :returned_once
  end

  scenario "a copy still out is chased" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    command :send_overdue_notice
    expect :overdue_notice_sent
  end

  scenario "a copy back is not chased" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    given :copy_returned
    command :send_overdue_notice
    rejected :only_a_copy_out_is_chased
  end

  scenario "a late fee is paid at the desk" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    given :copy_returned
    given :late_fee_charged, %{fee: 150}
    command :pay_late_fee
    expect :late_fee_paid
  end

  scenario "a late fee is waived" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    given :copy_returned
    given :late_fee_charged, %{fee: 150}
    command :waive_late_fee
    expect :late_fee_waived
  end

  scenario "a fee already paid is not waived" do
    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    given :copy_returned
    given :late_fee_charged, %{fee: 150}
    given :late_fee_paid
    command :waive_late_fee
    rejected :only_an_owed_fee_is_settled
  end

  # The copy

  scenario "a copy is withdrawn from circulation" do
    command :withdraw_copy, %{copy_id: "copy-1"}
    expect :withdrawn_from_circulation
  end

  scenario "a copy is withdrawn once" do
    given :withdrawn_from_circulation, %{copy_id: "copy-1"}
    command :withdraw_copy
    rejected :withdrawn_once
  end

  # The hold

  scenario "a member holds a copy nobody holds" do
    command :place_hold, %{copy_id: "copy-1", member_id: "member-ada"}
    expect :hold_placed, %{copy_id: "copy-1", member_id: "member-ada"}
  end

  scenario "a copy held for one member takes no second hold" do
    given :hold_placed, %{copy_id: "copy-1", member_id: "member-ada"}
    command :place_hold, %{copy_id: "copy-1", member_id: "member-bob"}
    rejected :one_hold_per_copy
  end

  scenario "a copy lent to its holder can be held again" do
    given :hold_placed, %{copy_id: "copy-1", member_id: "member-ada"}

    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    command :place_hold, %{copy_id: "copy-1", member_id: "member-bob"}
    expect :hold_placed, %{member_id: "member-bob"}
  end

  scenario "a withdrawn copy takes no hold" do
    given :withdrawn_from_circulation, %{copy_id: "copy-1"}
    command :place_hold, %{copy_id: "copy-1", member_id: "member-ada"}
    rejected :withdrawn_copy_takes_no_hold
  end

  # The chase

  scenario "a lent copy is first chased on its due date" do
    target :overdue_chase

    on :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    sets :reminder
    state %{remind_at: "2026-01-22T17:00:00Z"}
  end

  scenario "the reminder sends the notice" do
    target :overdue_chase

    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    on :reminder
    issues :send_overdue_notice, %{loan_id: "loan-1"}
  end

  scenario "a notice sent — the next one a week later" do
    target :overdue_chase

    given :copy_lent, %{
      loan_id: "loan-1",
      copy_id: "copy-1",
      member_id: "member-ada",
      card_id: "card-ada",
      due_at: "2026-01-22T17:00:00Z"
    }

    on :overdue_notice_sent, %{loan_id: "loan-1"}
    sets :reminder
    state %{remind_at: "2026-01-29T17:00:00Z"}
  end
end
