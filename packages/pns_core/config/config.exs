import Config

# Only the package's own suite reads this file. A path dependency's configuration
# is never loaded by the application that pulls it in, so nothing here can reach
# a consumer — which is the property that makes it safe for the engine to
# configure itself as its own first consumer.

config :pns,
  ecto_repos: [PNS.TestRepo],
  # The engine scans the binary that actually runs, and here that binary is its
  # own: the invented fixtures compile into `:pns` under `test/support/`. This is
  # the one place where a library naming itself is correct rather than the silent
  # failure `PNS.Registry.load!/1` warns about.
  applications: [:pns],
  repo: PNS.TestRepo,
  auth_verifier: PNS.Auth.LocalToken

config :pns, PNS.TestRepo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  database: "pns_core_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :pns, Oban,
  repo: PNS.TestRepo,
  queues: [events: 10],
  testing: :manual

config :pns, PNS.Auth.LocalToken, secret: "test-only-secret-not-for-production"

config :logger, level: :warning
