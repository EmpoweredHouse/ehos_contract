defmodule EhosContract.DslRules do
  # How the library's DSLs report a broken rule (v2 §6, layer L2).
  #
  # A rule is a transformer, not a verifier: Spark turns a verifier's error into a
  # warning and does not re-run verifiers on an incremental compile, so a rule written
  # as one would hold only sometimes. A transformer's error stops the compilation.
  #
  # Every violation found is reported, not only the first. They come in one
  # `Spark.Error.DslError`: its location is the first violation's, and its message
  # lists every violation with the file and line of the declaration at fault. A
  # violation is `{message, declaration}`, where the declaration is the Spark struct
  # whose source annotation says where it was written, or that annotation itself, for
  # what no struct holds, such as an option of `use`, or `nil` for a violation of the
  # whole module, which has no line to point at.
  @moduledoc false

  # `\z`, not `$`, which also matches before a final newline.
  @namespace ~r/^[a-z]([-a-z0-9_]*[a-z0-9_])?\z/
  @snake_case ~r/^[a-z][a-z0-9_]*\z/

  @typedoc "A broken rule, and the declaration it points at, or where it was written."
  @type violation :: {String.t(), struct() | :erl_anno.anno() | nil}

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

  @doc false
  # Each item whose snake_case name camelizes as an earlier, different name does, with
  # that earlier name and the camelized form, once per name: `Macro.camelize` drops a
  # trailing `_`, an `_` before a digit and a doubled `_`, so `:paid` and `:paid_`
  # would be one generated module and one alias. Two of one name are the caller's.
  @spec camel_collisions([item], (item -> atom())) :: [{item, atom(), String.t()}]
        when item: term()
  def camel_collisions(items, name) do
    named = Enum.filter(items, &name?(name.(&1)))
    first = Enum.reduce(Enum.reverse(named), %{}, &Map.put(&2, camelize(name.(&1)), name.(&1)))

    # In declaration order, so the error's location is the earliest collision.
    for item <- Enum.uniq_by(named, name),
        camel = camelize(name.(item)),
        Map.fetch!(first, camel) != name.(item),
        do: {item, Map.fetch!(first, camel), camel}
  end

  defp camelize(name), do: name |> Atom.to_string() |> Macro.camelize()

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

  @doc """
  Every declaration in `entities`, at any depth, whose label is given and blank —
  empty, or only whitespace — refused under `code`. The schema of a label is a
  string, which `""` is, and a blank label leaves a page, a graph's node or a
  report's sentence with nothing saying what the business calls the declaration.

  Every declaration of the library's DSLs with a `label` is asked, so one added later is
  covered without being listed here. An optional label left out is `nil`, and passes.
  Only the DSLs' own structs are walked: a struct in a scenario's rows or an
  invariant's examples is data, and its fields are not declarations.
  """
  @spec blank_labels([struct()], String.t()) :: [violation()]
  def blank_labels(entities, code) do
    for %{label: label} = declaration <- labelled(entities), blank?(label), uniq: true do
      {"#{code}: #{kind(declaration)} #{inspect(Map.get(declaration, :name))} has a blank " <>
         "label; say what the business calls it", declaration}
    end
  end

  # Unicode whitespace, and the format characters (Cf) a copy from a board export
  # brings along — zero-width spaces and joiners, direction marks and isolates, the
  # byte order mark — which `String.trim/1` keeps and a page prints as nothing.
  @blank ~r/\A[\s\p{Cf}]*\z/u

  @doc """
  Whether `text` is a string that says nothing: empty, or only Unicode whitespace and
  invisible format characters.
  """
  @spec blank?(term()) :: boolean()
  def blank?(text), do: is_binary(text) and text =~ @blank

  defp labelled(list) when is_list(list), do: Enum.flat_map(list, &labelled/1)

  defp labelled(%struct{} = declaration) do
    if declaration?(struct) do
      own = if Map.has_key?(declaration, :label), do: [declaration], else: []

      nested =
        declaration
        |> Map.drop([:__struct__, :__spark_metadata__])
        |> Map.values()
        |> Enum.flat_map(&labelled/1)

      own ++ nested
    else
      []
    end
  end

  defp labelled(_other), do: []

  defp declaration?(struct) do
    case Module.split(struct) do
      ["EhosContract", dsl, "Dsl" | _] when dsl in ["Contract", "Domain", "Process"] -> true
      _other -> false
    end
  end

  # What a refusal calls a declaration: its struct's name in words, where that is
  # not the word the DSL writes.
  defp kind(%{__struct__: struct} = declaration) do
    case {struct |> Module.split() |> List.last(), Map.get(declaration, :kind)} do
      {"Unit", :aggregate} -> "aggregate"
      {"Unit", :dcb} -> "dcb"
      {"ServiceFunction", _} -> "function"
      {"ValueInvariant", _} -> "invariant"
      {name, _} -> name |> Macro.underscore() |> String.replace("_", " ")
    end
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
