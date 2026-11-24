defmodule Lending.Contracts.Membership do
  @moduledoc """
  **Invented.** Membership: a person registered to borrow, with the name and the
  e-mail the desk keeps for them.

  Both are the member's personal data. The log seals them with the member's key and
  the member directory keeps them in the clear, so erasing the member destroys the
  key and empties the directory's row (`Lending.Membership.Directory.forget/2`). After
  that, a change of e-mail for the member is refused: its event would carry the
  member's data again.
  """

  use EhosContract.Contract,
    domain: Lending.Domain,
    context: :membership,
    id: "lending.membership"

  aggregate :membership, "Membership" do
    identity :membership_id

    state do
      field :registered, :boolean, default: false
      field :member_id, :id, optional: true
    end

    invariant :registered_once, "A membership is registered once"

    # The e-mail is sealed with the key of the member the command names, so a change
    # naming another member than the one registered would put that member's data on
    # this membership, where erasing either of them leaves it readable.
    invariant :only_a_registered_member_changes,
              "Only the member a membership was registered for changes its details"

    command :register_member, "Register a member",
      by: :librarian,
      emits: :member_registered,
      rejects: :registered_once do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :email, :string, personal: :member_id
    end

    command :change_email, "Change a member's e-mail",
      by: :librarian,
      emits: :email_changed,
      rejects: :only_a_registered_member_changes do
      field :member_id, :id, subject: :member
      field :email, :string, personal: :member_id
    end

    event :member_registered, "Member registered" do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :email, :string, personal: :member_id
    end

    event :email_changed, "E-mail changed" do
      field :member_id, :id, subject: :member
      field :email, :string, personal: :member_id
    end
  end

  read_model :member_directory, "Member directory",
    projects: [:member_registered, :email_changed],
    table: "lending_member_directory",
    key: :membership_id do
    field :membership_id, :id
    field :member_id, :id, subject: :member
    field :name, :string, personal: :member_id
    field :email, :string, personal: :member_id
  end

  # A member may hold more than one membership, each with its own details, so the
  # query answers each of them.
  query :member_contact, "How to reach a member",
    reads: :member_directory,
    by: :librarian do
    param :member_id, :id
  end

  scenario "a member is registered" do
    command :register_member, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    expect :member_registered, %{member_id: "member-ada"}
  end

  scenario "a membership is not registered twice" do
    given :member_registered, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    command :register_member, %{
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    rejected :registered_once
  end

  scenario "a registered member changes e-mail" do
    given :member_registered, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    command :change_email, %{member_id: "member-ada", email: "ada@example.net"}
    expect :email_changed, %{member_id: "member-ada"}
  end

  scenario "nobody registered — no e-mail to change" do
    command :change_email, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      email: "ada@example.net"
    }

    rejected :only_a_registered_member_changes
  end

  scenario "another member's e-mail is not put on a membership" do
    given :member_registered, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    command :change_email, %{member_id: "member-bob", email: "bob@example.org"}
    rejected :only_a_registered_member_changes
  end

  scenario "the desk finds a member's latest e-mail" do
    given :member_registered, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      name: "Ada Lovelace",
      email: "ada@example.org"
    }

    given :email_changed, %{
      membership_id: "membership-ada",
      member_id: "member-ada",
      email: "ada@example.net"
    }

    query :member_contact, %{member_id: "member-ada"}
    answers [%{member_id: "member-ada", email: "ada@example.net"}]
  end
end
