defmodule EhosContract do
  @moduledoc """
  The package's public surface: the engine a host boots in its supervision tree
  (`child_spec/1`), and the calls into it: `dispatch/3`, `record/3`, `query/3`,
  `call/3` for what arrives from outside, and `erase/3`.
  """

  # The package began inside the first client's application, behind `boundary`
  # from the first commit, in the structure notes §15 foresee, so that moving it out
  # was a `git mv`.

  use Boundary,
    deps: [],
    exports: [
      Actor,
      AsyncAPI,
      Authorizer,
      Authorizer.Default,
      Authorizer.OutsideScopeError,
      Authorizer.Request,
      Authorizer.WidenedError,
      Bus,
      Bus.Local,
      Bus.Message,
      Bus.Suite,
      Check,
      Check.Catalog,
      Check.Finding,
      Clock,
      Codec,
      CommandRecord,
      Config,
      Contract,
      {Contract.Dsl, []},
      Conformance,
      DomainService,
      Conformance.Wire,
      Deployment,
      Dependency,
      Domain,
      {Domain.Dsl, []},
      Duration,
      EctoTypes.Timestamp,
      EctoTypes.Value,
      Entities,
      Entities.UnfitRowError,
      Erased,
      Event,
      Form,
      Generators,
      Graph.Document,
      Graph.Overlay,
      Implementation,
      Key,
      Key.TooLongError,
      Meta,
      Migrations,
      Model,
      OpenAPI,
      Plug,
      Process,
      {Process.Dsl, []},
      ProcessManager,
      ProcessManagerRecord,
      PropertyCase,
      Registry,
      StageOrder,
      Receipt,
      Rejection,
      Report,
      Report.Sentence,
      ScenarioCase,
      Store,
      Store.Postgres,
      Store.Suite,
      Subscription,
      Subscription.Runner,
      SubscriptionRecord,
      Supplier,
      Supplier.Request,
      Testing,
      EffectJob,
      TimerJob,
      Trace,
      Vault,
      Vault.Local
    ]

  # Read from `mix.exs` at compile time rather than through
  # `Application.spec(:ehos_contract, :vsn)`, which returns a charlist and needs the
  # application loaded — neither of which a report renderer should have to care
  # about. This is the package reading its own project file, so it carries no
  # host configuration into a compile-time attribute.
  @version Mix.Project.config()[:version]

  @typedoc """
  What is wrong with one field of a command: missing, not of its type, breaking an
  invariant of its domain value, brought by the caller when the engine generates
  it (`:generated`) or the host supplies it (`:supplied`), or naming an entity the
  command reads that the host does not have (`:unknown`).
  """
  @type problem ::
          {field :: atom(),
           :required | :type | {:invariant, atom()} | :generated | :supplied | :unknown}

  @typedoc "What `dispatch/3`, `record/3`, `query/3` and `call/3` refuse with, before or instead of deciding."
  @type refusal ::
          EhosContract.Authorizer.reason()
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

  @typedoc "What `call/3` is asked: a command, a recording or a query, by its capability."
  @type call :: {:command | :record | :query, String.t()}

  @doc """
  The engine version, as published.

  A conformance report is an arithmetic result, and this repository has already
  changed what counts as drift more than once — zero runs, work still queued,
  "never attempted" against "attempted and failing", the fourth verdict. Two
  clients on two engine versions get two answers to the same question, and the
  report is evidence somebody may be asked to defend. The version says which
  arithmetic produced it. `CHANGELOG.md` says what each one changed.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Boots the engine inside the host's supervision tree, after the host's repo and Oban:

      children = [
        MyApp.Repo,
        {Oban, Application.fetch_env!(:my_app, Oban)},
        EhosContract,
        MyAppWeb.Endpoint
      ]

  The child is a supervisor. While it starts it does, in this order:

  0. `EhosContract.Config.validate!/0` refuses to go on when `config :ehos_contract`
     has an unknown key, a value of the wrong shape or a required key missing.
  1. It scans the running binary for contracts and domains, refusing to go on when
     a domain's `time_zone:` is one the time zone database this node runs with does
     not know. It refuses as well when a v2 contract declares personal fields and the
     vault has no master key to seal them with, when a field is declared
     `supplied_by: :host` and no supplier is configured, when a command `reads:` an
     entity and no `EhosContract.Entities` is configured, when a read model
     projects personal data and defines no `forget/2`, and when the database's
     storage is missing or older than the version this release needs
     (`EhosContract.Migrations`): a host that upgrades the package without running its
     new migration is told so at boot, not by the first command. Storage a newer
     release migrated is let through, so a node can restart during a rolling deploy.
     It unwraps one stored data key of each master key, and refuses when one of them
     does not unwrap (`EhosContract.Vault`). Then
     `EhosContract.Deployment.record!/0` writes what that binary declared and since
     when: without it the report could not tell history from drift. After the
     deployment is recorded, it logs a warning, and goes on, when the log holds
     event types no contract declares — a log written before event types became
     `"<contract id>.<event>"`, which the rest of the engine would skip silently —
     and when it files events under a name that is no contract's id, as a log
     written before rows named a contract by its id does. It logs a warning too
     when a contract declares an effect delivered `:at_least_once` or a process
     manager with a timer, and Oban runs no queue `:events`, where their jobs wait;
     under Oban's `testing: :manual` or `:inline`, or with Oban started after the
     engine, it does not check.
  2. It registers every consumer fed from the log, each with a row of its own in
     `ehos_contract_subscriptions`, marks the read models whose declaration changed
     `stale`, and rebuilds those that define `reset/0`.
  3. It starts one runner per subscription: a process that reads the log from where
     its consumer stopped and delivers each event to it. A runner wakes when a
     transaction that appended an event commits, the host's own included. A poll
     checks besides, every `subscription_poll:` milliseconds (30,000 by default), for a
     wake that did not arrive.

  It takes one option, `subscription_poll:`, in the host's list of children:

      children = [MyApp.Repo, {EhosContract, subscription_poll: 10_000}]

  It refuses any other option, and a value that is not a number of milliseconds from 1
  to 4,294,967,295.

  **`config :ehos_contract, subscriptions: :manual`** skips the last two steps:
  nothing is registered and no runner starts. Tests use it, and push the work through
  with `EhosContract.Testing.drain/1` inside their sandbox transaction, where a
  runner could not see their rows.

  If any step raises, the host fails to boot, which is the point: a host running with
  an unscanned registry reports nothing and looks healthy.
  """
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  @doc "Starts the engine's supervisor (`child_spec/1`)."
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__.Supervisor, opts)

  @doc """
  Dispatches `command`, a struct a v2 contract generated, to `contract`.

  `opts`: `actor:` (an `EhosContract.Actor`, required), `idempotency_key:` (opaque,
  never personal data), `correlation_id:` (a UUID; a new one when missing) and
  `causation_id:`. `supply: true`, which `call/3` sets, asks the
  `EhosContract.Supplier` for the fields declared `supplied_by: :host` once the actor
  is authorized; the application's own code leaves it out, and then fills
  those fields itself — its struct is trusted, and checked as every other field is.

      EhosContract.dispatch(Lending.Contracts.Circulation,
        %PayLateFee{loan_id: "loan-1", method: :card},
        actor: actor, idempotency_key: "req-81")

  **In order**, and each step refuses before the next one runs:

  1. **Who.** A credential's actor is asked of the `EhosContract.Authorizer`. A
     `:system` actor has to be one the domain declares `:system` and the command
     names in `by:`; a reaction's, one whose `issues:` names the command. The
     domain's `:seed` actor (`EhosContract.Actor.seed/1`) may issue a command a
     `:human` actor may, in every scope and with no `Authorizer`, unless the domain's
     `not_seeded:` names it or it has `actor_is`. A refusal
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
     (`EhosContract.Key`), is at most `EhosContract.Key.budget/0` bytes, or
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
     personal fields are sealed with their subjects' keys (`EhosContract.Personal`);
     an event carrying personal data of an erased subject is refused,
     `{:error, :subject_erased}`, before anything is sealed, and writes no row: the
     decision was the unit's, the refusal is the erasure's. So is a run's key over
     `EhosContract.Key.budget/0`, the process's id and the run's key, of a run an
     event belongs to: `{:error, :key_too_long}`, with no row, in place of Postgres
     refusing the entry.
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
  8. **After it, by the same commit**: one `EhosContract.EffectJob` per effect
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
  @spec dispatch(module(), struct(), keyword() | map()) ::
          {:ok, EhosContract.Receipt.t()}
          | {:error, EhosContract.Rejection.t() | refusal()}
  defdelegate dispatch(contract, command, opts), to: EhosContract.Dispatcher

  @doc """
  Records `event`, which the contract declares `recorded_by:` — an observation, or
  an integration's answer — without a decision.

  A credential's actor is asked of the `EhosContract.Authorizer` for the event's
  capability, `<domain>.<event>` (`EhosContract.Model.capabilities/1`), as a
  command's is — a person who saw something, a picker reporting a shelf found
  empty. An event only `:system` actors record has no capability, and a
  credential is refused `:missing_capability`. A `:system` actor records it when the
  event's `recorded_by:` names it: an integration writing down what a system
  answered. The domain's `:seed` actor records an event a `:human` actor may record
  and the domain's `not_seeded:` does not name, with no `Authorizer`. Otherwise it goes as a command
  does — the fields checked, the
  idempotency key honoured, the unit's stream version as the append's condition,
  the consumers in the transaction run, the `accepted` row written with the type
  `"record:<event>"` — only without a decider. An event of an aggregate whose
  identity is generated is recorded only for one a command created:
  `{:error, :not_created}` otherwise.
  """
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, EhosContract.Receipt.t()}
          | {:error, refusal() | :not_created}
  defdelegate record(contract, event, opts), to: EhosContract.Dispatcher

  @doc """
  The one way in for what arrives from outside the application's code: a capability's
  name and the data as a caller sent it, with the credential it came with.
  `EhosContract.Plug` is one door onto it; a form, or a job that carries
  a person's credential, is another.

      EhosContract.call(
        {:command, "lending.pay_late_fee"},
        %{"loan_id" => "loan-1", "method" => "card"},
        actor: actor, idempotency_key: "req-81"
      )

  **Whether the caller may is answered first.** Data that is not a map, fields that do
  not decode against the declaration, a correlation id that is not a UUID: each is
  asked of the `EhosContract.Authorizer` as the call would have been, so a caller
  without the capability is refused whatever it sent, and learns nothing about the
  declaration's fields; one with it is told what is wrong. Then it goes through
  `dispatch/3`, `record/3` or `query/3`, so everything they check is checked here
  the same way.

  `input` is a map with string keys, as JSON decodes; a query's values may come as
  text, as a query string carries them. With `form: true`, it is what an HTML form
  sends, read as `EhosContract.Form` reads it: every value as text, at every level, a
  field left blank as absent, and a list as `inputs_for` sends its rows. A page sends
  the params of its form so, with the `data:` it gave `EhosContract.Form.changeset/4`:

      EhosContract.call({:command, "billing.issue_invoice"}, params,
        actor: actor, form: true, data: %{invoice_id: invoice_id}
      )

  `data:` holds the call to what the page decided, as it holds the changeset: the
  identity of the unit it gives replaces a value the params carry for it, and each other
  field it gives is the value when the params leave the field out. Its values are the
  engine's, as `Form` takes them, and are read back as a form's text is: a blank string is
  absent. Unlike `Form`, `call/3` refuses a field the host supplies in `data:`: it is the
  `EhosContract.Supplier`'s.

  `opts`: `actor:`, a credential's
  `EhosContract.Actor`, required — a `:system` actor is the application's own code,
  which dispatches structs; `contracts:`, the contracts this door serves (every
  registered one by default); `form:`, `true` for a form's params, and `data:`, with
  `form: true` only, both set by the page's code, never taken from the caller; for a command or a recording `idempotency_key:` and
  `correlation_id:`, the latter a UUID's text; for a query `min_position:` and `wait:`,
  to read a write, as `query/3` takes them — set by the door's own code, an integer
  each, never taken from the caller: `wait:` bounds how long the call polls.

  `EhosContract.Form.refused/3` puts each answer back on the form's changeset.

  It raises `ArgumentError`, by the field's name, when `data:` is given without
  `form: true`, or holds what `EhosContract.Form.changeset/4` refuses in it, or a field the
  host supplies: the page's mistakes.

  Besides what those three answer: `{:error, :not_found}` for a capability none of
  the contracts declares as that kind, `{:error, :no_actor}` without a credential,
  and, once the caller may, `{:error, :not_an_object}` and
  `{:error, :correlation_id_is_not_a_uuid}`.
  """
  @spec call(call(), term(), keyword() | map()) ::
          {:ok, EhosContract.Receipt.t() | [struct()] | struct() | nil}
          | {:error,
             EhosContract.Rejection.t()
             | refusal()
             | :not_created
             | :not_found
             | :no_actor
             | :not_an_object
             | :correlation_id_is_not_a_uuid}
  defdelegate call(call, input, opts), to: EhosContract.Dispatcher

  @doc """
  Asks a query of a v2 contract, and returns what its implementation answers.
  Nothing is written: a read is not an event.

  A credential's actor is asked of the `EhosContract.Authorizer` for the query's
  capability, and for a scoped query with the value of the scope parameter, so a
  value outside the grant is refused before the implementation runs. A `:system`
  actor the query's `by:` names is the application's own code, and is not narrowed.
  The domain's `:seed` actor is refused every query with `{:error, :not_declared}`.

  **Every row is checked again**: for a credential's actor, a row whose scope field
  is not among the values the credential grants raises
  `EhosContract.Authorizer.OutsideScopeError`, so a wrong `where` cannot hand one
  warehouse another's rows. So do rows that are not the read model's.

  **Read your writes**: `min_position:` — the `position` of a dispatch's
  receipt — waits until the read model the query reads has taken that position,
  polling its subscription row for up to `wait:` milliseconds (5000), and then
  refuses with `{:error, :not_caught_up}` rather than answer from before the write.
  A read model delivered in the transaction has taken every committed event, unless
  it is being rebuilt.
  """
  @spec query(module(), struct(), keyword() | map()) ::
          {:ok, [struct()] | struct() | nil} | {:error, refusal()}
  defdelegate query(contract, params, opts), to: EhosContract.Dispatcher

  @doc """
  Erases `subject` `id` (how, in `EhosContract.Personal`):

      EhosContract.erase(:patient, "p-17", actor: actor)

  It says what it found: `{:ok, :erased}` when it deleted the subject's data key, `{:ok, :no_data}` when no
  key was there for that id — nothing personal was written for it, or its keys went
  some other way; recorded all the same, so none is written later, but perhaps a
  mistyped id, which the host can report — and `{:ok, :already_erased}` when it was
  erased before, and then nothing is appended again. Never `{:error, _}`, so a request
  can be repeated. `opts`: `actor:`, an
  `EhosContract.Actor`, required — who asked, recorded with the erasure and as the
  event's actor. The event starts a correlation of its own: it continues no command.
  Who may erase is the host's to decide: the engine asks no `EhosContract.Authorizer`.

  It reaches the read models of the configured applications,
  `config :ehos_contract, applications:`, as the registry and the subscriptions do:
  a contract dispatched from outside them has read models `erase/3` does not know.
  A read model fed after the transaction that is moved past the erasure by
  `mix ehos_contract.subscriptions --skip` keeps its copy; `--reset` rebuilds it,
  and the replay forgets. A read model fed in the transaction that is `failing` forgets
  at once; if its `forget/2` raises on the rows it has, what it wrote is undone, a
  warning names it, and it keeps its copy. A reset forgets; after a skip, its runner
  calls `forget/2` again when it reaches the erasure. Calling `erase/3` again appends nothing.

  Raises when no domain of the host's contracts declares `subject`.
  """
  @spec erase(atom(), String.t(), keyword() | map()) ::
          {:ok, :erased | :no_data | :already_erased}
  defdelegate erase(subject, id, opts), to: EhosContract.Personal
end
