defmodule EhOsContract.ActorIsTest do
  @moduledoc """
  Plan DD, A1 (#247): a command whose `actor_is` names a field of the unit's state is
  issued only by the person that field holds. Another credential is refused on the
  invariant before the decision, with a `rejected` row; the application's own `:system`
  actor passes. On the invented `PersonRig.Desk`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, CommandRecord, Event, Receipt, Rejection}
  alias PersonRig.Desk
  alias PersonRig.Desk.Commands.{AssignTicket, ResolveTicket}

  @capabilities ["person_rig.assign_ticket", "person_rig.resolve_ticket"]

  defp clerk(subject), do: Actor.credential(subject, @capabilities)

  defp assign!(ticket, clerk) do
    {:ok, _} =
      EhOsContract.dispatch(Desk, %AssignTicket{ticket_id: ticket, assignee_id: clerk},
        actor: clerk("clerk-ada")
      )
  end

  defp resolve(ticket, actor),
    do: EhOsContract.dispatch(Desk, %ResolveTicket{ticket_id: ticket}, actor: actor)

  defp resolved,
    do: Repo.all(from(e in Event, where: e.type == "person_rig.desk.resolved", select: e.id))

  test "the clerk the ticket is assigned to resolves it" do
    assign!("ticket-1", "clerk-bo")

    assert {:ok, %Receipt{events: [_]}} = resolve("ticket-1", clerk("clerk-bo"))
    assert [_] = resolved()
  end

  test "another clerk with the same credential is refused on the invariant, with a row" do
    assign!("ticket-1", "clerk-bo")

    assert {:error, %Rejection{invariant: :only_its_assignee_resolves}} =
             resolve("ticket-1", clerk("clerk-ada"))

    assert resolved() == []

    assert %{outcome: "rejected", invariant: "only_its_assignee_resolves"} =
             Repo.one!(from(c in CommandRecord, where: c.type == "resolve_ticket"))
  end

  test "a ticket assigned to nobody yet names nobody, and every clerk is refused" do
    assert {:error, %Rejection{invariant: :only_its_assignee_resolves}} =
             resolve("ticket-1", clerk("clerk-ada"))
  end

  test "the application's own :system actor passes, whoever the ticket is assigned to" do
    assign!("ticket-1", "clerk-bo")

    assert {:ok, %Receipt{events: [_]}} =
             resolve("ticket-1", Actor.system(:night_shift))
  end
end
