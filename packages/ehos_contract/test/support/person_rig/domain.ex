defmodule PersonRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `PersonRig`. A clerk is a person with a credential; the
  night shift is the application's own code, a `:system` actor that resolves what is
  left at the end of the day.
  """

  use EhosContract.Domain, name: :person_rig, language: :en

  context :desk, "Desk", subdomain: :core

  actor :clerk, :human, "Clerk"
  actor :night_shift, :system, "Night shift"

  subdomain :core, "Core", type: :core
end
