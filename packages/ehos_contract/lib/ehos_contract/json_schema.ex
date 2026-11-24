defmodule EhosContract.JsonSchema do
  # JSON Schema objects for fields of a v2 contract.
  #
  # AsyncAPI and OpenAPI share this projection so an `:id`, a domain value or an
  # optional field cannot mean one thing on the event side and another on the HTTP
  # side. The `x-ehos-contract-type` extension keeps the DSL type where JSON Schema
  # itself collapses distinctions such as `:id` and `:string`, and
  # `x-ehos-contract-max-bytes` gives an `:id`'s bound in bytes, which JSON Schema counts
  # only in characters.
  @moduledoc false

  alias EhosContract.Model

  @doc """
  A closed object schema for `fields`, resolving domain values through `domain`.

  With `erased: true`, a personal field also admits `null`: it remains a required
  key, but crypto-shredding can remove its value from a query row.
  """
  @spec object([map()], module() | map(), keyword()) :: map()
  def object(fields, domain, opts \\ []) do
    domain = Model.fetch(domain)
    values = Map.new(domain.values, &{&1.name, &1})
    erased? = Keyword.get(opts, :erased, false)

    %{
      "type" => "object",
      "properties" => Map.new(fields, &{to_string(&1.name), field_schema(&1, values, erased?)}),
      "required" =>
        fields
        |> Enum.reject(&Map.get(&1, :optional, false))
        |> Enum.map(&to_string(&1.name))
        |> Enum.sort(),
      "additionalProperties" => false
    }
  end

  @doc "The schema of one declared field, resolving domain values through `domain`."
  @spec field(map(), module() | map()) :: map()
  def field(field, domain) do
    values =
      domain |> Model.fetch() |> then(&Map.new(&1.values, fn value -> {value.name, value} end))

    field_schema(field, values, false)
  end

  defp field_schema(field, values, erased?) do
    field.type
    |> property(values, erased?)
    |> maybe_put("title", Map.get(field, :label))
    |> maybe_put("x-ehos-contract-personal", Map.get(field, :personal))
    |> maybe_put("x-ehos-contract-subject", Map.get(field, :subject))
    |> maybe_put("x-ehos-contract-issued-by", Map.get(field, :issued_by))
    |> nullable(
      Map.get(field, :optional, false) or (erased? and Map.get(field, :personal) != nil)
    )
  end

  defp nullable(schema, true), do: %{"anyOf" => [schema, %{"type" => "null"}]}
  defp nullable(schema, false), do: schema

  defp property(type, values, erased?) do
    type
    |> base_property(values, erased?)
    |> Map.put("x-ehos-contract-type", type_data(type))
  end

  defp base_property(type, values, erased?) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} -> object_fields(fields, values, erased?)
      %{type: inner} -> base_property(inner, values, erased?)
    end
  end

  # The codec's bounds (`EhosContract.Codec`), where JSON Schema has a word for them. It
  # counts an identifier's characters and the codec its UTF-8 bytes, so the bytes are
  # given beside it: a hundred four-byte characters pass `maxLength` and not the codec.
  defp base_property(:id, _values, _erased?),
    do: %{
      "type" => "string",
      "minLength" => 1,
      "maxLength" => 255,
      "x-ehos-contract-max-bytes" => 255
    }

  defp base_property(type, _values, _erased?) when type in [:string, :decimal],
    do: %{"type" => "string"}

  # `format` only annotates, so a validator would take 2 ** 63; the range asserts it.
  defp base_property(:integer, _values, _erased?),
    do: %{
      "type" => "integer",
      "format" => "int64",
      "minimum" => -9_223_372_036_854_775_808,
      "maximum" => 9_223_372_036_854_775_807
    }

  defp base_property(:boolean, _values, _erased?), do: %{"type" => "boolean"}
  defp base_property(:date, _values, _erased?), do: %{"type" => "string", "format" => "date"}

  defp base_property(:timestamp, _values, _erased?),
    do: %{"type" => "string", "format" => "date-time"}

  defp base_property({:id, _entity}, values, erased?), do: base_property(:id, values, erased?)

  defp base_property({:enum, members}, _values, _erased?),
    do: %{"type" => "string", "enum" => Enum.map(members, &enum_name/1)}

  defp base_property({:list, inner}, values, erased?),
    do: %{"type" => "array", "items" => property(inner, values, erased?)}

  defp object_fields(fields, values, erased?) do
    %{
      "type" => "object",
      "properties" => Map.new(fields, &{to_string(&1.name), field_schema(&1, values, erased?)}),
      "required" =>
        fields
        |> Enum.reject(&Map.get(&1, :optional, false))
        |> Enum.map(&to_string(&1.name))
        |> Enum.sort(),
      "additionalProperties" => false
    }
  end

  defp type_data(type) when is_atom(type), do: Atom.to_string(type)
  defp type_data({:id, entity}), do: %{"id" => Atom.to_string(entity)}
  defp type_data({:list, inner}), do: %{"list" => type_data(inner)}
  defp type_data({:enum, members}), do: %{"enum" => Enum.map(members, &enum_name/1)}

  defp enum_name({name, _label}), do: Atom.to_string(name)
  defp enum_name(name), do: Atom.to_string(name)

  defp maybe_put(map, _key, nil), do: map

  defp maybe_put(map, key, value) when is_atom(value),
    do: Map.put(map, key, Atom.to_string(value))

  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
