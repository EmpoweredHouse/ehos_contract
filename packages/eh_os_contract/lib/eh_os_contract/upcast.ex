defmodule EhOsContract.Upcast do
  # Plan DD, V1 (#333): a row of the log read in the shape its event declares today. The
  # log is never rewritten; a row written with an older version of the event's fields
  # goes through the event's steps (`upcast`), from its own version up, each renaming
  # fields and giving a value to those its version did not have.
  #
  # A sealed personal field is sealed under its path (the AEAD's associated data holds
  # it, `EhOsContract.Personal`), so a renamed one opens under the name it was sealed
  # with: `read/2` gives, beside the payload, the path each renamed field was written
  # under, the renames of every step composed — version 1's `a`, renamed `b` and then
  # `c`, opens as `a`. A step renames and defaults top-level fields only, so a path is a
  # field's name.
  #
  # A step by a function (`function:`, plan DD, V2, #338) calls the unit's implementation with
  # the payload and takes the map it gives. The engine cannot see what it did, so it holds
  # the result to what it can see: a sealed value stays where it was or goes, and is never
  # moved or made, since a seal opens only under the path it was sealed with; a field the
  # log tags rows with keeps its value, since old rows keep their tags. What breaks either,
  # or raises, or gives no map, refuses the row, naming the step and never a value.
  @moduledoc false

  alias EhOsContract.Key

  @typedoc "The path a field of the current version was written under, where it differs."
  @type paths :: %{String.t() => String.t()}

  @doc false
  # The row's payload in the declaration's version, and the path each renamed field was
  # written under. A row at the declared version, or with no payload, is as it is; a row
  # newer than the declaration is the caller's to refuse first (`Consumer.current!/2`).
  # `implementation` gives the unit's implementation, asked only for a step by a function;
  # `values` are the domain's, which say which fields of a value the log tags.
  @spec read(map(), EhOsContract.Event.t(), (-> module()) | nil, map()) :: {map(), paths()}
  def read(
        declaration,
        %{schema_version: written, payload: payload} = row,
        implementation \\ nil,
        values \\ %{}
      ) do
    steps =
      for step <- Map.get(declaration, :upcasts, []),
          is_integer(written) and step.from >= written and step.from < declaration.schema_version,
          do: step

    Enum.reduce(steps, {payload || %{}, %{}}, fn
      %{function: fun} = step, {data, paths} ->
        {called(declaration, row, step, fun, implementation, values, data), paths}

      step, acc ->
        step(step, acc)
    end)
  end

  defp called(declaration, row, step, fun, implementation, values, data) do
    module =
      implementation ||
        raise ArgumentError, "#{where(row, step)} names #{fun}/1, and no implementation was given"

    module = module.()

    result =
      try do
        apply(module, fun, [data])
      rescue
        exception ->
          raise ArgumentError,
                "#{where(row, step)}: #{inspect(module)}.#{fun}/1 raised " <>
                  "#{inspect(exception.__struct__)}"
      end

    unless is_map(result) do
      raise ArgumentError, "#{where(row, step)}: #{inspect(module)}.#{fun}/1 gave no map"
    end

    sealed!(row, step, data, result)
    tagged!(declaration, row, step, data, result, values)
    result
  end

  # A seal of the result is one of the input's, at the same field.
  defp sealed!(row, step, data, result) do
    before = seals(data)

    for {path, seal} <- seals(result), Map.get(before, path) != seal do
      raise ArgumentError,
            "#{where(row, step)}: the function puts a sealed value at #{path} that the row " <>
              "did not hold there; a seal opens only under the field it was sealed in, so a " <>
              "personal field is renamed with `rename:`"
    end

    :ok
  end

  defp tagged!(declaration, row, step, data, result, values) do
    for field <- declaration.fields,
        Key.tag_field?(field, values) or Key.bucket_field?(field, values),
        name = Atom.to_string(field.name),
        Map.get(data, name) != Map.get(result, name) do
      raise ArgumentError,
            "#{where(row, step)}: the function changes #{name}, which the log tags each row " <>
              "with; rows written before keep their tags"
    end

    :ok
  end

  # Every sealed value of `data`, by its path, inside values and lists too.
  defp seals(data, path \\ []) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      Map.merge(acc, seals_in(value, path ++ [to_string(key)]))
    end)
  end

  defp seals_in(%{"$eh" => _} = seal, path), do: %{Enum.join(path, ".") => seal}
  defp seals_in(%{} = map, path), do: seals(map, path)

  defp seals_in(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, i}, acc ->
      Map.merge(acc, seals_in(value, path ++ [to_string(i)]))
    end)
  end

  defp seals_in(_value, _path), do: %{}

  defp where(row, step),
    do:
      "the event at position #{row_position(row)} (#{row_type(row)}), `upcast from: #{step.from}`"

  defp row_position(row), do: Map.get(row, :position)
  defp row_type(row), do: Map.get(row, :type)

  # One step: the old names move to their new ones all at once — a step may rename `a`
  # to `b` and `b` to `c` — the path each was written under going with it; then a field
  # the row does not hold takes its default. A row that already holds a field keeps its
  # own value: the default stands for a version that had none.
  defp step(%{rename: rename, default: default}, {payload, paths}) do
    moves =
      for {old, new} <- rename,
          old = Atom.to_string(old),
          Map.has_key?(payload, old),
          do: {old, Atom.to_string(new)}

    olds = Enum.map(moves, &elem(&1, 0))

    data =
      Enum.reduce(moves, Map.drop(payload, olds), fn {old, new}, data ->
        Map.put(data, new, Map.fetch!(payload, old))
      end)

    paths =
      Enum.reduce(moves, Map.drop(paths, olds), fn {old, new}, acc ->
        Map.put(acc, new, Map.get(paths, old, old))
      end)

    data =
      Enum.reduce(default, data, fn {field, value}, data ->
        Map.put_new(data, Atom.to_string(field), value)
      end)

    {data, paths}
  end

  @doc false
  # `open`, an opener of `EhOsContract.Codec.decode/4`, asked for each renamed field under
  # the path it was sealed with: a field's own, or, inside a value or a list, the path
  # below its field's old name.
  @spec opener(EhOsContract.Codec.open() | nil, paths()) :: EhOsContract.Codec.open() | nil
  def opener(open, paths) when paths == %{} or is_nil(open), do: open

  def opener(open, paths) do
    fn path, subject, sealed ->
      [top | below] = String.split(path, ".", parts: 2)
      open.(Enum.join([Map.get(paths, top, top) | below], "."), subject, sealed)
    end
  end
end
