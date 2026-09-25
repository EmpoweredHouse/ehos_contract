defmodule Rehmed.Domain do
  @moduledoc """
  The vocabulary Rehmed's v2 contracts will share: contexts, actors, value types
  (v2 §4.5, v2 plan stage E3).

  Nothing reads it yet. The v1 contracts in `Rehmed.Contracts` do not know a
  domain, and the first v2 contract to name this one is VisitSettlement, in E6. It
  is here now because E3 has to show that a domain module compiles under this
  application's strict `boundary` with `--warnings-as-errors`, and that the
  formatter keeps it as declarations through `import_deps`. The scheduling context
  is written with its options beside its block, which is how v2 §4.5 writes a
  declaration and what v2 §16, D13, keeps legal.

  It translates v2 §4.5 and adds nothing to it. The identifiers in comments point
  into the material the same way the v1 contracts' `source:` strings do. `A-02`,
  `A-03` and `A-05` are the actors those contracts already cite, and `CTX-01` is the
  one `core` context of the context map
  (`docs/rehmed-2026-08-18-distillation.md`). The payment methods are the four
  `E-55` lists for `payment_recorded`. `CTX-05` is the number v2 §4.5 gives
  settlement; this repository's distillation does not repeat it.
  """

  use EhOsContract.Domain, name: :rehmed, language: :pl
  use Boundary, deps: [EhOsContract], exports: [Values]

  # CTX-01. The term is the good end state of a booked visit as `AGG-01` and `E-51`
  # name it; v2 §4.6 puts `visit_completed` in scheduling.
  context :scheduling, "Umawianie i zasoby", subdomain: :core do
    term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu", source: "AGG-01, E-51"
  end

  # CTX-05, as v2 §4.5 numbers it
  context :settlement, "Rozliczenia", subdomain: :supporting
  relation :customer_supplier, upstream: :scheduling, downstream: :settlement

  # A-02
  actor :reception, :human, "Recepcja"
  # A-03
  actor :specialist, :human, "Specjalista"
  # A-05
  actor :manager, :human, "Menedżer"

  value :money, :integer, unit: :grosze, label: "Kwota"

  # E-55: cash, card, bank transfer, voucher
  value :payment_method,
        {:enum, [card: "Karta", cash: "Gotówka", transfer: "Przelew", voucher: "Bon"]}
end
