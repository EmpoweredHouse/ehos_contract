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
  handler see **the same shape**. Without the contract that would have to be kept
  in two places.
  """

  @doc "The payload as it is stored: string keys, because the column is JSON."
  @spec to_storage(map()) :: map()
  def to_storage(payload) do
    Map.new(payload, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Restores the declared fields to atom keys, leaving anything undeclared as a
  string so an unknown field cannot exhaust the atom table.
  """
  @spec cast(map(), map()) :: map()
  def cast(event_def, payload) do
    declared = Map.keys(event_def.payload)

    Map.new(payload, fn {key, value} ->
      key_atom = Enum.find(declared, &(to_string(&1) == to_string(key)))
      {key_atom || to_string(key), value}
    end)
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

  @repo Application.compile_env!(:pns_prototype, :repo)

  @doc """
  Emits an event: the write to the log, the synchronous handlers in the same
  transaction, and asynchronous jobs inserted in that same transaction.

  A synchronous handler that raises takes down the whole transaction — and that is
  only correct because such handlers are confined to derived state in the same
  database. There is nothing to retry, because nothing happened.
  """
  @spec emit(module(), atom(), map(), map()) :: {:ok, Event.t()} | {:error, term()}
  def emit(contract, type, payload, ctx \\ %{}) do
    repo = repo()

    if repo.in_transaction?() do
      {:ok, do_emit(repo, contract, type, payload, ctx)}
    else
      repo.transaction(fn -> do_emit(repo, contract, type, payload, ctx) end)
    end
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
    ctx = Map.put_new_lazy(ctx, :correlation_id, &Ecto.UUID.generate/0)

    run = fn ->
      Enum.map(emissions, fn %PNS.Emission{name: name, payload: payload} ->
        do_emit(repo, contract, name, payload, ctx)
      end)
    end

    if repo.in_transaction?(), do: {:ok, run.()}, else: repo.transaction(run)
  end

  @spec do_emit(module(), module(), atom(), map(), map()) :: Event.t()
  defp do_emit(repo, contract, type, payload, ctx) do
    unless contract.event?(type) do
      raise ArgumentError,
            "#{inspect(contract)} does not declare event #{inspect(type)}. " <>
              "Dynamic publication is illegal — whether the static graph is a fact or a " <>
              "heuristic depends on it."
    end

    event_def = contract.event(type)
    correlation_id = ctx[:correlation_id] || Ecto.UUID.generate()

    # The `retain` policy is applied **once**, before anything else, and what
    # comes out of it is the only version of this payload in the system: it goes
    # to the log, to the synchronous handlers, and into the job's arguments.
    #
    # It was tempting to give handlers the full value and the log a hash — but
    # then an asynchronous handler receives the full value through `oban_jobs`,
    # that is, through a table `retain` does not cover. A retention policy the
    # queue can walk around is worse than none, because it looks satisfied.
    #
    # The consequence is explicit and belongs to the contract rather than to the
    # code: if a handler needs the raw value, that field cannot be `:hash`.
    stored = apply_retain(payload, event_def)
    cast_payload = Payload.cast(event_def, stored)

    # Computed from the payload **after** `retain`, so the run key is
    # reproducible from the log alone — rather than from the log plus knowledge
    # of what fell away on the way.
    {process, instance_id} = PNS.Instance.key(contract, type, cast_payload)

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
        actor: ctx[:actor] && to_string(ctx[:actor]),
        occurred_at: DateTime.utc_now()
      })

    # Context for handling: correlation carries on, and this event becomes the
    # cause of everything that follows from it.
    child_ctx = %{
      correlation_id: correlation_id,
      causation_id: event.id,
      actor: ctx[:actor]
    }

    dispatch_sync(repo, contract, type, cast_payload, child_ctx, event)
    dispatch_async(type, cast_payload, child_ctx, event)

    event
  end

  @spec dispatch_sync(module(), module(), atom(), map(), map(), Event.t()) :: :ok
  defp dispatch_sync(repo, contract, type, payload, ctx, event) do
    for handler <- Registry.sync_handlers_for(type) do
      started = System.monotonic_time(:microsecond)

      result =
        try do
          handler.module.handle(payload, ctx)
        rescue
          error ->
            # The handling row disappears along with the transaction — and that
            # is correct: nothing happened, so the log must not claim it did.
            reraise error, __STACKTRACE__
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
        "actor" => ctx[:actor] && to_string(ctx[:actor])
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

  defp repo, do: @repo
end
