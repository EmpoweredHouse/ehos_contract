defmodule Mix.Tasks.EhOsContract.Bundle do
  # The bundle's format is EHOS's (eh-os D-146).
  @shortdoc "Writes the files a deployment takes, with bundle.json, their index"

  @moduledoc """
  Writes a bundle, the files EHOS takes with an image to deploy it (eh-os D-146), into a directory
  that does not exist yet or is empty:

      mix eh_os_contract.bundle --output-dir bundle
      mix eh_os_contract.bundle --output-dir bundle --ehos-yaml deploy/ehos.yaml

  - `ehos.manifest.json`, the manifest, as `mix eh_os_contract.manifest` writes it from
    `ehos.yaml`, which `--ehos-yaml` names as it does there;
  - `graph/`, every graph document of the application, as
    `mix eh_os_contract.graph --output-dir` writes them; empty for one with no contracts;
  - `bundle.json`, the index: the bundle's version, `ehos.bundle/v1`, and each file by its path,
    its size and its SHA-256 (`EhOsContract.Auth.Bundle`).

  It refuses a directory that holds anything, so a document of a contract removed since an earlier
  run is never sent with the rest. The index is checked against EHOS's schema and the rules EHOS
  keeps beside it before it is written; a bundle EHOS would refuse is refused here, with every
  reason, and the files written for it are removed.

  The two commands it runs stay, each writing one part of a bundle.
  """

  use Boundary, classify_to: EhOsContract.Auth
  use Mix.Task

  alias EhOsContract.Auth.Bundle

  @manifest "ehos.manifest.json"
  @graph "graph"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [output_dir: :string, ehos_yaml: :string])

    cond do
      option =
          Enum.find_value(invalid, fn
            {option, nil} -> option in ~w(--output-dir --ehos-yaml) && option
            _ -> nil
          end) ->
        Mix.raise("#{option} needs a value")

      invalid != [] ->
        Mix.raise("unknown options: #{Enum.map_join(invalid, " ", &elem(&1, 0))}")

      rest != [] ->
        Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

      opts[:output_dir] in [nil, ""] ->
        Mix.raise("say where the bundle goes: --output-dir <dir>")

      true ->
        :ok
    end

    dir = opts[:output_dir]
    created? = empty!(dir)

    # A compilation or a start that fails exits rather than raises: each leaves nothing behind.
    try do
      write(dir, opts)
    catch
      kind, reason ->
        clear(dir, created?)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp write(dir, opts) do
    ehos_yaml = if opts[:ehos_yaml], do: ["--ehos-yaml", opts[:ehos_yaml]], else: []

    Mix.Task.rerun("eh_os_contract.manifest", ["--output", Path.join(dir, @manifest) | ehos_yaml])
    Mix.Task.rerun("eh_os_contract.graph", ["--output-dir", Path.join(dir, @graph)])

    graph =
      Path.join(dir, @graph)
      |> File.ls!()
      |> Enum.map(&"#{@graph}/#{&1}")

    # Where case is ignored, two documents whose names differ only in it are one file.
    if length(graph) != documents(),
      do:
        Mix.raise(
          "#{documents()} graph documents were written, and #{dir}/#{@graph} holds " <>
            "#{length(graph)} files: two names may differ only in case on a file system that " <>
            "ignores it, or something else wrote there during the run"
        )

    case Bundle.index(dir, @manifest, graph) do
      {:ok, index} ->
        File.write!(Path.join(dir, "bundle.json"), [
          Jason.encode_to_iodata!(index, pretty: true),
          "\n"
        ])

        Mix.shell().info("written: a bundle of #{length(graph)} graph documents in #{dir}")

      {:error, reasons} ->
        Mix.raise(
          "the bundle is refused, as EHOS would refuse it:\n" <>
            Enum.map_join(reasons, "\n", &"  #{&1}")
        )
    end
  end

  # As `eh_os_contract.graph --output-dir` writes them: each domain's, contract's and process
  # module's, from the registry it loaded.
  defp documents,
    do:
      length(EhOsContract.Registry.domains()) + length(EhOsContract.Registry.contracts()) +
        length(EhOsContract.Registry.processes())

  # Whether it is made here: an empty directory that was there is left, emptied, on a refusal.
  defp empty!(dir) do
    case File.ls(dir) do
      {:ok, []} ->
        false

      {:ok, _files} ->
        Mix.raise("#{dir} holds files already; --output-dir writes into an empty one")

      {:error, :enoent} ->
        true

      {:error, reason} ->
        Mix.raise("cannot read #{dir}: #{:file.format_error(reason)}")
    end
  end

  # Only what this run writes, by name, and the directory when this run made it and it is empty:
  # whatever another process put there meanwhile stays.
  defp clear(dir, created?) do
    for name <- ["bundle.json", @manifest], do: File.rm(Path.join(dir, name))
    File.rm_rf(Path.join(dir, @graph))
    if created?, do: File.rmdir(dir)
  end
end
