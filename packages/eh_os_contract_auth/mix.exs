defmodule EhOsContract.Auth.MixProject do
  use Mix.Project

  @version "0.7.0"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  @git_url "#{@source_url}.git"
  # The engine's versions this package works with, passed in every mode below, so that
  # beside it in this repository Mix holds its version to this as well.
  @eh_os_contract_requirement "~> 0.10.0"
  @description "Verifies EHOS credentials and authorizes EhOsContract commands, recordings and queries."

  @moduledoc """
  The third package beside the engine and the dashboard (v2 §16, D14).

  The engine asks an `EhOsContract.Authorizer` whether a credential's actor may
  act, and verifies nothing itself. This package is the implementation for the
  credentials EHOS issues: it verifies them against keys it
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
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        # A reference in a doc to a module, a function or a page that is not there,
        # or is hidden, fails here rather than becoming a dead link on hexdocs.
        "docs -f html --warnings-as-errors --output _build/test/doc",
        "test"
      ]
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
      # `priv/schemas/`, EHOS's `ehos.yaml` schemas the reader validates with, and not the rest of
      # `priv/`, which is this package's own test migration.
      files: ~w(lib priv/schemas .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      # The changelog names what a release removed, and the names resolve nowhere
      # after it, as they should.
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      # Only what hexdocs publishes: `mix check` builds the docs in `:test`, which also
      # compiles `test/support/` (the engine's `mix.exs` says why it matters).
      filter_modules: &lib_module?/2,
      # The package is a directory of its repository, so a source link names it. A build
      # of the docs for a commit (.github/scripts/build-docs.sh, the only one anybody
      # reads) links to that commit; any other build, to `main`. Not to `v<version>`: the
      # repository's tag follows the engine's version, not each package's, and a `-dev`
      # version has no tag at all.
      source_ref: source_ref(),
      source_url_pattern:
        "#{@source_url}/blob/#{source_ref()}/packages/eh_os_contract_auth/%{path}#L%{line}"
    ]
  end

  defp source_ref, do: System.get_env("EH_OS_CONTRACT_DOCS_SOURCE_REF", "main")

  @lib Path.join(__DIR__, "lib") <> "/"

  defp lib_module?(module, _metadata),
    do: String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib)

  # By version alone when built for Hex or installed from it, by path beside the engine in
  # this repository, and over git otherwise. Why each: `packages/eh_os_contract_web/mix.exs`.
  defp eh_os_contract_dep, do: sibling(:eh_os_contract, @eh_os_contract_requirement)

  # The same as `packages/eh_os_contract_web/mix.exs`'s, which an application installing both
  # needs: two packages declaring the engine differently make Mix refuse them.
  defp sibling(app, requirement) do
    cond do
      hex?() ->
        {app, requirement}

      File.exists?(Path.expand("../#{app}/mix.exs", __DIR__)) ->
        {app, requirement, path: "../#{app}"}

      true ->
        {app, requirement, git: @git_url, sparse: "packages/#{app}"}
    end
  end

  # `mix hex.build` and `mix hex.publish` run with `EH_OS_CONTRACT_HEX=1`, and Hex unpacks
  # `hex_metadata.config` beside the `mix.exs` of every package it installs.
  defp hex? do
    System.get_env("EH_OS_CONTRACT_HEX") == "1" or
      File.exists?(Path.expand("hex_metadata.config", __DIR__))
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
      # The cryptography: JOSE through Joken, never our own, as EHOS decided.
      # Not `joken_jwks`, which refreshes only on an unknown key and keeps its keys
      # only in memory, both of which EHOS's design rules out.
      {:joken, "~> 2.7"},
      # The key set is fetched over HTTP, by the small fetcher EHOS's design chose.
      {:req, "~> 0.7"},
      # Req's HTTP client, at least the release past three advisories, since
      # `EhOsContract.Auth.Egress` points it at servers outside the installation (#415).
      {:mint, "~> 1.11"},
      {:boundary, "~> 0.10", runtime: false},
      # `mix docs`, which `mix check` runs to hold the references in the docs.
      {:ex_doc, "~> 0.36", only: [:dev, :test], runtime: false},
      # `EhOsContract.Auth.Plug`, the bearer plug in front of `EhOsContract.Plug`. The
      # suite also plays EHOS's JWKS endpoint as a function plug handed to Req.
      {:plug, "~> 1.16"},
      # The session's tokens are encrypted with `Plug.Crypto.MessageEncryptor` (S3), which is
      # XChaCha20-Poly1305 from 2.0; `plug` alone would also take 1.x, which is AES-GCM.
      {:plug_crypto, "~> 2.0"},
      # Signing a browser in through EHOS with OpenID Connect (S1 in docs/adr/browser-session.md).
      # `oidcc` is pinned here because `oidcc_plug` accepts `~> 3.7`, and only 3.9.0 fixes
      # CVE-2026-75759; `oidcc_plug` 0.5.1 fixes CVE-2026-66883 and CVE-2026-66884. `oidcc`
      # needs OTP 27.
      {:oidcc, "~> 3.9"},
      {:oidcc_plug, "~> 0.5.1"},
      # `ehos.yaml` is read and validated as EHOS reads it: yamerl with YAML
      # 1.2's core schema, then JSV against the schema EHOS publishes, copied into `priv/`. Only
      # `mix eh_os_contract.manifest` reads it, in the application's CI, so neither is started
      # with the host or carried into its release. yamerl is held to 0.10.x because the reader
      # matches the shape of its tokens and nodes.
      {:yamerl, "~> 0.10.0", runtime: false},
      {:jsv, "~> 0.25.0", runtime: false},
      # The manifest's property: every key of any valid ehos.yaml comes through unchanged.
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
