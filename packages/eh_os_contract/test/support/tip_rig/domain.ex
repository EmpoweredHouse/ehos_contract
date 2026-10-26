defmodule TipRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `TipRig`: an amount and a tip, each more than nothing,
  under one rule's name.
  """

  use EhOsContract.Domain, name: :tip_rig, language: :en

  context :till, "Till", subdomain: :core

  actor :cashier, :human, "Cashier"

  value :amount, :integer do
    invariant :positive, "An amount is more than nothing", violated_by: [0], satisfied_by: [1]
  end

  value :tip, :integer do
    invariant :positive, "A tip is more than nothing", violated_by: [0], satisfied_by: [1]
  end

  subdomain :core, "Core", type: :core
end
