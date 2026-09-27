defmodule Mix.Tasks.EhOsContract.View do
  @shortdoc "Prints the domain as a tree: contexts, contracts, units and consumers"

  @moduledoc """
  The application's domain as a tree for a terminal (`EhOsContract.View`; ESDM's
  `view`).

      mix eh_os_contract.view                                   # the whole domain
      mix eh_os_contract.view settlement                        # one context
      mix eh_os_contract.view settlement/visit_settlement       # one unit, consumer or query
      mix eh_os_contract.view --details                         # with what each row declares
      mix eh_os_contract.view --domain rehmed                   # when there is more than one domain

  The domain and its contracts are found among the modules of
  `config :eh_os_contract, applications:`. Use `--output` to write a file: Erlang
  keeps stdout in latin1 when it is not a terminal, and labels are in the client's
  language.
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
          [context | unit] = String.split(path, "/", parts: 2)
          [Tools.context!(domain, context) | Enum.map(unit, &Tools.existing_atom(&1, "path"))]
      end

    text =
      EhOsContract.View.render(domain, EhOsContract.Registry.v2_contracts(),
        details: opts[:details] || false,
        path: path
      )

    case opts[:output] do
      nil -> Mix.shell().info(text)
      file -> File.write!(file, text <> "\n")
    end
  end
end
