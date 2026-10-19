defmodule UpcastRig.Fees do
  @moduledoc """
  # THIS IMPLEMENTATION IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The fee unit of `UpcastRig.Demands`: version 1 of `:fee_charged` held its amount in
  cents, `amount_minor`. A row's `"do"` says which of the things a function may not do
  this one does instead, so that a test can watch the read refuse it.
  """

  use UpcastRig.Demands, aggregate: :fee

  @impl true
  def amount_from_minor(%{"do" => "move_seal"} = data),
    do: data |> Map.delete("note") |> Map.put("remark", data["note"]) |> amount()

  def amount_from_minor(%{"do" => "change_tag"} = data),
    do: data |> Map.put("requester_id", "someone-else") |> amount()

  def amount_from_minor(%{"do" => "raise"} = data), do: Map.fetch!(data, "no such field")
  def amount_from_minor(%{"do" => "no_map"}), do: :not_a_map

  def amount_from_minor(%{"do" => "collide"} = data),
    do: data |> amount() |> Map.put(:amount, "1.00")

  def amount_from_minor(%{"do" => "clear"} = data),
    do: data |> amount() |> Map.put("note", "written in the clear")

  def amount_from_minor(%{"do" => "struct"}), do: Decimal.new(1)
  def amount_from_minor(%{"do" => "throw"} = data), do: throw(data)
  def amount_from_minor(%{"do" => "exit"} = data), do: exit({:gone, data})

  # A decimal, as the docs' example gives it, and atom keys: read as the log stores them.
  def amount_from_minor(%{"do" => "stored_form", "amount_minor" => minor} = data) do
    data
    |> Map.drop(["amount_minor", "do"])
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Map.put(:amount, Decimal.div(minor, 100))
  end

  def amount_from_minor(data), do: amount(data)

  defp amount(%{"amount_minor" => minor} = data) do
    data
    |> Map.delete("amount_minor")
    |> Map.delete("do")
    |> Map.put("amount", minor |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string())
  end
end
