defmodule Lending.Circulation.CopyHold do
  @moduledoc """
  **Invented.** Decides a hold on a copy, over everything the boundary consults: the
  holds placed on the copy, its loans and its withdrawal. A hold stands until the copy
  is lent to the member it is held for, and a withdrawn copy takes none. Dispatch decides again when any of them was
  appended after the read, so two members asking at once get one hold between them.
  """

  use Lending.Contracts.Circulation, dcb: :copy_hold

  @impl true
  def place_hold(_command, %State{withdrawn: true}), do: reject(:withdrawn_copy_takes_no_hold)

  def place_hold(%PlaceHold{copy_id: copy, member_id: member}, %State{held_by: nil}),
    do: emit(%HoldPlaced{copy_id: copy, member_id: member})

  def place_hold(_command, _state), do: reject(:one_hold_per_copy)

  @impl true
  def evolve(state, %HoldPlaced{member_id: member}), do: %{state | held_by: member}

  def evolve(%State{held_by: member} = state, %CopyLent{member_id: member}),
    do: %{state | held_by: nil}

  def evolve(state, %CopyLent{}), do: state
  def evolve(state, %WithdrawnFromCirculation{}), do: %{state | withdrawn: true}
end
