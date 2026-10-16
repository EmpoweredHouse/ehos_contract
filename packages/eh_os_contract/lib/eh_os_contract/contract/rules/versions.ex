defmodule EhOsContract.Contract.Rules.Versions do
  # V1–V3 of the contract's rules, plan DD, V1 (#333): how a row written with an older
  # version of an event's fields reads in the current one, a step (`upcast`) per version.
  #
  # - **V1.** An event at `schema_version` n has exactly one step from each version
  #   1..n-1, and none from n or later: a row of a version without a step could not be
  #   read, and a step from the current version reads nothing.
  # - **V2.** A step's targets — the new names of `rename:` and the fields of
  #   `default:` — are fields the chain leads to: fields of the current declaration, or
  #   old names a later step renames. A rename's two names differ, its new names are
  #   atoms, and no two old names of one step take the same new one.
  # - **V3.** The unit's identity is never renamed or given a default: every row of a
  #   stream holds it, and the stream is found by it. A personal field gets no default,
  #   since the log holds a seal where it holds a personal value, and a default would be
  #   clear text there.
  @moduledoc false

  alias EhOsContract.DslRules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    for unit <- declarations.units,
        event <- unit.events,
        violation <- coverage(event) ++ targets(unit, event) ++ identity(unit, event),
        do: violation
  end

  defp coverage(event) do
    froms = Enum.map(event.upcasts, & &1.from)

    wanted =
      if event.schema_version > 1, do: Enum.to_list(1..(event.schema_version - 1)), else: []

    missing =
      for v <- wanted, v not in froms do
        {"V1: event #{inspect(event.name)} is at schema_version #{event.schema_version} and " <>
           "has no `upcast from: #{v}`: a row written at version #{v} could not be read. Each " <>
           "version below the current one has a step, empty when the fields did not change",
         event}
      end

    twice =
      for {from, n} <- Enum.frequencies(froms), n > 1 do
        {"V1: event #{inspect(event.name)} has #{n} steps `upcast from: #{from}`; a version " <>
           "has one", event}
      end

    beyond =
      for u <- event.upcasts, u.from >= event.schema_version do
        {"V1: event #{inspect(event.name)} has `upcast from: #{u.from}`, and its fields are at " <>
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

  defp reachable(event, from, current) do
    for later <- event.upcasts,
        later.from > from,
        {old, _new} <- later.rename,
        into: current,
        do: old
  end

  defp step_targets(event, u, reachable) do
    news = for {_old, new} <- u.rename, do: new

    not_atoms =
      for {old, new} <- u.rename, not is_atom(new) do
        {"V2: event #{inspect(event.name)}, `upcast from: #{u.from}` renames #{inspect(old)} " <>
           "to #{inspect(new)}, which is not a field's name", u}
      end

    unknown =
      for {kind, name} <-
            Enum.map(news, &{:rename, &1}) ++ Enum.map(u.default, &{:default, elem(&1, 0)}),
          is_atom(name),
          not MapSet.member?(reachable, name) do
        what = if kind == :rename, do: "renames a field to", else: "gives a default to"

        {"V2: event #{inspect(event.name)}, `upcast from: #{u.from}` #{what} #{inspect(name)}, " <>
           "which is neither a field of the event nor a name a later step renames", u}
      end

    same =
      for {old, new} <- u.rename, old == new do
        {"V2: event #{inspect(event.name)}, `upcast from: #{u.from}` renames #{inspect(old)} " <>
           "to itself", u}
      end

    shared =
      for {new, n} <- Enum.frequencies(news), n > 1 do
        {"V2: event #{inspect(event.name)}, `upcast from: #{u.from}` renames #{n} fields to " <>
           "#{inspect(new)}; a field has one old name", u}
      end

    not_atoms ++ unknown ++ same ++ shared
  end

  defp identity(unit, event) do
    identity = MapSet.new(List.wrap(unit.identity))
    personal = MapSet.new(for f <- event.fields, f.personal != nil, do: f.name)

    Enum.flat_map(event.upcasts, fn u ->
      renamed(event, u, identity) ++ defaulted(event, u, identity, personal)
    end)
  end

  defp renamed(event, u, identity) do
    for {old, new} <- u.rename,
        MapSet.member?(identity, old) or MapSet.member?(identity, new) do
      {"V3: event #{inspect(event.name)}, `upcast from: #{u.from}` renames #{inspect(old)} " <>
         "to #{inspect(new)}, and the unit's identity is never renamed: every row of a " <>
         "stream holds it, and the stream is found by it", u}
    end
  end

  defp defaulted(event, u, identity, personal) do
    for {field, _value} <- u.default, why = default_refused(field, identity, personal) do
      {"V3: event #{inspect(event.name)}, `upcast from: #{u.from}` gives #{why}", u}
    end
  end

  defp default_refused(field, identity, personal) do
    cond do
      MapSet.member?(identity, field) ->
        "the identity field #{inspect(field)} a default; every row of a stream holds its identity"

      MapSet.member?(personal, field) ->
        "the personal field #{inspect(field)} a default; the log holds a seal there, and a " <>
          "default would be clear text"

      true ->
        nil
    end
  end
end
