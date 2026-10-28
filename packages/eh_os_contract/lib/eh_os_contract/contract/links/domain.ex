defmodule EhOsContract.Contract.Links.Domain do
  # X1–X4 of v2 §6, and the parts of D10 and D11 that need the domain: what a
  # contract names in the domain it says it belongs to.
  #
  # - **X1.** `domain:` names a compiled `EhOsContract.Domain`, and `context:` one of
  #   its contexts. When the domain is not one, nothing else here is checked, since
  #   there is nothing to check it against.
  # - **X2.** Every actor a contract names — in a command's or a query's `by:`, an
  #   event's `recorded_by:` and a scenario's `actor` —
  #   is an actor of the domain, and of this contract's context unless the actor
  #   names no context. A command whose `actor_is` names who must issue it has a
  #   `:human` actor in `by:`, and its scenario by a person names them with `as`, which
  #   no `:system` actor and no other command takes (plan DD, A1, #247).
  # - **X3.** Every field type that is not built in is a value of the domain, inside
  #   a list as well; every `{:id, name}` names exactly one entity of the domain or
  #   unit of one of its contracts (plan DD, L3 (#286)); every `subject:` is a subject
  #   of the domain.
  # - **X4.** An event's `depends_on`, an effect's `calls` and, since plan EL2, a field's
  #   `issued_by` name externals of the domain. Since plan EP5a, a call that names an
  #   operation, `{:p1, :submit_report}`, names one of that external's; and a call to an
  #   external that declares operations names one, since what the effect asks of it is
  #   what the operations are for.
  # - **F7**, the part that needs the domain: a field F7 keeps from being personal
  #   is not of a domain value that holds personal data, at any depth.
  # - **F5**, the part that needs the domain: a personal field is not of a type that
  #   holds personal data of its own, which would be sealed under this field's
  #   subject and outlive the erasure of its own.
  # - **D11**, the part that needs the domain: a publication carries no field of a
  #   type that holds personal data; a copy on a broker cannot be erased.
  # - **D10.** Every actor in a scoped query's `by:` carries the query's `scope` as a
  #   scope dimension, `actor :lead, :human, "…", scope: [:warehouse_id]`, since a
  #   grant to that actor carries the values the answer is narrowed to. The same for a
  #   scoped command's `by:` (plan E9c): the grant carries what it may be issued for.
  # - **F8**, the part that needs the domain: a field a run or a process manager's
  #   record is told by, typed by a domain value, is of one resting on `:id`.
  # - **F1**, the part that needs the domain (#435): a unit's identity field typed by a
  #   domain value names a value of the domain (X3) resting on `:id`, since its value
  #   is part of the unit's stream and of the tags a boundary matches on.
  # - **A4**, the part that needs the domain (#435): a field a boundary's `match:` names
  #   in a local event it consults, typed by a domain value, is of one resting on `:id`,
  #   since only such a field tags an appended event, and the boundary finds what it
  #   consults by its tags.
  # - **D11.** A `publish` is named under the application's namespace, the domain's
  #   `name:`: `"billing.invoice.issued.v1"` in the domain `:billing`.
  # - **P6**, the part that needs the domain (#472): a read model's key field typed by a
  #   domain value is of one that is one value, not made of fields or a list.
  # - **A8**, the part that needs the domain (plan DD, L3 (#286)): what a command
  #   `reads:` is an entity the application keeps, never a unit, whose state is its
  #   events.
  @moduledoc false

  alias EhOsContract.Codec
  alias EhOsContract.Domain
  alias EhOsContract.DslRules
  alias EhOsContract.Key
  alias EhOsContract.References
  alias EhOsContract.Contract.{Links, Rules}

  @built_in Domain.Rules.built_in_types()

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system) do
    # A reference may name a unit of any contract of the domain (plan DD, L3 (#286)).
    models = Enum.map(system.contracts, & &1.model)
    Enum.flat_map(system.contracts, &contract(&1, models))
  end

  defp contract(%{domain: nil} = c, _models) do
    [
      {"X1: #{inspect(c.module)} names domain #{inspect(c.model.domain)}, which is not a " <>
         "compiled EhOsContract.Domain", c.at}
    ]
  end

  defp contract(c, models) do
    Enum.concat([
      context(c),
      actors(c),
      people(c),
      types(c),
      returns(c),
      references(c, models),
      reads(c, models),
      subjects(c),
      personal_values(c),
      upcast_values(c),
      correlation_values(c),
      identity_values(c),
      consulted_values(c),
      externals(c),
      scopes(c),
      table_keys(c),
      namespaces(c)
    ])
  end

  defp context(%{model: model, domain: domain} = c) do
    names = Enum.map(domain.contexts, & &1.name)

    if model.context in names,
      do: [],
      else: [
        {"X1: #{inspect(c.module)} belongs to context #{inspect(model.context)}, which " <>
           "#{inspect(domain.module)} does not declare; #{suggest(model.context, names)}", c.at}
      ]
  end

  # --- X2 ---------------------------------------------------------------------------

  defp actors(%{declarations: d, domain: domain, model: model}) do
    known = Map.new(domain.actors, &{&1.name, &1})

    named =
      for(c <- Rules.commands(d), a <- c.by, do: {c, "command #{inspect(c.name)}: by:", a}) ++
        for(q <- d.queries, a <- q.by, do: {q, "query #{inspect(q.name)}: by:", a}) ++
        for(
          e <- Rules.local_events(d),
          a <- e.recorded_by,
          do: {e, "event #{inspect(e.name)}: recorded_by:", a}
        ) ++
        for s <- d.scenarios,
            s.actor != nil,
            do: {s, "scenario #{inspect(s.description)}: actor", s.actor}

    for {declaration, where, name} <- named,
        problem <- actor_problems(name, known, model.context, domain.module) do
      {"X2: #{where} #{inspect(name)} #{problem}", Links.at(declaration)}
    end
  end

  # X2, the part about a person (plan DD, A1, #247). A command whose `actor_is` names who
  # must issue it compares only a person's credential, so its `by:` names a `:human`
  # actor, or the rule is never applied. A scenario of such a command by a person names
  # them with `as`, as dispatch compares every person; and `as` beside a `:system` actor
  # names someone dispatch never compares.
  defp people(%{declarations: d, domain: domain}) do
    kinds = Map.new(domain.actors, &{&1.name, &1.kind})
    gated = for c <- Rules.commands(d), c.actor_is != [], into: %{}, do: {c.name, c}

    by =
      for c <- Map.values(gated), not Enum.any?(c.by, &(kinds[&1] == :human)) do
        {"X2: command #{inspect(c.name)} names who must issue it (actor_is), and its by: " <>
           "#{inspect(c.by)} names no person, so nobody is ever compared", Links.at(c)}
      end

    scenarios =
      for s <- d.scenarios,
          [%{kind: :command, name: name}] <- [s.trigger],
          Map.has_key?(gated, name) or s.as != nil,
          s.actor != nil,
          problem <- person_problems(s, kinds[s.actor], Map.has_key?(gated, name)) do
        {"X2: scenario #{inspect(s.description)}: #{problem}", Links.at(s)}
      end

    by ++ scenarios
  end

  defp person_problems(%{as: nil, actor: actor}, :human, true),
    do: [
      "actor #{inspect(actor)} is a person, and the command names who must issue it: say " <>
        "which person with as"
    ]

  defp person_problems(%{as: as, actor: actor}, :system, _gated) when is_binary(as),
    do: [
      "as #{inspect(as)} names a person beside #{inspect(actor)}, a :system actor, whom " <>
        "dispatch never compares"
    ]

  defp person_problems(%{as: as}, _kind, false) when is_binary(as),
    do: ["as #{inspect(as)} names a person, and the command names nobody who must issue it"]

  defp person_problems(_scenario, _kind, _gated), do: []

  defp actor_problems(name, known, context, domain) do
    case Map.fetch(known, name) do
      {:ok, %{context: own}} when own in [nil, context] ->
        []

      {:ok, %{context: own}} ->
        ["is an actor of context #{inspect(own)}, not of #{inspect(context)}"]

      :error ->
        ["is not an actor of #{inspect(domain)}; #{suggest(name, Map.keys(known))}"]
    end
  end

  # --- X3 ---------------------------------------------------------------------------

  defp types(%{declarations: d, domain: domain}) do
    values = Enum.map(domain.values, & &1.name)

    for {where, field} <- fields(d),
        name <- value_names(field.type),
        name not in values do
      {"X3: #{where}, field #{inspect(field.name)}: #{inspect(name)} is neither a built-in type " <>
         "nor a value of #{inspect(domain.module)}; #{suggest(name, values)}", Links.at(field)}
    end
  end

  defp returns(%{declarations: d, domain: domain}) do
    values = Enum.map(domain.values, & &1.name)

    for {where, function} <- Rules.Fields.returns(d),
        function.returns != nil,
        name <- value_names(function.returns.type),
        name not in values do
      {"X3: #{where} returns #{inspect(name)}, which is neither a built-in type nor a value of " <>
         "#{inspect(domain.module)}; #{suggest(name, values)}", Links.at(function)}
    end
  end

  # Plan DD, L3 (#286): `{:id, name}` names an entity of the domain or a unit of one of
  # its contracts, and exactly one, since every reader after this takes the name alone.
  defp references(%{declarations: d, domain: domain}, models) do
    fields =
      for {where, field} <- fields(d),
          name <- Domain.Rules.references(field.type),
          problem <- reference_problems(name, domain, models) do
        {"X3: #{where}, field #{inspect(field.name)}: {:id, #{inspect(name)}} #{problem}",
         Links.at(field)}
      end

    returns =
      for {where, function} <- Rules.Fields.returns(d),
          function.returns != nil,
          name <- Domain.Rules.references(function.returns.type),
          problem <- reference_problems(name, domain, models) do
        {"X3: #{where} returns {:id, #{inspect(name)}}, which #{problem}", Links.at(function)}
      end

    identities =
      for unit <- d.units,
          {field, type} <- unit.identity_types,
          name <- Domain.Rules.references(type),
          problem <- reference_problems(name, domain, models) do
        {"X3: #{unit.kind} #{inspect(unit.name)}: identity #{inspect(field)}: " <>
           "{:id, #{inspect(name)}} #{problem}", Links.at(unit)}
      end

    fields ++ returns ++ identities
  end

  defp reference_problems(name, domain, models) do
    case References.candidates(name, domain, models) do
      [_one] ->
        []

      [] ->
        [
          "names no entity of #{inspect(domain.module)} and no unit of its contracts; " <>
            suggest(name, References.names(domain, models), "they declare")
        ]

      many ->
        [
          "names more than one: #{Enum.map_join(many, ", ", &References.describe/1)}; a " <>
            "reference cannot tell them apart, so rename one"
        ]
    end
  end

  # A8, the part that needs the domain (plan DD, L3 (#286)): a command reads a row the
  # application keeps (`EhOsContract.Entities`). A unit's state is its events, which
  # its own contract decides, and the host has no row of it to give.
  defp reads(%{declarations: d, domain: domain}, models) do
    for command <- Rules.commands(d),
        {name, field_name} <- Map.get(command, :reads, []),
        field = Enum.find(command.fields, &(&1.name == field_name)),
        field != nil,
        [target] <- [Domain.Rules.references(field.type)],
        {:unit, _c, _name} = unit <- [References.resolve(target, domain, models)] do
      {"A8: command #{inspect(command.name)} reads #{inspect(name)} by " <>
         "#{inspect(field_name)}, which identifies #{References.describe(unit)}; a command reads " <>
         "only an entity the application keeps, and a unit's state is its events",
       Links.at(command)}
    end
  end

  defp subjects(%{declarations: d, domain: domain}) do
    subjects = Enum.map(domain.subjects, & &1.name)

    for {where, field} <- fields(d),
        subject = Map.get(field, :subject),
        subject != nil,
        subject not in subjects do
      {"X3: #{where}, field #{inspect(field.name)}: subject #{inspect(subject)} is not a subject " <>
         "of #{inspect(domain.module)}; #{suggest(subject, subjects)}", Links.at(field)}
    end
  end

  # --- F8: what a run is told by, typed by a domain value -------------------------------

  # A value the domain does not declare is X3's; one it does rests on a built-in type.
  defp correlation_values(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})

    for {where, field} <- Rules.Fields.correlation_fields(d),
        is_atom(field.type),
        Map.has_key?(values, field.type),
        (base = Key.base_type(field.type, values)) != :id do
      {"F8: #{where}, so its value is part of an index key, and it is #{inspect(field.type)}, " <>
         "which rests on #{rests_on(base, values)}; correlate only on an identifier, an :id of " <>
         "at most 255 bytes, as match: does", Links.at(field)}
    end
  end

  # --- F1: a unit's identity typed by a domain value (#435) ----------------------------

  defp identity_values(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})

    for unit <- d.units,
        {field, type} <- unit.identity_types,
        is_atom(type),
        type not in @built_in,
        problem <- identity_value_problems(type, domain, values) do
      {problem.(
         "#{unit.kind} #{inspect(unit.name)}: identity #{inspect(field)}: #{inspect(type)}"
       ), Links.at(unit)}
    end
  end

  # --- A4: what a boundary matches in a local event, typed by a domain value (#435) ----

  # L2 let a field of a value through, not knowing what the value rests on. A value
  # the domain does not declare is X3's, and an identity typed by one is F1's.
  defp consulted_values(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})
    events = for u <- d.units, e <- u.events, into: %{}, do: {e.name, {u, e}}

    for unit <- d.units,
        unit.kind == :dcb,
        consults <- unit.consults,
        {owner, event} <- List.wrap(events[consults.event]),
        name <- Enum.uniq(consults.match),
        name not in owner.identity,
        field = Enum.find(event.fields, &(&1.name == name)),
        field != nil,
        is_atom(field.type),
        Map.has_key?(values, field.type),
        (base = Key.base_type(field.type, values)) != :id do
      {"A4: dcb #{inspect(unit.name)} consults #{inspect(event.name)} matching " <>
         "#{inspect(name)}, which the event carries as #{inspect(field.type)}, resting on " <>
         "#{rests_on(base, values)}; only an :id, or a domain value resting on one, tags an " <>
         "appended event, so the boundary could never find one", Links.at(consults)}
    end
  end

  # Each problem takes where it is, so that its message starts with its code.
  defp identity_value_problems(type, domain, values) do
    cond do
      not Map.has_key?(values, type) ->
        [
          &("X3: #{&1} is neither a built-in type nor a value of #{inspect(domain.module)}; " <>
              suggest(type, Map.keys(values)))
        ]

      (base = Key.base_type(type, values)) != :id ->
        [
          &("F1: #{&1} rests on #{rests_on(base, values)}; a unit's identity is part of its " <>
              "stream's key and of the tags a boundary matches on, so a domain value typing it " <>
              "rests on :id")
        ]

      true ->
        []
    end
  end

  defp rests_on(base, values) do
    case values do
      %{^base => %{type: nil}} -> "fields of its own"
      %{^base => %{type: type}} -> inspect(type)
      _ -> inspect(base)
    end
  end

  # --- F7, F5 and D11: personal data inside domain values ------------------------------

  defp personal_values(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})

    outside =
      for {where, field, why} <- Rules.Fields.outside_the_log(d, :fields),
          Map.get(field, :personal) == nil,
          Codec.personal_type?(field.type, values) do
        {"F7: #{where} is of #{inspect(field.type)}, which holds personal data, and #{why}, " <>
           "where erasure cannot reach it", Links.at(field)}
      end

    nested =
      for {where, field} <- fields(d),
          Map.get(field, :personal) != nil,
          Codec.personal_type?(field.type, values) do
        {"F5: #{where}, field #{inspect(field.name)} is personal, and #{inspect(field.type)} holds " <>
           "personal data of its own, which would be sealed under this field's subject and outlive " <>
           "its own subject's erasure; drop personal: here and let the inner fields say whose they are",
         Links.at(field)}
      end

    outside ++ nested ++ published(d, values)
  end

  # --- U3 and U4: an event's steps against the domain's values ----------------------

  # Plan DD, V1 (#333): what L2 holds a step to for a built-in type
  # (`EhOsContract.Contract.Rules.Versions`), for a field of a domain value: one resting
  # on an `:id` or a day is tagged and keeps its old name in old rows, one holding
  # personal data takes no default, and a default fits its value.
  defp upcast_values(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})

    for unit <- d.units,
        event <- unit.events,
        u <- event.upcasts,
        {kind, target, value} <-
          Enum.map(u.rename, fn {_old, new} -> {:rename, new, nil} end) ++
            Enum.map(u.default, fn {field, value} -> {:default, field, value} end),
        is_atom(target),
        final = Rules.Versions.ends_as(event, u.from, target),
        field = final && Enum.find(event.fields, &(&1.name == final)),
        field != nil and of_values?(field.type),
        why = upcast_refused(kind, Rules.Versions.named(target, final), field, value, values),
        why != nil do
      {"#{why} (event #{inspect(event.name)}, `upcast from: #{u.from}`)", Links.at(u)}
    end
  end

  # A type of the domain's values, or a list of them: what L2 could not judge.
  defp of_values?({:list, inner}), do: of_values?(inner)
  defp of_values?(type), do: is_atom(type) and type not in @built_in

  defp upcast_refused(kind, named, field, value, values) do
    gives = if kind == :rename, do: "renames a field to", else: "gives a default to"

    cond do
      Key.tag_field?(field, values) or Key.bucket_field?(field, values) ->
        "U3: a step #{gives} #{named}, of #{inspect(field.type)}, which rests on an :id or a " <>
          "day, so the log tags each row with it: #{Rules.Versions.untagged(kind)}. Declare a " <>
          "new event instead"

      kind == :default and Codec.personal_type?(field.type, values) ->
        "U3: a step gives a default to #{named}, of #{inspect(field.type)}, which holds " <>
          "personal data; the log holds a seal there, and a default would be clear text"

      kind == :default and not Rules.Versions.fits?(field, value, values) ->
        "U4: a step gives #{named} the default #{inspect(value)}, which is not a value of " <>
          "#{inspect(field.type)}: every old row would fail to read"

      true ->
        nil
    end
  end

  defp published(d, values) do
    events = Map.new(Rules.local_events(d), &{&1.name, &1})

    for publish <- d.publishes,
        %{fields: declared} <- [Map.get(events, publish.from)],
        field <- declared,
        field.name in publish.fields,
        Map.get(field, :personal) == nil,
        Codec.personal_type?(field.type, values) do
      {"D11: publication #{inspect(publish.name)} carries #{inspect(field.name)}, of " <>
         "#{inspect(field.type)}, which holds personal data; a copy on a broker cannot be erased",
       Links.at(publish)}
    end
  end

  # The names of domain values a type refers to: none for a built-in type or an enum.
  defp value_names(type) when type in @built_in, do: []
  defp value_names({:list, inner}), do: value_names(inner)
  defp value_names({:enum, _members}), do: []
  defp value_names({:id, _entity}), do: []
  defp value_names(name) when is_atom(name), do: [name]
  defp value_names(_malformed), do: []

  # `{where, field}` for the field of every struct the contract declares.
  defp fields(d) do
    for {where, fields, _injected, _kind} <- Rules.Fields.structs(d), f <- fields, do: {where, f}
  end

  # --- X4 ---------------------------------------------------------------------------

  defp externals(%{declarations: d, domain: domain}) do
    externals = Enum.map(domain.externals, & &1.name)

    named =
      for(
        e <- Rules.local_events(d),
        e.depends_on != nil,
        do: {e, "event #{inspect(e.name)}: depends_on", e.depends_on}
      ) ++
        for(
          effect <- d.effects,
          x <- effect.calls,
          do: {effect, "effect #{inspect(effect.name)}: calls", system(x)}
        ) ++
        for {where, fields, _injected, _kind} <- Rules.Fields.structs(d),
            field <- fields,
            # A query's parameter and a service's argument take no `issued_by:`.
            issuer = Map.get(field, :issued_by),
            issuer != nil,
            do: {field, "#{where}, field #{inspect(field.name)}: issued_by", issuer}

    unknown =
      for {declaration, where, name} <- named, name not in externals do
        {"X4: #{where} #{inspect(name)} is not an external of #{inspect(domain.module)}; " <>
           suggest(name, externals), Links.at(declaration)}
      end

    unknown ++ operations(d, domain)
  end

  defp system({external, _operation}), do: external
  defp system(external), do: external

  # Plan EP5a: what a call asks of a system that says what it does.
  defp operations(d, domain) do
    declared =
      Map.new(
        domain.externals,
        &{&1.name, Enum.map(Map.get(&1, :operations, []), fn o -> o.name end)}
      )

    for effect <- d.effects,
        call <- Enum.uniq(effect.calls),
        {:ok, operations} <- [Map.fetch(declared, system(call))],
        problem <- operation_problems(call, operations, domain) do
      {"X4: effect #{inspect(effect.name)}: calls #{inspect(call)}, " <> problem,
       Links.at(effect)}
    end
  end

  defp operation_problems({external, _operation}, [], domain),
    do: [
      "and external #{inspect(external)} of #{inspect(domain.module)} declares no " <>
        "operations, so the call names the system alone: #{inspect(external)}"
    ]

  defp operation_problems({external, operation}, operations, domain) do
    if operation in operations,
      do: [],
      else: [
        "and #{inspect(operation)} is not an operation of external #{inspect(external)} of " <>
          "#{inspect(domain.module)}; " <> suggest(operation, operations)
      ]
  end

  defp operation_problems(external, [_ | _] = operations, _domain),
    do: [
      "and external #{inspect(external)} declares what it does, so the call names one of " <>
        "its operations: #{Enum.map_join(operations, ", ", &inspect({external, &1}))}"
    ]

  defp operation_problems(_external, [], _domain), do: []

  # --- D10, D11 ---------------------------------------------------------------------

  defp scopes(%{declarations: d, domain: domain}) do
    known = Map.new(domain.actors, &{&1.name, &1})

    uncarried =
      for {kind, declaration, _fields} <- scoped(d),
          name <- declaration.by,
          {:ok, actor} <- [Map.fetch(known, name)],
          declaration.scope not in actor.scope do
        {"D10: #{kind} #{inspect(declaration.name)} is scoped by #{inspect(declaration.scope)}, " <>
           "and actor #{inspect(name)} of #{inspect(domain.module)} does not carry it, so no " <>
           "grant to it could say #{granted(kind)}; declare it with " <>
           "scope: [#{inspect(declaration.scope)}]", Links.at(declaration)}
      end

    # A scope is one value compared with a grant as a string, so a value made of
    # fields cannot be one (plan E9c): it would reach the check as a map.
    values = Map.new(domain.values, &{&1.name, &1})

    # Followed through aliases, `value :home, :contact` or `value :codes, {:list, :id}`,
    # which L2 cannot see without the domain.
    composite =
      for {kind, declaration, fields} <- scoped(d),
          field = Enum.find(fields, &(&1.name == declaration.scope)),
          field != nil,
          shape = one_value(field.type, values),
          shape != :one do
        {"D10: #{kind} #{inspect(declaration.name)} is scoped by #{inspect(declaration.scope)}, " <>
           "a #{inspect(field.type)} #{shape}; a scope is one value", Links.at(field)}
      end

    uncarried ++ composite
  end

  # --- P6 -------------------------------------------------------------------------

  # A read model's key is its table's primary key, one column a field: a domain value
  # made of fields, or one that is a list, is not one, through its aliases too, which
  # L2 cannot see without the domain (#472).
  defp table_keys(%{declarations: d, domain: domain}) do
    values = Map.new(domain.values, &{&1.name, &1})

    for read_model <- d.read_models,
        name <- Enum.uniq(read_model.key),
        field = Enum.find(read_model.fields, &(&1.name == name)),
        field != nil,
        shape = one_value(field.type, values),
        shape != :one do
      {"P6: read model #{inspect(read_model.name)} has #{inspect(name)} in its key, a " <>
         "#{inspect(field.type)} #{shape}; a key field is one value", Links.at(field)}
    end
  end

  defp granted("query"), do: "which rows it may read"
  defp granted("command"), do: "what it may be issued for"

  # Whether a domain value comes down to one value: the value its aliases rest on
  # (`EhOsContract.Key.base_type/2`) is made of fields, or a list, or neither. A literal
  # list is L2's to refuse.
  defp one_value(type, values) when is_atom(type) do
    case Map.get(values, EhOsContract.Key.base_type(type, values)) do
      %{type: nil} -> "made of fields"
      %{type: {:list, _}} -> "which is a list"
      _built_in_or_undeclared -> :one
    end
  end

  defp one_value(_type, _values), do: :one

  # Every scoped query and command, with the fields its scope is one of.
  defp scoped(d) do
    for(q <- d.queries, q.scope != nil, do: {"query", q, q.params}) ++
      for c <- Rules.commands(d), c.scope != nil, do: {"command", c, c.fields}
  end

  defp namespaces(%{declarations: d, domain: domain} = c) do
    prefix = "#{domain.name}."

    published =
      for publish <- d.publishes,
          is_binary(publish.as),
          not String.starts_with?(publish.as, prefix) do
        {"D11: publish #{inspect(publish.name)} is named #{inspect(publish.as)}, outside the " <>
           "application's namespace #{inspect(prefix)}, the name: of #{inspect(domain.module)}",
         Links.at(publish)}
      end

    # Plan DD, ID1: the contract's own name, under the same namespace.
    named =
      for %{value: id, at: at} <- [c.id],
          not String.starts_with?(id, prefix) do
        {"D11: the contract's id: #{inspect(id)} is outside the application's namespace " <>
           "#{inspect(prefix)}, the name: of #{inspect(domain.module)}", at}
      end

    published ++ named
  end

  defp suggest(name, names, declare \\ "it declares") do
    case DslRules.closest(name, names) do
      nil -> "#{declare} #{inspect(Enum.sort(names))}"
      suggestion -> "did you mean #{inspect(suggestion)}?"
    end
  end
end
