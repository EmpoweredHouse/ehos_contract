{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: EhosContract.Web.TestHost.PubSub},
      EhosContract.Web.TestHost.Endpoint
    ],
    strategy: :one_for_one
  )

{:ok, _} = EhosContract.Web.TestHost.Repo.start_link()
{:ok, _} = Oban.start_link(Application.fetch_env!(:ehos_contract, Oban))

# The same two calls a host makes at boot: the graph comes from the binary
# that actually runs, and the deployment row records what that binary
# declared. EhosContract.Web.TestHost.DataCase deletes the row inside the sandbox,
# because it was written outside one — same reason packages/ehos_contract's own
# DataCase does this.
EhosContract.Registry.load!()
EhosContract.Deployment.record!()

Ecto.Adapters.SQL.Sandbox.mode(EhosContract.Web.TestHost.Repo, :manual)

ExUnit.start()
