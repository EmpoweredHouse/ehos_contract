import Config

config :eh_os_contract_host, Taxvision.Repo,
  database: "eh_os_contract_host_dev",
  show_sensitive_data_on_connection_error: true

# No `server: true`: `mix phx.server` serves the endpoint anyway, and with it every
# mix task that starts the application (`eh_os_contract.report`, `graph --overlay`,
# `trace`, `subscriptions`) bound a port too, and failed with `:eaddrinuse` whenever
# the dashboard was already running on it.
config :eh_os_contract_host, EhOsContractHostWeb.Endpoint,
  # 4010 by default, overridable — a developer machine often already has something
  # on 4000, another Phoenix application's default, and a hard-coded port turns
  # "show me the dashboard" into "first find out what else is running".
  http: [port: String.to_integer(System.get_env("PORT") || "4010")]

config :logger, level: :info

# The master key of Rehmed's personal fields — a PESEL, the ICD codes (E9). A key
# made for this sandbox's development database and nothing else; a real host reads
# its keys from the runtime environment (`EhOsContract.Vault`).
config :eh_os_contract, EhOsContract.Vault,
  keys: [{"sandbox-dev-2026-09", "pineNKIpeYQWgh3+i0ce+w6ITjYjHEwnd9SwBXbQGUM="}]
