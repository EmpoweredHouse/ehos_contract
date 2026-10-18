import Config

config :eh_os_contract_host, EhOsContractHost.Repo,
  database: "eh_os_contract_host_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# A second database for the tests the sandbox cannot host: dispatches racing over
# one consistency boundary need real commits (`EhOsContractHost.CommitRepo`, which
# `test_helper.exs` drops and creates afresh before every run). Named after this
# checkout, since every worktree's tests use the same Postgres and a run dropping
# the database another is using would break that one.
config :eh_os_contract_host, EhOsContractHost.CommitRepo,
  username: "eh_os",
  password: "eh_os",
  hostname: "localhost",
  port: 5433,
  database: "eh_os_contract_host_test_commits_#{:erlang.phash2(__DIR__)}",
  # Ten desks and the manager at once. The sandbox's phase of the gate then holds
  # 22 of Postgres's 100 connections; the engine's phase holds 70 on its own.
  pool_size: 12

# Jobs do not run by themselves. The tests check that a job was inserted in the
# same transaction, and run it explicitly.
config :eh_os_contract_host, Oban, testing: :manual

# The same for the engine's subscriptions: no runner starts and the boot registers
# nothing, so a test drains them itself (`EhOsContract.Testing.drain/1`).
config :eh_os_contract, subscriptions: :manual

# `EhOsContract.Auth.Testing` pins its test key in the running key store; only here.
config :eh_os_contract_auth, pin_keys: true

# `server: false` — Phoenix.ConnTest/Phoenix.LiveViewTest dispatch straight
# into the plug pipeline, no listening socket needed.
config :eh_os_contract_host, EhOsContractHostWeb.Endpoint,
  server: false,
  http: [port: 4001]

config :logger, level: :warning

# The same for the test database, a key of its own (`EhOsContract.Vault`).
config :eh_os_contract, EhOsContract.Vault,
  keys: [{"sandbox-test-2026-09", "u+W3CGlDJWesQODZ3d76HCOB24UM3/Y4tY009lASskw="}]
