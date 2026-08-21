defmodule PNS.MixProject do
  use Mix.Project

  @moduledoc """
  The engine as its own application, extracted on 2026-08-20.

  Until then `boundary` enforced the seam and `README.md` claimed that moving a
  client tree out was `git mv`. Nobody had tried, so the claim was untested —
  extracting this is what tests it, and what the extraction costs is recorded in
  `PLAN.md` rather than smoothed over.
  """

  def project do
    [
      app: :pns,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only read when this project is the top-level one; a path dependency's
      # configuration is never loaded by the application pulling it in. That is
      # what lets the engine be its own first consumer without leaking a repo
      # name, a database or a secret into anybody's build.
      config_path: "config/config.exs",
      # Without this entry `use Boundary` is documentation rather than a check.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # The invented fixtures — the universality gate and the process-shapes rig —
  # belong to the engine and not to any client, so they compile here. They are
  # the material a client-free test suite is built from.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The suite migrates itself with `PNS.Migrations`, so the package is the first
  # consumer of its own migration. Nothing else proves that module as cheaply.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      check: ["compile --force --warnings-as-errors", "pns.check", "test"]
    ]
  end

  defp deps do
    [
      # The log is the engine's own storage, so the persistence dependencies are
      # the engine's — the same shape as Oban, which is also a library that owns
      # tables and ships the migration for them.
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      # Asynchronous handlers cross a process boundary through a queue.
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"},
      # Declared explicitly rather than inherited: a package whose dependency is
      # satisfied only because a neighbour happens to need it breaks when the
      # neighbour goes.
      {:telemetry, "~> 1.3"},
      {:boundary, "~> 0.10", runtime: false},
      # The identity seam's real verifier. Not the active one — see
      # `PNS.Auth.OidcVerifier`.
      {:oidcc, "~> 3.0"}
    ]
  end
end
