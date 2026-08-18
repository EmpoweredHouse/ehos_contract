defmodule Rehmed do
  @moduledoc """
  The second client case, and the first one the engine did not grow up with.

  `lib/taxvision/` is here as a full application — schemas, handlers, a repo. This
  tree is deliberately **only contracts**. Rehmed has no code in this repository
  and may never have any; what it has is a modelled process, and the question this
  tree answers is whether the DSL can carry it.

  That makes it a different kind of evidence from `UniversalityGate`, which is an
  invented domain written by the author to prove the vocabulary needs no new words.
  This one is client material: every event name traces to a workshop, a board lane
  or a transcript, through
  [`docs/rehmed-2026-08-18-distillation.md`](../docs/rehmed-2026-08-18-distillation.md)
  and from there to `2-Solution/` in the engagement repository. Nothing here was
  invented to make a contract look complete; where the material was silent, the
  declaration is absent and the moduledoc says so.
  """

  use Boundary, deps: [PNS], exports: []
end
