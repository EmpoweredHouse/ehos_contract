defmodule EhOsContract.GraphRenderer.MixProject do
  use Mix.Project

  @version "0.2.1-dev"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
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
      deps: deps()
    ]
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
      files: ~w(lib priv/static .formatter.exs mix.exs README.md CHANGELOG.md LICENSE NOTICE)
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
      {:esbuild, "~> 0.9", runtime: false}
    ]
  end
end
