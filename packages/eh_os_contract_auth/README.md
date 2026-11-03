# EhOsContract.Auth

This package connects an application built on
[`eh_os_contract`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract)
to EHOS, the platform that hosts it. This page is for a developer who connects such an application.
It says what the package does, and links to the pages that tell you how to use it.

## What does the package do?

People and systems call the application with a *credential*: a signed token that EHOS issues. The
engine verifies no credential. It asks an *Authorizer* what the actor of a credential can do. This
package is that Authorizer for the credentials of EHOS. The engine does not depend on it.

The package verifies each credential in the application, against the public keys of EHOS. It keeps
the keys in the database of the application. After one fetch succeeds, the application accepts
credentials while EHOS is down, also after a restart. The package then writes a row for each
decision, a refusal too.

The [glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines each word of the contract language that these pages use. The words of the platform, such as
*installation* and *environment*, are the words of EHOS.

## What are its parts?

| Part | What it does |
| --- | --- |
| `EhOsContract.Auth.verify/2`, with the key process `EhOsContract.Auth.Keys` | verifies a credential and gives its actor |
| `EhOsContract.Auth` | the Authorizer of the engine, with a row for each decision |
| `EhOsContract.Auth.Plug` | verifies the bearer token of a request in front of `EhOsContract.Plug` |
| `mix eh_os_contract.manifest` | writes the application manifest that EHOS deploys from |
| `EhOsContract.Auth.SignIn`, `EhOsContract.Auth.Session` | signs people in to the pages of the application through EHOS, and keeps their sessions |
| `EhOsContract.Auth.Workload` | holds the credential of the application itself, for the people and for mail |
| `EhOsContract.Auth.People` | reads the people of the company |
| `EhOsContract.Auth.Mail` | sends mail through EHOS |
| `EhOsContract.Auth.Grants` | lets a person grant a role that their rule lets them give |
| `EhOsContract.Auth.Egress` | sends a call to a host outside the installation through the proxy that EHOS gives |
| `EhOsContract.Auth.Testing` | gives credentials and stand-ins to the tests of the application |

## Next steps

- [Get started](docs/getting-started.md): install the package, configure it, and accept a call with
  a credential.
- [The credential](docs/credential.md): what a credential holds, and when `verify/2` and the plug
  refuse it.
- [How is each decision recorded?](docs/decisions.md): the row for each decision, what it costs, and
  how long to keep it.
- [Sign people in through EHOS](docs/sign-in.md): the pages of the application, with a session for
  each person, and how to protect them from forgery.
- [Call another application as the person](docs/call-another-application.md): the credential of the
  person for another application of the installation.
- [Read the people of the company](docs/people.md): a list of employees for a form.
- [Send mail](docs/mail.md): mail from the application, through EHOS.
- [Let a person grant a role](docs/grants.md): invite a person with a role from a page.
- [Call a host outside the installation](docs/egress.md): the proxy that EHOS gives.
- [Use people, grants and mail where EHOS does not answer](docs/without-ehos.md): the stand-ins for
  development and tests.
- [Test the application without EHOS](docs/testing.md): credentials, a signed-in browser, and the
  check that each entry point refuses.
- [Configure the package](docs/configuration.md): each key, each option of the child, and the
  environment that EHOS gives the workload.
- [Where do the keys come from?](docs/keys.md): how the application trusts the keys of EHOS, and how
  it keeps them.
- [The application manifest](docs/manifest.md): what `mix eh_os_contract.manifest` reads from
  `ehos.yaml`, and what it writes.

<!-- Decisions behind this page:
contract v2 §16, D14 (docs/adr/contract-v2.md): the contract declares who may act; a separate package, this one, verifies who is acting.
EHOS's decisions this package follows:
- the credential, a ten-minute Ed25519 JWT with the key's thumbprint as kid; manual key rotation;
- keys kept in the application's own table; every decision recorded, a refusal as carefully as an acceptance;
- the claims cap and scp, scope values carried in the credential;
- ehos.yaml is EHOS's format, versioned by JSON Schema;
- ehos.manifest/v2, ehos.yaml extended with what the contracts offer;
- EHOS hands the workload its settings in the environment;
- signing a person in through EHOS with OpenID Connect; the callback address;
- the client key as a JWK, addresses as exact strings, an application's address as resource;
- sign_in in ehos.yaml/v2, and applications naming only the others;
- a capability names its declaration's kind, command, query or record;
- contracts left out of the manifest, so an edit does not ask for registration.
S2 (docs/adr/browser-session.md): the browser holds a random token, the row its SHA-256; the cookie session encrypted.
S3 (docs/adr/browser-session.md): EHOS's tokens encrypted, each bound to its row and column.
#89: the issuer and every address read alike by every parser.
-->
