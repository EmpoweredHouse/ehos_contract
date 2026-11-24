defmodule LifecycleRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `LifecycleRig`. Reception books and runs visits; the
  front desk is the application's own code, which records a patient's arrival when
  the patient checks in at a kiosk.
  """

  use EhosContract.Domain, name: :lifecycle_rig, language: :en

  context :visits, "Visits", subdomain: :core

  actor :reception, :human, "Reception"
  actor :front_desk, :system, "Front desk"

  subdomain :core, "Core", type: :core
end
