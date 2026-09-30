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

  # `\z`, not `$`, which also matches before a final newline.
  @namespace ~r/^[a-z]([-a-z0-9_]*[a-z0-9_])?\z/
  @snake_case ~r/^[a-z][a-z0-9_]*\z/

  @typedoc "A broken rule, and the declaration it points at, or where it was written."
  @type violation :: {String.t(), struct() | :erl_anno.anno()}

  @doc false
  # One segment of an application's namespace (D11): a domain's `name:`, and the first
  # segment of every name its contracts publish or consume. One pattern for both, so a
  # domain cannot compile under a name none of its publications could start with.
  @spec namespace?(term()) :: boolean()
  def namespace?(segment), do: is_binary(segment) and segment =~ @namespace

  @doc false
  # A snake_case name, as text: what a contract's names (N1), a domain's actors (D4), a
  # value's invariants (D9) and a page's path are held to. One pattern, so that a
  # newline let through by one of them cannot be let through by another.
  @spec snake_case?(term()) :: boolean()
  def snake_case?(text), do: is_binary(text) and text =~ @snake_case

  @doc false
  # A declared name that is snake_case: an atom, but not `nil`, `true` or `false`,
  # whose text fits.
  @spec name?(term()) :: boolean()
  def name?(name),
    do: is_atom(name) and name not in [nil, true, false] and snake_case?(Atom.to_string(name))

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
