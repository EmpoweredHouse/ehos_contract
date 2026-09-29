defmodule EhOsContract.Supervisor do
  @moduledoc false

  # The `EhOsContract` child (its `child_spec/1` says what it does at boot).

  use Supervisor

  alias EhOsContract.{Implementations, Model, Subscription}

  require Logger

  @impl Supervisor
  @spec init(term()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_opts) do
    EhOsContract.Registry.load!()
    EhOsContract.Vault.check!(Enum.map(EhOsContract.Registry.contracts(), &Model.fetch/1))
    EhOsContract.Personal.check_forgetting!(Implementations.index(nil).consumers)
    EhOsContract.Deployment.record!()

    runners =
      case Application.get_env(:eh_os_contract, :subscriptions) do
        :manual -> []
        _run -> subscribe!(Application.fetch_env!(:eh_os_contract, :repo))
      end

    Supervisor.init(runners, strategy: :one_for_one)
  end

  defp subscribe!(repo) do
    consumers = Implementations.subscribed()

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

    Enum.map(consumers, &{Subscription.Runner, &1.key})
  end
end
