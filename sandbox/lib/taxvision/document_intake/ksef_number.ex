defmodule Taxvision.DocumentIntake.KsefNumber do
  @moduledoc """
  The invariant of `Taxvision.Domain`'s value `:ksef_number`: the seller's NIP, the
  date as YYYYMMDD, twelve hex digits and a two-hex-digit checksum, joined by dashes.
  The checksum's value is not checked.
  """

  use Taxvision.Domain, value: :ksef_number

  @format ~r/\A\d{10}-(\d{4})(\d{2})(\d{2})-[0-9A-F]{12}-[0-9A-F]{2}\z/u

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
