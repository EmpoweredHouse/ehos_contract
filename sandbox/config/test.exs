import Config

config :eh_os_contract_host, Taxvision.Repo,
  database: "eh_os_contract_host_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :eh_os_contract_host, Oban, testing: :manual

# The same for the engine's subscriptions: no runner starts and the boot registers
# nothing, so a test drains them itself (`EhOsContract.Testing.drain/1`).
config :eh_os_contract, subscriptions: :manual

# `EhOsContract.Auth.Testing` pins its test key in the running key store; only here.
config :eh_os_contract_auth, pin_keys: true

# `server: false` — Phoenix.ConnTest/Phoenix.LiveViewTest dispatch straight
# into the plug pipeline, no listening socket needed.
config :eh_os_contract_host, EhOsContractHostWeb.Endpoint,
  server: false,
  http: [port: 4001]

config :logger, level: :warning
