defmodule AppuniteEquipment.Demanding do
  @moduledoc """
  The implementation of `AppuniteEquipment.Contracts.Demands`: the demand's
  decision, pure, the two policies that open and close a demand on the computer's
  events, and the list of who is waiting. It exists so that the contract's scenarios
  run.
  """

  use Boundary,
    deps: [EhOsContract, AppuniteEquipment.Contracts],
    exports: [Demand, FulfilOnIssue, OpenAfterTheft, WaitingRows, WaitingList]
end
