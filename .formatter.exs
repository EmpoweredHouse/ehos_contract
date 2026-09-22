# Used by "mix format"
[
  # `:pns` carries the contract DSL's `locals_without_parens`. Without it `mix format`
  # rewrites every contract in `lib/` with parentheses — which is what this line was
  # missing until 2026-09-22, because the package had no `.formatter.exs` to import.
  import_deps: [:phoenix, :phoenix_live_view, :pns_web, :pns],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
