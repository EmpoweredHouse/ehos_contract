defmodule EhOsContract.DslRules do
  @moduledoc """
  How the library's DSLs report a broken rule (v2 §6, layer L2).

  A rule is a transformer, not a verifier: Spark turns a verifier's error into a
  warning and does not re-run verifiers on an incremental compile, so a rule written
  as one would hold only sometimes. A transformer's error stops the compilation.

  Every violation found is reported, not only the first. They come in one
  `Spark.Error.DslError`: its location is the first violation's, and its message
  lists every violation with the file and line of the declaration at fault. A
  violation is `{message, declaration}`, where the declaration is the Spark struct
  whose source annotation says where it was written, or that annotation itself, for
  what no struct holds, such as an option of `use`.
  """

  @typedoc "A broken rule, and the declaration it points at, or where it was written."
  @type violation :: {String.t(), struct() | :erl_anno.anno()}

  @doc """
  `{:ok, dsl}` when there are no violations, and otherwise the one error that
  reports them all.
  """
  @spec result(map(), [atom()], [violation()]) :: {:ok, map()} | {:error, Exception.t()}
  def result(dsl, _path, []), do: {:ok, dsl}

  def result(dsl, path, [{_, first} | _] = violations) do
    {:error,
     Spark.Error.DslError.exception(
       module: Spark.Dsl.Transformer.get_persisted(dsl, :module),
       path: path,
       location: anno(first),
       message: Enum.map_join(violations, "\n  ", &describe/1)
     )}
  end

  @doc """
  Every item whose key an earlier item already had, in declaration order: the later
  declaration is the one to move or rename.
  """
  @spec duplicates([item], (item -> term())) :: [item] when item: term()
  def duplicates(list, key) do
    {_, repeated} =
      Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, repeated} ->
        k = key.(item)

        if MapSet.member?(seen, k),
          do: {seen, [item | repeated]},
          else: {MapSet.put(seen, k), repeated}
      end)

    Enum.reverse(repeated)
  end

  @doc """
  The name in `names` closest to `name`, for a did-you-mean, or `nil` when none is
  close enough to be the one meant.
  """
  @spec closest(atom(), [atom()]) :: atom() | nil
  def closest(name, names) do
    names
    |> Enum.map(&{&1, String.jaro_distance(Atom.to_string(name), Atom.to_string(&1))})
    |> Enum.filter(fn {_, distance} -> distance > 0.8 end)
    |> Enum.max_by(fn {_, distance} -> distance end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp anno(%_{} = declaration), do: Spark.Dsl.Entity.anno(declaration)
  defp anno(anno), do: anno

  defp describe({message, declaration}) do
    case anno(declaration) do
      nil ->
        message

      anno ->
        file = anno |> :erl_anno.file() |> to_string() |> Path.relative_to_cwd()
        "#{message} (#{file}:#{:erl_anno.line(anno)})"
    end
  end
end
