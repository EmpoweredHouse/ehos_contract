defmodule PNS.Job do
  @moduledoc """
  The Oban worker that runs one asynchronous handler.

  Oban gives at-least-once, so this event **will arrive a second time**.
  Idempotency here is not a good practice but a correctness condition — which is
  why the handler macro refuses `async: true` without a key.

  The whole thing is deliberately **not** wrapped in a transaction. An
  asynchronous handler exists precisely to do I/O against the outside world, and a
  transaction around I/O holds a pooled connection for the duration of the call.
  The price is that a failure between the effect and the handling row produces a
  repeat — and that is what the idempotency key is for.
  """

  use Oban.Worker, queue: :events, max_attempts: 3

  alias PNS.EventHandling


  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    case resolve(args["handler"]) do
      {:ok, handler} -> run(handler, args, attempt)
      :gone -> abandon(args, attempt)
    end
  end

  # A job whose handler no longer exists is **cancelled, not retried**, and recorded.
  #
  # Retrying is what used to happen and it was pure noise: the module is gone, so the
  # next two attempts fail identically, three seconds apart, and the job ends up
  # `discarded` with a `String.to_existing_atom` error that says nothing about why.
  #
  # The reason it is recorded rather than dropped is the deployment question from stage
  # 1.6. A queued job for a handler that no longer exists is a **path declared by a
  # wiring that is no longer deployed** — the same fact the wiring version exists to
  # separate from drift. Losing it would leave the log implying the work was never
  # scheduled at all.
  @spec abandon(map(), pos_integer()) :: {:cancel, String.t()}
  defp abandon(args, attempt) do
    reason =
      "handler #{args["handler"]} no longer exists, so this job belongs to a wiring that is " <>
        "no longer deployed. Cancelled rather than retried: the module is not coming back, and " <>
        "two more identical failures would say nothing a third time"

    repo().insert!(%EventHandling{
      event_id: args["event_id"],
      handler: args["handler"],
      attempt: attempt,
      status: "cancelled",
      duration_us: 0,
      error: reason,
      inserted_at: DateTime.utc_now()
    })

    {:cancel, reason}
  end

  @spec run(module(), map(), pos_integer()) :: :ok | {:error, term()}
  defp run(handler, args, attempt) do
    meta = handler.__pns_handler__()
    event_def = meta.contract.event(meta.event)
    payload = PNS.Payload.cast(event_def, args["payload"])

    ctx = %{
      # The trap from notes §3, closed here: the job runs in a different BEAM
      # process, so correlation has to be serialised into its arguments. Without
      # that the chain breaks at the boundary the most interesting processes
      # cross.
      correlation_id: args["correlation_id"],
      causation_id: args["causation_id"],
      # Rebuilt on this side so the cycle guard sees the whole path rather than
      # starting over at every queue hop. Jobs written before this field existed have
      # no chain, and an empty one is the honest answer: their path is unknown, not
      # empty. The cost is that a cycle already in the queue is caught one hop later.
      chain: args["chain"] || [],
      actor: args["actor"],
      attempt: attempt,
      idempotency_key: idempotency_key(event_def, args, payload)
    }

    started = System.monotonic_time(:microsecond)

    # Handling and emitting sit in **one** `try`, and that was a correction rather
    # than a preference. They used to be separated by the handling row, so a failure
    # while emitting arrived after the row had already recorded `ok` — the row
    # claiming a success whose consequence never happened. Anything that can fail
    # while acting on the handler's result belongs on the same side of the record:
    # an undeclared emission, a cycle, a rolled-back transaction.
    # The span covers this side too, so a handler is observable wherever it runs. Oban
    # emits its own span around the *job* — retries, cancellation, scheduling — and this
    # one is around the *handler*, which Oban knows nothing about. Two spans, two
    # subjects, no overlap.
    span = %{
      handler: handler,
      contract: meta.contract,
      event_type: meta.event,
      instance_id: ctx[:idempotency_key],
      correlation_id: ctx.correlation_id,
      async: true,
      attempt: attempt
    }

    {status, error} =
      try do
        PNS.Telemetry.handler_span(span, fn ->
          case handler.handle(payload, ctx) do
            :ok -> {"ok", nil}
            {:ok, list} when is_list(list) -> emit(meta, list, ctx)
            {:ok, _} -> {"ok", nil}
            {:error, reason} -> {"error", inspect(reason)}
          end
        end)
      rescue
        e -> {"error", Exception.message(e)}
      end

    repo().insert!(%EventHandling{
      event_id: args["event_id"],
      handler: args["handler"],
      attempt: attempt,
      status: status,
      duration_us: System.monotonic_time(:microsecond) - started,
      error: error,
      inserted_at: DateTime.utc_now()
    })

    if status == "ok", do: :ok, else: {:error, error}
  end

  @spec emit(map(), [PNS.Emission.t()], map()) :: {String.t(), String.t() | nil}
  defp emit(meta, emissions, ctx) do
    PNS.Handler.verify_publications!(meta, emissions)
    {:ok, _events} = PNS.Emitter.emit_all(meta.contract, emissions, ctx)
    {"ok", nil}
  end

  # The idempotency key comes from the `identity:` of **the event in the
  # contract**, not from the handler's declaration. A fact has one identity, while
  # one event can have many handlers — held on the handler it would drift between
  # them.
  #
  # Every segment is escaped before it is joined, in the same shape and for the same
  # reason as `PNS.Instance` escapes its own separator. Without it a two-field
  # identity holding `("x:y", "z")` and one holding `("x", "y:z")` produce the same
  # key — and the failure is the quiet kind: the client's idempotency table treats
  # the second fact as a repeat of the first, so its handler never runs and nothing
  # anywhere records that a consequence was skipped. A separator that can appear in
  # the values it separates is not a separator.
  @separator ":"
  @escaped "%3A"

  @spec idempotency_key(map(), map(), map()) :: String.t()
  defp idempotency_key(%{identity: nil}, args, _payload), do: args["event_id"]

  defp idempotency_key(%{identity: fields, name: name}, _args, payload) do
    values =
      Enum.map(fields, fn field ->
        Map.get(payload, field) || Map.get(payload, to_string(field))
      end)

    [name | values] |> Enum.map(&escape/1) |> Enum.join(@separator)
  end

  @spec escape(term()) :: String.t()
  defp escape(segment), do: segment |> to_string() |> String.replace(@separator, @escaped)

  # Three ways a handler can be gone, and all three mean the same thing to a job.
  #
  # `to_existing_atom` raises when nothing in the running system ever named that
  # module — a rename with jobs in the queue. The module can also exist as an atom and
  # not be loadable, or be loadable and no longer be a handler at all, which is what
  # happens when somebody removes `use PNS.Handler` but keeps the module. All three
  # are "this work has no owner any more".
  @spec resolve(String.t()) :: {:ok, module()} | :gone
  defp resolve(name) do
    module =
      case name do
        "Elixir." <> _ -> String.to_existing_atom(name)
        _ -> String.to_existing_atom("Elixir." <> name)
      end

    if Code.ensure_loaded?(module) and function_exported?(module, :__pns_handler__, 0) do
      {:ok, module}
    else
      :gone
    end
  rescue
    ArgumentError -> :gone
  end

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # `Taxvision.Repo` was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: Application.fetch_env!(:pns, :repo)
end
