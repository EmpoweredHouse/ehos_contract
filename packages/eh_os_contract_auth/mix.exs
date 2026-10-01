defmodule EhOsContract.Auth.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  @git_url "#{@source_url}.git"
  @description "Verifies EHOS credentials and authorizes EhOsContract commands, recordings and queries."

  @moduledoc """
  The third package beside the engine and the dashboard (v2 §16, D14).

  The engine asks an `EhOsContract.Authorizer` whether a credential's actor may
  act, and verifies nothing itself. This package is the implementation for the
  credentials EHOS issues (`eh-os` D-33, D-34): it verifies them against keys it
  keeps in the application's own database, and it owns that table. The engine
  does not depend on it, and it builds and tests standing alone, as the other two
  packages do.
  """

  def project do
    [
      app: :eh_os_contract_auth,
      version: @version,
      name: "EhOsContract.Auth",
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only read when this project is the top-level one, as in the other two packages.
      config_path: "config/config.exs",
      # Without this entry `use Boundary` is documentation rather than a check.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # `mix check` runs the tests, and those need MIX_ENV=test.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The suite migrates itself with `EhOsContract.Auth.Migrations`, so the package is
  # the first consumer of its own migration, as the engine is of its.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      check: ["format --check-formatted", "compile --force --warnings-as-errors", "test"]
    ]
  end

  defp package do
    [
      name: "eh_os_contract_auth",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/eh_os_contract_auth/CHANGELOG.md"
      },
      # Not `priv/`: the only thing there is this package's own test migration.
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end

  # A path when the engine sits beside this package, and the same repository over
  # git otherwise — the reason is in `packages/eh_os_contract_web/mix.exs`.
  defp eh_os_contract_dep do
    if File.exists?(Path.expand("../eh_os_contract/mix.exs", __DIR__)) do
      {:eh_os_contract, path: "../eh_os_contract"}
    else
      {:eh_os_contract, git: @git_url, sparse: "packages/eh_os_contract"}
    end
  end

  defp deps do
    [
      # `EhOsContract.Actor`, which a verified credential becomes, and the clock
      # expiry is measured by.
      eh_os_contract_dep(),
      # The key table is this package's own storage. Declared, not inherited
      # through the engine, which needs them for its own tables.
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:jason, "~> 1.4"},
      # The cryptography: JOSE through Joken, never our own (`eh-os` D-33, D-34).
      # Not `joken_jwks`, which refreshes only on an unknown key and keeps its keys
      # only in memory — D-34 has both reasons.
      {:joken, "~> 2.7"},
      # The key set is fetched over HTTP, by the small fetcher D-34 chose.
      {:req, "~> 0.7"},
      {:boundary, "~> 0.10", runtime: false},
      # `EhOsContract.Auth.Plug`, the bearer plug in front of `EhOsContract.Plug`. The
      # suite also plays EHOS's JWKS endpoint as a function plug handed to Req.
      {:plug, "~> 1.16"},
      # `ehos.yaml` is read and validated as EHOS reads it (`eh-os` D-51): yamerl with YAML
      # 1.2's core schema, then JSV against the schema EHOS publishes, copied into `priv/`.
      {:yamerl, "~> 0.10"},
      {:jsv, "~> 0.25.0"}
    ]
  end
end
