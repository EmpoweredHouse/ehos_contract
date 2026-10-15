defmodule GraphLab.Pesel do
  @moduledoc """
  The invariant of `GraphLab.Domain`'s value `:pesel`: eleven ASCII digits. The checksum
  is not checked.
  """

  use GraphLab.Domain, value: :pesel

  @impl true
  def eleven_digits(pesel), do: Regex.match?(~r/\A[0-9]{11}\z/u, pesel)
end
