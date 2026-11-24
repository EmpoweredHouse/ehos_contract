defmodule EhosContract.LifecycleScenariosTest do
  @moduledoc """
  Plan LC2: `LifecycleRig.Visits`' scenarios, run against its implementation. Two of
  them are refused by the engine, not by the code: the decider never reads the status.
  """

  use EhosContract.ScenarioCase, contract: LifecycleRig.Visits
end
