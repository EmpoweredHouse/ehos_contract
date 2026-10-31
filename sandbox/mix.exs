defmodule EhOsContractHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :eh_os_contract_host,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Module boundaries enforced at compile time, from the first commit
      # (ADR §5-6). Without this entry `use Boundary` is only documentation. The last
      # one checks v2 contracts against their domain and each other (v2 §6, L3).
      compilers: [:boundary] ++ Mix.compilers() ++ [:eh_os_contract],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # `mix check` runs the tests, and those need MIX_ENV=test. Without this the
  # alias fails on `mix test` not working in dev.
  def cli, do: [preferred_envs: [check: :test]]

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {EhOsContractHost.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"},
      # Direct, although Ecto and Oban both bring it transitively. `lib/eh_os_contract/` emits
      # telemetry, so it depends on it — and a package whose dependency is satisfied
      # only because a neighbour happens to need it breaks when the neighbour goes.
      {:telemetry, "~> 1.3"},
      # The time zone database the domains' `time_zone: "Europe/Warsaw"` is read with
      # (plan W2): the engine asks the one the host configures, and this host is in Poland.
      {:tz, "~> 0.28"},
      {:boundary, "~> 0.10", runtime: false},
      # The engine, extracted 2026-08-20. A path dependency rather than a copy:
      # the build system now enforces the boundary that `boundary` was enforcing
      # alone, so a domain's tree reaching into the engine's internals fails to
      # compile rather than merely warning.
      {:eh_os_contract, path: "../packages/eh_os_contract"},
      # The dashboard. `runtime: false` because :eh_os_contract_web has no `mod:` of
      # its own to start — EhOsContractHostWeb's own supervisor references its modules
      # directly instead of relying on the OTP application list.
      {:eh_os_contract_web, path: "../packages/eh_os_contract_web", runtime: false},
      # The graph renderer (plan E13b), which the dashboard draws with. Direct, the same
      # reasoning as `:telemetry` above: test/graph_renderer_test.exs draws every case
      # study's document with it.
      {:eh_os_contract_graph, path: "../packages/eh_os_contract_graph"},
      # The credential verifier (v2 stage EA): the `EhOsContract.Authorizer` this host
      # configures, and the bearer plug in front of the commands it serves over HTTP.
      {:eh_os_contract_auth, path: "../packages/eh_os_contract_auth"},
      # Direct, the same reasoning as `:telemetry` above: EhOsContractHostWeb calls
      # these by name (Endpoint, Router, PubSub, the Bandit adapter), and they
      # would otherwise be present only because :eh_os_contract_web happens to need them —
      # satisfied by a neighbour's dependency is satisfied only until the
      # neighbour changes what it needs.
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},
      # phoenix_live_view's own `live/2` test helper needs this to parse the
      # dead-render HTML — not optional, and not visible in
      # phoenix_live_view's own dependency tree (packages/eh_os_contract_web hit the
      # same thing first).
      {:lazy_html, ">= 0.1.0", only: :test},
      # The graph documents of every case study are held to the engine's schema
      # (plan E13a). Direct, although `:eh_os_contract_auth` brings it: the same
      # reasoning as `:telemetry` above. Not `only: :test`, which Mix refuses for a
      # dependency `:eh_os_contract_auth` declares for every environment; `runtime:
      # false` as there, so it is not started with the host.
      {:jsv, "~> 0.25.0", runtime: false},
      # The test material's units are tried on legal histories of their contracts
      # (`EhOsContract.PropertyCase`, plan DD, PC2), which exists only where StreamData is.
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # The one command that has to pass. `--warnings-as-errors` is necessary
      # here: `boundary` reports violations as warnings, so without that switch
      # the boundaries are documentation rather than enforcement. The DSL reference
      # is checked by the package's own gate, where the reference now lives.
      check: [
        # First because it is the cheapest and the message is the clearest. Until
        # 2026-09-22 the gate had no format step at all, and fifty-one files across
        # the three projects had drifted without anybody seeing it.
        #
        # **A trap worth knowing:** Mix caches the resolved formatter configuration in
        # `_build/<env>/lib/<app>/.mix/cached_dot_formatter` and does not invalidate it
        # when a *dependency's* `.formatter.exs` changes. A machine whose cache predates
        # such a change formats differently from CI, which never keeps the repository's
        # own applications in `_build` between runs. If this step disagrees with what
        # you see locally, delete that file.
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "eh_os_contract.check",
        # Plan DD, V3 (#340): an event's fields changed without a new version, which
        # nothing in a compile notices and the first old row in a log would.
        "eh_os_contract.schema --check",
        "test",
        &package_test/1,
        &package_diagrams/1,
        &package_test_web/1,
        &package_test_auth/1,
        &package_test_graph/1
      ]
    ]
  end

  # The engine's own suite, run from here as well.
  #
  # Since 2026-08-21 most of the tests live in `packages/eh_os_contract/test/` and `mix
  # test` in this project no longer reaches them — it runs this application's, which
  # are only its own case studies'. A gate that stopped covering the engine on
  # the day the engine got its own suite would be the worst possible outcome of that
  # move, so the gate runs both.
  #
  # A separate `mix` invocation rather than an umbrella, because the package has to
  # keep building and testing **standing alone** — that is the property being
  # protected, and an umbrella would quietly remove it.
  defp package_test(_args) do
    {_output, status} =
      System.cmd("mix", ["check"],
        cd: "../packages/eh_os_contract",
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0, do: Mix.raise("the engine's own gate failed (packages/eh_os_contract)")
  end

  # The engine's diagrams against their sources (#520). The generator is a `:dev` dependency
  # from the private ehos-tools, so the engine's own gate, which runs in `:test`, leaves it out
  # and anyone can run that. Here it runs where a maintainer's `mix deps.get` fetched it; without
  # it the gate says so and goes on, and CI's `diagrams` job holds the check.
  defp package_diagrams(_args) do
    if File.dir?("../packages/eh_os_contract/deps/ehos_diagrams") do
      {_output, status} =
        System.cmd("mix", ["ehos_diagrams.gen", "--check"],
          cd: "../packages/eh_os_contract",
          env: [{"MIX_ENV", "dev"}],
          into: IO.stream(:stdio, :line)
        )

      if status != 0,
        do: Mix.raise("the engine's diagrams are not current (packages/eh_os_contract)")
    else
      Mix.shell().info(
        "The engine's diagrams were not checked: ehos-tools is not fetched in packages/eh_os_contract."
      )
    end
  end

  # A path dependency does not run its own tests automatically — same fact
  # as package_test/1 above, confirmed again here rather than assumed.
  defp package_test_web(_args) do
    {_output, status} =
      System.cmd("mix", ["check"],
        cd: "../packages/eh_os_contract_web",
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0,
      do: Mix.raise("the dashboard foundation's own gate failed (packages/eh_os_contract_web)")
  end

  # The credential verifier (v2 stage EA), the same shape again: a package that
  # stands alone, whose gate is its own `mix check` in a separate Mix project.
  defp package_test_auth(_args) do
    {_output, status} =
      System.cmd("mix", ["check"],
        cd: "../packages/eh_os_contract_auth",
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0,
      do: Mix.raise("the credential verifier's own gate failed (packages/eh_os_contract_auth)")
  end

  # The graph renderer (plan E13b), the same shape again: it depends on no other package of
  # this repository, and its gate is its own `mix check` in a separate Mix project.
  defp package_test_graph(_args) do
    {_output, status} =
      System.cmd("mix", ["check"],
        cd: "../packages/eh_os_contract_graph",
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0,
      do: Mix.raise("the graph renderer's own gate failed (packages/eh_os_contract_graph)")
  end
end
