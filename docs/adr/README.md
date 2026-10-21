# The design record

These files are the library's design record: the assumptions it was built on, and the decisions taken
while it was built. **The record is historical and dated.** Each file states what was believed when it was
written; where the code later proved an assumption wrong, a dated amendment was added beside it, or a
dated correction in place where a file says so, and the original text was never silently rewritten. Read
it to learn why a mechanism exists, not what the code does today: for that, the packages' own docs
(`packages/eh_os_contract/docs/`) and the code are the source.

Four of the eight files predate the library's rename from `pns` (`PNS.*`). In them a module that survived the
rename, `PNS.X`, is today's `EhOsContract.X`; some they name, such as `PNS.Auth` and `PNS.Command.permits?/3`,
were removed and have no equivalent. Part of the record was written while the library was tested on client material that has since
been removed from the repository; the clients are described rather than named, and their examples are kept
only where they illustrate a decision.

| File | What it is |
| --- | --- |
| [`architecture.md`](architecture.md) | The starting assumptions of the first version: the numbered decisions (`§N`) that code comments cite. |
| [`contract-v2.md`](contract-v2.md) | The contract language's second version: its rules, its shapes and the refusals it introduced. |
| [`design-rationale.md`](design-rationale.md) | The argument behind each decision of the architecture, the alternatives it beat and the open questions. |
| [`technology-notes.md`](technology-notes.md) | Code shapes, schemas, tables, library choices and pitfalls: what `notes §N` in a comment points at. |
| [`identity-seam.md`](identity-seam.md) | Identity behind a protocol seam: the survey of providers and what a proof of concept would check. |
| [`browser-session.md`](browser-session.md) | What `eh_os_contract_auth` decides about a browser session beside EHOS's own sign-in. |
| [`dashboard-design-system.md`](dashboard-design-system.md) | How the dashboard takes its look from the EmpoweredHouse design system. |
| [`graph-renderer.md`](graph-renderer.md) | What draws a `graph.v1` document, the options weighed and the one chosen. |
