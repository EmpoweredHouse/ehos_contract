defmodule EhOsContract.ProcessManagerRecord do
  # A row of `eh_os_contract_process_managers`: one run of one process manager
  # (`EhOsContract.ProcessManager`, v2 §10.3).
  #
  # `name` is the process manager's key, `"<contract id>:process_manager:<name>"`, and
  # `correlation` the run's correlation values joined by `EhOsContract.Key`. `state`
  # is its state struct in the external term format; `timers` maps each pending
  # timer's name to `%{"token", "at", "correlation_id"}`, where the token is the id
  # of the event that set it; `position` is the last event it took; `completed_at`
  # is when an `ends_on` event ended it.
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "eh_os_contract_process_managers" do
    field(:name, :string, primary_key: true)
    field(:correlation, :string, primary_key: true)
    field(:state, :binary)
    field(:timers, :map, default: %{})
    field(:position, :integer)
    field(:completed_at, :utc_datetime_usec)
  end
end
