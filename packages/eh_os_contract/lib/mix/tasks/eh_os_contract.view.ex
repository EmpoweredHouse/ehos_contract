defmodule Mix.Tasks.EhOsContract.View do
  @shortdoc "Prints the domain as a tree: contexts, contracts, units and consumers"

  @moduledoc """
  Prints the application's domain as a tree for a terminal: its contexts, and in
  each its contracts, their units, consumers and queries.

      mix eh_os_contract.view                                   # the whole domain
      mix eh_os_contract.view settlement                        # one context
      mix eh_os_contract.view settlement/visit_settlement       # one unit, consumer or query
      mix eh_os_contract.view --details                         # with what each row declares
      mix eh_os_contract.view --domain rehmed                   # when there is more than one domain

  The domain and its contracts are found among the modules of
  `config :eh_os_contract, applications:`. `--output` writes the tree to a file.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.Tools

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, rest} =
      OptionParser.parse!(args, strict: [details: :boolean, domain: :string, output: :string])

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    domain = Tools.domain!(EhOsContract.Registry.domains(), opts[:domain])

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
        EhOsContract.View.render(domain, EhOsContract.Registry.contracts(),
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
