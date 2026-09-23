[
  # `:eh_os_contract` exports the contract DSL's `locals_without_parens`, so this package's own
  # test fixture formats the way every contract in the repository does. It used to
  # be a hand-copied list here, because `packages/eh_os_contract` had no `.formatter.exs`
  # — and the copy had already drifted.
  import_deps: [:phoenix, :phoenix_live_view, :eh_os_contract],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  # For a consumer's `import_deps: [:eh_os_contract_web]` — `eh_os_contract_dashboard/1,2` reads
  # like `plug`/`live`/`scope`, the router DSL it sits beside in a host's
  # own router, not like a plain function call.
  export: [
    locals_without_parens: [
      eh_os_contract_dashboard: 1,
      eh_os_contract_dashboard: 2,
      eh_os_contract_api: 1,
      eh_os_contract_api: 2
    ]
  ]
]
