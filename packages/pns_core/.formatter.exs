# Exported so a consumer's `mix format` leaves a contract looking like the ones in
# `docs/contract.md`. Without this, `event :x, label: "..."` is rewritten with
# parentheses and every contract in every consuming project reads like a function
# call rather than like a declaration — which is the whole point of the DSL's shape.
#
# `packages/pns_web/.formatter.exs` used to hand-copy this list for its own fixture,
# because this file did not exist. That copy had already gone stale: it was missing
# `external: 2`, `rule: 2` and `example: 2`.
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  export: [
    locals_without_parens: [
      event: 1,
      event: 2,
      process: 2,
      external: 2,
      rule: 2,
      example: 2,
      command: 2,
      trace: 1,
      from: 1,
      eventually: 1,
      eventually: 2,
      or_else: 1
    ]
  ]
]
