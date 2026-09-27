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
     `:in_transaction` projects the appended events, in order, then every such
     policy reacts, then every such effect acts (`EhOsContract.Consumer`). What a
     policy issues is dispatched at once, in the same transaction, as the policy's
     own actor, with the event as its cause and a key derived from it,
     `"policy:<contract>:<name>:<event id>:<index>"` — the contract too, since the
     index of accepted keys spans the application. A rejection of it is the unit's
     answer and leaves the first command standing; anything else it raises, and an
     effect's `{:error, reason}`, rolls everything back. A policy reacting to the
     kind of event it already reacted to down one chain is a cycle, and raises. A
     read model whose subscription is being rebuilt is left to the runner catching
     it up.
  8. **After it, by the same commit**: one `EhOsContract.EffectJob` per effect
     delivered `:at_least_once`, holding the effect's key and the event's id.

  **Conflicts.** When the stream moved between reading and appending, dispatch rolls
  back, reads again, decides again, up to three times, with jitter — but only when
  it owns the transaction. Inside a caller's transaction it returns
  `{:error, :conflict}`, since the caller's other writes cannot be replayed.

  **Failures.** An exception anywhere in the transaction rolls all of it back and is
  re-raised. When dispatch owns the transaction it first writes a `failed` row
  naming where it failed and the exception's module; inside a caller's transaction
  the row would roll back with everything else, so there is none. A row that cannot
  be written — the database is what failed — is logged, and the caller still gets
  the exception it would have recorded.
  """

  import Ecto.Query

  require Logger

  alias EhOsContract.{
    Actor,
    Authorizer,
    Clock,
    Codec,
    CommandRecord,
    Consumer,
    EffectJob,
    Event,
    Implementations,
    Key,
    Meta,
    Model,
    Personal,
    Receipt,
    Rejection,
    Store,
    SubscriptionRecord
  }

  @attempts 3

  @typedoc "What dispatch refuses a command with, before or instead of deciding."
  @type refusal ::
          Authorizer.reason()
          | :not_declared
          | {:invalid, [Codec.problem()]}
          | :idempotency_key_reused
          | :conflict
          | :not_caught_up

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
      job = %{
        kind: :command,
        type: Atom.to_string(declaration.name),
        model: model,
        declaration: declaration,
        command: command,
        ctx: ctx,
        values: values
      }

      run(job, repo())
    end
  end

  @doc """
  Records `event`, which the contract declares `recorded_by:` — an observation, or
  an integration's answer — without a decision (v2 §11, D6).

  Only a `:system` actor the event's `recorded_by:` names may record it. A
  credential is refused with `:not_grantable`: EHOS grants commands and queries,
  so no credential could carry a capability to record (v2 §11, the note of 26
  September 2026). Otherwise it goes as a command does — the fields checked, the
  idempotency key honoured, the unit's stream version as the append's condition,
  the consumers in the transaction run, the `accepted` row written with the type
  `"record:<event>"` — only without a decider.
  """
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, Receipt.t()} | {:error, refusal() | :not_grantable}
  def record(contract, %module{} = event, opts) do
    model = model!(contract)
    declaration = recorded!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)

    with :ok <- permit_record(model, declaration, ctx.actor),
         :ok <- valid(declaration.fields, event, values) do
      job = %{
        kind: :record,
        type: "record:#{declaration.name}",
        model: model,
        declaration: declaration,
        command: event,
        ctx: ctx,
        values: values
      }

      run(job, repo())
    end
  end

  @doc """
  Asks a query of a v2 contract, and returns what its implementation answers (v2
  §11, D10). Nothing is written: a read is not a fact.

  A credential's actor is asked of the `EhOsContract.Authorizer` for the query's
  capability, and for a scoped query with the value of the scope parameter, so a
  value outside the grant is refused before the implementation runs. A `:system`
  actor the query's `by:` names is the application's own code, and is not narrowed.

  **Every row is checked again**: for a credential's actor, a row whose scope field
  is not among the values the credential grants raises
  `EhOsContract.Authorizer.OutsideScopeError`, so a wrong `where` cannot hand one
  clinic another's rows. So do rows that are not the read model's.

  **Read your writes** (v2 §11): `min_position:` — the `position` of a dispatch's
  receipt — waits until the read model the query reads has taken that position,
  polling its subscription row for up to `wait:` milliseconds (5000), and then
  refuses with `{:error, :not_caught_up}` rather than answer from before the write.
  A read model delivered in the transaction has taken every committed event, unless
  it is being rebuilt.
  """
  @spec query(module(), struct(), keyword() | map()) ::
          {:ok, [struct()] | struct() | nil} | {:error, refusal()}
  def query(contract, %module{} = params, opts) do
    model = model!(contract)
    declaration = query!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)
    scope = scope(declaration, params, values)

    with :ok <- permit_query(model, declaration, ctx.actor, scope),
         :ok <- valid(declaration.params, params, values),
         :ok <- caught_up(model, declaration, Map.new(opts)) do
      impl = Implementations.fetch!(model, :query, declaration.name)
      answer = apply(impl, declaration.name, [params, %{actor: ctx.actor}])
      {:ok, answered!(model, declaration, answer, ctx.actor, values)}
    end
  end

  # --- read your writes ---------------------------------------------------------------

  @poll 25

  defp caught_up(model, declaration, %{min_position: position} = opts)
       when is_integer(position) do
    key = "#{inspect(model.module)}:read_model:#{declaration.reads}"
    read_model = Enum.find(model.read_models, &(&1.name == declaration.reads))
    until = System.monotonic_time(:millisecond) + Map.get(opts, :wait, 5000)
    wait_for(repo(), key, read_model.delivery, position, until)
  end

  defp caught_up(_model, _declaration, _opts), do: :ok

  defp wait_for(repo, key, delivery, position, until) do
    case {repo.get(SubscriptionRecord, key), delivery} do
      # Projected by dispatch in its own transaction, with no row to say so: what
      # committed is there.
      {nil, :in_transaction} ->
        :ok

      {%{position: at, status: status}, _delivery}
      when at >= position and status != "rebuilding" ->
        :ok

      _behind ->
        if System.monotonic_time(:millisecond) >= until do
          {:error, :not_caught_up}
        else
          Process.sleep(@poll)
          wait_for(repo, key, delivery, position, until)
        end
    end
  end

  # --- who ---------------------------------------------------------------------------

  # `EhOsContract.Plug`'s question when a request fails before dispatch or query would
  # run — a body that is not an object, fields that do not decode, a correlation id
  # that is not a UUID: the request either of them would make, with a scope value as
  # it was sent. Asked first, a caller without the capability learns nothing about
  # the declaration's fields, and every request is still one decision (v2 §11).
  @doc false
  @spec permit_undecoded(Model.t(), :command | :query, map(), Actor.t(), map()) ::
          :ok | {:error, Authorizer.reason()}
  def permit_undecoded(model, :command, declaration, actor, _input),
    do: permit(model, declaration, actor)

  def permit_undecoded(model, :query, %{scope: nil} = declaration, actor, _input),
    do: permit_query(model, declaration, actor, nil)

  def permit_undecoded(model, :query, declaration, actor, input) do
    value =
      case Map.get(input, Atom.to_string(declaration.scope)) do
        value when is_binary(value) -> value
        _missing_or_not_a_string -> nil
      end

    permit_query(model, declaration, actor, scope_request(declaration.scope, value))
  end

  defp permit(model, declaration, %Actor{kind: :credential} = actor) do
    Authorizer.run(actor, %Authorizer.Request{
      kind: :command,
      capability: capability(model, :command, declaration.name),
      contract: model.module,
      version: model.version
    })
  end

  defp permit(model, declaration, %Actor{kind: :system, name: name}),
    do: named(model, declaration.by, name)

  defp permit(model, declaration, %Actor{kind: :reaction, name: {:policy, name}}) do
    policy = Enum.find(model.policies, &(&1.name == name))
    if policy && declaration.name in policy.issues, do: :ok, else: {:error, :not_declared}
  end

  # A process manager issues what its reactions and its timers name.
  defp permit(model, declaration, %Actor{kind: :reaction, name: {:pm, name}}) do
    case Enum.find(model.process_managers, &(&1.name == name)) do
      nil ->
        {:error, :not_declared}

      pm ->
        issues = Enum.flat_map(pm.starts_on ++ pm.on ++ pm.timers, & &1.issues)
        if declaration.name in issues, do: :ok, else: {:error, :not_declared}
    end
  end

  defp permit(_model, _declaration, actor) do
    raise ArgumentError,
          "dispatch takes `actor:`, an EhOsContract.Actor — a credential's or a :system actor " <>
            "of the domain — and got #{inspect(actor)}"
  end

  defp permit_record(_model, _declaration, %Actor{kind: :credential}),
    do: {:error, :not_grantable}

  defp permit_record(model, declaration, %Actor{kind: :system, name: name}),
    do: named(model, declaration.recorded_by, name)

  defp permit_record(_model, _declaration, %Actor{kind: :reaction}), do: {:error, :not_declared}
  defp permit_record(model, declaration, actor), do: permit(model, declaration, actor)

  defp permit_query(model, declaration, %Actor{kind: :credential} = actor, scope) do
    Authorizer.run(actor, %Authorizer.Request{
      kind: :query,
      capability: capability(model, :query, declaration.name),
      contract: model.module,
      version: model.version,
      scope: scope && {scope.dimension, scope.value}
    })
  end

  defp permit_query(model, declaration, %Actor{kind: :system, name: name}, _scope),
    do: named(model, declaration.by, name)

  defp permit_query(_model, _declaration, %Actor{kind: :reaction}, _scope),
    do: {:error, :not_declared}

  defp permit_query(model, declaration, actor, _scope), do: permit(model, declaration, actor)

  # A scoped query's dimension, and the value asked for, in the form a credential's
  # `scp` carries: a string, or nil when the parameter is missing.
  defp scope(%{scope: nil}, _params, _values), do: nil

  defp scope(declaration, params, values) do
    param = Enum.find(declaration.params, &(&1.name == declaration.scope))
    value = scoped(param.type, Map.get(params, declaration.scope), values)
    declaration.scope |> scope_request(value) |> Map.put(:type, param.type)
  end

  # What a scoped request carries, decoded or as it was sent: the one place that
  # says so, for `query/3` and for `permit_undecoded/5`.
  defp scope_request(dimension, value), do: %{dimension: Atom.to_string(dimension), value: value}

  defp scoped(type, value, values) do
    case Codec.encode_value(type, value, values) do
      nil -> nil
      encoded -> to_string(encoded)
    end
  end

  # The implementation's answer, held to the declaration: rows of the read model, as
  # many as `returns:` says, and for a credential only rows within its grant.
  defp answered!(model, declaration, answer, actor, values) do
    row = Module.concat(Model.module_for(model, :read_model, declaration.reads), Row)
    # One row is a row or nil, never a list of one: the caller was promised a row.
    rows =
      case {declaration.returns, answer} do
        {:one, nil} -> []
        {:one, %{__struct__: _} = one} -> [one]
        {:one, _other} -> :unfit
        {:many, many} -> many
      end

    unless is_list(rows) and Enum.all?(rows, &is_struct(&1, row)) do
      raise ArgumentError,
            "query #{inspect(declaration.name)} of #{inspect(model.module)} answered " <>
              "#{describe(answer)}; it answers #{if declaration.returns == :one, do: "one %#{inspect(row)}{} or nil", else: "a list of %#{inspect(row)}{}"}"
    end

    with %Actor{kind: :credential} <- actor,
         %{dimension: dimension, type: type} <- scope(declaration, %{}, values) do
      granted = Authorizer.granted(actor, capability(model, :query, declaration.name), dimension)

      for row <- rows, scoped(type, Map.get(row, declaration.scope), values) not in granted do
        raise Authorizer.OutsideScopeError,
          message:
            "query #{inspect(declaration.name)} of #{inspect(model.module)} answered a row whose " <>
              "#{dimension} is outside what the credential of #{inspect(actor.subject)} grants; " <>
              "no row was returned"
      end
    end

    answer
  end

  # The application's own code acting as a :system actor of the domain: allowed where
  # the declaration names it, and only if the domain declares it :system, so a
  # person's actor cannot be passed off as code.
  defp named(model, names, name) do
    if name in names and system_actor?(model, name), do: :ok, else: {:error, :not_declared}
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
          stacktrace = __STACKTRACE__
          failed!(job, repo, exception)
          reraise exception, stacktrace
      end

    case result do
      {:ok, result} ->
        notify(job, result)
        result

      {:error, :conflict} when attempt < @attempts ->
        Process.sleep(:rand.uniform(10))
        owned(job, repo, attempt + 1)

      {:error, :conflict} ->
        {:error, :conflict}
    end
  end

  # Committed: the runners can read what was appended (v2 §11). Only when something
  # was, and something reads it after the transaction — with Oban's Postgres
  # notifier every notification is a query.
  defp notify(job, {:ok, %Receipt{duplicate: false, events: [_ | _]}}) do
    if Implementations.ordered?(job.model.module), do: EhOsContract.Subscription.Runner.notify()
  end

  defp notify(_job, _nothing_appended), do: :ok

  # One try: `{:ok, receipt}`, `{:error, _}`, or `:conflict` when the stream moved.
  defp attempt(%{kind: :record} = job, repo) do
    with :new <- idempotent(repo, job) do
      unit = Enum.find(job.model.units, &(&1.name == job.declaration.unit))
      stream = Key.stream(unit.name, Enum.map(unit.identity, &Map.fetch!(job.command, &1)))
      recorded = Store.read_stream(repo, stream, 0)
      version = if recorded == [], do: 0, else: List.last(recorded).stream_version
      job = Map.merge(job, %{stream: stream, version: version, given: recorded})
      commit(job, [{job.declaration, job.command}], repo)
    end
  end

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

          write_row!(repo, job, "rejected", %{invariant: Atom.to_string(invariant)})
          {:error, rejection}

        other ->
          raise ArgumentError,
                "the decision of command #{inspect(declaration.name)} returned #{inspect(other)}; " <>
                  "a decision returns {:ok, events} or {:error, %EhOsContract.Rejection{}}"
      end
    end
  end

  defp commit(job, events, repo) do
    # The subjects' keys are read and wrapped before the lock, where a vault's round
    # trip holds up no other writer, and stored under it (v2 §14).
    prepared = Personal.prepare(repo, subjects(job, events))
    :ok = Store.lock(repo)

    # Checked again under the lock: another transaction with the same key may have
    # committed while this one decided.
    with :new <- idempotent(repo, job) do
      command_id = Ecto.UUID.generate()
      keys = Personal.for_writing(repo, prepared)
      entries = Enum.map(events, &entry(job, &1, command_id, keys))

      case Store.append(repo, entries, {:stream, job.stream, job.version}) do
        {:error, :wrong_expected_version} ->
          :conflict

        {:ok, appended} ->
          write_row!(repo, Map.put(job, :command_id, command_id), "accepted", %{
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
  # the same transaction, as the policy's own actor; then every such effect acts. Last,
  # one job per effect delivered at least once.
  defp inline!(job, pairs, repo) do
    # Every read model takes every appended event before any policy reacts to one:
    # a policy's nested dispatch appends after them, and a read model has to see the
    # events in the log's order. Stable, so each kind keeps that order.
    consumers =
      for(
        {event, row} <- pairs,
        consumer <- Implementations.inline(job.model.module, row.type),
        do: {consumer, event, row}
      )
      |> Enum.sort_by(fn {consumer, _, _} -> Implementations.order(consumer.kind) end)

    projecting = projecting(repo, consumers)

    projected =
      for {consumer, event, row} <- consumers,
          consumer.kind != :read_model or Map.get(projecting, consumer.key) != :rebuilding do
        stage(Consumer.label(consumer), fn ->
          with {:error, reason} <- Consumer.handle!(consumer, event, job.ctx.chain) do
            raise ArgumentError,
                  "effect #{inspect(consumer.name)} runs in the dispatch transaction and " <>
                    "answered {:error, #{inspect(reason)}}, so nothing was appended"
          end
        end)

        {consumer.key, row.position}
      end

    # Each registered read model's row once, to the last event it projected.
    for {key, positions} <- Enum.group_by(projected, &elem(&1, 0), &elem(&1, 1)),
        Map.get(projecting, key) == :running,
        do: advance!(repo, key, Enum.max(positions))

    enqueue!(job, pairs, repo)
  end

  # What each inline read model's subscription row says: `:running` advances with the
  # dispatch, `:rebuilding` is left to the runner that is catching it up (v2 §12),
  # and a read model without a row, one no boot registered, projects as before.
  defp projecting(repo, consumers) do
    keys = for {%{kind: :read_model, key: key}, _, _} <- consumers, uniq: true, do: key

    if keys == [] do
      %{}
    else
      repo.all(
        from(s in SubscriptionRecord,
          where: s.name in ^keys,
          select: {s.name, s.status}
        )
      )
      |> Map.new(fn {name, status} ->
        {name, if(status == "rebuilding", do: :rebuilding, else: :running)}
      end)
    end
  end

  defp advance!(repo, key, position) do
    repo.update_all(
      from(s in SubscriptionRecord, where: s.name == ^key and s.position < ^position),
      set: [position: position, updated_at: DateTime.utc_now()]
    )
  end

  # One job per effect delivered at least once, inserted in this transaction, so the
  # job exists exactly when the event does.
  defp enqueue!(job, pairs, repo) do
    jobs =
      for {_event, row} <- pairs,
          effect <- Implementations.effects(job.model.module, row.type),
          do: EffectJob.job(effect.key, row.id)

    if jobs != [] do
      case Oban.config() do
        %{repo: ^repo} ->
          Oban.insert_all(jobs)

        %{repo: other} ->
          raise ArgumentError,
                "Oban runs on #{inspect(other)} and dispatch appends through #{inspect(repo)}, " <>
                  "so an effect's job would not commit with its event; run Oban on the same repo"
      end
    end

    :ok
  end

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
          accepted.type == job.type ->
        events =
          repo.all(from(e in Event, where: e.command_id == ^accepted.id, order_by: e.position))

        {:ok, receipt(accepted.id, Enum.zip(decode_all!(job, events), events), true)}

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
      Enum.reduce(decode_all!(job, recorded), state, fn event, state ->
        stage("evolve", fn -> impl.evolve(state, event) end)
      end)
    else
      state
    end
  end

  defp decode_all!(job, rows), do: Consumer.decode_all!(job.model, job.values, rows)

  # --- holding the decision to its declaration ----------------------------------------------

  defp emitted!(job, events) do
    %{model: model, declaration: declaration, values: values} = job
    allowed = Map.new(declaration.emits, &{Model.module_for(model, :event, &1), &1})
    unit = Enum.find(model.units, &(&1.name == declaration.unit))

    for event <- events do
      name =
        (is_struct(event) && Map.get(allowed, event.__struct__)) ||
          raise ArgumentError,
                "command #{inspect(declaration.name)} of #{inspect(model.module)} decided " <>
                  "#{describe(event)}, which is not among the events it emits: " <>
                  "#{inspect(declaration.emits)}. Nothing was appended."

      event_declaration = Enum.find(model.events, &(&1.name == name))

      # The event is appended to the command's stream, so it has to be about the same
      # unit: one carrying another identity would sit in this stream and be folded
      # into this unit's state.
      for field <- unit.identity, Map.fetch!(event, field) != Map.fetch!(job.command, field) do
        raise ArgumentError,
              "command #{inspect(declaration.name)} decided event #{inspect(name)} for another " <>
                "unit: its #{field} is not the command's, and an event joins the stream of the " <>
                "unit that decided it. Nothing was appended."
      end

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

  # Whose personal data the events carry.
  defp subjects(job, events) do
    for {declaration, event} <- events,
        subject <- Codec.subjects(declaration.fields, event, job.values, :value),
        uniq: true,
        do: subject
  end

  defp entry(job, {declaration, event}, command_id, keys) do
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
      # The runs of the processes that include it (D7), written with it.
      runs: included_runs(model, declaration.type, event),
      command_id: command_id,
      correlation_id: ctx.correlation_id,
      causation_id: command_id,
      actor: Actor.label(ctx.actor),
      occurred_at: ctx.now,
      payload:
        Codec.encode(declaration.fields, event, values, Personal.sealer(keys, declaration.type)),
      metadata:
        %{
          "command" => job.type,
          "issued_by" => Actor.label(ctx.actor)
        }
        |> put_present("idempotency_key", ctx.idempotency_key)
        # The policies that led here, so a runner reacting to this event later
        # continues the chain instead of starting it over.
        |> put_present("chain", if(ctx.chain != [], do: ctx.chain))
    }
  end

  # The run a struct belongs to: the process's name, then its correlation values.
  defp instance(%{process: nil}, _struct), do: nil
  defp instance(%{process: process}, struct), do: run_key(process, struct)

  defp run_key(process, struct) do
    values = Enum.map(process.correlate, &Map.get(struct, &1))
    if Enum.all?(values, &(&1 != nil)), do: Key.join([process.name | values])
  end

  # An event without the fields another process correlates on is in none of its runs,
  # as one without its home process's is in no home run.
  defp included_runs(model, type, event) do
    for process <- Implementations.included(model.module, type),
        key = run_key(process, event),
        key != nil,
        do: {Atom.to_string(process.name), key}
  end

  defp write_row!(repo, job, outcome, fields) do
    %{model: model, ctx: ctx} = job

    row =
      struct!(
        CommandRecord,
        Map.merge(
          %{
            id: Map.get(job, :command_id) || Ecto.UUID.generate(),
            contract: inspect(model.module),
            type: job.type,
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

  # The row records the failure and must never replace it: when the database is what
  # failed, writing the row fails too, and the caller has to see the first exception.
  defp failed!(job, repo, exception) do
    failed_in = Process.delete({__MODULE__, :failed_in}) || "dispatch"

    write_row!(repo, job, "failed", %{failed_in: failed_in, error: inspect(exception.__struct__)})
  rescue
    secondary ->
      Logger.error(
        "the failed row of command #{job.type} of #{inspect(job.model.module)} could not be " <>
          "written (#{inspect(secondary.__struct__)}); the exception it records, " <>
          "#{inspect(exception.__struct__)}, goes on to the caller"
      )
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

  defp recorded!(model, module) do
    Enum.find(model.events, fn e ->
      e.recorded_by != [] and Model.module_for(model, :event, e.name) == module
    end) ||
      raise ArgumentError,
            "#{inspect(module)} is not an event #{inspect(model.module)} records; only an event " <>
              "declaring recorded_by: is recorded, and a command emits the others"
  end

  defp query!(model, module) do
    Enum.find(model.queries, &(Model.module_for(model, :query, &1.name) == module)) ||
      raise ArgumentError, "#{inspect(module)} is not a query of #{inspect(model.module)}"
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
