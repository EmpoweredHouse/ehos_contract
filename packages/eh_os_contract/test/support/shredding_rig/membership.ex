defmodule ShreddingRig.Membership do
  @moduledoc "**Invented.** The decider of `ShreddingRig.Members`'s membership."

  use ShreddingRig.Members, aggregate: :membership

  @impl true
  def join(%Join{} = c, _state) do
    emit(%Joined{
      membership_id: c.membership_id,
      member_id: c.member_id,
      name: c.name,
      email: c.email,
      contacts: c.contacts,
      plan: c.plan
    })
  end

  @impl true
  def rename(%Rename{} = c, %State{name: previous}) do
    emit(%Renamed{
      membership_id: c.membership_id,
      member_id: c.member_id,
      name: c.name,
      previous: previous
    })
  end

  @impl true
  def evolve(state, %Joined{member_id: member, name: name}),
    do: %{state | member_id: member, name: name}

  def evolve(state, %Renamed{name: name}), do: %{state | name: name}
end
