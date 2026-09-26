defmodule ProcessShapes do
  @moduledoc """
  **A test rig, not a domain.** See `ProcessShapes.Rig`.

  Its own boundary rather than hanging off `Taxvision`: process shapes are meant
  to be checked **without** access to anything belonging to the client, otherwise
  the proof would be worth as much as one carried out inside the first domain.

  The repo comes **from configuration**, not from a reference to a client module —
  exactly as in `EhOsContract.Emitter`. The first version named `Taxvision.Repo` directly
  and `boundary` rejected it, rightly: an engine fixture has no business reaching
  into the client tree, not even for the repo.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      Rig,
      Bare,
      Promised,
      Intake,
      Matching,
      Resolution,
      Domain,
      Next.Promised,
      Next.Timed
    ]
end
