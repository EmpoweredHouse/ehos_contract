defmodule EhOsContract.Domain.Rules do
  @moduledoc """
  The rules a domain module must satisfy to compile: v2 §6, layer L2, rules D1–D5.

  A transformer, not a verifier, and every violation is reported at once, in one
  error that names each declaration's file and line (`EhOsContract.DslRules`).
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Domain.Dsl
  alias EhOsContract.DslRules
  alias EhOsContract.Domain.Dsl.{Actor, Context, External, Relation, Subject, Value}
  alias Spark.Dsl.Transformer

  @impl true
  def before?(EhOsContract.Domain.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:domain])
    domain = Transformer.get_persisted(dsl, :eh_os_contract_domain)

    DslRules.result(dsl, [:domain], Enum.flat_map(rules(), & &1.(entities, domain)))
  end

  defp rules, do: [&d1/2, &d2/2, &d3/2, &d4/2, &d5/2]

  # --- D1: names are unique per kind ---------------------------------------------

  @kinds [
    {Context, "context"},
    {Actor, "actor"},
    {Subject, "subject"},
    {Value, "value"},
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

    by_kind ++ terms ++ relations
  end

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
    options = Enum.flat_map(values, &field_options(&1, subjects))
    shape ++ options ++ cycles(values, names)
  end

  # A value's fields may say whose personal data they hold (v2 §4.3, §14), and
  # those options are checked here with the rule letters v2 §6 gives them. F3: a
  # default belongs only to a contract's state. F5: `personal: f` needs `f` to be
  # a required, non-personal `:id` field of the same value declaring `subject:`,
  # and that subject must be declared.
  defp field_options(value, subjects) do
    by_name = Map.new(value.fields, &{&1.name, &1})

    for field <- value.fields,
        violation <- field_option_violations(value, field, by_name, subjects) do
      violation
    end
  end

  defp field_option_violations(value, field, by_name, subjects) do
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

        {:ok, %{type: :id, subject: subject, personal: nil}} when subject != nil ->
          []

        {:ok, _} ->
          [
            {"F5: #{where} is personal to #{inspect(field.personal)}, which is not an :id field " <>
               "declaring a subject", field}
          ]
      end

    default ++ subject ++ personal
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

    one_of ++ unit ++ context ++ types ++ fields
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

  @doc false
  @spec type_problems(term(), MapSet.t(atom())) :: [String.t()]
  def type_problems(type, _values) when type in @built_in, do: []

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

  # --- D4: a person is not backed by a system ------------------------------------

  defp d4(entities, _domain) do
    externals = MapSet.new(for %External{name: name} <- entities, do: name)
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)

    for %Actor{} = actor <- entities, violation <- actor_violations(actor, externals, contexts) do
      violation
    end
  end

  defp actor_violations(actor, externals, contexts) do
    where = "D4: actor #{inspect(actor.name)}"

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

    backed_by ++ context
  end

  # --- D5: a relation's roles fit its type, and its ends exist --------------------

  defp d5(entities, _domain) do
    contexts = MapSet.new(for %Context{name: name} <- entities, do: name)

    for %Relation{} = relation <- entities,
        violation <- relation_violations(relation, contexts) do
      violation
    end
  end

  defp relation_violations(%Relation{type: type} = relation, contexts) do
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

    unknown =
      for name <- Enum.uniq(ends), not MapSet.member?(contexts, name) do
        {"#{where} names context #{inspect(name)}, which this domain does not declare", relation}
      end

    itself =
      if roles == [] and length(Enum.uniq(ends)) == 1,
        do: [{"#{where} relates context #{inspect(hd(ends))} to itself", relation}],
        else: []

    roles ++ unknown ++ itself
  end

  defp duplicates(list, key), do: DslRules.duplicates(list, key)
end
