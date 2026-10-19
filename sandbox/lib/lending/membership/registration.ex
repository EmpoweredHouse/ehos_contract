defmodule Lending.Membership.Registration do
  @moduledoc """
  **Invented.** Decides a membership: registered once, and its e-mail changed only
  once it is, and only for the member it was registered for. The member's name and e-mail go into the events as given; the engine
  seals them with the member's key.
  """

  use Lending.Contracts.Membership, aggregate: :membership

  @impl true
  def register_member(_command, %State{registered: true}), do: reject(:registered_once)

  def register_member(%RegisterMember{} = command, _state) do
    emit(%MemberRegistered{
      membership_id: command.membership_id,
      member_id: command.member_id,
      name: command.name,
      email: command.email
    })
  end

  @impl true
  def change_email(%ChangeEmail{member_id: member} = command, %State{member_id: member})
      when member != nil do
    emit(%EmailChanged{
      membership_id: command.membership_id,
      member_id: command.member_id,
      email: command.email
    })
  end

  def change_email(_command, _state), do: reject(:only_a_registered_member_changes)

  # Neither callback reads the name or the e-mail back, so an erased member's events,
  # which read back with `EhOsContract.Erased` in their place, fold like any other.
  @impl true
  def evolve(state, %MemberRegistered{member_id: member}),
    do: %{state | registered: true, member_id: member}

  def evolve(state, %EmailChanged{}), do: state
end
