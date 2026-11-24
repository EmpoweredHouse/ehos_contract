# Use people, grants and mail where EHOS does not answer

This page tells a developer how the pages of the application read people, grant roles and send mail
where EHOS does not answer. In development there is no EHOS. A release that starts without the
credentials of EHOS must not list people, or tell a person that it invited someone or sent a
message. A test must not call EHOS.

## Prerequisites

- The pages read people, grant roles or send mail: [Read the people of the company](people.md),
  [Let a person grant a role](grants.md), [Send mail](mail.md).

## 1. Ask for the module that answers

On a page, do not call `EhosContract.Auth.People`, `EhosContract.Auth.Grants` or
`EhosContract.Auth.Mail` directly. Ask for the module that answers:

```elixir
{:ok, %{people: people}} = EhosContract.Auth.People.directory().list(q: "ad")
EhosContract.Auth.Grants.granter().grant(conn, email: email, role: "clinic.client")
EhosContract.Auth.Mail.sender().deliver(to: [{:person, id}], subject: subject, text: text)
{:ok, everyone} = EhosContract.Auth.People.all()   # each page, 10,000 people or fewer
```

Each function reads the configuration at each call. When the configuration names no module, it
gives:

| Function | With EHOS configured | Without |
| --- | --- | --- |
| `People.directory/0` | `EhosContract.Auth.People`, when `workload:`, or its older name `people:`, is configured | `EhosContract.Auth.People.Directory.Unconfigured` |
| `Grants.granter/0` | `EhosContract.Auth.Grants`, when `sign_in:` is configured | `EhosContract.Auth.Grants.Unconfigured` |
| `Mail.sender/0` | `EhosContract.Auth.Mail`, when `workload:`, or its older name `people:`, is configured | `EhosContract.Auth.Mail.Unconfigured` |

An `Unconfigured` module answers `{:error, :unavailable}`, which the page already tells in words.
So configure EHOS in `config/runtime.exs` only when EHOS gives the credentials, and name no module
there.

`Grants.granter/0` uses the sign-in child with the name `EhosContract.Auth.SignIn`, and the
default options of `verify/2`.

**Result:** in a release with the credentials of EHOS, the pages use EHOS. In a release without
them, each call answers `:unavailable`.

## 2. Name a stand-in for development

```elixir
# config/dev.exs
config :ehos_contract_auth,
  people_directory: EhosContract.Auth.People.Directory.Static,
  granter: EhosContract.Auth.Grants.Local,
  mail_sender: EhosContract.Auth.Mail.Local

config :ehos_contract_auth, EhosContract.Auth.People.Directory.Static,
  people: [%{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}]
```

**Result:** in development, the pages list Ada, and each grant and each message gets an answer.
Nothing goes to EHOS.

## 3. Name a stand-in for tests

```elixir
# config/test.exs
config :ehos_contract_auth,
  pin_keys: true,
  people_directory: EhosContract.Auth.Testing.People,
  granter: EhosContract.Auth.Testing.Grants,
  mail_sender: EhosContract.Auth.Testing.Mail
```

The `Testing` stand-ins need `pin_keys: true`, as the credentials of `EhosContract.Auth.Testing`
do. Put the line only in `config/test.exs`. If another environment sets it, the children of the
package do not start: [Test the application without EHOS](testing.md).

**Result:** a test gives the answers with `stub_people/1`, `stub_grants/1` and `stub_mail/1` of
`EhosContract.Auth.Testing`. A stub is seen by the process of the test and the processes that it
starts. A stub made in `setup_all` is not seen.

## What does each module answer?

| Module | Answers |
| --- | --- |
| `EhosContract.Auth.People` | the people API of EHOS |
| `EhosContract.Auth.People.Directory.Static` | the people that the configuration lists; nobody by default |
| `EhosContract.Auth.People.Directory.Unconfigured` | `:unavailable` |
| `EhosContract.Auth.Testing.People` | the people that the test gave with `stub_people/1`; nobody by default |
| `EhosContract.Auth.Grants` | the grant routes of EHOS |
| `EhosContract.Auth.Grants.Local` | each grant made and mailed; the id of the person comes from the email |
| `EhosContract.Auth.Grants.Unconfigured` | `:unavailable` |
| `EhosContract.Auth.Testing.Grants` | each grant made, or what the test asked for with `stub_grants/1` |
| `EhosContract.Auth.Mail` | the mail API of EHOS |
| `EhosContract.Auth.Mail.Local` | each message taken and none sent; a log line without the recipients or the content |
| `EhosContract.Auth.Mail.Unconfigured` | `:unavailable` |
| `EhosContract.Auth.Testing.Mail` | each message taken, or what the test asked for with `stub_mail/1`; each message goes to the test as `{:ehos_mail, message}` |

The stand-ins raise `ArgumentError` for the arguments that the modules of EHOS raise for, so
development fails where a release fails.

- `Static` takes maps with `id` and `email`, and optionally `name` and `state` (`:invited`,
  `:joined` by default, or `:disabled`), or an `EhosContract.Auth.People.Person`. It gives all the
  people that match on one page, and ignores `limit:`. It raises for another shape at the first
  call, and the error does not show the values.
- `Grants.Local` refuses a role that is not `<application>.<name>` (`:unknown_role`), and the
  revocation of an id that names nobody (`:not_found`). It grants each other role, also one that
  the application does not declare. Anyone who knows the email can calculate the id of the person,
  so use it only in development.
- `Mail.Local` logs the number of recipients and the message ids. It checks nothing that only EHOS
  checks, such as the level of the agreement or the size, and does not remember an
  `idempotency_key:`.

To give another answer, write a module that implements `EhosContract.Auth.People.Directory`,
`EhosContract.Auth.Grants.Granter` or `EhosContract.Auth.Mail.Sender`, and name it in the
configuration. The function raises if the module does not export the callbacks of the behaviour.

## What can go wrong

**A stand-in never answers for EHOS where the credentials of EHOS are configured.** The function
raises at the first call, not at boot. It raises in each of these cases:

- `directory/0` gives `Static` or `Testing.People` while `workload:` is configured;
- `sender/0` gives `Mail.Local` or `Testing.Mail` while `workload:` is configured;
- `granter/0` gives `Grants.Local` or `Testing.Grants` while `sign_in:` is configured.

So a line of `config/dev.exs` that went into `config/config.exs` by mistake fails. It does not tell
a person that someone was invited or that a message was sent.

Each function checks only its own configuration. For example, a release with `workload:` and
without `sign_in:` accepts `Grants.Local`, which answers each grant as made and mailed. This check
knows only these six stand-ins. In a release without the credentials of EHOS, nothing
refuses them. A module of your own is never refused. Name a stand-in only in `config/dev.exs` and
`config/test.exs`.

## Next steps

- [Read the people of the company](people.md): the people API of EHOS.
- [Let a person grant a role](grants.md): the grant routes of EHOS.
- [Send mail](mail.md): the mail API of EHOS.
