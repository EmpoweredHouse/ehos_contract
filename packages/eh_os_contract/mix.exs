defmodule EhOsContract.MixProject do
  use Mix.Project

  # One source for `project/0` and, through `EhOsContract.version/0`, for the line every
  # conformance report carries. A change that can move a verdict raises the minor
  # version and gets a line in CHANGELOG.md — the rule is written there.
  @version "0.13.1-dev"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"

  # The concept pages, in `docs/` beside the others, in the order a reader takes them. ExDoc
  # writes every page into one directory, so a page in a subdirectory would link an image by a
  # path that is right in the repository and wrong in the HTML. `EhOsContract.Docs.concepts/0`
  # keeps the same list for the tests.
  @concepts ~w(domain domain-data personal-data units reactions reading forms between-contracts process scenarios)
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
      app: :eh_os_contract,
      version: @version,
      name: "EhOsContract",
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
      compilers: [:boundary] ++ Mix.compilers() ++ [:eh_os_contract],
      start_permanent: Mix.env() == :prod,
      # Tests compile contracts and domains while they run, whose structs derive Inspect
      # to hide personal fields; consolidated protocols would ignore those derivations
      # and warn about each one.
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases(),
      deps: deps(),
      # `mix ehos_diagrams.gen [--check]`, in `:dev` only: the sandbox's gate runs the check
      # when the generator is fetched, and CI in a job of its own (#520).
      # `docs/authorization.md` is left out of the documents that may hold no Mermaid block
      # until its two blocks become diagrams (#517).
      ehos_diagrams: [
        sources: "docs/diagrams",
        out: "docs/img",
        vocabulary: {EhOsContract.Docs, :vocabulary, []},
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
  # where `EhOsContract.TestRepo` is not compiled, and fails on `ecto.create` before reaching
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
  # `dev/` holds tooling for developing this package itself — `mix eh_os_contract.rules`
  # and `mix eh_os_contract.docs`, which write `docs/rules.md` and `docs/dsl/` inside this
  # package. A dependency always compiles in `:prod`, so none of it reaches a consumer,
  # where it had nothing to rewrite and failed with a `File.Error`.
  defp elixirc_paths(:test), do: ["lib", "test/support", "dev"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  # The suite migrates itself with `EhOsContract.Migrations`, so the package is the first
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
        "eh_os_contract.check",
        "eh_os_contract.rules --check",
        "eh_os_contract.docs --check",
        # A reference in a doc to a module, a function or a page that is not there,
        # or is hidden, fails here rather than becoming a dead link on hexdocs.
        "docs -f html --warnings-as-errors --output _build/test/doc",
        "spark.formatter --extensions EhOsContract.Domain.Dsl,EhOsContract.Contract.Dsl," <>
          "EhOsContract.Process.Dsl --check",
        "test"
      ]
    ]
  end

  defp package do
    [
      name: "eh_os_contract",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/eh_os_contract/CHANGELOG.md"
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
            "docs/authorization.md",
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
            @concept_pages ++ ["docs/authorization.md"],
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
          EhOsContract.Domain,
          EhOsContract.Domain.Dsl,
          EhOsContract.Contract,
          EhOsContract.Contract.Dsl,
          EhOsContract.Process,
          EhOsContract.Process.Dsl,
          EhOsContract.Implementation,
          EhOsContract.Rejection
        ],
        "Dispatch and queries": [
          EhOsContract,
          EhOsContract.Actor,
          EhOsContract.Authorizer,
          EhOsContract.Authorizer.Default,
          EhOsContract.Authorizer.Request,
          EhOsContract.Supplier,
          EhOsContract.Supplier.Request,
          EhOsContract.Entities,
          EhOsContract.Receipt,
          EhOsContract.Meta,
          EhOsContract.Clock,
          EhOsContract.Plug
        ],
        "The log": [
          EhOsContract.Event,
          EhOsContract.EventRun,
          EhOsContract.Store,
          EhOsContract.Store.Postgres,
          EhOsContract.Key,
          EhOsContract.Migrations,
          EhOsContract.NewerSchemaError
        ],
        "Delivery and other applications": [
          EhOsContract.EffectJob,
          EhOsContract.TimerJob,
          EhOsContract.Relay,
          EhOsContract.Inbox,
          EhOsContract.Bus,
          EhOsContract.Bus.Local,
          EhOsContract.Bus.Message
        ],
        "Personal data": [
          EhOsContract.Personal,
          EhOsContract.Vault,
          EhOsContract.Vault.Local,
          EhOsContract.Erased
        ],
        Conformance: [
          EhOsContract.Conformance,
          EhOsContract.Conformance.Wire,
          EhOsContract.Report,
          EhOsContract.Report.Sentence,
          EhOsContract.Trace,
          EhOsContract.StageOrder,
          EhOsContract.Dependency,
          EhOsContract.Deployment
        ],
        "The model and its documents": [
          EhOsContract.Model,
          EhOsContract.Registry,
          EhOsContract.Graph.Document,
          EhOsContract.Graph.Overlay,
          EhOsContract.OpenAPI,
          EhOsContract.AsyncAPI
        ],
        Testing: [
          EhOsContract.ScenarioCase,
          EhOsContract.PropertyCase,
          EhOsContract.Generators,
          EhOsContract.Testing,
          EhOsContract.Store.Suite,
          EhOsContract.Bus.Suite
        ],
        Configuration: [EhOsContract.Config]
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
        "#{@source_url}/blob/#{source_ref()}/packages/eh_os_contract/%{path}#L%{line}"
    ]
  end

  defp source_ref, do: System.get_env("EH_OS_CONTRACT_DOCS_SOURCE_REF", "main")

  @lib Path.join(__DIR__, "lib") <> "/"

  # From the compiled module, not ExDoc's metadata, whose keys are its own to change.
  defp lib_module?(module, _metadata),
    do: String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib)

  # A DSL's index, then a page per top-level entity, all generated by
  # `mix eh_os_contract.docs` (`EhOsContract.Docs`).
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
      # `EhOsContract.Codec` writes a `:decimal` field as a string and reads it back as a
      # `Decimal`, so the engine calls it by name. Declared explicitly rather than
      # inherited: a package whose dependency is satisfied only because a neighbour
      # happens to need it breaks when the neighbour goes. At least 3.2: before 3.0
      # `Decimal.new/1` took any exponent (CVE-2026-32686), which a caller's text reaches
      # through `Decimal.cast/1`, and the codec reads text as Decimal 3 parses it. 3.1.2 fixed
      # `Decimal.round/3`'s unbounded allocation (EEF-CVE-2026-97853, #416); 3.2 is the
      # release the repository's locks hold.
      {:decimal, "~> 3.2"},
      # `EhOsContract.Plug` serves the model's commands, recordings and queries over
      # HTTP. Optional: a host without Plug does not get it, and the module compiles
      # only when Plug is there.
      {:plug, "~> 1.16", optional: true},
      # `EhOsContract.Generators` gives valid examples of a contract's data as StreamData
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
      # (plan E13a), with the validator and the version `eh_os_contract_auth` uses.
      {:jsv, "~> 0.25.0", only: :test},
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
      # `EhOsContract.Form`'s tests build a form and its `inputs_for` as a LiveView page does.
      # Never a host's: the host brings its own. `phoenix_html` is in `:dev` too, because
      # `ehos_design` above brings Phoenix LiveView there, which needs it.
      {:phoenix_ecto, "~> 4.6", only: :test},
      {:phoenix_html, "~> 4.1", only: [:dev, :test]}
    ]
  end
end
