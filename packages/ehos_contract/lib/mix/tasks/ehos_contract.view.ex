defmodule Mix.Tasks.EhosContract.View do
  @shortdoc "Prints the domain as a tree: contexts, contracts, units, consumers and processes"

  @moduledoc """
  Prints the domain of the application as a tree in a terminal. The tree gives the
  contexts, and in each context its contracts with their units, consumers and
  queries. Then it gives the process modules, each with its stages in order and the
  events of each stage, by contract.

      mix ehos_contract.view                                   # the whole domain
      mix ehos_contract.view circulation                       # one context, without the processes
      mix ehos_contract.view circulation/loan                  # one unit, consumer or query
      mix ehos_contract.view --details                         # with what each row declares
      mix ehos_contract.view --domain lending                  # when there is more than one domain

  A path is `<context>` or `<context>/<name>`. The task takes one path at most.

  The task finds the domain, its contracts and its process modules among the modules
  of `config :ehos_contract, applications:`. `--output` writes the tree to a file.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  alias EhosContract.Tools

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, rest} =
      OptionParser.parse!(args, strict: [details: :boolean, domain: :string, output: :string])

    Mix.Task.run("compile")
    Application.load(:ehos_contract)
    EhosContract.Registry.load!()

    domain = Tools.domain!(EhosContract.Registry.domains(), opts[:domain])

    path =
      case rest do
        [] ->
          []

        [path] ->
          case String.split(path, "/") do
            [context] ->
              [Tools.context!(domain, context)]

            [context, unit] when unit != "" ->
              [Tools.context!(domain, context), Tools.existing_atom(unit, "path")]

            _other ->
              Mix.raise("the path is <context> or <context>/<name>, got #{inspect(path)}")
          end

        _many ->
          Mix.raise("one path at most, <context> or <context>/<name>; got #{inspect(rest)}")
      end

    text =
      try do
        EhosContract.View.render(
          domain,
          EhosContract.Registry.contracts() ++ EhosContract.Registry.processes(),
          details: opts[:details] || false,
          path: path
        )
      rescue
        error in ArgumentError -> Mix.raise(Exception.message(error))
      end

    case opts[:output] do
      nil -> Mix.shell().info(text)
      file -> File.write!(file, text <> "\n")
    end
  end
end
