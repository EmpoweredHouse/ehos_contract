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
  # A recorded version's fields change in place only as old rows still read (plan DD, V4,
  # #346): a field added as optional, a field removed, required made optional, an enum
  # given members, an integer made a decimal, and the same inside a list or a domain
  # value. Any other change raises the version, and the step from the version before,
  # `upcast from: n`, covers each change: a rename carries a field to its new name, a
  # default gives a new required field its value, and a function covers everything, since
  # the engine cannot see what it does. No step carries a field that turns personal or
  # stops being, or is sealed by another identifier, since a seal opens only under what
  # sealed it; nor a field the log tags rows with that the version before did not tag
  # under that name, since rows written before carry no such tag. Those are new events.
  #
  # A version newer than the declaration is refused too, and so is an event no contract
  # declares any more, since their rows would not read either. Forgetting is the person's
  # statement that no log holds rows of what is forgotten.
  @moduledoc false

  alias EhOsContract.Codec
  alias EhOsContract.Model

  @typedoc "A field as a row holds it: its stored type, then what is set of the rest."
  @type field :: keyword()

  @typedoc "What a step from one version to the next says of its fields."
  @type step :: :function | %{rename: %{atom() => atom()}, default: [atom()]}

  @typedoc "The lock: each event type's fields, by `schema_version`, sorted by name."
  @type t :: %{String.t() => %{pos_integer() => [{atom(), field()}]}}

  # The order `field/2` writes a field's keys in.
  @keys %{type: 0, optional: 1, personal: 2, subject: 3}

  @header """
  # The fields of every event, by its type in the log and its schema_version, as the log
  # stores them. Written by `mix eh_os_contract.schema` and checked by its `--check`: a
  # version's fields do not change once recorded, since rows written with them are read
  # with today's declaration. Commit this file.
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
  # Each event's steps, by its type and the version each reads: what it renames and gives a
  # default to, or `:function`.
  @spec steps([module() | Model.t()]) :: %{String.t() => %{pos_integer() => step()}}
  def steps(contracts) do
    for contract <- contracts,
        model = Model.fetch(contract),
        event <- model.events,
        into: %{},
        do: {event.type, Map.new(Map.get(event, :upcasts, []), &{&1.from, step(&1)})}
  end

  defp step(%{function: _function}), do: :function
  defp step(step), do: %{rename: Map.new(step.rename), default: Map.keys(step.default)}

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
  # `lock` with each version `declared` that it lacks, and each it holds with fields old
  # rows still read; refused, with a sentence a problem, when a version it holds differs
  # otherwise, is newer than the declaration, or is an event nothing declares, or when a
  # step of `steps` does not cover what changed from its version to the next.
  @spec merge(t(), t(), %{String.t() => %{pos_integer() => step()}}) ::
          {:ok, t()} | {:error, [String.t()]}
  def merge(lock, declared, steps \\ %{}) do
    problems =
      for {type, versions} <- Enum.sort(declared),
          {version, fields} <- versions,
          problem <- problems(type, version, fields, Map.get(lock, type, %{})),
          do: problem

    undeclared =
      for {type, versions} <- Enum.sort(lock), not Map.has_key?(declared, type) do
        "#{type}: the lock records it at schema_version " <>
          Enum.map_join(versions |> Map.keys() |> Enum.sort(), ", ", &to_string/1) <>
          ", and no contract of the applications read (`applications:`, less `exclude:`) " <>
          "declares it, so its rows would not read. Declare it again, or, if no log holds rows " <>
          "of it, run `mix eh_os_contract.schema --forget #{type}`"
      end

    merged = Map.merge(lock, declared, fn _type, kept, current -> Map.merge(kept, current) end)

    uncovered =
      for {type, current} <- Enum.sort(declared),
          [version] = Map.keys(current),
          versions = Map.fetch!(merged, type),
          from <- versions |> Map.keys() |> Enum.sort(),
          from < version and Map.has_key?(versions, from + 1),
          problem <-
            across(type, from, versions[from], versions[from + 1], steps[type][from]),
          do: problem

    case problems ++ undeclared ++ uncovered do
      [] -> {:ok, merged}
      problems -> {:error, problems}
    end
  end

  # What a step from `from` leaves uncovered of the change to the next version's fields.
  # A step the declaration lacks, which the compiler refuses (U1), is not judged here.
  defp across(_type, _from, _was, _is, nil), do: []

  defp across(type, from, was, is, step) do
    for {kind, _name, why} <- uncovered(was, is, step, true) do
      case kind do
        :never ->
          "#{type} at schema_version #{from + 1}: #{why}. No step carries that across: " <>
            "declare a new event instead"

        :step ->
          "#{type}, `upcast from: #{from}`: #{why}"
      end
    end
  end

  defp problems(type, version, fields, kept) do
    changed =
      case Map.fetch(kept, version) do
        {:ok, ^fields} ->
          []

        {:ok, recorded} ->
          in_place(type, version, recorded, fields)

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

  # A recorded version's fields changed in place: refused where an old row would not read.
  defp in_place(type, version, recorded, fields) do
    case uncovered(recorded, fields, %{rename: %{}, default: []}, true) do
      [] ->
        []

      problems ->
        whys = Enum.map_join(problems, "; ", &elem(&1, 2))

        if Enum.any?(problems, &(elem(&1, 0) == :never)) do
          [
            "#{type} at schema_version #{version}: #{whys}. No step carries that across: " <>
              "declare a new event instead, or, if no log holds rows of it, run " <>
              "`mix eh_os_contract.schema --forget #{type}`"
          ]
        else
          [
            "#{type} at schema_version #{version}: #{whys}. A row written at version " <>
              "#{version} holds the fields the lock records, and would not read: raise its " <>
              "schema_version with a step `upcast from: #{version}` that covers the change, " <>
              "or, if no log holds rows of it, run " <>
              "`mix eh_os_contract.schema --forget #{type}`"
          ]
        end
    end
  end

  # Each change from `was` to `is`, the fields of two versions, that `step` does not cover,
  # as `{:never | :step, name, why}`: `:never` where no step could. `tagged` says whether
  # these are an event's own fields, which the log tags rows by, or a domain value's.
  defp uncovered(was, is, step, tagged) do
    function = step == :function
    rename = if function, do: %{}, else: step.rename
    defaults = if function, do: [], else: step.default
    carried = Map.new(was, fn {name, field} -> {Map.get(rename, name, name), field} end)

    names = (Map.keys(carried) ++ Keyword.keys(is)) |> Enum.uniq() |> Enum.sort()

    for name <- names,
        problem =
          uncovered_field(
            name,
            Map.get(carried, name),
            Keyword.get(is, name),
            tagged and tags?(Keyword.get(was, name)),
            {function, name in defaults, tagged}
          ),
        problem != nil,
        do: problem
  end

  defp uncovered_field(_name, _was, nil, _tagged_before, _how), do: nil

  defp uncovered_field(name, was, is, tagged_before, {function, defaulted, tagged}) do
    cond do
      was != nil and sealing(was) != sealing(is) ->
        {:never, name,
         "#{name} was #{inspect(was)} and is #{inspect(is)}, and whether a field is " <>
           "personal, and the identifier that seals it, do not change"}

      tagged and tags?(is) and not tagged_before ->
        {:never, name,
         "#{name}, #{inspect(is)}, is a field the log tags rows with, and the version " <>
           "before did not tag rows with it, so rows written before carry no such tag"}

      was == nil and (Keyword.get(is, :optional, false) or function or defaulted) ->
        nil

      was == nil ->
        {:step, name,
         "#{name} was added, #{inspect(is)}, and is required: give it a `default:`, or make " <>
           "it optional"}

      function or compatible?(was, is) ->
        nil

      true ->
        {:step, name,
         "#{name} was #{inspect(was)} and is #{inspect(is)}, which a rename and a default " <>
           "cannot carry: write the step as a function"}
    end
  end

  defp sealing(field), do: {Keyword.get(field, :personal), Keyword.get(field, :subject)}

  # A field the log tags each row with: a required, non-personal identifier or day
  # (`EhOsContract.Key`), its domain value resolved to what it rests on.
  defp tags?(nil), do: false

  defp tags?(field),
    do:
      Keyword.get(field, :type) in [:id, :date, :timestamp] and
        not Keyword.get(field, :optional, false) and Keyword.get(field, :personal) == nil

  # Whether a row written with `was` reads with `is`: what `EhOsContract.Codec` decodes.
  defp compatible?(was, is) do
    sealing(was) == sealing(is) and
      not (Keyword.get(was, :optional, false) and not Keyword.get(is, :optional, false)) and
      readable?(Keyword.fetch!(was, :type), Keyword.fetch!(is, :type))
  end

  defp readable?(same, same), do: true
  defp readable?(:integer, :decimal), do: true
  defp readable?({:enum, was}, {:enum, is}), do: was -- is == []
  defp readable?({:list, was}, {:list, is}), do: readable?(was, is)

  defp readable?({:fields, was}, {:fields, is}),
    do: uncovered(was, is, %{rename: %{}, default: []}, false) == []

  defp readable?(_was, _is), do: false

  @doc false
  # `lock` without the versions of `type` from `from` up, and without `type` once none is
  # left.
  @spec forget(t(), String.t(), pos_integer()) :: t()
  def forget(lock, type, from \\ 1) do
    kept =
      for {version, fields} <- Map.get(lock, type, %{}),
          version < from,
          into: %{},
          do: {version, fields}

    if kept == %{}, do: Map.delete(lock, type), else: Map.put(lock, type, kept)
  end

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
      {:ok, Map.new(lock, fn {type, versions} -> {type, Map.new(versions, &normal/1)} end)}
    end
  end

  # The value `quoted` writes, built here from maps, lists, tuples, atoms, numbers and
  # strings alone. `Code.eval_quoted/1` is not asked even for a literal: a struct is one,
  # and evaluating it calls its module.
  defp literal(quoted) do
    {:ok, value(quoted)}
  catch
    :not_literal -> {:error, "it is not an Elixir literal"}
    {:twice, :key} -> {:error, "a map in it gives a key twice"}
  end

  defp value(term) when is_atom(term) or is_number(term) or is_binary(term), do: term
  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  # A key given twice, as a merge resolved by hand leaves both sides, would keep one side.
  defp value({:%{}, _meta, pairs}) when is_list(pairs) do
    pairs = Enum.map(pairs, &pair_value/1)
    map = Map.new(pairs)
    if map_size(map) == length(pairs), do: map, else: throw({:twice, :key})
  end

  defp value({:{}, _meta, elements}) when is_list(elements),
    do: elements |> value() |> List.to_tuple()

  defp value({:__block__, _meta, [one]}), do: value(one)
  defp value({left, right}), do: {value(left), value(right)}
  defp value(_code), do: throw(:not_literal)

  defp pair_value({key, value}), do: {value(key), value(value)}
  defp pair_value(_code), do: throw(:not_literal)

  defp quoted(text) do
    if String.valid?(text), do: parsed(text), else: {:error, "it is not UTF-8 text"}
  end

  defp parsed(text) do
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
      Keyword.keyword?(fields) and fields == Enum.uniq_by(fields, &elem(&1, 0)) and
        Enum.all?(fields, fn {_name, field} ->
          Keyword.keyword?(field) and Keyword.has_key?(field, :type)
        end)

  # A version as `encode/1` writes it, whatever order a hand resolving a merge left its
  # fields and their keys in, so that only a change of what they say is one.
  defp normal({version, fields}), do: {version, normal_fields(fields)}

  defp normal_fields(fields) do
    fields
    |> Enum.map(fn {name, field} -> {name, normal_field(field)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normal_field(field) do
    field
    |> Enum.map(fn
      {:type, type} -> {:type, normal_type(type)}
      other -> other
    end)
    |> Enum.sort_by(fn {key, _value} -> {Map.get(@keys, key, map_size(@keys)), key} end)
  end

  defp normal_type({:list, inner}), do: {:list, normal_type(inner)}
  defp normal_type({:enum, members}) when is_list(members), do: {:enum, Enum.sort(members)}

  defp normal_type({:fields, fields} = type),
    do: if(fields?(fields), do: {:fields, normal_fields(fields)}, else: type)

  defp normal_type(type), do: type
end
