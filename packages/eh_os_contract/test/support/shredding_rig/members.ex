defmodule ShreddingRig.Members do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A membership per stream, held by one member. Joining carries the member's name,
  an optional email and a list of contacts, each personal to the member it names;
  renaming carries the new name and the previous one, which the decision takes from
  the state its stream folds to — so a rename reads personal data back. Two read
  models keep the name in the host's tables, one in the dispatch transaction and one
  after it, and each forgets an erased member. A policy exists only so that a
  test can watch a reaction issue a command carrying an erased member's data.
  """

  use EhOsContract.Next.Contract, domain: ShreddingRig.Domain, context: :membership

  aggregate :membership, "Membership" do
    identity :membership_id

    state do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
    end

    command :join, "Join", by: :clerk, emits: :joined do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :email, :string, personal: :member_id, optional: true
      field :contacts, {:list, :contact}
      field :plan, {:enum, [:basic, :full]}
    end

    command :rename, "Rename", by: :clerk, emits: :renamed do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
    end

    event :joined, "Joined" do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :email, :string, personal: :member_id, optional: true
      field :contacts, {:list, :contact}
      field :plan, {:enum, [:basic, :full]}
    end

    event :renamed, "Renamed" do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :previous, :string, personal: :member_id
    end
  end

  read_model :members, "Members", projects: [:joined, :renamed] do
    field :membership_id, :id
    field :member_id, :id, subject: :member
    field :name, :string, personal: :member_id
  end

  read_model :member_names, "Member names", projects: :joined, delivery: :at_least_once do
    field :membership_id, :id
    field :member_id, :id, subject: :member
    field :name, :string, personal: :member_id
  end

  policy :rejoin, "Rejoin a member named in a rename", handles: :renamed, issues: :join

  process :membership, "Membership" do
    correlate :membership_id
    accountable :clerk
  end
end
