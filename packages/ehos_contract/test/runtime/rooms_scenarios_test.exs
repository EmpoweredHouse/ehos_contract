defmodule EhosContract.RoomsScenariosTest do
  @moduledoc """
  Plan DD, P1c (#190): `LifecycleRig.Rooms`' scenarios, run against its
  implementation: a contract without a process still runs its scenarios as tests.
  """

  use EhosContract.ScenarioCase, contract: LifecycleRig.Rooms
end
