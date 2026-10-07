defmodule EhOsContract.Erased do
  @moduledoc """
  What a personal field holds once its subject's data key is gone:
  `%EhOsContract.Erased{subject: :patient, id: "p-17"}`, in place of the value.

  An event read back from the log keeps every other field. The log still says that
  subject `p-17` had a visit on 3 September; it no longer says what the visit's
  personal fields held. The structs a contract generates admit `t()` on every
  personal field, so `evolve/2` and every consumer have to tolerate it.
  """

  # Crypto-shredding, v2 §14.

  @enforce_keys [:subject, :id]
  defstruct [:subject, :id]

  @typedoc """
  The subject whose data this was: its type, as the domain declares it, and its id.
  The type is a string only in an erasure of a type no domain declares any more.
  """
  @type t :: %__MODULE__{subject: atom() | String.t(), id: String.t()}
end
