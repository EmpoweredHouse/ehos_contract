defmodule PhaseRig.Domain do
  @moduledoc "**Invented**, like the rest of `PhaseRig`: the one actor its commands need."

  use EhosContract.Domain, name: :phase_rig, language: :en

  context :visits, "Visits", subdomain: :core

  actor :clerk, :human, "Clerk"

  subdomain :core, "Core", type: :core
end
