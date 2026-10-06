defmodule EhOsContract.Contract.Rules.Boundaries do
  # Plan DD, ID1: a contract's id will prefix every event type it records and the keys
  # of its rows, so it is held well under what a key may be (plan #98).
  @id_bytes 100

  @moduledoc """
  The layer-L2 rules of D10 and D11 (v2 §16): who may read what, and what crosses
  to another application. v2 §6 gives them no letter, so they carry the decision's.

  **D10, a query is a capability.**
  - A query names `by:`; nobody could be granted one that does not.
  - Its `scope` is a field of the read model it reads and a parameter of the query,
    of the same type.
  - A command's `scope` (plan E9c) is one of its fields, its unit's identity or
    declared, and required; and the command names `by:`, since no grant to a
    reaction could carry it. A generated identity is no scope: a command that
    creates its aggregate arrives without it.
  - A scope, a query's or a command's, is one value: not a list, whose elements
    would be compared with a grant as one string. A value made of fields is the
    domain's to see (L3).

  **D11, an event leaves only through `publish`.**
  - `from:` is an event of this contract, and `fields:` are some of its fields,
    none of them personal: a copy on a broker cannot be crypto-shredded (v2 §14).
  - `idempotent_on:` names fields among `fields:`.
  - `as:` is a versioned name, dotted lowercase segments ending in `.v<n>`, and two
    publications do not share one. The first segment is the application's namespace,
    the domain's `name:`, and may also hold a dash, not at either end: EHOS names an
    application with a DNS label, so `my_shop`'s domain is `:"my-shop"` there
    (`"my-shop.entry.recorded.v1"`). The other segments are snake_case. The namespace
    keeps the underscore the pattern always allowed, so a domain named `:dispatch_rig`
    still publishes. The domain's `name:` is held to the same segment by the domain
    (`EhOsContract.Domain.Rules`), so the namespace is never more than one.
  - A contract has an `id:` (plan DD, ID1; required from ID3), the application's namespace, then one or more
    dotted snake_case segments, none of them a version — `"rehmed.settlement"` — of at
    most #{@id_bytes} bytes: it names the contract to readers outside the code, prefixes
    its event types (`"<id>.<event>"`), and will prefix its rows' keys, where neither `:`
    nor `|` may stand.
  - `subscribe "<name>"` names such a versioned name, gives it a local name with
    `as:`, and lists the fields it reads.

  **D12, another application's event is a policy's.** An event received through
  `subscribe "<name>"` arrives in an inbox and never enters this log
  (`EhOsContract.Inbox`), so only a policy takes it: a read model is rebuilt from the
  log, an effect's job and a process manager read theirs from it, and none of them
  would ever see it. One that reacts to such an event takes what a policy's command
  records instead.

  Three checks of the same decisions need the domain, and a Mix compiler has it (L3):
  that every actor in a scoped query's or command's `by:` declares its scope, and that a publication's
  name and the contract's `id:` are under the application's own namespace.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules

  # A version segment, as `@versioned` ends a publication's name: no segment of a
  # contract's id is one, wherever it stands — the first included, since a domain may
  # be named `:v1`.
  @version ~r/^v[1-9][0-9]*\z/

  # What follows the namespace (`DslRules.namespace?/1`); `\z`, not `$`, which also
  # matches before a final newline.
  @versioned ~r/^(\.[a-z][a-z0-9_]*)+\.v[1-9][0-9]*\z/

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
      for(
        %{from: from, via: :subscribe} = c <- declarations.consumes,
        is_binary(from),
        v <- published(c),
        do: v
      ),
      received_beyond_policies(declarations)
    ])
  end

  defp received_beyond_policies(declarations) do
    received = Rules.received(declarations)

    takers =
      for(r <- declarations.read_models, e <- r.projects, do: {"read model", r, e, r}) ++
        for(e <- declarations.effects, h <- e.handles, do: {"effect", e, h, e}) ++
        for pm <- declarations.process_managers,
            d <- pm.starts_on ++ pm.on ++ pm.ends_on,
            do: {"process manager", pm, d.event, d}

    for {kind, taker, event, at} <- takers, MapSet.member?(received, event) do
      {"D12: #{kind} #{inspect(taker.name)} takes #{inspect(event)}, which arrives from " <>
         "another application into an inbox and never enters this log, so only a policy " <>
         "reacts to it; take the event its command records instead", at}
    end
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

            match?({:list, _}, param.type) ->
              [{"#{where} is scoped by #{inspect(scope)}, #{list(param.type)}", query}]

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

      command.scope in List.wrap(unit.identity) and command.creates and unit.generated != nil ->
        [
          {"#{where}, the identity the library generates, which the command that creates the " <>
             "aggregate arrives without", command}
        ]

      command.scope in List.wrap(unit.identity) ->
        []

      declared == nil ->
        [{"#{where}, which is not one of its fields", command}]

      declared.optional ->
        [{"#{where}, which it declares optional; a grant cannot narrow a missing value", command}]

      match?({:list, _}, declared.type) ->
        [{"#{where}, #{list(declared.type)}", command}]

      true ->
        []
    end
  end

  defp list(type),
    do:
      "a #{inspect(type)}; a scope is one value, and a list's elements would be compared " <>
        "with the grant as one string"

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

  @doc false
  # Plan DD, ID1: D11 of the contract's `id:` (`Rules.contract_id/1`), which stands
  # beside the declarations rather than among them.
  @spec contract_id(%{value: String.t(), at: term()} | nil) :: [{String.t(), term()}]
  def contract_id(nil), do: []

  # Plan DD, ID3 (#173): the id labels every event the contract records, so there is no
  # contract without one.
  def contract_id(%{value: nil, at: at}) do
    [
      {"D11: the contract names no id:, which labels every event it records; add one, the " <>
         "application's namespace and the contract's name, like `id: \"my-shop.settlement\"`", at}
    ]
  end

  def contract_id(%{value: id, at: at}) do
    if byte_size(id) <= @id_bytes and contract_id?(id),
      do: [],
      else: [
        {"D11: the contract's id: #{inspect(id)} is not a contract's name: the application's " <>
           "namespace, then dotted snake_case segments, unversioned, at most #{@id_bytes} bytes, " <>
           "like \"my-shop.settlement\"", at}
      ]
  end

  defp contract_id?(id) do
    case String.split(id, ".") do
      [namespace | [_ | _] = rest] = segments ->
        DslRules.namespace?(namespace) and Enum.all?(rest, &DslRules.snake_case?/1) and
          not Enum.any?(segments, &(&1 =~ @version))

      _one ->
        false
    end
  end

  defp shared_names(publishes) do
    for p <- DslRules.duplicates(publishes, & &1.as) do
      {"D11: publication #{inspect(p.name)} is named #{inspect(p.as)}, like an earlier one", p}
    end
  end

  defp published(consumes) do
    where = "D11: subscribe #{inspect(consumes.from)}"

    as =
      if is_atom(consumes.as) and consumes.as != nil,
        do: [],
        else: [{"#{where} needs as: the name the event has in this contract", consumes}]

    fields =
      if consumes.fields == [],
        do: [{"#{where} lists no fields; declare the ones this contract reads", consumes}],
        else: []

    as ++ fields ++ name(where, consumes.from, consumes)
  end

  defp name(where, name, declaration) do
    if versioned?(name),
      do: [],
      else: [
        {"#{where}: #{inspect(name)} is not a versioned name: the application's namespace, " <>
           "which may hold a dash but not at either end, then dotted snake_case segments, ending " <>
           "in .v<n>, like \"my-shop.visit.closed.v1\"", declaration}
      ]
  end

  defp versioned?(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [namespace, rest] -> DslRules.namespace?(namespace) and "." <> rest =~ @versioned
      [_] -> false
    end
  end

  defp versioned?(_name), do: false
end
