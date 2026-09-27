# The EmpoweredHouse design system, as copied

`colors_and_type.css` is a copy of the design system's foundation, kept here so the dashboard builds
without Claude Design ([the decision](../../../../../../docs/adr/dashboard-design-system.md), following
`eh-os` D-42). Do not edit it by hand: `test/design_system_test.exs` fails if it no longer matches the
hash below. A change reaches it only by a refresh, described in the repository's
`.claude/skills/sync-design-system/SKILL.md`. The dashboard's own styles are in `assets/css/app.css`.

The same file, byte for byte, is `eh-os`'s `assets/vendor/empoweredhouse/colors_and_type.css`. After a
refresh in either repository, both copies should have the hash below.

| | |
| --- | --- |
| Project | EmpoweredHouse Design System [FINAL] (Claude Design, design-system project) |
| Project id | `3f8e8eea-af89-4d98-851c-760c2b2e862c` |
| File | `colors_and_type.css` |
| Etag in Claude Design | `1781439475482903` |
| Taken | 2026-09-25, by `eh-os`; copied from there 2026-09-28 |
| SHA-256 as published | `fb98b275ea2e00182aa429268d9ea621ebcd96daa1ab8e48a235cc1ab17b7872` (16064 bytes, 416 lines) |
| Change made | The line `@import url("https://fonts.googleapis.com/css2?…")` is removed. The dashboard serves the fonts itself, from `priv/static/assets/fonts/`. |
| SHA-256 as committed | `704bbd4eecb0505700dd5531e8a4ead4b02c3fdc7e716e3aca24654a68e88888` |

## Fonts

Albert Sans and JetBrains Mono, weights 400 and 500, subsets `latin` and `latin-ext`, taken as WOFF2
from the npm packages `@fontsource/albert-sans@5.3.0` and `@fontsource/jetbrains-mono@5.3.0` (by way of
`eh-os`'s `priv/static/fonts/`, the same files). Both are under the SIL Open Font License 1.1, whose
text is beside the files in `priv/static/assets/fonts/`.

## Not copied

- The marks of EmpoweredHouse, Shugyo and EHOS. Whether they may be in a repository is open (D-42), and
  the dashboard names itself in text.
- The design system's README, brand book and claim system.
- The Shugyo screens, their data and screenshots.
