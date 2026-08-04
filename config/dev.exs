import Config

config :pns_prototype, Taxvision.Repo,
  database: "pns_prototype_dev",
  show_sensitive_data_on_connection_error: true

config :logger, level: :info
