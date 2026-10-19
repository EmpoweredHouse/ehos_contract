defmodule Lending.Circulation.Copy do
  @moduledoc "**Invented.** Decides a copy's withdrawal from circulation, once."

  use Lending.Contracts.Circulation, aggregate: :copy

  @impl true
  def withdraw_copy(_command, %State{withdrawn: true}), do: reject(:withdrawn_once)

  def withdraw_copy(%WithdrawCopy{copy_id: id}, _state),
    do: emit(%WithdrawnFromCirculation{copy_id: id})

  @impl true
  def evolve(state, %WithdrawnFromCirculation{}), do: %{state | withdrawn: true}
end
