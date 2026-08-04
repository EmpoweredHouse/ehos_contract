import Config

config :pns_prototype, Taxvision.Repo,
  database: "pns_prototype_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Joby nie wykonują się same. Testy sprawdzają, że job został wstawiony
# w tej samej transakcji, i uruchamiają go jawnie.
config :pns_prototype, Oban, testing: :manual

config :logger, level: :warning
