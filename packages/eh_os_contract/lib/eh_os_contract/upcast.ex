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
  @moduledoc false

  @typedoc "The path a field of the current version was written under, where it differs."
  @type paths :: %{String.t() => String.t()}

  @doc false
  # The row's payload in the declaration's version, and the path each renamed field was
  # written under. A row at the declared version, or with no payload, is as it is; a row
  # newer than the declaration is the caller's to refuse first (`Consumer.current!/2`).
  @spec read(map(), EhOsContract.Event.t()) :: {map(), paths()}
  def read(declaration, %{schema_version: written, payload: payload}) do
    steps =
      for step <- Map.get(declaration, :upcasts, []),
          is_integer(written) and step.from >= written and step.from < declaration.schema_version,
          do: step

    Enum.reduce(steps, {payload || %{}, %{}}, &step/2)
  end

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
