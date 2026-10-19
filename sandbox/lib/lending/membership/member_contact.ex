defmodule Lending.Membership.MemberContact do
  @moduledoc "**Invented.** Answers the desk: a member's name and latest e-mail, per membership."

  use Lending.Contracts.Membership, query: :member_contact

  import Ecto.Query

  @impl true
  def member_contact(%MemberContact{member_id: member}, _ctx) do
    from(m in "lending_member_directory",
      where: m.member_id == ^member,
      select: %{
        membership_id: m.membership_id,
        member_id: m.member_id,
        name: m.name,
        email: m.email
      }
    )
    |> order_by([m], m.membership_id)
    |> EhOsContract.Config.fetch!(:repo).all()
    |> Enum.map(&struct(Row, &1))
  end
end
