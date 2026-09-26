defmodule DispatchRig.Ledger do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  One account per stream. `withdraw` is refused below zero, and `misbehave` is a
  command whose implementation returns an event the command does not emit, which
  the compiler cannot see and dispatch has to stop. Two read models and a policy
  run inside the dispatch transaction; one policy flags an account on a deposit of
  1000 or more, through a command no actor may issue, and the other repeats a
  deposit of 777, a cycle for dispatch's guard to stop.
  """

  use EhOsContract.Next.Contract, domain: DispatchRig.Domain, context: :ledger

  aggregate :account, "Account" do
    identity :account_id

    state do
      field :balance, :integer, default: 0
    end

    invariant :balance_never_negative, "The balance never goes below zero"

    command :open_account, "Open an account", by: :clerk, emits: :account_opened do
      field :branch_id, :id
    end

    command :deposit, "Deposit", by: [:clerk, :nightly_import], emits: :deposited do
      field :amount, :integer
    end

    command :withdraw, "Withdraw",
      by: :clerk,
      emits: :withdrawn,
      rejects: :balance_never_negative do
      field :amount, :integer
    end

    command :misbehave, "Decide what is not declared", by: :clerk, emits: :deposited

    command :flag_account, "Flag the account for review", emits: :account_flagged

    event :account_opened, "Account opened" do
      field :branch_id, :id
    end

    event :deposited, "Deposited" do
      field :amount, :integer
    end

    event :withdrawn, "Withdrawn" do
      field :amount, :integer
    end

    event :account_flagged, "Account flagged for review"

    event :interest_recorded, "Interest recorded", recorded_by: :nightly_import do
      field :amount, :integer
    end

    event :balance_confirmed, "Balance confirmed", recorded_by: :auditor
  end

  read_model :balances, "Balances",
    projects: [:account_opened, :deposited, :withdrawn, :interest_recorded] do
    field :account_id, :id
    field :branch_id, :id
    field :balance, :integer
  end

  read_model :movements, "Movements", projects: :deposited do
    field :account_id, :id
    field :amount, :integer
  end

  query :balances_for_branch, "Balances of one branch",
    reads: :balances,
    by: [:clerk, :nightly_import],
    scope: :branch_id do
    param :branch_id, :id
  end

  policy :flag_large_deposit, "Flag an account on a large deposit",
    handles: :deposited,
    issues: :flag_account

  policy :echo_deposit, "Repeat a deposit of 777", handles: :deposited, issues: :deposit

  process :ledger, "Ledger" do
    correlate :account_id
  end

  scenario "a withdrawal beyond the balance is refused" do
    given :deposited, %{amount: 100}
    command :withdraw, %{amount: 150}
    rejected :balance_never_negative
  end

  scenario "a branch's balances are its accounts, with what was deposited" do
    given :account_opened, %{account_id: "a-1", branch_id: "b-7"}
    given :deposited, %{account_id: "a-1", amount: 40}
    given :account_opened, %{account_id: "a-2", branch_id: "b-9"}
    query :balances_for_branch, %{branch_id: "b-7"}
    answers [%{account_id: "a-1", balance: 40}]
  end

  scenario "a withdrawal within the balance goes through" do
    given :deposited, %{amount: 100}
    command :withdraw, %{amount: 100}
    expect :withdrawn, %{amount: 100}
  end
end
