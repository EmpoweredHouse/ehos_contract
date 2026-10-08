defmodule EhOsContract.Dispatcher do
  @moduledoc """
  A command to a contract, from the actor who issues it to the events in the log.
  `EhOsContract.dispatch/3` is how a host calls it.

      EhOsContract.dispatch(Rehmed.Contracts.VisitSettlement,
        %RecordPayment{visit_id: "w-1", method: :card, amount: 20_000},
        actor: actor, idempotency_key: "req-81")

  **In order**, and each step refuses before the next one runs:

  1. **Who.** A credential's actor is asked of the `EhOsContract.Authorizer`. A
     `:system` actor has to be one the domain declares `:system` and the command
     names in `by:`; a reaction's, one whose `issues:` names the command. A refusal
     is `{:error, reason}` and writes nothing, neither to the log nor to
     `_commands`.
  2. **What.** The command's fields against their declared types, and each value
     against the invariants of its domain value:
     `{:error, {:invalid, [{field, :required | :type | {:invariant, name}}]}}`,
     before anything is decided or written. A command that `creates:`
     an aggregate whose identity is generated gets a UUIDv7 here, and is refused
     with `{field, :generated}` when it brings one of its own, and with
     `{:error, :idempotency_key_required}` without an idempotency key.
     An idempotency key, a caller's or a reaction's, is printable ASCII (`0x21`–`0x7E`)
     of at most 255 bytes, or `{:error, :idempotency_key_invalid}`: stricter than the
     key's columns need, so a key never depends on what a text column, `jsonb` and an index entry
     happen to hold. An aggregate's stream id, its name and its identity escaped
     (`EhOsContract.Key`), is at most `EhOsContract.Key.budget/0` bytes, or
     `{:error, :key_too_long}`.
  3. **Once.** A key belongs to the actor who sent it: another actor's command
     with the same key is its own, and never sees the first one's receipt. An
     idempotency key the actor already had accepted for the same command returns
     that command's receipt, `duplicate: true`, and appends nothing; accepted for
     another command, `{:error, :idempotency_key_reused}`. Only an accepted
     command binds its key, so a rejected one can be sent again once the state has
     changed. The key is checked again under the append lock.
  4. **Decide.** What the unit decides over is read and folded through `evolve/2`,
     and the implementation decides with the command, its `__meta__` set. An
     aggregate reads its stream. A dynamic consistency boundary reads a query over
     the log: its own events carrying its identity, and every event it
     `consults` — on the fields it `match`es, or every one of that type when it
     consults by `where:` alone — each decoded by the contract that declares it, in
     the log's order. Only what `evolve/2` folds is decoded, when its one catch-all
     is `def evolve(state, _), do: state`, and a boundary reads, and conflicts on,
     those types alone. A command whose `actor_is` names a field of the state is
     refused on its invariant before the decision when a credential's subject is not
     the one that field holds; a `:system` actor and a reaction pass.
  5. **Hold the decision to its declaration.** An event the command does not emit,
     a rejection on an invariant it does not reject on, or an event whose fields
     do not fit — their types, or the invariants of their values — raises: that is a
     defect in the code, never a business outcome, and nothing is appended.
  6. **Append**, under the stream's version as it was read — for a boundary, only
     if nothing it read was appended since (`{:dcb, query, head}`) — and write the
     `accepted` row. A rejection writes a `rejected` row and appends nothing. The
     personal fields are sealed with their subjects' keys (`EhOsContract.Personal`);
     an event carrying personal data of an erased subject is refused,
     `{:error, :subject_erased}`, before anything is sealed, and writes no row: the
     decision was the unit's, the refusal is the erasure's. So is a run's key over
     `EhOsContract.Key.budget/0`, the process's name and the instance id an event
     belongs to, home or included: `{:error, :key_too_long}`, with no row, in place
     of Postgres refusing the entry.
  7. **Inside the transaction**: every read model delivered `:in_transaction`
     projects the appended events, in order, then every such policy reacts, then
     every such effect acts. What a
     policy issues is dispatched at once, in the same transaction, as the policy's
     own actor, with the event as its cause and a key derived from it,
     `"policy:<contract id>:<name>:<event id>:<index>"` — the contract too, since the
     index of accepted keys spans the application. A rejection of it is the unit's
     answer and leaves the first command standing; anything else it raises, and an
     effect's `{:error, reason}`, rolls everything back. A policy reacting to the
     kind of event it already reacted to down one chain is a cycle, and raises. A
     read model whose subscription is being rebuilt is left to the runner catching
     it up.
  8. **After it, by the same commit**: one `EhOsContract.EffectJob` per effect
     delivered `:at_least_once`, holding the effect's key and the event's id.

  **Conflicts.** When the stream, or the boundary, moved between reading and appending, dispatch rolls
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

  # Dispatch as v2 §11 has it. A boundary's read is the query over the log of v2 §10.1;
  # decoding, and conflicting on, only the types `evolve/2` folds is plan E11f-5.

  import Ecto.Query

  require Logger

  alias EhOsContract.{
    Actor,
    Authorizer,
    Clock,
    Codec,
    CommandRecord,
    Consumer,
    Decision,
    EffectJob,
    Entities,
    Event,
    Implementations,
    Key,
    Lifecycle,
    Meta,
    Model,
    Personal,
    Receipt,
    Rejection,
    Store,
    Supplier,
    SubscriptionRecord
  }

  alias EhOsContract.Subscription.Runner

  @attempts 3

  @typedoc """
  What is wrong with one field of a command: missing, not of its type, breaking an
  invariant of its domain value, brought by the caller when the engine generates
  it (`:generated`) or the host supplies it (`:supplied`), or naming an entity the
  command reads that the host does not have (`:unknown`).
  """
  @type problem ::
          {field :: atom(),
           :required | :type | {:invariant, atom()} | :generated | :supplied | :unknown}

  @typedoc "What dispatch refuses a command with, before or instead of deciding."
  @type refusal ::
          Authorizer.reason()
          | :not_declared
          | {:invalid, [problem()]}
          | :idempotency_key_reused
          | :idempotency_key_required
          | :idempotency_key_invalid
          | :conflict
          | :not_caught_up
          | :subject_erased
          | :key_too_long
          | {:not_supplied, term()}

  # Documented on `EhOsContract.dispatch/3`, which delegates here.
  @doc false
  @spec dispatch(module(), struct(), keyword() | map()) ::
          {:ok, Receipt.t()} | {:error, Rejection.t() | refusal()}
  def dispatch(contract, %module{} = command, opts) do
    model = model!(contract)
    declaration = command!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)

    with :ok <-
           permit(
             model,
             declaration,
             ctx.actor,
             scope(declaration, declaration.fields, command, values)
           ),
         :ok <- valid(callers(declaration, ctx), command, values, model.domain),
         :ok <- keyed(ctx),
         job = job(:command, model, declaration, command, ctx, values),
         {:ok, command} <- supplied(job),
         {:ok, command} <- generate_identity(model, declaration, command, ctx),
         :ok <- stream_fits(model, declaration, command),
         {:ok, reads} <- read_entities(%{job | command: command}) do
      run(Map.merge(job, %{command: command, reads: reads}), repo())
    else
      {:replayed, receipt} -> {:ok, receipt}
      refused -> refused
    end
  end

  # Documented on `EhOsContract.record/3`, which delegates here.
  @doc false
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, Receipt.t()} | {:error, refusal() | :not_created}
  def record(contract, %module{} = event, opts) do
    model = model!(contract)
    declaration = recorded!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)

    with :ok <- permit_record(model, declaration, ctx.actor),
         :ok <- valid(callers(declaration, ctx), event, values, model.domain),
         :ok <- keyed(ctx),
         job = job(:record, model, declaration, event, ctx, values),
         {:ok, event} <- supplied(job),
         :ok <- stream_fits(model, declaration, event) do
      run(%{job | command: event}, repo())
    else
      {:replayed, receipt} -> {:ok, receipt}
      refused -> refused
    end
  end

  defp job(kind, model, declaration, struct, ctx, values) do
    %{
      kind: kind,
      type:
        if(kind == :command,
          do: Atom.to_string(declaration.name),
          else: "record:#{declaration.name}"
        ),
      model: model,
      declaration: declaration,
      command: struct,
      ctx: ctx,
      values: values
    }
  end

  # Documented on `EhOsContract.query/3`, which delegates here.
  @doc false
  @spec query(module(), struct(), keyword() | map()) ::
          {:ok, [struct()] | struct() | nil} | {:error, refusal()}
  def query(contract, %module{} = params, opts) do
    model = model!(contract)
    declaration = query!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)
    scope = scope(declaration, declaration.params, params, values)

    with :ok <- permit_query(model, declaration, ctx.actor, scope),
         :ok <- valid(declaration.params, params, values, model.domain),
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
    key = "#{model.id}:read_model:#{declaration.reads}"
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

  # --- from outside ------------------------------------------------------------------

  @typedoc "What `call/3` is asked: a command, a recording or a query, by its capability."
  @type call :: {:command | :record | :query, String.t()}

  # The contract and the declaration `capability` names among `contracts`: a command,
  # a recording or a query, as `kind` says, under the name EHOS grants it by
  # (`EhOsContract.Model.capabilities/1`). `{:error, :not_found}` for a name none of
  # them declares as that kind — `<name>.subscribe` among them, which no caller
  # calls.
  # Called by plug.ex.
  @doc false
  @spec route([module()], :command | :record | :query, String.t()) ::
          {:ok, Model.t(), map()} | {:error, :not_found}
  def route(contracts, kind, capability) do
    Enum.find_value(contracts, {:error, :not_found}, fn contract ->
      model = Model.fetch(contract)

      case Map.get(Model.capabilities(model), capability) do
        %{kind: ^kind, name: name} ->
          declarations =
            case kind do
              :command -> model.commands
              :record -> model.events
              :query -> model.queries
            end

          {:ok, model, Enum.find(declarations, &(&1.name == name))}

        _other ->
          nil
      end
    end)
  end

  # Documented on `EhOsContract.call/3`, which delegates here.
  @doc false
  @spec call(call(), term(), keyword() | map()) ::
          {:ok, Receipt.t() | [struct()] | struct() | nil}
          | {:error,
             Rejection.t()
             | refusal()
             | :not_created
             | :not_found
             | :no_actor
             | :not_an_object
             | :correlation_id_is_not_a_uuid}
  def call({kind, capability}, input, opts)
      when kind in [:command, :record, :query] and is_binary(capability) do
    opts = Enum.to_list(opts)
    contracts = Keyword.get_lazy(opts, :contracts, &EhOsContract.Registry.contracts/0)

    with {:ok, model, declaration} <- route(contracts, kind, capability),
         {:ok, actor} <- credential(Keyword.get(opts, :actor)) do
      case prepare(model, kind, declaration, input, opts) do
        {:ok, struct} ->
          run_call(kind, model, struct, actor, opts)

        {:error, problem} ->
          sent = if is_map(input), do: input, else: %{}

          case permit_undecoded(model, kind, declaration, actor, sent) do
            :ok -> {:error, problem}
            refused -> refused
          end
      end
    end
  end

  defp credential(%Actor{kind: :credential} = actor), do: {:ok, actor}
  defp credential(_none_or_not_a_credential), do: {:error, :no_actor}

  # The struct dispatch or query takes, or what is wrong with what was sent.
  defp prepare(_model, _kind, _declaration, input, _opts) when not is_map(input),
    do: {:error, :not_an_object}

  defp prepare(model, kind, declaration, input, opts) do
    fields = if kind == :query, do: declaration.params, else: declaration.fields
    values = Codec.values(model.domain)

    with {:ok, decoded} <- decoded(fields, input, values, kind),
         :ok <- correlation(kind, Keyword.get(opts, :correlation_id)) do
      generated = if kind == :record, do: :event, else: kind
      {:ok, struct!(Model.module_for(model, generated, declaration.name), decoded)}
    end
  end

  # Plan T1: a field the host supplies is not the caller's to send — present at all,
  # even as `null`, it is refused by name — and is not decoded from the request.
  defp decoded(fields, input, values, kind) do
    supplied = Supplier.fields(fields)
    # Under either key: `Codec.decode/4` reads an atom's too, from Elixir code.
    sent =
      for f <- supplied,
          Map.has_key?(input, Atom.to_string(f.name)) or Map.has_key?(input, f.name),
          do: {f.name, :supplied}

    case {Codec.decode(fields -- supplied, input, values, strings: kind == :query), sent} do
      # `nil` until the host supplies it, once the caller is authorized.
      {{:ok, decoded}, []} -> {:ok, Enum.into(supplied, decoded, &{&1.name, nil})}
      {{:ok, _decoded}, sent} -> {:error, {:invalid, sent}}
      {{:error, problems}, sent} -> {:error, {:invalid, problems ++ sent}}
    end
  end

  defp correlation(:query, _id), do: :ok
  defp correlation(_kind, nil), do: :ok

  # The text form only: `Ecto.UUID.cast/1` also takes any sixteen bytes as a raw UUID,
  # which the log's column then refuses inside the transaction.
  defp correlation(_kind, id) when is_binary(id) and byte_size(id) == 36 do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :correlation_id_is_not_a_uuid}
    end
  end

  defp correlation(_kind, _id), do: {:error, :correlation_id_is_not_a_uuid}

  defp run_call(:query, model, params, actor, opts),
    do: query(model.module, params, [actor: actor] ++ Keyword.take(opts, [:min_position, :wait]))

  defp run_call(kind, model, struct, actor, opts) do
    opts = [actor: actor, supply: true] ++ Keyword.take(opts, [:idempotency_key, :correlation_id])

    if kind == :command,
      do: dispatch(model.module, struct, opts),
      else: record(model.module, struct, opts)
  end

  # --- who ---------------------------------------------------------------------------

  # `call/3`'s question when what it was given fails before dispatch or query would
  # run — not an object, fields that do not decode, a correlation id that is not a
  # UUID: the request either of them would make, with a scope value as it was sent.
  # Asked first, a caller without the capability learns nothing about the
  # declaration's fields, and every request is still one decision (v2 §11).
  defp permit_undecoded(model, :command, declaration, actor, input) do
    scope =
      case Map.get(declaration, :scope) do
        nil -> nil
        dimension -> scope_request(dimension, sent(input, dimension))
      end

    permit(model, declaration, actor, scope)
  end

  defp permit_undecoded(model, :record, declaration, actor, _input),
    do: permit_record(model, declaration, actor)

  defp permit_undecoded(model, :query, %{scope: nil} = declaration, actor, _input),
    do: permit_query(model, declaration, actor, nil)

  defp permit_undecoded(model, :query, declaration, actor, input) do
    permit_query(
      model,
      declaration,
      actor,
      scope_request(declaration.scope, sent(input, declaration.scope))
    )
  end

  # A scope value as the request sent it, when it is text an identifier may be: one with a NUL,
  # invalid UTF-8 or past 255 bytes is no value any grant holds, and the `Authorizer` may
  # record what it is asked.
  defp sent(input, dimension) do
    value = Map.get(input, Atom.to_string(dimension))
    if Codec.text?(value) and byte_size(value) <= 255, do: value
  end

  defp permit(model, declaration, actor), do: permit(model, declaration, actor, nil)

  # A credential is asked for the command's capability, and for a scoped command with
  # the value of its scope field (plan E9c), as a scoped query is (D10).
  defp permit(model, declaration, %Actor{kind: :credential} = actor, scope) do
    ask(actor, %Authorizer.Request{
      kind: :command,
      capability: capability(model, :command, declaration.name),
      contract: model.module,
      contract_id: model.id,
      version: model.version,
      scope: scope && {scope.dimension, scope.value}
    })
  end

  defp permit(model, declaration, actor, _scope), do: permit_code(model, declaration, actor)

  defp permit_code(model, declaration, %Actor{kind: :system, name: name}),
    do: named(model, declaration.by, name)

  defp permit_code(model, declaration, %Actor{kind: :reaction, name: {:policy, name}}) do
    policy = Enum.find(model.policies, &(&1.name == name))
    if policy && declaration.name in policy.issues, do: :ok, else: {:error, :not_declared}
  end

  # A process manager issues what its reactions and its timers name.
  defp permit_code(model, declaration, %Actor{kind: :reaction, name: {:pm, name}}) do
    case Enum.find(model.process_managers, &(&1.name == name)) do
      nil ->
        {:error, :not_declared}

      pm ->
        issues = Enum.flat_map(pm.starts_on ++ pm.on ++ pm.timers, & &1.issues)
        if declaration.name in issues, do: :ok, else: {:error, :not_declared}
    end
  end

  defp permit_code(_model, _declaration, actor) do
    raise ArgumentError,
          "dispatch takes `actor:`, an EhOsContract.Actor — a credential's or a :system actor " <>
            "of the domain — and got #{inspect(actor)}"
  end

  defp permit_record(model, declaration, %Actor{kind: :credential} = actor) do
    ask(actor, %Authorizer.Request{
      kind: :record,
      capability: capability(model, :record, declaration.name),
      contract: model.module,
      contract_id: model.id,
      version: model.version
    })
  end

  defp permit_record(model, declaration, %Actor{kind: :system, name: name}),
    do: named(model, declaration.recorded_by, name)

  defp permit_record(_model, _declaration, %Actor{kind: :reaction}), do: {:error, :not_declared}
  defp permit_record(model, declaration, actor), do: permit(model, declaration, actor)

  defp permit_query(model, declaration, %Actor{kind: :credential} = actor, scope) do
    ask(actor, %Authorizer.Request{
      kind: :query,
      capability: capability(model, :query, declaration.name),
      contract: model.module,
      contract_id: model.id,
      version: model.version,
      scope: scope && {scope.dimension, scope.value}
    })
  end

  defp permit_query(model, declaration, %Actor{kind: :system, name: name}, _scope),
    do: named(model, declaration.by, name)

  defp permit_query(_model, _declaration, %Actor{kind: :reaction}, _scope),
    do: {:error, :not_declared}

  defp permit_query(model, declaration, actor, _scope), do: permit(model, declaration, actor)

  # A scoped command's or query's dimension, the value it carries in the form a
  # credential's `scp` carries — a string, or nil when it is missing — and the field's
  # type. `fields` are a command's fields or a query's params. It is asked before the
  # fields are checked, so a value that does not fit its type is no value, refused as
  # one (plan E9c review), rather than an exception in the encoder.
  defp scope(declaration, fields, data, values) do
    case Map.get(declaration, :scope) do
      nil ->
        nil

      dimension ->
        field = Enum.find(fields, &(&1.name == dimension))

        value =
          if Codec.problems([field], data, values) == [],
            do: scoped(field.type, Map.get(data, dimension), values)

        dimension |> scope_request(value) |> Map.put(:type, field.type)
    end
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
         %{dimension: dimension, type: type} <-
           scope(declaration, declaration.params, %{}, values) do
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

  # A declaration no person may use has no capability (`Model.capabilities/1`), so
  # no credential is granted it and none is asked about.
  defp ask(_actor, %Authorizer.Request{capability: nil}), do: {:error, :missing_capability}
  defp ask(actor, request), do: Authorizer.run(actor, request)

  defp capability(model, kind, name) do
    Enum.find_value(Model.capabilities(model), fn
      {capability, %{kind: ^kind, name: ^name}} -> capability
      _ -> nil
    end)
  end

  # --- what --------------------------------------------------------------------------

  # A command that creates an aggregate whose identity is generated arrives without
  # it, and gets a UUIDv7 here, once per dispatch, so a retried conflict keeps it
  # (plan EM3). One that brings its own is refused: the library gives it, and a host
  # that made up its own would have two ways of doing so. And it needs an idempotency
  # key, since a retry without one would make a second aggregate the caller never
  # hears of (the user's choice after the EM3 review); a reaction's is derived.
  defp generate_identity(model, %{creates: true} = declaration, command, ctx) do
    [field] = Enum.find(model.units, &(&1.name == declaration.unit)).identity

    cond do
      Map.fetch!(command, field) != nil -> {:error, {:invalid, [{field, :generated}]}}
      ctx.idempotency_key == nil -> {:error, :idempotency_key_required}
      true -> {:ok, Map.put(command, field, Ecto.UUID.generate(version: 7))}
    end
  end

  defp generate_identity(_model, _declaration, command, _ctx), do: {:ok, command}

  # An aggregate's stream id is the first column of the log's unique index; a boundary's
  # events have none (issue #98).
  defp stream_fits(model, declaration, struct) do
    case Enum.find(model.units, &(&1.name == declaration.unit)) do
      %{kind: :aggregate} = unit -> fits([stream(unit, struct)])
      _boundary -> :ok
    end
  end

  defp fits(columns), do: if(Key.fits?(columns), do: :ok, else: {:error, :key_too_long})

  # A key is stored in `eh_os_contract_commands` and its unique index, and in the event's
  # metadata: printable ASCII that a text column, `jsonb` and a btree entry all hold. A
  # reaction's too: its actor is a struct any caller can build, and the keys the library
  # derives (`EhOsContract.Consumer`) are of this form anyway.
  defp keyed(%{idempotency_key: nil}), do: :ok

  defp keyed(%{idempotency_key: key}),
    do: if(idempotency_key?(key), do: :ok, else: {:error, :idempotency_key_invalid})

  # Whether `key` is an idempotency key the log holds: printable ASCII (`0x21`–`0x7E`) of 1 to
  # 255 bytes, what a text column, `jsonb` and a btree entry all take. A command with any other
  # key is refused with `:idempotency_key_invalid`. The keys the library derives for the
  # commands a reaction issues hold to it too.
  @doc false
  # Bytes, not characters, so no `u`: a binary that is not UTF-8 is refused byte by byte.
  @spec idempotency_key?(term()) :: boolean()
  def idempotency_key?(key), do: is_binary(key) and key =~ ~r/\A[\x21-\x7E]{1,255}\z/

  # Plan T1: what the caller's own fields are checked as before the host is asked —
  # every field but the supplied ones, which the host has not given yet. The
  # application's own struct is checked whole: it is not asked of the host.
  defp callers(declaration, %{supply: true}),
    do: declaration.fields -- Supplier.fields(declaration.fields)

  defp callers(declaration, _ctx), do: declaration.fields

  # Plan T1: the fields the host gives, asked of it last before the unit is read — after
  # authorization, so a caller who may not issue the command never makes the host look
  # anything up, and after what the caller sent is found sound, so a request refused
  # for its own fields or key is refused as such. A retry of a request already
  # accepted under its key gets its receipt without asking: the answer would be thrown
  # away, and a host that is down would turn the receipt into a refusal. The host's
  # answer is held to the fields' types and invariants (`Supplier.run/6`).
  defp supplied(%{ctx: %{supply: false}, command: struct}), do: {:ok, struct}

  defp supplied(job) do
    %{model: model, declaration: declaration, ctx: ctx, command: struct} = job

    case Supplier.fields(declaration.fields) do
      [] ->
        {:ok, struct}

      fields ->
        with :new <- idempotent(repo(), job) do
          names = Enum.map(fields, & &1.name)

          request = %Supplier.Request{
            kind: job.kind,
            capability: capability(model, job.kind, declaration.name),
            contract: model.module,
            name: declaration.name,
            fields: names,
            given: struct |> Map.from_struct() |> Map.drop([:__meta__ | names])
          }

          with {:ok, given} <-
                 Supplier.run(ctx.actor, request, declaration.fields, job.values, model.domain),
               do: {:ok, struct(struct, given)}
        else
          {:ok, receipt} -> {:replayed, receipt}
          refused -> refused
        end
    end
  end

  # Plan DD, T2a (#240): the entities the command reads, asked of the host once, before
  # the transaction dispatch owns, so a conflict's retry decides on the same rows and the
  # host's lookup does not hold the transaction open. No reaction issues such a command
  # (A8), so none is asked inside dispatch's own transaction, after its append lock; one
  # the host dispatches inside a transaction of its own is asked inside that. As for supplied fields, a
  # retry of a command already accepted under its key gets its receipt without asking: a
  # row deleted since would turn the receipt into a refusal.
  defp read_entities(%{declaration: %{reads: [_ | _]}} = job) do
    with :new <- idempotent(repo(), job) do
      Entities.read(job.model, job.declaration, job.command, job.ctx.actor)
    else
      {:ok, receipt} -> {:replayed, receipt}
      refused -> refused
    end
  end

  defp read_entities(_job), do: {:ok, %{}}

  defp valid(fields, struct, values, domain) do
    case Codec.problems(fields, struct, values, domain) do
      [] -> :ok
      problems -> {:error, {:invalid, problems}}
    end
  end

  # --- the transaction -----------------------------------------------------------------

  defp run(job, repo) do
    if repo.in_transaction?() do
      case attempt(job, repo) do
        :conflict -> {:error, :conflict}
        result -> marked(job, result)
      end
    else
      owned(job, repo, 1)
    end
  end

  defp owned(job, repo, attempt) do
    Process.delete({__MODULE__, :failed_in})

    result =
      try do
        Runner.transaction(repo, fn ->
          case attempt(job, repo) do
            :conflict -> repo.rollback(:conflict)
            result -> marked(job, result)
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
        result

      {:error, :conflict} when attempt < @attempts ->
        Process.sleep(:rand.uniform(10))
        owned(job, repo, attempt + 1)

      {:error, :conflict} ->
        {:error, :conflict}
    end
  end

  # Once committed, the runners can read what was appended (v2 §11): the transaction
  # is marked to wake them only when something was, and something reads it after the
  # transaction — with Oban's Postgres notifier every notification is a query. Whoever
  # owns the transaction, dispatch included, wakes them once it commits, however many
  # dispatches inside marked it.
  defp marked(job, {:ok, %Receipt{duplicate: false, events: [_ | _]}} = result) do
    if Implementations.ordered?(job.model.module), do: Runner.notify_on_commit()
    result
  end

  defp marked(_job, nothing_appended), do: nothing_appended

  # One try: `{:ok, receipt}`, `{:error, _}`, or `:conflict` when the stream moved.
  defp attempt(%{kind: :record} = job, repo) do
    with :new <- idempotent(repo, job) do
      unit = Enum.find(job.model.units, &(&1.name == job.declaration.unit))
      # Nothing is decided, so nothing is folded: the unit is read whole, as before.
      {recorded, condition} = read_unit(repo, job.model, unit, job.command, :all)

      # An aggregate whose identity the library gives is made only by the command that
      # creates it (A6), so an event recorded for one that does not exist would make
      # it under an identity the host made up (the user's choice after the EM3 review).
      if Map.get(unit, :generated) && recorded == [] do
        {:error, :not_created}
      else
        job = Map.merge(job, %{condition: condition, given: recorded})
        commit(job, [{job.declaration, job.command}], repo)
      end
    end
  end

  defp attempt(job, repo) do
    %{model: model, declaration: declaration, command: command, ctx: ctx} = job

    with :new <- idempotent(repo, job) do
      unit = Enum.find(model.units, &(&1.name == declaration.unit))
      impl = Implementations.fetch!(model, unit.kind, unit.name)
      folded = Implementations.folded_types(model, impl)
      {recorded, condition} = read_unit(repo, model, unit, command, folded)
      # The status needs only the rows' types, so a command refused on it decodes nothing.
      {before, status} = statuses(model, Lifecycle.of(unit), recorded)
      job = Map.merge(job, %{condition: condition, given: recorded})

      if Lifecycle.admits?(declaration, status) do
        state = fold(job, unit, impl, folded_only(recorded, model, unit, folded), before, status)

        case person_named(declaration, state, ctx.actor) do
          :ok ->
            decide(job, unit, impl, state, status, %{command | __meta__: meta(ctx)}, repo)

          {:refused, invariant} ->
            write_row!(repo, job, "rejected", %{invariant: Atom.to_string(invariant)})
            {:error, %Rejection{invariant: invariant}}
        end
      else
        # Plan LC2: outside the statuses its `from:` names, the command is refused on
        # its `or_rejects:` before the decision, as the decision would have refused it.
        write_row!(repo, job, "rejected", %{invariant: Atom.to_string(declaration.or_rejects)})
        {:error, %Rejection{invariant: declaration.or_rejects}}
      end
    end
  end

  # Plan DD, A1 (#247): a command whose `actor_is` names a field of the state is issued
  # only by the person that field holds, compared with the credential's subject, and is
  # refused on its invariant before the decision otherwise, as a lifecycle's
  # precondition is. A `:system` actor and a reaction act for the application, and pass.
  # A field still empty names nobody, so every person is refused.
  defp person_named(declaration, state, %Actor{kind: :credential, subject: subject}) do
    case Decision.not_the_person(declaration, state, subject) do
      nil -> :ok
      invariant -> {:refused, invariant}
    end
  end

  defp person_named(_declaration, _state, _actor), do: :ok

  defp decide(job, unit, impl, state, status, command, repo) do
    %{model: model, declaration: declaration} = job
    # A command that reads entities is decided with them (plan DD, T2a, #240).
    args =
      if Map.has_key?(declaration, :reads),
        do: [command, state, job.reads],
        else: [command, state]

    decision = stage("decider", fn -> apply(impl, declaration.name, args) end)

    case decision do
      {:ok, events} when is_list(events) ->
        # Held to its declaration and its unit's lifecycle (plan LC2, W4): an event the
        # contract does not allow from where the unit stands is a defect, never a
        # business outcome, and nothing is appended.
        {emitted, _status} =
          stage("decider", fn ->
            Decision.held!(model, declaration, unit, status, job.command, events, job.values)
          end)

        commit(job, emitted, repo)

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

  defp commit(job, events, repo) do
    # Before the subjects' keys, which `Personal.for_writing/2` may create and the
    # refusal, returned rather than rolled back, would leave behind (issue #98).
    with :ok <- runs_fit(job.model, events), do: append(job, events, repo)
  end

  defp append(job, events, repo) do
    # The subjects' keys are read and wrapped before the lock, where a vault's round
    # trip holds up no other writer, and stored under it (v2 §14).
    prepared = Personal.prepare(repo, subjects(job, events))
    :ok = Store.lock(repo)

    # Checked again under the lock: another transaction with the same key may have
    # committed while this one decided. Under the lock too, no subject whose data
    # the events carry is erased, and none gets its key created again (v2 §14).
    with :new <- idempotent(repo, job),
         {:ok, keys} <- Personal.for_writing(repo, prepared) do
      command_id = Ecto.UUID.generate()
      entries = Enum.map(events, &entry(job, &1, command_id, keys))

      case Store.append(repo, entries, job.condition) do
        {:error, conflict} when conflict in [:wrong_expected_version, :condition_failed] ->
          :conflict

        {:ok, appended} ->
          write_row!(repo, Map.put(job, :command_id, command_id), "accepted", %{
            emitted_types: Enum.map(appended, & &1.type),
            first_position: appended |> List.first() |> position(),
            last_position: appended |> List.last() |> position()
          })

          receipt =
            receipt(job, command_id, Enum.zip(Enum.map(events, &elem(&1, 1)), appended), false)

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
    delivered =
      for {_event, row} <- pairs,
          effect <- Implementations.effects(job.model.module, row.type),
          do: {effect.key, row.id}

    # Where dispatch found the effects besides the configured applications, which the
    # key's contract id cannot name (plan DD, ID4, #178): asked once, and only when
    # there is a job to carry it.
    application = delivered != [] && Application.get_application(job.model.module)
    jobs = for {key, id} <- delivered, do: EffectJob.job(key, id, application || nil)

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
        from(c in CommandRecord,
          where:
            c.idempotency_key == ^key and c.issued_by == ^Actor.label(job.ctx.actor) and
              c.outcome == "accepted"
        )
      )

    cond do
      accepted == nil ->
        :new

      accepted.contract == job.model.id and
          accepted.type == job.type ->
        events =
          repo.all(from(e in Event, where: e.command_id == ^accepted.id, order_by: e.position))

        {:ok, receipt(job, accepted.id, Enum.zip(decode_all!(job, events), events), true)}

      true ->
        {:error, :idempotency_key_reused}
    end
  end

  # --- reading a unit ----------------------------------------------------------------------

  # What a unit decides over, and the condition its append is made under. An
  # aggregate is its stream, appended under the version read. A consistency boundary
  # is a query over the log (v2 §10.1): its own events carrying its identity, and each
  # event it consults, on the fields it matches — every one of them when it matches on
  # none — appended only if nothing it reads was appended after the head it read to.
  # A row of a type the contract declares and `evolve/2` does not fold is not decoded
  # (plan E11f-5): the state is a function of the folded ones alone, so it can neither
  # change a decision nor stop one — except through an aggregate's status (plan LC2),
  # which is computed from every row's type, and needs no row decoded. A type the contract no longer declares is still
  # decoded, and stops the stream: that is history a changed contract left behind.
  defp folded_only(recorded, _model, _unit, :all), do: recorded

  defp folded_only(recorded, model, unit, folded) do
    consulted =
      for consults <- Map.get(unit, :consults, []) do
        {_contract, declaration} = Model.declaring(model, consults.event)
        declaration.type
      end

    declared = MapSet.new(Enum.map(model.events, & &1.type) ++ consulted)

    Enum.reject(
      recorded,
      &(MapSet.member?(declared, &1.type) and not MapSet.member?(folded, &1.type))
    )
  end

  # An aggregate reads its whole stream, whose version is the append's condition.
  defp read_unit(repo, _model, %{kind: :aggregate} = unit, command, _folded) do
    stream = stream(unit, command)
    recorded = Store.read_stream(repo, stream, 0)
    version = if recorded == [], do: 0, else: List.last(recorded).stream_version
    {recorded, {:stream, stream, version}}
  end

  # A boundary reads, and conflicts on, only the types its `evolve/2` folds. When it
  # folds none of them, the whole query stays: a store query cannot be empty.
  defp read_unit(repo, model, %{kind: :dcb} = unit, command, folded) do
    query = model |> boundary(unit, command) |> narrowed(folded)
    {recorded, head} = Store.read_query(repo, query)
    {recorded, {:dcb, query, head}}
  end

  defp stream(unit, struct),
    do: Key.stream(unit.name, Enum.map(unit.identity, &Map.fetch!(struct, &1)))

  defp boundary(model, unit, command) do
    tag = fn fields -> Enum.map(fields, &Key.tag(&1, Map.fetch!(command, &1))) end
    own = for e <- model.events, e.unit == unit.name, do: e.type

    consulted =
      for consults <- unit.consults do
        {_contract, declaration} = Model.declaring(model, consults.event)
        %{types: [declaration.type], tags: tag.(consults.match)}
      end

    [%{types: own, tags: tag.(unit.identity)} | consulted]
  end

  defp narrowed(query, :all), do: query

  defp narrowed(query, folded) do
    narrow =
      for item <- query,
          types = Enum.filter(item.types, &MapSet.member?(folded, &1)),
          types != [],
          do: %{item | types: types}

    if narrow == [], do: query, else: narrow
  end

  # --- reading a stream --------------------------------------------------------------------

  # The unit's state. For an aggregate with a lifecycle (plan LC2) the status — from
  # the names of every event of the stream, not only those `evolve/2` folds — is put
  # into the state before each folded event, `before` by position, so `evolve/2` sees
  # where the aggregate stood when the event happened, and `status` after the last.
  # Whatever `evolve/2` puts there is overwritten: the status is the engine's.
  defp fold(job, unit, impl, recorded, before, status) do
    state =
      struct(
        Module.concat(Model.module_for(job.model, unit.kind, unit.name), State),
        Map.new(unit.identity, &{&1, Map.fetch!(job.command, &1)})
      )

    state =
      if function_exported?(impl, :evolve, 2) do
        # Reading the stream back — its keys too — is part of evolving, for the failed row.
        rows = Enum.sort_by(recorded, & &1.position)
        events = stage("evolve", fn -> decode_all!(job, recorded) end)

        rows
        |> Enum.zip(events)
        |> Enum.reduce(state, fn {row, event}, state ->
          state = with_status(state, unit, Map.get(before, row.position))
          stage("evolve", fn -> state!(impl.evolve(state, event), state, impl) end)
        end)
      else
        state
      end

    with_status(state, unit, status)
  end

  # `evolve/2` returns the unit's state. Anything else is a defect, named without the
  # value: a state holds decoded fields, personal ones among them (v2 §17).
  defp state!(%module{} = next, %module{}, _impl), do: next

  defp state!(_other, %module{}, impl) do
    raise ArgumentError,
          "#{inspect(impl)}.evolve/2 returned what is not a %#{inspect(module)}{}; it returns " <>
            "the state it was given, changed"
  end

  # The status before each row, by position, and after the last.
  defp statuses(_model, nil, _rows), do: {%{}, nil}

  defp statuses(model, lifecycle, rows) do
    names = Map.new(model.events, &{&1.type, &1.name})
    rows = Enum.sort_by(rows, & &1.position)
    {befores, status} = Lifecycle.walk(lifecycle, Enum.map(rows, &Map.get(names, &1.type)))
    {Map.new(Enum.zip(Enum.map(rows, & &1.position), befores)), status}
  end

  defp with_status(state, unit, status) do
    if Lifecycle.of(unit), do: %{state | status: status}, else: state
  end

  # A boundary reads events of the sibling contracts it consults too, and each is
  # decoded by the contract that declares its type — found from this contract's model,
  # not from the name the row stored, which a renamed module would leave behind. The
  # log's order is kept.
  defp decode_all!(job, rows) do
    own = MapSet.new(job.model.events, & &1.type)

    rows
    |> Enum.group_by(fn row ->
      if MapSet.member?(own, row.type), do: job.model, else: declaring!(job.model, row)
    end)
    |> Enum.flat_map(fn {model, rows} ->
      values = if model == job.model, do: job.values, else: Codec.values(model.domain)
      Enum.zip(rows, Consumer.decode_all!(model, values, rows))
    end)
    |> Enum.sort_by(fn {row, _event} -> row.position end)
    |> Enum.map(&elem(&1, 1))
  end

  # The sibling contract this contract consumes the row's type from.
  defp declaring!(model, row) do
    Enum.find_value(model.consumes, fn
      %{kind: :contract, from: from} ->
        sibling = Model.fetch(from)
        if Enum.any?(sibling.events, &(&1.type == row.type)), do: sibling

      _published ->
        nil
    end) ||
      raise ArgumentError,
            "#{inspect(model.module)} neither declares nor consumes an event of type " <>
              "#{inspect(row.type)}, which it read at position #{row.position}"
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

    %{
      id: Ecto.UUID.generate(),
      type: declaration.type,
      # Plan W1: the version of the fields it was written with, so a reader running
      # older code refuses it instead of misreading it, and an upcaster (V1) knows
      # what it starts from. Until W1 every row said 1, the column's default.
      schema_version: declaration.schema_version,
      contract: model.id,
      contract_version: model.version,
      tags: tags(declaration, event, values, time_zone(model)),
      process: process_name(model),
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

  # Every required, non-personal `:id` field of the event, its unit's identity among
  # them, since that is what a consistency boundary may match on (A4, X6). Tagging
  # only the fields some boundary matches today would leave the events appended
  # before a new boundary untagged, and it would never see them. For the same reason
  # every required, non-personal date and timestamp is tagged with its day (plan W2),
  # in the domain's time zone, which a boundary bucketing by day reads (B2).
  defp tags(declaration, event, values, zone) do
    for(
      field <- declaration.fields,
      Key.tag_field?(field, values),
      do: Key.tag(field.name, Map.fetch!(event, field.name))
    ) ++
      for field <- declaration.fields,
          Key.bucket_field?(field, values),
          do: Key.day_tag(field.name, Map.fetch!(event, field.name), zone)
  end

  # A contract may name a domain that is not loaded (v2 §8); its days are then UTC's.
  defp time_zone(model) do
    case model.domain && Code.ensure_loaded?(model.domain) && Model.fetch(model.domain) do
      %{time_zone: zone} -> zone
      _ -> "Etc/UTC"
    end
  end

  # The run a struct belongs to: the process's name, then its correlation values.
  defp instance(model, struct) do
    case Model.process(model) do
      nil -> nil
      process -> run_key(process, struct)
    end
  end

  defp process_name(model) do
    case Model.process(model) do
      nil -> nil
      process -> Atom.to_string(process.name)
    end
  end

  # The key of the run of `process` an event belongs to, or nil when it lacks a
  # correlation field. Called by scenario_case.ex too, which files a promise scenario's
  # givens as dispatch files events (plan DD, S2, #251).
  @doc false
  @spec run_key(map(), struct()) :: String.t() | nil
  def run_key(process, struct) do
    values = Enum.map(process.correlate, &Map.get(struct, &1))
    if Enum.all?(values, &(&1 != nil)), do: Key.join([process.name | values])
  end

  # Every run the events belong to, as `eh_os_contract_event_runs` indexes it: the
  # process's name and the instance id (issue #98).
  defp runs_fit(model, events) do
    runs =
      Enum.flat_map(events, fn {declaration, event} ->
        home =
          case instance(model, event) do
            nil -> []
            key -> [{process_name(model), key}]
          end

        home ++ included_runs(model, declaration.type, event)
      end)

    if Enum.all?(runs, fn {process, key} -> Key.fits?([process, key]) end),
      do: :ok,
      else: {:error, :key_too_long}
  end

  # An event without the fields another process correlates on is in none of its runs,
  # as one without its home process's is in no home run. A process module's runs are
  # filed under its id (plan DD, P2c, #210), a contract process's under its name.
  defp included_runs(model, type, event) do
    for process <- Implementations.included(model.module, type),
        key = run_key(process, event),
        key != nil,
        do: {to_string(process.name), key}
  end

  defp write_row!(repo, job, outcome, fields) do
    %{model: model, ctx: ctx} = job

    row =
      struct!(
        CommandRecord,
        Map.merge(
          %{
            id: Map.get(job, :command_id) || Ecto.UUID.generate(),
            contract: model.id,
            type: job.type,
            issued_by: Actor.label(ctx.actor),
            idempotency_key: if(outcome == "accepted", do: ctx.idempotency_key),
            causation_event_id: ctx.causation_id,
            correlation_id: ctx.correlation_id,
            outcome: outcome,
            # Each type once, in the order first read: a boundary reads what may be the
            # whole history of a type, and coverage asks only which types were there.
            given_types: job |> Map.get(:given, []) |> Enum.map(& &1.type) |> Enum.uniq(),
            process: process_name(model),
            instance_id: instance(model, job.command),
            inputs: Entities.recorded(model, job.declaration, Map.get(job, :reads, %{}))
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

  defp receipt(job, command_id, pairs, duplicate) do
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

    # The unit's identity as the events carry it, so a duplicate's is the first
    # command's. When the command decided no event, a fresh one's is the command's; a
    # duplicate's is unknown, since this command's may be one generated just now for
    # the retry, or name another unit under a reused key.
    keys = Enum.find(job.model.units, &(&1.name == job.declaration.unit)).identity

    identity =
      case {events, duplicate} do
        {[first | _], _} -> Map.take(first, keys)
        {[], false} -> Map.take(job.command, keys)
        {[], true} -> %{}
      end

    %Receipt{
      command_id: command_id,
      identity: identity,
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
      supply: Map.get(opts, :supply, false) == true,
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
        raise ArgumentError, "#{inspect(module)} is not a contract"
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

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
