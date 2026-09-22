[
  # `:pns` exports the contract DSL's `locals_without_parens`, so this package's own
  # test fixture formats the way every contract in the repository does. It used to
  # be a hand-copied list here, because `packages/pns_core` had no `.formatter.exs`
  # — and the copy had already drifted.
  import_deps: [:phoenix, :phoenix_live_view, :pns],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  # For a consumer's `import_deps: [:pns_web]` — `pns_dashboard/1,2` reads
  # like `plug`/`live`/`scope`, the router DSL it sits beside in a host's
  # own router, not like a plain function call.
  export: [locals_without_parens: [pns_dashboard: 1, pns_dashboard: 2]]
]
