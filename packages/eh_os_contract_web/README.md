# EhOsContract.Web

A conformance dashboard for [EhOsContract](https://hex.pm/packages/eh_os_contract), mounted in your
own router.

Two screens and nothing else: the contract's conformance status, and the process
graph — declared shape per process, declared versus observed across all of them.

## Installation

From git, beside the engine, with the same `git:` and `sparse:` shape — this package
declares its dependency on the engine that way whenever it is fetched on its own, so
the two declarations converge instead of diverging:

```elixir
def deps do
  [
    {:eh_os_contract,
     git: "https://github.com/EmpoweredHouse/eh-os-prototype.git",
     sparse: "packages/eh_os_contract"},
    {:eh_os_contract_web,
     git: "https://github.com/EmpoweredHouse/eh-os-prototype.git",
     sparse: "packages/eh_os_contract_web"}
  ]
end
```

## Mounting it

```elixir
scope "/" do
  pipe_through :browser
  import EhOsContract.Web.Router

  eh_os_contract_dashboard "/dashboard", resolver: MyApp.EhOsContractResolver
end
```

Static assets are served at the **endpoint**, not through the macro. Phoenix's
cross-origin script guard refuses to serve JavaScript through a CSRF-protected
route, on principle and correctly, so add one line to your endpoint:

```elixir
plug Plug.Static,
  at: "/eh_os_contract_web/assets",
  from: {:eh_os_contract_web, "priv/static/assets"},
  gzip: false
```

This package's own test host carries that same line, so the suite proves the
instruction rather than assuming it.

## Who may see it

`eh_os_contract_dashboard/2` and `eh_os_contract_api/2` both require a `:resolver` implementing
`EhOsContract.Web.Resolver`: one callback says who the caller is, another says whether they
get `:all`, `:read_only` or a redirect. There is no default and no login screen —
the host already knows who is logged in, and this package does not get to guess.

## Not on Hex

This package is not published. Two reasons, both recorded rather than pending:

- it depends on `eh_os_contract`, which is not on Hex either, and a published package
  may depend only on published ones;
- `priv/static/assets/mermaid.min.js` is a vendored third-party build, so a tarball
  redistributes somebody else's code. `NOTICE` carries the attribution, and the
  decision to actually publish is a separate one.

## Licence

Apache 2.0. Third-party components are listed in `NOTICE`.
