# Changelog

The rule this package follows is the one written in `packages/pns_core/CHANGELOG.md`:
a change that can move something the dashboard reports raises the minor version and
gets a line here.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.1.0 — not published

Everything to date, recorded after the fact. The package is not on Hex and cannot
be until `pns` is: it depends on it by path, and a published package may only
depend on published ones. See `README.md` for the second reason.

- `pns_api/2` also serves the generated AsyncAPI documents: an index at
  `/asyncapi` and one document per contract, each with its digest in the body and
  in the `ETag`. Authenticated like everything else — a document naming every event
  and label in the client's own words is a map of their business.
- `pns_api/2`, a read-only JSON mount for the conformance report, sharing the
  dashboard's access decision through the same `PNS.Web.Resolver`. It mounts in its
  own scope because a JSON route needs the opposite pipeline to a page: no session,
  no CSRF, and `accepts` saying json rather than html.
- **Fixed:** `PNS.Web.Plug.Authenticate` crashed on any request without a bearer
  header in a pipeline that had not fetched a session — that is, on exactly the
  unauthenticated request an API mount most needs to refuse cleanly.
- `pns_dashboard/2`, mountable in a host's own router, with three LiveView screens:
  contract conformance, accounts, and the process graph.
- `PNS.Web.Resolver`, the seam by which a host decides who may see the dashboard,
  with a default reading `conn.assigns[:pns_actor]`.
- `PNS.Web.Plug.Authenticate`, optional, filling that assign from a bearer token or
  the session.
- A provisional local login, `PNS.Web.LocalLogin`, for a host that has no identity
  provider wired up yet.
