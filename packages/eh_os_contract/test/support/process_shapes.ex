defmodule ProcessShapes do
  @moduledoc """
  **A test rig, not a domain.** The names are deliberately colourless — a request,
  a run, a batch — because if they sounded like accounting or like medicine,
  somebody would read them as knowledge about a domain. There is not a single claim
  about anybody's process here.

  Its own boundary rather than hanging off `Taxvision`: process shapes are meant
  to be checked **without** access to anything belonging to the client, otherwise
  the proof would be worth as much as one carried out inside the first domain.

  The repo comes **from configuration**, not from a reference to a client module —
  exactly as the engine reads it. The first version named `Taxvision.Repo` directly
  and `boundary` rejected it, rightly: an engine fixture has no business reaching
  into the client tree, not even for the repo.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      Domain,
      Next.Promised,
      Next.Timed,
      Next.Bare
    ]
end
