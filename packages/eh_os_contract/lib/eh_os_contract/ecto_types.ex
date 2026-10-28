defmodule EhOsContract.EctoTypes do
  # #472: a declared field's Ecto type, written once for every changeset and schema the
  # engine builds from a declaration, so a form and a read model cannot read the same
  # field as two types.
  @moduledoc false

  @typedoc "The values a domain declares, by name: `EhOsContract.Codec.values/1`."
  @type values :: %{optional(atom()) => map()}

  @typedoc """
  Whether a type holds a domain value with fields, one (`{:one, value}`) or a list of them
  (`{:many, value}`), or anything else (`:flat`).
  """
  @type shape :: {:one | :many, atom()} | :flat

  @doc """
  Whether `type` holds a domain value with fields, one or a list of them, or anything else.
  A value that is another value's name is followed to the type it names.
  """
  @spec shape(term(), values()) :: shape()
  def shape({:list, inner}, values) do
    case shape(inner, values) do
      {:one, value} -> {:many, value}
      _other -> :flat
    end
  end

  def shape(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} -> {:one, type}
      %{type: inner} -> shape(inner, values)
    end
  end

  def shape(_type, _values), do: :flat

  @doc """
  The Ecto type of a declared type: an `:id` is text, a `:timestamp` keeps microseconds
  and writes a time of any precision (`EhOsContract.EctoTypes.Timestamp`),
  an enum is an `Ecto.Enum` of its members, a domain value is the type it names, and a
  domain value with fields is a `:map`.
  """
  @spec of(term(), values()) :: Ecto.Type.t()
  def of(type, _values) when type in [:string, :id], do: :string
  def of({:id, _entity}, _values), do: :string
  def of(:timestamp, _values), do: EhOsContract.EctoTypes.Timestamp
  def of(type, _values) when type in [:integer, :boolean, :decimal, :date], do: type

  def of({:enum, members}, _values),
    do: Ecto.ParameterizedType.init(Ecto.Enum, values: members(members))

  def of({:list, inner}, values), do: {:array, of(inner, values)}

  def of(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} -> :map
      %{type: inner} -> of(inner, values)
    end
  end

  def of(_type, _values), do: :any

  @doc "An enum's members, in the order declared, without their labels."
  @spec members([atom() | {atom(), String.t()}]) :: [atom()]
  def members(members),
    do:
      Enum.map(members, fn
        {name, _label} -> name
        name -> name
      end)
end
