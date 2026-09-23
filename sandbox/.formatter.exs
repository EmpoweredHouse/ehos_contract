# Used by "mix format"
[
  # `:eh_os_contract` carries the contract DSL's `locals_without_parens`. Without it `mix format`
  # rewrites every contract in `lib/` with parentheses — which is what this line was
  # missing until 2026-09-22, because the package had no `.formatter.exs` to import.
  # `:ecto_sql` for the migrations, which are the only place `add`/`remove` appear
  # and which read as a DSL rather than as function calls.
  import_deps: [:ecto_sql, :phoenix, :phoenix_live_view, :eh_os_contract_web, :eh_os_contract],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
