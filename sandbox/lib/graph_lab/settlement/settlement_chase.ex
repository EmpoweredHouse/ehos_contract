defmodule GraphLab.Settlement.SettlementChase do
  @moduledoc """
  Flags a visit as unsettled at the end of reception's day, 20:00 at the clinic, unless
  reception took a payment or closed it first, in the test set (`GraphLab`). A visit that
  ends after 20:00 is due the next evening.
  """

  use GraphLab.Contracts.Settlement, process_manager: :settlement_chase

  @zone "Europe/Warsaw"
  @closing ~T[20:00:00]

  @impl true
  def settlement_due(%State{visit_id: id}), do: issue(%FlagUnsettledVisit{visit_id: id})

  @impl true
  def evolve(state, %VisitCompleted{__meta__: meta}),
    do: %{state | due_at: end_of_day(meta.occurred_at)}

  def evolve(state, _event), do: state

  defp end_of_day(at) do
    local = DateTime.shift_zone!(at, @zone)
    today = DateTime.new!(DateTime.to_date(local), @closing, @zone)

    closing =
      if DateTime.compare(local, today) == :lt,
        do: today,
        else: DateTime.new!(Date.add(DateTime.to_date(local), 1), @closing, @zone)

    DateTime.shift_zone!(closing, "Etc/UTC")
  end
end
