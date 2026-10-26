defmodule EhOsContract.Auth.Bundle do
  @moduledoc """
  A bundle's index, `bundle.json` (eh-os D-146): the files a deployment of one image takes,
  written together by `mix eh_os_contract.bundle`, each named by its path, its size and its
  SHA-256. EHOS owns the format, and explains it in its `docs/bundle.md`.

  `index/3` makes the index of a manifest and graph documents already written, and checks it as
  EHOS will: against EHOS's own JSON Schema of `ehos.bundle/v1`, copied unchanged into this
  package's `priv/schemas/ehos.bundle/`, and the two rules EHOS keeps beside it, the graph
  documents at most 33554432 bytes in all and each path named once, without regard to case.
  """

  alias EhOsContract.Auth.EhosYaml.Schema.Ecma

  @version "ehos.bundle/v1"
  @file_path Path.expand("../../../priv/schemas/ehos.bundle/v1.json", __DIR__)
  @external_resource @file_path
  @schema @file_path |> File.read!() |> Jason.decode!()
  @max_graph_bytes 33_554_432

  @doc "The version of `bundle.json` this package writes."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Where the copy of EHOS's schema is."
  @spec schema_file() :: Path.t()
  def schema_file, do: @file_path

  @doc """
  The index of the bundle in `dir`: its manifest at `manifest` and its graph documents at `graph`,
  each a path relative to `dir`. `{:ok, index}` as `bundle.json` holds it, keys in the order EHOS
  writes them, or `{:error, reasons}` for one EHOS would refuse.
  """
  @spec index(Path.t(), String.t(), [String.t()]) ::
          {:ok, Jason.OrderedObject.t()} | {:error, [String.t()]}
  def index(dir, manifest, graph) do
    files = Enum.map([manifest | Enum.sort(graph)], &described(dir, &1))
    [manifest | graph] = files

    plain = %{"schema" => @version, "manifest" => manifest, "graph" => graph}

    with :ok <- schema(plain),
         :ok <- total(graph),
         :ok <- once(files) do
      {:ok,
       Jason.OrderedObject.new([
         {"schema", @version},
         {"manifest", ordered(manifest)},
         {"graph", Enum.map(graph, &ordered/1)}
       ])}
    end
  end

  defp described(dir, path) do
    bytes = File.read!(Path.join(dir, path))

    %{
      "path" => path,
      "bytes" => byte_size(bytes),
      "sha256" => :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    }
  end

  defp ordered(file),
    do: Jason.OrderedObject.new(for key <- ~w(path bytes sha256), do: {key, file[key]})

  # JSV's built schema holds compiled patterns, which a module attribute cannot, so it is built at
  # each check, with each pattern's `$` read as EHOS reads it.
  defp schema(index) do
    case JSV.validate(index, JSV.build!(Ecma.schema(@schema))) do
      {:ok, _valid} ->
        :ok

      {:error, error} ->
        reasons =
          error
          |> JSV.normalize_error()
          |> Map.fetch!(:details)
          |> Enum.flat_map(fn unit ->
            for %{kind: kind, message: message} <- unit.errors,
                kind not in [:properties, :items, :additionalProperties, :"$ref", :allOf],
                do: "#{location(unit.instanceLocation)}: #{message}"
          end)
          |> Enum.uniq()

        {:error, reasons}
    end
  end

  defp location("#"), do: "bundle.json"
  defp location("#" <> pointer), do: "bundle.json at #{pointer}"

  defp total(graph) do
    total = graph |> Enum.map(& &1["bytes"]) |> Enum.sum()

    if total > @max_graph_bytes,
      do:
        {:error,
         ["the graph documents hold #{total} bytes; EHOS takes at most #{@max_graph_bytes}"]},
      else: :ok
  end

  defp once(files) do
    repeated =
      files
      |> Enum.map(& &1["path"])
      |> Enum.group_by(&String.downcase/1)
      |> Enum.filter(fn {_key, paths} -> length(paths) > 1 end)

    case repeated do
      [] ->
        :ok

      _repeated ->
        {:error,
         for(
           {_key, paths} <- repeated,
           do: "#{Enum.join(paths, " and ")} name one file where case is ignored"
         )}
    end
  end
end
