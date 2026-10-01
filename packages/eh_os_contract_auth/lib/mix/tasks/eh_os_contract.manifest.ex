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
  with contracts names the one this image is in `ehos.yaml`, as
  `application: <name>`. What the manifest holds is `EhOsContract.Auth.Manifest`'s.

  EHOS keeps every manifest it is given, for good, and every key of `ehos.yaml` is in
  it as written: `ehos.yaml` must hold no secret, such as a password in a `migrate`
  argument. Nothing here can tell one. What the workload needs at run time comes
  from its environment.
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

    source =
      case opts[:ehos_yaml] do
        nil ->
          Path.join(project_dir(), "ehos.yaml")

        "" ->
          Mix.raise(
            "say which ehos.yaml to read: --ehos-yaml <file>, or leave it out for the project's"
          )

        source ->
          source
      end

    if same_file?(output, source),
      do: Mix.raise("--output names the ehos.yaml it is made from: #{source}")

    ehos_yaml = read_ehos_yaml!(source, opts[:ehos_yaml] == nil)

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    document =
      Manifest.build(
        ehos_yaml,
        EhOsContract.Registry.domains(),
        EhOsContract.Registry.contracts()
      )

    # Again, just before the write: a link made to ehos.yaml while the project compiled, or an
    # output that did not exist when it was first looked at, is judged now.
    if same_file?(output, source),
      do: Mix.raise("--output names the ehos.yaml it is made from: #{source}")

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode_to_iodata!(document, pretty: true) ++ ["\n"])
    Mix.shell().info("written: #{output}")
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end

  @known ~w(--output --ehos-yaml)

  # `--domain` chose the domain until the manifest was v2; `ehos.yaml` says it now. A known
  # option without its value is invalid to OptionParser as well, and is told so.
  defp refuse_arguments!(rest, invalid) do
    cond do
      Enum.any?(invalid, fn {option, _value} -> option == "--domain" end) ->
        Mix.raise(
          "--domain is gone: a project with more than one domain names the one this image is " <>
            "in ehos.yaml, as application: <name>"
        )

      option = Enum.find_value(invalid, fn {option, _value} -> option in @known && option end) ->
        Mix.raise("#{option} needs a value")

      invalid != [] ->
        Mix.raise("unknown options: #{Enum.map_join(invalid, " ", &elem(&1, 0))}")

      rest != [] ->
        Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

      true ->
        :ok
    end
  end

  # The directory of the project's `mix.exs`, which is the current one unless `MIX_EXS` says
  # otherwise.
  defp project_dir do
    case Mix.Project.project_file() do
      nil -> File.cwd!()
      file -> Path.dirname(file)
    end
  end

  # By name, and, when both exist, by the file they are: a link, or another case of the name on a
  # file system that ignores case, is the same ehos.yaml. Windows reports every inode as 0, so
  # there only the name is compared.
  defp same_file?(output, source) do
    Path.expand(output) == Path.expand(source) or
      case {File.stat(output), File.stat(source)} do
        {{:ok, %{inode: inode} = out}, {:ok, %{inode: inode} = src}} when inode != 0 ->
          out.major_device == src.major_device

        _other ->
          false
      end
  end

  # A FIFO with no writer, or a device, would hold the task for ever or fill its memory, so the
  # file is looked at before it is read, and read no further than one byte past what EHOS reads,
  # however it has grown since; the reader refuses that byte. A path swapped for a FIFO between
  # the look and the open can still hold the task: Erlang opens nothing without blocking.
  defp read_ehos_yaml!(path, default?) do
    max = EhosYaml.max_bytes()

    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size <= max ->
        :ok

      {:ok, %File.Stat{type: :regular, size: size}} ->
        Mix.raise("#{path} is #{size} bytes; EHOS reads at most #{max}")

      {:ok, %File.Stat{}} ->
        Mix.raise("#{path} is not a regular file")

      {:error, reason} ->
        hint =
          if default?,
            do:
              ". The manifest is ehos.yaml extended with what the contracts offer; name " <>
                "another file with --ehos-yaml",
            else: ""

        Mix.raise("cannot read #{path}: #{:file.format_error(reason)}#{hint}")
    end

    text =
      case File.open(path, [:read, :binary], &IO.binread(&1, max + 1)) do
        {:ok, :eof} ->
          ""

        {:ok, text} when is_binary(text) ->
          text

        {_open, {:error, reason}} ->
          Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")

        {:error, reason} ->
          Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
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
