# Invented test material: an application built as a release that carries Mix, with the
# development mode's switch set, or `pin_keys: true`, which `EhosContract.Auth.DevelopmentReleaseTest`
# builds and starts. Its dependencies are this build's own, copied beside it by the test.
defmodule DevelopmentRelease.MixProject do
  use Mix.Project

  def project do
    [
      app: :development_release,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps_path: System.fetch_env!("DEVELOPMENT_RELEASE_DEPS"),
      deps: [{:ehos_contract_auth, path: System.fetch_env!("DEVELOPMENT_RELEASE_AUTH")}],
      releases: [development_release: [include_erts: false]]
    ]
  end

  # `:mix` is added to the release, as a dependency or `extra_applications` can add it.
  def application do
    [mod: {DevelopmentRelease.Application, []}, extra_applications: [:logger, :mix]]
  end
end
