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
  does not compile against (v2 §8): `problems/2` leaves it alone, and the Mix
  compiler checks it with `problems/3`, given the domain's values (L3, X9).
  """

  @built_in EhOsContract.Domain.Rules.built_in_types()

  @typedoc "A field's type, as a contract declares it."
  @type type :: atom() | {:enum, list()} | {:list, type()} | {:id, atom()}

  @doc """
  What is wrong with `value` as a value of `type`, as far as a contract can tell on
  its own: an empty list when it fits, or when the type is a domain value.
  """
  @spec problems(type(), term()) :: [String.t()]
  def problems(_type, nil), do: []
  # As `EhOsContract.Codec` refuses it at dispatch: an identifier that names nothing.
  def problems(:id, ""), do: [~s|"" is not an identifier, which names something|]
  def problems(:id, value) when is_binary(value), do: []
  def problems({:id, _entity}, value), do: problems(:id, value)
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

  @doc """
  What is wrong with `value` as a value of `type`, domain values included: `values`
  are the domain's, by name. A value with a type is a value of that type; a value
  with fields is a map of those fields, each required one given.
  """
  @spec problems(type(), term(), %{atom() => map()}) :: [String.t()]
  def problems(_type, nil, _values), do: []

  def problems({:list, inner}, list, values) when is_list(list),
    do: Enum.flat_map(list, &problems(inner, &1, values))

  def problems(type, value, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        fields_problems(type, fields, value, values)

      %{type: nil} ->
        ["#{inspect(value)} is not a map of the fields of #{inspect(type)}"]

      %{type: inner} ->
        problems(inner, value, values)
    end
  end

  def problems(type, value, _values), do: problems(type, value)

  defp fields_problems(type, fields, value, values) do
    declared = Map.new(fields, &{&1.name, &1})

    unknown =
      for key <- Map.keys(value), not Map.has_key?(declared, key) do
        "#{inspect(type)} has no field #{inspect(key)}"
      end

    missing =
      for f <- fields, not f.optional, not Map.has_key?(value, f.name) do
        "#{inspect(type)} needs #{inspect(f.name)}"
      end

    nested =
      for {key, v} <- value,
          field = declared[key],
          field != nil,
          problem <- problems(field.type, v, values) do
        "#{inspect(type)}, field #{inspect(key)}: #{problem}"
      end

    unknown ++ missing ++ nested
  end

  defp example(:date), do: ~s|an ISO 8601 date, "2026-09-01"|
  defp example(:timestamp), do: ~s|an ISO 8601 string, "2026-09-01T09:00:00Z"|

  defp describe({:list, inner}), do: "a list of #{describe(inner)}"
  defp describe(:id), do: "an :id, a string"
  defp describe(:integer), do: "an :integer"
  defp describe(type), do: "a #{inspect(type)}"
end
