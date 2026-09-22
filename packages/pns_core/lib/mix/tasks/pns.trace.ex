defmodule Mix.Tasks.Pns.Trace do
  @shortdoc "Evaluates `trace` assertions against the log, per run"

  @moduledoc """
  Prints the verdicts of the contracts' assertions against what is in the log.

  By default **numbers, not a list of runs** — because the report answers the
  question about the assertion, not about a specific company. `--instances` turns
  on the single-run view that notes §9 foresee for debugging ("what happened to
  invoice 4712"), not for the evidence report.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} = OptionParser.parse!(args, strict: [instances: :boolean, since: :string])

    Mix.Task.run("app.start")
    PNS.Registry.load!()

    since = opts[:since] && parse_since(opts[:since])

    for %{contract: contract, trace: name, verdicts: verdicts} <-
          PNS.Trace.evaluate_all(since: since) do
      report(contract, name, verdicts, opts)
    end
  end

  defp report(contract, name, verdicts, opts) do
    s = PNS.Trace.summary(verdicts)
    trace = Enum.find(contract.traces(), &(&1.name == name))

    Mix.shell().info("\n#{name}  (#{inspect(contract)})")

    Mix.shell().info(
      "  after #{trace.from} → #{trace.eventually}#{window(trace)}#{alternative(trace)}"
    )

    if s.instances == 0 do
      # Zero runs is **no basis for a verdict**, not zero violations. Reading it
      # the other way round would turn an unimplemented process into a green
      # report.
      Mix.shell().info("  no run reached #{trace.from} — nothing to judge")
    else
      Mix.shell().info(
        "  satisfied #{s.satisfied}/#{s.instances}" <>
          " (#{s.satisfied_via_eventually} via eventually, #{s.satisfied_via_or_else} via or_else)" <>
          ", violated #{s.violated}, pending #{s.pending}"
      )
    end

    if opts[:instances] do
      for v <- verdicts do
        via = if v.via, do: " via #{v.via}", else: ""

        Mix.shell().info(
          "    #{String.pad_trailing(to_string(v.verdict), 10)}#{via}  #{v.instance_id}"
        )
      end
    end
  end

  defp window(%{within: nil}), do: ""
  defp window(%{within: {n, unit}}), do: " within #{n} #{unit}"

  defp alternative(%{or_else: nil}), do: ""
  defp alternative(%{or_else: event}), do: ", or else #{event}"

  defp parse_since(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> Mix.raise("--since needs an ISO8601 date, e.g. 2026-07-01T00:00:00Z")
    end
  end
end
