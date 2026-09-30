defmodule Mix.Tasks.EhOsContract.Pages do
  @shortdoc "Writes the domain and its contracts as Markdown pages, one per element"

  @moduledoc """
  The application's domain and its contracts as linked Markdown pages, one per
  element (`EhOsContract.Pages`; ESDM's `documentation`).

      mix eh_os_contract.pages --output docs/model                  # write the pages
      mix eh_os_contract.pages --output docs/model --check          # are they current?
      mix eh_os_contract.pages --output docs/model --domain rehmed  # when there is more than one domain

  The domain and its contracts are found among the modules of
  `config :eh_os_contract, applications:`. The pages go where `--output` says: the
  host decides whether to commit them, add them to ExDoc's `extras`, or only read
  them. A page the model no longer has is deleted — only a file that starts with
  the marker line of the domain's pages, so another domain's pages in the same
  directory stay — and a page is never written over a file without it, nor
  through a symbolic link: then nothing is written, and the task names what is in
  the way. Nothing outside `--output` is read or touched.

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

    output =
      case opts[:output] do
        blank when blank in [nil, ""] -> Mix.raise("say where the pages go: --output <directory>")
        output -> output
      end

    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    domain = Tools.domain!(EhOsContract.Registry.domains(), opts[:domain])

    pages =
      try do
        Pages.render(domain, EhOsContract.Registry.contracts())
      rescue
        error in ArgumentError -> Mix.raise(Exception.message(error))
      end

    found = found(output, Pages.marker(domain.__eh_os_contract_model__().name))
    stale = for {path, :page} <- found, not Map.has_key?(pages, path), do: path
    blocked = blocked(pages, found)

    if opts[:check],
      do: check!(output, pages, stale, blocked),
      else: write!(output, pages, stale, blocked)
  end

  defp write!(output, pages, stale, blocked) do
    if blocked != [] do
      Mix.raise(
        "#{output}: nothing written, since these are not pages this task wrote:\n  " <>
          Enum.join(blocked, "\n  ")
      )
    end

    for {path, text} <- pages do
      file = Path.join(output, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, text)
    end

    for path <- stale do
      File.rm!(Path.join(output, path))
      prune(output, Path.dirname(path))
    end

    Mix.shell().info(
      "#{output}: #{map_size(pages)} pages written" <>
        if(stale == [], do: "", else: ", #{length(stale)} left over deleted")
    )
  end

  defp check!(output, pages, stale, blocked) do
    wrong =
      for {path, text} <- Enum.sort(pages),
          path not in blocked,
          problem = problem(Path.join(output, path), text),
          do: "#{path} #{problem}"

    problems =
      wrong ++
        Enum.map(stale, &"#{&1} is left over") ++
        Enum.map(blocked, &"#{&1} is in the way")

    case problems do
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

  # What is under `output`, by relative path: a page this task wrote for the domain
  # (`:page`), any other file — another domain's page too — or a symbolic link. Walked, not globbed, so nothing in `output`'s own
  # name is read as a pattern, and a link is never followed: what it points at is
  # outside what the task was given.
  defp found(output, marker) do
    case File.lstat(output) do
      {:ok, _} -> walk(output, "", marker)
      {:error, _} -> %{}
    end
  end

  defp walk(output, relative, marker) do
    output
    |> Path.join(relative)
    |> File.ls!()
    |> Enum.reduce(%{}, fn name, acc ->
      path = if relative == "", do: name, else: Path.join(relative, name)
      file = Path.join(output, path)

      case File.lstat!(file).type do
        :directory -> Map.merge(acc, walk(output, path, marker))
        :symlink -> Map.put(acc, path, :link)
        :regular -> Map.put(acc, path, if(page?(file, marker), do: :page, else: :file))
        _other -> Map.put(acc, path, :file)
      end
    end)
  end

  # Only the marker's bytes are read: `--output` may be a large tree of documents.
  defp page?(file, marker) do
    case File.open(file, [:read, :binary], &IO.binread(&1, byte_size(marker))) do
      {:ok, ^marker} -> true
      _other -> false
    end
  end

  # The pages whose path, or a directory on the way to it, is something the task did
  # not write: a file without the marker, or a link.
  defp blocked(pages, found) do
    for path <- Enum.sort(Map.keys(pages)), in_the_way?(path, found), do: path
  end

  defp in_the_way?(path, found) do
    parents =
      path
      |> Path.split()
      |> Enum.drop(-1)
      |> Enum.scan(&Path.join(&2, &1))

    Enum.any?([path | parents], &(Map.get(found, &1) in [:file, :link]))
  end

  # Directories a deleted page leaves empty go with it, up to `output`.
  defp prune(_output, "."), do: :ok

  defp prune(output, dir) do
    case File.rmdir(Path.join(output, dir)) do
      :ok -> prune(output, Path.dirname(dir))
      {:error, _not_empty} -> :ok
    end
  end
end
