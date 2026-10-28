defmodule EhOsContract.EctoTypes.Value do
  # #472: the Ecto type of a field typed by a domain value, in a read model's `Row`.
  #
  # A contract names its domain without a compile dependency, so its `Row` cannot know,
  # when it compiles, what a domain value is. This type keeps the domain's module and
  # the value's name, and reads the value from the domain the first time it casts,
  # loads or dumps. A value resting on a type is that type's column, through
  # `EhOsContract.EctoTypes.of/2`: a `:money` resting on `:integer` an integer, a domain
  # enum an `Ecto.Enum`. A value made of fields is a `jsonb` column, written in the
  # log's form and read back through `EhOsContract.Codec` as the map the engine hands a
  # consumer in an event: atom keys, a date a `Date`, an enum's member an atom. It is
  # never a struct, so a projection writes `event.address` as it is, and reads back
  # what it wrote.
  @moduledoc false

  use Ecto.ParameterizedType

  alias EhOsContract.{Codec, EctoTypes}

  @impl true
  def init(opts),
    do: %{domain: Keyword.fetch!(opts, :domain), value: Keyword.fetch!(opts, :value)}

  @impl true
  def type(params) do
    case resolved(params) do
      {:one, _fields, _values} -> :map
      {:many, _fields, _values} -> {:array, :map}
      {:type, type} -> Ecto.Type.type(type)
    end
  end

  # `nil` is `nil` whatever the value, and asks nothing of the domain: Ecto dumps a
  # field's default, `nil`, while the schema compiles, before the domain may have.
  @impl true
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, params) do
    case resolved(params) do
      {:type, type} -> Ecto.Type.cast(type, value)
      made_of -> read(made_of, value)
    end
  end

  @impl true
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, loader, params) do
    case resolved(params) do
      {:type, type} -> Ecto.Type.load(type, value, loader)
      made_of -> read(made_of, value)
    end
  end

  @impl true
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, dumper, params) do
    case resolved(params) do
      {:one, fields, values} -> write(fields, value, values)
      {:many, fields, values} -> each(value, &write(fields, &1, values))
      {:type, type} -> Ecto.Type.dump(type, value, dumper)
    end
  end

  @impl true
  def equal?(a, b, params) do
    case resolved(params) do
      {:type, type} -> Ecto.Type.equal?(type, a, b)
      _made_of -> a == b
    end
  end

  @impl true
  def embed_as(format, params) do
    case resolved(params) do
      {:type, type} -> Ecto.Type.embed_as(type, format)
      _made_of -> :self
    end
  end

  # A value made of fields, one or a list, as the engine holds it, or as the log and a
  # JSON caller write it: a map already of its types is taken as it is, anything else
  # is decoded.
  defp read({:one, fields, values}, value), do: one(fields, value, values)
  defp read({:many, fields, values}, value), do: each(value, &one(fields, &1, values))

  defp one(fields, value, values) when is_map(value) and not is_struct(value) do
    if Codec.problems(fields, value, values) == [] do
      {:ok, value}
    else
      case Codec.decode(fields, value, values) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _problems} -> :error
      end
    end
  end

  defp one(_fields, _value, _values), do: :error

  # In the log's form, as an event's payload holds it.
  defp write(fields, value, values) do
    if is_map(value) and not is_struct(value) and Codec.problems(fields, value, values) == [],
      do: {:ok, Codec.encode(fields, value, values)},
      else: :error
  end

  defp each(list, fun) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | done]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      :error -> :error
    end
  end

  defp each(_value, _fun), do: :error

  # The value read from the domain: the fields of one made of fields, or of a list of
  # them, through any alias, or the Ecto type of one resting on a type. A domain that is not compiled, or
  # that does not declare the value, is a defect the links check refuses at compile.
  defp resolved(%{domain: domain, value: value}) do
    values = Codec.values(domain)

    unless is_map_key(values, value) do
      raise ArgumentError, "#{inspect(domain)} declares no value #{inspect(value)}"
    end

    case EctoTypes.shape(value, values) do
      {cardinality, made_of} -> {cardinality, Map.fetch!(values, made_of).fields, values}
      :flat -> {:type, EctoTypes.of(value, values)}
    end
  end
end
