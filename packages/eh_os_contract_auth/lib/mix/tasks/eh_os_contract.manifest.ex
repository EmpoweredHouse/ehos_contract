defmodule Mix.Tasks.EhOsContract.Manifest do
  @shortdoc "Writes the EHOS application manifest from ehos.yaml and the contracts"

  @moduledoc """
  Writes `ehos.manifest/v2`, the application's `ehos.yaml` extended with what its
  contracts offer (`eh-os` D-52), for EHOS to deploy with the image.

      mix eh_os_contract.manifest --output ehos.manifest.json
      mix eh_os_contract.manifest --ehos-yaml deploy/ehos.yaml --output ehos.manifest.json

  `ehos.yaml` is read from the project's directory unless `--ehos-yaml` names
  another file, and is read as EHOS reads it (`EhOsContract.Auth.EhosYaml`): a file
  EHOS would refuse is refused here, with every reason, its path and its line.
  Domains and contracts are found among modules of
  `config :eh_os_contract, applications:`. A project with more than one domain
  names the one this image is in `ehos.yaml`, as `application: <name>`. What the
  manifest holds is `EhOsContract.Auth.Manifest`'s.
  """

  use Boundary, classify_to: EhOsContract.Auth
  use Mix.Task

  alias EhOsContract.Auth.{EhosYaml, Manifest}

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [output: :string, ehos_yaml: :string])

    refuse_arguments!(rest, invalid)

    output =
      case opts[:output] do
        blank when blank in [nil, ""] -> Mix.raise("say where the manifest goes: --output <file>")
        output -> output
      end

    ehos_yaml = read_ehos_yaml!(opts[:ehos_yaml] || "ehos.yaml")

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    document =
      Manifest.build(
        ehos_yaml,
        EhOsContract.Registry.domains(),
        EhOsContract.Registry.contracts()
      )

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode_to_iodata!(document, pretty: true) ++ ["\n"])
    Mix.shell().info("written: #{output}")
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end

  # `--domain` chose the domain until the manifest was v2; `ehos.yaml` says it now.
  defp refuse_arguments!(rest, invalid) do
    cond do
      Enum.any?(invalid, fn {option, _value} -> option == "--domain" end) ->
        Mix.raise(
          "--domain is gone: a project with more than one domain names the one this image is " <>
            "in ehos.yaml, as application: <name>"
        )

      invalid != [] ->
        Mix.raise("unknown options: #{Enum.map_join(invalid, " ", &elem(&1, 0))}")

      rest != [] ->
        Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

      true ->
        :ok
    end
  end

  defp read_ehos_yaml!(path) do
    text =
      case File.read(path) do
        {:ok, text} ->
          text

        {:error, reason} ->
          Mix.raise(
            "cannot read #{path}: #{:file.format_error(reason)}. The manifest is ehos.yaml " <>
              "extended with what the contracts offer; name another file with --ehos-yaml"
          )
      end

    case EhosYaml.read(text) do
      {:ok, ehos_yaml} ->
        ehos_yaml

      {:error, errors} ->
        reasons = Enum.map_join(errors, "\n", &"  #{EhosYaml.format_error(&1)}")
        Mix.raise("#{path} is refused, as EHOS would refuse it:\n#{reasons}")
    end
  end
end
