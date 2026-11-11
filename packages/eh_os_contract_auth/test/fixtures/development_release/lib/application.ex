# Invented test material: the release's application, which lists the development mode's child.
defmodule DevelopmentRelease.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    Supervisor.start_link([EhOsContract.Auth.Development], strategy: :one_for_one)
  end
end
