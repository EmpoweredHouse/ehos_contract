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
  digest, and nothing else.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias Spark.Dsl.Transformer

  @kinds [
    contexts: :context,
    actors: :actor,
    subjects: :subject,
    values: :value,
    externals: :external,
    relations: :relation
  ]

  @impl true
  def transform(dsl) do
    model = model(dsl)

    {:ok,
     Transformer.eval(
       dsl,
       [],
       quote do
         @doc false
         def __eh_os_contract_model__, do: unquote(Macro.escape(model))
       end
     )}
  end

  @doc false
  @spec model(map()) :: map()
  def model(dsl) do
    %{name: name, language: language} = Transformer.get_persisted(dsl, :eh_os_contract_domain)
    entities = Transformer.get_entities(dsl, [:domain])

    collections =
      for {key, entity} <- @kinds, into: %{} do
        {key, for(%{__struct__: _} = e <- entities, entity_name(e) == entity, do: plain(e))}
      end

    Map.merge(collections, %{
      format: 1,
      kind: :domain,
      module: Transformer.get_persisted(dsl, :module),
      name: name,
      language: language,
      version:
        Digest.hash_groups(
          for {key, _} <- @kinds, do: {key, Enum.map(collections[key], &digest_form/1)}
        ),
      digests: digests(collections)
    })
  end

  @spec digests(map()) :: %{String.t() => String.t()}
  defp digests(collections) do
    for {key, entity} <- @kinds, declaration <- collections[key], into: %{} do
      {"#{entity}:#{key_of(entity, declaration)}", Digest.hash(digest_form(declaration))}
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
  defp digest_form(%{} = declaration) do
    Map.new(declaration, fn
      {key, list} when key in [:terms, :translations, :avoid, :fields] and is_list(list) ->
        {key, list |> Enum.map(&digest_form/1) |> Enum.sort_by(&Digest.canonical/1)}

      {:between, list} ->
        {:between, Enum.sort(list)}

      other ->
        other
    end)
  end

  defp digest_form(other), do: other

  defp entity_name(%EhOsContract.Domain.Dsl.Context{}), do: :context
  defp entity_name(%EhOsContract.Domain.Dsl.Actor{}), do: :actor
  defp entity_name(%EhOsContract.Domain.Dsl.Subject{}), do: :subject
  defp entity_name(%EhOsContract.Domain.Dsl.Value{}), do: :value
  defp entity_name(%EhOsContract.Domain.Dsl.External{}), do: :external
  defp entity_name(%EhOsContract.Domain.Dsl.Relation{}), do: :relation

  # A Spark struct becomes a plain map, recursively, without the struct tag and
  # without the source annotation.
  @doc false
  @spec plain(term()) :: term()
  def plain(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Map.new(fn {key, value} -> {key, plain(value)} end)
  end

  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(other), do: other
end
