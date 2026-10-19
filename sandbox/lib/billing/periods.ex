defmodule Billing.Periods do
  @moduledoc """
  **Invented.** Billing periods are months named `YYYY-MM`. This module names them and
  works out their dates, without the database: the month a moment falls in, the first
  moment of the next month, and the month that ended just before a moment.
  """

  use Boundary, deps: [EhOsContract, Billing.Domain], exports: [Name]

  @doc "Whether `name` is a month written `YYYY-MM`."
  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name) do
    case Regex.run(~r/\A([0-9]{4})-([0-9]{2})\z/, name) do
      [_, _year, month] -> String.to_integer(month) in 1..12
      _ -> false
    end
  end

  def name?(_name), do: false

  @doc "The first moment, UTC, of the month after the one `moment` falls in."
  @spec next_month_start(DateTime.t()) :: DateTime.t()
  def next_month_start(%DateTime{} = moment) do
    moment |> DateTime.to_date() |> Date.beginning_of_month() |> Date.shift(month: 1) |> start()
  end

  @doc "The name of the month that ended just before `moment`."
  @spec ended_before(DateTime.t()) :: String.t()
  def ended_before(%DateTime{} = moment) do
    moment |> DateTime.add(-1) |> DateTime.to_date() |> name()
  end

  defp start(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp name(%Date{year: year, month: month}),
    do: "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}"
end

defmodule Billing.Periods.Name do
  @moduledoc "The invariant of `Billing.Domain`'s value `:billing_period`: a month, named YYYY-MM."

  use Billing.Domain, value: :billing_period

  @impl true
  def named_by_month(name), do: Billing.Periods.name?(name)
end
