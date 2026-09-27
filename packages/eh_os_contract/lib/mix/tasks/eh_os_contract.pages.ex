defmodule Mix.Tasks.EhOsContract.Pages do
  @shortdoc "Writes the domain and its contracts as Markdown pages, one per element"

  @moduledoc """
  The application's domain and its v2 contracts as linked Markdown pages, one per
  element (`EhOsContract.Pages`; ESDM's `documentation`).

      mix eh_os_contract.pages --output docs/model                  # write the pages
      mix eh_os_contract.pages --output docs/model --check          # are they current?
      mix eh_os_contract.pages --output docs/model --domain rehmed  # when there is more than one domain

  The domain and its contracts are found among the modules of
  `config :eh_os_contract, applications:`. The pages go where `--output` says: the
  host decides whether to commit them, add them to ExDoc's `extras`, or only read
  them. A page the model no longer has is deleted — only a file that starts with
  the pages' marker line, so nothing else in the directory is touched.

  `--check` writes nothing, and fails naming every page that is missing, differs or
  is left over.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.{Pages, Tools}

  @impl Mix.Task
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args, strict: [output: :string, domain: :string, check: :boolean])

    output = opts[:output] || Mix.raise("say where the pages go: --output <directory>")
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    domain = Tools.domain!(EhOsContract.Registry.domains(), opts[:domain])

    pages =
      try do
        Pages.render(domain, EhOsContract.Registry.v2_contracts())
      rescue
        error in ArgumentError -> Mix.raise(Exception.message(error))
      end

    stale = generated(output) -- Map.keys(pages)

    if opts[:check],
      do: check!(output, pages, stale),
      else: write!(output, pages, stale)
  end

  defp write!(output, pages, stale) do
    for {path, text} <- pages do
      file = Path.join(output, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, text)
    end

    for path <- stale, do: File.rm!(Path.join(output, path))

    Mix.shell().info(
      "#{output}: #{map_size(pages)} pages written" <>
        if(stale == [], do: "", else: ", #{length(stale)} left over deleted")
    )
  end

  defp check!(output, pages, stale) do
    wrong =
      for {path, text} <- Enum.sort(pages),
          problem = problem(Path.join(output, path), text),
          do: "#{path} #{problem}"

    case wrong ++ Enum.map(stale, &"#{&1} is left over") do
      [] ->
        Mix.shell().info("#{output}: current")

      problems ->
        Mix.raise(
          "#{output} is not current; run `mix eh_os_contract.pages --output #{output}`:\n  " <>
            Enum.join(problems, "\n  ")
        )
    end
  end

  defp problem(file, text) do
    case File.read(file) do
      {:ok, ^text} -> nil
      {:ok, _other} -> "differs"
      {:error, _} -> "is missing"
    end
  end

  # The pages written before: files under `output` that start with the marker.
  defp generated(output) do
    marker = Pages.marker()

    for file <- Path.wildcard(Path.join(output, "**/*.md")),
        File.regular?(file),
        String.starts_with?(File.read!(file), marker),
        do: Path.relative_to(file, output)
  end
end
