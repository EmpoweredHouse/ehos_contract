import Config

# Only this package's own suite and asset build read this file — a path dependency's
# configuration is never loaded by the application that pulls it in.

config :eh_os_contract_graph, EhOsContract.GraphRenderer.TestEndpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("g", 64),
  live_view: [signing_salt: "eh-os-contract-graph-test-salt"],
  server: false

config :phoenix, :json_library, JSON

config :logger, level: :warning

# `mix assets.build`. Two profiles, as in packages/eh_os_contract_web, so each output
# lands flat in priv/static/. The script is an ES module a host's own bundle imports,
# not minified: the host minifies its bundle, and a diff of this one stays readable
# where it is ours. The vendored libraries come in through relative imports, so no
# NODE_PATH is needed.
config :esbuild,
  version: "0.25.0",
  eh_os_contract_graph: [
    args:
      ~w(js/eh_os_contract_graph.js --bundle --format=esm --target=es2022 --outfile=../priv/static/eh_os_contract_graph.esm.js),
    cd: Path.expand("../assets", __DIR__)
  ],
  eh_os_contract_graph_css: [
    args:
      ~w(css/eh_os_contract_graph.css --bundle --outfile=../priv/static/eh_os_contract_graph.css),
    cd: Path.expand("../assets", __DIR__)
  ]
