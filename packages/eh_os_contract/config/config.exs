import Config

# Only the package's own suite reads this file. A path dependency's configuration
# is never loaded by the application that pulls it in, so nothing here can reach
# a consumer — which is the property that makes it safe for the engine to
# configure itself as its own first consumer.

config :eh_os_contract,
  ecto_repos: [EhOsContract.TestRepo],
  # The engine scans the binary that actually runs, and here that binary is its
  # own: the invented fixtures compile into `:eh_os_contract` under `test/support/`. This is
  # the one place where a library naming itself is correct rather than the silent
  # failure `EhOsContract.Registry.load!/1` warns about.
  applications: [:eh_os_contract],
  repo: EhOsContract.TestRepo

config :eh_os_contract, EhOsContract.TestRepo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  database: "pns_core_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :eh_os_contract, Oban,
  repo: EhOsContract.TestRepo,
  queues: [events: 10],
  testing: :manual

config :logger, level: :warning
