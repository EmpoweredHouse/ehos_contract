defmodule EhOsContract.Rejection do
  @moduledoc """
  A command refused on an invariant: what a decision returns instead of events (v2
  §5), `{:error, %EhOsContract.Rejection{invariant: :payment_lines_sum_to_total}}`.

  It names the invariant and nothing else. A rejection travels to logs, telemetry
  and callers, so it carries no field values: those may be personal data (v2 §17).
  """

  @enforce_keys [:invariant]
  defstruct [:invariant]

  @typedoc "The invariant a command was refused on."
  @type t :: %__MODULE__{invariant: atom()}
end
