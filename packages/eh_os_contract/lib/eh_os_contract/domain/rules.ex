defmodule EhOsContract.Domain.Rules do
  @moduledoc """
  The rules a domain module must satisfy to compile: v2 §6, layer L2, rules D1–D7.

  **D5**, since plan EL2: an end of a directed relation may be an external system, the
  other end then a context; **D1** refuses a name that is both a context and an
  external.

  **D1**, since plan EP5a: an external's operations are snake_case and named once
  within it; since plan EP5b, so are an actor's responsibilities.

  **D5**, since plan EP5b: a relation's `terms` are pairs, the word of its first end
  and of its second, and each word of a context end is a term of that context's
  glossary.

  **D1**, since the review of the actors' names: a subdomain's, context's, subject's,
  value's, entity's and external's name is snake_case, as an actor's is (D4) and a
  contract's (N1). The names become a value's module — `value :"a/b"` was
  `<Domain>.Values.A.B`, a module nested in another — node identifiers of the context
  map, where `context :"front desk"` broke the diagram, page paths, which refused such
  a name only when the pages were generated, and the type a subject's key is stored
  under. Two values whose names camelize alike, `:money_amount` and `:money_amount_` or
  `:money__amount`, would be one module of invariants, `Values.MoneyAmount`, so they
  are refused as two of one name, invariants or not. A value is not named after a type
  Elixir builds in, `:map` or `:integer`, whose `@type` it could not define, nor after a
  built-in field type, `:date`, which a field of that type would mean instead.

  **D3** and **D6**, since the review of the domain's names: a value's and an
  entity's field is snake_case and named once — a value's fields were not checked
  for either, and one declared twice gave the JSON Schema the later definition with
  the earlier one's `required`.

  **D4**, since the review of the domain's `name:`: an actor's name is snake_case, as a
  contract's names are (N1). A person's is a role, `<domain>.<actor>`, in the manifest
  EHOS reads — `actor :"*", :human` would have been the role `"acme.*"` — and a
  system's is named in `by:` as a person's is.

  **D8** (plan EL2): a field's `issued_by:` names an external of this domain, and so does
  an entity's, which gives its injected identity (plan N1).

  **D9** (plan EL2b): a value's invariant is named as a function is — snake_case,
  once in its value, never clashing with what Elixir defines, as N2 holds a
  contract's names, and never `:required`, `:type`, `:generated` or `:supplied`, the words a
  refusal already puts where an invariant's name goes — and shows itself on
  examples: `violated_by:` and `satisfied_by:` each give at least one, every one is
  plain data of the value's type, none is in both and none is in one twice, since
  each names its test. And no example that keeps an invariant is one another
  invariant breaks, of the value or of what it is made of, by its own
  `violated_by:`.

  **D7** (plan EL2): a context's `subdomain:` names a subdomain the domain declares,
  `subdomain :visits, "Wizyty", type: :core`; the kind is the subdomain's.

  **D6** (plan EM2): an entity belongs to a context this domain declares, and is
  identified by its `identity`, a snake_case name the library injects as a required,
  non-personal `:id` (plan N1), so no field of its own takes that name. Its fields are
  well formed and named once, as a value's are, each `subject:` a declared subject,
  and none is personal, nor of a value that holds personal data: an entity's rows are
  the application's, outside the log, where erasure cannot reach them. Every
  `{:id, entity}`, in a value's field or an entity's, names an entity of this domain.

  **D13** (plan W2): the domain's `time_zone:` is a zone the time zone database
  Elixir is configured with knows, since dispatch tags a timestamp's day there.

  **D11** (plan, after #50): the domain's `name:` is the application's namespace, the
  first segment of every name its contracts publish (`EhOsContract.Contract.Rules.Boundaries`)
  and of every capability, so it is such a segment: lowercase letters, digits, `_` and
  `-`, starting with a letter and not ending with a dash. A dot would put the domain's
  publications inside another application's namespace — `:"acme.billing"` publishes
  under `acme.` — and a name no publication could start with would be refused only at
  each publication. The underscore stays, as it does in a publication's name: EHOS
  names an application with a DNS label, which has none, but `:dispatch_rig` is a
  domain the library's own tests publish from. The refusal points at `use`.

  A transformer, not a verifier, and every violation is reported at once, in one
  error that names each declaration's file and line (`EhOsContract.DslRules`).
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Domain.Dsl
  alias EhOsContract.DslRules

  alias EhOsContract.Domain.Dsl.{
    Actor,
    Context,
    Entity,
    External,
    Relation,
    Subdomain,
    Subject,
    Value
  }

  alias Spark.Dsl.Transformer

  @doc false
  # An identifier as declared: `:id`, or `{:id, entity}`, which the model stores as one.
  defguard is_id(type)
           when type == :id or
                  (is_tuple(type) and tuple_size(type) == 2 and elem(type, 0) == :id and
                     is_atom(elem(type, 1)))

  @impl true
  def before?(EhOsContract.Domain.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:domain])
    domain = Transformer.get_persisted(dsl, :eh_os_contract_domain)

    DslRules.result(
      dsl,
      [:domain],
      d11(dsl, domain) ++ d13(dsl, domain) ++ Enum.flat_map(rules(), & &1.(entities, domain))
    )
  end

  defp rules, do: [&d1/2, &d2/2, &d3/2, &d4/2, &d5/2, &d6/2, &d7/2, &d8/2, &d9/2]

  # --- D11: the name is one segment of a namespace --------------------------------

  # `nil`, `true` and `false` are atoms whose text fits, and the option is required.
  defp d11(dsl, %{name: name}) do
    if name not in [nil, true, false] and DslRules.namespace?(Atom.to_string(name)),
      do: [],
      else: [
        {"D11: the domain's name: #{inspect(name)} is not an application's namespace: lowercase " <>
           "letters, digits, _ and -, starting with a letter and not ending with a dash, like " <>
           ":\"my-shop\"; it begins every name the domain's contracts publish", use_at(dsl)}
      ]
  end

  # --- D13: the time zone is one the configured database knows (plan W2) ---------

  # Asked of the database Elixir is configured with, as dispatch will ask it: a zone
  # it does not know would raise on the first append of a timestamp.
  defp d13(dsl, %{time_zone: zone}) do
    if EhOsContract.Domain.time_zone_known?(zone),
      do: [],
      else: [
        {"D13: the domain's time_zone: #{inspect(zone)} is not a zone the configured time " <>
           "zone database (#{inspect(Calendar.get_time_zone_database())}) knows; name an " <>
           "IANA zone like \"Europe/Warsaw\", and configure a database such as Tz with " <>
           "config :elixir, :time_zone_database", use_at(dsl)}
      ]
  end

  defp use_at(dsl) do
    file = dsl |> Transformer.get_persisted(:file) |> String.to_charlist()
    :erl_anno.set_file(file, :erl_anno.new(Transformer.get_persisted(dsl, :eh_os_contract_line)))
  end

  # --- D1: names are snake_case, and unique per kind -----------------------------

  # The types `@type` refuses to redefine are Erlang's, which the running OTP answers
  # for, and these, which Elixir adds (`Kernel.Typespec`).
  @elixir_types ~w(char_list charlist struct nonempty_charlist keyword var)a

  @kinds [
    {Subdomain, "subdomain"},
    {Context, "context"},
    {Actor, "actor"},
    {Subject, "subject"},
    {Value, "value"},
    {Entity, "entity"},
    {External, "external"}
  ]

  defp d1(entities, _domain) do
    by_kind =
      for {struct, kind} <- @kinds,
          duplicate <- duplicates(for(%{__struct__: ^struct} = e <- entities, do: e), & &1.name) do
        {"D1: two #{kind}s are named #{inspect(duplicate.name)}", duplicate}
      end

    terms =
      for %Context{} = context <- entities,
          duplicate <- duplicates(context.terms, & &1.text) do
        {"D1: context #{inspect(context.name)} defines the term #{inspect(duplicate.text)} twice",
         duplicate}
      end

    # Plan EP5a: an operation is named within its system, as `calls: {:p1, :name}` says.
    operations =
      for %External{} = external <- entities,
          operation <- external.operations,
          problem <-
            [
              unless(DslRules.name?(operation.name),
                do: "is not snake_case, as every name of a domain is"
              )
            ],
          problem != nil do
        {"D1: operation #{inspect(operation.name)} of external #{inspect(external.name)} " <>
           problem, operation}
      end ++
        for %External{} = external <- entities,
            duplicate <- duplicates(external.operations, & &1.name) do
          {"D1: external #{inspect(external.name)} declares the operation " <>
             "#{inspect(duplicate.name)} twice", duplicate}
        end

    # Plan EP5b: an actor's responsibilities, named within the actor.
    pairs =
      for %Relation{} = relation <- entities,
          duplicate <- Enum.uniq(duplicates(relation.terms, & &1)) do
        {"D1: relation #{inspect(relation.type)} pairs #{inspect(duplicate)} twice", relation}
      end

    responsibilities =
      for %Actor{} = actor <- entities,
          r <- actor.responsibilities,
          not DslRules.name?(r.name) do
        {"D1: responsibility #{inspect(r.name)} of actor #{inspect(actor.name)} is not " <>
           "snake_case, as every name of a domain is", r}
      end ++
        for %Actor{} = actor <- entities,
            duplicate <- duplicates(actor.responsibilities, & &1.name) do
          {"D1: actor #{inspect(actor.name)} declares the responsibility " <>
             "#{inspect(duplicate.name)} twice", duplicate}
        end

    # A relation has no name: it is its type and its two ends, a symmetric pair in
    # either order. Two of them would also share one key in the model's digests.
    relations =
      for duplicate <-
            duplicates(
              for(%Relation{} = r <- entities, do: r),
              &{&1.type, EhOsContract.Domain.Build.endpoints(&1)}
            ) do
        [a, b | _] = EhOsContract.Domain.Build.endpoints(duplicate) ++ [nil, nil]

        {"D1: relation #{inspect(duplicate.type)} between #{inspect(a)} and #{inspect(b)} " <>
           "is declared twice", duplicate}
      end

    # Plan EL2: a relation's end may be a context or an external, so no name is both.
    contexts = for %Context{name: name} <- entities, do: name

    both =
      for %External{name: name} = external <- entities, name in contexts do
        {"D1: #{inspect(name)} is a context and an external; a relation could not tell which " <>
           "it names", external}
      end

    # An actor's name is D4's.
    forms =
      for {struct, kind} <- @kinds,
          struct != Actor,
          %{__struct__: ^struct, name: name} = declaration <- entities,
          not DslRules.name?(name) do
        {"D1: #{kind} #{inspect(name)} is not snake_case, as every name of a domain is",
         declaration}
      end

    values = for %Value{name: name} = value <- entities, DslRules.name?(name), do: value

    modules =
      for {other, first, camel} <- DslRules.camel_collisions(values, & &1.name) do
        {"D1: value #{inspect(other.name)} camelizes to #{camel}, as value #{inspect(first)} " <>
           "does, and a value's invariants are the module Values.#{camel}; rename one of them",
         other}
      end

    types =
      for %Value{name: name} = value <- values do
        cond do
          built_in_type?(name) ->
            {"D1: value #{inspect(name)} is named after a type Elixir builds in, and its @type " <>
               "could not be defined; name it after what it holds", value}

          name in built_in_types() ->
            {"D1: value #{inspect(name)} is named after a built-in field type, which a field " <>
               "of type #{inspect(name)} would mean instead; name it after what it holds", value}

          true ->
            nil
        end
      end
      |> Enum.reject(&is_nil/1)

    forms ++
      by_kind ++
      modules ++ types ++ terms ++ operations ++ responsibilities ++ pairs ++ relations ++ both
  end

  defp built_in_type?(name), do: :erl_internal.is_type(name, 0) or name in @elixir_types

  # --- D2: one translation per language, none into the term's own ----------------

  defp d2(entities, domain) do
    for %Context{} = context <- entities,
        own = context.language || domain.language,
        term <- context.terms,
        violation <- translation_violations(context, term, own) do
      violation
    end
  end

  defp translation_violations(context, term, own) do
    into_own =
      for %{language: ^own} = translation <- term.translations do
        {"D2: the term #{inspect(term.text)} in context #{inspect(context.name)} is translated " <>
           "into #{inspect(own)}, which is the language it is written in", translation}
      end

    repeated =
      for translation <- duplicates(term.translations, & &1.language),
          translation.language != own do
        {"D2: the term #{inspect(term.text)} in context #{inspect(context.name)} has a second " <>
           "translation into #{inspect(translation.language)}", translation}
      end

    into_own ++ repeated
  end

  # --- D3: a value is one type or a set of fields, well formed, without cycles ----

  # The built-in types of v2 §4.3. Each names a shape, never a thing: a domain type
  # is a `value` of the client's domain.
  @built_in [:id, :string, :integer, :decimal, :boolean, :date, :timestamp]
  @numeric [:integer, :decimal]

  @doc false
  @spec built_in_types() :: [atom()]
  def built_in_types, do: @built_in

  defp d3(entities, _domain) do
    values = for %Value{} = value <- entities, do: value
    names = MapSet.new(values, & &1.name)
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)
    subjects = MapSet.new(for %Subject{name: name} <- entities, do: name)

    aliases = Map.new(values, &{&1.name, &1.type})
    shape = Enum.flat_map(values, &value_shape(&1, names, contexts, aliases))
    by_name = Map.new(values, &{&1.name, &1})
    options = Enum.flat_map(values, &field_options(&1, subjects, by_name))
    shape ++ options ++ cycles(values, names)
  end

  # A value's fields may say whose personal data they hold (v2 §4.3, §14), and
  # those options are checked here with the rule letters v2 §6 gives them. F3: a
  # default belongs only to a contract's state. F5: `personal: f` needs `f` to be
  # a required, non-personal `:id` field of the same value declaring `subject:`,
  # and that subject must be declared; and a personal field is not of a value that
  # holds personal data of its own, which would be sealed under this field's subject.
  defp field_options(value, subjects, values) do
    by_name = Map.new(value.fields, &{&1.name, &1})

    for field <- value.fields,
        violation <- field_option_violations(value, field, by_name, subjects, values) do
      violation
    end
  end

  defp field_option_violations(value, field, by_name, subjects, values) do
    where = "value #{inspect(value.name)}, field #{inspect(field.name)}"

    default =
      if field.default != nil,
        do: [{"F3: #{where} has a default, which only a contract's state may have", field}],
        else: []

    subject =
      if field.subject && not MapSet.member?(subjects, field.subject),
        do: [
          {"F5: #{where} names subject #{inspect(field.subject)}, which this domain does not declare",
           field}
        ],
        else: []

    personal =
      case field.personal && Map.fetch(by_name, field.personal) do
        nil ->
          []

        false ->
          []

        :error ->
          [
            {"F5: #{where} is personal to #{inspect(field.personal)}, which is not a field of this value",
             field}
          ]

        {:ok, %{optional: true}} ->
          [{"F5: #{where} is personal to #{inspect(field.personal)}, which is optional", field}]

        {:ok, %{type: type, subject: subject, personal: nil}}
        when subject != nil and is_id(type) ->
          []

        {:ok, _} ->
          [
            {"F5: #{where} is personal to #{inspect(field.personal)}, which is not an :id field " <>
               "declaring a subject", field}
          ]
      end

    nested =
      if field.personal && EhOsContract.Codec.personal_type?(field.type, values),
        do: [
          {"F5: #{where} is personal, and #{inspect(field.type)} holds personal data of its own, " <>
             "which would be sealed under this field's subject", field}
        ],
        else: []

    default ++ subject ++ personal ++ nested
  end

  defp value_shape(value, names, contexts, aliases) do
    where = "D3: value #{inspect(value.name)}"

    one_of =
      case {value.type, value.fields} do
        {nil, []} ->
          [{"#{where} has neither a type nor fields; give it exactly one", value}]

        {type, [_ | _]} when type != nil ->
          [{"#{where} has both a type and fields; keep one", value}]

        _ ->
          []
      end

    unit =
      if value.unit && not numeric?(value.type, aliases, MapSet.new()) do
        [
          {"#{where} has unit #{inspect(value.unit)}, and a unit counts only an :integer or a :decimal, " <>
             "or a value that is one", value}
        ]
      else
        []
      end

    context =
      if value.context && not MapSet.member?(contexts, value.context) do
        [
          {"#{where} names context #{inspect(value.context)}, which this domain does not declare",
           value}
        ]
      else
        []
      end

    types =
      if value.type,
        do: for(problem <- type_problems(value.type, names), do: {"#{where}: #{problem}", value}),
        else: []

    fields =
      for field <- value.fields, problem <- type_problems(field.type, names) do
        {"#{where}, field #{inspect(field.name)}: #{problem}", field}
      end

    field_names =
      for(
        field <- value.fields,
        not DslRules.name?(field.name),
        do: {"#{where}, field #{inspect(field.name)} is not snake_case", field}
      ) ++
        for field <- duplicates(value.fields, & &1.name),
            do: {"#{where} declares field #{inspect(field.name)} twice", field}

    one_of ++ unit ++ context ++ types ++ fields ++ field_names
  end

  # A number counts something whether it is written as :integer or as a value that
  # is one, `value :fee, :money` over `value :money, :integer`. The walk stops at a
  # value already seen, because a cycle is D3's own violation, reported separately.
  defp numeric?(type, _aliases, _seen) when type in @numeric, do: true

  defp numeric?(name, aliases, seen) when is_atom(name) and name != nil do
    not MapSet.member?(seen, name) and
      numeric?(Map.get(aliases, name), aliases, MapSet.put(seen, name))
  end

  defp numeric?(_type, _aliases, _seen), do: false

  # --- D6: an entity, and every field that names one --------------------------------

  defp d6(entities, _domain) do
    known = MapSet.new(for %Entity{name: name} <- entities, do: name)
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)
    subjects = MapSet.new(for %Subject{name: name} <- entities, do: name)
    values = Map.new(for %Value{} = value <- entities, do: {value.name, value})
    scope = %{contexts: contexts, subjects: subjects, values: values}

    shapes = for %Entity{} = entity <- entities, v <- entity_shape(entity, scope), do: v

    references =
      for %{__struct__: kind, fields: fields} = declaration <- entities,
          kind in [Value, Entity],
          field <- fields,
          name <- references(field.type),
          not MapSet.member?(known, name) do
        {"D6: #{describe(declaration)}, field #{inspect(field.name)}: {:id, #{inspect(name)}} names " <>
           "an entity this domain does not declare", field}
      end

    # A value that is an entity's identifier, `value :period_ref, {:id, :period}`.
    aliases =
      for %Value{type: type} = value <- entities,
          name <- references(type),
          not MapSet.member?(known, name) do
        {"D6: #{describe(value)} is {:id, #{inspect(name)}}, which names an entity this domain " <>
           "does not declare", value}
      end

    shapes ++ references ++ aliases
  end

  defp entity_shape(entity, scope) do
    where = "D6: entity #{inspect(entity.name)}"
    by_name = Map.new(entity.fields, &{&1.name, &1})

    field_names =
      for(
        field <- entity.fields,
        not DslRules.name?(field.name),
        do: {"#{where}, field #{inspect(field.name)} is not snake_case", field}
      ) ++
        for field <- duplicates(entity.fields, & &1.name) do
          {"#{where} declares field #{inspect(field.name)} twice", field}
        end

    context =
      if MapSet.member?(scope.contexts, entity.context),
        do: [],
        else: [
          {"#{where} names context #{inspect(entity.context)}, which this domain does not declare",
           entity}
        ]

    identity =
      cond do
        not DslRules.name?(entity.identity) ->
          [{"#{where}, identity #{inspect(entity.identity)} is not snake_case", entity}]

        Map.has_key?(by_name, entity.identity) ->
          field = Map.fetch!(by_name, entity.identity)

          [
            {"#{where} declares field #{inspect(entity.identity)}, which is its identity; the " <>
               "library injects it as a required, non-personal :id, so declare no field for it" <>
               issuer_moves(field), field}
          ]

        true ->
          []
      end

    names = MapSet.new(Map.keys(scope.values))

    fields =
      for field <- entity.fields, problem <- type_problems(field.type, names) do
        {"#{where}, field #{inspect(field.name)}: #{problem}", field}
      end

    subject =
      for field <- entity.fields,
          field.subject != nil,
          not MapSet.member?(scope.subjects, field.subject) do
        {"#{where}, field #{inspect(field.name)} names subject #{inspect(field.subject)}, which " <>
           "this domain does not declare", field}
      end

    # Personal data inside a value is as far from erasure in an entity's row as a
    # personal field is.
    inside =
      for field <- entity.fields,
          field.personal == nil,
          EhOsContract.Codec.personal_type?(field.type, scope.values) do
        {"#{where}, field #{inspect(field.name)} is of #{inspect(field.type)}, which holds personal " <>
           "data, and an entity's rows are the application's, outside the log, where erasure " <>
           "cannot reach them", field}
      end

    options =
      for field <- entity.fields,
          {option, why} <- [
            default: "only a contract's state has defaults",
            personal:
              "an entity's rows are the application's, outside the log, where erasure " <>
                "cannot reach them"
          ],
          Map.get(field, option) != nil do
        {"#{where}, field #{inspect(field.name)} has #{option}:, and #{why}", field}
      end

    field_names ++ context ++ identity ++ fields ++ subject ++ options ++ inside
  end

  defp describe(%Value{name: name}), do: "value #{inspect(name)}"
  defp describe(%Entity{name: name}), do: "entity #{inspect(name)}"

  @doc false
  # The entities a type names: `{:id, entity}`, inside a list as well.
  @spec references(term()) :: [atom()]
  def references({:id, entity}) when is_atom(entity), do: [entity]
  def references({:list, inner}), do: references(inner)
  def references(_type), do: []

  @doc false
  @spec type_problems(term(), MapSet.t(atom())) :: [String.t()]
  def type_problems(type, _values) when type in @built_in, do: []

  # An identifier of an entity: an :id, whose entity D6 or X3 checks.
  def type_problems({:id, entity}, _values)
      when is_atom(entity) and entity not in [nil, true, false],
      do: []

  def type_problems({:list, inner}, values), do: type_problems(inner, values)

  def type_problems({:enum, members}, _values) when is_list(members) and members != [] do
    names =
      Enum.map(members, fn
        {name, _label} -> name
        name -> name
      end)

    cond do
      not Enum.all?(members, &enum_member?/1) ->
        ["an enum member is an atom, or an atom with a label: #{inspect(members)}"]

      length(Enum.uniq(names)) != length(names) ->
        ["an enum repeats a member: #{inspect(names)}"]

      true ->
        []
    end
  end

  def type_problems({:enum, members}, _values),
    do: ["an enum is a non-empty list of members, got #{inspect(members)}"]

  def type_problems(name, values) when is_atom(name) do
    if MapSet.member?(values, name),
      do: [],
      else: [
        "type #{inspect(name)} is neither a built-in type #{inspect(@built_in)} nor a value of this domain"
      ]
  end

  def type_problems(other, _values), do: ["#{inspect(other)} is not a type"]

  defp enum_member?({name, label}), do: is_atom(name) and is_binary(label)
  defp enum_member?(name), do: is_atom(name) and not is_boolean(name) and not is_nil(name)

  # A value that refers to itself, directly or through other values, has no finite
  # shape. Each cycle is reported once, at the first of its values in declaration
  # order.
  defp cycles(values, names) do
    edges = Map.new(values, &{&1.name, referenced(&1, names)})

    values
    |> Enum.map(& &1.name)
    |> Enum.flat_map(fn name -> cycle_from(name, edges) end)
    |> Enum.uniq_by(&MapSet.new/1)
    |> Enum.map(fn [first | _] = cycle ->
      value = Enum.find(values, &(&1.name == first))
      path = Enum.map_join(cycle ++ [first], " -> ", &inspect/1)
      {"D3: values refer to each other in a cycle: #{path}", value}
    end)
  end

  defp referenced(value, names) do
    types = [value.type | Enum.map(value.fields, & &1.type)]

    types
    |> Enum.flat_map(&type_names/1)
    |> Enum.filter(&MapSet.member?(names, &1))
    |> Enum.uniq()
  end

  defp type_names({:list, inner}), do: type_names(inner)

  defp type_names(name) when is_atom(name) and name not in @built_in and not is_nil(name),
    do: [name]

  defp type_names(_), do: []

  # The shortest cycle through `start`, if there is one: a breadth-first walk back
  # to it.
  defp cycle_from(start, edges) do
    walk([[start]], start, edges, MapSet.new())
  end

  defp walk([], _start, _edges, _seen), do: []

  defp walk([[current | _] = path | rest], start, edges, seen) do
    next = Map.get(edges, current, [])

    if start in next do
      [Enum.reverse(path)]
    else
      fresh = Enum.reject(next, &MapSet.member?(seen, &1))

      walk(
        rest ++ Enum.map(fresh, &[&1 | path]),
        start,
        edges,
        MapSet.union(seen, MapSet.new(fresh))
      )
    end
  end

  # --- D4: an actor is named as a role, and a person is not backed by a system ---

  defp d4(entities, domain) do
    externals = MapSet.new(for %External{name: name} <- entities, do: name)
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)

    for %Actor{} = actor <- entities,
        violation <- actor_violations(actor, externals, contexts, domain) do
      violation
    end
  end

  defp actor_violations(actor, externals, contexts, domain) do
    where = "D4: actor #{inspect(actor.name)}"

    name =
      cond do
        DslRules.name?(actor.name) ->
          []

        actor.kind == :human ->
          [
            {"#{where} is not snake_case; it is the role " <>
               "#{inspect("#{domain.name}.#{actor.name}")}", actor}
          ]

        true ->
          [{"#{where} is not snake_case, as every name in by: is", actor}]
      end

    backed_by =
      cond do
        actor.backed_by == nil ->
          []

        actor.kind == :human ->
          [
            {"#{where} is a person and cannot be backed_by #{inspect(actor.backed_by)}; " <>
               "only a system actor stands for an external system", actor}
          ]

        not MapSet.member?(externals, actor.backed_by) ->
          [
            {"#{where} is backed_by #{inspect(actor.backed_by)}, which this domain does not " <>
               "declare as an external", actor}
          ]

        true ->
          []
      end

    context =
      if actor.context && not MapSet.member?(contexts, actor.context),
        do: [
          {"#{where} names context #{inspect(actor.context)}, which this domain does not declare",
           actor}
        ],
        else: []

    name ++ backed_by ++ context
  end

  # --- D5: a relation's roles fit its type, and its ends exist --------------------

  defp d5(entities, _domain) do
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)
    externals = MapSet.new(for %External{name: name} <- entities, do: name)

    glossaries =
      Map.new(for %Context{} = c <- entities, do: {c.name, MapSet.new(c.terms, & &1.text)})

    for %Relation{} = relation <- entities,
        violation <- relation_violations(relation, contexts, externals, glossaries) do
      violation
    end
  end

  defp relation_violations(%Relation{type: type} = relation, contexts, externals, glossaries) do
    where = "D5: relation #{inspect(type)}"
    directed? = type in Dsl.directed_relations()

    roles =
      cond do
        directed? and
            (relation.between != [] or is_nil(relation.upstream) or is_nil(relation.downstream)) ->
          [
            {"#{where} has a direction: give it upstream: and downstream:, and no between:",
             relation}
          ]

        not directed? and
            (relation.upstream != nil or relation.downstream != nil or
               length(relation.between) != 2) ->
          [
            {"#{where} is symmetric: give it between: [a, b], and no upstream: or downstream:",
             relation}
          ]

        true ->
          []
      end

    ends = Enum.reject([relation.upstream, relation.downstream | relation.between], &is_nil/1)

    # Plan EL2: an end of a directed relation may be an external system, as in ESDM
    # (`conformist` to KSeF); the other end is then a context, since a relation between
    # two systems outside is not this domain's. A symmetric relation joins contexts.
    known = if directed?, do: MapSet.union(contexts, externals), else: contexts

    unknown =
      for name <- Enum.uniq(ends), not MapSet.member?(known, name) do
        cond do
          not directed? and MapSet.member?(externals, name) ->
            {"#{where} is symmetric and names external #{inspect(name)}: a symmetric relation " <>
               "joins contexts; an external may end a directed one", relation}

          directed? ->
            {"#{where} names context or external #{inspect(name)}, which this domain does not " <>
               "declare", relation}

          true ->
            {"#{where} names context #{inspect(name)}, which this domain does not declare",
             relation}
        end
      end

    outside =
      if unknown == [] and ends != [] and Enum.all?(ends, &MapSet.member?(externals, &1)),
        do: [{"#{where} joins no context of this domain: one end has to be a context", relation}],
        else: []

    itself =
      if roles == [] and outside == [] and length(Enum.uniq(ends)) == 1,
        do: [{"#{where} relates context #{inspect(hd(ends))} to itself", relation}],
        else: []

    sides = EhOsContract.Domain.Build.sides(relation)

    terms =
      if roles == [] and unknown == [],
        do: term_violations(where, relation, sides, glossaries),
        else: []

    roles ++ unknown ++ outside ++ itself ++ terms
  end

  # Plan EP5b: each word of a pair is a term of its end's glossary. An external end
  # has no glossary, so its word is the material's and nothing here checks it.
  defp term_violations(where, relation, sides, glossaries) do
    for {first, second} <- relation.terms,
        {word, side} <- [{first, Enum.at(sides, 0)}, {second, Enum.at(sides, 1)}],
        glossary = Map.get(glossaries, side),
        glossary != nil,
        not MapSet.member?(glossary, word) do
      {"#{where}: the term #{inspect(word)} is not in the glossary of context " <>
         "#{inspect(side)}; a relation's terms pair words its contexts define", relation}
    end
  end

  # --- D7: a context belongs to a subdomain this domain declares (plan EL2) ---------

  defp d7(entities, _domain) do
    subdomains = for %Subdomain{name: name} <- entities, do: name

    for %Context{} = context <- entities, context.subdomain not in subdomains do
      {"D7: context #{inspect(context.name)} belongs to subdomain #{inspect(context.subdomain)}, " <>
         "which this domain does not declare; " <> suggest(context.subdomain, subdomains),
       context}
    end
  end

  # An identity that was a field with an issuer keeps the issuer on the entity, or
  # deleting the field would lose it without a word.
  defp issuer_moves(%{issued_by: nil}), do: ""

  defp issuer_moves(%{issued_by: issuer}),
    do: ", and write issued_by: #{inspect(issuer)} on the entity, which gives it"

  # --- D8: a field's issuer is an external of this domain (plan EL2) ---------------

  defp d8(entities, _domain) do
    externals = for %External{name: name} <- entities, do: name

    fields =
      for %{__struct__: struct, fields: fields} = owner <- entities,
          struct in [Value, Entity],
          field <- fields,
          field.issued_by != nil,
          field.issued_by not in externals do
        {"D8: #{describe(owner)}, field #{inspect(field.name)} is issued_by: " <>
           "#{inspect(field.issued_by)}, which is not an external of this domain; " <>
           suggest(field.issued_by, externals), field}
      end

    # Plan N1: an entity's identity is injected, so its issuer is the entity's option.
    identities =
      for %Entity{issued_by: issuer} = entity <- entities,
          issuer != nil,
          issuer not in externals do
        {"D8: #{describe(entity)}, identity #{inspect(entity.identity)} is issued_by: " <>
           "#{inspect(issuer)}, which is not an external of this domain; " <>
           suggest(issuer, externals), entity}
      end

    fields ++ identities
  end

  # --- D9: a value's invariant is named as a function, with examples (plan EL2b) ----

  # What `EhOsContract.Codec` already reports for a field in the place an invariant's
  # name takes in `{:invalid, …}` and in a 422's body.
  @refusals [:required, :type, :generated, :supplied]

  defp d9(entities, _domain) do
    values = Map.new(for(%Value{} = value <- entities, do: {value.name, value}))

    for %Value{} = value <- entities,
        violation <-
          Enum.flat_map(value.invariants, &invariant_violations(value, &1, values)) ++
            for(
              duplicate <- duplicates(value.invariants, & &1.name),
              do:
                {"D9: value #{inspect(value.name)} declares the invariant " <>
                   "#{inspect(duplicate.name)} twice", duplicate}
            ) do
      violation
    end
  end

  defp invariant_violations(value, invariant, values) do
    where = "D9: invariant #{inspect(invariant.name)} of value #{inspect(value.name)}"

    name =
      cond do
        not DslRules.snake_case?(Atom.to_string(invariant.name)) ->
          [
            {"#{where} is not snake_case; it is the name of the function that checks it",
             invariant}
          ]

        clash = EhOsContract.Contract.Rules.Names.elixir_clash(invariant.name, 1) ->
          [{"#{where} #{clash}; it is the name of the function that checks it", invariant}]

        invariant.name in @refusals ->
          [
            {"#{where} is named like a refusal of a field, #{inspect(@refusals)}; a refusal " <>
               "could not tell them apart", invariant}
          ]

        true ->
          []
      end

    examples =
      for {key, list} <- [
            violated_by: invariant.violated_by,
            satisfied_by: invariant.satisfied_by
          ],
          violation <- example_violations(where, key, list, value, invariant, values) do
        violation
      end

    both =
      for example <- Enum.uniq(invariant.violated_by), example in invariant.satisfied_by do
        {"#{where} gives #{inspect(example)} in both violated_by: and satisfied_by:", invariant}
      end

    # Each example names its test, so one given twice would name two alike.
    twice =
      for {key, list} <- [
            violated_by: invariant.violated_by,
            satisfied_by: invariant.satisfied_by
          ],
          example <- Enum.uniq(duplicates(list, & &1)) do
        {"#{where} gives #{inspect(example)} twice in #{key}:", invariant}
      end

    # A value that keeps one invariant is a value, so it breaks no other: neither
    # another of this value's, nor one of what the value is made of, which dispatch
    # asks first. Only what the declarations themselves say is compared.
    contradicted =
      for example <- Enum.uniq(invariant.satisfied_by),
          {type, other} <- Enum.uniq(listed_as_breaking(value.name, example, values)),
          {type, other.name} != {value.name, invariant.name} do
        {"#{where} gives #{inspect(example)} in satisfied_by:, and invariant " <>
           "#{inspect(other.name)} of value #{inspect(type)} gives " <>
           "#{if type == value.name, do: "it", else: "what it holds there"} in violated_by:; a " <>
           "value that keeps one invariant breaks no other", invariant}
      end

    name ++ examples ++ both ++ twice ++ contradicted
  end

  # Every `{value, invariant}` whose `violated_by:` names `data`, or a part of it, as
  # the value of that type it holds: the value itself, an item of a list, a field of a
  # value with fields, the value an alias stands for.
  defp listed_as_breaking(_type, nil, _values), do: []

  defp listed_as_breaking({:list, inner}, data, values) when is_list(data),
    do: Enum.flat_map(data, &listed_as_breaking(inner, &1, values))

  defp listed_as_breaking(type, data, values) when is_atom(type) and is_map_key(values, type) do
    value = Map.fetch!(values, type)
    own = for i <- value.invariants, data in i.violated_by, do: {type, i}

    parts =
      case value do
        %{type: nil, fields: fields} when is_map(data) ->
          Enum.flat_map(fields, &listed_as_breaking(&1.type, Map.get(data, &1.name), values))

        %{type: nil} ->
          []

        %{type: inner} ->
          listed_as_breaking(inner, data, values)
      end

    own ++ parts
  end

  defp listed_as_breaking(_type, _data, _values), do: []

  defp example_violations(where, key, [], _value, invariant, _values),
    do: [
      {"#{where} gives no #{key}: example; give at least one, since each is a test", invariant}
    ]

  defp example_violations(where, key, examples, value, invariant, values) do
    for example <- examples,
        problem <- example_problems(value.name, example, values) do
      {"#{where}, #{key}: #{problem}", invariant}
    end
  end

  defp example_problems(_type, nil, _values),
    do: ["nil is no value; an absent field is never checked"]

  defp example_problems(type, example, values),
    do: EhOsContract.Contract.Data.problems(type, example, values)

  defp suggest(name, names) do
    case DslRules.closest(name, names) do
      nil -> "it declares #{inspect(Enum.sort(names))}"
      suggestion -> "did you mean #{inspect(suggestion)}?"
    end
  end

  defp duplicates(list, key), do: DslRules.duplicates(list, key)
end
