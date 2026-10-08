defmodule EhOsContract do
  @moduledoc """
  The package's public surface.

  What would be the `eh_os_contract` hex package — kept in `lib/eh_os_contract/` beside the client
  application in `lib/taxvision/`, with the boundary enforced by `boundary` from
  the first commit. The structure is the one notes §15 foresee for the first
  client, so moving it out beside the client's repository is a `git mv`.
  """

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
      Domain,
      {Domain.Dsl, []},
      Duration,
      Erased,
      Event,
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
      Registry,
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
  1. `EhOsContract.Registry.load!/1` scans the running binary for contracts and
     domains, refusing to go on when a domain's `time_zone:` is one the time zone
     database this node runs with does not know, and `EhOsContract.Deployment.record!/1` writes what that binary
     declared and since when. Forgetting the first leaves an empty graph;
     forgetting the second leaves the report unable to tell history from drift.
     Between the two, `EhOsContract.Vault.check!/1` refuses to go on when a v2
     contract declares personal fields and the vault has no master key to seal
     them with, and `EhOsContract.Personal.check_forgetting!/1` when a read model
     projects personal data and defines no `forget/2`. After the deployment is
     recorded, `EhOsContract.UndeclaredTypes.warn/2` logs a warning, and goes on, when the log
     holds event types no contract declares — a log written before event types became
     `"<contract id>.<event>"`, which the rest of the engine would skip silently — and
     `warn_contracts/2` when it files events under a name that is no contract's id, as a
     log written before rows named a contract by its id does (#179).
  2. `EhOsContract.Subscription.register!/2` writes a row for every consumer fed from
     the log, marks the read models whose declaration changed `stale`, and rebuilds
     those that define `reset/0` (v2 §12).
  3. It starts one `EhOsContract.Subscription.Runner` per subscription.

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
  Dispatches a command to a contract: authorizes its actor, decides, appends
  (`EhOsContract.Dispatcher`).
  """
  @spec dispatch(module(), struct(), keyword() | map()) ::
          {:ok, EhOsContract.Receipt.t()}
          | {:error, EhOsContract.Rejection.t() | EhOsContract.Dispatcher.refusal()}
  defdelegate dispatch(contract, command, opts), to: EhOsContract.Dispatcher

  @doc "Records an event a contract declares `recorded_by:` (`EhOsContract.Dispatcher.record/3`)."
  @spec record(module(), struct(), keyword() | map()) ::
          {:ok, EhOsContract.Receipt.t()}
          | {:error, EhOsContract.Dispatcher.refusal() | :not_created}
  defdelegate record(contract, event, opts), to: EhOsContract.Dispatcher

  @doc """
  Takes a command, a recording or a query by its capability's name, with the data as a
  caller sent it and the credential it came with: the one way in for a door onto the
  application, which asks whether the caller may before it says what is wrong with
  what was sent (`EhOsContract.Dispatcher.call/3`).
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

  @doc "Asks a query of a contract (`EhOsContract.Dispatcher.query/3`)."
  @spec query(module(), struct(), keyword() | map()) ::
          {:ok, [struct()] | struct() | nil} | {:error, EhOsContract.Dispatcher.refusal()}
  defdelegate query(contract, params, opts), to: EhOsContract.Dispatcher

  @doc """
  Erases a subject's personal data from the log, and from every read model that
  projects it (`EhOsContract.Personal.erase/3`, v2 §14):

      EhOsContract.erase(:patient, "p-17", actor: actor)

  `{:ok, :erased}`, `{:ok, :no_data}` when no data key was there for that id (a
  mistyped one?), or `{:ok, :already_erased}`; never `{:error, _}`, though it raises
  on a subject no domain declares. Who may erase is the host's to
  decide.
  """
  @spec erase(atom(), String.t(), keyword() | map()) ::
          {:ok, :erased | :no_data | :already_erased}
  defdelegate erase(subject, id, opts), to: EhOsContract.Personal
end
