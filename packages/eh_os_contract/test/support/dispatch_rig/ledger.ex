defmodule DispatchRig.Ledger do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  One account per stream. `withdraw` is refused below zero, and `misbehave` is a
  command whose implementation returns an event the command does not emit, which
  the compiler cannot see and dispatch has to stop.
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

    event :account_opened, "Account opened" do
      field :branch_id, :id
    end

    event :deposited, "Deposited" do
      field :amount, :integer
    end

    event :withdrawn, "Withdrawn" do
      field :amount, :integer
    end
  end

  process :ledger, "Ledger" do
    correlate :account_id
  end

  scenario "a withdrawal beyond the balance is refused" do
    given :deposited, %{amount: 100}
    command :withdraw, %{amount: 150}
    rejected :balance_never_negative
  end

  scenario "a withdrawal within the balance goes through" do
    given :deposited, %{amount: 100}
    command :withdraw, %{amount: 100}
    expect :withdrawn, %{amount: 100}
  end
end
