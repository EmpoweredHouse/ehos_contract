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
  Writes one row to the log directly, bypassing `EhOsContract.emit/4`: an event from an
  older contract version, one the contract never declared, or one dated in the past.

  **The one place the suite writes the log itself.** Until v2 plan stage E2, ten test
  files each did their own `Repo.insert!(%EhOsContract.Event{})`. The log is becoming a
  store with an append path of its own, and one writer here follows it in one edit.

  Defaults cover what those files never cared about: `actor` is the system actor
  (the log never holds a nil actor), `payload` is empty and `occurred_at` comes from
  `EhOsContract.Clock`.
  """
  @spec record_event!(map()) :: EhOsContract.Event.t()
  def record_event!(attrs) when is_map(attrs) do
    defaults = %{
      actor: EhOsContract.Event.system_actor(),
      correlation_id: Ecto.UUID.generate(),
      payload: %{},
      occurred_at: EhOsContract.Clock.now()
    }

    EhOsContract.TestRepo.insert!(struct!(EhOsContract.Event, Map.merge(defaults, attrs)))
  end

  @doc "Every event of a type, oldest first."
  def events_of(type) do
    name = to_string(type)

    EhOsContract.TestRepo.all(
      from(e in EhOsContract.Event, where: e.type == ^name, order_by: e.occurred_at)
    )
  end
end
