defmodule LifecycleRig.Room do
  @moduledoc "**Invented.** The decider of `LifecycleRig.Rooms`' room."

  use LifecycleRig.Rooms, aggregate: :room

  @impl true
  def open_room(%OpenRoom{room_id: id}, _state), do: emit(%Opened{room_id: id})

  @impl true
  def retire_room(%RetireRoom{room_id: id}, _state), do: emit(%Retired{room_id: id})
end
