defmodule EhOsContract.Contract.Rules.Versions do
  # U1–U4 of the contract's rules, plan DD, V1 (#333): how a row written with an older
  # version of an event's fields reads in the current one, a step (`upcast`) per version.
  # What needs the domain's values — a value resting on an `:id` or a day, one holding
  # personal data, a default of a value's type — is held to the same between modules
  # (`EhOsContract.Contract.Links.Domain`).
  #
  # - **U1.** An event at `schema_version` n has exactly one step from each version
  #   1..n-1, and none from n or later: a row of a version without a step could not be
  #   read, and a step from the current version reads nothing.
  # - **U2.** A step's targets — the new names of `rename:` and the fields of
  #   `default:` — are fields the chain leads to: fields of the current declaration, or
  #   old names a later step renames. A rename's two names differ, its new names are
  #   atoms, an old name is renamed once, and no two old names of one step take the same
  #   new one. A step by a function (`function:`, plan DD, V2, #338) is a step on its own,
  #   without `rename:` or `default:`; what it gives is the function's, so a step before
  #   it is not held to the names it leads to.
  # - **U3.** What the log keeps outside a row's payload is never renamed or given a
  #   default, since old rows keep it under their old names: the unit's identity, by which
  #   its stream is found, and every field the log tags — a required, non-personal `:id`,
  #   `:date` or `:timestamp` — by which a boundary, a process and a report find rows. A
  #   personal field gets no default, since the log holds a seal there and a default would
  #   be clear text. A name is judged as it ends, through the later steps' renames.
  # - **U4.** A default fits its field: a value of its type, as the log stores one, and
  #   never nil, which no row of a required field holds. A field of a domain value is held
  #   to it between modules.
  @moduledoc false

  alias EhOsContract.Codec
  alias EhOsContract.DslRules
  alias EhOsContract.Key

  require EhOsContract.Domain.Rules

  @built_in EhOsContract.Domain.Rules.built_in_types()

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    for unit <- declarations.units,
        event <- unit.events,
        violation <-
          coverage(event) ++
            targets(unit, event) ++ kept(unit, event) ++ defaults(event) ++ functions(unit, event),
        do: violation
  end

  @doc false
  # The current field of `event` that `name`, a target of step `from`, ends as through
  # the later steps' renames; nil when it ends as none. Read between modules too.
  @spec ends_as(map(), pos_integer(), atom()) :: atom() | nil
  def ends_as(event, from, name) do
    later = event.upcasts |> Enum.filter(&(&1.from > from)) |> Enum.sort_by(& &1.from)

    if Enum.any?(later, & &1.function), do: nil, else: ends_through(event, later, name)
  end

  defp ends_through(event, later, name) do
    final =
      Enum.reduce(later, name, fn step, name ->
        case List.keyfind(step.rename, name, 0) do
          {^name, new} -> new
          nil -> name
        end
      end)

    if Enum.any?(event.fields, &(&1.name == final)), do: final
  end

  defp coverage(event) do
    froms = Enum.map(event.upcasts, & &1.from)

    wanted =
      if event.schema_version > 1, do: Enum.to_list(1..(event.schema_version - 1)), else: []

    missing =
      for v <- wanted, v not in froms do
        {"U1: event #{inspect(event.name)} is at schema_version #{event.schema_version} and " <>
           "has no `upcast from: #{v}`: a row written at version #{v} could not be read. Each " <>
           "version below the current one has a step, empty when the fields did not change",
         event}
      end

    twice =
      for {from, n} <- Enum.frequencies(froms), n > 1 do
        {"U1: event #{inspect(event.name)} has #{n} steps `upcast from: #{from}`; a version " <>
           "has one", event}
      end

    beyond =
      for u <- event.upcasts, u.from >= event.schema_version do
        {"U1: event #{inspect(event.name)} has `upcast from: #{u.from}`, and its fields are at " <>
           "schema_version #{event.schema_version}: a step reads a version below the current " <>
           "one", u}
      end

    missing ++ twice ++ beyond
  end

  # The names step `from` may lead to: the current fields, the unit's identity among
  # them, and every old name a later step renames from.
  defp targets(unit, event) do
    current = MapSet.new(Enum.map(event.fields, & &1.name) ++ List.wrap(unit.identity))

    for u <- event.upcasts,
        violation <- step_targets(event, u, reachable(event, u.from, current)),
        do: violation
  end

  # What a step before a function leads to is the function's to say: anything.
  defp reachable(event, from, current) do
    if opaque?(event, from) do
      :any
    else
      for later <- event.upcasts,
          later.from > from,
          {old, _new} <- later.rename,
          into: current,
          do: old
    end
  end

  defp step_targets(event, u, reachable) do
    news = for {_old, new} <- u.rename, do: new
    at = "event #{inspect(event.name)}, `upcast from: #{u.from}`"

    not_atoms =
      for {old, new} <- u.rename, not is_atom(new) do
        {"U2: #{at} renames #{inspect(old)} to #{inspect(new)}, which is not a field's name", u}
      end

    unknown =
      for {kind, name} <-
            Enum.map(news, &{:rename, &1}) ++ Enum.map(u.default, &{:default, elem(&1, 0)}),
          is_atom(name),
          reachable != :any,
          not MapSet.member?(reachable, name) do
        what = if kind == :rename, do: "renames a field to", else: "gives a default to"

        {"U2: #{at} #{what} #{inspect(name)}, which is neither a field of the event nor a " <>
           "name a later step renames", u}
      end

    same =
      for {old, new} <- u.rename, old == new do
        {"U2: #{at} renames #{inspect(old)} to itself", u}
      end

    renamed_twice =
      for {old, n} <- Enum.frequencies(Enum.map(u.rename, &elem(&1, 0))), n > 1 do
        {"U2: #{at} renames #{inspect(old)} #{n} times; a field has one new name", u}
      end

    defaulted_twice =
      for {field, n} <- Enum.frequencies(Enum.map(u.default, &elem(&1, 0))), n > 1 do
        {"U2: #{at} gives #{inspect(field)} #{n} defaults; a field has one", u}
      end

    shared =
      for {new, n} <- Enum.frequencies(news), n > 1 do
        {"U2: #{at} renames #{n} fields to #{inspect(new)}; a field has one old name", u}
      end

    both =
      if u.function != nil and (u.rename != [] or u.default != []) do
        [
          {"U2: #{at} names the function #{inspect(u.function)} and renames or gives defaults " <>
             "too; a step by a function is a step on its own: put what the function does in " <>
             "it, or the renames in a step of their own", u}
        ]
      else
        []
      end

    not_atoms ++ unknown ++ same ++ renamed_twice ++ defaulted_twice ++ shared ++ both
  end

  # U2, plan DD, V2 (#338): a step's function is a callback of the unit's implementation
  # beside its commands', so it is not named like one.
  defp functions(unit, event) do
    commands = MapSet.new(unit.commands, & &1.name)

    for u <- event.upcasts, u.function != nil, why = clash(u.function, commands), why != nil do
      {"U2: event #{inspect(event.name)}, `upcast from: #{u.from}` names the function " <>
         "#{inspect(u.function)}, #{why}; name it after what it reads", u}
    end
  end

  # An implementation imports `emit/1`, `reject/1` and `issue/1`, so a function of one
  # argument by those names cannot be defined beside them.
  defp clash(fun, _commands) when fun in [:emit, :reject, :issue],
    do: "which the implementation imports"

  defp clash(fun, commands) do
    if MapSet.member?(commands, fun),
      do: "the name of a command of the unit, which the implementation holds too"
  end

  # U3: what the log keeps by a field's name, judged as each target ends.
  defp kept(unit, event) do
    identity = MapSet.new(List.wrap(unit.identity))
    fields = Map.new(event.fields, &{&1.name, &1})

    for u <- event.upcasts,
        {kind, old, target} <-
          Enum.map(u.rename, fn {old, new} -> {:rename, old, new} end) ++
            Enum.map(u.default, fn {field, _value} -> {:default, field, field} end),
        is_atom(target),
        # Before a step by a function, what a target ends as is the function's: it is
        # judged by its own name, which the function is given.
        why =
          kept_why(kind, old, target, ends_as(event, u.from, target) || target, identity, fields),
        why != nil do
      {"U3: event #{inspect(event.name)}, `upcast from: #{u.from}` #{why}", u}
    end
  end

  defp opaque?(event, from), do: Enum.any?(event.upcasts, &(&1.from > from and &1.function))

  defp kept_why(kind, old, target, final, identity, fields) do
    field = Map.get(fields, final)
    gives = if kind == :rename, do: "renames #{inspect(old)} to", else: "gives a default to"
    named = named(target, final)

    cond do
      MapSet.member?(identity, final) or (kind == :rename and MapSet.member?(identity, old)) ->
        "#{gives} the unit's identity, #{inspect(if MapSet.member?(identity, final), do: final, else: old)}; " <>
          "every row of a stream holds it, and the stream is found by it"

      field != nil and (Key.tag_field?(field) or Key.bucket_field?(field)) ->
        "#{gives} #{named}, which the log tags each row with: #{untagged(kind)}, and a " <>
          "boundary, a process or a report finding rows by it would miss them. Declare a new " <>
          "event instead"

      kind == :default and field != nil and field.personal != nil ->
        "gives a default to the personal field #{named}; the log holds a seal there, and a " <>
          "default would be clear text"

      true ->
        nil
    end
  end

  @doc false
  # A step's target as a refusal names it: as the step writes it, and the field it ends as
  # where a later step renames it. Read between modules too.
  @spec named(atom(), atom()) :: String.t()
  def named(target, target), do: inspect(target)
  def named(target, final), do: "#{inspect(target)} (#{inspect(final)} now)"

  @doc false
  # Why rows written before a step are not found by a tagged field it leads to. Read
  # between modules too.
  @spec untagged(:rename | :default) :: String.t()
  def untagged(:rename), do: "rows written before keep their tags under their old names"
  def untagged(:default), do: "rows written before were never tagged with it"

  # U4, for a field of a built-in type: the default decodes as an old row's value would.
  defp defaults(event) do
    for u <- event.upcasts,
        {name, value} <- u.default,
        is_atom(name),
        final = ends_as(event, u.from, name),
        final != nil,
        field = Enum.find(event.fields, &(&1.name == final)),
        built_in?(field.type),
        not fits?(field, value) do
      {"U4: event #{inspect(event.name)}, `upcast from: #{u.from}` gives #{named(name, final)} " <>
         "the default #{inspect(value)}, which is not a value of #{inspect(field.type)}: every " <>
         "old row would fail to read", u}
    end
  end

  defp built_in?({:list, inner}), do: built_in?(inner)
  defp built_in?({:enum, _members}), do: true
  defp built_in?({:id, _referent}), do: true
  defp built_in?(type), do: type in @built_in

  @doc false
  # Whether `value`, a default of `field`, reads back as a value of the field's type, with
  # the domain's `values`: as the log stores it, through JSON. Nil fits an optional field,
  # and a step giving it changes nothing. Read between modules.
  @spec fits?(map(), term(), map()) :: boolean()
  def fits?(field, value, values \\ %{})
  def fits?(%{optional: true}, nil, _values), do: true

  def fits?(field, value, values) do
    stored = value |> Jason.encode!() |> Jason.decode!()

    plain = %{
      name: field.name,
      type: decodable(field.type),
      optional: false,
      personal: nil,
      subject: nil
    }

    value != nil and
      match?({:ok, _}, Codec.decode([plain], %{Atom.to_string(field.name) => stored}, values))
  rescue
    # A value JSON cannot write, as a tuple.
    _cannot_encode in [Protocol.UndefinedError, Jason.EncodeError] -> false
  end

  # A reference to an entity's or a unit's number reads as the `:id` it is.
  defp decodable({:id, _referent}), do: :id
  defp decodable({:list, inner}), do: {:list, decodable(inner)}
  defp decodable(type), do: type
end
