import Config

config :pns_prototype,
  ecto_repos: [Taxvision.Repo],
  # PNS reads the repo from configuration rather than through a module
  # reference — that is what keeps the package from depending on the client
  # application at compile time.
  repo: Taxvision.Repo,
  # The identity seam: the verifier implementation is swappable. Today a local
  # HMAC, eventually `oidcc` against a bought provider. Domain code does not
  # know which one it is.
  auth_verifier: PNS.Auth.LocalToken

config :pns_prototype, Taxvision.Repo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  pool_size: 10

config :pns_prototype, Oban,
  repo: Taxvision.Repo,
  queues: [events: 10]

config :pns_prototype, PNS.Auth.LocalToken,
  # A dev-only secret. A real provider does not hand out its signing secret —
  # the engine validates the signature with a public key from JWKS and cannot
  # issue a token at all.
  secret: "dev-only-secret-not-for-production"

import_config "#{config_env()}.exs"
