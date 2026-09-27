# The dashboard's look — a copy of the EmpoweredHouse design system

> **Status: proposed**, 28 September 2026. Becomes *accepted* when the product owner says so, and is
> corrected in place, with a date, where the code proves it wrong.
>
> Follows `eh-os` [D-42](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/adr/0042-console-design-system-vendored-copy.md)
> (accepted 25 September 2026), which made the same decision for the EHOS console. What D-42 argues —
> why a copy, why the design-system project and not Shugyo's fork, why the repository never writes back
> — holds here unchanged and is not restated. This file records what is different about a mountable
> library with a plain stylesheet.

## The problem

`packages/eh_os_contract_web` ships its own look: GitHub-like colours in `--eh-os-contract-*` properties,
the system font, a light theme only. The EHOS console, which is where this dashboard's readers also work,
is styled from the EmpoweredHouse design system that Shugyo is built on. The two look like two products.

The design system is made in Claude Design, which contributors to this repository will not have: the
library is to be published as open source (see `README.md`). And the dashboard is not an application.
It is mounted inside somebody else's Phoenix application, under that application's
Content-Security-Policy, and may run where there is no internet.

## Drivers

1. The package builds, tests and can be restyled from this repository alone. Nothing in the build or
   the tests reaches Claude Design or any other outside service.
2. The dashboard looks like the product family, and follows the design system as it changes.
3. Each token has one definition.
4. The page loads nothing from outside the package's own assets. A host's CSP decides what else is
   allowed, and this package cannot assume it allows anything.
5. **The host does nothing new.** Mounting instructions in `README.md` are one route macro and one
   `Plug.Static` line. A restyle that needs a second line has made every host's upgrade a code change.
6. A host can still restyle the dashboard with its own stylesheet, as it can today through the
   `--eh-os-contract-*` properties.

   *Correction, 28 September 2026 (review of this change):* it cannot, and could not before. The root
   layout replaces the host's and loads only the package's stylesheet, so no host stylesheet reaches
   these pages. The properties are kept, pointing at tokens, as the names a future hook would set.
   Adding that hook changes what a host sees, so it is the product owner's decision, not this
   change's.

## Decision

Same three layers as D-42, placed in the package:

- **The copy**, `packages/eh_os_contract_web/assets/css/vendor/empoweredhouse/colors_and_type.css`, the
  design-system project's file with its Google Fonts `@import` removed, and `SOURCE.md` beside it with
  the project, etag, both hashes and the one change. It is byte-identical to `eh-os`'s copy, so a
  refresh in either repository should leave both with the same hash. Nobody edits it by hand; a test
  compares its SHA-256 with `SOURCE.md`, and `.gitattributes` keeps git from converting its line
  endings.
- **The dashboard's layer**, `assets/css/app.css`, plain CSS. It imports the copy first, then:
  - keeps `--eh-os-contract-*`, each now set to a token (`--eh-os-contract-bg: var(--canvas)`) —
    meant as the host's override surface, which driver 6's correction says no host can reach yet;
  - never redefines a property the copy defines (a test compares the two sets of names), and may add
    properties of its own, named `--eh-os-contract-*`;
  - declares the fonts' `@font-face` with URLs relative to the stylesheet.
- **The rules** are D-42's, written for contributors in `eh-os`'s `docs/DESIGN.md`. They are not copied
  into this repository: the dashboard is two screens and uses a handful of them, which the layer's own
  comments name where they apply. A second copy of `DESIGN.md` would drift from the first.

