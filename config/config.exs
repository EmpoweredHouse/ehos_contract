import Config

config :pns_prototype, ecto_repos: [Taxvision.Repo]

# The engine is its own application since 2026-08-20, so its configuration is
# keyed by its own name. It reads the repo from configuration rather than
# through a module reference — that is what keeps the package from depending on
# a client application at compile time, and it is why extracting it needed no
# change to either client tree.
config :eh_os_contract,
  # Which applications hold the contracts. The engine scans the binary that
  # actually runs, and after the extraction it can no longer guess whose binary
  # that is — a library defaulting to its own name scans itself and reports a
  # healthy empty graph.
  applications: [:pns_prototype],
  repo: Taxvision.Repo

config :pns_prototype, Taxvision.Repo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  pool_size: 10

config :pns_prototype, Oban,
  repo: Taxvision.Repo,
  queues: [events: 10]

config :pns_prototype, Taxvision.Identity,
  # A dev-only secret. A real provider does not hand out its signing secret —
  # the request edge validates the signature with a public key from JWKS and
  # cannot issue a token at all.
  secret: "dev-only-secret-not-for-production"

# The real host (PLAN.md, dopisek 23 sierpnia (8)) — `server:`/`http:` differ
# per env (config/dev.exs, config/test.exs) so `mix test` never binds a port.
config :pns_prototype, PnsPrototypeWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  # Dev-only, same status as Taxvision.Identity's secret above — a real
  # deployment generates its own with `mix phx.gen.secret`.
  secret_key_base: String.duplicate("c", 64),
  live_view: [signing_salt: "pns-prototype-live-salt"],
  pubsub_server: PnsPrototypeWeb.PubSub,
  render_errors: [formats: [html: PnsPrototypeWeb.ErrorHTML], layout: false]

import_config "#{config_env()}.exs"
