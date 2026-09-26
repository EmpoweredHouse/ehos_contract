defmodule DispatchRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `DispatchRig`: the actors a dispatch test needs.
  A clerk is a person who acts with a credential; the nightly import is the
  application's own code, a `:system` actor.
  """

  use EhOsContract.Domain, name: :dispatch_rig, language: :en

  context :ledger, "Ledger", subdomain: :core

  actor :clerk, :human, "Clerk"
  actor :auditor, :human, "Auditor"
  actor :nightly_import, :system, "Nightly import"
end
