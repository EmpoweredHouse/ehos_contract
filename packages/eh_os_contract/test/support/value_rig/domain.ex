defmodule ValueRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `ValueRig`: values with invariants, of every shape
  the check walks. An amount is more than nothing; a fee is an amount with a cap, so
  it keeps both; a window is two dates in order; a payment is an amount with a note,
  a value with fields whose field has invariants of its own.
  """

  use EhOsContract.Domain, name: :value_rig, language: :en

  context :till, "Till", subdomain: :core

  actor :cashier, :human, "Cashier"
  actor :counter, :system, "Counting machine"

  value :amount, :integer do
    invariant :positive, "An amount is more than nothing",
      violated_by: [0, -5],
      satisfied_by: [1, 250]
  end

  value :fee, :amount do
    invariant :capped, "A fee is at most 1000", violated_by: [1001], satisfied_by: [1000]
  end

  value :window do
    field :from, :date
    field :to, :date

    invariant :in_order, "A window ends no earlier than it starts",
      violated_by: [%{from: "2026-02-01", to: "2026-01-31"}],
      satisfied_by: [%{from: "2026-01-01", to: "2026-01-01"}]
  end

  # A shift is named by its day, and the name keys a drawer, so a key is held to an
  # invariant too (#435).
  value :shift, :id do
    invariant :named_by_day, "A shift is a day written YYYY-MM-DD",
      violated_by: ["2026-13-01", "Monday"],
      satisfied_by: ["2026-01-31"]
  end

  value :payment do
    field :amount, :amount
    field :note, :string, optional: true
  end

  subdomain :core, "Core", type: :core
end
