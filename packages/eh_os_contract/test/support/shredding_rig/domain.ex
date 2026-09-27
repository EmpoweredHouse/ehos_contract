defmodule ShreddingRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `ShreddingRig`: the domain crypto-shredding is
  tested on (v2 §14). A member is a person whose data may be erased; a contact is a
  phone number of a member, perhaps of another member than the one it is listed
  for, so one event can carry the personal data of two subjects.
  """

  use EhOsContract.Domain, name: :shredding_rig, language: :en

  context :membership, "Membership", subdomain: :core

  actor :clerk, :human, "Clerk"

  subject :member, "Member"

  value :contact do
    field :member_id, :id, subject: :member
    field :phone, :string, personal: :member_id
  end

  subdomain :core, "Core", type: :core
end
