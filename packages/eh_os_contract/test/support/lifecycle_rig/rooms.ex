defmodule LifecycleRig.Rooms do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The clinic's rooms, which open and are retired and belong to no process: a room has
  a lifecycle and no run (plan DD, P1c (#190)). It is the shape of a register — of
  equipment, of rooms — that a process only consults.
  """

  use EhOsContract.Contract,
    domain: LifecycleRig.Domain,
    context: :visits,
    id: "lifecycle_rig.rooms"

  aggregate :room, "Room" do
    identity :room_id

    invariant :only_an_available_room, "Only an available room is retired"

    lifecycle do
      status :available, "Available"
      status :retired, "Retired", final: true

      initial :available, on: :opened
      transition :available, :retired, :retired
    end

    command :open_room, "Open a room", by: :reception, emits: :opened

    command :retire_room, "Retire a room",
      by: :reception,
      emits: :retired,
      from: :available,
      or_rejects: :only_an_available_room,
      rejects: :only_an_available_room

    event :opened, "Room opened"
    event :retired, "Room retired"
  end

  scenario "an available room is retired" do
    given :opened
    command :retire_room
    expect :retired
  end

  scenario "a retired room is not retired again" do
    given :opened
    given :retired
    command :retire_room
    rejected :only_an_available_room
  end
end
