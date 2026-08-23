import Config

# Only this package's own suite reads this file — a path dependency's
# configuration is never loaded by the application that pulls it in, the
# same property packages/pns_core/config/config.exs relies on.

# `@verifier` in PNS.Auth is keyed under :pns, not :pns_web — whoever the
# top-level project is at the time PNS.Auth compiles must set this.
config :pns, auth_verifier: PNS.Auth.LocalToken
config :pns, PNS.Auth.LocalToken, secret: "pns-web-test-only-secret"

# The accounts screen (PLAN.md, dopisek 23 sierpnia (3)) calls PNS.Auth's
# admin-side functions, which need this key just as strictly as
# auth_verifier does — same compile_env!, same reason.
config :pns, identity_admin: PNS.Auth.LocalIdentityAdmin

# The contract status screen (PLAN.md, dopisek 23 sierpnia (2)) calls straight
# into PNS.Registry/PNS.Conformance, the same functions `mix pns.report`
# already calls — so this package needs the same two keys any consumer of
# `:pns` needs: which application holds the contracts (its own test fixture,
# under test/support), and which repo answers for them.
config :pns, applications: [:pns_web], repo: PNS.Web.TestHost.Repo

config :pns_web, ecto_repos: [PNS.Web.TestHost.Repo]

config :pns_web, PNS.Web.TestHost.Repo,
  username: "pns",
  password: "pns",
  hostname: "localhost",
  port: 5433,
  database: "pns_web_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves — same reason packages/pns_core sets this.
config :pns, Oban, repo: PNS.Web.TestHost.Repo, queues: [events: 10], testing: :manual

config :pns_web, PNS.Web.TestHost.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "pns-web-test-salt"],
  pubsub_server: PNS.Web.TestHost.PubSub,
  server: false,
  http: [port: 4102]

config :logger, level: :warning

# `mix assets.build` — the JS pipeline (PLAN.md, dopisek 23 sierpnia (4)).
# NODE_PATH points at deps/ so `import {Socket} from "phoenix"` resolves
# against the hex packages already in this build, the same trick every
# `mix phx.new` app uses — no npm, no node_modules, esbuild is a downloaded
# binary that reads plain ES modules.
# Two profiles, not one multi-entry build: esbuild names multi-entry
# output after each file's path relative to the lowest common ancestor —
# `js/app.js` + `css/app.css` would land at `assets/js/app.js` and
# `assets/css/app.css`, not the flat `assets/app.js`/`assets/app.css` the
# layout links to.
config :esbuild,
  version: "0.25.0",
  pns_web: [
    args: ~w(js/app.js --bundle --minify --target=es2022 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  pns_web_css: [
    args: ~w(css/app.css --bundle --minify --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__)
  ]
