import Config

# Only this package's own suite reads this file: a path dependency's configuration
# is never loaded by the application that pulls it in.

# The engine's repo is the one this package writes to, as it is at a consumer. The
# applications the engine scans are this package's own, which hold no contracts:
# `EhosContract.Auth.child_spec/1` compares the audience with their domains at boot.
config :ehos_contract,
  repo: EhosContract.Auth.TestRepo,
  applications: [:ehos_contract_auth]

config :ehos_contract_auth,
  ecto_repos: [EhosContract.Auth.TestRepo, EhosContract.Auth.CommitRepo]

config :ehos_contract_auth,
  issuer: "https://ehos.test",
  audience: "clinic/test",
  # Test keys may be pinned (`EhosContract.Auth.Keys.pin/2`); nowhere but a test.
  pin_keys: true

config :ehos_contract_auth, EhosContract.Auth.TestRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "ehos_contract_auth_test",
  priv: "priv/test_repo",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# A second database for the tests the sandbox cannot host: renewals on connections of
# their own, and a renewal that must hold no transaction while it calls EHOS (S4). Its
# rows are committed, so `test_helper.exs` migrates it down and up before every run.
config :ehos_contract_auth, EhosContract.Auth.CommitRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "ehos_contract_auth_test_commits",
  priv: "priv/test_repo",
  pool_size: 10

config :logger, level: :warning
