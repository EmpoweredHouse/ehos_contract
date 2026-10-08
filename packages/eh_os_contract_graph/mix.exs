defmodule EhOsContract.GraphRenderer.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
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
      check: ["format --check-formatted", "compile --force --warnings-as-errors", "test"],
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
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end

  defp deps do
    [
      # The component, HEEx and the hook's events.
      {:phoenix_live_view, "~> 1.1"},
      # The test endpoint (test/support/test_live.ex) is a Phoenix endpoint. Declared for
      # every environment because phoenix_live_view needs it in every one, and Mix
      # refuses `only: :test` for a dependency another declares without it.
      {:phoenix, "~> 1.8"},
      {:boundary, "~> 0.10", runtime: false},
      # phoenix_live_view's test helpers parse the rendered HTML with it.
      {:lazy_html, ">= 0.1.0", only: :test},
      # Builds assets/ into the bundle committed under priv/static/, as in
      # packages/eh_os_contract_web: a downloaded binary, run by whoever edits the JS.
      {:esbuild, "~> 0.9", runtime: false}
    ]
  end
end
