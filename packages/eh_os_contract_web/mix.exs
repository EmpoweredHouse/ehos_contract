defmodule EhOsContract.Web.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/EmpoweredHouse/eh-os-contract"
  @git_url "#{@source_url}.git"
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
      check: ["format --check-formatted", "compile --force --warnings-as-errors", "test"],
      # Run by whoever edits assets/js/app.js or assets/css/app.css; the
      # committed output under priv/static/ is what everyone else —
      # including `mix check` — uses. The vendored Mermaid build is a
      # straight copy, not an esbuild input: it needs to execute as a
      # classic global script (see app.js's own comment on why), which
      # esbuild's bundling would break.
      "assets.build": [
        "esbuild eh_os_contract_web",
        "esbuild eh_os_contract_web_css",
        fn _args ->
          File.cp!(
            Path.expand("assets/js/vendor/mermaid.min.js", __DIR__),
            Path.expand("priv/static/assets/mermaid.min.js", __DIR__)
          )
        end
      ]
    ]
  end

  # **Metadata now; publication held.** `priv/static/assets/mermaid.min.js` is a
  # vendored third-party build (Mermaid, MIT), so a tarball of this package
  # redistributes somebody else's code. That needs an attribution line a lawyer would
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
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end

  # A path when the engine sits beside this package — inside its own repository —
  # and the same repository over git otherwise. A consumer fetching this package
  # with `sparse: "packages/eh_os_contract_web"` gets only this directory, so
  # `../eh_os_contract` is not there, and a bare `path:` made every such
  # `mix deps.get` fail with "Dependencies have diverged". The git form is the one
  # a consumer declares for the engine itself, so the two converge; `mix.lock`
  # pins the commit.
  defp eh_os_contract_dep do
    if File.exists?(Path.expand("../eh_os_contract/mix.exs", __DIR__)) do
      {:eh_os_contract, path: "../eh_os_contract"}
    else
      {:eh_os_contract, git: @git_url, sparse: "packages/eh_os_contract"}
    end
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
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:boundary, "~> 0.10", runtime: false},
      # Endpoint adapter for the test host. `only: :test` because nothing in
      # this package ever starts a real listening socket outside its own
      # suite — see PLAN.md's dopisek on why it might still turn out to be
      # unnecessary.
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
      {:esbuild, "~> 0.9", runtime: false}
    ]
  end
end
