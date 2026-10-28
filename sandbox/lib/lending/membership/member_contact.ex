defmodule Lending.Membership.MemberContact do
  @moduledoc "**Invented.** Answers the desk: a member's name and latest e-mail, per membership."

  use Lending.Contracts.Membership, query: :member_contact

  import Ecto.Query

  @impl true
  def member_contact(%MemberContact{member_id: member}, _ctx) do
    from(m in Row, where: m.member_id == ^member, order_by: m.membership_id)
    |> EhOsContract.Config.fetch!(:repo).all()
  end
end
