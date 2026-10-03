defmodule AppuniteEquipment do
  @moduledoc """
  The third client case: AppUnite's own employee computers, from the order to the
  sale, as one person runs them today in a spreadsheet and in Notion.

  Like `lib/rehmed/`, this tree is **contracts and the code they need to run**: a
  domain, two contracts, and the pure decision of one computer, so that the
  contracts' scenarios run. No screen and no integration.

  It is here for the shape no earlier case had. A visit or an accounting month is a
  run with a start and an end; a computer lives for years and goes round the same
  loop — issued, returned, cleaned, set up, issued again — before it ends. Every
  name traces to [`docs/appunite-equipment-2026-10-03-distillation.md`](../docs/appunite-equipment-2026-10-03-distillation.md):
  `T l.N` is a line of the notes from the conversation with the person who manages
  the equipment, `E` an answer of the process owner of 3 October 2026, and `A:F` and
  `A:G` the status lists of the spreadsheet.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
