---
owner: operator
status: draft
last_updated: 2026-08-04
source_of_truth: design conversation 2026-08-04
load_policy: reference
related:
  - /decisions/009-pns-runtime-architecture.md
  - ~/Projects/ai/pns_prototype/docs/adr/technology-notes.md
---

> **Przeniesione z repozytorium kontekstu 6 sierpnia 2026, bez zmian w treści.**
>
> Szczegół projektowy stojący za decyzją §16–17 („tożsamość kupiona, za szwem protokolarnym, vendor i
> topologia otwarte"). Sama decyzja jest w rekordzie w repozytorium kontekstu; tutaj jest rozpoznanie
> providerów, ich licencje i lista rzeczy do sprawdzenia w PoC — czyli materiał, którego nie chcemy
> researchować drugi raz.
>
> **Stan implementacji:** szew stoi, weryfikatorem jest lokalny HMAC. Providera nie stawialiśmy — patrz
> `../../README.md`.

# Identity — the boundary, before any decision

No vendor is chosen here, and no topology either. What is worth fixing now is the seam, because the seam is
what keeps every later option open.

## The one rule

**Identity sits behind a protocol seam, wherever it runs. The engine's domain code receives an OIDC discovery
URL, a client id and a client secret, validates a signed token against JWKS, and holds neither credentials nor
the ability to issue tokens.**

That is the whole architectural commitment, and it is deliberately silent on topology. It costs one plug in
the engine (`oidcc`) and a `behaviour` for the handful of user-management calls the admin screen needs.

## Three levels, so "IAM" does not read as one thing

The word covers three questions with three different owners. Worked through on a TaxVision-shaped example —
an accounting API, an HR API, a frontend, and a user-management API — on 4 August.

| | Question | Owner |
| --- | --- | --- |
| Authentication | who is this | Bought |
| Entitlement | may this person reach the accounting API at all | **Bought** — a role grant, carried as a token claim |
| Domain rule | may they approve an invoice over 50k, may they see salaries outside their own department | Ours |

"Employee X has accounting, employee Y has HR only" is the middle row, and it arrives free with any provider:
grant a role, read one claim. No engine is built for it.

The third row is where the value is, and it is already accounted for — technology notes §13 lists *Permission
engine — own dependency, Oban-style migrations*. **The user-management API is therefore thin**: the employee
list is provider users, granting access is a role grant, inviting someone is a provider endpoint. Thickness
there would mean a second source of truth about who works at the company. It thickens only where the rules are
about our domain, which the provider knows nothing about.

The one part of this worth settling early, because it enters every request path: **how a given API learns the
entitlement** — from the token (no network, fresh to within the token lifetime; right for entitlements), from
its own replica updated by an event when a grant changes (right for rules, and consistent with the
event-driven direction), or by calling a shared authorisation service per request. The third turns several APIs
into a distributed monolith where one outage takes all of them down; prefer the first two.

## Two axes, only one of them decided

| Axis | State |
| --- | --- |
| Write or buy the provider | [ADR 009](~/Projects/ai/empowered-house-context/decisions/009-pns-runtime-architecture.md) decided **not written** |
| Where it runs — in-process module, sidecar, separately deployed application, or the client's own service | **Open** |

The seam holds in all four positions on the second axis, which is why it can be fixed before that axis is.

One interaction to watch, because it is the only place the axes touch: *module* is a packaging choice while the
provider is still bought — an OIDC provider running inside the same release unit. *Module* meaning we implement
OIDC ourselves, for instance on `Boruta`, reopens the first axis. That is a write-or-buy decision wearing the
costume of a packaging decision.

## What that rule keeps open, so none of it has to be decided now

| Later decision | Why the rule protects it |
| --- | --- |
| Which provider — Zitadel, Keycloak, something else | Swappable, and swappable *per client*, not per company |
| A client who already runs their own IdP | Becomes a configuration change, not a project |
| Our own login and signup screens | Independent of the seam; a screen choice, not an architecture one |
| SCIM, directory sync, automatic loss of access when someone leaves | Access token lifetime is the lever, and it is a setting |
| Module, sidecar, separate application, or the client's own service | A packaging decision downstream of the seam |

## Provider options, recorded so they need not be researched again

All licences below permit bundling and redistribution, which matters if the component ships with the project
into a client's environment.

| Candidate | Licence | For | Against |
| --- | --- | --- | --- |
| **Zitadel** (Go) | Apache 2.0 | Declarative bootstrap, organizations model, SCIM v2, login shipped as a separate deployable app, light to bundle | Smaller ecosystem and hiring pool |
| **Keycloak** (JVM) | Apache 2.0 | Most battle-tested against corporate IdP quirks, identity brokering, LDAP/AD federation, widest familiarity | Heavy to bundle, upgrades painful, no built-in SCIM server |
| Authentik (Python) | MIT core | Flexible flows, SCIM inbound and outbound | Weaker multi-tenancy, centre of gravity is self-hosters rather than B2B |
| BoxyHQ SAML Jackson | Apache 2.0 | Surgical: SAML-to-OIDC bridge, directory sync, admin portal for the client's IT — the paid part of WorkOS | Not a provider; only relevant if we keep our own auth |
| SuperTokens | Apache 2.0 | OIDC plus multi-tenancy | Reaches SAML through Jackson anyway |
| Ory (Hydra, Kratos) | Apache 2.0 | Strong protocol implementation, API-first | **Ruled out** — no SAML SP, so enterprise SSO fails |
| `Boruta` (Elixir) | — | An in-process OIDC provider, if the seam is ever wanted without a second runtime | Protocol only; no SAML broker, no SCIM, no admin portal. Reopens write-or-buy |

Two off the list, with reasons, so they do not get re-proposed:

**WorkOS** fails on model rather than price. It cannot ship into a deployment that runs in a client's own
environment, and its per-connection pricing lands in cost of goods per client rather than as a fixed tool cost
— wrong shape when every client is one enterprise connection.

**FusionAuth** is source-available with a free community edition, not open source. Worth remembering only
because its pricing is not per connection, so it is the commercial fallback if self-hosting is rejected.

Non-obvious things to verify in a PoC rather than trust from documentation: Zitadel's SCIM v2 coverage, how far
its login application can be restyled, `zitadel_api`'s API-generation coverage (generated gRPC clients lag API
generations; REST via the gRPC gateway is the fallback), and which Google Workspace and Entra ID licence tiers
gate automatic provisioning on the client's side.

