import Config

config :pns_prototype, Taxvision.Repo,
  database: "pns_prototype_dev",
  show_sensitive_data_on_connection_error: true

config :pns_prototype, PnsPrototypeWeb.Endpoint,
  server: true,
  # 4000 by default, overridable — a developer machine often already has something
  # on it, and a hard-coded port turns "show me the dashboard" into "first find out
  # what else is running".
  http: [port: String.to_integer(System.get_env("PORT") || "4000")]

config :logger, level: :info
