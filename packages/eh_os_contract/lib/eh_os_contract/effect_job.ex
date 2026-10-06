defmodule EhOsContract.EffectJob do
  @moduledoc """
  The Oban job that runs one effect delivered `:at_least_once` on one event (v2 §12).

  Dispatch inserts it in the transaction that appends the event, so the job exists
  exactly when the event does. **Its arguments are the effect's key, the event's id
  and the dispatched contract's application, and nothing else**: the job reads the
  event from the log when it runs, so no payload ever lands in `oban_jobs`, where the
  queue would keep what erasure means to remove. The application is where dispatch
  found the effect besides the configured ones, which the key's contract id cannot name
  (plan DD, ID4, #178).

  Oban delivers at least once, so an effect **will** see an event a second time. The
  contract names what makes that harmless (`idempotency:`, rule P3), and the event's
  `__meta__.id` is the key an effect passes on to the system it calls. An effect
  that has to put an external answer into the log records it with
  `EhOsContract.record/3`, as its `:system` actor.

  `:ok` finishes the job; `{:error, reason}` or an exception is retried, three
  attempts in all. What Oban keeps of a failure names the effect, the event's position
  and the module or kind of what failed, never a value (`EhOsContract.EffectJob.Failure`):
  a value may be personal data, and `oban_jobs` is beyond an erasure's reach. That holds
  for an exception, an exit, a throw, and a linked process the effect started crashing:
  exits are trapped while the effect runs. A job whose effect no module implements any more, or whose effect
  no longer takes the event's type, is cancelled, not retried: that wiring is not
  coming back, and two more identical failures would say nothing a third time.

  The queue is `:events`. Oban has to run on the repo dispatch appends
  through, or the job would not commit with the event, and dispatch refuses to
  insert it otherwise.
  """

  @max_attempts 3

  use Oban.Worker, queue: :events, max_attempts: @max_attempts

  # Seconds a job waits for a node that runs the code which wrote its event (plan W1).
  @newer_code_snooze 30

  alias EhOsContract.{Consumer, Event, Implementations}

  @doc """
  Oban's backoff over the attempts that ran (plan W1). A snooze raises `attempt` and
  `max_attempts` by one each, and Oban's default backoff scales `attempt` by
  `max_attempts` once that passes 20, so a job that waited out a long deploy would
  retry a real failure after days instead of seconds.
  """
  @impl Oban.Worker
  @spec backoff(Oban.Job.t()) :: pos_integer()
  def backoff(%Oban.Job{attempt: attempt, max_attempts: max_attempts} = job) do
    snoozed = max(max_attempts - @max_attempts, 0)
    Oban.Worker.backoff(%{job | attempt: max(attempt - snoozed, 1), max_attempts: @max_attempts})
  end

  @doc """
  The job for `effect`'s key and the event `event_id`, dispatched by a contract of
  `application`.
  """
  @spec job(String.t(), Ecto.UUID.t(), atom() | nil) :: Oban.Job.changeset()
  def job(effect, event_id, application \\ nil) do
    args = %{"effect" => effect, "event_id" => event_id}
    new(if application, do: Map.put(args, "application", Atom.to_string(application)), else: args)
  end

  @doc """
  Runs the effect on the event, read from the log: `:ok`, `{:error, reason}` to be
  retried, `{:snooze, seconds}` when the event was written by newer code than this node
  runs (`EhOsContract.NewerSchemaError`), or `{:cancel, reason}` when the wiring the
  job was enqueued for is gone —
  no module implements the effect, or it no longer takes the event's type.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :ok | {:error, term()} | {:snooze, pos_integer()} | {:cancel, String.t()}
  def perform(%Oban.Job{args: %{"effect" => key, "event_id" => event_id} = args}) do
    application = application(args["application"])

    with %{kind: :effect, module: module} = effect when module != nil <-
           Implementations.consumer(key, application),
         row = repo().get!(Event, event_id),
         true <- Map.has_key?(effect.callbacks, row.type) || {:dropped, row.type} do
      guarded(key, row, fn ->
        Consumer.handle!(
          Implementations.taking(effect, row.type),
          Consumer.decode!(row, application),
          []
        )
      end)
    else
      {:dropped, type} ->
        {:cancel,
         "effect #{key} no longer takes #{type}, so the job belongs to a wiring that is no " <>
           "longer deployed"}

      _gone ->
        {:cancel,
         "no module implements effect #{key} in this binary, so the job belongs to a wiring " <>
           "that is no longer deployed"}
    end
  end

  # Oban keeps a failed attempt in `oban_jobs.errors`: the exception, blamed — a
  # function clause's arguments — and formatted with its stacktrace, the banner of an
  # exit or a throw, or the reason an effect returned. Any of those can be the decoded
  # event, personal data in the clear that an erasure never reaches (v2 §14, §17). So
  # Oban is handed only what the engine records everywhere else: which effect, which
  # event, and the module or kind of what failed.
  #
  # Exits are trapped while the effect runs, so that a linked process it started —
  # `Task.async/1` — crashing becomes an exit this catches, rather than a signal that
  # kills the job with the crash's reason in hand. The flag goes back as it was.
  defp guarded(key, row, fun) do
    trapping = Process.flag(:trap_exit, true)

    result =
      try do
        fun.()
      rescue
        # Plan W1: newer code wrote the event. Snoozed, which Oban does not count against
        # `max_attempts`, so the job runs once a node with that code takes it.
        _newer in EhOsContract.NewerSchemaError ->
          {:snooze, @newer_code_snooze}

        exception ->
          failed(key, row, "raised #{inspect(exception.__struct__)}", __STACKTRACE__)
      catch
        :exit, reason ->
          failed(key, row, "exited with #{kind(reason)}", __STACKTRACE__)

        :throw, value ->
          failed(key, row, "threw #{kind(value)}", __STACKTRACE__)
      after
        Process.flag(:trap_exit, trapping)
      end

    case exits_after(key, row, result) do
      {:error, reason} ->
        {:error,
         "effect #{key} answered {:error, #{kind(reason)}} on the event at position " <>
           "#{row.position}"}

      other ->
        other
    end
  end

  # What trapping exits left in the mailbox once the effect returned: a linked process
  # that crashed fails the job, as it would have without trapping; a shutdown from the
  # job's supervisor is honoured now that the effect is done; a normal exit is nothing.
  defp exits_after(key, row, result) do
    receive do
      {:EXIT, _pid, :normal} ->
        exits_after(key, row, result)

      {:EXIT, _pid, reason} when reason == :shutdown or elem(reason, 0) == :shutdown ->
        exit(:shutdown)

      {:EXIT, _pid, reason} ->
        failed(key, row, "had a linked process exit with #{kind(reason)}", [])
    after
      0 -> result
    end
  end

  defp failed(key, row, what, stacktrace) do
    reraise EhOsContract.EffectJob.Failure,
            [message: "effect #{key} #{what} on the event at position #{row.position}"],
            without_arguments(stacktrace)
  end

  defp kind(reason) when is_atom(reason), do: inspect(reason)
  defp kind(%module{}), do: "%#{inspect(module)}{}"

  defp kind(reason) when is_tuple(reason) and tuple_size(reason) > 0 and is_atom(elem(reason, 0)),
    do: "{#{inspect(elem(reason, 0))}, ...}"

  defp kind(_reason), do: "a value"

  # A stacktrace's first entry carries a function clause's arguments, and a fun's
  # entry may too; the arity says enough.
  defp without_arguments(stacktrace) do
    Enum.map(stacktrace, fn
      {module, function, args, location} when is_list(args) ->
        {module, function, length(args), location}

      {fun, args, location} when is_list(args) ->
        {fun, length(args), location}

      entry ->
        entry
    end)
  end

  # An application this node has not loaded holds nothing it could run, and its name is
  # never made an atom from a job's arguments.
  defp application(nil), do: nil

  defp application(name) do
    Enum.find_value(Application.loaded_applications(), fn {app, _, _} ->
      Atom.to_string(app) == name and app
    end)
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end

defmodule EhOsContract.EffectJob.Failure do
  @moduledoc """
  What an `EhOsContract.EffectJob` raises in place of its effect's exception: the
  effect, the event's position and the exception's module, and no value, since Oban
  keeps it in `oban_jobs.errors`. The stacktrace is the effect's, without arguments.
  """

  defexception [:message]
end
