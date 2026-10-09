defmodule Mix.Tasks.EhOsContract.Report do
  @shortdoc "Prints the conformance report for a period: what the code did against what the contracts say"

  @moduledoc """
  Prints the conformance report of the application for a period: a section for each
  contract, then one for each process module, if there are any.

  Each contract's section answers four questions about it: which declared paths were
  never taken, which transitions happened that the contract does not declare, which
  promises were broken, and which version of the contract was deployed, and since
  when. Around them it shows what explains the answers: steps in progress or
  failing, scenarios never observed, declarations that changed, and events written
  under earlier versions.

      mix eh_os_contract.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
      mix eh_os_contract.report --since 2026-07-01T00:00:00Z --output july.md

  `--since` and `--until` take ISO 8601 times with an offset (`Z`), and either may
  be left out. The task starts the application, since the report reads the log
  through its repo. `--output` writes the report to a file.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Contract labels can carry non-ASCII characters regardless of the report's
    # own language, and Erlang keeps stdout in latin1 when the output is not a
    # terminal.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args, strict: [since: :string, until: :string, output: :string])

    Mix.Task.run("app.start")
    EhOsContract.Registry.load!()

    period = [since: at(opts[:since]), until: at(opts[:until])]

    text =
      (EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes())
      |> Enum.map(
        &(&1
          |> EhOsContract.Conformance.report(period)
          |> EhOsContract.Report.render())
      )
      |> Enum.join("\n")

    case opts[:output] do
      nil ->
        Mix.shell().info(text)

      path ->
        # `File.write!` always writes UTF-8; redirecting through a pipe does not.
        File.write!(path, text)
        Mix.shell().info("written: #{path}")
    end
  end

  defp at(nil), do: nil

  defp at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> Mix.raise("--since and --until need an ISO8601 date, e.g. 2026-07-01T00:00:00Z")
    end
  end
end
