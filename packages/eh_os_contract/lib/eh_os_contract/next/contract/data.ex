defmodule EhOsContract.Next.Contract.Data do
  @moduledoc """
  Values written in a contract — a scenario's data — against the types of the
  fields they fill.

  A contract compiles to plain data (v2 §9), so a value written in it is plain data
  too. **A timestamp is an ISO 8601 string with an offset, `"2026-09-01T09:00:00Z"`,
  and a date an ISO 8601 date, `"2026-09-01"`**: a `~U` or `~D` literal would put a
  struct into the model, which then no longer encodes to JSON unchanged. A decimal is
  an integer or a string of digits, for the same reason.

  A field typed with a domain value is checked against the domain, which a contract
  does not compile against (v2 §8): `problems/2` leaves it alone, and a Mix compiler
  checks it (L3, X9).
  """

  @built_in EhOsContract.Domain.Rules.built_in_types()

  @typedoc "A field's type, as a contract declares it."
  @type type :: atom() | {:enum, list()} | {:list, type()}

  @doc """
  What is wrong with `value` as a value of `type`, as far as a contract can tell on
  its own: an empty list when it fits, or when the type is a domain value.
  """
  @spec problems(type(), term()) :: [String.t()]
  def problems(_type, nil), do: []
  def problems(:id, value) when is_binary(value), do: []
  def problems(:string, value) when is_binary(value), do: []
  def problems(:integer, value) when is_integer(value), do: []
  def problems(:boolean, value) when is_boolean(value), do: []
  def problems(:decimal, value) when is_integer(value), do: []

  def problems(:decimal, value) when is_binary(value) do
    if value =~ ~r/^-?\d+(\.\d+)?$/,
      do: [],
      else: ["#{inspect(value)} is not a decimal; write an integer or a string of digits"]
  end

  def problems(:date, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _} -> []
      {:error, _} -> ["#{inspect(value)} is not an ISO 8601 date, \"2026-09-01\""]
    end
  end

  def problems(:timestamp, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} ->
        []

      {:error, _} ->
        [
          "#{inspect(value)} is not an ISO 8601 timestamp with an offset, \"2026-09-01T09:00:00Z\""
        ]
    end
  end

  def problems(type, %struct{}) when type in [:date, :timestamp] do
    ["#{inspect(struct)} is a struct; write #{example(type)}, since the model is plain data"]
  end

  def problems({:enum, members}, value) do
    names =
      Enum.map(members, fn
        {name, _label} -> name
        name -> name
      end)

    if value in names,
      do: [],
      else: ["#{inspect(value)} is not one of #{inspect(names)}"]
  end

  def problems({:list, inner}, values) when is_list(values),
    do: Enum.flat_map(values, &problems(inner, &1))

  def problems(type, value) when type in @built_in or is_tuple(type) do
    ["#{inspect(value)} is not #{describe(type)}"]
  end

  # A domain value: the domain says.
  def problems(type, _value) when is_atom(type), do: []

  defp example(:date), do: ~s|an ISO 8601 date, "2026-09-01"|
  defp example(:timestamp), do: ~s|an ISO 8601 string, "2026-09-01T09:00:00Z"|

  defp describe({:list, inner}), do: "a list of #{describe(inner)}"
  defp describe(:id), do: "an :id, a string"
  defp describe(:integer), do: "an :integer"
  defp describe(type), do: "a #{inspect(type)}"
end
