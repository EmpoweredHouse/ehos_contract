defmodule SupplyRig.Supplier do
  @moduledoc """
  **Invented.** The engine suite's `EhOsContract.Supplier`. It answers what the test
  put under `:supply_rig_answer` — a value, or a function of the actor and the
  request — and otherwise that the report went out and the patient arrived at
  `arrived_at/0`. It keeps what it was asked under `:supply_rig_asked`. Both in the
  calling process, which is the one dispatch runs in.
  """

  @behaviour EhOsContract.Supplier

  @arrived_at ~U[2026-07-01 09:00:00.000000Z]

  @doc "The moment it answers for an arrival."
  @spec arrived_at() :: DateTime.t()
  def arrived_at, do: @arrived_at

  @impl true
  def supply(actor, request) do
    Process.put(:supply_rig_asked, {actor, request})

    case Process.get(:supply_rig_answer, :default) do
      :default -> {:ok, default(request)}
      fun when is_function(fun, 2) -> fun.(actor, request)
      answer -> answer
    end
  end

  defp default(%{name: :close_visit}), do: %{reported: true}
  defp default(%{name: :arrival_noted}), do: %{arrived_at: @arrived_at}
end
