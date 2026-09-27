import Config

# Only this package's own suite reads this file — a path dependency's
# configuration is never loaded by the application that pulls it in, the
# same property packages/eh_os_contract/config/config.exs relies on.

# The contract status screen (PLAN.md, dopisek 23 sierpnia (2)) calls straight
# into EhOsContract.Registry/EhOsContract.Conformance, the same functions `mix eh_os_contract.report`
# already calls — so this package needs the same two keys any consumer of
# `:eh_os_contract` needs: which application holds the contracts (its own test fixture,
# under test/support), and which repo answers for them.
config :eh_os_contract, applications: [:eh_os_contract_web], repo: EhOsContract.Web.TestHost.Repo

config :eh_os_contract_web, ecto_repos: [EhOsContract.Web.TestHost.Repo]

config :eh_os_contract_web, EhOsContract.Web.TestHost.Repo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "eh_os_contract_web_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves — same reason packages/eh_os_contract sets this.
config :eh_os_contract, Oban,
  repo: EhOsContract.Web.TestHost.Repo,
  queues: [events: 10],
  testing: :manual

config :eh_os_contract_web, EhOsContract.Web.TestHost.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "eh-os-contract-web-test-salt"],
  pubsub_server: EhOsContract.Web.TestHost.PubSub,
  server: false,
  http: [port: 4102],
  # Without this, an unhandled error masks itself as "no html template
  # defined for EhOsContract.ErrorView" — see EhOsContract.Web.TestHost.ErrorHTML's moduledoc.
  render_errors: [formats: [html: EhOsContract.Web.TestHost.ErrorHTML], layout: false]

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
  eh_os_contract_web: [
    args: ~w(js/app.js --bundle --minify --target=es2022 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  # The fonts are not an input: they are committed where the built stylesheet's
  # relative url()s point, priv/static/assets/fonts/, and --external keeps
  # esbuild from resolving (and failing on) those urls.
  eh_os_contract_web_css: [
    args: ~w(css/app.css --bundle --minify --external:*.woff2 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__)
  ]
