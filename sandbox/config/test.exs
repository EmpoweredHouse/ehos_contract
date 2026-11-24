import Config

config :ehos_contract_host, EhosContractHost.Repo,
  database: "ehos_contract_host_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# A second database for the tests the sandbox cannot host: dispatches racing over
# one consistency boundary need real commits (`EhosContractHost.CommitRepo`, which
# `test_helper.exs` drops and creates afresh before every run). Named after this
# checkout, since every worktree's tests use the same Postgres and a run dropping
# the database another is using would break that one.
config :ehos_contract_host, EhosContractHost.CommitRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "ehos_contract_host_test_commits_#{:erlang.phash2(__DIR__)}",
  # Ten members racing for one copy, and the test reading after them. The sandbox's phase of the gate then holds
  # 22 of Postgres's 100 connections; the engine's phase holds 70 on its own.
  pool_size: 12

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :ehos_contract_host, Oban, testing: :manual

# The same for the engine's subscriptions: no runner starts and the boot registers
# nothing, so a test drains them itself (`EhosContract.Testing.drain/1`).
config :ehos_contract, subscriptions: :manual

# `EhosContract.Auth.Testing` pins its test key in the running key store; only here.
config :ehos_contract_auth, pin_keys: true

# `server: false` — Phoenix.ConnTest/Phoenix.LiveViewTest dispatch straight
# into the plug pipeline, no listening socket needed.
config :ehos_contract_host, EhosContractHostWeb.Endpoint,
  server: false,
  http: [port: 4001]

config :logger, level: :warning

# The same for the test database, a key of its own (`EhosContract.Vault`).
config :ehos_contract, EhosContract.Vault,
  keys: [{"sandbox-test-2026-09", "u+W3CGlDJWesQODZ3d76HCOB24UM3/Y4tY009lASskw="}]
