defmodule FormRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `FormRig`: a billing period is a month written
  `YYYY-MM`, a value a form checks with an invariant of its own; an invoice's line counts
  at least one, an invariant of a value with fields, which a form shows on the line's row;
  and an address is a value with fields and no invariant.
  """

  use EhosContract.Domain, name: :form_rig, language: :en

  context :invoicing, "Invoicing", subdomain: :core

  actor :accountant, :human, "Accountant"

  value :period, :string do
    invariant :written_as_month, "A period is a month written YYYY-MM",
      violated_by: ["2026-13", "July"],
      satisfied_by: ["2026-07"]
  end

  value :line do
    field :title, :string
    field :quantity, :integer

    invariant :counted, "A line counts at least one",
      violated_by: [%{title: "Payroll", quantity: 0}],
      satisfied_by: [%{title: "Payroll", quantity: 1}]
  end

  value :address do
    field :street, :string
    field :city, :string, optional: true
  end

  subdomain :core, "Core", type: :core
end
