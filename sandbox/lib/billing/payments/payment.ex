defmodule Billing.Payments.Payment do
  @moduledoc """
  **Invented.** Decides a payment: asked for once, and written off only while it is
  still owed.
  """

  use Billing.Contracts.Payments, aggregate: :payment

  @impl true
  def request_payment(_command, %State{requested: true}), do: reject(:requested_once)

  def request_payment(%RequestPayment{} = command, _state) do
    emit(%Requested{
      subscription_id: command.subscription_id,
      period_id: command.period_id,
      amount: command.amount
    })
  end

  @impl true
  def write_off_payment(%WriteOffPayment{} = command, %State{requested: true, settled: false}),
    do:
      emit(%WrittenOff{
        subscription_id: command.subscription_id,
        period_id: command.period_id
      })

  def write_off_payment(_command, _state), do: reject(:only_an_unpaid_payment_is_written_off)

  @impl true
  def evolve(state, %Requested{}), do: %{state | requested: true}
  def evolve(state, %Collected{}), do: %{state | settled: true}
  def evolve(state, %WrittenOff{}), do: %{state | settled: true}
end
