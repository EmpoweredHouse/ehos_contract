import Config

# Only this package's own suite reads this file — a path dependency's
# configuration is never loaded by the application that pulls it in, the
# same property packages/pns_core/config/config.exs relies on.

# `@verifier` in PNS.Auth is keyed under :pns, not :pns_web — whoever the
# top-level project is at the time PNS.Auth compiles must set this.
config :pns, auth_verifier: PNS.Auth.LocalToken
config :pns, PNS.Auth.LocalToken, secret: "pns-web-test-only-secret"

config :pns_web, PNS.Web.TestHost.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "pns-web-test-salt"],
  pubsub_server: PNS.Web.TestHost.PubSub,
  server: false,
  http: [port: 4102]

config :logger, level: :warning
