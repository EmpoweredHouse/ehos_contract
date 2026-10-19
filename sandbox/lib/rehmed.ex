defmodule Rehmed do
  @moduledoc """
  The second client case, and the first one the engine did not grow up with.

  `lib/taxvision/` is here as a full application — schemas, handlers, a repo. This
  tree is **contracts and the code they need to run**: no screen and no real
  integration. Until 26 September 2026 it was contracts only; since v2 a
  contract's scenarios are tests, and a test needs an implementation to run
  against, so each contract has one beside it (`Rehmed.Scheduling`,
  `Rehmed.Settlement`, …): pure decisions and policies, one read model with its
  table, and an effect that stands in for the P1 registry. The question the tree answers is unchanged: whether the
  DSL can carry a modelled process.

  That makes it a different kind of evidence from `UniversalityGate`, which is an
  invented domain written by the author to prove the vocabulary needs no new words.
  This one is client material: every event name traces to a workshop, a board lane
  or a transcript, through
  [`docs/rehmed-2026-08-18-distillation.md`](../docs/rehmed-2026-08-18-distillation.md)
  and from there to `2-Solution/` in the engagement repository. Nothing here was
  invented to make a contract look complete; where the material was silent, the
  declaration is absent and the moduledoc says so.
  """

  use Boundary, deps: [EhOsContract], exports: [Supplier, Entities]
end
