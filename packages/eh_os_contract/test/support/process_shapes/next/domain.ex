defmodule ProcessShapes.Domain do
  @moduledoc """
  # THIS DOMAIN IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The vocabulary the v2 process shapes name (v2 plan, E7c): `ProcessShapes.Next.Promised`,
  `ProcessShapes.Next.Timed` and `ProcessShapes.Next.Bare`, ported beside their v1
  originals so that the same runs can be judged on both. English, like the shapes:
  nobody reads it as a process owner.

  The one role a v1 shape wrote as a string, `accountable: "Run owner"`, is an actor
  here, as v2 makes it (v2 §18).
  """

  use EhOsContract.Domain, name: :process_shapes, language: :en

  context :handling, "Request handling", subdomain: :core
  context :timing, "Timed runs", subdomain: :supporting
  context :batching, "Batch runs", subdomain: :supporting

  actor :requester, :human, "Requester"
  actor :reviewer, :human, "Reviewer"
  actor :run_owner, :human, "Run owner"
  actor :batch_operator, :human, "Batch operator"
end
