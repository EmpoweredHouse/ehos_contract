defmodule FormRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `FormRig`: a billing period is a month written
  `YYYY-MM`, the one value a form checks with an invariant of its own.
  """

  use EhOsContract.Domain, name: :form_rig, language: :en

  context :invoicing, "Invoicing", subdomain: :core

  actor :accountant, :human, "Accountant"

  value :period, :string do
    invariant :written_as_month, "A period is a month written YYYY-MM",
      violated_by: ["2026-13", "July"],
      satisfied_by: ["2026-07"]
  end

  subdomain :core, "Core", type: :core
end
