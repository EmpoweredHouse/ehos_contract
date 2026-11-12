# Changelog

The rule this package follows is the one written in `packages/eh_os_contract/CHANGELOG.md`: a
change a consumer can see gets a line here, in its own pull request.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Every change a user of this package can see gets a line under `## [Unreleased]`, in its own pull
request.** A user is a host application's developer: what they see is the package's public API, its
Mix tasks, what it writes, what it verifies and what the dashboard reports; its tests, docs and CI
are not. A pull request with no such line says why on a line of its description,
`No changelog: <why>`, and CI's Changelog check (`.github/workflows/changelog.yml`) fails it
otherwise. A line for a breaking change, one a host has to act on when it upgrades, starts with
`**Breaking:**`, under the subsection it belongs to.

This package keeps its own version; the repository's tag, `vX.Y.Z`, is the engine's, and one tag
releases each package whose version has left `-dev`, at its own version; the others stay unreleased at
that tag, though `release.json` lists their versions. Between releases the version in `mix.exs` ends in `-dev`;
at a release, a package with lines under `## [Unreleased]` moves to its next version. Every release
moves the engine, whose version the tag is: a release of other packages alone moves it by a patch
from its last release, and that version's section says so under `### Changed` ("Released with
eh_os_contract_auth 0.1.1; nothing in the engine changed."). The maintainers make a release by
their release procedure, and pushing the tag publishes it (`.github/workflows/release.yml`).

## [Unreleased]

## [0.13.0] - 2026-11-12

### Added

- **A development mode signs a person in on a developer's computer, where no EHOS runs** (#619).
  With `config :eh_os_contract_auth, development: true` in `config/dev.exs` and the new child
  `EhOsContract.Auth.Development` after `EhOsContract.Auth`, the application makes an Ed25519 key at
  start, keeps it in memory, and signs a credential for a person with the actors of the domain that
  the developer chooses: `sign_in/3` writes a browser session, and `credential/3` answers a bearer
  credential. The mode renews a session's credential when it expires, and a restart signs every
  session out and sends the browser to `/dev/sign-in`. The mode refuses to start unless Mix is
  started with a project loaded and the environment `:dev`, neither `RELEASE_NAME` nor
  `RELEASE_ROOT` is set, neither `EHOS_ISSUER` nor `EHOS_AUDIENCE` is set, and none of `sign_in:`,
  `workload:` and `people:` is configured. `forward "/dev", EhOsContract.Auth.Development.Router` in
  the router's `dev_routes` block mounts the page `/dev/sign-in`, where the developer chooses the
  actors and scope values, and the endpoint `/dev/credential`, from which `mix
  eh_os_contract.dev.credential` gets a credential, with the token in `EH_OS_CONTRACT_DEV_TOKEN`.
  The router answers only a request from a loopback address, with a `Host` of `localhost`,
  `127.0.0.1` or `[::1]`, and the token the mode prints at start; mount it after the block's other
  `/dev` routes. `EhOsContract.Auth.Keys.pin/2` admits the mode's own key outside a test, and no
  other, and trusts one such key at a time, so a restart of the mode leaves the old key untrusted;
  `pin_keys` does not start the mode. Without the switch, the child starts
  nothing. `docs/development.md` says how to set it up.

## [0.12.0] - 2026-11-05

### Changed

- **Breaking:** **the engine is required at `~> 0.14.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.
- **The README starts as an overview, and three pages take its first sections** (#517). The README
  says what the package does and lists its parts. `docs/getting-started.md` takes "Installation" and
  "Wiring it", with the result of each step. `docs/credential.md`, a Reference page, takes "The
  credential" and "Over HTTP". `docs/decisions.md` takes "Deciding, and recording every decision".
  Hexdocs shows the three pages. The pages and the doc of `EhOsContract.Auth.Plug` now say that
  `www-authenticate` is `Bearer error="invalid_token"` for a refused credential. The pages also say
  that a recorded event gets a decision row too, and that `verify/2` does not read `iat` or `jti`.
  They say which scope values a row records as `NULL` and which as a digest, that a host's own
  Authorizer that refuses first leaves no row, and that a rollback of the caller's transaction
  removes the record of a refusal. The retention example now deletes in batches. Links change: `#installation`, `#wiring-it`,
  `#deciding-and-recording-every-decision`, `#over-http` and `#the-credential` of the README are
  now the three pages. The other sections of the README stay, and move in later pull requests.
