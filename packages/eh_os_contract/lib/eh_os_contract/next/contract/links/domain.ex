defmodule EhOsContract.Next.Contract.Links.Domain do
  @moduledoc """
  X1–X4 of v2 §6, and the parts of D10 and D11 that need the domain: what a
  contract names in the domain it says it belongs to.

  - **X1.** `domain:` names a compiled `EhOsContract.Domain`, and `context:` one of
    its contexts. When the domain is not one, nothing else here is checked, since
    there is nothing to check it against.
  - **X2.** Every actor a contract names — in a command's or a query's `by:`, an
    event's `recorded_by:`, the process's `accountable` and a scenario's `actor` —
    is an actor of the domain, and of this contract's context unless the actor
    names no context.
  - **X3.** Every field type that is not built in is a value of the domain, inside
    a list as well; every `{:id, entity}` names an entity of the domain; every
    `subject:` is a subject of the domain.
  - **X4.** An event's `depends_on` and an effect's `calls` name externals of the
    domain.
  - **F7**, the part that needs the domain: a field F7 keeps from being personal
    is not of a domain value that holds personal data, at any depth.
  - **F5**, the part that needs the domain: a personal field is not of a type that
    holds personal data of its own, which would be sealed under this field's
    subject and outlive the erasure of its own.
  - **D11**, the part that needs the domain: a publication carries no field of a
    type that holds personal data; a copy on a broker cannot be erased.
  - **D10.** Every actor in a scoped query's `by:` carries the query's `scope` as a
    scope dimension, `actor :reception, :human, "…", scope: [:clinic_id]`, since a
    grant to that actor carries the values the answer is narrowed to.
  - **D11.** A `publish` is named under the application's namespace, the domain's
    `name:`: `"rehmed.visit.closed.v1"` in the domain `:rehmed`.
  """

  alias EhOsContract.Codec
  alias EhOsContract.Domain
  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.{Links, Rules}

  @built_in Domain.Rules.built_in_types()

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system), do: Enum.flat_map(system.contracts, &contract/1)

  defp contract(%{domain: nil} = c) do
    [
      {"X1: #{inspect(c.module)} names domain #{inspect(c.model.domain)}, which is not a " <>
         "compiled EhOsContract.Domain", c.at}
    ]
  end

  defp contract(c) do
    Enum.concat([
      context(c),
      actors(c),
      types(c),
      entities(c),
      subjects(c),
      personal_values(c),
      externals(c),
      scopes(c),
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
        for(
          p <- d.processes,
          p.accountable != nil,
          do: {p, "process #{inspect(p.name)}: accountable", p.accountable}
        ) ++
        for s <- d.scenarios,
            s.actor != nil,
            do: {s, "scenario #{inspect(s.description)}: actor", s.actor}

    for {declaration, where, name} <- named,
        problem <- actor_problems(name, known, model.context, domain.module) do
      {"X2: #{where} #{inspect(name)} #{problem}", Links.at(declaration)}
    end
  end

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

  defp entities(%{declarations: d, domain: domain}) do
    entities = Enum.map(Map.get(domain, :entities, []), & &1.name)

    for {where, field} <- fields(d),
        name <- Domain.Rules.references(field.type),
        name not in entities do
      {"X3: #{where}, field #{inspect(field.name)}: {:id, #{inspect(name)}} names no entity of " <>
         "#{inspect(domain.module)}; #{suggest(name, entities)}", Links.at(field)}
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
        for effect <- d.effects,
            x <- effect.calls,
            do: {effect, "effect #{inspect(effect.name)}: calls", x}

    for {declaration, where, name} <- named, name not in externals do
      {"X4: #{where} #{inspect(name)} is not an external of #{inspect(domain.module)}; " <>
         suggest(name, externals), Links.at(declaration)}
    end
  end

  # --- D10, D11 ---------------------------------------------------------------------

  defp scopes(%{declarations: d, domain: domain}) do
    known = Map.new(domain.actors, &{&1.name, &1})

    for query <- d.queries,
        query.scope != nil,
        name <- query.by,
        {:ok, actor} <- [Map.fetch(known, name)],
        query.scope not in actor.scope do
      {"D10: query #{inspect(query.name)} is scoped by #{inspect(query.scope)}, and actor " <>
         "#{inspect(name)} of #{inspect(domain.module)} does not carry it, so no grant to it " <>
         "could say which rows it may read; declare it with scope: [#{inspect(query.scope)}]",
       Links.at(query)}
    end
  end

  defp namespaces(%{declarations: d, domain: domain}) do
    prefix = "#{domain.name}."

    for publish <- d.publishes,
        is_binary(publish.as),
        not String.starts_with?(publish.as, prefix) do
      {"D11: publish #{inspect(publish.name)} is named #{inspect(publish.as)}, outside the " <>
         "application's namespace #{inspect(prefix)}, the name: of #{inspect(domain.module)}",
       Links.at(publish)}
    end
  end

  defp suggest(name, names) do
    case DslRules.closest(name, names) do
      nil -> "it declares #{inspect(Enum.sort(names))}"
      suggestion -> "did you mean #{inspect(suggestion)}?"
    end
  end
end
