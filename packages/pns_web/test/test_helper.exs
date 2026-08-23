{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: PNS.Web.TestHost.PubSub},
      PNS.Web.TestHost.Endpoint
    ],
    strategy: :one_for_one
  )

ExUnit.start()
