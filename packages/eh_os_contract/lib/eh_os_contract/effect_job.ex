defmodule EhOsContract.EffectJob do
  @moduledoc """
  The Oban job that runs one effect delivered `:at_least_once` on one event (v2 §12).

  Dispatch inserts it in the transaction that appends the event, so the job exists
  exactly when the event does. **Its arguments are the effect's key and the event's
  id, and nothing else**: the job reads the event from the log when it runs, so no
  payload ever lands in `oban_jobs` — the hole v1's jobs had, where the queue kept
  what retention meant to remove.

  Oban delivers at least once, so an effect **will** see an event a second time. The
  contract names what makes that harmless (`idempotency:`, rule P3), and the event's
  `__meta__.id` is the key an effect passes on to the system it calls. An effect
  that has to put an external answer into the log records it with
  `EhOsContract.record/3`, as its `:system` actor.

  `:ok` finishes the job; `{:error, reason}` or an exception is retried, three
  attempts in all. A job whose effect no module implements any more is cancelled,
  not retried: the module is not coming back, and two more identical failures would
  say nothing a third time.

  The queue is `:events`, the one v1's handler jobs used, so a host's Oban
  configuration does not change. Oban has to run on the repo dispatch appends
  through, or the job would not commit with the event, and dispatch refuses to
  insert it otherwise.
  """

  use Oban.Worker, queue: :events, max_attempts: 3

  alias EhOsContract.{Consumer, Event, Implementations}

  @doc "The job for `effect`'s key and the event `event_id`."
  @spec job(String.t(), Ecto.UUID.t()) :: Oban.Job.changeset()
  def job(effect, event_id), do: new(%{"effect" => effect, "event_id" => event_id})

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"effect" => key, "event_id" => event_id}}) do
    case Implementations.consumer(key) do
      %{kind: :effect, module: module} = effect when module != nil ->
        row = repo().get!(Event, event_id)
        Consumer.handle!(Implementations.taking(effect, row.type), Consumer.decode!(row), [])

      _gone ->
        {:cancel,
         "no module implements effect #{key} in this binary, so the job belongs to a wiring " <>
           "that is no longer deployed"}
    end
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
