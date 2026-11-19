defmodule EhOsContract.Supervisor do
  @moduledoc false

  # The `EhOsContract` child (its `child_spec/1` says what it does at boot).

  use Supervisor

  alias EhOsContract.{Implementations, Model, Subscription}

  require Logger

  @impl Supervisor
  @spec init(term()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_opts) do
    EhOsContract.Config.validate!()
    EhOsContract.Registry.load!()
    models = Enum.map(EhOsContract.Registry.contracts(), &Model.fetch/1)
    EhOsContract.Vault.check!(models)
    EhOsContract.Supplier.check!(models)
    EhOsContract.Entities.check!(models)
    repo = EhOsContract.Config.fetch!(:repo)
    EhOsContract.Migrations.check!(repo)
    EhOsContract.Personal.check_master_keys!(repo, models)
    EhOsContract.Personal.check_forgetting!(Implementations.index(nil).consumers)
    EhOsContract.Deployment.record!()
    EhOsContract.UndeclaredTypes.warn(repo, models)
    # Every contract dispatch reaches, `exclude:` or not, and the siblings they consume.
    known = Map.values(Implementations.index(nil).contracts)
    EhOsContract.UndeclaredTypes.warn_contracts(repo, known)

    runners =
      case EhOsContract.Config.get(:subscriptions) do
        :manual -> []
        _run -> subscribe!(EhOsContract.Config.fetch!(:repo))
      end

    Supervisor.init(runners, strategy: :one_for_one)
  end

  defp subscribe!(repo) do
    consumers = Implementations.subscribed()
    inboxes = Implementations.inboxes()
    bus? = EhOsContract.Bus.adapter() != nil

    unless bus? do
      for %{kind: :relay, key: key} <- consumers do
        Logger.warning(
          "subscription #{key}: no bus is configured (config :eh_os_contract, bus:), so " <>
            "its relay publishes nothing and waits at its position"
        )
      end

      for %{key: key} <- inboxes do
        Logger.warning(
          "inbox #{key}: no bus is configured (config :eh_os_contract, bus:), so nothing " <>
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
    keepers = if bus?, do: Enum.map(inboxes, &{EhOsContract.Inbox.Keeper, &1}), else: []

    # The registry before the runners, which join it in their init; the node's poll
    # after them, so its first poll finds them there.
    keepers ++
      [{Registry, keys: :unique, name: Subscription.Head.registry()}] ++
      Enum.map(consumers, &{Subscription.Runner, &1.key}) ++
      [{Subscription.Head, repo: repo}]
  end
end
