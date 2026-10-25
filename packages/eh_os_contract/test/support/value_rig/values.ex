defmodule ValueRig.Amount do
  @moduledoc """
  **Invented.** The check of `ValueRig.Domain`'s value `:amount`. A test can make the
  next check answer something other than a boolean,
  `Process.put(:value_rig_amount_answers, :maybe)`, to watch dispatch refuse to guess.
  """

  use ValueRig.Domain, value: :amount

  @impl true
  def positive(amount) do
    case Process.delete(:value_rig_amount_answers) do
      nil -> amount > 0
      answer -> answer
    end
  end
end

defmodule ValueRig.Fee do
  @moduledoc "**Invented.** The check of `ValueRig.Domain`'s value `:fee`."

  use ValueRig.Domain, value: :fee

  @impl true
  def capped(fee), do: fee <= 1000
end

defmodule ValueRig.Shift do
  @moduledoc "**Invented.** The check of `ValueRig.Domain`'s value `:shift`."

  use ValueRig.Domain, value: :shift

  @impl true
  def named_by_day(shift), do: match?({:ok, _}, Date.from_iso8601(shift))
end

defmodule ValueRig.Window do
  @moduledoc "**Invented.** The check of `ValueRig.Domain`'s value `:window`."

  use ValueRig.Domain, value: :window

  @impl true
  def in_order(%{from: from, to: to}), do: Date.compare(from, to) != :gt
end