**Fonts** — Albert Sans and JetBrains Mono, 400 and 500, `latin` and `latin-ext`, the same WOFF2 files
as `eh-os` — live in `priv/static/assets/fonts/`, beside the built `app.css`. The `Plug.Static` line a
host already has serves them, and relative URLs resolve against wherever that line mounted the
stylesheet. This is driver 5, and the reason the fonts are not in `priv/static/fonts/` as in EHOS. The
build leaves the URLs alone (esbuild's `--external`), and the tarball carries the fonts with their
licence; `NOTICE` names them.

**Themes** follow the copy: dark by default, light under `prefers-color-scheme: light`. The copy
can also be pinned by `data-theme` on `<html>`, and the diagrams redraw when it changes, but the
dashboard's layout never sets it. The dashboard has no switch of its own, and does not follow a host's: the
EHOS console has one, but the dashboard's root layout replaces the host's, so a choice made there does
not reach these pages. Following it would need the host to pass something in, which driver 5 rules out
for now.

**The dashboard's own colour decisions** (the product owner, 28 September 2026):

- A promise's verdict: *breached* in the error colour, *met* and *in progress* in neutral text. The
  sentence already says which. Lime stays for the one signal — the page being viewed.
- Mermaid is themed from the tokens at render time, read from the page's computed style, so diagrams
  follow the theme. The engine's own node colours are handled in two ways. The v1 classes
  (`confirmed`, `in_flight` and `dead` on the overlay, `terminal` and `external` on the declared shape)
  are status colours — green, amber — that the design system does not have, so the dashboard replaces
  them with tokens. The v2 graph's Event Storming palette stays for
  now, as the vocabulary of the workshop rather than decoration. **It is likely to change soon**, so the
  replacement is one table in `assets/js/app.js` that the Event Storming classes can join. The engine is
  not changed: its Mermaid output also goes to `mix eh_os_contract.graph`, which has no page to theme.

**Not copied**, as in D-42: the marks of EmpoweredHouse, Shugyo and EHOS (the dashboard names itself in
text), the brand book, Shugyo's screens and data.

## Refreshing the copy

`.claude/skills/sync-design-system/SKILL.md`, adapted from `eh-os`: the source is always the
design-system project named in `SOURCE.md`, the transcription is checked against the published size and
line count, the one change is made, the token diff is shown, the tests run, the commit carries all of it.
Nothing is ever written to Claude Design. Without Claude Code, a maintainer with access copies `eh-os`'s
copy, which is the same file.

## Consequences

- Good: the dashboard looks like the console it sits beside, in both themes, from the repository alone.
- Good: a host changes nothing.
- Bad: two repositories now hold the same copy, and a refresh has to be made in both. The hashes make a
  missed one visible, but nothing reports it.
- Bad: the dashboard becomes dark by default for every host. A host with a light-only application sees
  a dark dashboard on a machine set to dark. This is the design system's default, and today a host
  cannot change it (driver 6).
- Bad: `eh_os_contract_web`'s tarball grows by eight font files, about 100 KB.
- Neutral: the rules reach contributors through D-42 and `eh-os`'s `DESIGN.md`. Where `eh-os` cannot be
  read, the layer's comments are all a contributor here has.

## Found while checking it, 28 September 2026

**The graph screen does not work under a strict Content-Security-Policy, and never has.** Mermaid
writes a `<style>` element into every diagram it draws, so a host whose policy has no `'unsafe-inline'`
for styles — EHOS's is `default-src 'self'` — blocks it, and each diagram renders as black boxes. The
status screen is unaffected. Checked on the sandbox host with EHOS's policy added for the test: the same
result with the stylesheet and script from before this change, so it is not caused by it, and it is
not fixed by it either. Driver 4 holds for what the dashboard *loads*; it does not yet hold for what
Mermaid *injects*. Recorded in `PLAN.md` as its own piece of work.

## Confirmation

`packages/eh_os_contract_web/test/design_system_test.exs`:

- the copy's SHA-256 equals `SOURCE.md`'s;
- `.gitattributes` has the `-text` rule for the copy;
- neither the copy nor `app.css`, source or built, names another origin in `url(` or `@import`;
- `app.css` defines no custom property the copy defines;
- every font `@font-face` names exists and the test host serves it as `font/woff2`.

And in a browser, on the sandbox host: both themes, fonts loaded, no CSP error, no horizontal scroll at
375px, and each page lighting only its own link.

## Revisit when

- the design system ships as a package (`eh-os` D-22) — then both copies are replaced by it;
- the Event Storming palette of the v2 graph is decided;
- the graph screen is made to work under a strict policy (diagrams drawn without inline styles);
- the founders decide about the marks;
- a host needs the dashboard to follow its own theme switch, which would be the first new host-side
  instruction and a change to driver 5.
