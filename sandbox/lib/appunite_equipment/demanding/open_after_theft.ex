defmodule AppuniteEquipment.Demanding.OpenAfterTheft do
  @moduledoc """
  The policy `open_after_theft`: the person a computer was stolen from needs
  another, and the demand opens with no start date, since they are already working.
  """

  use AppuniteEquipment.Contracts.Demands, policy: :open_after_theft

  @impl true
  def lost(%Lost{employee_id: employee}),
    do: issue(%OpenDemand{employee_id: employee, reason: :theft})
end
