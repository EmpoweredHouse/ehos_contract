# PNS.Web

A conformance dashboard for [PNS](https://hex.pm/packages/pns), mounted in your
own router.

Three screens and nothing else: the contract's conformance status, the accounts
that may see it, and the process graph — declared shape per process, declared
versus observed across all of them.

## Mounting it

```elixir
scope "/" do
  pipe_through :browser
  import PNS.Web.Router

  pns_dashboard "/pns"
end
```

Static assets are served at the **endpoint**, not through the macro. Phoenix's
cross-origin script guard refuses to serve JavaScript through a CSRF-protected
route, on principle and correctly, so add one line to your endpoint:

```elixir
plug Plug.Static,
  at: "/pns_web/assets",
  from: {:pns_web, "priv/static/assets"},
  gzip: false
```

This package's own test host carries that same line, so the suite proves the
instruction rather than assuming it.

## Who may see it

`pns_dashboard/2` takes a `:resolver` implementing `PNS.Web.Resolver`: one callback
says who the caller is, another says whether they get `:all`, `:read_only` or a
redirect. The default reads `conn.assigns[:pns_actor]`, which the optional
`PNS.Web.Plug.Authenticate` fills from a bearer token or the session — but a host is
free to fill that assign however it already authenticates.

## Not on Hex

This package is not published. Two reasons, both recorded rather than pending:

- it depends on `pns` by path, which a published package cannot do;
- `priv/static/assets/mermaid.min.js` is a vendored third-party build, so a tarball
  redistributes somebody else's code. `NOTICE` carries the attribution, and the
  decision to actually publish is a separate one.

## Licence

Apache 2.0. Third-party components are listed in `NOTICE`.
