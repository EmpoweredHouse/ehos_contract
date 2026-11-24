defmodule EhosContract.EctoTypes.Value do
  # #472: the Ecto type of a field typed by a domain value, in a read model's `Row`.
  #
  # A contract names its domain without a compile dependency, so its `Row` cannot know,
  # when it compiles, what a domain value is. This type keeps the domain's module and
  # the value's name, and reads the value from the domain the first time it casts,
  # loads or dumps, kept until the domain is recompiled. A value resting on a type is
  # that type's column, through
  # `EhosContract.EctoTypes.of/2`: a `:money` resting on `:integer` an integer, a domain
  # enum an `Ecto.Enum`. A value made of fields is a `jsonb` column, and so is a list of
  # them, one column holding the list as `embeds_many` would; each is written in the
  # log's form and read back through `EhosContract.Codec` as the value's struct, the one
  # the engine hands a consumer in an event (#486), so a projection writes
  # `event.address` as it is, and reads back what it wrote.
  @moduledoc false

  use Ecto.ParameterizedType

  alias EhosContract.{Codec, EctoTypes}

  @impl true
  def init(opts) do
    %{
      domain: Keyword.fetch!(opts, :domain),
      value: Keyword.fetch!(opts, :value),
      list: Keyword.get(opts, :list, false)
    }
  end

  @impl true
  def type(params) do
    case resolved(params) do
      {:type, type} -> Ecto.Type.type(type)
      _made_of -> :map
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
      {:one, declared, values} -> write(declared, value, values)
      {:many, declared, values} -> each(value, &write(declared, &1, values))
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

  # A value made of fields, one or a list: the value's struct as the engine holds it,
  # taken as it is, or the string-keyed map the column and a JSON caller write, decoded
  # into it. A map keyed by atoms is neither, and is refused, as dispatch refuses one.
  defp read({:one, declared, values}, value), do: one(declared, value, values)
  defp read({:many, declared, values}, value), do: each(value, &one(declared, &1, values))

  defp one(%{fields: fields} = declared, value, values) when is_map(value) do
    cond do
      is_struct(value, declared.struct) ->
        if Codec.problems(fields, value, values) == [], do: {:ok, value}, else: :error

      not is_struct(value) and Enum.all?(Map.keys(value), &is_binary/1) ->
        case Codec.decode(fields, value, values) do
          {:ok, decoded} -> {:ok, Codec.built(declared, decoded)}
          {:error, _problems} -> :error
        end

      true ->
        :error
    end
  end

  defp one(_declared, _value, _values), do: :error

  # In the log's form, as an event's payload holds it.
  defp write(%{fields: fields} = declared, value, values) do
    if is_struct(value, declared.struct) and Codec.problems(fields, value, values) == [],
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
  # them, through any alias, or the Ecto type of one resting on a type. A domain that is
  # not compiled, or that does not declare the value, is a defect the links check
  # refuses at compile.
  #
  # A personal field of a value made of fields is read as optional: an erasure leaves
  # it `nil` in the row (`EhosContract.Erased` is written as `nil`, as a query's answer
  # gives it over HTTP), and a row that could not be read back would fail every query
  # over its read model.
  defp resolved(%{domain: domain, value: value, list: list}) do
    # Asked for every field of every row, so read once per compiled domain: the key
    # carries the domain's digest, and a recompiled domain is read again.
    digest = if Code.ensure_loaded?(domain), do: domain.module_info(:md5)
    key = {__MODULE__, domain, value, list}

    case :persistent_term.get(key, nil) do
      {^digest, resolved} when digest != nil ->
        resolved

      _stale_or_none ->
        resolved = resolve(domain, value, list)
        if digest, do: :persistent_term.put(key, {digest, resolved})
        resolved
    end
  end

  defp resolve(domain, value, list) do
    values = Codec.values(domain)

    unless is_map_key(values, value) do
      raise ArgumentError, "#{inspect(domain)} declares no value #{inspect(value)}"
    end

    case {EctoTypes.shape(value, values), list} do
      {{:one, made_of}, list} ->
        made_of(if(list, do: :many, else: :one), made_of, values)

      {{:many, made_of}, false} ->
        made_of(:many, made_of, values)

      # A list of a value that is a list itself: rows of it are lists of maps, kept as
      # the column holds them.
      {{:many, _made_of}, true} ->
        {:type, {:array, :map}}

      {:flat, list} ->
        type = EctoTypes.of(value, values)
        {:type, if(list, do: {:array, type}, else: type)}
    end
  end

  defp made_of(cardinality, value, values) do
    values = Map.new(values, fn {name, v} -> {name, Map.update(v, :fields, [], &erasable/1)} end)
    {cardinality, Map.fetch!(values, value), values}
  end

  defp erasable(fields),
    do: Enum.map(fields, &if(Map.get(&1, :personal), do: Map.put(&1, :optional, true), else: &1))
end
