# Exported so a consumer's `mix format` leaves a contract looking like the ones in
# `docs/contract.md`. Without this, `event :x, label: "..."` is rewritten with
# parentheses and every contract in every consuming project reads like a function
# call rather than like a declaration — which is the whole point of the DSL's shape.
#
# `packages/eh_os_contract_web/.formatter.exs` used to hand-copy this list for its own fixture,
# because this file did not exist. That copy had already gone stale: it was missing
# `external: 2`, `rule: 2` and `example: 2`.
# The v2 DSL's entities, maintained by Spark rather than by hand:
# `mix spark.formatter --extensions EhOsContract.Domain.Dsl` rewrites this list, and
# the package's `mix check` runs it with `--check`, so it cannot fall behind the DSL.
spark_locals_without_parens = [
  actor: 3,
  actor: 4,
  avoid: 1,
  avoid: 2,
  backed_by: 1,
  between: 1,
  context: 1,
  context: 2,
  context: 3,
  default: 1,
  definition: 1,
  direction: 1,
  downstream: 1,
  expected_latency: 1,
  external: 2,
  external: 3,
  field: 2,
  field: 3,
  label: 1,
  language: 1,
  optional: 1,
  personal: 1,
  relation: 1,
  relation: 2,
  source: 1,
  subdomain: 1,
  subject: 1,
  subject: 2,
  subject: 3,
  term: 1,
  term: 2,
  terms: 1,
  translation: 2,
  translation: 3,
  type: 1,
  unavailable_looks_like: 1,
  unit: 1,
  upstream: 1,
  value: 1,
  value: 2,
  value: 3
]

# The v1 contract DSL's, by hand, until v1 is removed (v2 plan, E11).
v1_locals_without_parens = [
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

locals_without_parens = v1_locals_without_parens ++ spark_locals_without_parens

[
  # `:ecto_sql` for `EhOsContract.Migrations`' version modules.
  import_deps: [:ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  # Named once, used twice: `export:` is what a consumer's `import_deps: [:eh_os_contract]`
  # reads, the top-level key is what this package's own `mix format` uses — and
  # without the second, the fixtures in `test/support/` are the one place in the
  # repository where a contract would be rewritten with parentheses.
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
