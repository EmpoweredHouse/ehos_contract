defmodule EhosContract.Supervisor do
  @moduledoc false

  # The `EhosContract` child (its `child_spec/1` says what it does at boot).

  use Supervisor

  alias EhosContract.{Implementations, Model, Subscription}

  require Logger

  @impl Supervisor
  @spec init(term()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(opts) do
    poll = subscription_poll!(opts)
    EhosContract.Config.validate!()
    EhosContract.Registry.load!()
    models = Enum.map(EhosContract.Registry.contracts(), &Model.fetch/1)
    EhosContract.Vault.check!(models)
    EhosContract.Supplier.check!(models)
    EhosContract.Entities.check!(models)
    repo = EhosContract.Config.fetch!(:repo)
    EhosContract.Migrations.check!(repo)
    EhosContract.Personal.check_master_keys!(repo, models)
    EhosContract.Personal.check_forgetting!(Implementations.index(nil).consumers)
    EhosContract.Deployment.record!()
    EhosContract.UndeclaredTypes.warn(repo, models)
    # Every contract dispatch reaches, `exclude:` or not, and the siblings they consume.
    known = Map.values(Implementations.index(nil).contracts)
    EhosContract.UndeclaredTypes.warn_contracts(repo, known)

    warn_events_queue(
      waiting_jobs(Implementations.index(nil)),
      Oban.whereis(Oban) && Oban.config(Oban)
    )

    runners =
      case EhosContract.Config.get(:subscriptions) do
        :manual -> []
        _run -> subscribe!(EhosContract.Config.fetch!(:repo), poll)
      end

    Supervisor.init(runners, strategy: :one_for_one)
  end

  # The pause of the runners' poll, the safety net under the notifications a commit
  # sends: 30 seconds unless the host's child spec says otherwise (#635).
  defp subscription_poll!(opts) do
    case Keyword.validate!(List.wrap(opts), subscription_poll: 30_000) do
      # The longest timer the runtime sets, about 49 days.
      [subscription_poll: ms] when is_integer(ms) and ms > 0 and ms <= 4_294_967_295 ->
        ms

      [subscription_poll: other] ->
        raise ArgumentError,
              "EhosContract's subscription_poll: is a number of milliseconds from 1 to " <>
                "4294967295, got: #{inspect(other)}"
    end
  end

  # The effects delivered :at_least_once and the timers of process managers are Oban
  # jobs in the queue :events, which a host's Oban may not run: then they wait in the
  # table, and nothing says so (#671). A warning, not a refusal: the application
  # still serves its commands, and another node may run the queue. Read from the
  # index of the configured applications, which `exclude:` does not narrow, so a
  # contract it leaves out and dispatch still reaches counts too.
  defp waiting_jobs(index) do
    timers? =
      Enum.any?(index.consumers, fn consumer ->
        consumer.kind == :process_manager and
          Enum.any?(
            Model.fetch(consumer.contract).process_managers,
            &(&1.name == consumer.name and &1.timers != [])
          )
      end)

    for {true, job} <- [
          {index.effects != %{}, EhosContract.EffectJob},
          {timers?, EhosContract.TimerJob}
        ],
        do: job
  end

  # Nothing waits in the queue.
  defp warn_events_queue([], _oban), do: :ok
  # Oban not started before the engine: this node cannot tell.
  defp warn_events_queue(_waiting, nil), do: :ok

  defp warn_events_queue(waiting, %{testing: :disabled, queues: queues}) do
    unless Keyword.has_key?(queues, :events) do
      Logger.warning(
        "Oban runs no queue :events (its queues: #{inspect(Keyword.keys(queues))}), so " <>
          "the jobs of #{Enum.map_join(waiting, " and ", &inspect/1)} wait in its table " <>
          "until a node runs the queue: add it where the host configures Oban, " <>
          "queues: [events: 10]"
      )
    end
  end

  # Oban's testing modes run no queue by design, and `EhosContract.Testing.drain/1`
  # runs :events.
  defp warn_events_queue(_waiting, %{testing: _manual_or_inline}), do: :ok

  defp subscribe!(repo, poll) do
    consumers = Implementations.subscribed()
    inboxes = Implementations.inboxes()
    bus? = EhosContract.Bus.adapter() != nil

    unless bus? do
      for %{kind: :relay, key: key} <- consumers do
        Logger.warning(
          "subscription #{key}: no bus is configured (config :ehos_contract, bus:), so " <>
            "its relay publishes nothing and waits at its position"
        )
      end

      for %{key: key} <- inboxes do
        Logger.warning(
          "inbox #{key}: no bus is configured (config :ehos_contract, bus:), so nothing " <>
            "it subscribes to arrives"
        )
      end
    end

    for %{status: "stale", name: key} <- Subscription.register!(repo, consumers) do
      case Subscription.rebuild(repo, key) do
        :ok ->
          Logger.info("subscription #{key}: its declaration changed, so it is rebuilt")

        {:error, :no_reset} ->
          Logger.warning(
            "subscription #{key}: its declaration changed and it defines no reset/0, so it " <>
              "stays stale until it is rebuilt by hand"
          )
      end
    end

    # Every inbox before every runner, so before every relay (plan, E12c): a keeper
    # starts its consumer in its own init, and a consumer is subscribed once started,
    # so in one node nothing a relay publishes is published before the inbox that
    # takes it listens.
    keepers = if bus?, do: Enum.map(inboxes, &{EhosContract.Inbox.Keeper, &1}), else: []

    keepers ++ runners(repo, consumers, poll)
  end

  # Whether the log's trigger wakes this node's runners at commit, so the engine need
  # not send a wake of its own after its commits (#648). The schema is the log table's
  # own, which the trigger names, not the first of the search path. A node that cannot
  # tell — Oban not started yet, say — keeps its own wake.
  defp trigger_reaches?(repo) do
    %{rows: [[schema]]} =
      repo.query!(
        "SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace " <>
          "WHERE c.oid = 'ehos_contract_events'::regclass",
        [],
        log: false
      )

    Subscription.Wake.reaches?(Map.from_struct(Oban.config(Oban)), repo, schema)
  rescue
    _not_known -> false
  end

  # The runners under a supervisor of their own, which the node's poll reads to find the
  # runner of each row; neither is started for a host with no subscription.
  defp runners(_repo, [], _poll), do: []

  defp runners(repo, consumers, poll) do
    children = Enum.map(consumers, &{Subscription.Runner, &1.key})
    name = Subscription.Head.runners()

    [
      {Subscription.Wake, trigger: trigger_reaches?(repo)},
      %{
        id: name,
        start: {Supervisor, :start_link, [children, [strategy: :one_for_one, name: name]]},
        type: :supervisor
      },
      {Subscription.Head, repo: repo, runners: name, poll: poll}
    ]
  end
end
