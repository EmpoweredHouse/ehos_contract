defmodule TipRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `TipRig`: an amount and a tip, each more than nothing,
  under one rule's name.
  """

  use EhosContract.Domain, name: :tip_rig, language: :en

  context :till, "Till", subdomain: :core

  actor :cashier, :human, "Cashier"
  actor :counter, :system, "Counting machine"

  subject :customer, "Customer"

  value :amount, :integer do
    invariant :positive, "An amount is more than nothing", violated_by: [0], satisfied_by: [1]
  end

  value :tip, :integer do
    invariant :positive, "A tip is more than nothing", violated_by: [0], satisfied_by: [1]
  end

  # A payment holds both, so the name alone does not tell which of its parts refuses it.
  value :payment do
    field :amount, :amount
    field :tip, :tip, optional: true
  end

  subdomain :core, "Core", type: :core
end
