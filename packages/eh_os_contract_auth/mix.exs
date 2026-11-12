defmodule EhOsContract.Auth.MixProject do
  use Mix.Project

  @version "0.13.1-dev"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  @git_url "#{@source_url}.git"
  # The engine's versions this package works with, passed in every mode below, so that
  # beside it in this repository Mix holds its version to this as well.
  @eh_os_contract_requirement "~> 0.14.0"
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
      deps: deps(),
      # `mix ehos_diagrams.gen [--check]`, in `:dev` only, as in the engine: the sandbox's gate
      # runs the check when the generator is fetched, and CI in its `diagrams` job.
      ehos_diagrams: [
        sources: "docs/diagrams",
        out: "docs/img",
        vocabulary: {__MODULE__, :vocabulary, []},
        pages: ["README.md", "docs/**/*.md"],
        documents: ["README.md", "docs/**/*.md"]
      ]
    ]
  end

  # What the labels of the diagrams are held to: each word the engine's glossary defines, in
  # lower case, as in the graph renderer. EHOS's own words are not in this repository, so a
  # diagram names them as technical. Read from the engine beside it, which is there wherever
  # `ehos_diagrams` is, in this repository.
  @doc false
  def vocabulary do
    words =
      ~r/^\| \*\*([^*]+)\*\* \|/mu
      |> Regex.scan(File.read!(Path.expand("../eh_os_contract/docs/glossary.md", __DIR__)),
        capture: :all_but_first
      )
      |> Enum.map(fn [word] -> String.downcase(word) end)

    %{words: words, alone: [], concepts: %{}, badges: []}
  end

  # `mix check` runs the tests, and those need MIX_ENV=test.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [mod: {EhOsContract.Auth.Application, []}, extra_applications: [:logger, :crypto]]
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
      files: ~w(lib priv/schemas docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      # The diagrams `mix ehos_diagrams.gen` writes, which the pages link as `img/<id>.svg`.
      assets: %{"docs/img" => "img"},
      extras: [
        "README.md",
        "docs/getting-started.md",
        "docs/credential.md",
        "docs/decisions.md",
        "docs/sign-in.md",
        "docs/call-another-application.md",
        "docs/people.md",
        "docs/mail.md",
        "docs/grants.md",
        "docs/egress.md",
        "docs/without-ehos.md",
        "docs/development.md",
        "docs/testing.md",
        "docs/configuration.md",
        "docs/keys.md",
        "docs/manifest.md",
        "CHANGELOG.md"
      ],
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
      # Named, not only inherited through Joken: the package calls JOSE itself, and 1.11.13
      # fixes eight advisories against 1.11.12 (EEF-CVE-2026-65625 to -65632, #471).
      {:jose, ">= 1.11.13 and < 2.0.0"},
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
      {:jsv, "~> 0.26.2", runtime: false},
      # The manifest's property: every key of any valid ehos.yaml comes through unchanged.
      {:stream_data, "~> 1.1", only: :test},
      # Holds every implementation of `People.Directory` and `Grants.Granter` but EHOS's to the
      # callbacks' types, as a host's Hammox mock would (#475). Never a dependency of a host.
      {:hammox, "~> 0.7", only: :test},
      # The diagrams of the pages: hand-laid sources in `docs/diagrams/`, checked and written
      # into `docs/img/` by `mix ehos_diagrams.gen` (`ehos_diagrams:` above), at the commits the
      # engine pins, for the reasons its `mix.exs` gives. `:dev` only: `mix deps.get --only test`
      # fetches nothing private, so anyone can run this package's `mix check`.
      {:ehos_diagrams, "~> 0.2.0",
       github: "EmpoweredHouse/ehos-tools",
       sparse: "packages/ehos_diagrams",
       ref: "2198050364cee447b66b010ac31dfd6df9c9262e",
       only: :dev,
       runtime: false},
      {:ehos_design, "~> 0.5.0",
       github: "EmpoweredHouse/ehos-tools",
       sparse: "packages/ehos_design",
       ref: "8b2de14f3c6f7768c5ddb9f74f0595ec44acddd0",
       only: :dev,
       runtime: false}
    ]
  end
end
