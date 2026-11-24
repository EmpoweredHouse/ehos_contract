defmodule EhosContract.Rejection do
  @moduledoc """
  A command refused on an invariant: what a decision returns instead of events,
  `{:error, %EhosContract.Rejection{invariant: :payment_lines_sum_to_total}}`.
  A command may also be refused on one of its constraints, and `invariant` then
  names the constraint: both are what the command `rejects:`.

  It names the rule and nothing else. A rejection travels to logs, telemetry
  and callers, so it carries no field values: those may be personal data.
  """

  # The rejection of v2 §5, without values for v2 §17; constraints since plan EL2.

  @enforce_keys [:invariant]
  defstruct [:invariant]

  @typedoc "The invariant, or the command's constraint, a command was refused on."
  @type t :: %__MODULE__{invariant: atom()}
end
