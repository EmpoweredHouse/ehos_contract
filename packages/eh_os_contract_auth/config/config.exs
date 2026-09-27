import Config

# Only this package's own suite reads this file: a path dependency's configuration
# is never loaded by the application that pulls it in.

# The engine's repo is the one this package writes to, as it is at a consumer.
config :eh_os_contract, repo: EhOsContract.Auth.TestRepo

config :eh_os_contract_auth, ecto_repos: [EhOsContract.Auth.TestRepo]

config :eh_os_contract_auth,
  issuer: "https://ehos.test",
  audience: "rehmed/test"

config :eh_os_contract_auth, EhOsContract.Auth.TestRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "eh_os_contract_auth_test",
  priv: "priv/test_repo",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
