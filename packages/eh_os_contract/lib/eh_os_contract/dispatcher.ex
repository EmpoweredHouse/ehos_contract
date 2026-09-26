defmodule EhOsContract.Dispatcher do
  @moduledoc """
  A command to a v2 contract, from the actor who issues it to the events in the log
  (v2 §11). `EhOsContract.dispatch/3` is how a host calls it.

      EhOsContract.dispatch(Rehmed.Contracts.VisitSettlement,
        %RecordPayment{visit_id: "w-1", method: :card, amount: 20_000},
        actor: actor, idempotency_key: "req-81")

  **In order**, and each step refuses before the next one runs:

  1. **Who.** A credential's actor is asked of the `EhOsContract.Authorizer`. A
     `:system` actor has to be one the domain declares `:system` and the command
     names in `by:`; a reaction's, one whose `issues:` names the command. A refusal
     is `{:error, reason}` and writes nothing, neither to the log nor to
     `_commands`.
  2. **What.** The command's fields against their types (`EhOsContract.Codec`):
     `{:error, {:invalid, [{field, :required | :type}]}}`.
  3. **Once.** An idempotency key already accepted for the same command returns
     that command's receipt, `duplicate: true`, and appends nothing; accepted for
     another command, `{:error, :idempotency_key_reused}`. Only an accepted
     command binds its key, so a rejected one can be sent again once the state has
     changed. The key is checked again under the append lock.
  4. **Decide.** The unit's stream is read and folded through `evolve/2`, and the
     implementation decides with the command, its `__meta__` set.
  5. **Hold the decision to its declaration.** An event the command does not emit,
     a rejection on an invariant it does not reject on, or an event whose fields
     do not fit raises: that is a defect in the code, never a business outcome, and
     nothing is appended.
  6. **Append**, under the stream's version as it was read, and write the
     `accepted` row. A rejection writes a `rejected` row and appends nothing.
  7. **Inside the transaction** (v2 §12): every read model delivered
     `:in_transaction` projects the appended events, in order, and then every such
     policy reacts. What a policy issues is dispatched at once, in the same
     transaction, as the policy's own actor, with the event as its cause and a key
     derived from it, `"policy:<name>:<event id>:<index>"`. A rejection of it is the
     unit's answer and leaves the first command standing; anything else it raises
     rolls everything back. A policy reacting to the kind of event it already reacted
     to down one chain is a cycle, and raises.

  **Conflicts.** When the stream moved between reading and appending, dispatch rolls
  back, reads again, decides again, up to three times, with jitter — but only when
  it owns the transaction. Inside a caller's transaction it returns
  `{:error, :conflict}`, since the caller's other writes cannot be replayed.

  **Failures.** An exception anywhere in the transaction rolls all of it back and is
  re-raised. When dispatch owns the transaction it first writes a `failed` row
  naming where it failed and the exception's module; inside a caller's transaction
  the row would roll back with everything else, so there is none.
  """

  import Ecto.Query

  alias EhOsContract.{
    Actor,
    Authorizer,
    Clock,
    Codec,
    CommandRecord,
    Event,
    Implementations,
    Key,
    Meta,
    Model,
    Receipt,
    Rejection,
    Store
  }

  @attempts 3

  @typedoc "What dispatch refuses a command with, before or instead of deciding."
  @type refusal ::
          Authorizer.reason()
          | :not_declared
          | {:invalid, [Codec.problem()]}
          | :idempotency_key_reused
          | :conflict

  @doc """
  Dispatches `command`, a struct a v2 contract generated, to `contract`.

  `opts`: `actor:` (an `EhOsContract.Actor`, required), `idempotency_key:` (opaque,
  never personal data), `correlation_id:` (a UUID; a new one when missing) and
  `causation_id:`.
  """
  @spec dispatch(module(), struct(), keyword() | map()) ::
          {:ok, Receipt.t()} | {:error, Rejection.t() | refusal()}
  def dispatch(contract, %module{} = command, opts) do
    model = model!(contract)
    declaration = command!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)

    with :ok <- permit(model, declaration, ctx.actor),
         :ok <- valid(declaration.fields, command, values) do
      job = %{model: model, declaration: declaration, command: command, ctx: ctx, values: values}
      run(job, repo())
    end
  end

  # --- who ---------------------------------------------------------------------------

  defp permit(model, declaration, %Actor{kind: :credential} = actor) do
    Authorizer.run(actor, %Authorizer.Request{
      kind: :command,
      capability: capability(model, :command, declaration.name),
      contract: model.module,
      version: model.version
    })
  end

  defp permit(model, declaration, %Actor{kind: :system, name: name}) do
    if name in declaration.by and system_actor?(model, name),
      do: :ok,
      else: {:error, :not_declared}
  end

  defp permit(model, declaration, %Actor{kind: :reaction, name: {:policy, name}}) do
    policy = Enum.find(model.policies, &(&1.name == name))
    if policy && declaration.name in policy.issues, do: :ok, else: {:error, :not_declared}
  end

  defp permit(_model, _declaration, actor) do
    raise ArgumentError,
          "dispatch takes `actor:`, an EhOsContract.Actor — a credential's or a :system actor " <>
            "of the domain — and got #{inspect(actor)}"
  end

  defp system_actor?(model, name) do
    Code.ensure_loaded?(model.domain) and
      function_exported?(model.domain, :__eh_os_contract_model__, 0) and
      Enum.any?(
        model.domain.__eh_os_contract_model__().actors,
        &(&1.name == name and &1.kind == :system)
      )
  end

  defp capability(model, kind, name) do
    Enum.find_value(Model.capabilities(model), fn
      {capability, %{kind: ^kind, name: ^name}} -> capability
      _ -> nil
    end)
  end

  # --- what --------------------------------------------------------------------------

  defp valid(fields, struct, values) do
    case Codec.problems(fields, struct, values) do
      [] -> :ok
      problems -> {:error, {:invalid, problems}}
    end
  end

  # --- the transaction -----------------------------------------------------------------

  defp run(job, repo) do
    if repo.in_transaction?() do
      case attempt(job, repo) do
        :conflict -> {:error, :conflict}
        result -> result
      end
    else
      owned(job, repo, 1)
    end
  end

  defp owned(job, repo, attempt) do
    Process.delete({__MODULE__, :failed_in})

    result =
      try do
        repo.transaction(fn ->
          case attempt(job, repo) do
            :conflict -> repo.rollback(:conflict)
            result -> result
          end
        end)
      rescue
        exception ->
          failed!(job, repo, exception)
          reraise exception, __STACKTRACE__
      end

    case result do
      {:ok, result} ->
        result

      {:error, :conflict} when attempt < @attempts ->
        Process.sleep(:rand.uniform(10))
        owned(job, repo, attempt + 1)

      {:error, :conflict} ->
        {:error, :conflict}
    end
  end

  # One try: `{:ok, receipt}`, `{:error, _}`, or `:conflict` when the stream moved.
  defp attempt(job, repo) do
    %{model: model, declaration: declaration, command: command, ctx: ctx} = job

    with :new <- idempotent(repo, job) do
      unit = Enum.find(model.units, &(&1.name == declaration.unit))
      impl = Implementations.fetch!(model, unit.kind, unit.name)
      stream = Key.stream(unit.name, Enum.map(unit.identity, &Map.fetch!(command, &1)))
      recorded = Store.read_stream(repo, stream, 0)
      state = fold(job, unit, impl, recorded)
      version = if recorded == [], do: 0, else: List.last(recorded).stream_version

      command = %{command | __meta__: meta(ctx)}
      decision = stage("decider", fn -> apply(impl, declaration.name, [command, state]) end)
      job = Map.merge(job, %{stream: stream, version: version, given: recorded})

      case decision do
        {:ok, events} when is_list(events) ->
          commit(job, stage("decider", fn -> emitted!(job, events) end), repo)

        {:error, %Rejection{invariant: invariant} = rejection} ->
          unless invariant in declaration.rejects do
            raise ArgumentError,
                  "command #{inspect(declaration.name)} of #{inspect(model.module)} was rejected " <>
                    "on #{inspect(invariant)}, which is not among its rejects: " <>
                    "#{inspect(declaration.rejects)}"
          end

          record!(repo, job, "rejected", %{invariant: Atom.to_string(invariant)})
          {:error, rejection}

        other ->
          raise ArgumentError,
                "the decision of command #{inspect(declaration.name)} returned #{inspect(other)}; " <>
                  "a decision returns {:ok, events} or {:error, %EhOsContract.Rejection{}}"
      end
    end
  end

  defp commit(job, events, repo) do
    :ok = Store.lock(repo)

    # Checked again under the lock: another transaction with the same key may have
    # committed while this one decided.
    with :new <- idempotent(repo, job) do
      command_id = Ecto.UUID.generate()
      entries = Enum.map(events, &entry(job, &1, command_id))

      case Store.append(repo, entries, {:stream, job.stream, job.version}) do
        {:error, :wrong_expected_version} ->
          :conflict

        {:ok, appended} ->
          record!(repo, Map.put(job, :command_id, command_id), "accepted", %{
            emitted_types: Enum.map(appended, & &1.type),
            first_position: appended |> List.first() |> position(),
            last_position: appended |> List.last() |> position()
          })

          receipt = receipt(command_id, Enum.zip(Enum.map(events, &elem(&1, 1)), appended), false)
          inline!(job, Enum.zip(receipt.events, appended), repo)
          {:ok, receipt}
      end
    end
  end

  defp position(nil), do: nil
  defp position(%Event{position: position}), do: position

  # --- inside the transaction ------------------------------------------------------------

  # Every read model delivered in the transaction projects the appended events, in
  # order; then every such policy reacts, and what it issues is dispatched here, in
  # the same transaction, as the policy's own actor.
  defp inline!(job, pairs, repo) do
    consumers =
      for {event, row} <- pairs,
          consumer <- Implementations.inline(job.model.module, row.type),
          do: {consumer, event}

    {projections, policies} = Enum.split_with(consumers, &(elem(&1, 0).kind == :read_model))

    for {consumer, event} <- projections do
      module = implemented!(consumer)

      stage("read_model:#{consumer.name}", fn ->
        case apply(module, consumer.callback, [event]) do
          :ok ->
            :ok

          other ->
            raise ArgumentError,
                  "read model #{inspect(consumer.name)} returned #{inspect(other)} for " <>
                    "#{inspect(consumer.callback)}; a projection returns :ok"
        end
      end)
    end

    Enum.each(policies, fn {consumer, event} -> react!(job, consumer, event, repo) end)
  end

  defp react!(job, consumer, event, _repo) do
    module = implemented!(consumer)
    model = Model.fetch(consumer.contract)
    policy = Enum.find(model.policies, &(&1.name == consumer.name))
    link = {consumer.contract, consumer.name, event.__struct__}
    chain = job.ctx.chain

    # The cycle guard v1's emitter had: a policy that reacts, down one chain, to the
    # kind of event it has already reacted to would dispatch for ever.
    if link in chain or length(chain) >= 32 do
      raise ArgumentError,
            "policy #{inspect(consumer.name)} of #{inspect(consumer.contract)} reacts to " <>
              "#{inspect(event.__struct__)} again down one chain of dispatches, which would " <>
              "never end: #{inspect(Enum.reverse([link | chain]))}"
    end

    issued =
      stage("policy:#{consumer.name}", fn ->
        case apply(module, consumer.callback, [event]) do
          {:ok, commands} when is_list(commands) ->
            commands

          other ->
            raise ArgumentError,
                  "policy #{inspect(consumer.name)} returned #{inspect(other)}; it returns {:ok, commands}"
        end
      end)

    allowed = MapSet.new(policy.issues, &Model.module_for(model, :command, &1))

    for {command, index} <- Enum.with_index(issued) do
      unless is_struct(command) and MapSet.member?(allowed, command.__struct__) do
        raise ArgumentError,
              "policy #{inspect(consumer.name)} issued #{describe(command)}, which is not among " <>
                "the commands it issues: #{inspect(policy.issues)}"
      end

      opts = [
        actor: Actor.reaction(:policy, consumer.name),
        causation_id: event.__meta__.id,
        correlation_id: event.__meta__.correlation_id,
        idempotency_key: "policy:#{consumer.name}:#{event.__meta__.id}:#{index}",
        chain: [link | chain]
      ]

      case dispatch(consumer.contract, command, opts) do
        {:ok, _receipt} ->
          :ok

        # A rejection is the unit's answer, and its row is written: the policy asked
        # and was told no. The command that set it off still stands.
        {:error, %Rejection{}} ->
          :ok

        # Not a conflict: the append lock is held from this transaction's first
        # append, so no stream can move under a nested dispatch.
        {:error, reason} ->
          raise ArgumentError,
                "policy #{inspect(consumer.name)} issued #{describe(command)}, and dispatch " <>
                  "refused it: #{inspect(reason)}"
      end
    end
  end

  defp implemented!(%{module: nil} = consumer) do
    raise ArgumentError,
          "#{consumer.kind} #{inspect(consumer.name)} of #{inspect(consumer.contract)} runs in " <>
            "the dispatch transaction and no module implements it; bind one with " <>
            "`use #{inspect(consumer.contract)}, #{consumer.kind}: #{inspect(consumer.name)}`"
  end

  defp implemented!(%{module: module}), do: module

  # --- once ------------------------------------------------------------------------------

  defp idempotent(_repo, %{ctx: %{idempotency_key: nil}}), do: :new

  defp idempotent(repo, %{ctx: %{idempotency_key: key}} = job) do
    accepted =
      repo.one(
        from(c in CommandRecord, where: c.idempotency_key == ^key and c.outcome == "accepted")
      )

    cond do
      accepted == nil ->
        :new

      accepted.contract == inspect(job.model.module) and
          accepted.type == Atom.to_string(job.declaration.name) ->
        events =
          repo.all(from(e in Event, where: e.command_id == ^accepted.id, order_by: e.position))

        {:ok, receipt(accepted.id, Enum.map(events, &{decode!(job, &1), &1}), true)}

      true ->
        {:error, :idempotency_key_reused}
    end
  end

  # --- reading a stream --------------------------------------------------------------------

  defp fold(job, unit, impl, recorded) do
    state =
      struct(
        Module.concat(Model.module_for(job.model, unit.kind, unit.name), State),
        Map.new(unit.identity, &{&1, Map.fetch!(job.command, &1)})
      )

    if function_exported?(impl, :evolve, 2) do
      Enum.reduce(recorded, state, fn event, state ->
        stage("evolve", fn -> impl.evolve(state, decode!(job, event)) end)
      end)
    else
      state
    end
  end

  defp decode!(job, %Event{} = event) do
    declaration =
      Enum.find(job.model.events, &(&1.type == event.type)) ||
        raise ArgumentError,
              "#{inspect(job.model.module)} declares no event of type #{inspect(event.type)}, " <>
                "which its log holds at position #{event.position}"

    case Codec.decode(declaration.fields, event.payload, job.values) do
      {:ok, fields} ->
        struct!(
          Model.module_for(job.model, :event, declaration.name),
          Map.put(fields, :__meta__, %Meta{
            actor: event.actor,
            occurred_at: event.occurred_at,
            correlation_id: event.correlation_id,
            causation_id: event.causation_id,
            id: event.id,
            position: event.position
          })
        )

      {:error, problems} ->
        raise ArgumentError,
              "the event at position #{event.position} no longer fits #{inspect(event.type)} as " <>
                "declared: #{inspect(problems)}"
    end
  end

  # --- holding the decision to its declaration ----------------------------------------------

  defp emitted!(job, events) do
    %{model: model, declaration: declaration, values: values} = job
    allowed = Map.new(declaration.emits, &{Model.module_for(model, :event, &1), &1})

    for event <- events do
      name =
        (is_struct(event) && Map.get(allowed, event.__struct__)) ||
          raise ArgumentError,
                "command #{inspect(declaration.name)} of #{inspect(model.module)} decided " <>
                  "#{describe(event)}, which is not among the events it emits: " <>
                  "#{inspect(declaration.emits)}. Nothing was appended."

      event_declaration = Enum.find(model.events, &(&1.name == name))

      case Codec.problems(event_declaration.fields, event, values) do
        [] ->
          {event_declaration, event}

        problems ->
          raise ArgumentError,
                "command #{inspect(declaration.name)} decided event #{inspect(name)} with fields " <>
                  "that do not fit: #{inspect(problems)}. Nothing was appended."
      end
    end
  end

  defp describe(%module{}), do: "%#{inspect(module)}{}"
  defp describe(other), do: inspect(other)

  # --- writing ----------------------------------------------------------------------------

  defp entry(job, {declaration, event}, command_id) do
    %{model: model, ctx: ctx, values: values} = job
    unit = Enum.find(model.units, &(&1.name == declaration.unit))

    %{
      id: Ecto.UUID.generate(),
      type: declaration.type,
      contract: inspect(model.module),
      contract_version: model.version,
      tags: Enum.map(unit.identity, &Key.tag(&1, Map.fetch!(event, &1))),
      process: model.process && Atom.to_string(model.process.name),
      instance_id: instance(model, event),
      command_id: command_id,
      correlation_id: ctx.correlation_id,
      causation_id: command_id,
      actor: Actor.label(ctx.actor),
      occurred_at: ctx.now,
      payload: Codec.encode(declaration.fields, event, values),
      metadata:
        %{
          "command" => Atom.to_string(job.declaration.name),
          "issued_by" => Actor.label(ctx.actor)
        }
        |> put_present("idempotency_key", ctx.idempotency_key)
    }
  end

  # The run a struct belongs to: the process's name, then its correlation values.
  defp instance(%{process: nil}, _struct), do: nil

  defp instance(%{process: process}, struct) do
    values = Enum.map(process.correlate, &Map.get(struct, &1))
    if Enum.all?(values, &(&1 != nil)), do: Key.join([process.name | values])
  end

  defp record!(repo, job, outcome, fields) do
    %{model: model, declaration: declaration, ctx: ctx} = job

    row =
      struct!(
        CommandRecord,
        Map.merge(
          %{
            id: Map.get(job, :command_id) || Ecto.UUID.generate(),
            contract: inspect(model.module),
            type: Atom.to_string(declaration.name),
            issued_by: Actor.label(ctx.actor),
            idempotency_key: if(outcome == "accepted", do: ctx.idempotency_key),
            causation_event_id: ctx.causation_id,
            correlation_id: ctx.correlation_id,
            outcome: outcome,
            given_types: Enum.map(Map.get(job, :given, []), & &1.type),
            process: model.process && Atom.to_string(model.process.name),
            instance_id: instance(model, job.command)
          },
          fields
        )
      )

    repo.insert!(row)
  end

  defp failed!(job, repo, exception) do
    failed_in = Process.delete({__MODULE__, :failed_in}) || "dispatch"

    record!(repo, job, "failed", %{failed_in: failed_in, error: inspect(exception.__struct__)})
  end

  # Where an exception came from, for the `failed` row.
  defp stage(name, fun) do
    fun.()
  rescue
    exception ->
      Process.put({__MODULE__, :failed_in}, name)
      reraise exception, __STACKTRACE__
  end

  defp receipt(command_id, pairs, duplicate) do
    events =
      for {event, %Event{} = row} <- pairs do
        meta = %Meta{
          actor: row.actor,
          occurred_at: row.occurred_at,
          correlation_id: row.correlation_id,
          causation_id: row.causation_id,
          id: row.id,
          position: row.position
        }

        %{event | __meta__: meta}
      end

    positions = Enum.map(events, & &1.__meta__.position)

    %Receipt{
      command_id: command_id,
      events: events,
      positions: positions,
      position: List.last(positions),
      duplicate: duplicate
    }
  end

  # --- context ------------------------------------------------------------------------------

  defp context(opts) do
    opts = Map.new(opts)

    %{
      actor: Map.get(opts, :actor),
      idempotency_key: Map.get(opts, :idempotency_key),
      correlation_id: Map.get(opts, :correlation_id) || Ecto.UUID.generate(),
      causation_id: Map.get(opts, :causation_id),
      now: Clock.now(),
      chain: Map.get(opts, :chain, [])
    }
  end

  defp meta(ctx) do
    %Meta{
      actor: Actor.label(ctx.actor),
      occurred_at: ctx.now,
      correlation_id: ctx.correlation_id,
      causation_id: ctx.causation_id
    }
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # --- lookups --------------------------------------------------------------------------------

  defp model!(contract) do
    case Model.fetch(contract) do
      %{kind: :contract, units: _} = model ->
        model

      %{module: module} ->
        raise ArgumentError, "#{inspect(module)} is not a v2 contract; v1 contracts emit"
    end
  end

  defp command!(model, module) do
    Enum.find(model.commands, &(Model.module_for(model, :command, &1.name) == module)) ||
      raise ArgumentError,
            "#{inspect(module)} is not a command of #{inspect(model.module)}"
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
