[
  # `:ehos_contract` exports the contract DSL's `locals_without_parens`, so this package's own
  # test fixture formats the way every contract in the repository does. It used to
  # be a hand-copied list here, because `packages/ehos_contract` had no `.formatter.exs`
  # — and the copy had already drifted.
  import_deps: [:phoenix, :phoenix_live_view, :ehos_contract],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  # For a consumer's `import_deps: [:ehos_contract_web]` — `ehos_contract_dashboard/1,2` reads
  # like `plug`/`live`/`scope`, the router DSL it sits beside in a host's
  # own router, not like a plain function call.
  export: [
    locals_without_parens: [
      ehos_contract_dashboard: 1,
      ehos_contract_dashboard: 2,
      ehos_contract_api: 1,
      ehos_contract_api: 2
    ]
  ]
]
