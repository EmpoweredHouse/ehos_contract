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
      # Without this entry `use Boundary` is documentation rather than a check.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
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
