defmodule EhOsContract.Dispatcher do
  @moduledoc """
  A command to a contract, from the actor who issues it to the events in the log
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
  2. **What.** The command's fields against their types (`EhOsContract.Codec`), and
     each value against the invariants of its domain value (plan EL2b):
     `{:error, {:invalid, [{field, :required | :type | {:invariant, name}}]}}`,
     before anything is decided or written. A command that `creates:`
     an aggregate whose identity is generated gets a UUIDv7 here, and is refused
     with `{field, :generated}` when it brings one of its own, and with
     `{:error, :idempotency_key_required}` without an idempotency key (plan EM3).
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
     the log (v2 §10.1): its own events carrying its identity, and every event it
     `consults` — on the fields it `match`es, or every one of that type when it
     consults by `where:` alone — each decoded by the contract that declares it, in
     the log's order. Only what `evolve/2` folds is decoded, when its one catch-all
     is `def evolve(state, _), do: state`, and a boundary reads, and conflicts on,
     those types alone (plan E11f-5).
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
     decision was the unit's, the refusal is the erasure's.
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
          | {:invalid, [Codec.problem() | {atom(), :generated}]}
          | :idempotency_key_reused
          | :idempotency_key_required
          | :conflict
          | :not_caught_up
          | :subject_erased

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

    with :ok <-
           permit(
             model,
             declaration,
             ctx.actor,
             scope(declaration, declaration.fields, command, values)
           ),
         :ok <- valid(declaration.fields, command, values, model.domain),
         {:ok, command} <- generate_identity(model, declaration, command, ctx) do
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

  A credential's actor is asked of the `EhOsContract.Authorizer` for the event's
  capability, `<domain>.<event>` (`EhOsContract.Model.capabilities/1`), as a
  command's is — a person who saw something, reception marking the patient's
  arrival. An event only `:system` actors record has no capability, and a
  credential is refused `:missing_capability`. A `:system` actor records it when the
  event's `recorded_by:` names it: an integration writing down what a system
  answered. Until E9a a credential was
  refused, because no capability named a recording. Otherwise it goes as a command
  does — the fields checked, the
  idempotency key honoured, the unit's stream version as the append's condition,
  the consumers in the transaction run, the `accepted` row written with the type
  `"record:<event>"` — only without a decider. An event of an aggregate whose
  identity is generated is recorded only for one a command created:
  `{:error, :not_created}` otherwise.
  """
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, Receipt.t()} | {:error, refusal() | :not_created}
  def record(contract, %module{} = event, opts) do
    model = model!(contract)
    declaration = recorded!(model, module)
    ctx = context(opts)
    values = Codec.values(model.domain)

    with :ok <- permit_record(model, declaration, ctx.actor),
         :ok <- valid(declaration.fields, event, values, model.domain) do
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

  # --- from outside ------------------------------------------------------------------

  @typedoc "What `call/3` is asked: a command, a recording or a query, by its capability."
  @type call :: {:command | :record | :query, String.t()}

  @doc """
  The contract and the declaration `capability` names among `contracts`: a command,
  a recording or a query, as `kind` says, under the name EHOS grants it by
  (`EhOsContract.Model.capabilities/1`). `{:error, :not_found}` for a name none of
  them declares as that kind — `<name>.subscribe` among them, which no caller
  calls.
  """
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

  @doc """
  The one way in for what arrives from outside the application's code: a capability's
  name and the data as a caller sent it, with the credential it came with
  (plan E12d). `EhOsContract.Plug` is one door onto it; a form, or a job that carries
  a person's credential, is another.

      EhOsContract.call(
        {:command, "rehmed.record_payment"},
        %{"visit_id" => "w-1", "method" => "card", "amount" => 20000},
        actor: actor, idempotency_key: "req-81"
      )

  **Whether the caller may is answered first.** Data that is not a map, fields that do
  not decode against the declaration, a correlation id that is not a UUID: each is
  asked of the `EhOsContract.Authorizer` as the call would have been, so a caller
  without the capability is refused whatever it sent, and learns nothing about the
  declaration's fields; one with it is told what is wrong. Then it goes through
  `dispatch/3`, `record/3` or `query/3`, so everything they check is checked here
  the same way.

  `input` is a map with string keys, as JSON decodes; a query's values may come as
  text, as a query string carries them. `opts`: `actor:`, a credential's
  `EhOsContract.Actor`, required — a `:system` actor is the application's own code,
  which dispatches structs; `contracts:`, the contracts this door serves (every
  registered one by default); for a command or a recording `idempotency_key:` and
  `correlation_id:`, the latter a UUID's text; for a query `min_position:` and `wait:`,
  to read a write, as `query/3` takes them.

  Besides what those three answer: `{:error, :not_found}` for a capability none of
  the contracts declares as that kind, `{:error, :no_actor}` without a credential,
  and, once the caller may, `{:error, :not_an_object}` and
  `{:error, :correlation_id_is_not_a_uuid}`.
  """
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

  defp decoded(fields, input, values, kind) do
    case Codec.decode(fields, input, values, strings: kind == :query) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, problems} -> {:error, {:invalid, problems}}
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
    opts = [actor: actor] ++ Keyword.take(opts, [:idempotency_key, :correlation_id])

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

  # A scope value as the request sent it, when it is a string.
  defp sent(input, dimension) do
    case Map.get(input, Atom.to_string(dimension)) do
      value when is_binary(value) -> value
      _missing_or_not_a_string -> nil
    end
  end

  defp permit(model, declaration, actor), do: permit(model, declaration, actor, nil)

  # A credential is asked for the command's capability, and for a scoped command with
  # the value of its scope field (plan E9c), as a scoped query is (D10).
  defp permit(model, declaration, %Actor{kind: :credential} = actor, scope) do
    ask(actor, %Authorizer.Request{
      kind: :command,
      capability: capability(model, :command, declaration.name),
      contract: model.module,
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
      state = fold(job, unit, impl, folded_only(recorded, model, unit, folded))

      command = %{command | __meta__: meta(ctx)}
      decision = stage("decider", fn -> apply(impl, declaration.name, [command, state]) end)
      job = Map.merge(job, %{condition: condition, given: recorded})

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
        from(c in CommandRecord,
          where:
            c.idempotency_key == ^key and c.issued_by == ^Actor.label(job.ctx.actor) and
              c.outcome == "accepted"
        )
      )

    cond do
      accepted == nil ->
        :new

      accepted.contract == inspect(job.model.module) and
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
  # change a decision nor stop one. A type the contract no longer declares is still
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
    stream = Key.stream(unit.name, Enum.map(unit.identity, &Map.fetch!(command, &1)))
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

  defp fold(job, unit, impl, recorded) do
    state =
      struct(
        Module.concat(Model.module_for(job.model, unit.kind, unit.name), State),
        Map.new(unit.identity, &{&1, Map.fetch!(job.command, &1)})
      )

    if function_exported?(impl, :evolve, 2) do
      # Reading the stream back — its keys too — is part of evolving, for the failed row.
      events = stage("evolve", fn -> decode_all!(job, recorded) end)

      Enum.reduce(events, state, fn event, state ->
        stage("evolve", fn -> impl.evolve(state, event) end)
      end)
    else
      state
    end
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

      # The event joins the unit that decided it — its stream, or its boundary's own
      # events — so it has to be about the same unit: one carrying another identity
      # would be folded into this unit's state.
      for field <- unit.identity, Map.fetch!(event, field) != Map.fetch!(job.command, field) do
        raise ArgumentError,
              "command #{inspect(declaration.name)} decided event #{inspect(name)} for another " <>
                "unit: its #{field} is not the command's, and an event joins the stream of the " <>
                "unit that decided it. Nothing was appended."
      end

      case Codec.problems(event_declaration.fields, event, values, model.domain) do
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

    %{
      id: Ecto.UUID.generate(),
      type: declaration.type,
      contract: inspect(model.module),
      contract_version: model.version,
      tags: tags(declaration, event, values),
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

  # Every required, non-personal `:id` field of the event, its unit's identity among
  # them, since that is what a consistency boundary may match on (A4, X6). Tagging
  # only the fields some boundary matches today would leave the events appended
  # before a new boundary untagged, and it would never see them.
  defp tags(declaration, event, values) do
    for field <- declaration.fields,
        Key.tag_field?(field, values),
        do: Key.tag(field.name, Map.fetch!(event, field.name))
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
            # Each type once, in the order first read: a boundary reads what may be the
            # whole history of a type, and coverage asks only which types were there.
            given_types: job |> Map.get(:given, []) |> Enum.map(& &1.type) |> Enum.uniq(),
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

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
