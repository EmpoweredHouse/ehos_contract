defmodule Mix.Tasks.EhOsContract.Subscriptions do
  @shortdoc "Shows where each subscription stands, and moves one past an event that fails"

  @moduledoc """
  Shows each consumer that reads the log in order: how far it has read, and its
  status. It also moves one subscription past a failure, when a person decides to.

  > **The task starts the whole application.**
  > Run it only with the code that is deployed. The task records a deployment, and
  > registers each subscription with the code that you run. It also starts the
  > subscriptions, the relays and Oban, so effects can call external systems from
  > where you run it. If your code differs from the deployed code, the engine
  > rebuilds each changed process manager at once. It also rebuilds each changed read
  > model that has `reset/0`. A rebuilt process manager forgets its runs.

      mix eh_os_contract.subscriptions

  The consumers are the read models, the process managers, the policies delivered
  `:at_least_once`, and the relays. The task prints a line for each of them, with its
  status and its position: `running`, `stale`, `rebuilding` or `failing`. A line of a
  failing subscription also gives the position where it fails, the module of the
  exception and the count of attempts. A consumer with no row is `not registered`.

  ## Move a subscription past a failure

  A subscription that fails on an event tries it again, with a longer pause each time.
  After three attempts, it is `failing`, and stops at that event. It does not try again
  by itself: an ordered consumer that skipped events would be a read model with wrong
  rows that nobody sees. A person decides how to move it:

      mix eh_os_contract.subscriptions --skip dispatch_rig.ledger:read_model:ledger_lines
      mix eh_os_contract.subscriptions --reset dispatch_rig.ledger:read_model:ledger_lines

  If you give both options, the task does only `--skip`. The task stops with an error
  in these cases:

  - the name is not a subscription of the application;
  - you skip a subscription that is not `failing`;
  - you reset a read model without `reset/0`.

  A changed declaration also moves a failing subscription, at the next boot. The
  engine rebuilds a failing process manager, and a failing read model that has
  `reset/0`.

  `--skip` moves a `failing` subscription past the one event that it fails on. The
  consumer never applies that event.

  - If that event erased a subject, the read model keeps the copy of the subject until
    you reset it.
  - If the subscription failed while it replayed the log, the replay goes on after
    that event. A read model takes the rest of the log. A process manager learns the
    rest of its runs without a reaction to them. This includes the events appended
    while it was failing.

  `--reset` does a different thing for each kind of consumer:

  | Consumer | What `--reset` does |
  | --- | --- |
  | A read model | Empties it through its `reset/0`, and replays the whole log into it. A read model without `reset/0` cannot be reset. |
  | A process manager | Forgets each run that it steers, and replays the log with its reactions off. So it learns the runs again, and issues nothing for them. |
  | A policy | Moves it back to the start of the log. It reacts to each event from there. The keys that it derives from each event stop it from issuing again what it issued before. |
  | A relay (`<contract id>:relay:<name>`, `EhOsContract.Relay`) | Publishes the whole log again, under the same ids. |

  For a relay, `--skip` means that the event never leaves the application.

  [Repair or replay a subscription](subscriptions.md) tells when to use each one, and
  what each one costs.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.{Implementations, Subscription}

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [skip: :string, reset: :string])

    Mix.Task.run("app.start")
    repo = EhOsContract.Config.fetch!(:repo)

    cond do
      key = opts[:skip] -> skip(repo, key)
      key = opts[:reset] -> reset(repo, key)
      true -> :ok
    end

    list(repo)
  end

  defp skip(repo, key) do
    case Subscription.skip(repo, key) do
      :ok -> Mix.shell().info("#{key}: moved past the event it failed on, which is not applied")
      {:error, :not_failing} -> Mix.raise("#{key} is not failing, so there is nothing to skip")
      {:error, :not_registered} -> Mix.raise("#{key} is not a subscription of this application")
    end
  end

  defp reset(repo, key) do
    case Subscription.rebuild(repo, key) do
      :ok ->
        case Implementations.consumer(key) do
          %{kind: :policy} ->
            Mix.shell().info("#{key}: moved back to the beginning of the log, to react to it")

          %{kind: :relay} ->
            Mix.shell().info(
              "#{key}: moved back to the beginning of the log, to publish it again under the " <>
                "same ids"
            )

          _rebuilt ->
            Mix.shell().info("#{key}: emptied, and replayed from the beginning of the log")
        end

      {:error, :no_reset} ->
        Mix.raise(
          "#{key} defines no reset/0, so its rows cannot be emptied and it cannot be reset"
        )

      {:error, :not_registered} ->
        Mix.raise("#{key} is not a subscription of this application")
    end
  end

  defp list(repo) do
    rows = Map.new(Subscription.all(repo), &{&1.name, &1})

    lines =
      for consumer <- Implementations.subscribed() do
        case Map.get(rows, consumer.key) do
          nil -> "#{consumer.key}  not registered"
          row -> "#{consumer.key}  #{row.status} at #{row.position}#{failure(row)}"
        end
      end

    Mix.shell().info(if lines == [], do: "no subscriptions", else: Enum.join(lines, "\n"))
  end

  defp failure(%{failed_position: nil}), do: ""

  defp failure(row),
    do:
      ", fails at #{row.failed_position} (#{row.failure}, #{row.attempts} attempts)" <>
        while(row)

  defp while(%{resume_status: "rebuilding"}), do: " while it replays the log"
  defp while(_row), do: ""
end
