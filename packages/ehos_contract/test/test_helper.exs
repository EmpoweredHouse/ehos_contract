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

{:ok, _} = EhosContract.TestRepo.start_link()
{:ok, _} = EhosContract.CommitRepo.start_link()
:ok = EhosContract.CommitRepo.reset!()
{:ok, _} = Oban.start_link(Application.fetch_env!(:ehos_contract, Oban))

# The same two calls a host makes at boot, for the same reason: the graph comes
# from the binary that actually runs, and the deployment row records what that
# binary declared. `EhosContract.DataCase` deletes the row inside the sandbox, because it
# was written outside one.
EhosContract.Registry.load!()
EhosContract.Deployment.record!()

Ecto.Adapters.SQL.Sandbox.mode(EhosContract.TestRepo, :manual)

ExUnit.start()
