# Invented test material: the release's application, which lists the development mode's child,
# or `EhosContract.Auth`, whose keys `pin_keys: true` would let a test pin.
defmodule DevelopmentRelease.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children =
      if Application.get_env(:ehos_contract_auth, :pin_keys),
        do: [EhosContract.Auth],
        else: [EhosContract.Auth.Development]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
