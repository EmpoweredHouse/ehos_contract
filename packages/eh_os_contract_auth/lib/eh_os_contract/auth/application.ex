defmodule EhOsContract.Auth.Application do
  @moduledoc false

  # The package's own processes, which run whatever children a host starts: the Finch
  # pools its calls to EHOS go through (`EhOsContract.Auth.Pools`).

  use Application

  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EhOsContract.Auth.Pools.Supervisor, strategy: :one_for_one},
      EhOsContract.Auth.Pools
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
