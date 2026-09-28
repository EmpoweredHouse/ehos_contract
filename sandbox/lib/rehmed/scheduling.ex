defmodule Rehmed.Scheduling do
  @moduledoc """
  The implementation of `Rehmed.Contracts.Scheduling` (`CTX-01`): the visit's
  decision, pure, as `Rehmed.Settlement` is for settlement. It exists so that the
  contract's scenarios run.
  """

  use Boundary, deps: [EhOsContract, Rehmed.Contracts], exports: [Visit]
end
