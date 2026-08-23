import Config

config :pns_prototype, Taxvision.Repo,
  database: "pns_prototype_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :pns_prototype, Oban, testing: :manual

# `server: false` — Phoenix.ConnTest/Phoenix.LiveViewTest dispatch straight
# into the plug pipeline, no listening socket needed.
config :pns_prototype, PnsPrototypeWeb.Endpoint,
  server: false,
  http: [port: 4001]

config :logger, level: :warning