## Simplest start

Run any OIDC provider alongside the engine, wire the plug, and move on. Zitadel is the current best guess on
bundling ergonomics and Keycloak on breadth of IdP compatibility — but under the rule above, that guess is
cheap to be wrong about, which is exactly why it does not need settling today. Whether it ends up a module in
the release, a sidecar, or its own deployed application can be answered by the first real client rather than
in advance.

What breaks the rule, and therefore should not happen: a credential store reachable from the engine's domain
code, domain code minting its own tokens, or any vendor name in the engine's configuration schema.

## One thing worth fixing now

[Technology notes §13](~/Projects/ai/pns_prototype/docs/adr/technology-notes.md) lists *Users and sessions —
`phx.gen.auth`, generated*. Read literally that is a credential store inside the engine, which contradicts
identity being separate and produces two answers to whether a person still works at the company. It should
say either "user profile mirror, no credentials, keyed by the identity subject" or nothing.

## Not decided

Vendor, packaging, login screen route, deprovisioning mechanism, who operates the instance. Also
[ADR 009](~/Projects/ai/empowered-house-context/decisions/009-pns-runtime-architecture.md) line 248 still says `WorkOS wrapped`; that becomes
wrong if the deployment ships into the client's environment, but it can be corrected whenever the ADR is next
touched rather than on its own.

Reasoning behind all of the above is in the 4 August conversation; it does not need to be repeated here until
something is actually being decided.
