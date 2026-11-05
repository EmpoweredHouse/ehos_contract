defmodule EhOsContract.GraphRenderer.MixProject do
  use Mix.Project

  @version "0.9.1"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  # The pages ExDoc builds, in the order a reader takes them.
  @extras [
    "README.md",
    "docs/explore-a-domain.md",
    "docs/draw-a-document.md",
    "docs/join-applications.md",
    "CHANGELOG.md"
  ]
  @description "Draws EhOsContract's graph.v1 documents in a LiveView: cards, arrows, panels."

  @moduledoc """
  The renderer beside the engine and the dashboard (plan E13b): a `graph.v1` document
  and its overlay in, an interactive graph out. It does not depend on the engine —
  the document is plain data, and the EHOS Console draws it without the engine's
  tables, jobs or migrations — so it builds and tests standing alone, on fixture
  documents, as the other packages do.
  """

  def project do
    [
      app: :eh_os_contract_graph,
      version: @version,
      name: "EhOsContract.GraphRenderer",
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only read when this project is the top-level one, as in the other packages.
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
  # lower case. The engine owns the words of a contract, and this package draws them. Read from
  # the engine beside it, which is there wherever `ehos_diagrams` is, in this repository.
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
    [extra_applications: [:logger]]
  end

  # The endpoint the LiveView tests drive the component through.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        # A reference in a doc to a module, a function or a page that is not there,
        # or is hidden, fails here rather than becoming a dead link on hexdocs.
        "docs -f html --warnings-as-errors --output _build/test/doc",
        "test"
      ],
      # Run by whoever edits assets/; the committed output under priv/static/ is what
      # everyone else — `mix check` and every host — uses. The libraries are vendored
      # under assets/vendor/ (NOTICE says what each is and how it was taken), so the
      # build is esbuild alone, a downloaded binary: no Node, no npm.
      "assets.build": ["esbuild eh_os_contract_graph", "esbuild eh_os_contract_graph_css"]
    ]
  end

  # The bundle redistributes dagre and d3 under their licences, which NOTICE carries.
  defp package do
    [
      name: "eh_os_contract_graph",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/eh_os_contract_graph/CHANGELOG.md"
      },
      files:
        ~w(lib priv/static priv/schema docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      # The diagrams `mix ehos_diagrams.gen` writes, which the pages link as `img/<id>.svg`.
      assets: %{"docs/img" => "img"},
      extras: @extras,
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
        "#{@source_url}/blob/#{source_ref()}/packages/eh_os_contract_graph/%{path}#L%{line}"
    ]
  end

  defp source_ref, do: System.get_env("EH_OS_CONTRACT_DOCS_SOURCE_REF", "main")

  @lib Path.join(__DIR__, "lib") <> "/"

  defp lib_module?(module, _metadata),
    do: String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib)

  defp deps do
    [
      # The component, HEEx and the hook's events.
      {:phoenix_live_view, "~> 1.1"},
      # The test endpoint (test/support/test_live.ex) is a Phoenix endpoint. Declared for
      # every environment because phoenix_live_view needs it in every one, and Mix
      # refuses `only: :test` for a dependency another declares without it.
      {:phoenix, "~> 1.8"},
      {:boundary, "~> 0.10", runtime: false},
      # `mix docs`, which `mix check` runs to hold the references in the docs.
      {:ex_doc, "~> 0.36", only: [:dev, :test], runtime: false},
      # phoenix_live_view's test helpers parse the rendered HTML with it.
      {:lazy_html, ">= 0.1.0", only: :test},
      # Builds assets/ into the bundle committed under priv/static/, as in
      # packages/eh_os_contract_web: a downloaded binary, run by whoever edits the JS.
      {:esbuild, "~> 0.9", only: :dev, runtime: false},
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
