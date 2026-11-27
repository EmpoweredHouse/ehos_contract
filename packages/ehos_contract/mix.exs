defmodule EhosContract.MixProject do
  use Mix.Project

  # One source for `project/0` and, through `EhosContract.version/0`, for the line every
  # conformance report carries. A change that can move a verdict raises the minor
  # version and gets a line in CHANGELOG.md — the rule is written there.
  @version "0.17.1-dev"
  @source_url "https://github.com/EmpoweredHouse/ehos_contract"

  # The concept pages, in `docs/` beside the others, in the order a reader takes them. ExDoc
  # writes every page into one directory, so a page in a subdirectory would link an image by a
  # path that is right in the repository and wrong in the HTML. `EhosContract.Docs.concepts/0`
  # keeps the same list for the tests.
  @concepts ~w(domain domain-data personal-data master-keys units deciding event-versions reactions reading read-models subscriptions forms between-contracts process outages conformance scenarios authorization scope authorizer calls)
  @concept_pages Enum.map(@concepts, &"docs/#{&1}.md")
  @description "Checks that deployed code does what the declared business process says it does."

  @moduledoc """
  The engine as its own application, extracted on 2026-08-20.

  Until then `boundary` enforced the seam and `README.md` claimed that moving a
  client tree out was `git mv`. Nobody had tried, so the claim was untested —
  extracting this is what tests it, and what the extraction costs is recorded
  rather than smoothed over.
  """

  def project do
    [
      app: :ehos_contract,
      version: @version,
      name: "EhosContract",
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
      # Without this entry `use Boundary` is documentation rather than a check. The
      # last one checks the fixtures' v2 contracts across modules, as a consumer's
      # would be (v2 §6, L3).
      compilers: [:boundary] ++ Mix.compilers() ++ [:ehos_contract],
      start_permanent: Mix.env() == :prod,
      # Tests compile contracts and domains while they run, whose structs derive Inspect
      # to hide personal fields; consolidated protocols would ignore those derivations
      # and warn about each one.
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases(),
      deps: deps(),
      # `mix ehos_diagrams.gen [--check]`, in `:dev` only: the sandbox's gate runs the check
      # when the generator is fetched, and CI in a job of its own (#520).
      ehos_diagrams: [
        sources: "docs/diagrams",
        out: "docs/img",
        vocabulary: {EhosContract.Docs, :vocabulary, []},
        pages: ["README.md", "docs/**/*.md"],
        documents: [
          "README.md",
          "docs/{introduction,getting-started,contract,refusals,glossary}.md"
          | @concept_pages
        ]
      ]
    ]
  end

  # Mirrors the host's. Without it `mix check` here runs the `test` alias in `:dev`,
  # where `EhosContract.TestRepo` is not compiled, and fails on `ecto.create` before reaching
  # a single test — which is how this alias stood until 2026-09-22, usable only if
  # you happened to prefix `MIX_ENV=test` yourself.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # The invented fixtures — the universality gate and the process-shapes rig —
  # belong to the engine and not to any client, so they compile here. They are
  # the material a client-free test suite is built from.
  #
  # `dev/` holds tooling for developing this package itself — `mix ehos_contract.rules`
  # and `mix ehos_contract.docs`, which write `docs/rules.md` and `docs/dsl/` inside this
  # package. A dependency always compiles in `:prod`, so none of it reaches a consumer,
  # where it had nothing to rewrite and failed with a `File.Error`.
  defp elixirc_paths(:test), do: ["lib", "test/support", "dev"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  # The suite migrates itself with `EhosContract.Migrations`, so the package is the first
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
        "ehos_contract.check",
        "ehos_contract.rules --check",
        "ehos_contract.docs --check",
        # A reference in a doc to a module, a function or a page that is not there,
        # or is hidden, fails here rather than becoming a dead link on hexdocs.
        "docs -f html --warnings-as-errors --output _build/test/doc",
        "spark.formatter --extensions EhosContract.Domain.Dsl,EhosContract.Contract.Dsl," <>
          "EhosContract.Process.Dsl --check",
        "test"
      ]
    ]
  end

  defp package do
    [
      name: "ehos_contract",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/ehos_contract/CHANGELOG.md"
      },
      # Listed explicitly rather than left to the default, which would include all of
      # `priv/`. Of it only `priv/schema` ships — the JSON Schema of the graph
      # documents, which a renderer holds them to (plan E13a); `priv/test_repo` is this
      # package's own test migration, an artifact of testing the migration module
      # against itself, and nothing a consumer should receive. `LICENSE` is a copy: a
      # package published from a subdirectory does not pick up the repository's, and
      # `licenses:` above is metadata rather than a file.
      files: ~w(lib priv/schema docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      # The diagrams `mix ehos_diagrams.gen` writes, which the pages link as `img/<id>.svg`.
      assets: %{"docs/img" => "img"},
      extras:
        [
          "README.md",
          "docs/introduction.md",
          "docs/getting-started.md",
          "docs/contract.md"
        ] ++
          @concept_pages ++
          [
            "docs/glossary.md",
            "docs/configuration.md",
            "docs/cli.md",
            "docs/behaviours.md",
            "docs/refusals.md",
            "docs/rules.md"
          ] ++
          dsl_reference("domain") ++
          dsl_reference("contract") ++
          dsl_reference("process") ++ ["CHANGELOG.md"],
      groups_for_extras: [
        Introduction: ["README.md", "docs/introduction.md", "docs/getting-started.md"],
        Concepts:
          ["docs/contract.md"] ++
            @concept_pages,
        Reference: [
          "docs/glossary.md",
          "docs/configuration.md",
          "docs/cli.md",
          "docs/behaviours.md",
          "docs/refusals.md",
          "docs/rules.md"
        ],
        "DSL reference": ~r{docs/dsl/}
      ],
      # Hexdocs lists the modules in these groups, in this order, rather than in one
      # alphabetical column. Mix tasks get their own section from ExDoc.
      groups_for_modules: [
        "Writing a contract": [
          EhosContract.Domain,
          EhosContract.Domain.Dsl,
          EhosContract.Contract,
          EhosContract.Contract.Dsl,
          EhosContract.Process,
          EhosContract.Process.Dsl,
          EhosContract.Implementation,
          EhosContract.Rejection
        ],
        "Dispatch and queries": [
          EhosContract,
          EhosContract.Actor,
          EhosContract.Authorizer,
          EhosContract.Authorizer.Default,
          EhosContract.Authorizer.Request,
          EhosContract.Supplier,
          EhosContract.Supplier.Request,
          EhosContract.Entities,
          EhosContract.Receipt,
          EhosContract.Meta,
          EhosContract.Clock,
          EhosContract.Plug
        ],
        "The log": [
          EhosContract.Event,
          EhosContract.EventRun,
          EhosContract.Store,
          EhosContract.Store.Postgres,
          EhosContract.Key,
          EhosContract.Migrations,
          EhosContract.NewerSchemaError
        ],
        "Delivery and other applications": [
          EhosContract.EffectJob,
          EhosContract.TimerJob,
          EhosContract.Relay,
          EhosContract.Inbox,
          EhosContract.Bus,
          EhosContract.Bus.Local,
          EhosContract.Bus.Message
        ],
        "Personal data": [
          EhosContract.Personal,
          EhosContract.Vault,
          EhosContract.Vault.Local,
          EhosContract.Erased
        ],
        Conformance: [
          EhosContract.Conformance,
          EhosContract.Conformance.Wire,
          EhosContract.Report,
          EhosContract.Report.Sentence,
          EhosContract.Trace,
          EhosContract.StageOrder,
          EhosContract.Dependency,
          EhosContract.Deployment
        ],
        "The model and its documents": [
          EhosContract.Model,
          EhosContract.Registry,
          EhosContract.Graph.Document,
          EhosContract.Graph.Overlay,
          EhosContract.OpenAPI,
          EhosContract.AsyncAPI
        ],
        Testing: [
          EhosContract.ScenarioCase,
          EhosContract.PropertyCase,
          EhosContract.Generators,
          EhosContract.Testing,
          EhosContract.Store.Suite,
          EhosContract.Bus.Suite
        ],
        Configuration: [EhosContract.Config]
      ],
      # The changelog names what a release removed, and the names resolve nowhere
      # after it, as they should.
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      # Only what hexdocs publishes. `mix check` builds the docs in `:test`, which also
      # compiles `test/support/` and `dev/`; documenting them would let a doc in `lib/`
      # cite a fixture and pass here, then be a dead link once published.
      filter_modules: &lib_module?/2,
      # The package is a directory of its repository, so a source link names it. A build
      # of the docs for a commit (.github/scripts/build-docs.sh, the only one anybody
      # reads) links to that commit; any other build, to `main`. Not to `v<version>`: the
      # repository's tag follows the engine's version, not each package's, and a `-dev`
      # version has no tag at all.
      source_ref: source_ref(),
      source_url_pattern:
        "#{@source_url}/blob/#{source_ref()}/packages/ehos_contract/%{path}#L%{line}"
    ]
  end

  defp source_ref, do: System.get_env("EHOS_CONTRACT_DOCS_SOURCE_REF", "main")

  @lib Path.join(__DIR__, "lib") <> "/"

  # From the compiled module, not ExDoc's metadata, whose keys are its own to change.
  defp lib_module?(module, _metadata),
    do: String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib)

  # A DSL's index, then a page per top-level entity, all generated by
  # `mix ehos_contract.docs` (`EhosContract.Docs`).
  defp dsl_reference(dsl) do
    index = "docs/dsl/#{dsl}-dsl.md"
    [index | Path.wildcard("docs/dsl/#{dsl}-*.md") -- [index]]
  end

  defp deps do
    [
      # The log is the engine's own storage, so the persistence dependencies are
      # the engine's — the same shape as Oban, which is also a library that owns
      # tables and ships the migration for them.
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      # What is delivered at least once — effects, timers — crosses a process
      # boundary through a queue.
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"},
      # A subscription's steps and lag go out as `:telemetry` events. Ecto and Oban
      # bring it too; declared, as `:decimal` below, so the engine does not lean on them.
      {:telemetry, "~> 1.0"},
      # `EhosContract.Codec` writes a `:decimal` field as a string and reads it back as a
      # `Decimal`, so the engine calls it by name. Declared explicitly rather than
      # inherited: a package whose dependency is satisfied only because a neighbour
      # happens to need it breaks when the neighbour goes. At least 3.2: before 3.0
      # `Decimal.new/1` took any exponent (CVE-2026-32686), which a caller's text reaches
      # through `Decimal.cast/1`, and the codec reads text as Decimal 3 parses it. 3.1.2 fixed
      # `Decimal.round/3`'s unbounded allocation (EEF-CVE-2026-97853, #416); 3.2 is the
      # release the repository's locks hold.
      {:decimal, "~> 3.2"},
      # `EhosContract.Plug` serves the model's commands, recordings and queries over
      # HTTP. Optional: a host without Plug does not get it, and the module compiles
      # only when Plug is there.
      {:plug, "~> 1.16", optional: true},
      # `EhosContract.Generators` gives valid examples of a contract's data as StreamData
      # generators (plan DD, PC1). Optional, as Plug is: the module compiles only where a
      # host has StreamData, usually as a test dependency.
      {:stream_data, "~> 1.1", optional: true},
      {:boundary, "~> 0.10", runtime: false},
      # The v2 DSL engine (v2 §2). From the patch E3 tested its properties on (error
      # locations, formatter export, digest stability under `boundary`), and any later 2.x,
      # which a host on Ash needs; CI also runs the suite on the newest.
      {:spark, "~> 2.7 and >= 2.7.3"},
      # Spark's formatter task rewrites `.formatter.exs` through it. Only where that
      # task runs.
      {:sourceror, "~> 1.12", only: [:dev, :test], runtime: false},
      # A domain's `time_zone:` other than UTC is read with the time zone database the
      # host configures (plan W2); the package's own suite needs one, a host brings its
      # own, so the package does not choose it for them.
      {:tz, "~> 0.28", only: [:dev, :test]},
      # Every graph document the suite builds is held to `priv/schema/graph.v1.json`
      # (plan E13a), with the validator and the version `ehos_contract_auth` uses.
      {:jsv, "~> 0.28.0", only: :test},
      {:ex_doc, "~> 0.36", only: [:dev, :test], runtime: false},
      # The diagrams of the prose pages: hand-laid sources in `docs/diagrams/`, checked and
      # written into `docs/img/` in the design system's colours and fonts by
      # `mix ehos_diagrams.gen` (`ehos_diagrams:` above). Both live in the private
      # ehos-tools, pinned by the commits their tags name
      # (`ehos_diagrams-v0.2.0`, `ehos_design-v0.5.0`); `ehos_diagrams` reads the design
      # system's tokens and fonts from the `ehos_design` the host has. `:dev` only, as the
      # dashboard's `ehos_design`: `mix deps.get --only test` fetches nothing private, so
      # anyone can run this package's `mix check`. Hex leaves a `:dev` dependency out of the
      # published requirements.
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
       runtime: false},
      # `EhosContract.Form`'s tests build a form and its `inputs_for` as a LiveView page does.
      # Never a host's: the host brings its own. `phoenix_html` is in `:dev` too, because
      # `ehos_design` above brings Phoenix LiveView there, which needs it.
      {:phoenix_ecto, "~> 4.6", only: :test},
      {:phoenix_html, "~> 4.1", only: [:dev, :test]}
    ]
  end
end
