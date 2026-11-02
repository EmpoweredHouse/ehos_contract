defmodule Mix.Tasks.EhOsContract.Report do
  @shortdoc "Prints the conformance report: what the code did against what the contracts say"

  @moduledoc """
  Prints the conformance report of the application for a period. The report has a
  section for each contract, then a section for each process module.

  > **The task starts the whole application.**
  > The report reads the log through the repo of the application, so the task starts
  > the application. Run it only with the code that is deployed. The task records a
  > deployment, and starts the subscriptions, the relays and Oban. So effects can call external
  > systems from where you run it. If your code differs from the deployed code, the
  > recorded deployment changes the answer to question 4. The engine also rebuilds
  > each changed process manager at once. It also rebuilds each changed read model
  > that has `reset/0`. A rebuilt process manager forgets its runs. To read the report of a
  > running host without this, use the
  > [JSON API of the dashboard](conformance.md#the-dashboard).

      mix eh_os_contract.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
      mix eh_os_contract.report --since 2026-07-01T00:00:00Z --output july.md

  | Option | Value | If you leave it out |
  | --- | --- | --- |
  | `--since` | the start of the period, ISO 8601 with an offset (`Z`) | the period has no start |
  | `--until` | the end of the period, ISO 8601 with an offset | the period has no end |
  | `--output` | a file | the report goes to the terminal |

  A time without an offset stops the task with an error. The moment of judgement is
  always the current time.

  ## What the report answers

  The report answers four questions:

  1. Which declared paths were never taken?
  2. Which transitions occurred that the contract does not declare?
  3. Which promises were broken?
  4. Which version of the contract is deployed, and since when?

  The section of a contract answers questions 1, 2 and 4. The section of a process
  module answers question 3. Around the answers, the report shows what explains
  them:

  - steps in progress or failing;
  - scenarios never observed;
  - declarations that changed;
  - events written under earlier versions.

  [The conformance report](conformance.md) tells what each section says, and which
  events each number reads.
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
