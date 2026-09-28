defmodule Taxvision.DocumentIntake.KsefNumber do
  @moduledoc """
  The invariant of `Taxvision.Domain`'s value `:ksef_number`: the seller's NIP, the
  date as YYYYMMDD, twelve hex digits and a two-hex-digit checksum, joined by
  dashes, in ASCII digits. The checksum's value is not checked.
  """

  use Taxvision.Domain, value: :ksef_number

  # `[0-9]`, not `\d`: with `u`, `\d` is any Unicode digit, which the date's
  # `String.to_integer/1` does not read.
  @format ~r/\A[0-9]{10}-([0-9]{4})([0-9]{2})([0-9]{2})-[0-9A-F]{12}-[0-9A-F]{2}\z/u

  @impl true
  def ksef_format(number) do
    with [_, year, month, day] <- Regex.run(@format, number),
         {:ok, _} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      true
    else
      _ -> false
    end
  end
end
