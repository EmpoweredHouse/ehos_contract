# Changelog

The rule this package follows is the one written in `packages/eh_os_contract_core/CHANGELOG.md`:
a change that can move something the dashboard reports raises the minor version and
gets a line here.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **Removed:** the provisional login (`EhOsContract.Web.LocalLogin`, the `/login` and
  `/logout` routes), the accounts screen (`EhOsContract.Web.Live.Accounts`), the optional
  `EhOsContract.Web.Plug.Authenticate` and the default resolver `EhOsContract.Web.Resolvers.Default`.
  All of them stood on `EhOsContract.Auth`, which left the engine with them. `:resolver` is
  now required by both `eh_os_contract_dashboard/2` and `eh_os_contract_api/2`: the host decides who may
  see the dashboard, with no fallback that silently lets everyone in.

## 0.1.0 — not published

Everything to date, recorded after the fact. The package is not on Hex and cannot
be until `eh_os_contract` is: it depends on it by path, and a published package may only
depend on published ones. See `README.md` for the second reason.

- **Fixed:** only the verdict carries the verdict's colour. The whole sentence used
  to, including the clause explaining that an external outage means "this is not a
  breach on the client's side" — printed in red, which says the opposite of what it
  means. `EhOsContract.Report.Sentence.verdict/1` and `qualifications/1` split the two.
- **Fixed:** the contract screen was quietly answering six fewer questions than
  `mix eh_os_contract.report`. It carried its own copy of the report's sentences — a
  deliberate duplication, made when both copies said the same four things — and by
  the time anybody ran the two side by side it had no addressee, no measured
  `deadline`, nothing for a run suspended by an external outage, nothing for a run
  judged under a rule that had since changed, nothing about which met runs reached
  the fallback, and no sign of queued work at all. A run suspended by somebody
  else's outage read on screen exactly like an ordinary one. Every sentence now
  comes from `EhOsContract.Report.Sentence`; the screen decides what is a heading, a list or
  red, and decides nothing about what the answer says.
- `eh_os_contract_api/2` also serves the generated AsyncAPI documents: an index at
  `/asyncapi` and one document per contract, each with its digest in the body and
  in the `ETag`. Authenticated like everything else — a document naming every event
  and label in the client's own words is a map of their business.
- `eh_os_contract_api/2`, a read-only JSON mount for the conformance report, sharing the
  dashboard's access decision through the same `EhOsContract.Web.Resolver`. It mounts in its
  own scope because a JSON route needs the opposite pipeline to a page: no session,
  no CSRF, and `accepts` saying json rather than html.
- **Fixed:** `EhOsContract.Web.Plug.Authenticate` crashed on any request without a bearer
  header in a pipeline that had not fetched a session — that is, on exactly the
  unauthenticated request an API mount most needs to refuse cleanly.
- `eh_os_contract_dashboard/2`, mountable in a host's own router, with three LiveView screens:
  contract conformance, accounts, and the process graph.
- `EhOsContract.Web.Resolver`, the seam by which a host decides who may see the dashboard,
  with a default reading `conn.assigns[:eh_os_contract_actor]`.
- `EhOsContract.Web.Plug.Authenticate`, optional, filling that assign from a bearer token or
  the session.
- A provisional local login, `EhOsContract.Web.LocalLogin`, for a host that has no identity
  provider wired up yet.
