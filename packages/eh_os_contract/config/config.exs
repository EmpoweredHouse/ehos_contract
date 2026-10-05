import Config

# Only the package's own suite reads this file. A path dependency's configuration
# is never loaded by the application that pulls it in, so nothing here can reach
# a consumer — which is the property that makes it safe for the engine to
# configure itself as its own first consumer.

# The time zone database a host configures for its domain's `time_zone:` (plan W2);
# the invented fixtures' ledger keeps the days of Warsaw.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :eh_os_contract,
  ecto_repos: [EhOsContract.TestRepo, EhOsContract.CommitRepo],
  # The engine scans the binary that actually runs, and here that binary is its
  # own: the invented fixtures compile into `:eh_os_contract` under `test/support/`. This is
  # the one place where a library naming itself is correct rather than the silent
  # failure `EhOsContract.Registry.load!/1` warns about.
  applications: [:eh_os_contract],
  repo: EhOsContract.TestRepo,
  # Nothing runs by itself: the tests drain subscriptions and effect jobs in their
  # own sandbox transaction (`EhOsContract.Testing.drain/1`).
  subscriptions: :manual,
  # Plan T1: `SupplyRig` declares fields the host supplies, and a node with such a field
  # and no supplier does not start.
  supplier: SupplyRig.Supplier

# The master key of the invented fixtures' personal fields (`ShreddingRig`). A test
# key, in a file only this package's suite reads; a host's comes from its runtime
# environment (`EhOsContract.Vault`).
config :eh_os_contract, EhOsContract.Vault,
  keys: [{"test-2026-09", "D4NnXLZHJadFxy6qG6IvSNfTuDEXAyDnrH9SBQSjl6U="}]

config :eh_os_contract, EhOsContract.TestRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "eh_os_contract_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# A second database for the tests the sandbox cannot host: concurrent appenders,
# transactions that commit out of order, and migrations run back and forth. Those
# need real commits, and a committed row in the log can never be deleted, so they
# get a database of their own. `test_helper.exs` migrates it down and up again before
# every run, which is what empties it.
config :eh_os_contract, EhOsContract.CommitRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "eh_os_contract_test_commits",
  priv: "priv/test_repo",
  pool_size: 60

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :eh_os_contract, Oban,
  repo: EhOsContract.TestRepo,
  queues: [events: 10],
  testing: :manual

config :logger, level: :warning
