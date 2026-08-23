[
  import_deps: [:phoenix, :phoenix_live_view],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  # packages/pns_core has no .formatter.exs of its own to import_deps from, so
  # this package's own test fixture (the only PNS.Contract this package
  # writes) would otherwise format with parens — unlike every contract in
  # docs/contract.md and the rest of the repo, which read like Ecto.Schema on
  # purpose.
  locals_without_parens: [
    event: 1,
    event: 2,
    process: 2,
    trace: 1,
    from: 1,
    eventually: 1,
    eventually: 2,
    or_else: 1
  ],
  # For a consumer's `import_deps: [:pns_web]` — `pns_dashboard/1,2` reads
  # like `plug`/`live`/`scope`, the router DSL it sits beside in a host's
  # own router, not like a plain function call.
  export: [locals_without_parens: [pns_dashboard: 1, pns_dashboard: 2]]
]
