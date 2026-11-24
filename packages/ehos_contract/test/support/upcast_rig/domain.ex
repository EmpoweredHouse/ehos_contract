defmodule UpcastRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `UpcastRig`: a requester is a person whose data may be
  erased, and a clerk records what they ask for.
  """

  use EhosContract.Domain, name: :upcast_rig, language: :en

  context :requests, "Requests", subdomain: :core

  actor :clerk, :human, "Clerk"

  subject :requester, "Requester"

  subdomain :core, "Core", type: :core
end
