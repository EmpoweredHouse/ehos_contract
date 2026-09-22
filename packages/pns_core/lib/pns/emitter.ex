defmodule PNS.Emission do
  @moduledoc "An intention to emit an event, returned by a pure decision function."
  defstruct [:name, :payload]

  @type t :: %__MODULE__{name: atom(), payload: map()}
end

defmodule PNS.Payload do
  @moduledoc """
  The payload is declared in the contract, so deserialisation is typed.

  This is one of the things the contract gives for free: after a round trip
  through JSON (the queue, the database) keys come back as strings, but the
  contract knows which fields were declared — so a synchronous and an asynchronous
  handler see **the same shape**.

  **That promise used to be about keys only, and the client was paying for it.**
  Values were passed through untouched, so a `:timestamp` was a `DateTime` in a
  synchronous handler and an ISO 8601 string in an asynchronous one. Domain code
  worked around it by serialising by hand at the emit site — a field declared as a
  point in time holding text, because two shapes were worse than one degraded one.
  `cast/2` now restores values as well, so the workaround is unnecessary.

  Only `:timestamp` needs restoring, and that is the rule rather than a list: **cast
  repairs exactly what JSON destroys.** Integers, strings and identifiers survive the
  round trip; a point in time does not.

  ## Strict on write, defensive on read

  `validate!/2` runs on the way **in** and refuses a payload that does not match its
  declaration. Nothing validates on the way out, and that is deliberate rather than an
  omission: the log holds events written under older contracts, and a report that
  cannot read history is worse than one that reads it loosely. ADR §7-8 says the
  payload is *read defensively*, and this is what that means in code.
  """

  @doc """
  The payload as it is stored: string keys, because the column is JSON.

  Values are left to the JSON encoder, which turns a `DateTime` into ISO 8601 — the
  same text `cast/2` reads back. The round trip is lossy in one direction only, and
  that is the direction `cast/2` repairs.
  """
  @spec to_storage(map()) :: map()
  def to_storage(payload) do
    Map.new(payload, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Restores the declared fields: atom keys, and values in the shape the type names.

  An undeclared field keeps its string key and its value untouched, so an unknown
  field can neither exhaust the atom table nor be silently reinterpreted.
  """
  @spec cast(map(), map()) :: map()
  def cast(event_def, payload) do
    declared = event_def.payload

    Map.new(payload, fn {key, value} ->
      case Enum.find(Map.keys(declared), &(to_string(&1) == to_string(key))) do
        nil -> {to_string(key), value}
        field -> {field, restore(Map.fetch!(declared, field), value)}
      end
    end)
  end

  # Restoration is not coercion, and the difference matters. A `:timestamp` arrives as
  # text because JSON has no other way to carry one, so reading it back is repairing a
  # known loss. An `:integer` arriving as `"5"` is not a loss — JSON carries integers —
  # so it is a caller passing the wrong thing, and coercing it would hide the defect
  # that `validate!/2` exists to surface.
  @spec restore(atom(), term()) :: term()
  defp restore(:timestamp, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> value
    end
  end

  defp restore(_type, value), do: value

  @doc """
  Raises unless every declared field is present and holds what its type names.

  Three failures, and the first is the one that makes the others worth having:

  **A declared field that is absent.** The contract says this fact carries a period and
  it does not. Nothing caught that, and it is the exact shape of hole this product
  exists to detect — a declaration nobody honoured, which reads as satisfied.

  **A declared field holding `nil`.** There is no optional field in the payload DSL: a
  field is declared or it is not. `nil` is the absent case wearing a key.

  **A value of the wrong shape.** The contract says `:integer` and a string arrives.

  Undeclared fields are **not** rejected. They are already refused where it matters —
  a handler emitting an undeclared event does not get that far — and a payload carrying
  one extra key is visible in the log rather than silent, which is the same argument
  that made the retention check a report instead of a gate.
  """
  @spec validate!(module(), atom(), map(), map()) :: :ok
  def validate!(contract, type, event_def, payload) do
    for {field, declared_type} <- event_def.payload do
      case Map.fetch(payload, field) do
        :error ->
          bail!(contract, type, field, "is declared and missing from the payload")

        {:ok, nil} ->
          bail!(
            contract,
            type,
            field,
            "is declared as #{inspect(declared_type)} and holds nil. A payload field is " <>
              "declared or it is not — there is no optional one, so nil is the missing case " <>
              "with a key on it"
          )

        {:ok, value} ->
          holds?(declared_type, value) ||
            bail!(
              contract,
              type,
              field,
              "is declared as #{inspect(declared_type)} and holds #{inspect(value)}"
            )
      end
    end

    :ok
  end

  # What each type accepts. `:id` takes an integer as well as text, because a client
  # keying on a database sequence should not have to call it a string — what the
  # identifier refers to is theirs, and so is its representation.
  #
  # Bare `:enum` stays "a name, any name" — a contract that never declared a set is
  # not asking for one. `{:enum, [...]}` checks membership instead, compared as
  # strings so an atom supplied synchronously and the string the queue hands back
  # asynchronously are judged the same way.
  @spec holds?(atom() | {:enum, [atom() | String.t()]}, term()) :: boolean()
  defp holds?(:id, value), do: (is_binary(value) and value != "") or is_integer(value)
  defp holds?(:string, value), do: is_binary(value)
  defp holds?(:integer, value), do: is_integer(value)
  defp holds?(:timestamp, value), do: match?(%DateTime{}, value)
  defp holds?(:enum, value), do: is_atom(value) or is_binary(value)

  defp holds?({:enum, values}, value) do
    (is_atom(value) or is_binary(value)) and to_string(value) in Enum.map(values, &to_string/1)
  end

  @spec bail!(module(), atom(), atom(), String.t()) :: no_return()
  defp bail!(contract, type, field, what) do
    raise ArgumentError,
          "#{inspect(contract)}, event #{inspect(type)}: `#{field}` #{what}. The contract " <>
            "declares what a fact carries, and a declaration nothing enforces is a promise " <>
            "the report will repeat as though it were measured."
  end
end

defmodule PNS.Emitter do
  @moduledoc """
  Dispatch is split along the **transaction boundary**, not by developer
  preference (ADR §9-10, notes §4).

  The whole decision is visible in one function, and that is deliberate: if it
  does not fit in a few dozen lines, the argument for an emission layer of our own
  is weaker than the record claims.
  """

  alias PNS.{Event, EventHandling, Payload, Registry}

  @doc """
  Emits an event: the write to the log, the synchronous handlers in the same
  transaction, and asynchronous jobs inserted in that same transaction.

  A synchronous handler that raises takes down the whole transaction — and that is
  only correct because such handlers are confined to derived state in the same
  database. There is nothing to retry, because nothing happened. What it leaves
  behind is a `PNS.HandlerFailure`, written after the rollback rather than inside it.
  """
  @spec emit(module(), atom(), map(), map()) :: {:ok, Event.t()} | {:error, term()}
  def emit(contract, type, payload, ctx \\ %{}) do
    repo = repo()
    ctx = default_ctx(ctx)

    in_own_transaction(repo, fn -> do_emit(repo, contract, type, payload, ctx) end)
  end

  @doc "Like `emit/4`, but returns the event or raises."
  @spec emit!(module(), atom(), map(), map()) :: Event.t()
  def emit!(contract, type, payload, ctx \\ %{}) do
    {:ok, event} = emit(contract, type, payload, ctx)
    event
  end

  @doc """
  Emits the list of intentions returned by a decision function.

  Correlation is established **once, for the whole list**. That came out as a bug
  on the first test run: without it every event from one command got its own
  `correlation_id`, so one business operation fell apart in the log into four
  unrelated facts — and the very chain this log exists for could not be
  reconstructed.

  Intentions from one decision function are **siblings**, not a chain: none of
  them caused another, the same command caused all of them. Hence a shared
  correlation and a shared cause, rather than causation between them.
  """
  @spec emit_all(module(), [PNS.Emission.t()], map()) :: {:ok, [Event.t()]} | {:error, term()}
  def emit_all(contract, emissions, ctx \\ %{}) do
    repo = repo()
    ctx = default_ctx(ctx)

    run = fn ->
      Enum.map(emissions, fn %PNS.Emission{name: name, payload: payload} ->
        do_emit(repo, contract, name, payload, ctx)
      end)
    end

    in_own_transaction(repo, run)
  end

  # The failure trace is written **here** and not where the failure is noticed,
  # because that code runs inside the transaction that is about to disappear. By the
  # time this frame rescues, the rollback has happened and the connection is free, so
  # a plain insert commits — no second connection, no task, nothing writing around
  # the sandbox in tests.
  #
  # When the caller opened the transaction, this never gets a turn: the exception
  # goes into their transaction, and the trace is theirs to write. Stated in
  # `PNS.HandlerFailure` rather than worked around, because a durable write from
  # inside somebody else's doomed transaction is not possible on one connection.
  @spec in_own_transaction(module(), (-> term())) :: {:ok, term()} | {:error, term()}
  defp in_own_transaction(repo, run) do
    own? = not repo.in_transaction?()

    try do
      if own?, do: repo.transaction(run), else: {:ok, run.()}
    rescue
      failure in PNS.SyncHandlerError ->
        # Recorded only when the transaction was ours. Inside somebody else's, this
        # insert would roll back with theirs — so it is skipped rather than written
        # and lost.
        if own?, do: PNS.HandlerFailure.record!(failure)

        # Unwrapped in **both** cases. The wrapper carries context to the recorder
        # and stops here: a caller keeps seeing the exception the handler raised,
        # with the stacktrace that points at the handler. Letting it out would make
        # a diagnostic mechanism a breaking change in every caller's error handling.
        reraise failure.original, failure.stacktrace
    end
  end

  @spec do_emit(module(), module(), atom(), map(), map()) :: Event.t()
  defp do_emit(repo, contract, type, payload, ctx) do
    unless contract.event?(type) do
      raise ArgumentError,
            "#{inspect(contract)} does not declare event #{inspect(type)}. " <>
              "Dynamic publication is illegal — whether the static graph is a fact or a " <>
              "heuristic depends on it."
    end

    guard_against_cycle!(type, ctx)

    event_def = contract.event(type)
    correlation_id = ctx[:correlation_id] || Ecto.UUID.generate()

    # Three steps in this order, and the order was wrong on the first attempt.
    #
    # **Cast first**, so keys are atoms and a `:timestamp` is a point in time whichever
    # way the caller expressed it. Doing this before `retain` also means the policy
    # finds its fields when a caller passed string keys.
    #
    # **Validate second, on the payload as supplied.** Validating after `retain` looked
    # right — it checks what actually gets stored — and it is backwards. `retain`
    # transforms the value: `:hash` turns anything into a hex string, so a `:string`
    # field could never fail and an `:integer` field could never pass, and the check
    # would stop applying to exactly the fields that carry sensitive content. `:drop`
    # is worse: the field disappears, so a declared field would be permanently missing
    # and every such event would be refused. A declared type describes the fact; what
    # the log keeps of it is a storage policy applied afterwards.
    #
    # **Retain third, once**, and what comes out is the only version of this payload in
    # the system: the log, the synchronous handlers and the job's arguments all get it.
    # Giving handlers the full value and the log a hash was tempting, but then an
    # asynchronous handler receives the full value through `oban_jobs` — a table
    # `retain` does not cover — and a retention policy the queue can walk around is
    # worse than none, because it looks satisfied. The consequence belongs to the
    # contract rather than to the code: a handler that needs the raw value cannot have
    # that field on `:hash`.
    supplied = Payload.cast(event_def, payload)
    validate_payload!(contract, type, event_def, supplied)
    stored = apply_retain(supplied, event_def)

    # Computed from the payload **after** `retain`, so the run key is
    # reproducible from the log alone — rather than from the log plus knowledge
    # of what fell away on the way.
    {process, instance_id} = PNS.Instance.key(contract, type, stored)

    event =
      repo.insert!(%Event{
        type: to_string(type),
        contract: inspect(contract),
        contract_version: contract.version(),
        process: process,
        instance_id: instance_id,
        correlation_id: correlation_id,
        causation_id: ctx[:causation_id],
        payload: Payload.to_storage(stored),
        # Never nil: `default_ctx/1` fills this in before `do_emit/5` ever runs.
        actor: to_string(ctx[:actor]),
        occurred_at: DateTime.utc_now()
      })

    # Context for handling: correlation carries on, and this event becomes the
    # cause of everything that follows from it.
    child_ctx = %{
      correlation_id: correlation_id,
      causation_id: event.id,
      actor: ctx[:actor],
      # The ancestors of whatever comes next, root first. Strings rather than atoms
      # on purpose: this list crosses into job arguments as JSON, and converting
      # back would ask the atom table to vouch for a name that may have been
      # removed since the job was queued.
      chain: chain(ctx) ++ [to_string(type)]
    }

    dispatch_sync(repo, contract, type, stored, child_ctx, event)
    dispatch_async(type, stored, child_ctx, event)

    event
  end

  @doc """
  The causal ancestors of an event, root first, as they travel in a context.

  Public because `PNS.Job` has to put the chain back together on the other side of
  the queue, and a cycle that is only caught on one of the two dispatch paths is a
  cycle that moves to the other one.
  """
  @spec chain(map()) :: [String.t()]
  def chain(ctx), do: Map.get(ctx, :chain) || []

  # A cycle is the same event type appearing twice **on one path** from the root
  # emission, and nothing else. Three cheaper rules were wrong:
  #
  # A depth limit needs a number nobody can justify, and the number is what decides
  # whether a legitimate long chain works. The declared graph gives the bound for
  # free — a path without a repeat cannot be longer than the number of declared
  # events.
  #
  # "The same type twice anywhere in this transaction" false-positives on a diamond:
  # one command emits A, A's handlers emit B and C, and both publish D. Two D's, no
  # cycle, because neither is an ancestor of the other.
  #
  # And a static check on the declared graph cannot do it, because a backward edge is
  # **not** a cycle. The rig has one on purpose — it is the acceptance criterion of
  # stage 1.3 — so forbidding backward edges would forbid a shape the workshop
  # described: a turnover with no invoice, then the invoice arrives and the pair
  # closes.
  # Both guards report before they raise, and the reporting is the same three lines
  # twice rather than a shared wrapper: what a violation *is* differs per guard, and a
  # generic reporter would have to be told, which is the wrapper earning nothing.
  @spec validate_payload!(module(), atom(), map(), map()) :: :ok
  defp validate_payload!(contract, type, event_def, payload) do
    Payload.validate!(contract, type, event_def, payload)
  rescue
    error ->
      PNS.Telemetry.contract_violation(:payload, %{contract: contract, event_type: type})
      reraise error, __STACKTRACE__
  end

  @spec guard_against_cycle!(atom(), map()) :: :ok
  defp guard_against_cycle!(type, ctx) do
    ancestors = chain(ctx)

    if to_string(type) in ancestors do
      path = Enum.join(ancestors ++ [to_string(type)], " → ")

      PNS.Telemetry.contract_violation(:cycle, %{
        event_type: type,
        # The path, as names. It is the only thing that makes this actionable, and it
        # is names rather than values, so it stays on the right side of the retention
        # rule in `PNS.Telemetry`.
        chain: ancestors ++ [to_string(type)]
      })

      raise ArgumentError,
            "emitting #{inspect(type)} would close a cycle: #{path}. One event caused another " <>
              "that caused it again, so without this the chain runs until the stack or the " <>
              "connection gives out. A backward edge is legal and this is not one — it is the " <>
              "same fact causing itself. Break the loop in the contract: the second occurrence " <>
              "is a different business fact and needs its own event, or the handler should stop " <>
              "publishing what caused it. Making a handler asynchronous does **not** help — the " <>
              "chain travels with the job, so the loop only gets slower."
    end

    :ok
  end

  @spec dispatch_sync(module(), module(), atom(), map(), map(), Event.t()) :: :ok
  defp dispatch_sync(repo, contract, type, payload, ctx, event) do
    for handler <- Registry.sync_handlers_for(type) do
      started = System.monotonic_time(:microsecond)

      span = %{
        handler: handler.module,
        contract: contract,
        event_type: type,
        instance_id: event.instance_id,
        correlation_id: ctx.correlation_id,
        async: false
      }

      result =
        try do
          # A span rather than a bespoke event: it emits `:start`, then `:stop` or
          # `:exception`, in the shape every Elixir observability tool already reads.
          # The `:exception` half is what stage 2.3 added by hand with its own
          # measurement name — corrected here, because a package that emits
          # almost-conventional telemetry costs each integrator a special case.
          PNS.Telemetry.handler_span(span, fn -> handler.module.handle(payload, ctx) end)
        rescue
          already in PNS.SyncHandlerError ->
            # A handler further down the chain failed and is already described. This
            # handler did not fail — it emitted, and something downstream died. Left
            # unguarded, the wrapping would attribute the fault to whoever is highest
            # in the chain and emit one telemetry event per frame for one failure.
            reraise already, __STACKTRACE__

          error ->
            # The span has already reported the exception; this rescue exists for the
            # durable half. The handling row disappears along with the transaction —
            # correct, since nothing happened — and it used to disappear leaving
            # nothing at all, which is the gap ADR §13 found by building this layer.
            #
            # Wrapped rather than reraised bare: the frame that can durably write this
            # is outside the transaction and knows none of the context.
            reraise PNS.SyncHandlerError.exception(
                      handler: handler.module,
                      contract: contract,
                      event_type: type,
                      correlation_id: ctx.correlation_id,
                      instance_id: event.instance_id,
                      original: error,
                      stacktrace: __STACKTRACE__
                    ),
                    __STACKTRACE__
        end

      repo.insert!(%EventHandling{
        event_id: event.id,
        handler: inspect(handler.module),
        status: "ok",
        duration_us: System.monotonic_time(:microsecond) - started,
        inserted_at: DateTime.utc_now()
      })

      # A handler may return further intentions — they go in the same transaction.
      case result do
        {:ok, emissions} when is_list(emissions) ->
          # Before emitting, not after: an undeclared emission must not reach the log
          # at all, or the graph it contradicts is already wrong by the time anyone
          # finds out.
          PNS.Handler.verify_publications!(handler, emissions)

          Enum.each(emissions, fn %PNS.Emission{name: name, payload: p} ->
            do_emit(repo, contract, name, p, ctx)
          end)

        _ ->
          :ok
      end
    end

    :ok
  end

  @spec dispatch_async(atom(), map(), map(), Event.t()) :: :ok
  defp dispatch_async(type, payload, ctx, event) do
    for handler <- Registry.async_handlers_for(type) do
      # The job insert goes in the same transaction — that is an outbox for free,
      # and it is the property that decided in favour of Oban.
      #
      # The trap from notes §3: the job runs later, in a different BEAM process,
      # so correlation has to be serialised into its arguments. Without that the
      # chain breaks at exactly the boundary the most interesting processes cross.
      %{
        "handler" => inspect(handler.module),
        "event_id" => event.id,
        "event_type" => to_string(type),
        "payload" => Payload.to_storage(payload),
        "correlation_id" => ctx.correlation_id,
        "causation_id" => ctx.causation_id,
        # The chain crosses the queue with correlation and causation, for the same
        # reason they do: a cycle through the queue does not blow the stack, it just
        # runs forever more slowly. Catching it on one path only moves the failure.
        "chain" => ctx.chain,
        # Never nil, for the same reason as the event row: `default_ctx/1` fills
        # it in before any `ctx` reaches here.
        "actor" => to_string(ctx[:actor])
      }
      |> PNS.Job.new()
      |> Oban.insert!()
    end

    :ok
  end

  @spec apply_retain(map(), map()) :: map()
  defp apply_retain(payload, event_def) do
    Enum.reduce(event_def.retain, payload, fn {field, policy}, acc ->
      case {policy, Map.fetch(acc, field)} do
        {:persist, _} -> acc
        {_, :error} -> acc
        {:drop, _} -> Map.delete(acc, field)
        {:hash, {:ok, value}} -> Map.put(acc, field, hash(value))
      end
    end)
  end

  @spec hash(term()) :: String.t()
  defp hash(value) do
    "sha256:" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(value))
       |> Base.encode16(case: :lower)
       |> binary_part(0, 16))
  end

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # the host's repo module was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: Application.fetch_env!(:pns, :repo)

  # Both entry points fill in the same two defaults before anything else runs, so
  # every event this module writes carries a correlation id and a non-nil actor
  # regardless of what the caller supplied.
  @spec default_ctx(map()) :: map()
  defp default_ctx(ctx) do
    ctx
    |> Map.put_new_lazy(:correlation_id, &Ecto.UUID.generate/0)
    |> Map.put_new(:actor, PNS.Auth.system_actor())
  end
end
