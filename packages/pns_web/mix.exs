defmodule PNS.Web.MixProject do
  use Mix.Project

  @moduledoc """
  The dashboard foundation, extracted as its own package from the first commit.

  Mirrors the `packages/pns_core` extraction: this package builds and tests
  standing alone, against its own test host, and never touches `pns_prototype`
  directly. What it does not carry is `ecto_sql`/`postgrex`/`oban` — this
  package owns no tables and runs no jobs, so pulling those in would be
  copying the template rather than mirroring it.
  """

  def project do
    [
      app: :pns_web,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only read when this project is the top-level one; see
      # packages/pns_core/config/config.exs for why that matters here too.
      config_path: "config/config.exs",
      # Without this entry `use Boundary` is documentation rather than a check.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # `mix check` runs the tests, and those need MIX_ENV=test — same trap the
  # root project's mix.exs already documents and works around.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [extra_applications: [:logger]]
  end

  # The test host lives here so this package proves its own mounting
  # mechanism against a host it controls, the same shape as
  # packages/pns_core's test/support fixtures.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      check: ["compile --force --warnings-as-errors", "test"]
    ]
  end

  defp deps do
    [
      # The engine, for PNS.Auth. A path dependency, same shape as the root
      # host's own dependency on it.
      {:pns, path: "../pns_core"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:boundary, "~> 0.10", runtime: false},
      # Endpoint adapter for the test host. `only: :test` because nothing in
      # this package ever starts a real listening socket outside its own
      # suite — see PLAN.md's dopisek on why it might still turn out to be
      # unnecessary.
      {:bandit, "~> 1.5", only: :test},
      # phoenix_live_view's own `live/2` test helper parses the dead-render
      # HTML with this and refuses to run without it — not optional despite
      # not appearing in phoenix_live_view's own dependency tree.
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
