import Config

# The switch, as config/dev.exs sets it, here in a file a release reads.
config :eh_os_contract_auth,
  development: true,
  issuer: "https://ehos.test",
  audience: "clinic/dev"

config :eh_os_contract, applications: [:development_release]

config :logger, level: :error
