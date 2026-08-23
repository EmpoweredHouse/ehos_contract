import Config

# Only this package's own suite reads this file — a path dependency's
# configuration is never loaded by the application that pulls it in, the
# same property packages/pns_core/config/config.exs relies on.

# `@verifier` in PNS.Auth is keyed under :pns, not :pns_web — whoever the
# top-level project is at the time PNS.Auth compiles must set this.
config :pns, auth_verifier: PNS.Auth.LocalToken
config :pns, PNS.Auth.LocalToken, secret: "pns-web-test-only-secret"

# The contract status screen (PLAN.md, dopisek 23 sierpnia (2)) calls straight
# into PNS.Registry/PNS.Conformance, the same functions `mix pns.report`
# already calls — so this package needs the same two keys any consumer of
# `:pns` needs: which application holds the contracts (its own test fixture,
# under test/support), and which repo answers for them.
config :pns, applications: [:pns_web], repo: PNS.Web.TestHost.Repo

config :pns_web, ecto_repos: [PNS.Web.TestHost.Repo]

config :pns_web, PNS.Web.TestHost.Repo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  database: "pns_web_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves — same reason packages/pns_core sets this.
config :pns, Oban, repo: PNS.Web.TestHost.Repo, queues: [events: 10], testing: :manual

config :pns_web, PNS.Web.TestHost.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "pns-web-test-salt"],
  pubsub_server: PNS.Web.TestHost.PubSub,
  server: false,
  http: [port: 4102]

config :logger, level: :warning
