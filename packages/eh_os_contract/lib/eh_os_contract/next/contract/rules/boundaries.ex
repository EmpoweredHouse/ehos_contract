defmodule EhOsContract.Next.Contract.Rules.Boundaries do
  @moduledoc """
  The layer-L2 rules of D10 and D11 (v2 §16): who may read what, and what crosses
  to another application. v2 §6 gives them no letter, so they carry the decision's.

  **D10, a query is a capability.**
  - A query names `by:`; nobody could be granted one that does not.
  - Its `scope` is a field of the read model it reads and a parameter of the query,
    of the same type.
  - A command's `scope` (plan E9c) is one of its fields, its unit's identity or
    declared, and required; and the command names `by:`, since no grant to a
    reaction could carry it.

  **D11, an event leaves only through `publish`.**
  - `from:` is an event of this contract, and `fields:` are some of its fields,
    none of them personal: a copy on a broker cannot be crypto-shredded (v2 §14).
  - `idempotent_on:` names fields among `fields:`.
  - `as:` is a versioned name, dotted lowercase segments ending in `.v<n>`, and two
    publications do not share one.
  - `consumes "<name>"` names such a versioned name, gives it a local name with
    `as:`, and lists the fields it reads; it lists no events, since the name is one.

  Two checks of the same decisions need the domain, and a Mix compiler has it (L3):
  that every actor in a scoped query's or command's `by:` declares its scope, and that a publication's
  name is under the application's own namespace.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.Rules

  @versioned ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\.v[1-9][0-9]*$/

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    read_models = Map.new(declarations.read_models, &{&1.name, &1})
    events = Map.new(Rules.local_events(declarations), &{&1.name, &1})
    identity = Map.new(declarations.units, &{&1.name, &1.identity})

    unit_of =
      for unit <- declarations.units,
          event <- Rules.events(unit),
          into: %{},
          do: {event.name, unit.name}

    Enum.concat([
      Enum.flat_map(declarations.queries, &query(&1, read_models)),
      for(u <- declarations.units, c <- u.commands, v <- command(c, u), do: v),
      Enum.flat_map(declarations.publishes, &publish(&1, events, identity, unit_of)),
      shared_names(declarations.publishes),
      for(%{from: from} = c <- declarations.consumes, is_binary(from), v <- published(c), do: v)
    ])
  end

  defp query(query, read_models) do
    where = "D10: query #{inspect(query.name)}"

    by =
      if query.by == [],
        do: [{"#{where} names no by:, so nobody could be granted it", query}],
        else: []

    scope =
      case query.scope do
        nil ->
          []

        scope ->
          row = read_models |> Map.get(query.reads, %{fields: []}) |> Map.fetch!(:fields)
          row_field = Enum.find(row, &(&1.name == scope))
          param = Enum.find(query.params, &(&1.name == scope))

          cond do
            row_field == nil ->
              [
                {"#{where} is scoped by #{inspect(scope)}, which is not a field of read model " <>
                   "#{inspect(query.reads)}", query}
              ]

            param == nil ->
              [{"#{where} is scoped by #{inspect(scope)}, which is not one of its params", query}]

            row_field.type != param.type ->
              [
                {"#{where} is scoped by #{inspect(scope)}, a #{inspect(row_field.type)} in the read " <>
                   "model and a #{inspect(param.type)} param", query}
              ]

            true ->
              []
          end
      end

    by ++ scope
  end

  defp command(%{scope: nil}, _unit), do: []

  defp command(command, unit) do
    where = "D10: command #{inspect(command.name)} is scoped by #{inspect(command.scope)}"
    declared = Enum.find(command.fields, &(&1.name == command.scope))

    cond do
      command.by == [] ->
        [{"#{where}, and names no by:, so no grant could carry its scope", command}]

      command.scope in List.wrap(unit.identity) ->
        []

      declared == nil ->
        [{"#{where}, which is not one of its fields", command}]

      declared.optional ->
        [{"#{where}, which it declares optional; a grant cannot narrow a missing value", command}]

      true ->
        []
    end
  end

  defp publish(publish, events, identity, unit_of) do
    where = "D11: publication #{inspect(publish.name)}"

    case Map.fetch(events, publish.from) do
      :error ->
        [
          {"#{where} is built from #{inspect(publish.from)}, which is not an event of this contract",
           publish}
        ] ++ name(where, publish.as, publish)

      {:ok, event} ->
        injected = Map.get(identity, Map.fetch!(unit_of, event.name), [])
        declared = Map.new(event.fields, &{&1.name, &1})
        available = MapSet.new(injected ++ Map.keys(declared))

        empty =
          if publish.fields == [],
            do: [{"#{where} carries no fields", publish}],
            else: []

        unknown =
          for field <- publish.fields, not MapSet.member?(available, field) do
            {"#{where} carries #{inspect(field)}, which event #{inspect(event.name)} does not have",
             publish}
          end

        personal =
          for field <- publish.fields,
              %{personal: p} = declared[field] || %{personal: nil},
              p != nil do
            {"#{where} carries #{inspect(field)}, which is personal; a copy on a broker cannot be " <>
               "erased", publish}
          end

        idempotent =
          for field <- publish.idempotent_on, field not in publish.fields do
            {"#{where} is idempotent on #{inspect(field)}, which it does not carry", publish}
          end

        empty ++ unknown ++ personal ++ idempotent ++ name(where, publish.as, publish)
    end
  end

  defp shared_names(publishes) do
    for p <- DslRules.duplicates(publishes, & &1.as) do
      {"D11: publication #{inspect(p.name)} is named #{inspect(p.as)}, like an earlier one", p}
    end
  end

  defp published(consumes) do
    where = "D11: consumes #{inspect(consumes.from)}"

    as =
      if is_atom(consumes.as) and consumes.as != nil,
        do: [],
        else: [{"#{where} needs as: the name the event has in this contract", consumes}]

    events =
      if consumes.events == [],
        do: [],
        else: [
          {"#{where} lists events; a published name is one event, read by its fields", consumes}
        ]

    fields =
      if consumes.fields == [],
        do: [{"#{where} lists no fields; declare the ones this contract reads", consumes}],
        else: []

    as ++ events ++ fields ++ name(where, consumes.from, consumes)
  end

  defp name(where, name, declaration) do
    if is_binary(name) and name =~ @versioned,
      do: [],
      else: [
        {"#{where}: #{inspect(name)} is not a versioned name, dotted lowercase segments ending in " <>
           ".v<n>, like \"rehmed.visit.closed.v1\"", declaration}
      ]
  end
end
