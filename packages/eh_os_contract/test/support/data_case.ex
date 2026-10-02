defmodule EhOsContract.DataCase do
  @moduledoc """
  The sandbox case for the engine's own tests.

  The counterpart of what used to be `Taxvision.DataCase` and is now only the
  client's. The difference is not cosmetic: this one knows nothing about a
  company, a period or an accounting month, so a test using it cannot accidentally
  depend on the client tree being there.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  using do
    quote do
      import Ecto.Query
      import EhOsContract.DataCase

      alias EhOsContract.TestRepo, as: Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EhOsContract.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    EhOsContract.Registry.load!()

    # Deployments are written by the **boot**, that is, outside the sandbox — those
    # rows commit to the test database permanently and would leak into every test
    # that claims anything about deployments. The cleanup runs inside the sandbox
    # transaction, so it rolls back after the test, and production behaviour is
    # untouched: there, writing at boot is exactly right.
    EhOsContract.TestRepo.delete_all(EhOsContract.Deployment)

    :ok
  end

  @doc """
  Sends the calling test `:runners_woken` for every wake of the runners
  (`EhOsContract.Subscription.Runner.notify/0`) sent from its own process, until the
  test exits — or `:runners_woken_in_transaction` for one sent before the transaction
  it announces has committed, which a runner would wake for and find nothing. A wake
  from another process — a runner, another test — is not reported.
  """
  @spec watch_wakes() :: :ok
  def watch_wakes do
    test = self()
    id = "wakes-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        id,
        [:oban, :notifier, :notify, :start],
        &__MODULE__.woken/4,
        test
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  @spec woken(list(), map(), map(), pid()) :: :ok
  def woken(_event, _measurements, metadata, test) do
    cond do
      metadata[:channel] != :eh_os_contract or self() != test -> :ok
      EhOsContract.TestRepo.in_transaction?() -> send(test, :runners_woken_in_transaction)
      true -> send(test, :runners_woken)
    end

    :ok
  end

  @doc """
  Writes one row to the log directly, bypassing dispatch: an event from an
  older contract version, one the contract never declared, or one dated in the past.

  **The one place the suite writes the log itself**, and it writes through
  `EhOsContract.Store` like dispatch does. Until v2 plan stage E2, eleven test files
  each did their own `Repo.insert!(%EhOsContract.Event{})`. The one exception is
  `store_schema_test.exs`, which tests what the table refuses from any writer and so
  inserts around the store on purpose.

  Defaults cover what those files never cared about: `actor` is the system actor
  (the log never holds a nil actor), `payload` is empty and `occurred_at` comes from
  `EhOsContract.Clock`.
  """
  @spec record_event!(map()) :: EhOsContract.Event.t()
  def record_event!(attrs) when is_map(attrs) do
    [event] = append!([Map.merge(defaults(), attrs)])
    event
  end

  @doc """
  `record_event!/1` for many rows at once, for a test about the size of the log
  rather than about how any one row got there. Inserted in chunks, so fifty thousand
  rows stay under Postgres's limit on bind parameters.
  """
  @spec record_events!([map()]) :: :ok
  def record_events!(rows) when is_list(rows) do
    rows
    |> Enum.map(&Map.merge(defaults(), &1))
    |> Enum.chunk_every(2_000)
    |> Enum.each(&append!/1)
  end

  defp append!(entries) do
    {:ok, {:ok, events}} =
      EhOsContract.TestRepo.transaction(fn ->
        EhOsContract.Store.append(EhOsContract.TestRepo, entries, :none)
      end)

    events
  end

  defp defaults do
    %{
      actor: EhOsContract.Event.system_actor(),
      correlation_id: Ecto.UUID.generate(),
      payload: %{},
      occurred_at: EhOsContract.Clock.now()
    }
  end

  @doc "Every event of a type, oldest first."
  def events_of(type) do
    name = to_string(type)

    EhOsContract.TestRepo.all(
      from(e in EhOsContract.Event, where: e.type == ^name, order_by: e.occurred_at)
    )
  end
end
