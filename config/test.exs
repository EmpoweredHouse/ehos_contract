import Config

config :eh_os_contract_host, Taxvision.Repo,
  database: "eh_os_contract_host_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :eh_os_contract_host, Oban, testing: :manual

# `server: false` — Phoenix.ConnTest/Phoenix.LiveViewTest dispatch straight
# into the plug pipeline, no listening socket needed.
config :eh_os_contract_host, EhOsContractHostWeb.Endpoint,
  server: false,
  http: [port: 4001]

config :logger, level: :warning
