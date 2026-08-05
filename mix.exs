defmodule PnsPrototype.MixProject do
  use Mix.Project

  def project do
    [
      app: :pns_prototype,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Module boundaries enforced at compile time, from the first commit
      # (ADR §5-6). Without this entry `use Boundary` is only documentation.
      compilers: [:boundary] ++ Mix.compilers(),
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
      mod: {PnsPrototype.Application, []}
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
      {:boundary, "~> 0.10", runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # The one command that has to pass. `--warnings-as-errors` is necessary
      # here: `boundary` reports violations as warnings, so without that switch
      # the boundaries are documentation rather than enforcement.
      # `pns.docs --check` is here for the same reason: without it the key
      # reference in `docs/contract.md` is documentation that can lie, rather
      # than a generated artifact.
      check: ["compile --force --warnings-as-errors", "pns.check", "pns.docs --check", "test"]
    ]
  end
end
