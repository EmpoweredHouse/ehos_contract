# Invented test material: the project a child process of `EhosContract.Auth.DevelopmentTest` loads,
# as `mix phx.server` loads an application's, so that the development mode sees a Mix project.
defmodule DevelopmentFixture.MixProject do
  use Mix.Project

  def project, do: [app: :development_fixture, version: "0.1.0", elixir: "~> 1.18"]
end
