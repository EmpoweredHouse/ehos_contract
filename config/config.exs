import Config

config :pns_prototype, ecto_repos: [Taxvision.Repo]

# The engine is its own application since 2026-08-20, so its configuration is
# keyed by its own name. It reads the repo from configuration rather than
# through a module reference — that is what keeps the package from depending on
# a client application at compile time, and it is why extracting it needed no
# change to either client tree.
config :pns,
  # Which applications hold the contracts. The engine scans the binary that
  # actually runs, and after the extraction it can no longer guess whose binary
  # that is — a library defaulting to its own name scans itself and reports a
  # healthy empty graph.
  applications: [:pns_prototype],
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

config :pns, PNS.Auth.LocalToken,
  # A dev-only secret. A real provider does not hand out its signing secret —
  # the engine validates the signature with a public key from JWKS and cannot
  # issue a token at all.
  secret: "dev-only-secret-not-for-production"

import_config "#{config_env()}.exs"
