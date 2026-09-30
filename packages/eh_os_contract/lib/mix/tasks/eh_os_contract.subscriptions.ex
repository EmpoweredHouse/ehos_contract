defmodule Mix.Tasks.EhOsContract.Subscriptions do
  @shortdoc "Where each subscription stands, and a person's way past a poison event"

  @moduledoc """
  Lists every consumer fed from the log (`EhOsContract.Subscription`): how far it
  has read, and whether it is `running`, `stale`, `rebuilding` or `failing`.

      mix eh_os_contract.subscriptions

  A subscription that fails on an event stops there and is never moved past it by
  itself, because an ordered consumer that skips is a read model that silently lies
  (v2 §12). Moving it is a decision, and these are the two a person can take:

      mix eh_os_contract.subscriptions --skip DispatchRig.Ledger:read_model:ledger_lines
      mix eh_os_contract.subscriptions --reset DispatchRig.Ledger:read_model:ledger_lines

  `--skip` moves a `failing` subscription past the one event it fails on, which is
  then never applied — an erasure among them: the read model keeps that subject's
  copy until it is reset. `--reset` empties a read model through its `reset/0` and
  replays the whole log into it; a read model without `reset/0` cannot be reset. A
  policy keeps no rows, so `--reset` moves it back to the beginning of the log, and
  it reacts to the history a new policy leaves alone. A relay (`<contract>:relay:<name>`,
  `EhOsContract.Relay`) is the same: `--skip` means the event never leaves the
  application, and `--reset` publishes the whole log again, under the same ids.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.{Implementations, Subscription}

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [skip: :string, reset: :string])

    Mix.Task.run("app.start")
    repo = Application.fetch_env!(:eh_os_contract, :repo)

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
    end
  end

  defp reset(repo, key) do
    case Subscription.rebuild(repo, key) do
      :ok ->
        case Implementations.consumer(key) do
          %{kind: :policy} ->
            Mix.shell().info("#{key}: moved back to the beginning of the log, to react to it")

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
    do: ", fails at #{row.failed_position} (#{row.failure}, #{row.attempts} attempts)"
end
