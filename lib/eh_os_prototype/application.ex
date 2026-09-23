defmodule EhOsPrototype.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [EhOsContract, Taxvision, EhOsPrototypeWeb]

  @impl true
  def start(_type, _args) do
    children = [
      Taxvision.Repo,
      {Oban, Application.fetch_env!(:eh_os_prototype, Oban)},
      {Phoenix.PubSub, name: EhOsPrototypeWeb.PubSub},
      EhOsPrototypeWeb.Endpoint
    ]

    result =
      Supervisor.start_link(children, strategy: :one_for_one, name: EhOsPrototype.Supervisor)

    # The registry scan at boot. The graph comes from the binary that actually
    # runs — not from a file beside it.
    EhOsContract.Registry.load!()

    # Recording the deployed version: what is declared and since when it applies.
    # Without it, history cannot be separated from drift for **paths**, because
    # `version/0` hashes the contract while paths come from handlers.
    EhOsContract.Deployment.record!()

    result
  end
end
