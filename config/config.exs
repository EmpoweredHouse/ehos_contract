import Config

config :pns_prototype,
  ecto_repos: [Taxvision.Repo],
  # PNS czyta repo z konfiguracji, nie referencją do modułu — dzięki temu
  # pakiet nie zależy od aplikacji klienta w czasie kompilacji.
  repo: Taxvision.Repo,
  # Szew tożsamości: implementacja weryfikatora jest wymienna. Dziś lokalny
  # HMAC, docelowo `oidcc` przeciw kupionemu providerowi. Kod domenowy nie
  # wie, która to jest.
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
  # Sekret dev-only. Prawdziwy provider nie oddaje sekretu do podpisu —
  # silnik waliduje podpis publicznym kluczem z JWKS i nie umie wystawić tokenu.
  secret: "dev-only-secret-nie-do-produkcji"

import_config "#{config_env()}.exs"