- **Seven how-to pages take the README's sections on signing in, the people, mail, grants, calls
  outside the installation and the stand-ins** (#517). `docs/sign-in.md` has a diagram of the sign-in,
  configures `sign_in:` and starts its child only where EHOS gives `EHOS_SIGN_IN_APPLICATIONS` (#454),
  as the doc of `EhOsContract.Auth.SignIn` now does too, since EHOS also gives its client to an
  application that only reads the people or sends mail, and says how to protect a host's own routes
  behind the session from forgery: `same_site: "Lax"` on the cookie with `secure: true`,
  `protect_from_forgery` for the host's routes, and none in front of `EhOsContract.Plug` (#570).
  `docs/call-another-application.md`, `docs/people.md`, `docs/mail.md`, `docs/grants.md`,
  `docs/egress.md` and `docs/without-ehos.md` take the other sections. The pages now say that
  `may_grant:` is written in the domain, that the grant example covers every `delivery`, that
  `in_reply_to:` and `references:` take lists, that a people cursor also carries `state:`, which
  errors a mail call gives in which case, that the egress plugin raises for a request that uses only
  HTTP/2 also without `EHOS_EGRESS_PROXY`, and that the check against a stand-in in a release knows
  only the six stand-ins of the package. Links change: `#calling-a-host-outside-the-installation`,
  `#signing-people-in`, `#reading-the-companys-people`, `#sending-mail`, `#a-person-granting-a-role`
  and `#people-grants-and-mail-where-ehos-does-not-answer` of the README are now these pages.
- **The README is only the overview: four pages take its last sections** (#517).
  `docs/configuration.md` lists each key, each option of the child and each variable EHOS gives
  the workload; `docs/keys.md`, with a diagram, says where the keys come from and how the key
  process keeps them; `docs/testing.md` takes the host's tests; `docs/manifest.md` takes the
  manifest and the bundle. The pages and the docs of `EhOsContract.Auth.Keys` and
  `EhOsContract.Auth.Testing` now say that `pin_keys: true` belongs in `config/test.exs` alone, and
  list what the line unlocks (#560); the line under "Security" says what the package now checks.
  The doc of `EhOsContract.Auth.Manifest` says that no role binding in EHOS carries scope values
  yet, so a scoped capability called through EHOS gets `:unscoped_grant` (#561). The
  pages also say that a key EHOS removed stays trusted while the application cannot reach EHOS,
  which global Req options reach the fetch of the keys, and that `EHOS_CA_FILE` goes to the
  sign-in and the workload too. The manifest page says
  that EHOS gives its client for `needs.people` and `needs.mail` too, not only for `sign_in`. Links
  change: the README's `#generating-the-ehos-application-manifest` is now `docs/manifest.md`,
  `#configuration-from-ehoss-environment` is `docs/configuration.md`, `#in-a-hosts-tests` is
  `docs/testing.md`, and `#where-the-keys-come-from-and-what-to-configure-at-integration` is
  `docs/keys.md` and `docs/configuration.md`.
- **`docs/configuration.md` says what `SSLKEYLOGFILE` does to the application** (#591). Finch, the
  client under Req, writes the TLS secrets of a pool with `keep_secrets: true` to the file that the
  variable names, and the application does not start if Finch cannot open the file. The package does
  not check the variable, so keep it out of production.

### Fixed

- **With `SSLKEYLOGFILE` set, the package opens the file when a pool starts, not on each call to
  EHOS** (#595). The package starts one Finch pool for each set of connection options, and its calls
  go through it. Before, each call asked Req for a pool, and Finch opened the file again and did not
  close it, so a long-running application ran out of file descriptors. A pool that stops and starts
  again still leaves the files of the old pool open (#607). A `connect_options:` or `finch:` in
  `config :req, default_options` still does not get to the calls of the package. The package now
  starts an application of its own, which holds the pools. While that application is not started, as
  with `runtime: false` on the dependency, the key process cannot fetch the keys and refuses every
  credential with `:no_keys`, and the calls of the sign-in fail.
- **`Keys.pin/2` waits up to 10 seconds for the key process** (#591). The process can be in a fetch
  of the keys, such as the first one after it starts, which can take 5 seconds. Before, `pin/2`
  waited 5 seconds, so `Testing.credential/3` or `Testing.sign_in/3` could exit with a timeout. It
  now waits as long as `Keys.refresh/1` does.

### Security

- **Breaking:** **Test keys and plugs are trusted only where Mix's environment is `:test`** (#591).
  Before, the package checked only that `config :eh_os_contract_auth, pin_keys: true` was set. With
  the line in `config.exs` or `runtime.exs`, code in a release could trust keys and answers that
  EHOS did not give. Now `Keys.pin/2`, the `Testing` helpers and stand-ins, and the `plug:` option
  of each child also need Mix's environment to be `:test`, as in `mix test`, read when they are
  called. A release without the `:mix` application has no environment of Mix. A release that
  starts `:mix` takes the environment from `MIX_ENV`, so keep the line out of every release's
  configuration. A suite that runs `mix test` under another environment, such as `MIX_ENV=ci`,
  loses the test key and the stand-ins: run it under `:test`.
  `EhOsContract.Auth`, `EhOsContract.Auth.SignIn` and `EhOsContract.Auth.Workload` do not start
  when `pin_keys: true` is set and Mix's environment is not `:test`. Move the line to
  `config/test.exs`. `EhOsContract.Auth.Workload` now takes `plug:` only under the same rule, as
  the other two do. A `plug:` or `adapter:` in `config :req, default_options` still answers in
  place of EHOS in every environment, and a `plugins:`, `unix_socket:` or `finch_request:` there
  changes where its requests go (#601): keep it out of every configuration but the tests'.

## [0.11.0] - 2026-11-01

### Security

- **Breaking:** `eh_os_contract_auth` requires `jsv` `~> 0.26.2`, not `~> 0.25.0`. 0.26.2 fixes
  EEF-CVE-2026-117680 (CVE-2026-117680, GHSA-cvmg-hgv6-jqcp), which fails a host's `mix hex.audit` while
  its lock holds 0.25.0. `jsv` checks only the host's own `ehos.yaml` and bundle as it builds, and a release
  holds none of it. When a regex runs out of its backtracking budget, under `pattern`,
  `patternProperties` or `not`, validation now stops with one error, `indeterminate_pattern`, even
  where the value would match; 0.25.0 read it as no match. After 0.25.0, `jsv` also counts `minLength`
  and `maxLength` in code points (0.26.2) and reads `date-time` as RFC 3339 says (0.26.1). A host runs
  `mix deps.update jsv`, and removes any `ignore_advisories:` entry it added for this advisory (#543).

## [0.10.0] - 2026-10-29

### Added

- `EhOsContract.Auth.Mail.deliver/1` takes `idempotency_key:`, sent as EHOS's `Idempotency-Key`
  header, so a call answered `:outcome_unknown` can be made again with the same key and mails no
  one twice: for 24 hours EHOS answers a repeat with what the first call sent. Three new errors
  say why a repeat sent nothing: `:idempotency_key_reused`, `:idempotency_key_in_progress` and
  `:idempotency_key_abandoned`. EHOS 0.23.0 or later reads the key (#482).

### Changed

- **Breaking:** **the engine is required at `~> 0.13.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.

## [0.9.0] - 2026-10-27

### Added

- **Mail where EHOS does not answer** (#477), as #475 did for people and grants: the behaviour
  `EhOsContract.Auth.Mail.Sender`, which `Mail` implements; `Mail.sender/0`, which reads
  `config :eh_os_contract_auth, mail_sender:` at each call and otherwise chooses EHOS's when
  `workload:` is configured and `Mail.Unconfigured`, answering `:unavailable`, when not;
  `Mail.Local`, which sends nothing and answers every message as taken, for development; and
  `Testing.Mail` with `stub_mail/1`, which tells a host's test each message as
  `{:ehos_mail, message}`. `sender/0` raises when it names `Mail.Local` or `Testing.Mail` while
  `workload:` is configured, and `Testing.Mail` needs `pin_keys: true`.

- **People and grants where EHOS does not answer** (#475): the behaviours
  `EhOsContract.Auth.People.Directory` and `EhOsContract.Auth.Grants.Granter`, which `People` and
  `Grants` implement; `People.directory/0` and `Grants.granter/0`, which read
  `config :eh_os_contract_auth, people_directory:` / `granter:` at each call and otherwise choose
  EHOS's when `workload:` or `sign_in:` is configured and an `Unconfigured` one answering
  `:unavailable` when not; `People.Directory.Static` (the configured people) and `Grants.Local`
  (every grant made) for development; `Testing.People`, `Testing.Grants`, `stub_people/1` and
  `stub_grants/1` for a host's tests, held per test and its processes; and `People.all/1`, every
  page up to `max:`, `{:error, :too_many}` past it. A stand-in never answers for EHOS in a release:
  the choice raises when it names `Static`, `Local` or a `Testing` one while `workload:` or
  `sign_in:` is configured, and the `Testing` ones need `pin_keys: true`.

- **`ehos.yaml/v7` and `ehos.manifest/v8`** (#453), as EHOS 0.21.0 released them.
  `mix eh_os_contract.manifest` reads an `ehos.yaml/v7`, EHOS's file copied byte for byte, whose
  `needs.compute` asks for the CPU (`cpu`, a request) and memory (`memory`, the request and the
  limit) the workload's containers need. It writes an `ehos.manifest/v8` for it, with
  `needs.compute` as written, whether or not a role may grant another; an older file makes the
  manifest it made before. `EhOsContract.Auth.Manifest.schemas/0`, and so what a release produces,
  now ends with `ehos.manifest/v8`, which only an EHOS from 0.21.0 deploys.

- `EhOsContract.Auth.Mail.deliver/1` takes `verify_html: true`, which asks EHOS to refuse the
  message's HTML, as `{:invalid, reasons}`, when it holds a script, a form, a frame, an event
  attribute or an address whose scheme a message does not need, rather than send it; EHOS never
  changes the HTML. It needs EHOS 0.21.0 or later (#469).

- **`mix eh_os_contract.bundle --output-dir <dir>`** writes the bundle EHOS takes with an image:
  `ehos.manifest.json` as `eh_os_contract.manifest` writes it, every graph document in `graph/` as
  `eh_os_contract.graph --output-dir` writes them, and `bundle.json`, which names each file with
  its size and SHA-256. It refuses a directory that holds anything, checks the index
  against EHOS's schema of `ehos.bundle/v1`, carried unchanged in `priv/schemas/ehos.bundle/`, and
  writes nothing EHOS would refuse (#456).

### Changed

- **Breaking:** **the engine is required at `~> 0.12.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.

- **Breaking:** EHOS 0.21.0 and later send `html:` as given, where earlier ones cleaned it of
  scripts and forms. A host that puts a value it did not write into its HTML escapes it, and may
  pass `verify_html: true` as a backstop (#469).

### Security

- **Breaking:** `eh_os_contract_auth` names `jose` itself, `>= 1.11.13 and < 2.0.0`, which it reached
  only through `joken` before: 1.11.13 fixes eight advisories against 1.11.12 (EEF-CVE-2026-65625 to
  EEF-CVE-2026-65632), and this package verifies credentials with it. A host whose lock holds an older
  `jose` runs `mix deps.update jose` (#471).

## [0.8.0] - 2026-10-26

### Added

- **`EhOsContract.Auth.Testing.sign_in/3` and `sign_out/1`**: a host's test signs a browser in without EHOS
  and puts the returned token in its session under `EhOsContract.Auth.Session.session_key/0`, so a page
  behind `EhOsContract.Auth.Session` is tested through the real plug, `Session.actor/2` included, and
  signed out again. Without an `EhOsContract.Auth.SignIn` child, a stand-in that never calls EHOS takes its
  name for the rest of the run, so a test that starts a sign-in child of its own gives it another `name:`.
  The stand-in cannot renew: past the credential's ten minutes, or for another application's credential,
  the session answers `:ehos_unavailable`. `use EhOsContract.Auth.Testing` imports both, so a test module
  defining its own `sign_in/2`, `sign_in/3` or `sign_out/1` beside it renames it or imports with `only:`.

### Changed

- **Breaking:** **the engine is required at `~> 0.11.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.
- **Breaking:** `EhOsContract.Auth.Mail.deliver/1` answers `{:error, :outcome_unknown}` when some
  messages may have been sent: any failure of the transport but those below, a timeout even while
  connecting, a failed TLS handshake and an unreachable host included, a 5xx, a 408, or a 200 it
  cannot read. `:unavailable` now means nothing was sent, so the call may be made again: no
  credential, a name that does not resolve, a connection refused, an address that is not https, or
  a refusal EHOS never gives.
  Before, `:unavailable` meant either, and an application could not tell a retry that is safe from
  one that mails someone twice. A host that matches every reason adds `:outcome_unknown`; one that
  retried on `:unavailable` now retries only what was not sent (#451).

### Security

- The warnings `EhOsContract.Auth.Workload`, `EhOsContract.Auth.People` and
  `EhOsContract.Auth.Mail` log when EHOS cannot be reached name only what failed: a transport's
  reason, a TLS alert's name or an exception's module. They printed the whole exception, which,
  raised inside the request, may hold its headers and the credential in them, as
  `EhOsContract.Auth.Grants` already did not (#451).

## [0.7.0] - 2026-10-24

### Added

- **`ehos.yaml/v6` and `ehos.manifest/v7`** (#429), as EHOS 0.20.0 releases them.
  `mix eh_os_contract.manifest` reads an `ehos.yaml/v6`, EHOS's file copied byte for byte, whose
  `needs.mail` asks to send mail through EHOS, to the company's people (`internal`) or to any address
  (`external`), with the domains where the answers arrive. It writes an `ehos.manifest/v7` for it,
  with `needs.mail` as written, whether or not a role may grant another; an older file makes the
  manifest it made before. `EhOsContract.Auth.Manifest.schemas/0`, and so what a release produces,
  now ends with `ehos.manifest/v7`, which only an EHOS from 0.20.0 deploys.

- **Sending mail through EHOS** (#436). `EhOsContract.Auth.Mail.deliver/1` sends a
  message to people in EHOS's directory by their id, or, under an `external` agreement, to any
  address, with HTML and attachments, as the application itself. It answers each recipient's
  `EhOsContract.Auth.Mail.Result`, or why nothing was sent.
- **`EhOsContract.Auth.Workload`**, the process that holds the application's own credential at
  EHOS, which reading the people and sending mail share, configured by
  `config :eh_os_contract_auth, :workload`.

### Changed

- **Breaking:** **the people client's process is registered as `EhOsContract.Auth.Workload`** (#436),
  whichever child starts it. A host that passes `server: EhOsContract.Auth.People`, or looks the
  process up by that name, drops it or names `EhOsContract.Auth.Workload`. Both children have
  that id, so a supervisor given both refuses to start: list one.
- **`:not_asked` from `EhOsContract.Auth.People`** now means the deployment asks for neither the
  people nor mail: one that asks for mail alone is given a credential, and the people API answers
  `:not_agreed` (#436).
- **Breaking:** **the engine is required at `~> 0.10.0`** (#421), however it is fetched: by version from Hex, and also when this
  package comes from git or a path, where Mix now holds the engine's version to it. A host whose engine is older
  than 0.10.0 is refused at `mix deps.get`.

### Deprecated

- **`config :eh_os_contract_auth, :people` and `EhOsContract.Auth.People` as a child** (#436): they
  still start `EhOsContract.Auth.Workload`, and `:people` logs a warning at boot; name the child
  and `:workload` instead. Setting both `:workload` and `:people` is refused at boot.

## [0.6.0] - 2026-10-23

### Added

- **`ehos.yaml/v5` and `ehos.manifest/v6`**, as agreed with EHOS. `mix eh_os_contract.manifest` reads an
  `ehos.yaml/v5`, EHOS's file copied byte for byte, whose `needs.egress` names the hosts outside the installation
  the workload reaches, and writes an `ehos.manifest/v6` for it, whether or not a role may grant another, with
  the hosts as written. An older file makes the manifest it made before. `EhOsContract.Auth.Manifest.schemas/0`,
  and so what a release produces, now ends with `ehos.manifest/v6`, which only an EHOS that accepts it deploys.
- **`EhOsContract.Auth.Egress.attach/1`**, a Req plugin for the client that calls a host outside the
  installation (#415): where EHOS gives `EHOS_EGRESS_PROXY`, an `https` call goes through the application's
  proxy, TLS still verified against the host's own name; a host `NO_PROXY` names, such as EHOS or another
  application, and a plain `http` URL go directly; each redirect is decided again; without the variable it does
  nothing. A request with its own `:finch` pool is refused, since Req cannot give it a proxy, and so is an `https`
  request that speaks HTTP/2 alone, which Mint would open without the proxy.
- **Requires Mint 1.11**, past GHSA-gvrc-75rc-7gj9, GHSA-q95c-ccq6-j5j6 and GHSA-9x8p-qrf4-jq7g, since the plugin
  points it at servers outside the installation.

### Fixed

- **A value of `ehos.yaml` that ends in a line break is refused**, in every version, as EHOS refuses it: an
  application named `ledger` and a newline, a probe path, a secret's, an endpoint's or a host's name. A pattern's
  `$` in EHOS's schema ends the text, and the validator read it as PCRE does, where it matches before a final
  line break; the generator then wrote a manifest EHOS refused at deploy.

## [0.5.0] - 2026-10-21

### Added

- **The manifest carries a role's grant rule**, as agreed with EHOS. A role whose actor has
  `may_grant:` carries `may_grant`, the roles it may grant, and the manifest is then `ehos.manifest/v5`,
  which EHOS accepts from 0.13.0 on. A domain without a rule keeps the version and the
  digests it had. A rule naming an actor that holds no capability, and so is no role, or a rule on such an
  actor, is refused with what to change, and so is, for a domain given as a map, what the domain's `D4` would
  refuse. `EhOsContract.Auth.Manifest.schemas/0` lists `ehos.manifest/v5`.
- **A signed-in person grants and revokes a role their rule lets them give**, as EHOS's grants
  are designed. `EhOsContract.Auth.Grants.grant/3` and `revoke/4`, from the person's request,
  exchange their credential for one to EHOS as the sign-in's client and call EHOS's grant routes, which EHOS
  serves from 0.14.0 on. A grant answers an `EhOsContract.Auth.Grants.Grant`: the person's
  id, whether they were invited or have joined, whether the role was bound now or before, and whether a link was
  mailed; a refusal answers EHOS's code. Nothing is configured beyond sign-in, no credential is kept, and nothing
  is retried.

### Changed

- **The documentation's examples name no client** (the publication programme, PB3, #375). The module docs,
  the README and the older entries of this changelog took their audience, contract and capabilities from a real
  clinic; they now use an invented one (`clinic/production`, `Clinic.Contracts.VisitSettlement`). Nothing a host
  calls changed.

## [0.4.0] - 2026-10-17

### Added

- **`sign_in: absolute_limit`**: how long a session lasts from the person's sign-in at EHOS, in
  seconds, from a minute to 366 days; twelve hours when not given, as before. A host maps it from
  `EHOS_SIGN_IN_ABSOLUTE`, which EHOS gives every workload with its installation's limit, so the session ends
  when EHOS's does; nil is not given, and a value out of range stops the host at boot.

### Fixed

- **Signing in asks EHOS for `max_age` of the session's absolute limit**, so EHOS never returns a sign-in older than the session would accept, and refuses a sign-in older
  than it. With an installation's limit longer than the application's, EHOS gave a code for a sign-in the new
  session refused at once, and the browser went between the page and EHOS without end. An application must run
  this version before its installation raises its limits.

## [0.3.0] - 2026-10-17

### Added

- **`ehos.yaml/v4` and `ehos.manifest/v4`** (#306). `mix eh_os_contract.manifest` reads an
  `ehos.yaml/v4`, EHOS's file copied byte for byte, and writes an `ehos.manifest/v4` for it, so an application
  can name `needs.database.seed`, the command EHOS runs to seed an ephemeral environment, and `needs.secrets`,
  the secrets its workload is given as environment variables. Both are carried as written. A v1 to v3 file
  still makes the manifest it made before. `EhOsContract.Auth.Manifest.schemas/0`, and so what a release
  produces, now ends with `ehos.manifest/v4`, which only an EHOS that accepts it (0.9 and later) deploys.

## [0.2.0] - 2026-10-16

### Removed

- **Breaking:** `mix eh_os_contract.manifest` no longer writes `process` on a capability of `offers.capabilities`,
  because a contract can no longer declare a process (engine, plan DD, stage P2h, eh-os-contract#221). EHOS keeps
  the field optional and reads it nowhere; a consumer that compared a manifest field by
  field finds it gone.

## [0.1.0] - 2026-10-11

### Added

- **`EhOsContract.Auth.Manifest.schemas/0` lists the versions of EHOS's manifest the package writes**
  (EHOS's release procedure, eh-os-contract#275): `["ehos.manifest/v2", "ehos.manifest/v3"]`, what a release of this
  repository says it produces, and what an EHOS has to accept for every manifest `build/3` writes.

- **eh-os-contract#252: the application reads EHOS's people as itself.** `EhOsContract.Auth.People`,
  a child configured with `config :eh_os_contract_auth, people: [client_id:, client_key_file:]`, takes a
  credential with OAuth's client credentials grant and the client key EHOS gives, renews it, and answers `list/1`
  and `get/2` with `EhOsContract.Auth.People.Person`s, or `:not_agreed`, `:not_found`, `:not_asked`,
  `:rate_limited` or `:unavailable`. The README says a person's key is the `sub` sign-in gives, which is their
  `id` here.

- **eh-os-contract#252: `ehos.yaml/v3` and `ehos.manifest/v3`.** The generator reads `ehos.yaml/v3`,
  EHOS's schema copied unchanged, whose `needs.people: read` asks to read the company's people, and writes an
  `ehos.manifest/v3` for it. A v1 or v2 file still gives an `ehos.manifest/v2`.
  - **Action:** none for an application that does not read the people. One that does writes `schema: ehos.yaml/v3`
    and `needs.people: read`, and needs an EHOS that accepts `ehos.manifest/v3`.

- **eh-os-contract#133: the manifest offers queries and recordings.** `mix eh_os_contract.manifest` writes a
  capability for every command, query and recording a human actor may make, each naming its declaration as
  `command`, `query` or `record`, as EHOS names them, and the roles hold them all. Until now a deployed application's
  people were refused every query their pages asked (`missing_capability`) and could record nothing.
  - **Breaking:** an EHOS that does not name capabilities by kind refuses such a manifest (`"query" is not a field of ehos.manifest/v2`);
    deploy EHOS first.

- **EB3b (#78): other applications' credentials.** `Session.credential/3` takes the session (a connection or a
  LiveView's session map) and an application's name in `sign_in: [applications: ...]`, and returns the person's
  credential for that application. It is renewed like the application's own, under the same lease, with the
  application's address as `resource`, and handed out as EHOS issued it, unverified (S8).
  - **New refusal:** `{:error, :refused}` when EHOS answers `invalid_target`. It is remembered for ten minutes,
    and EHOS is not asked again until then. The refresh token is kept, the session goes on, and a credential
    held for that application is dropped.
  - **A name `applications` does not have** raises `ArgumentError`.
  - **Breaking:** the sign-in child refuses to start when an address in `applications` is the application's own
    `address`, since `credential/3` would hand out its own credential as another's.

- **EB3a (#78, #80): renewal.** `Session.actor/2`, and the plug with `assign_actor: true`, renew a credential
  good for less than 30 seconds through EHOS with `Oidcc.Token.refresh/3`. The refresh token is rotated, and the
  newest ID token is kept.
  - **One renewal per session:** a lease on the session's row, taken by one statement on the database's clock
    for 30 seconds, longer than a holder can spend before writing, and released with the write.
    - While it is held, another request uses a credential still unexpired; an expired one waits, for at most 15
      seconds.
    - A lease never released by its holder ends the session instead of being taken over, since that holder may
      have presented the refresh token.
  - **No transaction is held across the call to EHOS.** The call ends after 10 seconds.
  - **What is checked before a renewal is stored,** as the callback checks a sign-in:
    - the credential, by `verify/2`, and of the session's person;
    - the ID token's `sid` and `auth_time`, the sign-in's;
    - a stored expiry past the 30-second margin, bounded by the credential's own `exp`.

    A refusal of `verify/2` for keys this application does not hold yet (`:unknown_key`, `:no_keys`) keeps the
    renewal.

    The callback checks the margin and the `exp` bound too.
  - **What a failure leaves:**
    - `invalid_grant`: the session ends.
    - A timeout, a reset or an error response: the refresh token is kept, the held credential is used while
      unexpired, and the session's other requests do not call EHOS again for 5 seconds.
    - A 2xx response that cannot be used, or that `oidcc` refuses or raises on: the session ends, since the
      rotated token is lost.
    - A lease lost before the write: the session ends.
  - **Keys:** an ID token signed with a key the sign-in child does not hold yet makes it refetch EHOS's keys once.
  - **New refusals:** `{:error, :ehos_unavailable}` and `{:error, :renewal_busy}`. The plug answers both with 503.
  - **Changed:** an expired credential is no longer a redirect to sign in, but a renewal.

- **EB2b (#78): signing a browser in through EHOS and out.**
  - **`EhOsContract.Auth.SignIn.Router`**, forwarded at `/auth/ehos`:
    - `GET /sign-in` redirects to EHOS with PKCE, and answers 503 while EHOS cannot be signed in with;
    - `GET /callback` checks EHOS's `iss`, exchanges the code with `private_key_jwt` only, writes a new session
      and returns to a local `return_to`;
    - `POST /sign-out`, behind CSRF protection, ends the session and redirects to EHOS's end session with
      `id_token_hint` and exactly `address <> "/"`, as EHOS compares it.
  - **`EhOsContract.Auth.Session`**, a plug, lets a signed-in person through with
    `conn.assigns.eh_os_contract_session`. Without a session, or with an expired credential, it redirects a
    browser's navigation to sign in and answers 401 otherwise; any other refusal is 401. With
    `assign_actor: true` it also sets `conn.assigns.eh_os_contract_actor`.
  - **The callback** verifies the credential before signing anyone in, ends the session a signed-in browser
    had, and starts the Plug session empty.
  - **`Session.actor/2`** takes a connection or a LiveView's session map, and verifies the person's credential
    as a bearer one.
  - **Exported** from the package's boundary: `EhOsContract.Auth.Session` and `EhOsContract.Auth.SignIn.Router`.

- **EB2a (#78): where a person signed in through EHOS is kept.** **Migration version 3**: a host adds a
  migration calling `EhOsContract.Auth.Migrations.up(version: 3)`.
  - **Two tables:** `eh_os_contract_auth_sessions` (the browser token's SHA-256, `subject`, `sid`, `auth_time`,
    the lease columns) and `eh_os_contract_auth_session_credentials` (one row per application's address).
  - **Encryption:** the refresh token, the ID token and every credential are stored encrypted with
    XChaCha20-Poly1305. The key is derived from `secret_key_base`, and each ciphertext is bound to its row and
    column. A value that does not decrypt, under a rotated `SECRET_KEY_BASE` for one, ends that session.
  - **Pruning:** sessions past twelve hours from `auth_time` are deleted by the next sign-in, with no job.
  - **`EhOsContract.Auth.SignIn.client_context/1`:** the context `oidcc` calls EHOS with, built from what the
    child holds and the client's key.
  - **The client secret** is now random, made at each start, and never inspected (S6).

- **#83: `ehos.yaml/v2` is read, and its `sign_in` goes into the manifest**.
  - `EhOsContract.Auth.EhosYaml.read/1` takes v1 and v2, each against EHOS's own schema, copied unchanged.
  - **Beside the schema,** as EHOS checks it, `sign_in` is refused without an entry `web` with `public: true`,
    and when its `applications` name the file's own `application`.
  - `mix eh_os_contract.manifest` carries `sign_in` as written, `{}` included, with `ehos_yaml: "ehos.yaml/v2"`, and
    refuses `applications` that name the application it finds.
  - A file whose `schema` is neither version is refused with both named.

- **EB1 (#78): `EhOsContract.Auth.SignIn`, the application's client for signing people in through EHOS**
  (EHOS's sign-in, with OpenID Connect).
  - **Configuration:** a child for the supervision tree, configured by `config :eh_os_contract_auth, sign_in:`
    with `client_id`, `client_key_file`, `address`, `secret_key_base` and `applications`.
  - **What it refuses at boot,** with no secret in the message:
    - a key file that is not exactly the private Ed25519 JWK EHOS gives, a PEM included;
    - an address that is not `https://<host>`;
    - an issuer that is not https;
    - a `secret_key_base` shorter than 64 bytes.
  - **What it holds:** EHOS's discovery document and keys, fetched by the package's own transport, the one
    `oidcc` uses too. That transport goes over https only, follows no redirect, reads at most 64 KiB and ends a
    call after ten seconds.
  - **While EHOS is down:** the child retries from one to thirty seconds and never stops the application.
  - **`provider/1`** refuses a document that lacks the `iss` parameter, PKCE with `S256`, `Ed25519` ID tokens
    or `private_key_jwt`, and one that allows a symmetric ID token algorithm.
  - **New dependencies:** `oidcc ~> 3.9` and `oidcc_plug ~> 0.5.1`. **The package now needs OTP 27.**
  - **Sign-in itself comes later:** the routes, the session and renewal are EB2 and EB3.

- **EH2: `EhOsContract.Auth.EhosYaml.read/1` reads `ehos.yaml` as EHOS reads it**, for the
  manifest v2 to carry its keys unchanged. It refuses what YAML can say and JSON cannot — an anchor or an alias, a
  tag, a directive, a key given twice, a key that is not a string, a second document, `.inf`, an escape past Unicode's
  last code point — and resolves plain
  values by YAML 1.2's core schema, so `yes` is a string, refusing a node `config :yamerl, node_mods:` adds. It keeps
  EHOS's bounds: at most 64 KiB, 256 of `[` and `{`, 16 levels of nesting and 256 entries in a list. Each reason has
  the value's path in EHOS's notation, and its line when it is known. New dependencies: `yamerl` and `jsv`, the reader and the validator EHOS uses, both `runtime: false`:
  `ehos.yaml` is read for `mix eh_os_contract.manifest` (EH3), in the application's CI, so neither starts with the
  host or goes into its release. yamerl is held to 0.10.x, whose tokens and nodes the reader matches.

- **EH2: a file that reads is validated against EHOS's own JSON Schema of its version**, copied unchanged into
  `priv/schemas/ehos.yaml/v1.json` (EHOS's file, as of 1 October 2026) and carried in the package. A file without `schema`,
  or with a version the package has no copy of, is refused before any schema reads it; `EhosYaml.versions/0`
  lists those it has. No default is filled in. The rules EHOS checks beside its schema, such as unique names and
  ports in `serves`, are left to EHOS.

- **`mix eh_os_contract.manifest --output PATH`** writes the selected domain's human command
  capabilities and roles as strict `ehos.manifest/v1`. `EhOsContract.Auth.Manifest.build/2` is the same
  projection as data. System actors and actors with no command capability are not roles; query and record
  capabilities wait for a later EHOS manifest schema instead of appearing under fields v1 would reject. If
  two registered modules expose the same public domain name, `--domain` refuses the ambiguity and names both
  modules instead of silently taking the first scan result.

- **The package** (contract v2 §16; the credential's form and the key store as EHOS decided them). `EhOsContract.Auth.verify/1,2`
  turns an EHOS credential — a JWT signed with Ed25519 — into an `EhOsContract.Actor`, or refuses
  it with `:expired`, `:unknown_key`, `:bad_signature`, `:wrong_audience`, `:wrong_issuer` or
  `:no_keys`. `EhOsContract.Auth` is a child for the application's supervision tree that keeps
  EHOS's public keys: loaded from `eh_os_contract_auth_keys` at start, fetched from the JWKS every
  five minutes and early on an unknown `kid`, at most once every thirty seconds, and unchanged by a
  failed fetch — and a redirect, a body over 64 KB or more than 16 keys is a failed fetch. The key set
  must come over `https` (`http` only for `localhost`), or the boot fails. A credential whose `exp` is
  more than fifteen minutes away, or whose header carries `crit`, is `:bad_signature`.
  `EhOsContract.Auth.ready?/0` answers whether any key is held, for the host's
  health check. `EhOsContract.Auth.Migrations` creates the table.

- **`EhOsContract.Auth` is an `EhOsContract.Authorizer`** (`config :eh_os_contract, authorizer:
  EhOsContract.Auth`): `EhOsContract.Authorizer.check/2`'s answer, and one row per decision in
  `eh_os_contract_auth_decisions` — subject, kind, capability, contract and version, the scope
  dimension and value, `allowed` or `refused`, the reason. Migration version 2 creates the table.

- **`EhOsContract.Auth.Plug`** verifies a bearer credential in front of `EhOsContract.Plug`, and
  answers 401 with `no_credential` or the reason `verify/2` refused it.

- **`EhOsContract.Auth.Testing`**: `credential/3` signs with a test key pinned in the running key
  store (`EhOsContract.Auth.Keys.pin/2`), and `assert_every_entry_refuses/3` calls a host's entry
  point for every capability its contracts declare with a credential that lacks it.

### Changed

- **Breaking:** **eh-os-contract#180: the application refuses to start when no domain of its contracts has its name in EHOS,
  or when another domain publishes.** `EhOsContract.Auth.child_spec/1` compares the application in the configured
  `audience` (`"clinic/prod"`, the part before the `/`) with the `name:` of the domains that have contracts in
  `config :eh_os_contract, applications:`. One of them must equal it exactly, and every other one must declare no
  `publish` in any of its contracts. Every name the application publishes begins with its domain's name, and EHOS
  lets an application publish only under the name it registered; a domain that publishes nothing sends
  no name to anyone. A domain named `:my_shop` does not match `"my-shop/prod"`: EHOS never names an application
  with `_`, the manifest generator refuses such a domain, and the message advises renaming it to `:"my-shop"`. The
  check runs whenever the child starts, which already requires an `audience`. An `audience` that is not
  `<application>/<environment>` with both parts non-empty (`"clinic"`, `"/prod"`), one whose application is not a
  name EHOS gives, and a contract whose domain is not loaded, are refused too.
  - **Action:** a host whose domains' names all differ from its application's name in EHOS either renames the
    domain that publishes, which renames every event and every stored contract id, so the event log starts again,
    or has EHOS register the application under that domain's name; a domain named with `_` has only the rename. A host with a second domain that publishes moves
    that domain's contracts to an application of its own, or removes its `publish`.

- **Breaking:** **#178 (plan DD, ID4): a decision names the contract by its `id:`.** `eh_os_contract_auth_decisions.contract`
  holds `"clinic.visit_settlement"` where it held `"Clinic.Contracts.VisitSettlement"`, as every row of the engine
  does from ID4, so moving a contract's module no longer splits its authorization history. It comes from
  `EhOsContract.Authorizer.Request.contract_id`, new and set by the engine on every request, so this package needs
  an `eh_os_contract` from #178 on: against an older one every `authorize/2` raises.
  - **Breaking:** rows written before name the module. The decisions table is the authorization audit trail and
    survives the engine's reset (ID3, ID4): keep it, and read the two forms apart, or map each module to its id
    with one `UPDATE` per contract.

- **#71: `refresh_every:` and `refetch_at_most_every:` below five seconds are refused at boot**, by
  `EhOsContract.Auth.child_spec/1` and `EhOsContract.Auth.Keys.start_link/1`, as is a value that is not whole
  milliseconds, and both intervals now count from the end of the fetch before, not its start. A shorter interval,
  or one counted from the start, let fetches follow one another, each asked for by an unknown `kid`. The defaults
  are unchanged.

- **EH3: `mix eh_os_contract.manifest` writes `ehos.manifest/v2`, and v1 is gone** (EHOS deploys only
  v2). The task reads the project's `ehos.yaml` (`--ehos-yaml` names another), refuses it with every reason as EHOS
  would, and writes it extended with `application`, `offers` and `engine`: every key but `schema` unchanged, `schema`
  as `ehos_yaml`, no default filled in. `offers` holds v1's capabilities and roles. `contracts` is not written while
  EHOS counts it in the authority digest. **`--domain` is removed:** a project with more than one
  domain names the image's in `ehos.yaml`, as `application: <name>`. A domain whose `name:` EHOS does not take for an
  application — with `_`, longer than 63 characters, or `ehos` — is refused, with the name to use. A key of
  `ehos.yaml` the generator writes is refused rather than overwritten, as agreed with EHOS.
  A command or a role's actor past 63 characters, or with an empty label, is refused, each named: the engine takes
  them, EHOS does not. Only domains with contracts are counted when `ehos.yaml` names none.
  `EhOsContract.Auth.Manifest.build/3` takes the read `ehos.yaml`, the domains and the contracts; `build/2` is gone.

- **E12c: `assert_every_entry_refuses/3` asks for no entry for `<name>.subscribe`.** The engine derives that
  capability for an event a contract consumes from another application and a policy handles; it is the
  application's, in no person's credential, and has no door. A map that names it now fails the check as a key
  the contracts do not declare.

- **E11: the manifest reads `EhOsContract.Registry.contracts/0`**, the engine's one list of contracts from its
  0.3.0; `Manifest.build/2` raises "has no contracts" for a domain with none.

- **`cacertfile:` or `cacerts:` names an internal certificate authority, in place of
  `req_options:`**, which is gone. `req_options` handed the host all of Req's options, so
  `connect_options: [transport_opts: [cacertfile: …]]` dropped the fetch's two-second connect
  timeout to Mint's thirty seconds, and `redirect: true` or `verify: :verify_none` quietly undid
  what the key set is trusted by. The fetch's options are now the package's, with the host's
  authority beside the two seconds. An option the key process does not take — `req_options:`
  among them — fails the boot. `url:` in `EhOsContract.Auth`'s child options, which replaced the
  address after its https check, is refused, and `EhOsContract.Auth.Keys.start_link/1` checks
  the address itself, so a key process listed directly is held to https too. `plug:`, for tests,
  needs `config :eh_os_contract_auth, pin_keys: true`.

### Fixed

- **eh-os-contract#186 (plan DD, P1b): a capability names a process only when its contract has one.** The
  manifest generator stopped with an error on a contract without a process; it now leaves `"process"` out of that
  contract's capabilities. EHOS keeps the field optional and reads it nowhere.
  - **Note:** until EHOS takes `process` out of its authority digest, the first deploy in which a
    capability loses its `"process"` counts as an authority change and needs `ehos.application.register`. Nothing
    in this release removes one; a contract that later drops its process does.

- **#66: a scope value the decisions table cannot hold is recorded as its digest.** A value as sent that holds a
  NUL (`%00` in a query string, JSON's `"\u0000"`), is not valid UTF-8 (from a caller of `call/3` or `dispatch/3`
  directly: Plug refuses it in a query string), is past 256 bytes, or starts `sha256:` is written to
  `eh_os_contract_auth_decisions.scope_value` as `sha256:<hex>`. Until now Postgres refused the insert, and any
  holder of a credential could turn a refusal into a 500. The decision is `check/2`'s as before, and every other
  value is recorded as it was asked for.
  - **Changed:** a credential whose `sub` holds a NUL is `:bad_signature`. No text column holds it, and the
    subject names the actor in every row.

- **#71: `EhOsContract.Auth.Keys.refresh/1` answers instead of exiting** when the key process does not answer in
  ten seconds (`{:error, :timeout}`) or is not running (`{:error, :not_running}`).

- **#71: the key process waits for a locked `eh_os_contract_auth_keys` at most a second.** Reading and writing
  the table run with Postgres's `statement_timeout` of one second, which ends a wait for a lock too, and the client
  gives up on any call after two; a fetched key set goes into memory before the table. A table held by a migration
  or `VACUUM FULL` no longer keeps the start, or the early fetch a new `kid` asks for, past the ten-second call: the
  read or write fails, is logged, and the keys from EHOS are in force anyway.

- **`up/1` and `down/1` run what the host's migration queued before them first**, as the engine's do: a
  `CREATE SCHEMA` queued ahead of them left the version to be read in `public`, and with `search_path:
  "ledger, public"` nothing was created in `ledger`.

- **The tables work in a schema other than `public`** (issue #51; EHOS gives each application a schema of its own).
  `EhOsContract.Auth.Migrations` read and wrote its version on `public.eh_os_contract_auth_keys` by name, and
  in a schema of the application's own failed or, where `public` had the tables, created nothing. It now
  reads it in `current_schema()`, where the tables are created, as the key store and the decisions table
  already resolved theirs through the connection's `search_path`. The role the application runs as needs
  only `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the tables and `USAGE` on the sequences.

- **A key set fetch that has not finished in five seconds is a failed fetch.** The request timeouts
  bounded each step but not the fetch, so an endpoint sending a byte every few seconds held the key
  process indefinitely: the scheduled refresh stopped, and every credential with an unknown `kid`
  waited the full ten seconds. The deadline is not configurable. An exit or a throw inside the request
  is now a failed fetch too, not a crash of the key process.

### Security

- **The discovery document's endpoints by #89's rule, at the issuer's origin.** A document is held only when each
  endpoint is held to the rule the configured addresses are, and at the issuer's own scheme, host and port, where
  EHOS serves every one. The rule: https, read back as written, a lowercase DNS name, an IPv4 address in its
  dotted form or `::1` as the host, and no user, query or fragment.
  - It covers the browser's authorization and end-session endpoints.
  - It covers **the PAR endpoint**, which `oidcc` posts the client's assertion to whenever the document names one,
    and which was not checked before.
  - The transport holds every call to the same rule, whichever field its address came from.
  - **Breaking:** such a document is not held, and `SignIn.refresh/2` answers
    `{:error, {:endpoints_refused, names}}` in place of `{:not_https, names}`.

- **Breaking:** **#89: addresses are taken only as every parser reads them.** EHOS's rule for its issuer
  (`Ehos.Credentials.check_issuer/1`): the address reads back as written (`URI.new/1`, then
  `URI.to_string/1`), with a lowercase DNS name, an IPv4 address in its dotted form or `::1` as the host, a port
  from 1 to 65535, and no user, query or fragment. It holds for:
  - **the key set's address**, with a path; plain http on `localhost`, `127.0.0.1` and `::1`;
  - **`issuer`**, with no path, in `EhOsContract.Auth.child_spec/1` and in sign-in. The child checks it at boot
    even when `jwks_url` is set, since it is compared with each credential's `iss` as a string; an `issuer:`
    given to `verify/2` or a plug is not checked. Sign-in still takes https only;
  - **sign-in's `address` and the addresses in `applications`**.

  An address of another shape now refuses the boot. One such was `http://evil.example\@localhost/...`:
  `URI.parse/1` read its host as `localhost` and passed the loopback exception, while EHOS and a browser read
  its host as `evil.example`. So is an issuer with a path or a trailing slash, which EHOS never publishes. A
  refused address is shown by its scheme, host and port only, as EHOS shows its own, since a user or a query can
  hold a secret.
