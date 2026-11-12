# Invented test material: a domain with two people's actors, one of them scoped, for the
# development mode to sign a person in as.
defmodule DevelopmentFixture.Clinic do
  @moduledoc false
  use EhOsContract.Domain, name: :clinic, language: :en

  subdomain(:core, "Core", type: :core)
  context(:front_desk, "Front desk", subdomain: :core)

  actor(:receptionist, :human, "Receptionist", scope: [:clinic_id])
  actor(:manager, :human, "Manager")
end

defmodule DevelopmentFixture.Visits do
  @moduledoc false
  use EhOsContract.Contract,
    domain: DevelopmentFixture.Clinic,
    context: :front_desk,
    id: "clinic.visits"

  aggregate :visit, "Visit" do
    identity(:visit_id)

    command :record_payment, "Record a payment",
      by: :receptionist,
      scope: :clinic_id,
      emits: :payment_recorded do
      field(:clinic_id, :id)
    end

    command(:close_visit, "Close a visit", by: :manager, emits: :visit_closed)

    event :payment_recorded, "Payment recorded" do
      field(:clinic_id, :id)
    end

    event(:visit_closed, "Visit closed")
  end
end
