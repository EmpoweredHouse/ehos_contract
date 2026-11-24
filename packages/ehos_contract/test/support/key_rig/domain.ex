defmodule KeyRig.Domain do
  @moduledoc "**Invented**, like the rest of `KeyRig`: the one actor a key test needs."

  use EhosContract.Domain, name: :key_rig, language: :en

  context :stock, "Stock", subdomain: :core

  actor :stocker, :human, "Stocker"

  subdomain :core, "Core", type: :core
end
