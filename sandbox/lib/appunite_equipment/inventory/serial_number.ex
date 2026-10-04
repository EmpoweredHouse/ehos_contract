defmodule AppuniteEquipment.Inventory.SerialNumber do
  @moduledoc """
  The invariant of `AppuniteEquipment.Domain`'s value `:serial_number`: eight to
  fourteen capital letters and digits, in ASCII. It does not tell an old serial
  number from a random one, nor check what an old one encodes.
  """

  use AppuniteEquipment.Domain, value: :serial_number

  # `[0-9]`, not `\d`: with `u`, `\d` is any Unicode digit.
  @format ~r/\A[A-Z0-9]{8,14}\z/u

  @impl true
  def apple_format(serial), do: Regex.match?(@format, serial)
end
