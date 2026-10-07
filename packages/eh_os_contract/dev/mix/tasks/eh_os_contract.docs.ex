defmodule Mix.Tasks.EhOsContract.Docs do
  @shortdoc "Regenerates the package's generated documentation (DSL reference, configuration)"

  @moduledoc """
  Writes every page `EhOsContract.Docs` lists as generated:

    * the reference of the three DSLs, an index for each (`docs/dsl/domain-dsl.md`
      for `use EhOsContract.Domain`, `docs/dsl/contract-dsl.md` for `use
      EhOsContract.Contract`, `docs/dsl/process-dsl.md` for `use
      EhOsContract.Process`) and a page for each top-level entity beside it
      (`docs/dsl/contract-aggregate.md`, …), with every entity nested in it, its
      arguments and options, which are required, their types, defaults and docs;
    * `docs/configuration.md`, from the schema of `EhOsContract.Config`.

  The pages are named after their DSL (`contract-…`, `*-dsl.md`) so that none shares a
  basename with another page of the package: ExDoc names a page after its basename,
  and `docs/contract.md`, the guide, would otherwise share `contract.html` with the
  reference.

  Only the reference is generated. `docs/contract.md` is prose a generator has no
  business writing: how to start, what each layer of checks refuses, and why.

  A page under `docs/` that starts with the generated marker and that the manifest no
  longer lists is deleted; a page written by hand is never touched.

  `--check` writes nothing, and fails naming every page that is missing, differs or
  is left over: a key table written by hand beside the extension is a second copy,
  and every second copy in this project has eventually disagreed with the code. The
  package's `mix check` runs it.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean])

    Mix.Task.run("compile")

    pages = EhOsContract.Docs.generated()
    stale = for {path, markdown} <- pages, current(path) != markdown, do: {path, markdown}
    listed = MapSet.new(pages, &elem(&1, 0))

    left_over =
      for path <- Path.wildcard("docs/**/*.md"),
          not MapSet.member?(listed, path),
          EhOsContract.Docs.marker?(File.read!(path)),
          do: path

    paths = Enum.map(stale, &elem(&1, 0)) ++ left_over

    cond do
      paths == [] ->
        Mix.shell().info("#{length(pages)} generated pages: current")

      opts[:check] ->
        Mix.raise(
          "#{Enum.join(paths, ", ")} out of date with the code. Run `mix eh_os_contract.docs`."
        )

      true ->
        for {path, markdown} <- stale do
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, markdown)
        end

        Enum.each(left_over, &File.rm!/1)
        Mix.shell().info("regenerated #{Enum.join(paths, ", ")}")
    end
  end

  defp current(path), do: if(File.exists?(path), do: File.read!(path))
end
