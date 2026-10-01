defmodule EhOsContract.TimerJob do
  @moduledoc """
  The Oban job that fires one timer of one process manager's run (v2 §12).

  **A fired timer does not call the process manager.** The job checks that its token
  is still the run's — a timer cancelled, set again, or already fired has another
  one or none — and appends `eh_os_contract.timer_elapsed` to the run's own stream,
  `$pm:<key>:<correlation>`. The process manager reacts when its runner reaches that
  event, in order with everything else, so a replay sees the firing where it
  happened; the runners are woken once the firing commits. A job that runs twice may
  append two firings; the process manager takes the first, which removes the token,
  and ignores the second, so the timer's commands are dispatched once.

  **Due by `EhOsContract.Clock.now/0`.** Oban runs the job at its `scheduled_at`; a
  job run earlier than the timer's time — a test draining the queue, or a clock
  behind another node's — snoozes until then. A test moves time with
  `EhOsContract.Clock.at/2` around `EhOsContract.Testing.drain/1`.

  Its arguments are the process manager's key, the run's correlation, the timer's
  name, its token and its time: nothing of the run's data.
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      states: :incomplete
    ]

  import Ecto.Query

  alias EhOsContract.{Clock, Implementations, Model, ProcessManager, ProcessManagerRecord, Store}
  alias EhOsContract.Subscription.Runner

  @doc "The job for `timer` of the run `correlation` of process manager `key`, due `at`."
  @spec job(String.t(), String.t(), String.t(), map()) :: Oban.Job.changeset()
  def job(key, correlation, timer, %{"token" => token, "at" => at}) do
    new(
      %{
        "process_manager" => key,
        "correlation" => correlation,
        "timer" => timer,
        "token" => token,
        "at" => at
      },
      scheduled_at: at |> DateTime.from_iso8601() |> elem(1)
    )
  end

  @doc """
  Appends the timer's firing to the run's stream, if the timer is due and still the
  run's; snoozes one that is not due; does nothing for one that is no longer the
  run's; cancels one whose process manager is no longer deployed.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:snooze, pos_integer()} | {:cancel, String.t()}
  def perform(%Oban.Job{args: %{"at" => at} = args}) do
    {:ok, at, _} = DateTime.from_iso8601(at)

    case DateTime.diff(at, Clock.now(), :second) do
      early when early > 0 -> {:snooze, early}
      _due -> fire(args)
    end
  end

  defp fire(%{"process_manager" => key} = args) do
    case Implementations.consumer(key) do
      %{kind: :process_manager} = consumer ->
        fire(consumer, args)

      _gone ->
        {:cancel,
         "no process manager #{key} in this binary, so the timer belongs to a wiring that is " <>
           "no longer deployed"}
    end
  end

  defp fire(consumer, %{"process_manager" => key, "correlation" => correlation} = args) do
    %{"timer" => name, "token" => token} = args
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    {:ok, :ok} =
      Runner.transaction(repo, fn ->
        :ok = Store.lock(repo)

        case repo.one(
               from(r in ProcessManagerRecord,
                 where:
                   r.name == ^key and r.correlation == ^correlation and is_nil(r.completed_at)
               )
             ) do
          %{timers: %{^name => %{"token" => ^token} = timer}} ->
            append!(repo, consumer, correlation, args, timer)

          _gone ->
            :ok
        end
      end)

    :ok
  end

  defp append!(repo, consumer, correlation, args, timer) do
    %{contract: contract, name: name, key: key} = consumer
    stream = ProcessManager.stream(key, correlation)
    version = length(Store.read_stream(repo, stream, 0))

    {:ok, _} =
      Store.append(
        repo,
        [
          %{
            type: ProcessManager.elapsed(),
            contract: inspect(contract),
            contract_version: Model.fetch(contract).version,
            actor: "timer:#{name}",
            correlation_id: timer["correlation_id"],
            causation_id: timer["token"],
            occurred_at: Clock.now(),
            payload: Map.take(args, ~w(process_manager correlation timer token)),
            metadata: %{"issued_by" => "timer:#{name}:#{args["timer"]}"}
          }
        ],
        {:stream, stream, version}
      )

    # The process manager's runner reads it, so it is woken once this commits.
    Runner.notify_on_commit()
  end
end
