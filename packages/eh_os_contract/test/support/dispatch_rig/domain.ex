defmodule DispatchRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `DispatchRig`: the actors a dispatch test needs.
  A clerk is a person who acts with a credential, and sees the balances of the
  branches the credential grants; the nightly import is the application's own
  code, a `:system` actor; the auditor is a person who confirms balances without a
  command, which a credential cannot yet do (v2 §11, the note of 26 September).
  """

  use EhOsContract.Domain, name: :dispatch_rig, language: :en

  context :ledger, "Ledger", subdomain: :core

  actor :clerk, :human, "Clerk", scope: [:branch_id]
  actor :auditor, :human, "Auditor"
  actor :nightly_import, :system, "Nightly import", scope: [:branch_id]

  subdomain :core, "Core", type: :core
end
