defmodule EhOsContract.Domain.Build do
  @moduledoc """
  Builds a domain's model and compiles it into the module as
  `__eh_os_contract_model__/0` (v2 §9).

  Runs last, after every rule has passed, so the model is only ever built from a
  domain that is well formed.

  The model is plain data: maps, lists, atoms, strings, and tuples only where the
  declaration itself holds one. Spark's structs and source annotations stay behind.
  **Collections keep declaration order**, because readers print in it (E1's
  correction to v2 §9). **The digest does not see that order.** A domain is a set of
  declarations, so `version` and each entry of `digests` are computed over a form
  where every collection of declarations is sorted, nested ones included: a
  context's terms, a term's translations, a value's fields. Moving a declaration
  therefore moves nothing. Changing one moves the version and that declaration's
  digest, and nothing else. The domain's own `name:` and `language:` are covered as
  well, under the digest key `"domain:<name>"`.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias Spark.Dsl.Transformer

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

  # Kinds that came after the first domains were digested: a domain that declares
  # none of one hashes as it did before the kind existed, so adding a kind to the
  # library moves no domain's version.
  @later [:entities]

  @impl true
  def transform(dsl) do
    model = model(dsl)
    types = Enum.map(model.values, &value_type/1)
    behaviours = for %{invariants: [_ | _]} = value <- model.values, do: behaviour(model, value)

    {:ok,
     Transformer.eval(
       dsl,
       [],
       quote do
         @doc false
         def __eh_os_contract_model__, do: unquote(Macro.escape(model))

         defmodule Values do
           @moduledoc """
           One type per value of `#{inspect(unquote(model.module))}`, generated from its
           declarations. Contracts refer to them as remote types, which records no
           compile dependency (v2 §5).
           """

           unquote_splicing(types)
         end

         unquote_splicing(behaviours)

         @doc "Binds a value's invariants to their checks: `EhOsContract.Implementation`."
         defmacro __using__(opts),
           do: EhOsContract.Implementation.bind(__MODULE__, opts, __CALLER__)
       end
     )}
  end

  # `D.Values.Money`: one callback per invariant of `value :money`, taking a value of
  # the type and answering whether it keeps the invariant (plan EL2b). Written from
  # `EhOsContract.Contract.Callbacks`, the list `use D, value: :money` checks
  # against.
  defp behaviour(model, value) do
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

    doc =
      "What an implementation of value `#{inspect(value.name)}` of `#{inspect(model.module)}` " <>
        "defines, generated from its invariants: one function each, answering whether a " <>
        "value of the type keeps it. Bound with `use #{inspect(model.module)}, value: " <>
        "#{inspect(value.name)}`."

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(doc)
        unquote_splicing(specs)
      end
    end
  end

  # `value :money, :integer` becomes `@type money :: integer()`; a value with fields
  # becomes a map type with one key per field. A personal field may hold what it
  # reads back as once its subject is erased (v2 §14).
  defp value_type(%{name: name, type: nil, fields: fields}) do
    pairs =
      for field <- fields do
        type = typespec(field.type)

        type =
          if field.personal, do: quote(do: unquote(type) | EhOsContract.Erased.t()), else: type

        {field.name, if(field.optional, do: quote(do: unquote(type) | nil), else: type)}
      end

    quote do: @type(unquote({name, [], []}) :: %{unquote_splicing(pairs)})
  end

  defp value_type(%{name: name, type: type}) do
    quote do: @type(unquote({name, [], []}) :: unquote(typespec(type)))
  end

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
    %{name: name, language: language} = Transformer.get_persisted(dsl, :eh_os_contract_domain)
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
    own = %{name: name, language: language}

    Map.merge(collections, %{
      format: 1,
      kind: :domain,
      module: Transformer.get_persisted(dsl, :module),
      name: name,
      language: language,
      version:
        Digest.hash_groups(
          [domain: [own]] ++
            for(
              {key, entity} <- @kinds,
              key not in @later or collections[key] != [],
              do: {key, Enum.map(collections[key], &digest_form(sourced(&1, entity)))}
            )
        ),
      digests: Map.put(digests(collections), "domain:#{name}", Digest.hash(own))
    })
  end

  defp built(:relation, relation), do: pairs(relation)
  defp built(:entity, entity), do: identified(entity)
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

  # Kinds that took `source:` after their first domains were digested (plan EP1): a
  # `nil` one is left out of the digest, so no declaration written without it moves.
  # The model keeps the key, `nil` or not, as it does for every other kind.
  @sourced_later [:actor, :subject, :value, :external, :relation]

  defp sourced(%{source: nil} = declaration, entity) when entity in @sourced_later,
    do: Map.delete(declaration, :source)

  defp sourced(declaration, _entity), do: declaration

  @spec digests(map()) :: %{String.t() => String.t()}
  defp digests(collections) do
    for {key, entity} <- @kinds, declaration <- collections[key], into: %{} do
      {"#{entity}:#{key_of(entity, declaration)}",
       Digest.hash(digest_form(sourced(declaration, entity)))}
    end
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

  # Plan EP5b: an actor without responsibilities hashes as before it could have them.
  defp digest_form(%{responsibilities: []} = actor),
    do: actor |> Map.delete(:responsibilities) |> digest_form()

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
