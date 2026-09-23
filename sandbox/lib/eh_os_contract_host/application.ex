defmodule EhOsContractHost.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [EhOsContract, Taxvision, EhOsContractHostWeb]

  @impl true
  def start(_type, _args) do
    children = [
      Taxvision.Repo,
      {Oban, Application.fetch_env!(:eh_os_contract_host, Oban)},
      # After the repo, which it writes the deployment row to, and before the
      # endpoint, whose dashboard reads the registry it loads.
      EhOsContract,
      {Phoenix.PubSub, name: EhOsContractHostWeb.PubSub},
      EhOsContractHostWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EhOsContractHost.Supervisor)
  end
end
