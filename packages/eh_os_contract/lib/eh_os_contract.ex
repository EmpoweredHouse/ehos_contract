defmodule EhOsContract do
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
      Entities,
      Entities.UnfitRowError,
      Erased,
      Event,
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
  # `Application.spec(:eh_os_contract, :vsn)`, which returns a charlist and needs the
  # application loaded — neither of which a report renderer should have to care
  # about. This is the package reading its own project file, so it carries no
  # host configuration into a compile-time attribute.
  @version Mix.Project.config()[:version]

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
        EhOsContract,
        MyAppWeb.Endpoint
      ]

  The child is a supervisor. While it starts it does, in this order:

  0. `EhOsContract.Config.validate!/0` refuses to go on when `config :eh_os_contract`
     has an unknown key, a value of the wrong shape or a required key missing.
  1. It scans the running binary for contracts and domains, refusing to go on when
     a domain's `time_zone:` is one the time zone database this node runs with does
     not know. It refuses as well when a v2 contract declares personal fields and the
     vault has no master key to seal them with, when a field is declared
     `supplied_by: :host` and no supplier is configured, when a command `reads:` an
     entity and no `EhOsContract.Entities` is configured, when a read model
     projects personal data and defines no `forget/2`, and when the database's
     storage is missing or older than the version this release needs
     (`EhOsContract.Migrations`): a host that upgrades the package without running its
     new migration is told so at boot, not by the first command. Storage a newer
     release migrated is let through, so a node can restart during a rolling deploy.
     Then
     `EhOsContract.Deployment.record!/0` writes what that binary declared and since
     when: without it the report could not tell history from drift. After the
     deployment is recorded, it logs a warning, and goes on, when the log holds
     event types no contract declares — a log written before event types became
     `"<contract id>.<event>"`, which the rest of the engine would skip silently —
     and when it files events under a name that is no contract's id, as a log
     written before rows named a contract by its id does.
  2. It registers every consumer fed from the log, each with a row of its own in
     `eh_os_contract_subscriptions`, marks the read models whose declaration changed
     `stale`, and rebuilds those that define `reset/0`.
  3. It starts one runner per subscription: a process that reads the log from where
     its consumer stopped and delivers each event to it.

  **`config :eh_os_contract, subscriptions: :manual`** skips the last two steps:
  nothing is registered and no runner starts. Tests use it, and push the work through
  with `EhOsContract.Testing.drain/1` inside their sandbox transaction, where a
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
  def start_link(_opts \\ []), do: Supervisor.start_link(__MODULE__.Supervisor, [])

  @doc """
  Dispatches `command`, a struct a v2 contract generated, to `contract`.

  `opts`: `actor:` (an `EhOsContract.Actor`, required), `idempotency_key:` (opaque,
  never personal data), `correlation_id:` (a UUID; a new one when missing) and
  `causation_id:`. `supply: true`, which `call/3` sets, asks the
  `EhOsContract.Supplier` for the fields declared `supplied_by: :host` once the actor
  is authorized; the application's own code leaves it out, and then fills
  those fields itself — its struct is trusted, and checked as every other field is.
  """
  @spec dispatch(module(), struct(), keyword() | map()) ::
          {:ok, EhOsContract.Receipt.t()}
          | {:error, EhOsContract.Rejection.t() | EhOsContract.Dispatcher.refusal()}
  defdelegate dispatch(contract, command, opts), to: EhOsContract.Dispatcher

  @doc """
  Records `event`, which the contract declares `recorded_by:` — an observation, or
  an integration's answer — without a decision.

  A credential's actor is asked of the `EhOsContract.Authorizer` for the event's
  capability, `<domain>.<event>` (`EhOsContract.Model.capabilities/1`), as a
  command's is — a person who saw something, a picker reporting a shelf found
  empty. An event only `:system` actors record has no capability, and a
  credential is refused `:missing_capability`. A `:system` actor records it when the
  event's `recorded_by:` names it: an integration writing down what a system
  answered. Otherwise it goes as a command
  does — the fields checked, the
  idempotency key honoured, the unit's stream version as the append's condition,
  the consumers in the transaction run, the `accepted` row written with the type
  `"record:<event>"` — only without a decider. An event of an aggregate whose
  identity is generated is recorded only for one a command created:
  `{:error, :not_created}` otherwise.
  """
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, EhOsContract.Receipt.t()}
          | {:error, EhOsContract.Dispatcher.refusal() | :not_created}
  defdelegate record(contract, event, opts), to: EhOsContract.Dispatcher

  @doc """
  The one way in for what arrives from outside the application's code: a capability's
  name and the data as a caller sent it, with the credential it came with.
  `EhOsContract.Plug` is one door onto it; a form, or a job that carries
  a person's credential, is another.

      EhOsContract.call(
        {:command, "lending.pay_late_fee"},
        %{"loan_id" => "loan-1", "method" => "card"},
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
  to read a write, as `query/3` takes them — set by the door's own code, an integer
  each, never taken from the caller: `wait:` bounds how long the call polls.

  Besides what those three answer: `{:error, :not_found}` for a capability none of
  the contracts declares as that kind, `{:error, :no_actor}` without a credential,
  and, once the caller may, `{:error, :not_an_object}` and
  `{:error, :correlation_id_is_not_a_uuid}`.
  """
  @spec call(EhOsContract.Dispatcher.call(), term(), keyword() | map()) ::
          {:ok, EhOsContract.Receipt.t() | [struct()] | struct() | nil}
          | {:error,
             EhOsContract.Rejection.t()
             | EhOsContract.Dispatcher.refusal()
             | :not_created
             | :not_found
             | :no_actor
             | :not_an_object
             | :correlation_id_is_not_a_uuid}
  defdelegate call(call, input, opts), to: EhOsContract.Dispatcher

  @doc """
  Asks a query of a v2 contract, and returns what its implementation answers.
  Nothing is written: a read is not a fact.

  A credential's actor is asked of the `EhOsContract.Authorizer` for the query's
  capability, and for a scoped query with the value of the scope parameter, so a
  value outside the grant is refused before the implementation runs. A `:system`
  actor the query's `by:` names is the application's own code, and is not narrowed.

  **Every row is checked again**: for a credential's actor, a row whose scope field
  is not among the values the credential grants raises
  `EhOsContract.Authorizer.OutsideScopeError`, so a wrong `where` cannot hand one
  warehouse another's rows. So do rows that are not the read model's.

  **Read your writes**: `min_position:` — the `position` of a dispatch's
  receipt — waits until the read model the query reads has taken that position,
  polling its subscription row for up to `wait:` milliseconds (5000), and then
  refuses with `{:error, :not_caught_up}` rather than answer from before the write.
  A read model delivered in the transaction has taken every committed event, unless
  it is being rebuilt.
  """
  @spec query(module(), struct(), keyword() | map()) ::
          {:ok, [struct()] | struct() | nil} | {:error, EhOsContract.Dispatcher.refusal()}
  defdelegate query(contract, params, opts), to: EhOsContract.Dispatcher

  @doc """
  Erases `subject` `id` (how, in `EhOsContract.Personal`):

      EhOsContract.erase(:patient, "p-17", actor: actor)

  It says what it found: `{:ok, :erased}` when it deleted the subject's data key, `{:ok, :no_data}` when no
  key was there for that id — nothing personal was written for it, or its keys went
  some other way; recorded all the same, so none is written later, but perhaps a
  mistyped id, which the host can report — and `{:ok, :already_erased}` when it was
  erased before, and then nothing is appended again. Never `{:error, _}`, so a request
  can be repeated. `opts`: `actor:`, an
  `EhOsContract.Actor`, required — who asked, recorded with the erasure and as the
  event's actor. The event starts a correlation of its own: it continues no command.
  Who may erase is the host's to decide: the engine asks no `EhOsContract.Authorizer`.

  It reaches the read models of the configured applications,
  `config :eh_os_contract, applications:`, as the registry and the subscriptions do:
  a contract dispatched from outside them has read models `erase/3` does not know.
  A read model fed after the transaction that is moved past the erasure by
  `mix eh_os_contract.subscriptions --skip` keeps its copy; `--reset` rebuilds it,
  and the replay forgets. Calling `erase/3` again appends nothing.

  Raises when no domain of the host's contracts declares `subject`.
  """
  @spec erase(atom(), String.t(), keyword() | map()) ::
          {:ok, :erased | :no_data | :already_erased}
  defdelegate erase(subject, id, opts), to: EhOsContract.Personal
end
