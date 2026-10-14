defmodule GraphLab.Till.TillDay do
  @moduledoc """
  Decides the till's day in the test set (`GraphLab`): it closes only once the cash is
  counted, with the last count. A day already closed is refused by the lifecycle before
  this decision runs.
  """

  use GraphLab.Contracts.Till, aggregate: :till_day

  @impl true
  def open_till_day(%OpenTillDay{day_id: id}, _state), do: emit(%DayOpened{day_id: id})

  @impl true
  def count_cash(%CountCash{day_id: id, counted: counted}, _state),
    do: emit(%CashCounted{day_id: id, counted: counted})

  @impl true
  def close_till_day(_command, %State{counted: nil}), do: reject(:cash_counted_before_close)

  def close_till_day(%CloseTillDay{day_id: id}, %State{counted: counted}),
    do: emit(%DayClosed{day_id: id, counted: counted})

  @impl true
  def evolve(state, %CashCounted{counted: counted}), do: %{state | counted: counted}
  def evolve(state, _event), do: state
end
