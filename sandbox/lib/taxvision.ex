defmodule Taxvision do
  @moduledoc """
  The client application. Whatever is specific to TaxVision — and whatever is not
  lands in `lib/eh_os_contract/`. That one rule is the whole discipline of this prototype
  (notes §15, step 1).

  The topology of the boundaries is content here rather than ornament. Every
  process module is a **separate boundary** and a sibling of the others, so
  reaching another module's tables requires an explicit `deps` — which nobody
  writes by accident. `boundary` rejected the first version, in which `Taxvision`
  depended on its own children, and it was right: that was a hierarchy pretending
  to be a boundary.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
