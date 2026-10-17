defmodule EhOsContract.SchemaLock do
  # Plan DD, V3 (#340): the fields of every event, by its type in the log and its
  # `schema_version`, as the log stores them, kept in a file of the host's project
  # (`eh_os_contract.lock`, beside `mix.lock`) so that a change to the fields of a version
  # some log already holds rows of cannot go unnoticed. `mix eh_os_contract.schema`
  # reads and writes the file; everything here works on maps.
  #
  # A field is recorded as a row holds it, as `EhOsContract.Codec` reads it: a built-in
  # type, an enum as its members' names, a list as what it holds, a domain value as its
  # shape — its inner type, or its own fields — and whether it may be absent, whether it
  # is sealed and whose key seals it. What no row holds is left out: labels, the names of
  # domain values and of what an `:id` refers to, invariants, the order of fields. So a
  # domain value renamed changes nothing, and one given another field changes every
  # event that holds it.
  #
  # Once recorded, a version's fields do not change: a row written with them would not
  # read. A version newer than the declaration is refused too, since its rows would not
  # read either. An event no contract declares any more stays, since logs may still hold
  # its rows, until it is forgotten, which is the person's statement that none do.
  @moduledoc false

  alias EhOsContract.Codec
  alias EhOsContract.Model

  @typedoc "A field as a row holds it: its stored type, then what is set of the rest."
  @type field :: keyword()

  @typedoc "The lock: each event type's fields, by `schema_version`, sorted by name."
  @type t :: %{String.t() => %{pos_integer() => [{atom(), field()}]}}

  @header """
  # The fields of every event, by its type in the log and its schema_version, as the log
  # stores them. Written by `mix eh_os_contract.schema` and checked by its `--check`: a
  # version's fields do not change once recorded, since rows written with them would not
  # read. Commit this file.
  """

  @doc false
  # The entry of each event of `contracts` at the version it declares.
  @spec declared([module() | Model.t()]) :: t()
  def declared(contracts) do
    for contract <- contracts,
        model = Model.fetch(contract),
        values = Codec.values(Map.get(model, :domain)),
        event <- model.events,
        reduce: %{} do
      lock -> Map.put(lock, event.type, %{event.schema_version => fields(event.fields, values)})
    end
  end

  @doc false
  # `fields` as a row holds them, with the domain's `values`, sorted by name.
  @spec fields([map()], Codec.values()) :: [{atom(), field()}]
  def fields(fields, values) do
    fields
    |> Enum.map(&{&1.name, field(&1, values)})
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp field(field, values) do
    [type: stored(field.type, values)] ++
      if(Map.get(field, :optional, false), do: [optional: true], else: []) ++
      set(:personal, Map.get(field, :personal)) ++ set(:subject, Map.get(field, :subject))
  end

  defp set(_key, nil), do: []
  defp set(key, value), do: [{key, value}]

  defp stored({:id, _referent}, _values), do: :id
  defp stored({:list, inner}, values), do: {:list, stored(inner, values)}

  defp stored({:enum, members}, _values),
    do: {:enum, members |> Enum.map(&member/1) |> Enum.sort()}

  defp stored(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} -> {:fields, fields(fields, values)}
      %{type: inner} -> stored(inner, values)
    end
  end

  defp stored(type, _values), do: type

  defp member({name, _label}), do: name
  defp member(name), do: name

  @doc false
  # `lock` with each version `declared` that it lacks; refused, with a sentence a problem,
  # when a version it holds differs from the declaration or is newer than it.
  @spec merge(t(), t()) :: {:ok, t()} | {:error, [String.t()]}
  def merge(lock, declared) do
    problems =
      for {type, versions} <- Enum.sort(declared),
          {version, fields} <- versions,
          problem <- problems(type, version, fields, Map.get(lock, type, %{})),
          do: problem

    if problems == [] do
      {:ok, Map.merge(lock, declared, fn _type, kept, current -> Map.merge(kept, current) end)}
    else
      {:error, problems}
    end
  end

  defp problems(type, version, fields, kept) do
    changed =
      case Map.fetch(kept, version) do
        {:ok, ^fields} ->
          []

        {:ok, recorded} ->
          [
            "#{type} at schema_version #{version}: " <>
              Enum.join(changes(recorded, fields), "; ") <>
              ". A row written at version #{version} holds the fields the lock records, and " <>
              "is read with the declaration's: raise its schema_version with a step " <>
              "`upcast from: #{version}` that says how an old row reads, or, if no log holds " <>
              "rows of it, run `mix eh_os_contract.schema --forget #{type}`"
          ]

        :error ->
          []
      end

    newer =
      for later <- kept |> Map.keys() |> Enum.sort(), later > version do
        "#{type}: the lock records schema_version #{later}, and its contract declares " <>
          "#{version}, so rows written at #{later} would not read. Declare version #{later} " <>
          "again, or, if no log holds rows of it, run " <>
          "`mix eh_os_contract.schema --forget #{type}`"
      end

    changed ++ newer
  end

  @doc false
  # What changed from `recorded` to `current`, a sentence a field, in the fields' order.
  @spec changes([{atom(), field()}], [{atom(), field()}]) :: [String.t()]
  def changes(recorded, current) do
    names = (Keyword.keys(recorded) ++ Keyword.keys(current)) |> Enum.uniq() |> Enum.sort()

    for name <- names,
        {was, is} = {Keyword.get(recorded, name), Keyword.get(current, name)},
        was != is do
      cond do
        was == nil -> "#{name} was added, #{inspect(is)}"
        is == nil -> "#{name} was removed, #{inspect(was)}"
        true -> "#{name} was #{inspect(was)} and is #{inspect(is)}"
      end
    end
  end

  @doc false
  # `lock` without `type`, every version of it.
  @spec forget(t(), String.t()) :: t()
  def forget(lock, type), do: Map.delete(lock, type)

  @doc false
  # The lock as the file holds it: an Elixir literal, one field a line, sorted.
  @spec encode(t()) :: String.t()
  def encode(lock) do
    types =
      for {type, versions} <- Enum.sort(lock) do
        entries =
          for {version, fields} <- Enum.sort(versions) do
            lines = Enum.map_join(fields, ",\n", fn {name, field} -> pair(name, field) end)
            "#{version} => [\n#{lines}\n]"
          end

        "#{inspect(type)} => %{\n#{Enum.join(entries, ",\n")}\n}"
      end

    body = if types == [], do: "%{}", else: "%{\n#{Enum.join(types, ",\n")}\n}"
    @header <> IO.iodata_to_binary(Code.format_string!(body)) <> "\n"
  end

  defp pair(name, field),
    do:
      "#{Macro.inspect_atom(:key, name)} " <>
        inspect(field, limit: :infinity, printable_limit: :infinity)

  @doc false
  # The lock in `text`, read as a literal and never evaluated as code; refused, with why,
  # when it is not one or not a lock's shape.
  @spec decode(String.t()) :: {:ok, t()} | {:error, String.t()}
  def decode(text) do
    with {:ok, quoted} <- quoted(text),
         {:ok, lock} <- literal(quoted),
         true <- lock?(lock) || {:error, "it is not a map of event types to versions"} do
      {:ok, lock}
    end
  end

  # The value `quoted` writes, built here from maps, lists, tuples, atoms, numbers and
  # strings alone. `Code.eval_quoted/1` is not asked even for a literal: a struct is one,
  # and evaluating it calls its module.
  defp literal(quoted) do
    {:ok, value(quoted)}
  catch
    :not_literal -> {:error, "it is not an Elixir literal"}
  end

  defp value(term) when is_atom(term) or is_number(term) or is_binary(term), do: term
  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value({:%{}, _meta, pairs}) when is_list(pairs), do: Map.new(pairs, &pair_value/1)

  defp value({:{}, _meta, elements}) when is_list(elements),
    do: elements |> value() |> List.to_tuple()

  defp value({:__block__, _meta, [one]}), do: value(one)
  defp value({left, right}), do: {value(left), value(right)}
  defp value(_code), do: throw(:not_literal)

  defp pair_value({key, value}), do: {value(key), value(value)}
  defp pair_value(_code), do: throw(:not_literal)

  defp quoted(text) do
    case Code.string_to_quoted(text) do
      {:ok, quoted} ->
        {:ok, quoted}

      {:error, {location, message, token}} ->
        line = if is_list(location), do: Keyword.get(location, :line), else: location
        {:error, "line #{line}: #{format_error(message)}#{token}"}
    end
  end

  defp format_error({prefix, suffix}), do: "#{prefix}#{suffix}"
  defp format_error(message), do: message

  # A map written with a `__struct__` key is a struct to `Enum`, and a lock is none.
  defp lock?(lock) do
    is_map(lock) and not is_struct(lock) and
      Enum.all?(lock, fn {type, versions} ->
        is_binary(type) and is_map(versions) and not is_struct(versions) and
          Enum.all?(versions, fn {version, fields} ->
            is_integer(version) and version > 0 and fields?(fields)
          end)
      end)
  end

  defp fields?(fields),
    do:
      is_list(fields) and
        Enum.all?(fields, &match?({name, [{:type, _} | _]} when is_atom(name), &1))
end
