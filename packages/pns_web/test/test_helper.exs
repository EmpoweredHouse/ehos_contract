{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: PNS.Web.TestHost.PubSub},
      PNS.Web.TestHost.Endpoint,
      # The accounts screen's own fake (PLAN.md, dopisek 23 sierpnia (3)) —
      # an Agent, so it starts here rather than in PNS.Web.TestHost.DataCase,
      # which is only about the sandboxed repo.
      PNS.Auth.LocalIdentityAdmin
    ],
    strategy: :one_for_one
  )

{:ok, _} = PNS.Web.TestHost.Repo.start_link()
{:ok, _} = Oban.start_link(Application.fetch_env!(:pns, Oban))

# The same two calls a host makes at boot: the graph comes from the binary
# that actually runs, and the deployment row records what that binary
# declared. PNS.Web.TestHost.DataCase deletes the row inside the sandbox,
# because it was written outside one — same reason packages/pns_core's own
# DataCase does this.
PNS.Registry.load!()
PNS.Deployment.record!()

Ecto.Adapters.SQL.Sandbox.mode(PNS.Web.TestHost.Repo, :manual)

ExUnit.start()
