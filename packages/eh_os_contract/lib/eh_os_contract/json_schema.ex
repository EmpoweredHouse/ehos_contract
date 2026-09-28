defmodule EhOsContract.JsonSchema do
  @moduledoc """
  JSON Schema objects for fields of a v2 contract.

  AsyncAPI and OpenAPI share this projection so an `:id`, a domain value or an
  optional field cannot mean one thing on the event side and another on the HTTP
  side. The `x-eh-os-contract-type` extension keeps the DSL type where JSON Schema
  itself collapses distinctions such as `:id` and `:string`.
  """

  alias EhOsContract.Model

  @doc "A closed object schema for `fields`, resolving domain values through `domain`."
  @spec object([map()], module() | map()) :: map()
  def object(fields, domain) do
    domain = Model.fetch(domain)
    values = Map.new(domain.values, &{&1.name, &1})

    %{
      "type" => "object",
      "properties" => Map.new(fields, &{to_string(&1.name), field(&1, values)}),
      "required" =>
        fields
        |> Enum.reject(&Map.get(&1, :optional, false))
        |> Enum.map(&to_string(&1.name))
        |> Enum.sort(),
      "additionalProperties" => false
    }
  end

  defp field(field, values) do
    field.type
    |> property(values)
    |> maybe_put("title", Map.get(field, :label))
    |> maybe_put("x-eh-os-contract-personal", Map.get(field, :personal))
    |> maybe_put("x-eh-os-contract-subject", Map.get(field, :subject))
    |> maybe_put("x-eh-os-contract-issued-by", Map.get(field, :issued_by))
  end

  defp property(type, values) do
    type
    |> base_property(values)
    |> Map.put("x-eh-os-contract-type", type_data(type))
  end

  defp base_property(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} -> object_fields(fields, values)
      %{type: inner} -> base_property(inner, values)
    end
  end

  defp base_property(type, _values) when type in [:id, :string, :decimal],
    do: %{"type" => "string"}

  defp base_property(:integer, _values), do: %{"type" => "integer"}
  defp base_property(:boolean, _values), do: %{"type" => "boolean"}
  defp base_property(:date, _values), do: %{"type" => "string", "format" => "date"}
  defp base_property(:timestamp, _values), do: %{"type" => "string", "format" => "date-time"}
  defp base_property({:id, _entity}, _values), do: %{"type" => "string"}

  defp base_property({:enum, members}, _values),
    do: %{"type" => "string", "enum" => Enum.map(members, &enum_name/1)}

  defp base_property({:list, inner}, values),
    do: %{"type" => "array", "items" => property(inner, values)}

  defp object_fields(fields, values) do
    %{
      "type" => "object",
      "properties" => Map.new(fields, &{to_string(&1.name), field(&1, values)}),
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
