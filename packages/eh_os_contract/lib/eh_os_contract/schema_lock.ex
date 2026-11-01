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
  # given members, an integer made a decimal, an identifier made a string, and the same
  # inside a list or a domain value. A field removed stays, marked `removed: true`, since
  # old rows still hold it and rows written since do not. Any other change raises the
  # version, and the steps from each recorded version to the declared one cover each
  # change, read as `EhOsContract.Upcast` reads an old row: a rename carries a field to
  # its new name, a default gives a new required field its value where a row lacks it,
  # and a function covers everything a step could carry, since the engine cannot see what
  # it does. No step carries a field that turns personal or stops being, or is sealed by
  # another identifier; a personal field whose type changes otherwise than in place (an
  # integer made a decimal still reads, sealed or not), or a value holding personal
  # data whose shape changes; a required personal field, at any depth, old rows may lack; or
  # an identifier that seals a field given another subject: a seal opens only under what
  # sealed it, and no step converts, moves or makes one. Nor a field the log tags rows
  # with that the version before did not tag under that name, since rows written before
  # carry no such tag. Those are new events.
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

  @carry "which a rename and a default cannot carry: write the step as a function"
  @sealed "it holds personal data, sealed where it was written, and no step converts a " <>
            "sealed value or moves its seal"
  @unfilled "it is personal, or holds a required personal field, and old rows may lack it, " <>
              "and no step fills it: a default would be clear text where a seal belongs, and " <>
              "a function makes no seal"
  @refill "rows written since it was removed lack it: give it a `default:`, or make it optional"

  # The order `field/2` writes a field's keys in.
  @keys %{type: 0, optional: 1, personal: 2, subject: 3, removed: 4}

  @header """
  # The fields of every event, by its type in the log and its schema_version, as the log
  # stores them. Written by `mix eh_os_contract.schema` and checked by its `--check`: a
  # version's fields change in place only where rows written with them still read with
  # today's declaration. Commit this file.
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
  # otherwise, is newer than the declaration, or is an event nothing declares, or when the
  # steps of `steps` do not cover what changed between two versions it records.
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

    merged =
      Map.merge(lock, declared, fn _type, kept, current ->
        Map.merge(kept, current, fn _version, recorded, fields -> combine(recorded, fields) end)
      end)

    uncovered =
      for {type, current} <- Enum.sort(declared),
          [version] = Map.keys(current),
          problem <- across(type, Map.fetch!(merged, type), version, Map.get(steps, type, %{})),
          do: problem

    case problems ++ undeclared ++ uncovered do
      [] -> {:ok, merged}
      problems -> {:error, problems}
    end
  end

  # A recorded version's fields with a change old rows still read: the declaration's, and a
  # field it no longer has kept, marked `removed: true`, since old rows still hold it, and
  # rows written since do not. A field later declared under that name again is held to
  # what both hold.
  defp combine(recorded, fields) do
    names = (Keyword.keys(recorded) ++ Keyword.keys(fields)) |> Enum.uniq() |> Enum.sort()

    for name <- names do
      case {Keyword.get(recorded, name), Keyword.get(fields, name)} do
        {was, nil} ->
          {name, was |> Keyword.put(:removed, true) |> normal_field()}

        {nil, is} ->
          {name, is}

        {was, is} ->
          {name, Keyword.put(is, :type, combine_type(was[:type], is[:type]))}
      end
    end
  end

  defp combine_type({:fields, was}, {:fields, is}), do: {:fields, combine(was, is)}
  defp combine_type({:list, was}, {:list, is}), do: {:list, combine_type(was, is)}
  defp combine_type(_was, is), do: is

  # Each earlier version the lock records, read as the declared one through the steps
  # between them, as the engine reads an old row: a change no step covers, once a field,
  # where no step could carry it first, then at the closest version that shows it. A
  # function covers every change a step could carry, and leaves only what none could; a
  # chain missing a step, which the compiler refuses (U1), is not judged.
  defp across(type, versions, to, steps) do
    found =
      for from <- versions |> Map.keys() |> Enum.sort(:desc),
          from < to,
          chain = chain(steps, from, to),
          chain != nil,
          {kind, name, why} <- uncovered(versions[from], versions[to], chain, true),
          do: {name, from, kind, why}

    found
    |> Enum.sort_by(fn {name, from, kind, _why} -> {name, kind != :never, -from} end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {_name, from, kind, why} ->
      case kind do
        :never ->
          "#{type} at schema_version #{to}: #{why}. No step carries that across: declare a " <>
            "new event instead"

        :step ->
          "#{type}, from schema_version #{from} to #{to} (#{named_steps(from, to)}): #{why}"
      end
    end)
  end

  defp named_steps(from, to),
    do: Enum.map_join(from..(to - 1)//1, ", ", &"`upcast from: #{&1}`")

  # The steps from `from` to `to`, in order; nil when one is missing.
  defp chain(steps, from, to) do
    Enum.reduce_while(from..(to - 1)//1, [], fn version, chain ->
      case Map.get(steps, version) do
        nil -> {:halt, nil}
        step -> {:cont, chain ++ [{version, step}]}
      end
    end)
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
    {never, step} =
      recorded |> uncovered(fields, [], true) |> Enum.split_with(&(elem(&1, 0) == :never))

    forget = "or, if no log holds rows of it, run `mix eh_os_contract.schema --forget #{type}`"

    for {problems, advice} <- [
          {never, "No step carries that across: declare a new event instead, " <> forget},
          {step,
           "A row written at version #{version} holds the fields the lock records, and would " <>
             "not read: raise its schema_version with a step `upcast from: #{version}` that " <>
             "covers the change, " <> forget}
        ],
        problems != [] do
      "#{type} at schema_version #{version}: " <>
        Enum.map_join(problems, "; ", &elem(&1, 2)) <> ". " <> advice
    end
  end

  # Each change from `was` to `is`, the fields of two versions, that `chain`, the steps
  # between them, does not cover, as `{:never | :step, name, why}`: `:never` where no step
  # could. `tagged` says whether these are an event's own fields, which the log tags rows
  # by, or a domain value's.
  defp uncovered(was, is, chain, tagged) do
    function = Enum.any?(chain, &(elem(&1, 1) == :function))
    declared = for {from, %{} = step} <- chain, do: {from, step}
    carried = Enum.reduce(declared, Map.new(was), fn {_from, step}, acc -> carry(acc, step) end)
    defaults = defaulted(declared)

    sealers =
      was |> Enum.map(fn {_name, field} -> Keyword.get(field, :personal) end) |> MapSet.new()

    # A field the version no longer declares, kept for what old rows hold, is not read.
    is = Enum.reject(is, fn {_name, field} -> Keyword.get(field, :removed, false) end)
    names = (Map.keys(carried) ++ Keyword.keys(is)) |> Enum.uniq() |> Enum.sort()

    for name <- names,
        problem =
          uncovered_field(name, Map.get(carried, name), Keyword.get(is, name), %{
            defaulted: MapSet.member?(defaults, name),
            sealer: MapSet.member?(sealers, name),
            tagged: tagged,
            tagged_before: tagged and tags?(Keyword.get(was, name))
          }),
        problem != nil,
        # A function covers what a step could carry; its renames are its own, so a field
        # is judged by its name.
        not function or elem(problem, 0) == :never,
        do: problem
  end

  # A step's renames, as `EhOsContract.Upcast` applies them: the old names leave, and each
  # takes its new name, over a field the version already held there.
  defp carry(fields, %{rename: rename}) do
    moves = for {old, new} <- rename, Map.has_key?(fields, old), do: {old, new}

    Enum.reduce(moves, Map.drop(fields, Enum.map(moves, &elem(&1, 0))), fn {old, new}, acc ->
      Map.put(acc, new, Map.fetch!(fields, old))
    end)
  end

  # The names a default of the chain fills, as the last version names them: each carried
  # through the renames of the steps after it. A name a later step gives the field, which a
  # step may write its default under (U2), is carried as itself.
  defp defaulted(chain) do
    for {{_from, step}, i} <- Enum.with_index(chain),
        name <- step.default,
        later = Enum.drop(chain, i + 1),
        into: MapSet.new(),
        do: Enum.reduce(later, name, fn {_from, s}, n -> Map.get(s.rename, n, n) end)
  end

  defp uncovered_field(_name, _was, nil, _how), do: nil

  defp uncovered_field(name, nil, is, how) do
    cond do
      how.tagged and tags?(is) ->
        {:never, name, untagged(name, is)}

      not Keyword.get(is, :optional, false) and seals?(is) ->
        {:never, name, "#{name} was added, #{inspect(is)}: " <> @unfilled}

      Keyword.get(is, :optional, false) or how.defaulted ->
        nil

      true ->
        {:step, name,
         "#{name} was added, #{inspect(is)}, and is required: give it a `default:`, or make " <>
           "it optional"}
    end
  end

  defp uncovered_field(name, was, is, how) do
    case reading(was, is, how) do
      :ok -> nil
      :default -> {:step, name, "#{name} was #{inspect(was)} and is #{inspect(is)}: " <> @refill}
      {:never, why} -> {:never, name, "#{name} was #{inspect(was)} and is #{inspect(is)}: #{why}"}
      :step -> {:step, name, "#{name} was #{inspect(was)} and is #{inspect(is)}, " <> @carry}
    end
  end

  # Whether a row holding `was` reads as `is`: `:ok`, `:step` where only a step by a
  # function carries it, or `{:never, why}` where none does.
  defp reading(was, is, how) do
    cond do
      Keyword.get(was, :personal) != Keyword.get(is, :personal) ->
        {:never,
         "whether a field is personal, and the identifier that seals it, do not change, " <>
           "since a seal opens only under what sealed it"}

      how.sealer and Keyword.get(was, :subject) != Keyword.get(is, :subject) ->
        {:never,
         "the subject of an identifier that seals another field does not change, since its " <>
           "seals open only under the subject they were sealed for"}

      how.tagged and tags?(is) and not how.tagged_before ->
        {:never, untagged_why()}

      true ->
        read = readable(Keyword.fetch!(was, :type), Keyword.fetch!(is, :type))
        required = not Keyword.get(is, :optional, false)

        cond do
          match?({:never, _why}, read) ->
            read

          read == :step and Keyword.get(was, :personal) != nil ->
            {:never, @sealed}

          # No step fills a personal field an old row lacks: a default would be clear text
          # (U3), and a function makes no seal.
          required and seals?(is) and
              (Keyword.get(was, :optional, false) or Keyword.get(was, :removed, false)) ->
            {:never, @unfilled}

          # An optional field's old rows hold an explicit nil, which a default does not fill.
          required and Keyword.get(was, :optional, false) ->
            :step

          required and Keyword.get(was, :removed, false) and not how.defaulted ->
            if read == :ok, do: :default, else: read

          true ->
            read
        end
    end
  end

  defp personal_inside?(field), do: personal_type?(Keyword.fetch!(field, :type))

  # Whether a row holding `field` holds a seal however it was written: the field is
  # personal, or a value of it has a required field that does. A list may be empty.
  defp seals?(field),
    do: Keyword.get(field, :personal) != nil or seals_type?(Keyword.fetch!(field, :type))

  defp seals_type?({:fields, fields}),
    do: Enum.any?(fields, fn {_name, f} -> not Keyword.get(f, :optional, false) and seals?(f) end)

  defp seals_type?(_type), do: false

  # A value holding personal data that takes another shape moves its seals, which open
  # only under the path they were sealed at, and one that takes a shape holding a required
  # seal needs one no step makes; a change inside a value is judged field by field.
  defp reshaped(was, is) do
    cond do
      personal_type?(was) -> {:never, @sealed}
      seals_type?(is) -> {:never, @unfilled}
      true -> :step
    end
  end

  defp personal_type?({:list, inner}), do: personal_type?(inner)

  defp personal_type?({:fields, fields}),
    do:
      Enum.any?(fields, fn {_name, f} ->
        Keyword.get(f, :personal) != nil or personal_inside?(f)
      end)

  defp personal_type?(_type), do: false

  defp untagged(name, is), do: "#{name} was added, #{inspect(is)}: " <> untagged_why()

  defp untagged_why,
    do:
      "the log tags rows with it, and the version before did not tag rows with it under " <>
        "that name, so rows written before carry no such tag"

  # Whether a value stored as `was` reads as `is`: what `EhOsContract.Codec` decodes.
  defp readable(same, same), do: :ok
  defp readable(:integer, :decimal), do: :ok
  defp readable(:id, :string), do: :ok
  defp readable({:enum, was}, {:enum, is}), do: if(was -- is == [], do: :ok, else: :step)
  defp readable({:list, was}, {:list, is}), do: readable(was, is)

  defp readable({:fields, was}, {:fields, is}) do
    problems = uncovered(was, is, [], false)

    case Enum.find(problems, &(elem(&1, 0) == :never)) do
      {:never, _name, why} -> {:never, "within it, " <> why}
      nil -> if problems == [], do: :ok, else: :step
    end
  end

  defp readable(was, is), do: reshaped(was, is)

  # A field the log tags each row with: a required, non-personal identifier or day
  # (`EhOsContract.Key`), its domain value resolved to what it rests on.
  defp tags?(nil), do: false

  defp tags?(field),
    do:
      Keyword.get(field, :type) in [:id, :date, :timestamp] and
        not Keyword.get(field, :optional, false) and Keyword.get(field, :personal) == nil and
        not Keyword.get(field, :removed, false)

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

  # Fields as `encode/1` writes them, at every depth: what reading the lock relies on.
  defp fields?(fields),
    do:
      Keyword.keyword?(fields) and fields == Enum.uniq_by(fields, &elem(&1, 0)) and
        Enum.all?(fields, fn {_name, field} -> field?(field) end)

  defp field?(field),
    do:
      Keyword.keyword?(field) and type?(Keyword.get(field, :type)) and
        Enum.all?(field, fn
          {:type, _type} -> true
          {key, value} when key in [:optional, :removed] -> is_boolean(value)
          {key, value} when key in [:personal, :subject] -> is_atom(value) and value != nil
          _unknown -> false
        end)

  defp type?({:list, inner}), do: type?(inner)
  defp type?({:enum, members}), do: is_list(members) and Enum.all?(members, &is_atom/1)
  defp type?({:fields, fields}), do: fields?(fields)
  defp type?(type), do: is_atom(type) and type != nil

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

  defp normal_type({:fields, fields}), do: {:fields, normal_fields(fields)}

  defp normal_type(type), do: type
end
