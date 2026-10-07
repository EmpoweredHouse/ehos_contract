defmodule Mix.Tasks.EhOsContract.Glossary do
  @shortdoc "Prints a domain's ubiquitous language as Markdown"

  @moduledoc """
  Prints the glossary of the application's domain as Markdown: each context's terms,
  their definitions, the words to avoid and their translations.

      mix eh_os_contract.glossary                        # every term, in its context's language
      mix eh_os_contract.glossary --language en          # each term in English, or a note that it has none
      mix eh_os_contract.glossary --context settlement   # one context
      mix eh_os_contract.glossary --domain rehmed        # when the application has more than one domain

  The domain is found among the modules of `config :eh_os_contract, applications:`.
  Use `--output` to write a file: when the output is not a terminal, Erlang writes
  it in Latin-1, and the terms are in the client's language.
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
        context: EhOsContract.Tools.context!(domain, opts[:context])
      )

    case opts[:output] do
      nil -> Mix.shell().info(text)
      path -> File.write!(path, text)
    end
  end
end
