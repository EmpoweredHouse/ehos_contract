defmodule Mix.Tasks.EhOsContract.Subscriptions do
  @shortdoc "Where each subscription stands, and a person's way past a poison event"

  @moduledoc """
  Lists every consumer fed from the log in order, with how far it has read and
  whether it is `running`, `stale`, `rebuilding` or `failing`, and moves one past a
  failure when a person decides to.

      mix eh_os_contract.subscriptions

  The consumers are the read models, process managers, policies delivered
  `:at_least_once`, and relays. One that fails on an event stops there, and nothing
  moves it past that event by itself: an ordered consumer that skipped events would
  be a read model that silently lies. Moving it is a person's decision, taken in one
  of two ways:

      mix eh_os_contract.subscriptions --skip dispatch_rig.ledger:read_model:ledger_lines
      mix eh_os_contract.subscriptions --reset dispatch_rig.ledger:read_model:ledger_lines

  - `--skip` moves a `failing` subscription past the one event it fails on, which is
    then never applied. If that event erased a subject, the read model keeps the
    subject's copy until it is reset. A subscription that failed while it was reset
    goes on with the reset past that event: a read model takes the rest of the log,
    and a process manager learns the rest of its runs without reacting to them.
  - `--reset` empties a read model through its `reset/0` and replays the whole log
    into it; a read model without `reset/0` cannot be reset.
  - `--reset` of a process manager forgets every run it steers and replays the log
    with its reactions suppressed, so it learns the runs again and issues nothing
    for them.
  - `--reset` of a policy moves it back to the beginning of the log, and it reacts to
    every event from there. The keys it derives from each event keep it from issuing
    again what it issued before.
  - A relay (`<contract id>:relay:<name>`, `EhOsContract.Relay`): `--skip` means that
    event never leaves the application, and `--reset` publishes the whole log again,
    under the same ids.
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

  defp while(%{resume_status: "rebuilding"}), do: " while it is reset"
  defp while(_row), do: ""
end
