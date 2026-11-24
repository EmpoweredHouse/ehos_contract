defmodule TipRig.Amount do
  @moduledoc "**Invented.** The check of `TipRig.Domain`'s value `:amount`."

  use TipRig.Domain, value: :amount

  @impl true
  def positive(amount), do: amount > 0
end

defmodule TipRig.Tip do
  @moduledoc "**Invented.** The check of `TipRig.Domain`'s value `:tip`."

  use TipRig.Domain, value: :tip

  @impl true
  def positive(tip), do: tip > 0
end
