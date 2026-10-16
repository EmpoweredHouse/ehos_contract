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
  # the payload and takes the map it gives, as the log stores one (through JSON). The engine
  # cannot see what it did, so it holds the result to what it can see: a sealed value stays
  # where it was or goes, and is never moved or made, since a seal opens only under the path
  # it was sealed with; a field the log tags rows with holds what the row was written with,
  # since its tags were made from that. What breaks either, or raises, throws or exits, or
  # gives no map, refuses the row, naming the step and never a value.
  @moduledoc false

  alias EhOsContract.Key

  @typedoc "The path a field of the current version was written under, where it differs."
  @type paths :: %{String.t() => String.t()}

  @doc false
  # The row's payload in the declaration's version, and the path each renamed field was
  # written under. A row at the declared version, or with no payload, is as it is; a row
  # newer than the declaration is the caller's to refuse first (`Consumer.current!/2`).
  # `implementation` gives the unit's implementation and `values` the domain's values,
  # which say which fields of a value the log tags; each is a function, asked only for a
  # step by a function.
  @spec read(map(), EhOsContract.Event.t(), (-> module()) | nil, (-> map()) | map()) ::
          {map(), paths()}
  def read(
        declaration,
        %{schema_version: written, payload: payload} = row,
        implementation \\ nil,
        values \\ %{}
      ) do
    stored = payload || %{}

    steps =
      for step <- Map.get(declaration, :upcasts, []),
          is_integer(written) and step.from >= written and step.from < declaration.schema_version,
          do: step

    Enum.reduce(steps, {stored, %{}}, fn
      %{function: fun} = step, {data, paths} ->
        context = %{declaration: declaration, row: row, step: step, stored: stored}
        {called(context, fun, implementation, values, data), paths}

      step, acc ->
        step(step, acc)
    end)
  end

  @doc false
  # Whether `row` goes through a step by a function of `declaration` when it is read.
  @spec function_step?(map(), EhOsContract.Event.t()) :: boolean()
  def function_step?(declaration, %{schema_version: written}) do
    is_integer(written) and
      Enum.any?(
        Map.get(declaration, :upcasts, []),
        &(Map.has_key?(&1, :function) and &1.from >= written and
            &1.from < declaration.schema_version)
      )
  end

  defp called(context, fun, implementation, values, data) do
    module = implementation!(context, fun, implementation)

    given =
      try do
        apply(module, fun, [data])
      rescue
        exception ->
          refuse!(context, "#{inspect(module)}.#{fun}/1 raised #{inspect(exception.__struct__)}")
      catch
        kind, _reason -> refuse!(context, "#{inspect(module)}.#{fun}/1 #{caught(kind)}")
      end

    result = stored!(context, module, fun, given)
    sealed!(context, data, result)
    clear!(context, result)
    tagged!(context, result, if(is_function(values, 0), do: values.(), else: values))
    result
  end

  defp implementation!(context, fun, nil),
    do: refuse!(context, "names #{fun}/1, and no implementation was given")

  defp implementation!(context, fun, implementation) do
    implementation.()
  rescue
    exception in ArgumentError ->
      refuse!(
        context,
        "names #{fun}/1 of the unit's implementation: #{Exception.message(exception)}"
      )
  end

  defp caught(:throw), do: "threw"
  defp caught(:exit), do: "exited"
  defp caught(_error), do: "failed"

  # What the function gave, as the log stores a value: through JSON, so that a decimal, a
  # date or an atom key reads as an old row's own would. Anything else is refused, and so
  # is a field given twice, under an atom and under its name, which JSON would settle
  # by the order of keys.
  defp stored!(context, module, fun, given) when is_map(given) and not is_struct(given) do
    keys = Enum.map(Map.keys(given), &to_string/1)

    if length(Enum.uniq(keys)) != length(keys) do
      refuse!(
        context,
        "#{inspect(module)}.#{fun}/1 gave a field under an atom and under its name"
      )
    end

    given |> Jason.encode!() |> Jason.decode!()
  rescue
    _cannot_encode in [Protocol.UndefinedError, Jason.EncodeError] ->
      refuse!(context, "#{inspect(module)}.#{fun}/1 gave a map the log cannot store")
  end

  defp stored!(context, module, fun, _given),
    do: refuse!(context, "#{inspect(module)}.#{fun}/1 gave no map")

  # A seal of the result is one of the input's, at the same field.
  defp sealed!(context, data, result) do
    before = seals(data)

    for {path, seal} <- seals(result), Map.get(before, path) != seal do
      refuse!(
        context,
        "the function puts a sealed value at #{path} that the row did not hold there; a seal " <>
          "opens only under the field it was sealed in, so a personal field is renamed with " <>
          "`rename:`, and a list holding personal data keeps its order"
      )
    end

    :ok
  end

  # A personal field holds a seal or nothing: the function sees no clear value of one, and
  # one it wrote would be clear text where the log keeps a seal.
  defp clear!(%{declaration: declaration} = context, result) do
    for field <- declaration.fields,
        Map.get(field, :personal) != nil,
        name = Atom.to_string(field.name),
        value = Map.get(result, name),
        value != nil and not match?(%{"$eh" => _}, value) do
      refuse!(context, "the function writes #{name}, a personal field, in the clear")
    end

    :ok
  end

  # A field the log tags rows with holds what the row was written with: its tags were
  # made from that, whatever steps came before the function.
  defp tagged!(%{declaration: declaration, stored: stored} = context, result, values) do
    for field <- declaration.fields,
        Key.tag_field?(field, values) or Key.bucket_field?(field, values),
        name = Atom.to_string(field.name),
        Map.get(stored, name) != Map.get(result, name) do
      refuse!(
        context,
        "the function leaves #{name} other than the row was written with, and the log tags " <>
          "each row with it; rows written before keep their tags"
      )
    end

    :ok
  end

  defp refuse!(%{row: row, step: step}, why),
    do: raise(ArgumentError, "#{where(row, step)}: #{why}")

  # Every sealed value of `data`, by its path, inside values and lists too.
  defp seals(data), do: seals(data, [], %{})

  defp seals(%{"$eh" => _} = seal, path, acc),
    do: Map.put(acc, path |> Enum.reverse() |> Enum.join("."), seal)

  defp seals(%{} = map, path, acc),
    do:
      Enum.reduce(map, acc, fn {key, value}, acc -> seals(value, [to_string(key) | path], acc) end)

  defp seals(list, path, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, i}, acc -> seals(value, [Integer.to_string(i) | path], acc) end)
  end

  defp seals(_value, _path, acc), do: acc

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
