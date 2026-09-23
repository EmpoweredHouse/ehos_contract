{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: EhOsContract.Web.TestHost.PubSub},
      EhOsContract.Web.TestHost.Endpoint
    ],
    strategy: :one_for_one
  )

{:ok, _} = EhOsContract.Web.TestHost.Repo.start_link()
{:ok, _} = Oban.start_link(Application.fetch_env!(:eh_os_contract, Oban))

# The same two calls a host makes at boot: the graph comes from the binary
# that actually runs, and the deployment row records what that binary
# declared. EhOsContract.Web.TestHost.DataCase deletes the row inside the sandbox,
# because it was written outside one — same reason packages/eh_os_contract's own
# DataCase does this.
EhOsContract.Registry.load!()
EhOsContract.Deployment.record!()

Ecto.Adapters.SQL.Sandbox.mode(EhOsContract.Web.TestHost.Repo, :manual)

ExUnit.start()
