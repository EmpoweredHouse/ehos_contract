# EhOsContract.Web

A conformance dashboard for [EhOsContract](https://hex.pm/packages/eh_os_contract), mounted in your
own router.

Two screens and nothing else: the contract's conformance status, and the graphs —
each domain's context map and system, and per process its declared shape, its graph
with the log laid over it, and its contract's units.

## Installation

From git, beside the engine, with the same `git:` and `sparse:` shape — this package
declares its dependency on the engine that way whenever it is fetched on its own, so
the two declarations converge instead of diverging:

```elixir
def deps do
  [
    {:eh_os_contract,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract"},
    {:eh_os_contract_web,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
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

The same line serves the fonts: they sit beside the stylesheet, in
`priv/static/assets/fonts/`, and the stylesheet names them by relative URL. Nothing
the dashboard loads comes from anywhere but these assets — no Google Fonts, no CDN —
so it works under a policy of `default-src 'self'` and without internet, with one
exception: the graph screen's diagrams need inline styles (see "Looks" below).

## Looks

The dashboard is styled from the EmpoweredHouse design system, the one the EHOS
console uses: dark by default, light when the system prefers it. Its tokens and fonts
come from the `ehos_design` package in
[EmpoweredHouse/ehos-tools](https://github.com/EmpoweredHouse/ehos-tools/tree/main/packages/ehos_design),
a `:dev` dependency pinned in `mix.exs`. `mix assets.build` imports the plain tokens,
`priv/css/colors_and_type.css`, into the stylesheet and copies the fonts beside it.
The built stylesheet and the fonts are committed under `priv/static/assets/`, so a host
fetches nothing from that package; a new version of the design system reaches the
dashboard by moving the pinned ref and rebuilding.

A host cannot restyle it or pin its theme yet. The dashboard's root layout replaces
the host's for these routes and loads only this package's stylesheet, so neither a
host stylesheet nor a `data-theme` attribute reaches the page. The
`--eh-os-contract-*` custom properties are kept as the names such a hook would set.

**The dashboard works under a strict Content-Security-Policy**, `default-src 'self'`
as EHOS serves it. Mermaid, which draws the graph screen's diagrams in the browser,
writes a `<style>` element and `style` attributes into each; the dashboard hands both
to the CSSOM, which such a policy leaves alone. Mermaid still tries inline styles
while it measures a diagram, so the browser's console logs blocked inline styles on
the graph screen; the diagrams are drawn in full regardless. The sandbox host serves
this policy on the dashboard, so it is looked at there as it runs in EHOS.

## Who may see it

`eh_os_contract_dashboard/2` and `eh_os_contract_api/2` both require a `:resolver` implementing
`EhOsContract.Web.Resolver`: one callback says who the caller is, another says whether they
get `:all`, `:read_only` or a redirect. There is no default and no login screen —
the host already knows who is logged in, and this package does not get to guess.

## Not on Hex

This package is not published. Two reasons, both recorded rather than pending:

- it depends on `eh_os_contract`, which is not on Hex either, and a published package
  may depend only on published ones;
- `priv/static/assets/mermaid.min.js` is a vendored third-party build, and
  `priv/static/assets/fonts/` holds two third-party fonts, so a tarball redistributes
  somebody else's work. `NOTICE` carries the attribution, and the decision to
  actually publish is a separate one.

## Licence

Apache 2.0. Third-party components are listed in `NOTICE`.
