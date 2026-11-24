import Config

# Only this package's own suite reads this file — a path dependency's
# configuration is never loaded by the application that pulls it in, the
# same property packages/ehos_contract/config/config.exs relies on.

# The contract status screen calls straight
# into EhosContract.Registry/EhosContract.Conformance, the same functions `mix ehos_contract.report`
# already calls — so this package needs the same two keys any consumer of
# `:ehos_contract` needs: which application holds the contracts (its own test fixture,
# under test/support), and which repo answers for them.
config :ehos_contract, applications: [:ehos_contract_web], repo: EhosContract.Web.TestHost.Repo

config :ehos_contract_web, ecto_repos: [EhosContract.Web.TestHost.Repo]

config :ehos_contract_web, EhosContract.Web.TestHost.Repo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "ehos_contract_web_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Jobs do not run by themselves — same reason packages/ehos_contract sets this.
config :ehos_contract, Oban,
  repo: EhosContract.Web.TestHost.Repo,
  queues: [events: 10],
  testing: :manual

config :ehos_contract_web, EhosContract.Web.TestHost.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "ehos-contract-web-test-salt"],
  pubsub_server: EhosContract.Web.TestHost.PubSub,
  server: false,
  http: [port: 4102],
  # Without this, an unhandled error masks itself as "no html template
  # defined for EhosContract.ErrorView" — see EhosContract.Web.TestHost.ErrorHTML's moduledoc.
  render_errors: [formats: [html: EhosContract.Web.TestHost.ErrorHTML], layout: false]

config :logger, level: :warning

# `mix assets.build` — the JS pipeline.
# NODE_PATH points at deps/ so `import {Socket} from "phoenix"` resolves
# against the hex packages already in this build, the same trick every
# `mix phx.new` app uses — no npm, no node_modules, esbuild is a downloaded
# binary that reads plain ES modules.
# Two profiles, not one multi-entry build: esbuild names multi-entry
# output after each file's path relative to the lowest common ancestor —
# `js/app.js` + `css/app.css` would land at `assets/js/app.js` and
# `assets/css/app.css`, not the flat `assets/app.js`/`assets/app.css` the
# layout links to.
# `esbuild` is a `:dev` dependency, so it is configured only there.
if config_env() == :dev do
  config :esbuild,
    version: "0.25.0",
    ehos_contract_web: [
      args: ~w(js/app.js --bundle --minify --target=es2022 --outdir=../priv/static/assets),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ],
    # The fonts are not an input: `mix assets.build` copies them from ehos_design
    # to where the built stylesheet's relative url()s point, priv/static/assets/fonts/,
    # and --external keeps esbuild from resolving (and failing on) those urls.
    ehos_contract_web_css: [
      args: ~w(css/app.css --bundle --minify --external:*.woff2 --outdir=../priv/static/assets),
      cd: Path.expand("../assets", __DIR__)
    ]
end
