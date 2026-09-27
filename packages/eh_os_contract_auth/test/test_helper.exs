# The package's suite, standing alone: no client application, no EHOS. Keys come
# from `EhOsContract.Auth.KeyCase`, which plays EHOS's JWKS endpoint.

{:ok, _} = EhOsContract.Auth.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(EhOsContract.Auth.TestRepo, :manual)

ExUnit.start(capture_log: true)
