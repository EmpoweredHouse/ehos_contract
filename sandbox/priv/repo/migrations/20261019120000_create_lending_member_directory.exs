defmodule EhosContractHost.Repo.Migrations.CreateLendingMemberDirectory do
  @moduledoc """
  The table of `Lending.Membership.Directory`: one row per membership, with the
  member's name and e-mail, deleted when the member is erased.
  """

  use Ecto.Migration

  def change do
    create table(:lending_member_directory, primary_key: false) do
      add :membership_id, :string, primary_key: true
      add :member_id, :string, null: false
      add :name, :string
      add :email, :string
    end

    # The erasure deletes by the member, inside its own transaction.
    create index(:lending_member_directory, [:member_id])
  end
end
