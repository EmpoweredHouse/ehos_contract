defmodule EhOsContract.ContractDataCastTest do
  @moduledoc """
  **`EhOsContract.Contract.Data.cast/3`** (plan W4): a value written in a contract, as
  the value its field holds at run time. `EhOsContract.ScenarioCase` casts every
  scenario's data through it, so the scenarios pin it end to end; this file pins it on
  its own.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Contract.Data

  @domain %{
    amount: %{name: :amount, type: :decimal, fields: []},
    period: %{
      name: :period,
      type: nil,
      fields: [%{name: :from, type: :date}, %{name: :days, type: :integer}]
    }
  }

  test "built-in values written as plain data become the values the field holds" do
    assert Data.cast(:timestamp, "2026-09-01T09:00:00Z", %{}) ==
             {:ok, ~U[2026-09-01 09:00:00Z]}

    assert Data.cast(:date, "2026-09-01", %{}) == {:ok, ~D[2026-09-01]}
    assert Data.cast(:decimal, "12.50", %{}) == {:ok, Decimal.new("12.50")}
    assert Data.cast({:list, :date}, ["2026-09-01"], %{}) == {:ok, [~D[2026-09-01]]}
    assert Data.cast(:string, "visit", %{}) == {:ok, "visit"}
    assert Data.cast(:date, nil, %{}) == {:ok, nil}
  end

  test "a domain value is cast through the type it rests on, or field by field" do
    assert Data.cast(:amount, 12, @domain) == {:ok, Decimal.new(12)}

    assert Data.cast(:period, %{from: "2026-09-01", days: 3}, @domain) ==
             {:ok, %{from: ~D[2026-09-01], days: 3}}
  end

  test "what does not fit is the first problem, not a raise" do
    assert {:error, problem} = Data.cast(:date, "01/09/2026", %{})
    assert problem =~ "ISO 8601"

    assert Data.cast(:period, "2026-09", @domain) ==
             {:error, ~s|"2026-09" is not a map of the fields of :period|}
  end

  test "a type the domain does not name is left as written" do
    assert Data.cast(:unknown_value, "anything", %{}) == {:ok, "anything"}
  end
end
