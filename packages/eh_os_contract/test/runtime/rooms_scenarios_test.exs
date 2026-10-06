defmodule EhOsContract.RoomsScenariosTest do
  @moduledoc """
  Plan DD, P1c (#190): `LifecycleRig.Rooms`' scenarios, run against its
  implementation: a contract without a process still runs its scenarios as tests.
  """

  use EhOsContract.ScenarioCase, contract: LifecycleRig.Rooms
end
