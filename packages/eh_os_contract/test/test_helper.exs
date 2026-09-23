# The engine's suite, standing alone. Nothing here loads a client application,
# and that is the point of the file: if `mix test` in this directory passes, the
# seam between the engine and whoever uses it is real rather than declared.

# `:known_defect` marks a test that asserts what the engine **should** do and does
# not. Excluded by default so the gate stays green on a defect that is recorded
# rather than fixed; run it deliberately with
#
#     mix test --include known_defect
#
# The alternative — deleting the test and describing the defect in prose — is how a
# gap stops being checkable. A tagged red test is the only form of a known defect
# that turns green by itself when somebody fixes it.
ExUnit.configure(exclude: [:known_defect])

{:ok, _} = EhOsContract.TestRepo.start_link()
{:ok, _} = Oban.start_link(Application.fetch_env!(:eh_os_contract, Oban))

# The same two calls a host makes at boot, for the same reason: the graph comes
# from the binary that actually runs, and the deployment row records what that
# binary declared. `EhOsContract.DataCase` deletes the row inside the sandbox, because it
# was written outside one.
EhOsContract.Registry.load!()
EhOsContract.Deployment.record!()

Ecto.Adapters.SQL.Sandbox.mode(EhOsContract.TestRepo, :manual)

ExUnit.start()
