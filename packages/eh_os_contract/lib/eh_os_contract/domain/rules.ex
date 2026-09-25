defmodule EhOsContract.Domain.Rules do
  @moduledoc """
  The rules a domain module must satisfy to compile: v2 §6, layer L2, rules D1–D5.

  A transformer, not a verifier. Spark turns a verifier's error into a warning and
  does not re-run verifiers on an incremental compile, so a rule written as one would
  hold only sometimes (v2 §6). A transformer's error stops the compilation.

  Every violation found is reported, not only the first. They come in one
  `Spark.Error.DslError`: its location is the first violation's, and its message
  lists every violation with the file and line of the declaration at fault.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Domain.Dsl.{Actor, Context, External, Subject, Value}
  alias Spark.Dsl.Transformer

  @impl true
  def before?(EhOsContract.Domain.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    entities = Transformer.get_entities(dsl, [:domain])

    case Enum.flat_map(rules(), & &1.(entities)) do
      [] ->
        {:ok, dsl}

      [{_, first} | _] = violations ->
        {:error,
         Spark.Error.DslError.exception(
           module: Transformer.get_persisted(dsl, :module),
           path: [:domain],
           location: anno(first),
           message: Enum.map_join(violations, "\n  ", &describe/1)
         )}
    end
  end

  defp rules, do: [&d1/1]

  # --- D1: names are unique per kind ---------------------------------------------

  @kinds [
    {Context, "context"},
    {Actor, "actor"},
    {Subject, "subject"},
    {Value, "value"},
    {External, "external"}
  ]

  defp d1(entities) do
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

    by_kind ++ terms
  end

  # Every occurrence after the first, in declaration order: the later declaration is
  # the one to move or rename.
  defp duplicates(list, key) do
    {_, repeated} =
      Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, repeated} ->
        k = key.(item)

        if MapSet.member?(seen, k),
          do: {seen, [item | repeated]},
          else: {MapSet.put(seen, k), repeated}
      end)

    Enum.reverse(repeated)
  end

  # --- reporting -----------------------------------------------------------------

  defp anno(entity), do: Spark.Dsl.Entity.anno(entity)

  defp describe({message, entity}) do
    case anno(entity) do
      nil ->
        message

      anno ->
        file = anno |> :erl_anno.file() |> to_string() |> Path.relative_to_cwd()
        "#{message} (#{file}:#{:erl_anno.line(anno)})"
    end
  end
end
