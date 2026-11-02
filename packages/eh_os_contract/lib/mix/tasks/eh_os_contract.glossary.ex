defmodule Mix.Tasks.EhOsContract.Glossary do
  @shortdoc "Prints the ubiquitous language of a domain as Markdown"

  @moduledoc """
  Prints the glossary of the domain of the application as Markdown.

      mix eh_os_contract.glossary                        # each term, in the language of its context
      mix eh_os_contract.glossary --language en          # each term in English, or a note that it has none
      mix eh_os_contract.glossary --context circulation  # one context
      mix eh_os_contract.glossary --domain lending       # when the application has more than one domain

  For each context, the glossary gives:

  - each term, its definition, the words to avoid and its translations;
  - the word in code of each term: its translation into the `code_language:` of the
    domain;
  - the declarations of the contracts of the context that the term names;
  - the process modules that include events of the context and that the term names.
    The term can name the id, a stage, a promise, or a field that tells the runs
    apart.

  The task finds the domain among the modules of `config :eh_os_contract,
  applications:`. `--output` writes the glossary to a file.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [language: :string, context: :string, domain: :string, output: :string]
      )

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    domain = EhOsContract.Tools.domain!(EhOsContract.Registry.domains(), opts[:domain])

    text =
      EhOsContract.Glossary.render(domain,
        # Any language may be asked for, one nobody translated into too: the answer is
        # then that there is no translation, so this is the one name made an atom here.
        language: opts[:language] && String.to_atom(opts[:language]),
        context: EhOsContract.Tools.context!(domain, opts[:context]),
        contracts: EhOsContract.Registry.contracts(),
        processes: EhOsContract.Registry.processes()
      )

    case opts[:output] do
      nil -> Mix.shell().info(text)
      path -> File.write!(path, text)
    end
  end
end
