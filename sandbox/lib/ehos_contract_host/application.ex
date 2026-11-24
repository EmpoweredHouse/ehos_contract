defmodule EhosContractHost.Application do
  @moduledoc false

  use Application

  use Boundary,
    top_level?: true,
    deps: [EhosContract, EhosContract.Auth, EhosContractHost.Repo, EhosContractHostWeb]

  @impl true
  def start(_type, _args) do
    children = [
      EhosContractHost.Repo,
      {Oban, Application.fetch_env!(:ehos_contract_host, Oban)},
      # After the repo, which it writes the deployment row to, and before the
      # endpoint, whose dashboard reads the registry it loads.
      EhosContract,
      # After the repo, whose table holds the last key set it saw.
      EhosContract.Auth,
      {Phoenix.PubSub, name: EhosContractHostWeb.PubSub},
      EhosContractHostWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EhosContractHost.Supervisor)
  end
end
