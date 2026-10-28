defmodule EhOsContract.Domain.Build do
  # Builds a domain's model and compiles it into the module as
  # `__eh_os_contract_model__/0` (v2 §9).
  #
  # Runs last, after every rule has passed, so the model is only ever built from a
  # domain that is well formed.
  #
  # The model is plain data: maps, lists, atoms, strings, and tuples only where the
  # declaration itself holds one. Spark's structs and source annotations stay behind.
  # **Collections keep declaration order**, because readers print in it (E1's
  # correction to v2 §9). **The digest does not see that order.** A domain is a set of
  # declarations, so `version` and each entry of `digests` are computed over a form
  # where every collection of declarations is sorted, nested ones included: a
  # context's terms, a term's translations, a value's fields. Moving a declaration
  # therefore moves nothing. Changing one moves the version and that declaration's
  # digest, and nothing else. The domain's own `name:` and `language:` are covered as
  # well, under the digest key `"domain:<name>"`.
  @moduledoc false

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias Spark.Dsl.Transformer

  @built_in EhOsContract.Domain.Rules.built_in_types()

  @kinds [
    subdomains: :subdomain,
    contexts: :context,
    actors: :actor,
    subjects: :subject,
    values: :value,
    externals: :external,
    relations: :relation,
    entities: :entity
  ]

  @impl true
  def transform(dsl) do
    model = model(dsl)
    types = Enum.map(model.values, &value_type(&1, model.module))

    behaviours =
      for value <- model.values,
          value.invariants != [] or value.type == nil,
          do: value_module(model, value)

    members = enum_members(model.values)

    # One clause per enum value, not a lookup in a map literal: in a domain with no enum,
    # the type checker of a newer Elixir sees the empty map and warns that the lookup
    # can never succeed.
    member_clauses =
      for {name, labelled} <- Enum.sort(members) do
        quote do: def(members(unquote(name)), do: unquote(Macro.escape(labelled)))
      end

    {:ok,
     Transformer.eval(
       dsl,
       [],
       quote do
         @doc false
         def __eh_os_contract_model__, do: unquote(Macro.escape(model))

         # The values by name, each made of fields with its struct's module: what
         # `EhOsContract.Codec.values/1` reads on every dispatch, built once here, and kept
         # out of the model so that naming the struct moves no digest.
         @doc false
         def __eh_os_contract_values__, do: unquote(Macro.escape(values_by_name(model)))

         defmodule Values do
           @moduledoc """
           One type per value of `#{inspect(unquote(model.module))}`, generated from its
           declarations. Contracts refer to them as remote types, which records no
           compile dependency.
           """

           unquote_splicing(types)
         end

         unquote_splicing(behaviours)

         @doc """
         The members of an enum this domain declares as a value, in the order declared, each
         with its label, or `nil` when it has none: what a select offers, or a check accepts,
         read from the domain rather than copied. For
         `value :service, {:enum, [parcel: "Parcel", freight: "Freight"]}`,
         `members(:service)` is `[parcel: "Parcel", freight: "Freight"]`.

         A value named after another enum value has that value's members. Raises
         `ArgumentError` for a name that is no value of this domain, or a value that is not
         an enum.
         """
         @spec members(atom()) :: [{atom(), String.t() | nil}]
         def members(value)

         unquote_splicing(member_clauses)

         def members(value) do
           raise ArgumentError,
                 "#{inspect(value)} is no enum value of #{inspect(__MODULE__)}; its enum " <>
                   "values are #{inspect(unquote(members |> Map.keys() |> Enum.sort()))}"
         end

         @doc "Binds a value's invariants to their checks: `EhOsContract.Implementation`."
         defmacro __using__(opts),
           do: EhOsContract.Implementation.bind(__MODULE__, opts, __CALLER__)
       end
     )}
  end

  # `D.Values.Money`, the one module of a value: one callback per invariant of
  # `value :money`, taking a value of the type and answering whether it keeps the
  # invariant (plan EL2b), written from `EhOsContract.Contract.Callbacks`, the list
  # `use D, value: :money` checks against; and, for a value made of fields, its struct
  # (#486), whose required fields are enforced, so `%Address{}` without one does not
  # compile.
  defp value_module(model, value) do
    module = Module.concat([model.module, Values, Macro.camelize(Atom.to_string(value.name))])
    %{callbacks: callbacks} = EhOsContract.Contract.Callbacks.of(model, :value, value.name)
    labels = Map.new(value.invariants, &{&1.name, &1.label})

    specs =
      for c <- callbacks do
        quote do
          @doc unquote(Map.fetch!(labels, c.name))
          @callback unquote(c.name)(unquote_splicing(c.args)) :: unquote(c.returns)
        end
      end

    rules =
      "What an implementation of value `#{inspect(value.name)}` of `#{inspect(model.module)}` " <>
        "defines, generated from its invariants: one function each, answering whether a " <>
        "value of the type keeps it. Bound with `use #{inspect(model.module)}, value: " <>
        "#{inspect(value.name)}`."

    doc =
      case {value.type, value.invariants} do
        {nil, []} -> struct_doc(model, value)
        {nil, _invariants} -> struct_doc(model, value) <> "\n\n" <> rules
        {_type, _invariants} -> rules
      end

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(doc)
        unquote(
          if value.type == nil, do: value_struct(value, Module.concat(model.module, Values))
        )

        unquote_splicing(specs)
      end
    end
  end

  defp struct_doc(model, value),
    do:
      "Value `#{inspect(value.name)}` of `#{inspect(model.module)}`, generated from its " <>
        "fields: the struct the engine hands a consumer wherever the value appears."

  # The struct of a value made of fields, its fields in the order declared. A personal
  # field may hold what it reads back as once its subject is erased (v2 §14).
  defp value_struct(value, values) do
    enforce = for f <- value.fields, not f.optional, do: f.name

    types =
      for field <- value.fields do
        type = remote(field.type, values)

        type =
          if field.personal, do: quote(do: unquote(type) | EhOsContract.Erased.t()), else: type

        {field.name, if(field.optional, do: quote(do: unquote(type) | nil), else: type)}
      end

    quote do
      @enforce_keys unquote(enforce)
      defstruct unquote(Enum.map(value.fields, & &1.name))
      @type t :: %__MODULE__{unquote_splicing(types)}
    end
  end

  defp values_by_name(model) do
    Map.new(model.values, fn
      %{type: nil, name: name} = value ->
        {name,
         Map.put(
           value,
           :struct,
           Module.concat([model.module, Values, Macro.camelize(Atom.to_string(name))])
         )}

      value ->
        {value.name, value}
    end)
  end

  # `%{service: [parcel: "Parcel", freight: nil]}`: every value that is an enum, or names
  # one, with its members labelled, for the generated `members/1` (#472).
  defp enum_members(values) do
    by_name = Map.new(values, &{&1.name, &1.type})

    for %{name: name} <- values,
        {:enum, members} <- [enum_of(Map.get(by_name, name), by_name)],
        into: %{},
        do: {name, Enum.map(members, &labelled/1)}
  end

  defp enum_of({:enum, _members} = enum, _by_name), do: enum

  defp enum_of(name, by_name) when is_atom(name) and is_map_key(by_name, name),
    do: enum_of(Map.fetch!(by_name, name), by_name)

  defp enum_of(_type, _by_name), do: nil

  defp labelled({member, label}), do: {member, label}
  defp labelled(member), do: {member, nil}

  # `value :money, :integer` becomes `@type money :: integer()`; a value with fields
  # becomes its struct's type, `@type address :: D.Values.Address.t()` (#486).
  defp value_type(%{name: name, type: nil}, domain) do
    module = Module.concat([domain, Values, Macro.camelize(Atom.to_string(name))])
    quote do: @type(unquote({name, [], []}) :: unquote(module).t())
  end

  defp value_type(%{name: name, type: type}, _domain) do
    quote do: @type(unquote({name, [], []}) :: unquote(typespec(type)))
  end

  # A field's type outside `Values`, where another value is the remote `Values.x()`.
  defp remote({:list, inner}, values), do: quote(do: [unquote(remote(inner, values))])

  defp remote(value, values) when is_atom(value) and value not in @built_in,
    do: quote(do: unquote(values).unquote(value)())

  defp remote(type, _values), do: typespec(type)

  @doc false
  @spec typespec(term()) :: Macro.t()
  def typespec(:id), do: quote(do: String.t())
  def typespec(:string), do: quote(do: String.t())
  def typespec(:integer), do: quote(do: integer())
  def typespec(:decimal), do: quote(do: Decimal.t())
  def typespec(:boolean), do: quote(do: boolean())
  def typespec(:date), do: quote(do: Date.t())
  def typespec(:timestamp), do: quote(do: DateTime.t())
  def typespec({:list, inner}), do: quote(do: [unquote(typespec(inner))])

  def typespec({:enum, members}) do
    members
    |> Enum.map(fn
      {member, _label} -> member
      member -> member
    end)
    |> Enum.reverse()
    |> Enum.reduce(fn member, union -> {:|, [], [member, union]} end)
  end

  # Anything else has passed D3, so it is a value of the same domain.
  def typespec(value) when is_atom(value), do: {value, [], []}

  @doc false
  @spec model(map()) :: map()
  def model(dsl) do
    %{name: name, language: language} =
      persisted = Transformer.get_persisted(dsl, :eh_os_contract_domain)

    time_zone = Map.get(persisted, :time_zone, "Etc/UTC")
    code_language = Map.get(persisted, :code_language, :en)
    entities = Transformer.get_entities(dsl, [:domain])

    collections =
      for {key, entity} <- @kinds, into: %{} do
        {key,
         for(
           %{__struct__: _} = e <- entities,
           entity_name(e) == entity,
           do: built(entity, plain(e))
         )}
      end

    # The domain's own options are part of the agreement too: `language` decides what
    # D2 accepts and which language every label and term is written in.
    # `time_zone` too (plan W2), since it decides which day a timestamp is tagged with;
    # kept out where it is UTC, the default, so no domain written without it moves.
    own = %{name: name, language: language}
    own = if time_zone == "Etc/UTC", do: own, else: Map.put(own, :time_zone, time_zone)

    # `code_language` (plan DD, L1 (#269)) only says which word of a term `check` holds
    # the code to: it is in the model where it is not English, the default, and in no
    # digest, so setting it moves no version.
    collections =
      if code_language == :en,
        do: collections,
        else: Map.put(collections, :code_language, code_language)

    grouped = groups(own, collections)

    Map.merge(collections, %{
      format: 1,
      kind: :domain,
      module: Transformer.get_persisted(dsl, :module),
      name: name,
      language: language,
      time_zone: time_zone,
      # Plan DD, V5 (#322): `version` and `digests` hash what the domain allows,
      # `text_digest` and `text_digests` its words: labels, `source:`, the glossary.
      version: Digest.version(grouped),
      text_digest: Digest.text_digest(grouped),
      digests: digests(own, collections, &Digest.agreement/2),
      text_digests: digests(own, collections, &Digest.words/2)
    })
  end

  defp built(:relation, relation), do: pairs(relation)
  defp built(:entity, entity), do: identified(entity)
  # `code:` is in the model only where a value is one, so no other value's digest moves.
  defp built(:value, %{code: false} = value), do: Map.delete(value, :code)
  defp built(_kind, declaration), do: declaration

  # Plan N1: an entity's identity is a field the library injects, as it injects a
  # unit's: a required, non-personal `:id`, which the entity's `issued_by:` gives when
  # it names an external. The model keeps the issuer on the field, where readers of an
  # identifier look for it, and not twice.
  defp identified(entity) do
    field = %{
      name: entity.identity,
      type: :id,
      optional: false,
      label: nil,
      personal: nil,
      subject: nil,
      default: nil
    }

    # `plain/1` has already left out an `issued_by` that is `nil`; matched here too, so
    # a field without an issuer never carries the key, whatever `plain/1` does.
    field =
      case Map.get(entity, :issued_by) do
        nil -> field
        issuer -> Map.put(field, :issued_by, issuer)
      end

    entity |> Map.delete(:issued_by) |> Map.update!(:fields, &[field | &1])
  end

  defp groups(own, collections) do
    [domain: [own]] ++
      for {key, _entity} <- @kinds, do: {key, Enum.map(collections[key], &digest_form/1)}
  end

  @spec digests(map(), map(), (atom(), map() -> term())) :: %{String.t() => String.t()}
  defp digests(own, collections, of) do
    for {key, entity} <- @kinds, declaration <- collections[key], into: %{} do
      {"#{entity}:#{key_of(entity, declaration)}",
       Digest.hash(of.(key, digest_form(declaration)))}
    end
    |> Map.put("domain:#{own.name}", Digest.hash(of.(:domain, own)))
  end

  defp key_of(:relation, %{type: type} = relation),
    do: "#{type}:#{relation |> endpoints() |> Enum.join(",")}"

  defp key_of(_, %{name: name}), do: to_string(name)

  @doc false
  @spec endpoints(map()) :: [atom()]
  def endpoints(%{between: [_ | _] = between}), do: Enum.sort(between)

  def endpoints(%{upstream: upstream, downstream: downstream}),
    do: Enum.reject([upstream, downstream], &is_nil/1)

  # Every list of declarations inside a declaration is a set: sorted here, and only
  # here. `between` is a pair without a direction, so it is sorted too.
  #
  # A value without invariants hashes as it did before values had them (plan EL2b), so
  # the key moves no domain's version until a value declares one.
  defp digest_form(%{invariants: []} = value),
    do: value |> Map.delete(:invariants) |> digest_form()

  # `code:` only says what `check` reports, as `code_language` does, so a value declared
  # a code allows what it allowed before and hashes as it did (#431).
  defp digest_form(%{code: true} = value),
    do: value |> Map.delete(:code) |> digest_form()

  # Plan EP5b: an actor without responsibilities hashes as before it could have them.
  defp digest_form(%{responsibilities: []} = actor),
    do: actor |> Map.delete(:responsibilities) |> digest_form()

  # And one without a grant rule (`may_grant:`), as before it could have
  # one, so the option moves no domain's version until an actor declares a rule.
  defp digest_form(%{may_grant: []} = actor),
    do: actor |> Map.delete(:may_grant) |> digest_form()

  # A symmetric relation's ends are a set, so its pairs are read in the sorted ends'
  # order: `between: [b, a]` with `{"y", "x"}` is `between: [a, b]` with `{"x", "y"}`.
  defp digest_form(%{between: [a, b], terms: [_ | _] = terms} = relation) when a > b,
    do: digest_form(%{relation | between: [b, a], terms: Enum.map(terms, &Enum.reverse/1)})

  # The same for an external without operations (plan EP5a).
  defp digest_form(%{operations: []} = external),
    do: external |> Map.delete(:operations) |> digest_form()

  defp digest_form(%{} = declaration) do
    Map.new(declaration, fn
      {key, list}
      when key in [
             :terms,
             :translations,
             :avoid,
             :fields,
             :invariants,
             :operations,
             :responsibilities
           ] and
             is_list(list) ->
        {key, list |> Enum.map(&digest_form/1) |> Enum.sort_by(&Digest.canonical/1)}

      {:between, list} ->
        {:between, Enum.sort(list)}

      # A grant rule names a set of actors.
      {:may_grant, list} ->
        {:may_grant, Enum.sort(list)}

      other ->
        other
    end)
  end

  defp digest_form(other), do: other

  defp entity_name(%EhOsContract.Domain.Dsl.Subdomain{}), do: :subdomain
  defp entity_name(%EhOsContract.Domain.Dsl.Context{}), do: :context
  defp entity_name(%EhOsContract.Domain.Dsl.Actor{}), do: :actor
  defp entity_name(%EhOsContract.Domain.Dsl.Subject{}), do: :subject
  defp entity_name(%EhOsContract.Domain.Dsl.Value{}), do: :value
  defp entity_name(%EhOsContract.Domain.Dsl.External{}), do: :external
  defp entity_name(%EhOsContract.Domain.Dsl.Relation{}), do: :relation
  defp entity_name(%EhOsContract.Domain.Dsl.Entity{}), do: :entity

  # Plan EP5b: a relation's terms are pairs, kept as two-element lists, the shape a
  # JSON reader of the model gets as well.
  defp pairs(%{terms: terms} = relation),
    do: %{relation | terms: Enum.map(terms, &Tuple.to_list/1)}

  @doc false
  # A relation's two ends in the order its pairs are read: upstream then downstream,
  # or `between:` as written. D5 and the glossary read pairs through this one place.
  @spec sides(map()) :: [atom()]
  def sides(%{upstream: up, downstream: down}) when up != nil and down != nil, do: [up, down]
  def sides(%{between: between}), do: between

  # A Spark struct becomes a plain map, recursively, without the struct tag and
  # without the source annotation.
  @doc false
  @spec plain(term()) :: term()
  def plain(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Map.new(fn {key, value} -> {key, plain(value)} end)
    |> reference()
  end

  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(other), do: other

  @doc false
  # A field declared `{:id, entity}` is an `:id` in the model, as it is in the log,
  # and says which entity it identifies in `refers_to` (plan EM2), a key only such a
  # field has, so no other field's digest moves. Every reader of types — the codec,
  # tags, typespecs — therefore sees a plain `:id`.
  @spec reference(map()) :: map()
  #
  # `issued_by` (plan EL2) is kept only where a field declares it, for the same reason.
  def reference(%{name: _, type: {:id, entity}} = field) when is_atom(entity),
    do: field |> Map.put(:type, :id) |> Map.put(:refers_to, entity) |> issuer()

  def reference(%{name: _, type: {:list, {:id, entity}}} = field) when is_atom(entity),
    do: field |> Map.put(:type, {:list, :id}) |> Map.put(:refers_to, entity) |> issuer()

  def reference(map), do: issuer(map)

  defp issuer(%{issued_by: nil} = field), do: Map.delete(field, :issued_by)
  defp issuer(map), do: map
end
