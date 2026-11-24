import Config

# The switch, as config/dev.exs sets it, here in a file a release reads.
config :ehos_contract_auth,
  development: true,
  issuer: "https://ehos.test",
  audience: "clinic/dev"

config :ehos_contract, applications: [:development_release]

config :logger, level: :error
