defmodule Lending.ErasureTest do
  @moduledoc """
  A member's personal data in a real project, from registration to erasure: sealed in
  the log, kept in the clear in the member directory, and gone from both once the
  member is erased. The engine's own tests hold each step on an invented rig; this one
  runs them through a host's configuration, its vault key and its migration.
  """

  use EhOsContractHost.DataCase, async: false

  alias EhOsContract.{Actor, Consumer, Erased, Event}
  alias Lending.Contracts.Membership
  alias Lending.Contracts.Membership.Commands.{ChangeEmail, RegisterMember}
  alias Lending.Contracts.Membership.Queries.MemberContact

  @librarian Actor.credential("librarian-una", [
               "lending.register_member",
               "lending.change_email",
               "lending.member_contact"
             ])

  setup do
    {:ok, _} =
      EhOsContract.dispatch(
        Membership,
        %RegisterMember{
          membership_id: "membership-ada",
          member_id: "member-ada",
          name: "Ada Lovelace",
          email: "ada@example.org"
        },
        actor: @librarian
      )

    :ok
  end

  defp contact,
    do: EhOsContract.query(Membership, %MemberContact{member_id: "member-ada"}, actor: @librarian)

  defp change_email(email) do
    EhOsContract.dispatch(
      Membership,
      %ChangeEmail{membership_id: "membership-ada", member_id: "member-ada", email: email},
      actor: @librarian
    )
  end

  test "the log holds the member's data sealed, and the directory in the clear" do
    [payload] =
      Repo.all(
        from(e in Event,
          where: e.type == "lending.membership.member_registered",
          select: e.payload
        )
      )

    refute inspect(payload) =~ "Ada Lovelace"
    refute inspect(payload) =~ "ada@example.org"
    assert payload["member_id"] == "member-ada"

    assert {:ok, %{name: "Ada Lovelace", email: "ada@example.org"}} = contact()
  end

  test "erasing the member empties the directory, and their events read back erased" do
    assert {:ok, :erased} = EhOsContract.erase(:member, "member-ada", actor: @librarian)

    assert {:ok, nil} = contact()

    ada = %Erased{subject: :member, id: "member-ada"}

    assert [%{name: ^ada, email: ^ada}] =
             Repo.all(from(e in Event, where: e.type == "lending.membership.member_registered"))
             |> Enum.map(&Consumer.decode!/1)
  end

  test "an erased member's data is not written again" do
    {:ok, :erased} = EhOsContract.erase(:member, "member-ada", actor: @librarian)

    assert {:error, :subject_erased} = change_email("ada@example.net")
    assert {:ok, :already_erased} = EhOsContract.erase(:member, "member-ada", actor: @librarian)
  end

  test "the control: a member not erased changes e-mail, and the directory follows" do
    assert {:ok, _} = change_email("ada@example.net")
    assert {:ok, %{email: "ada@example.net"}} = contact()
  end
end
