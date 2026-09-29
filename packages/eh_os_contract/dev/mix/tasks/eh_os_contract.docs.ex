defmodule Mix.Tasks.EhOsContract.Docs do
  @shortdoc "Regenerates the DSL reference in docs/dsl/ from the Spark extensions"

  @moduledoc """
  Writes the reference of the two DSLs — `docs/dsl/domain.md` for
  `use EhOsContract.Domain` and `docs/dsl/contract.md` for `use EhOsContract.Contract`
  — from their Spark extensions, with `Spark.CheatSheet.cheat_sheet/1`: every
  entity, where it nests, its arguments and options, which are required, their types,
  defaults and docs.

  Only the reference is generated. `docs/contract.md` is prose a generator has no
  business writing: how to start, what each layer of checks refuses, and why.

  `--check` verifies both files are current and exits non-zero otherwise: a key
  table written by hand beside the extension is a second copy, and every second copy
  in this project has eventually disagreed with the code. The package's `mix check`
  runs it.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @pages [
    {"docs/dsl/domain.md", EhOsContract.Domain.Dsl},
    {"docs/dsl/contract.md", EhOsContract.Contract.Dsl}
  ]

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean])

    Mix.Task.run("compile")

    stale =
      for {path, extension} <- @pages,
          generated = Spark.CheatSheet.cheat_sheet(extension),
          current(path) != generated,
          do: {path, generated}

    paths = Enum.map_join(stale, ", ", &elem(&1, 0))

    cond do
      stale == [] ->
        Mix.shell().info("docs/dsl: current")

      opts[:check] ->
        Mix.raise("#{paths} out of date with the DSL extensions. Run `mix eh_os_contract.docs`.")

      true ->
        for {path, generated} <- stale do
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, generated)
        end

        Mix.shell().info("regenerated #{paths}")
    end
  end

  defp current(path), do: if(File.exists?(path), do: File.read!(path))
end
