defmodule SeedRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `SeedRig`. A clerk is a person with a credential, scoped
  to a shop, and a manager one for the whole application; the nightly job is the application's own code, a `:system` actor; sample data
  is the seed, which may do what a person may except refund an order.
  """

  use EhosContract.Domain, name: :seed_rig, language: :en

  context :shop, "Shop", subdomain: :core

  actor :clerk, :human, "Clerk", scope: [:shop_id]
  actor :manager, :human, "Manager"
  actor :nightly_job, :system, "Nightly job"

  actor :sample_data, :seed, "Sample data",
    not_seeded: [refund_order: "A refund moves a client's money"]

  subdomain :core, "Core", type: :core
end
