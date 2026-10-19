import Config

config :eh_os_contract_host, ecto_repos: [EhOsContractHost.Repo]

# The database the engine reads the domains' `time_zone:` with (plan W2).
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# The engine is its own application since 2026-08-20, so its configuration is
# keyed by its own name. It reads the repo from configuration rather than
# through a module reference — that is what keeps the package from depending on
# a host application at compile time, and it is why extracting it needed no
# change to the host's trees.
config :eh_os_contract,
  # Which applications hold the contracts. The engine scans the binary that
  # actually runs, and after the extraction it can no longer guess whose binary
  # that is — a library defaulting to its own name scans itself and reports a
  # healthy empty graph.
  applications: [:eh_os_contract_host],
  repo: EhOsContractHost.Repo,
  # Every command and query that arrives with a credential is decided, and recorded,
  # by the credential verifier's package (v2 stage EA).
  authorizer: EhOsContract.Auth,
  # The field the host gives, a return's late fee, and the entity a command reads, a
  # membership card: each domain's stand-in answers for its own.
  supplier: EhOsContractHost.Supplier,
  entities: EhOsContractHost.Entities

# EHOS's address and this application's audience. There is no EHOS beside the
# sandbox, and `.invalid` never resolves (RFC 6761), so the key store logs at boot
# that it has no keys and refuses every real credential; the tests pin a key of
# their own (`EhOsContract.Auth.Testing`). The application is `billing`, as in
# `ehos.yaml` (`application: billing`): of the sandbox's domains only the invented
# `Billing` publishes, so it is the one `EhOsContract.Auth` requires the audience to
# name (#180).
config :eh_os_contract_auth,
  issuer: "https://ehos.invalid",
  audience: "billing/sandbox"

config :eh_os_contract_host, EhOsContractHost.Repo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  pool_size: 10

config :eh_os_contract_host, Oban,
  repo: EhOsContractHost.Repo,
  queues: [events: 10]

# The real host — `server:`/`http:` differ
# per env (config/dev.exs, config/test.exs) so `mix test` never binds a port.
config :eh_os_contract_host, EhOsContractHostWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  # Dev-only — a real deployment generates its own with `mix phx.gen.secret`.
  secret_key_base: String.duplicate("c", 64),
  live_view: [signing_salt: "eh-os-contract-host-live-salt"],
  pubsub_server: EhOsContractHostWeb.PubSub,
  render_errors: [formats: [html: EhOsContractHostWeb.ErrorHTML], layout: false]

import_config "#{config_env()}.exs"
