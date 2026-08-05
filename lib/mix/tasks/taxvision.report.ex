defmodule Mix.Tasks.Taxvision.Report do
  @shortdoc "The conformance report for a period — four questions, one page"

  @moduledoc """
  Assembles the screen's four questions into one artifact for the client.

  This task is **in the client tree**, not in `pns.*`, and that is the same
  boundary as for rendering: the engine produces the data, the client application
  produces the screen. The other tasks — `pns.graph`, `pns.trace`, `pns.check` —
  are developer views and stay where they are, because they have a different
  reader and answer a different question.

      mix taxvision.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
  """

  use Boundary, classify_to: Taxvision.Report
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, and this
    # report is in Polish and does get redirected to a file.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} = OptionParser.parse!(args, strict: [since: :string, until: :string, output: :string])

    Mix.Task.run("app.start")
    PNS.Registry.load!()

    period = [since: at(opts[:since]), until: at(opts[:until])]

    text =
      PNS.Registry.contracts()
      |> Enum.map(&(&1 |> PNS.Conformance.report(period) |> Taxvision.Report.render()))
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
