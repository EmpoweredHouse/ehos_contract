defmodule PnsPrototype.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [PNS, Taxvision, PnsPrototypeWeb]

  @impl true
  def start(_type, _args) do
    children = [
      Taxvision.Repo,
      {Oban, Application.fetch_env!(:pns_prototype, Oban)},
      {Phoenix.PubSub, name: PnsPrototypeWeb.PubSub},
      PnsPrototypeWeb.Endpoint,
      # The accounts screen's fake (PLAN.md, dopisek 23 sierpnia (3)) — a
      # config key alone was enough while nothing mounted that screen for
      # real; now something does.
      PNS.Auth.LocalIdentityAdmin
    ]

    result =
      Supervisor.start_link(children, strategy: :one_for_one, name: PnsPrototype.Supervisor)

    # The registry scan at boot. The graph comes from the binary that actually
    # runs — not from a file beside it.
    PNS.Registry.load!()

    # Recording the deployed version: what is declared and since when it applies.
    # Without it, history cannot be separated from drift for **paths**, because
    # `version/0` hashes the contract while paths come from handlers.
    PNS.Deployment.record!()

    result
  end
end
