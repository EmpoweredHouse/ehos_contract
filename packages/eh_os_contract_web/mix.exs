defmodule EhOsContract.Web.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  @git_url "#{@source_url}.git"
  # The siblings' versions this package works with, passed in every mode below, so that
  # beside them in this repository Mix holds their versions to these as well.
  @eh_os_contract_requirement "~> 0.11.0"
  @eh_os_contract_graph_requirement "~> 0.8.0"
  @description "A mountable conformance dashboard for EhOsContract."

  @moduledoc """
  The dashboard foundation, extracted as its own package from the first commit.

  Mirrors the `packages/eh_os_contract` extraction: this package builds and tests
  standing alone, against its own test host, and never touches `eh_os_contract_host`
  directly. What it does not carry is `ecto_sql`/`postgrex`/`oban` — this
  package owns no tables and runs no jobs, so pulling those in would be
  copying the template rather than mirroring it.
  """

  def project do
    [
      app: :eh_os_contract_web,
      version: @version,
      name: "EhOsContract.Web",
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only read when this project is the top-level one; see
      # packages/eh_os_contract/config/config.exs for why that matters here too.
      config_path: "config/config.exs",
      # Without this entry `use Boundary` is documentation rather than a check.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # `mix check` runs the tests, and those need MIX_ENV=test — same trap the
  # root project's mix.exs already documents and works around.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [extra_applications: [:logger]]
  end

  # The test host lives here so this package proves its own mounting
  # mechanism against a host it controls, the same shape as
  # packages/eh_os_contract's test/support fixtures.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # The contract status screen's own test suite needs a real database, the
      # same way packages/eh_os_contract's does — same alias, same reason.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        # A reference in a doc to a module, a function or a page that is not there,
        # or is hidden, fails here rather than becoming a dead link on hexdocs.
        "docs -f html --warnings-as-errors --output _build/test/doc",
        "test"
      ],
      # Run by whoever edits assets/js/app.js or assets/css/app.css; the
      # committed output under priv/static/ is what everyone else —
      # including `mix check` — uses. The fonts are copied from
      # `ehos_design` beside the built stylesheet, whose relative url()s
      # name them there.
      "assets.build": [
        "esbuild eh_os_contract_web",
        "esbuild eh_os_contract_web_css",
        fn _args ->
          fonts =
            Path.expand(
              "deps/ehos_design/packages/ehos_design/priv/static/ehos_design/fonts",
              __DIR__
            )

          target = Path.expand("priv/static/assets/fonts", __DIR__)
          File.mkdir_p!(target)

          for name <- File.ls!(fonts), Path.extname(name) in [".woff2", ".txt"] do
            File.cp!(Path.join(fonts, name), Path.join(target, name))
          end
        end
      ]
    ]
  end

  # **Metadata now; publication held.** `priv/static/assets/fonts/` holds
  # third-party fonts (OFL), and `priv/static/assets/app.js` bundles the graph
  # renderer's dagre (MIT) and d3 (ISC, BSD), so a tarball of this package
  # redistributes somebody else's work. That needs an attribution line a lawyer would
  # accept, not just a comment in a source file, and publishing is irreversible in a
  # way editing is not. `NOTICE` carries the attribution; the decision to actually
  # push is a separate one and has not been made.
  defp package do
    [
      name: "eh_os_contract_web",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/eh_os_contract_web/CHANGELOG.md"
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
        "#{@source_url}/blob/#{source_ref()}/packages/eh_os_contract_web/%{path}#L%{line}"
    ]
  end

  defp source_ref, do: System.get_env("EH_OS_CONTRACT_DOCS_SOURCE_REF", "main")

  @lib Path.join(__DIR__, "lib") <> "/"

  defp lib_module?(module, _metadata),
    do: String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib)

  # The engine and the renderer are this repository's packages too, and where they come
  # from depends on where this package is:
  #
  # - built for Hex, or installed from it: by version alone. Hex accepts no other kind of
  #   dependency, and in an application that installed this package from Hex,
  #   `../eh_os_contract` is the engine Hex installed beside it, which a `path:` would
  #   declare a second time;
  # - inside this repository: by path;
  # - fetched over git with `sparse: "packages/eh_os_contract_web"`: over git as well. Only
  #   this directory is there, so `../eh_os_contract` is not, and a bare `path:` made every
  #   such `mix deps.get` fail with "Dependencies have diverged". The git form is the one a
  #   consumer declares for the engine itself, so the two converge; `mix.lock` pins the commit.
  defp eh_os_contract_dep, do: sibling(:eh_os_contract, @eh_os_contract_requirement)

  defp eh_os_contract_graph_dep,
    do: sibling(:eh_os_contract_graph, @eh_os_contract_graph_requirement)

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
      # Declared rather than inherited. It reaches here today only through
      # `{:eh_os_contract, path: ...}` — Phoenix and LiveView both list it `optional: true` —
      # and a dependency satisfied because a neighbour happens to need it breaks
      # when the neighbour goes. The same rule this repository states twice
      # elsewhere.
      {:jason, "~> 1.4"},
      # The engine, whose report and graph the screens render.
      eh_os_contract_dep(),
      # The renderer the graph is drawn with (plan E13b), its script and stylesheet bundled
      # into this package's own by `mix assets.build`.
      eh_os_contract_graph_dep(),
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:boundary, "~> 0.10", runtime: false},
      # `mix docs`, which `mix check` runs to hold the references in the docs.
      {:ex_doc, "~> 0.36", only: [:dev, :test], runtime: false},
      # Endpoint adapter for the test host. `only: :test` because nothing in
      # this package ever starts a real listening socket outside its own
      # suite.
      {:bandit, "~> 1.5", only: :test},
      # phoenix_live_view's own `live/2` test helper parses the dead-render
      # HTML with this and refuses to run without it — not optional despite
      # not appearing in phoenix_live_view's own dependency tree.
      {:lazy_html, ">= 0.1.0", only: :test},
      # Builds assets/js/app.js into the compiled bundle committed under
      # priv/static/ — a downloaded binary, not Node, so a consumer of this
      # package never needs it: only whoever edits the JS itself runs
      # `mix assets.build` and commits the result, the same way a compiled
      # asset ships with any other Phoenix component library.
      {:esbuild, "~> 0.9", only: :dev, runtime: false},
      # The EmpoweredHouse design system's tokens and fonts, which `mix assets.build`
      # reads from deps/. Only there: the built stylesheet and the fonts
      # are committed under priv/static/assets/, so a host fetches nothing from it,
      # and Hex leaves a `:dev` dependency out of the published requirements. The
      # ref is the commit tagged `ehos_design-v0.1.0`; a new version of the design
      # system reaches the dashboard by moving it and rebuilding.
      {:ehos_design, "~> 0.1.0",
       github: "EmpoweredHouse/ehos-tools",
       sparse: "packages/ehos_design",
       ref: "a65b9c86d920b5566f1c085b2286a44da77505c9",
       only: :dev,
       runtime: false}
    ]
  end
end
