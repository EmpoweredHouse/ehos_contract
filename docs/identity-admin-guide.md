# Managing users, roles and access — a working guide

> The architecture and the open questions live in
> [`adr/identity-seam.md`](adr/identity-seam.md) — this document is the "how", not the "why". Everything
> below was run against a real sidecar on 9 August (`docker-compose.identity.yml`), not copied from vendor
> docs; see that ADR's "PoC findings" for what did not work and is not shown here.

## The model, in short

Full diagrams are in [`adr/identity-seam.md`](adr/identity-seam.md#the-same-three-levels-as-a-graph). The
short version: a **user or group** is assigned a **role**, a role bundles **scopes**, and a scope grants one
action on one **resource** — a definable part of the application. Adding a resource or a role is
configuration in the sidecar. Adding a company-specific rule ("may approve an invoice over 50k") is the one
part that is code, in the engine's own permission engine, not here.

## Vocabulary: our terms vs. Zitadel's

| Our term | Zitadel term | Notes |
| --- | --- | --- |
| The whole product's access surface | **Project** | One project is enough for one engine; do not create a project per resource. |
| Resource ("part of the application") | **Project role** | A role string such as `accounting:approve`. Defined once per project, not per user. |
| Role (bundle of scopes) | A **set of project roles** granted together | Zitadel has no separate "bundle" object — granting several roles at once *is* the bundle. |
| A human who logs in | **Human user** (or federated via an IdP — see the ADR's identity-brokering section) | |
| A service calling another service | **Machine user** | Not a project application. See the ADR finding: client credentials only work against a machine user's own secret. |
| The token claim the engine reads | `roles` (or wherever `OIDC_TOKEN_TYPE_JWT` / the project's role-assertion scope puts it) | `PNS.Auth.OidcVerifier`'s `roles_claim` config option names it. |

## One-time setup

```bash
docker compose -f docker-compose.identity.yml up -d
```

On first boot this also writes a Management API token to `tmp/identity-poc/admin.pat` (gitignored) — no
console login needed for anything below. If you need to start over, `down -v` before `up -d`: the bootstrap
only runs on a fresh instance.

## Recipe: define a resource and a role

A "resource" is a project role string; a "role" a user gets is just the set of those strings granted to them.
Nothing here needs its own project per resource.

```bash
PAT=$(cat tmp/identity-poc/admin.pat)

# Once: the project that stands for the whole engine.
curl -s -X POST http://localhost:8080/management/v1/projects \
  -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d '{"name":"engine"}'
# => note the returned "id" as $PROJECT_ID below

# Once per resource: add it as a project role.
curl -s -X POST "http://localhost:8080/management/v1/projects/$PROJECT_ID/roles" \
  -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d '{"roleKey":"accounting:approve","displayName":"Approve accounting entries"}'
```

## Recipe: a human user, and granting them access

```bash
# Create the user.
curl -s -X POST http://localhost:8080/v2/users/human \
  -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d '{
        "username": "alice",
        "profile": {"givenName": "Alice", "familyName": "Example"},
        "email": {"email": "alice@example.com", "isVerified": true},
        "password": {"password": "ChangeMe1!", "changeRequired": true}
      }'
# => note the returned "userId" as $USER_ID

# Grant the role — this is the "role" in our model, one call per resource
# they need, or several roleKeys in one call for a bundle.
curl -s -X POST "http://localhost:8080/management/v1/users/$USER_ID/grants" \
  -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d "{\"projectId\": \"$PROJECT_ID\", \"roleKeys\": [\"accounting:approve\"]}"
```

Removing access is the same call with a different `roleKeys` list, or
`DELETE /management/v1/users/{userId}/grants/{grantId}` to remove it entirely — there is no separate
"revoke" concept to learn.

## Recipe: verifying a token from the engine side

```bash
ZITADEL_CLIENT_ID=... ZITADEL_CLIENT_SECRET=... \
  MIX_ENV=dev mix run priv/poc/identity_smoke_test.exs
```

See that script's header for where the client id/secret come from, and the ADR's PoC findings for which
token (`id_token`, not the machine-user `access_token`) is the one worth pointing it at today.

## Recipe: a human logging in through a browser

`docker-compose.identity.yml` also runs the login screens (a second container) behind a small Traefik that
puts both containers on one origin — see the ADR's 10 August finding for why that split exists and why one
origin matters. Point a browser at:

```
http://localhost:8080/oauth/v2/authorize?client_id=...&redirect_uri=...&response_type=code&scope=openid&code_challenge=...&code_challenge_method=S256
```

with a real registered `redirect_uri` for an OIDC app (`authMethodType: OIDC_AUTH_METHOD_TYPE_NONE` if the
frontend is a public client using PKCE, which is the normal shape for a browser app — no client secret to
leak). Login happens entirely inside Zitadel's own pages; the frontend never sees a password, only the code
that comes back on its redirect. Where the frontend itself runs — Phoenix, a SPA, anything — is irrelevant to
this: it is a redirect out and a redirect back, not an embed.

## Recipe: adding a field to a user

Zitadel's `human.profile` is a closed schema — `givenName`, `familyName`, `nickName`, `displayName`,
`preferredLanguage`, `gender`, plus email/phone. Nothing else fits there; a custom field sent alongside it is
not stored (verified 11 August, on a throwaway test user — it came back with exactly those fields and nothing
added).

The question is not "how do I add a field" but **whose field it is**:

- **Generic, about the person, no harm in the provider knowing it** (locale, avatar) → Zitadel
  [user metadata](https://zitadel.com/docs/apis/resources/mgmt/management-service-set-user-metadata) — a
  plain key/value store, one call per key:
  ```bash
  curl -X POST "http://localhost:8080/management/v1/users/$USER_ID/metadata/costCenter" \
    -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
    -d "{\"value\": \"$(echo -n 'CC-042' | base64)\"}"
  ```
  Verified working 11 August. Values are base64. Add the `urn:zitadel:iam:user:metadata` scope to a token
  request to have it show up in the token; otherwise it is management-API-only.
- **About this person's relationship to a specific client's business** (department, cost center in *their*
  chart of accounts, an ID from *their* HR system) → **never Zitadel**, metadata included. Putting it there
  makes the provider a second source of truth about the client's company — the exact failure
  [`adr/identity-seam.md`](adr/identity-seam.md) names as the one thing "Users and sessions" must not become.
  This belongs in the **user profile mirror** (technology notes §13: "no credentials, keyed by the identity
  subject") — a local table keyed by the token's `sub`. Not built yet; this is the one piece of the whole
  loop in this guide that still has nowhere to go.

## Not yet true

- **The proxy exists, but not against this sidecar.** `PNS.Auth.IdentityAdmin` and
  `PNS.Web.Live.Accounts` (23 August) are the engine's own API the screen calls instead of the sidecar
  directly (ADR, 9 August) — but the implementation behind that API today is `PNS.Auth.LocalIdentityAdmin`,
  an in-memory fake, not a client for the Management API calls this guide documents. Everything above is
  still the sidecar's Management API, called directly, for this PoC only; wiring a real implementation of
  `PNS.Auth.IdentityAdmin` against it is future work this repository deliberately does not do — see
  `docs/adr/identity-seam.md`'s 23 August note.
- **No domain-rule UI.** Company-specific rules (the third row of the "Three levels" table) live in the
  permission engine, which is not built. This guide only covers the bought half.
