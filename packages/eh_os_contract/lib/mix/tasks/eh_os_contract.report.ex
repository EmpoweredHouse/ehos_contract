defmodule Mix.Tasks.EhOsContract.Report do
  @shortdoc "The conformance report for a period — four questions, one page"

  @moduledoc """
  Assembles the screen's four questions into one artifact.

  Moved here from `taxvision.report` (6 August) when rendering moved into the
  engine: the report stopped being a client-tree concern, so it sits beside
  `eh_os_contract.check` and `eh_os_contract.graph` rather than in `taxvision.*`.

      mix eh_os_contract.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z

  Every contract the registry finds (plan E7c), one section each.
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
      EhOsContract.Registry.v2_contracts()
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
