defmodule ValueRig.TillDecider do
  @moduledoc """
  **Invented.** The decider of `ValueRig.Till`'s till: it pays in what it is given,
  and `short_change/2` decides an amount of nothing, which the value `:amount` does
  not allow.
  """

  use ValueRig.Till, aggregate: :till

  @impl true
  def pay_in(%PayIn{} = c, _state),
    do:
      emit(%PaidIn{
        till_id: c.till_id,
        amount: c.amount,
        fees: c.fees,
        window: c.window,
        payment: c.payment
      })

  @impl true
  def short_change(%ShortChange{till_id: id}, _state), do: emit(%PaidIn{till_id: id, amount: 0})
end

defmodule ValueRig.Payments do
  @moduledoc """
  **Invented.** A read model that keeps nothing: the query over it is here for its
  parameters, which dispatch holds to their values' invariants.
  """

  use ValueRig.Till, read_model: :payments

  @impl true
  def paid_in(_event), do: :ok

  @impl true
  def counted(_event), do: :ok
end

defmodule ValueRig.PaymentsAbove do
  @moduledoc "**Invented.** Answers nothing: nothing is kept."

  use ValueRig.Till, query: :payments_above

  @impl true
  def payments_above(%PaymentsAbove{}, _ctx), do: []
end

defmodule ValueRig.Splitting do
  @moduledoc """
  **Invented.** The implementation of `ValueRig.Till`'s domain service `:splitting`.
  One grosz halves into nothing, which it answers as `nil`, since an amount of
  nothing is no amount. A test can make the next call answer 0,
  `Process.put(:value_rig_half_of_nothing, true)`, which breaks the invariant of the
  value it returns.
  """

  use ValueRig.Till, domain_service: :splitting

  @impl true
  def half(amount) do
    cond do
      Process.delete(:value_rig_half_of_nothing) -> 0
      div(amount, 2) == 0 -> nil
      true -> div(amount, 2)
    end
  end
end
