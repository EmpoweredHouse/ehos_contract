defmodule TipRig.Till do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A till takes an amount and a tip, and each is refused on its own value's
  `:positive` (issue #458).
  """

  use EhosContract.Contract, domain: TipRig.Domain, context: :till, id: "tip_rig.till"

  aggregate :till, "Till" do
    identity :till_id

    command :pay_in, "Pay in", by: :cashier, emits: :paid_in do
      field :amount, :amount
      field :tip, :tip, optional: true
    end

    command :settle, "Settle a payment", by: :cashier, emits: :settled do
      field :payment, :payment
    end

    event :paid_in, "Paid in"
    event :settled, "Settled"

    # Who tipped is personal, so the graph's data masks the tip (the review of #458).
    event :counted, "Counted", recorded_by: :counter do
      field :amount, :amount
      field :customer_id, :id, subject: :customer
      field :tip, :tip, optional: true, personal: :customer_id
    end
  end

  scenario "an amount and a tip are paid in" do
    command :pay_in, %{amount: 250, tip: 5}
    expect :paid_in
  end

  scenario "a tip of nothing is not paid in" do
    command :pay_in, %{amount: 250, tip: 0}
    rejected :positive
  end

  scenario "an amount of nothing is not paid in" do
    command :pay_in, %{amount: 0, tip: 5}
    rejected :positive
  end

  scenario "a payment is settled" do
    command :settle, %{payment: %{amount: 250, tip: 5}}
    expect :settled
  end

  scenario "a payment with a tip of nothing is not settled" do
    command :settle, %{payment: %{amount: 250, tip: 0}}
    rejected :positive
  end

  scenario "the machine counts an amount and a tip" do
    actor :counter
    record :counted, %{amount: 250, customer_id: "c-1", tip: 5}
    expect :counted
  end

  scenario "the machine counts no tip of nothing" do
    actor :counter
    record :counted, %{amount: 250, customer_id: "c-1", tip: 0}
    rejected :positive
  end
end

defmodule TipRig.TillDecider do
  @moduledoc "**Invented.** The decider of `TipRig.Till`'s till: it pays in what it is given."

  use TipRig.Till, aggregate: :till

  @impl true
  def pay_in(%PayIn{till_id: id}, _state), do: emit(%PaidIn{till_id: id})

  @impl true
  def settle(%Settle{till_id: id}, _state), do: emit(%Settled{till_id: id})
end
