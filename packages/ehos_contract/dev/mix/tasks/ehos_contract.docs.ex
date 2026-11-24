defmodule Mix.Tasks.EhosContract.Docs do
  @shortdoc "Regenerates the package's generated documentation: DSL, configuration, CLI, behaviours"

  @moduledoc """
  Writes every page `EhosContract.Docs` lists as generated:

    * the reference of the three DSLs, an index for each (`docs/dsl/domain-dsl.md`
      for `use EhosContract.Domain`, `docs/dsl/contract-dsl.md` for `use
      EhosContract.Contract`, `docs/dsl/process-dsl.md` for `use
      EhosContract.Process`) and a page for each top-level entity beside it
      (`docs/dsl/contract-aggregate.md`, …), with every entity nested in it, its
      arguments and options, which are required, their types, defaults and docs;
    * `docs/configuration.md`, from the schema of `EhosContract.Config`;
    * `docs/cli.md`, the `mix` tasks of `lib/`, and `docs/behaviours.md`, the
      behaviours a host may implement, from their docs and callback specs
      (`EhosContract.Docs.ModulePages`).

  The pages are named after their DSL (`contract-…`, `*-dsl.md`) so that none shares a
  basename with another page of the package: ExDoc names a page after its basename,
  and `docs/contract.md`, the guide, would otherwise share `contract.html` with the
  reference.

  Only the reference is generated. `docs/contract.md` is prose a generator has no
  business writing: how to start, what each layer of checks refuses, and why. A
  prose page (`EhosContract.Docs.prose/0`) may still hold generated regions, which
  this task rewrites, and say what it covers (`EhosContract.Docs.Prose`); the task
  prints how many top-level entities and rules no prose page covers, and
  `--coverage` lists them.

  A page under `docs/` that starts with the generated marker and that the manifest no
  longer lists is deleted; a page written by hand is never touched.

  `--check` writes nothing, and fails naming every page that is missing, differs or
  is left over: a key table written by hand beside the extension is a second copy,
  and every second copy in this project has eventually disagreed with the code. The
  package's `mix check` runs it.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  alias EhosContract.Docs.Prose

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean, coverage: :boolean])

    Mix.Task.run("compile")

    generated = EhosContract.Docs.generated()
    filled = for path <- EhosContract.Docs.prose(), do: {path, Prose.fill(File.read!(path))}
    pages = generated ++ filled
    stale = for {path, markdown} <- pages, current(path) != markdown, do: {path, markdown}

    report_coverage(Enum.map(filled, &elem(&1, 1)), opts[:coverage])

    listed = MapSet.new(pages, &elem(&1, 0))

    left_over =
      for path <- Path.wildcard("docs/**/*.md"),
          not MapSet.member?(listed, path),
          EhosContract.Docs.marker?(File.read!(path)),
          do: path

    paths = Enum.map(stale, &elem(&1, 0)) ++ left_over

    cond do
      paths == [] ->
        Mix.shell().info(
          "#{length(generated)} generated pages and #{length(filled)} prose pages: current"
        )

      opts[:check] ->
        Mix.raise(
          "#{Enum.join(paths, ", ")} out of date with the code. Run `mix ehos_contract.docs`."
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

  # Printed here, failed in `test/docs_test.exs`, which `mix check` runs.
  defp report_coverage(prose, list?) do
    case Prose.uncovered(prose) do
      [] ->
        :ok

      gaps when list? ->
        Mix.shell().info(
          "#{length(gaps)} top-level entities and rules are covered by no prose page:\n  " <>
            Enum.join(gaps, "\n  ")
        )

      gaps ->
        Mix.shell().info(
          "#{length(gaps)} top-level entities and rules are covered by no prose page " <>
            "(--coverage lists them)"
        )
    end
  end

  defp current(path), do: if(File.exists?(path), do: File.read!(path))
end
