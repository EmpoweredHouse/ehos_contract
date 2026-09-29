defmodule Mix.Tasks.EhOsContract.Manifest do
  @shortdoc "Writes an EHOS application manifest from contracts"

  @moduledoc """
  Writes the selected domain's human command capabilities and roles as the strict
  `ehos.manifest/v1` document accepted by EHOS.

      mix eh_os_contract.manifest --output ehos.manifest.json
      mix eh_os_contract.manifest --domain taxvision --output ehos.manifest.json

  Domains and contracts are found among modules of
  `config :eh_os_contract, applications:`. `--domain` is required only when more
  than one registered domain exists. The output is UTF-8 JSON with only fields the
  v1 schema permits; query and record capabilities need a later EHOS schema.
  """

  use Boundary, classify_to: EhOsContract.Auth
  use Mix.Task

  alias EhOsContract.Auth.Manifest

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [output: :string, domain: :string])
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    output =
      case opts[:output] do
        blank when blank in [nil, ""] -> Mix.raise("say where the manifest goes: --output <file>")
        output -> output
      end

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    domain = select_domain!(EhOsContract.Registry.domains(), opts[:domain])
    domain_module = domain.module

    contracts =
      Enum.filter(EhOsContract.Registry.contracts(), fn contract ->
        EhOsContract.Model.fetch(contract).domain == domain_module
      end)

    document = Manifest.build(domain, contracts)
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode_to_iodata!(document, pretty: true) ++ ["\n"])
    Mix.shell().info("written: #{output}")
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end

  @doc false
  def select_domain!([], _wanted), do: Mix.raise("no EhOsContract.Domain is registered")

  def select_domain!(domains, nil) do
    case Enum.map(domains, &EhOsContract.Model.fetch/1) do
      [domain] -> domain
      many -> Mix.raise("choose a domain with --domain: #{known_domains(many)}")
    end
  end

  def select_domain!(domains, wanted) do
    models = Enum.map(domains, &EhOsContract.Model.fetch/1)

    case Enum.filter(models, &(to_string(&1.name) == wanted)) do
      [domain] ->
        domain

      [] ->
        Mix.raise("no domain #{inspect(wanted)}. Registered: #{known_domains(models)}")

      many ->
        modules = many |> Enum.map(&inspect(&1.module)) |> Enum.sort() |> Enum.join(", ")
        Mix.raise("domain #{inspect(wanted)} is ambiguous; matching modules: #{modules}")
    end
  end

  defp known_domains(models) do
    models
    |> Enum.map(&"#{&1.name} (#{inspect(&1.module)})")
    |> Enum.sort()
    |> Enum.join(", ")
  end
end
