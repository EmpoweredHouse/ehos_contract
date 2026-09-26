defmodule EhOsContract.Codec do
  @moduledoc """
  Field values against their declared types, and their form in the log (v2 §5,
  §11): what the compiler cannot check, since a struct can be built with any value
  in any field.

  **Types.** `:id` and `:string` are binaries, `:integer` and `:boolean` what they
  say, `:decimal` a `Decimal`, `:date` a `Date`, `:timestamp` a `DateTime` in UTC,
  `{:enum, members}` one of the member atoms, `{:list, type}` a list of them. A
  domain value is its own type: an alias of a type (`value :money, :integer`), or a
  map of its fields.

  **The log's form is JSON's.** A decimal is written as a string of digits, so no
  float ever stands between two sums; a date and a timestamp as ISO 8601; an enum
  member as its name. Reading back never creates an atom: a member is found among
  the declared ones, and a name the contract no longer declares does not fit.

  **Problems name the field and what is wrong, never the value** (v2 §17): they
  travel to logs, telemetry and HTTP callers, and a value may be personal data.
  """

  @typedoc "A declared field, as a model carries it."
  @type field :: %{
          required(:name) => atom(),
          required(:type) => term(),
          optional(atom()) => term()
        }

  @typedoc "A domain's values, by name: `values/1`."
  @type values :: %{atom() => map()}

  @typedoc "What is wrong with one field: missing, or not of its type."
  @type problem :: {atom(), :required | :type}

  @doc """
  The values a domain declares, by name. `%{}` when the domain is not a compiled
  `EhOsContract.Domain`, and then a field of a domain value fits nothing.
  """
  @spec values(module()) :: values()
  def values(domain) do
    if Code.ensure_loaded?(domain) and function_exported?(domain, :__eh_os_contract_model__, 0),
      do: Map.new(domain.__eh_os_contract_model__().values, &{&1.name, &1}),
      else: %{}
  end

  @doc """
  What is wrong with `data`, a struct or a map with atom keys, against `fields`: a
  required field that is `nil`, or a value not of its type. `[]` when nothing is.
  """
  @spec problems([field()], map(), values()) :: [problem()]
  def problems(fields, data, values) do
    for field <- fields,
        problem <- field_problems(field, Map.get(data, field.name), values),
        do: {field.name, problem}
  end

  defp field_problems(field, nil, _values),
    do: if(Map.get(field, :optional, false), do: [], else: [:required])

  defp field_problems(field, value, values),
    do: if(fits?(field.type, value, values), do: [], else: [:type])

  defp fits?(type, value, _values) when type in [:id, :string], do: is_binary(value)
  defp fits?(:integer, value, _values), do: is_integer(value)
  defp fits?(:boolean, value, _values), do: is_boolean(value)
  defp fits?(:decimal, value, _values), do: is_struct(value, Decimal)
  defp fits?(:date, value, _values), do: is_struct(value, Date)

  defp fits?(:timestamp, value, _values),
    do: is_struct(value, DateTime) and value.time_zone == "Etc/UTC"

  defp fits?({:enum, members}, value, _values), do: is_atom(value) and value in names(members)

  defp fits?({:list, inner}, value, values),
    do: is_list(value) and Enum.all?(value, &fits?(inner, &1, values))

  defp fits?(type, value, values) when is_atom(type) do
    case Map.fetch(values, type) do
      {:ok, %{type: nil, fields: fields}} ->
        is_map(value) and problems(fields, value, values) == []

      {:ok, %{type: inner}} ->
        fits?(inner, value, values)

      :error ->
        false
    end
  end

  defp fits?(_type, _value, _values), do: false

  @doc """
  `data`'s fields in the log's form: a map with string keys, JSON-encodable. Every
  declared field is written, `nil` included, so a payload says a field was absent
  rather than leaving it to be guessed. Assumes `problems/3` found nothing.
  """
  @spec encode([field()], map(), values()) :: %{String.t() => term()}
  def encode(fields, data, values) do
    Map.new(fields, fn field ->
      {Atom.to_string(field.name), encode_value(field.type, Map.get(data, field.name), values)}
    end)
  end

  @doc "One value in the log's form. What a scoped query compares, as a string."
  @spec encode_value(term(), term(), values()) :: term()
  def encode_value(_type, nil, _values), do: nil
  def encode_value(:decimal, value, _values), do: Decimal.to_string(value, :normal)
  def encode_value(:date, value, _values), do: Date.to_iso8601(value)
  def encode_value(:timestamp, value, _values), do: DateTime.to_iso8601(value)
  def encode_value({:enum, _members}, value, _values), do: Atom.to_string(value)

  def encode_value({:list, inner}, value, values),
    do: Enum.map(value, &encode_value(inner, &1, values))

  def encode_value(type, value, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} -> encode(fields, value, values)
      %{type: inner} -> encode_value(inner, value, values)
    end
  end

  def encode_value(_type, value, _values), do: value

  @doc """
  Fields from their external form — the log's, or JSON a caller sent — to the values
  a struct holds. Keys are read as strings, or as atoms when the map has those.
  Fails with the fields that do not fit, and never creates an atom.
  """
  @spec decode([field()], map(), values()) :: {:ok, map()} | {:error, [problem()]}
  def decode(fields, external, values) when is_map(external) do
    {decoded, problems} =
      Enum.reduce(fields, {%{}, []}, fn field, {decoded, problems} ->
        raw = Map.get(external, Atom.to_string(field.name), Map.get(external, field.name))

        case decode_value(field.type, raw, values) do
          {:ok, nil} ->
            if Map.get(field, :optional, false),
              do: {Map.put(decoded, field.name, nil), problems},
              else: {decoded, [{field.name, :required} | problems]}

          {:ok, value} ->
            {Map.put(decoded, field.name, value), problems}

          :error ->
            {decoded, [{field.name, :type} | problems]}
        end
      end)

    if problems == [], do: {:ok, decoded}, else: {:error, Enum.reverse(problems)}
  end

  defp decode_value(_type, nil, _values), do: {:ok, nil}

  defp decode_value(type, value, _values) when type in [:id, :string] and is_binary(value),
    do: {:ok, value}

  defp decode_value(:integer, value, _values) when is_integer(value), do: {:ok, value}
  defp decode_value(:boolean, value, _values) when is_boolean(value), do: {:ok, value}

  defp decode_value(:decimal, value, _values) when is_binary(value) or is_integer(value) do
    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, decimal}
      :error -> :error
    end
  end

  defp decode_value(:date, value, _values) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  defp decode_value(:timestamp, value, _values) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _} -> :error
    end
  end

  defp decode_value({:enum, members}, value, _values) when is_binary(value) or is_atom(value) do
    name = to_string(value)

    case Enum.find(names(members), &(Atom.to_string(&1) == name)) do
      nil -> :error
      member -> {:ok, member}
    end
  end

  defp decode_value({:list, inner}, value, values) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case decode_value(inner, item, values) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp decode_value(type, value, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        case decode(fields, value, values) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> :error
        end

      %{type: nil} ->
        :error

      %{type: inner} ->
        decode_value(inner, value, values)
    end
  end

  defp decode_value(_type, _value, _values), do: :error

  # An enum's members: atoms, or `atom: label` pairs.
  defp names(members),
    do:
      Enum.map(members, fn
        {name, _label} -> name
        name -> name
      end)
end
