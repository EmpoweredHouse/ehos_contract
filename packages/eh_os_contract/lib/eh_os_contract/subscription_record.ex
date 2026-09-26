defmodule EhOsContract.SubscriptionRecord do
  @moduledoc """
  A row of `eh_os_contract_subscriptions`: how far one consumer has read the log
  (`EhOsContract.Subscription`, v2 §10.3).

  `status` is `running`, `stale` (its declaration changed and it has not been
  rebuilt), `rebuilding`, or `failing` at `failed_position`, whose exception's
  module is `failure`. `mode` is `ordered` for a consumer a runner feeds and
  `inline` for a read model dispatch projects.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:name, :string, autogenerate: false}
  schema "eh_os_contract_subscriptions" do
    field(:kind, :string)
    field(:mode, :string)
    field(:position, :integer, default: 0)
    field(:version, :string)
    field(:status, :string, default: "running")
    field(:failed_position, :integer)
    field(:failure, :string)
    field(:attempts, :integer, default: 0)
    field(:updated_at, :utc_datetime_usec)
  end

  @doc "A change to a row, stamped with the time it is made."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, changes) do
    row
    |> cast(changes, [:position, :version, :status, :failed_position, :failure, :attempts])
    |> put_change(:updated_at, DateTime.utc_now())
  end
end
