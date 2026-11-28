# The application manifest

EHOS deploys an image of the application with its *manifest*. The manifest is the `ehos.yaml` of
the application, with what its contracts offer added. This page is for a developer who writes
`ehos.yaml` and generates the manifest in CI. It tells what `mix ehos_contract.manifest` reads,
what it writes, and what it refuses. The [glossary of the
engine](https://github.com/EmpoweredHouse/ehos_contract/blob/main/packages/ehos_contract/docs/glossary.md)
defines each word of the contract language that this page uses.

`ehos.yaml` tells EHOS what the workload needs: a database, the routes that it serves, its health
checks, and more. EHOS alone defines its format. The words of the platform, such as *installation*,
*environment* and *role binding*, are the words of EHOS.

## Generate the manifest

Run the task in CI, beside the build of the image:

```bash
mix ehos_contract.manifest --output ehos.manifest.json
```

| Option | What it takes |
| --- | --- |
| `--output <file>` | where the task writes the manifest. Required. It must not be the `ehos.yaml` that the task reads. |
| `--ehos-yaml <file>` | the `ehos.yaml` to read. Without it, the task reads `ehos.yaml` in the directory of the project. |

The task compiles the project and reads the domains and contracts of
`config :ehos_contract, applications:`. It writes the manifest as JSON and prints
`written: <file>`.

To write the bundle that EHOS takes with the image, run the other task into an empty directory:

```bash
mix ehos_contract.bundle --output-dir bundle
```

The bundle has three parts:

- `ehos.manifest.json`, the same manifest;
- `graph/`, each graph document of the application, as `mix ehos_contract.graph --output-dir`
  writes them;
- `bundle.json`, the index, which names each file with its size and its SHA-256.

The task refuses a directory that is not empty, so an old graph document does not go with the
bundle. It checks the index against the schema of EHOS for `ehos.bundle/v1`, which the package
carries unchanged. It also checks the two rules that EHOS keeps beside that schema:

- the graph documents have 33554432 bytes or fewer in all;
- each path is in the index one time, in any case of its letters.

If EHOS would refuse the bundle, the task gives each reason and removes the files that it wrote.

## Which version does the task write?

The `schema` of `ehos.yaml` gives the version of the manifest:

| `ehos.yaml` | What the version adds to `ehos.yaml` | Manifest |
| --- | --- | --- |
| `ehos.yaml/v1` | — | `ehos.manifest/v2` |
| `ehos.yaml/v2` | `sign_in` | `ehos.manifest/v2` |
| `ehos.yaml/v3` | `needs.people` | `ehos.manifest/v3` |
| `ehos.yaml/v4` | `needs.database.seed`, `needs.secrets` | `ehos.manifest/v4` |
| `ehos.yaml/v5` | `needs.egress` | `ehos.manifest/v6` |
| `ehos.yaml/v6` | `needs.mail` | `ehos.manifest/v7` |
| `ehos.yaml/v7` | `needs.compute` | `ehos.manifest/v8` |
| `ehos.yaml/v8` | `kind`, `needs.services` | `ehos.manifest/v9` |

If the contracts publish an event or subscribe to one, the task writes `ehos.manifest/v10`, for
each version of `ehos.yaml`. [Events](#events) tells what v10 adds.

If a role may grant another role, an `ehos.yaml` before v5 makes an `ehos.manifest/v5`. From
`ehos.yaml/v5`, the version is the one in the table, with a grant rule or without one. A domain
without a grant rule keeps the version and the digests of its manifest.

An EHOS refuses a manifest of a version that is newer than its own.
`EhosContract.Auth.Manifest.schemas/0` lists each version that the task can write.

## How does the task read `ehos.yaml`?

The task reads the file as EHOS reads it. So it refuses each file that the reader or the schema of
EHOS refuses. EHOS can still refuse a manifest for a rule that the task does not check, as the list
below tells.

- **The file has 64 KiB or less.**
- **The file has only what JSON can hold.** The task refuses each of these: an anchor, an alias, a
  tag, a directive, a second document, and a number such as `.inf`. It also refuses a key that is
  not a string, and a key two times in one mapping.
- **Plain values follow the core schema of YAML 1.2.** So `yes` and `on` are strings, not `true`.
- **The file must agree with the JSON Schema of its version.** That schema is the file of EHOS,
  and the package carries it unchanged.

If the file breaks a rule, the task writes no manifest. It gives each reason, with the path of the
value, such as `serves[0].port`, and the line when it knows it.

The task does not check the other rules that EHOS keeps beside its schema. Examples: the names and
the ports in `serves` are unique, the health port is not among them, and each name is in
`needs.secrets` one time. From `ehos.yaml/v8`, each utility service is in `needs.services` one
time. EHOS refuses a break of these rules when it deploys the manifest.

The task checks the rules of `sign_in` after the schema, because `sign_in` alone breaks them:

- `serves` must have an entry `web` with `public: true`. The sign-in returns to it.
- `sign_in.applications` names other applications only, each one time. It must not name the
  `application` of the file, or the domain that the task finds.

> **`ehos.yaml` holds no secret.** EHOS keeps each manifest for good, with each key of
> `ehos.yaml` as you wrote it. That includes each argument of `migrate` and `seed`. The task cannot
> find a secret in the file. The workload gets its secrets from its environment, as `needs.secrets`
> below tells.

## What does the manifest hold?

Each key of `ehos.yaml` but `schema` is in the manifest, at the same path, with the same value. The
task fills in no default value. The task adds these keys:

| Key | What it holds |
| --- | --- |
| `schema` | the version of the manifest, from the table above |
| `ehos_yaml` | the `schema` of `ehos.yaml`, such as `ehos.yaml/v4` |
| `application` | the `name:` of the domain with contracts |
| `offers` | the capabilities and the roles of the contracts, and the events that they publish |
| `needs.subscribes` | the events of other applications that the contracts subscribe to, beside the `needs` of `ehos.yaml` |
| `engine` | `{"name": "ehos_contract", "version": …}`, the version of the engine that wrote the manifest |

`ehos.yaml` must not have `ehos_yaml`, `engine`, `contracts` or `offers`. The task refuses to
overwrite a key of the file.

### `application`

The application is the domain of the contracts:

- If the project has one domain with contracts, the task takes it. A domain without contracts does
  not count.
- If the project has two or more domains with contracts, write `application: <name>` in
  `ehos.yaml`. The task takes the domain with that `name:`.

EHOS takes lowercase letters, digits and dashes for the name of an application. The name starts with
a letter, does not end with a dash, has 63 characters or fewer, and is not `ehos`. The task refuses
a domain with another name. If `application` is `my-shop` and the domain is `name: :my_shop`, the
task finds the domain, refuses its name, and tells you to use `name: :"my-shop"`.

### `offers`

`offers` has two lists, and a third when the contracts publish an event:

- **`capabilities`**: each capability of a command, a query or a recorded event that a human actor
  can use. Each one has its `name`, its `label`, its `principals`, and its kind with its
  declaration: `"command": "record_payment"`, `"query": …` or `"record": …`.
- **`roles`**: each human actor that holds one capability or more, as `<application>.<actor>`, with
  its `label` and its `capabilities`. A role whose actor has `may_grant:` also has `may_grant`: the
  roles that a person with this role can grant through the application.
- **`publishes`**: each event that the contracts publish. [Events](#events) tells what it holds.

An EHOS that does not know the kinds `query` and `record` refuses a manifest that offers them.

These things are not in `offers`, because the manifest has no field for them, and EHOS refuses a
field that it does not know:

- a system actor, and a human actor without a capability;
- the scopes of a capability.

**A scoped capability gets no scope values from EHOS.** The task offers a scoped command or query
as a capability without its scope. A role binding of EHOS has no scope values. So each call through
EHOS to a scoped capability gets `{:error, :unscoped_grant}`. [Narrow a call to the values of a
grant](https://github.com/EmpoweredHouse/ehos_contract/blob/main/packages/ehos_contract/docs/scope.md)
tells what the engine does with scope values.

### Events

The contracts publish events to other applications with `publish`, and take the events of other
applications with `subscribe`. In the manifest, EHOS gets both, and a person who approves the
authority of the application sees both. Each list is in the manifest only when it has an entry:

- **`offers.publishes`** has one entry for each `publish`. The entry has the `name` that the
  library builds, such as `ledger.entry_recorded.v1`, and the `fields` that the event carries.
  Each field has its `name` and its `type`. If the `publish` has `idempotent_on:`, the entry has
  `idempotent_on` too.
- **`needs.subscribes`** has one entry for each event of another application that a policy
  handles. The entry has the `name` of the event, and the `consumers`: the inbox of each contract
  that takes the event, as `<contract id>:inbox:<name>`.

A `subscribe` that no policy handles has no inbox. So the task leaves it out.

The type of a field is the type that the contract declares, as text. EHOS compares the type and
shows it, but does not read it:

| Declared type | `type` in the manifest |
| --- | --- |
| `:decimal` | `decimal` |
| `{:id, :invoice}` | `id` |
| `{:list, :string}` | `{:list, :string}` |
| `{:enum, [debit: "Debit", credit: "Credit"]}` | `{:enum, [:credit, :debit]}` |

For a ledger that publishes an entry recorded, and takes the invoices that billing issues in two
contracts:

```json
{"offers": {"publishes": [
  {"name": "ledger.entry_recorded.v1",
   "fields": [{"name": "amount", "type": "decimal"}, {"name": "entry_id", "type": "id"}],
   "idempotent_on": ["entry_id"]}]},
 "needs": {"subscribes": [
  {"name": "billing.invoice_issued.v1",
   "consumers": ["ledger.audit:inbox:issued_invoice", "ledger.books:inbox:invoice_issued"]}]}}
```

The manifest does not say if a field can be absent. `ehos_contract.lock` holds each publication to
its fields at its version, so a subscriber keeps what it reads.

### What the manifest does not hold

The manifest has no `contracts`. EHOS counts it in the digest of the authority of the application.
The version of a contract changes with each edit, a label too. So each edit would make each
deployment ask for `ehos.application.register`. `engine` is in the digest of the manifest only.

## What does the task refuse in the contracts?

The task raises, and tells what to change, in these cases:

- no domain is registered;
- no domain has contracts, or two or more do and `ehos.yaml` names none of them;
- the domain that `application` names has no contracts;
- `application` names no domain, or two or more domains match it and none of them has exactly that
  `name:`. A domain with exactly that `name:` wins over one whose `_` reads as `-`;
- the name of the domain is not a name that EHOS takes;
- two contracts declare the same capability;
- the name of a command, a query, a recorded event or a role has more than 63 characters;
- the label of one of them is empty;
- no human actor holds a capability;
- `ehos.yaml` says `kind: service`. A utility service has no contract, so a project with contracts
  is an application. Remove `kind: service`, or write `kind: application`;
- `needs.services` names the application of the manifest. An application is not a utility service;
- more than 100 events are published, or more than 100 are subscribed to;
- a published event carries more than 100 fields, or more than 20 inboxes take one event;
- the name of an event has more than 255 characters, the name of a field more than 63, or the
  type of a field more than 255;
- a contract subscribes to an event of its own application, or to an event under `ehos`;
- a contract subscribes to an event of a publisher whose name is not a name that EHOS takes for an
  application;
- an event is published two times, or under the name of another application;
- the type of a field has a character that is not printable ASCII;
- a contract of another domain in the project publishes an event, or subscribes to one that a
  policy handles. The image runs
  the events of each contract that it configures, and the manifest names the events of one
  application.

A grant rule, `may_grant:` on an actor of the domain, has its own refusals:

- a system actor has a rule;
- an actor with a rule holds no capability, so it is no role;
- a rule names the actor itself, names an actor two times, or names an actor that is not a person
  of the domain;
- a rule names a person who holds no capability;
- rules make a cycle: a person could grant their own role through another role.

[Let a person grant a role](grants.md) tells how to write a rule.

## The keys of each version of `ehos.yaml`

### `ehos.yaml/v1`

```yaml
schema: ehos.yaml/v1
needs:
  database:
    engine: postgres
    version: ">= 16"
    migrate: [/app/bin/migrate]
serves:
  - name: web
    port: 4000
    public: true
health:
  port: 4001
  ready: /health/ready
  live: /health/live
```

### `sign_in`, from `ehos.yaml/v2`

`sign_in` tells EHOS that people sign in to the application. The manifest carries it as you wrote
it, `{}` too:

```yaml
schema: ehos.yaml/v2
serves:
  - name: web
    port: 4000
    public: true       # the sign-in returns here, so sign_in needs it
sign_in: {}            # this application only; or applications: [billing] for others its pages call
health:
  port: 4001
  ready: /health/ready
  live: /health/live
```

With `sign_in`, EHOS gives the workload a client: `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE`.
EHOS also gives the client for `needs.people` and for `needs.mail`. Only `sign_in` makes EHOS give
`EHOS_SIGN_IN_APPLICATIONS`. [Sign people in through EHOS](sign-in.md) tells the rest.

### `needs.people`, from `ehos.yaml/v3`

`needs.people: read` asks EHOS to let the workload read the people of the company. EHOS lets it
read after a person who manages people agrees. [Read the people of the company](people.md) tells
how.

### `needs.database.seed` and `needs.secrets`, from `ehos.yaml/v4`

```yaml
schema: ehos.yaml/v4
needs:
  database:
    engine: postgres
    migrate: ["/app/bin/migrate"]
    # Run after the migration in an ephemeral environment only, never in production; idempotent.
    seed: ["/app/bin/seed"]
  secrets:
    - name: smtp_password
    - name: gus_api_key
      version: 2
```

`needs.secrets` names each secret and holds no value:

- People set each value in EHOS, for an environment, or as the default of an environment template
  for its ephemeral environments.
- EHOS refuses a deployment while a secret that it names has no value there.
- The workload gets each secret as an environment variable, with the name in upper case:
  `smtp_password` becomes `SMTP_PASSWORD`. `config/runtime.exs` reads it.
- Without `version`, the workload gets the newest value, and a new value restarts the workload.
  With `version`, it gets that version, also after a person sets a new value.
- EHOS refuses a name that it gives each workload, or that the runtime reads. Examples: `ehos_*`,
  `database_*`, `phx_*`, `secret_key_base` and `path`.

### `needs.egress`, from `ehos.yaml/v5`

```yaml
schema: ehos.yaml/v5
needs:
  egress:
    - host: registry.example.org      # port 443 when left out
    - host: mail.example.net
      port: 587
```

Each host is a DNS name in lowercase. It is not an address, and not a pattern such as
`*.example.org`. The manifest carries the list as you wrote it: a port that you left out stays out.

The hosts are part of the authority of the application in EHOS. A deployment that adds, removes or
changes a host asks for `ehos.application.register`, as a new role does. At deployment, EHOS also
refuses these hosts, which the task does not check:

- a host that only a network inside answers, such as `*.svc.cluster.local`;
- a host and port that the list names two times.

[Call a host outside the installation](egress.md) tells how the application sends the call.

### `needs.mail`, from `ehos.yaml/v6`

```yaml
schema: ehos.yaml/v6
needs:
  mail:
    level: internal                     # or external, to any address as well
    reply_domains: [reply.office.example.org]
```

The manifest carries `needs.mail` as you wrote it. Each reply domain is a DNS name in lowercase,
not an address or a pattern. At deployment, EHOS also refuses a domain that the list names two
times, and a domain that only a network inside answers. The task does not check these.

The key grants nothing. EHOS sends mail only after a person agrees, for each environment. [Send
mail](mail.md) tells how the application sends it.

### `needs.compute`, from `ehos.yaml/v7`

```yaml
schema: ehos.yaml/v7
needs:
  compute:
    cpu: 500m                           # a request; EHOS sets no CPU limit
    memory: 1Gi                         # the request, and the most each container may use
```

The manifest carries `needs.compute` as you wrote it: `1Gi` stays `1Gi`. EHOS gives the values to
the container that serves, to the migration and to the seed. A key that you leave out takes the
default of the environment.

`needs.compute` is not part of the authority of the application. A change needs only the right to
deploy. At deployment, EHOS refuses a memory below `16Mi`, and a deployment that is larger than the
quota of its environment.

### `kind` and `needs.services`, from `ehos.yaml/v8`

A *utility service* is a workload with no contract, such as a converter that makes a PDF from the
XML of an invoice. EHOS deploys it to an environment as it deploys an application. The
applications of that environment call it. `kind` tells EHOS if the workload is an application or a
utility service. `needs.services` names the utility services that an application calls:

```yaml
schema: ehos.yaml/v8
kind: application                       # or leave it out: a file without kind is an application's
needs:
  services:
    - name: invoice-pdf
    - name: address-check
```

The manifest carries `kind` only when you write it, and `needs.services` as you wrote it, in the
same order. EHOS reads a manifest without `kind` and a manifest with `kind: application` as two
versions of one authority.

`needs.services` grants nothing. The application calls a utility service in an environment only
after a person agrees there. A change needs only the right to deploy.

The task writes no manifest for a utility service. The file of a utility service says
`kind: service` and names the service in `application`. The schema refuses keys that a utility
service cannot have: `needs.database`, `needs.people`, `needs.mail`, `needs.services`, `sign_in`,
and `public: true` in `serves`. The task refuses `kind: service` in a project with contracts.

## The readers of the file are not in a release

The task reads `ehos.yaml` with `yamerl` and validates it with `JSV`. Both are `runtime: false`, so
a release of the application has neither of them.

## Next steps

- [Configure the package](configuration.md): the configuration that the workload reads from its
  environment at run time.
- [Let a person grant a role](grants.md): the `may_grant:` rule of an actor.
- [Sign people in through EHOS](sign-in.md): what the application does with `sign_in`.

<!-- Decisions behind this page:
EHOS's decisions this package follows:
- ehos.yaml is EHOS's format, versioned by JSON Schema;
- ehos.manifest/v2, ehos.yaml extended with what the contracts offer;
- sign_in in ehos.yaml/v2, and applications naming only the others;
- a capability names its declaration's kind, command, query or record;
- contracts left out of the manifest, so an edit does not ask for registration;
- a utility service, an application with no contract, and the services an application calls;
- scope values on a role binding, which EHOS decided but does not issue yet: lib/ehos/grants.ex
  of eh-os says so, and no credential it issues carries scp (#561).
-->
