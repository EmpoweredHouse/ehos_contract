defmodule PnsPrototype.MixProject do
  use Mix.Project

  def project do
    [
      app: :pns_prototype,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Granice modułów wymuszone w czasie kompilacji, od pierwszego commita
      # (ADR §5-6). Bez tego wpisu `use Boundary` jest tylko dokumentacją.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # `mix check` uruchamia testy, a te wymagają MIX_ENV=test. Bez tego alias
  # wywala się na tym, że `mix test` nie działa w dev.
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
      # Jedna komenda, która musi przechodzić. `--warnings-as-errors` jest tu
      # konieczne: `boundary` raportuje naruszenia jako ostrzeżenia, więc bez
      # tego przełącznika granice są dokumentacją, a nie wymuszeniem.
      # `pns.docs --check` jest tu z tego samego powodu, co `--warnings-as-errors`:
      # bez niego referencja kluczy w `docs/contract.md` jest dokumentacją, która
      # może kłamać, a nie generowanym artefaktem.
      check: ["compile --force --warnings-as-errors", "pns.check", "pns.docs --check", "test"]
    ]
  end
end
