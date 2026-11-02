defmodule Mix.Tasks.EhOsContract.Pages do
  @shortdoc "Writes the domain, its contracts and its process modules as Markdown pages"

  @moduledoc """
  Writes the domain of the application, its contracts and its process modules as
  linked Markdown pages, one page for each element.

      mix eh_os_contract.pages --output docs/model                  # write the pages
      mix eh_os_contract.pages --output docs/model --check          # are they current?
      mix eh_os_contract.pages --output docs/model --domain lending # when there is more than one domain
      mix eh_os_contract.pages --output docs/owner --audience owner # the pages for the business owner

  The task finds the domain, its contracts and its process modules among the modules
  of `config :eh_os_contract, applications:`. It writes the pages where `--output`
  says. `--output` is necessary. The host decides if it commits them, adds them to the `extras` of ExDoc, or
  only reads them.

  ## What it writes

  - A page for the domain, for each contract and for each process module.
  - The page of a process module is `processes/<its id after the domain's name>.md`.
    The page of the domain links it, and so does the page of each contract whose
    events it includes.
  - The page of a process module gives its stages in order with their events, and
    what ends a run. It also gives its promises, its deadline, and the external
    systems that its events rest on.
  - `graph/<contract id>.json` holds the `graph.v1` document of each contract
    (`EhOsContract.Graph.Document`). `graph/process/<process id>.json` holds the
    document of each process module. The page of each one links its document.

  ## What it deletes, and what stops it

  The task reads and changes nothing outside `--output`.

  - It deletes a page that the model no longer has. It deletes only a file that starts
    with the marker line of the pages of the domain. It also deletes a `graph.v1`
    document of a contract or a process module of the domain, at the path that the
    task gives it. So the pages of another domain in the same directory stay.
  - It never writes a page over a file without the marker, or through a symbolic link.
    Then it writes nothing, and names what is in the way.

  `--check` writes nothing. It fails, and names each page that is missing, different
  or left over, and each file in the way.

  ## Write the pages for the business owner

  `--audience owner` writes the pages that a business owner reads. They have the same
  tree, with each declaration by its label. They leave out the names of modules,
  versions, stored types, delivery, idempotency, correlation keys, the names and types
  of fields, and the graph documents.

  - These pages have a marker of their own. Write them to a directory of their own.
    In the directory of the engineering pages, each one is a file in the way.
  - If the owner reads a stage or a value by its name in the code,
    `mix eh_os_contract.check` reports `owner-view-without-label`.

  `--audience engineering` is the default. Another value stops the task with an
  error.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.{Pages, Tools}

  @impl Mix.Task
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args,
        strict: [output: :string, domain: :string, check: :boolean, audience: :string]
      )

    audience =
      case opts[:audience] do
        nil -> :engineering
        "engineering" -> :engineering
        "owner" -> :owner
        other -> Mix.raise("--audience is engineering or owner, not #{inspect(other)}")
      end

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
        Pages.render(
          domain,
          EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes(),
          audience: audience
        )
      rescue
        error in ArgumentError -> Mix.raise(Exception.message(error))
      end

    marker = Pages.marker(domain.__eh_os_contract_model__().name, audience)
    found = found(output, {marker, domain, audience})
    stale = for {path, :page} <- found, not Map.has_key?(pages, path), do: path
    blocked = blocked(pages, found)

    if opts[:check],
      do: check!(output, pages, stale, blocked, audience),
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

  defp check!(output, pages, stale, blocked, audience) do
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
          "#{output} is not current; run `mix eh_os_contract.pages --output #{output}" <>
            if(audience == :owner, do: " --audience owner", else: "") <>
            "`:\n  " <>
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

  # What is under `output`, by relative path: a page this task wrote for the domain,
  # its graph documents among them (`:page`), any other file — another domain's page too — or a symbolic link. Walked, not globbed, so nothing in `output`'s own
  # name is read as a pattern, and a link is never followed: what it points at is
  # outside what the task was given.
  defp found(output, mine) do
    case File.lstat(output) do
      {:ok, _} -> walk(output, "", mine)
      {:error, _} -> %{}
    end
  end

  defp walk(output, relative, mine) do
    output
    |> Path.join(relative)
    |> File.ls!()
    |> Enum.reduce(%{}, fn name, acc ->
      path = if relative == "", do: name, else: Path.join(relative, name)
      file = Path.join(output, path)

      case File.lstat!(file).type do
        :directory -> Map.merge(acc, walk(output, path, mine))
        :symlink -> Map.put(acc, path, :link)
        :regular -> Map.put(acc, path, if(page?(path, file, mine), do: :page, else: :file))
        _other -> Map.put(acc, path, :file)
      end
    end)
  end

  # Only the marker's bytes are read: `--output` may be a large tree of documents. A
  # graph document has no room for a marker, so it is read whole, and only
  # where the pages put one (`EhOsContract.Pages.graph?/3`). One the task cannot read
  # is not taken for its own, as a page whose marker it cannot read is not.
  # The owner's pages have no graph documents, so none is theirs.
  defp page?(path, file, {marker, domain, audience}) do
    if audience == :engineering and String.starts_with?(path, "graph/") and
         String.ends_with?(path, ".json") do
      case File.read(file) do
        {:ok, text} -> Pages.graph?(path, text, domain)
        {:error, _reason} -> false
      end
    else
      marked?(file, marker)
    end
  end

  defp marked?(file, marker) do
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
