# Invented test material: the release's application, which lists the development mode's child,
# or `EhOsContract.Auth`, whose keys `pin_keys: true` would let a test pin.
defmodule DevelopmentRelease.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children =
      if Application.get_env(:eh_os_contract_auth, :pin_keys),
        do: [EhOsContract.Auth],
        else: [EhOsContract.Auth.Development]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
