defmodule PNS.MixProject do
  use Mix.Project

  # One source for `project/0` and, through `PNS.version/0`, for the line every
  # conformance report carries. A change that can move a verdict raises the minor
  # version and gets a line in CHANGELOG.md — the rule is written there.
  @version "0.2.0"
  @source_url "https://github.com/EmpoweredHouse/eh-os-prototype"
  @description "Checks that deployed code does what the declared business process says it does."

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
      version: @version,
      name: "PNS",
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
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

  # Mirrors the host's. Without it `mix check` here runs the `test` alias in `:dev`,
  # where `PNS.TestRepo` is not compiled, and fails on `ecto.create` before reaching
  # a single test — which is how this alias stood until 2026-09-22, usable only if
  # you happened to prefix `MIX_ENV=test` yourself.
  def cli, do: [preferred_envs: [check: :test]]

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
      # `hex.build` is deliberately **not** here. It works standalone
      # (`MIX_ENV=test mix hex.build`) and not from inside an alias, and wrapping it
      # in a shell-out for a package nobody has decided to publish yet would be
      # machinery ahead of the decision. `test/package_test.exs` pins the metadata;
      # the tarball is a manual step before a release that has not been scheduled.
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "pns.check",
        "test"
      ]
    ]
  end

  defp package do
    [
      name: "pns",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/pns_core/CHANGELOG.md"
      },
      # Listed explicitly rather than left to the default, which would include
      # `priv/`. The only thing under `priv/` here is this package's own test
      # migration — an artifact of testing the migration module against itself, and
      # nothing a consumer should receive. `LICENSE` is a copy: a package published
      # from a subdirectory does not pick up the repository's, and `licenses:` above
      # is metadata rather than a file.
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
