defmodule UpcastRig do
  @moduledoc """
  **An engine fixture, and invented.** Demands whose event changed its fields twice
  while the log kept its rows (plan DD, V1, #333): a reason renamed and renamed again, a
  priority added, and a personal note renamed. No workshop stands behind it, and no
  name in it comes from one.
  """

  use Boundary, deps: [EhosContract], exports: [Domain, Demands]
end
