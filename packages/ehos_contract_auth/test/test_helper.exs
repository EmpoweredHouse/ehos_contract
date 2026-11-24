# The package's suite, standing alone: no client application, no EHOS. Keys come
# from `EhosContract.Auth.KeyCase`, which plays EHOS's JWKS endpoint.

{:ok, _} = EhosContract.Auth.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(EhosContract.Auth.TestRepo, :manual)

{:ok, _} = EhosContract.Auth.CommitRepo.start_link()
:ok = EhosContract.Auth.CommitRepo.reset!()

ExUnit.start(capture_log: true)
