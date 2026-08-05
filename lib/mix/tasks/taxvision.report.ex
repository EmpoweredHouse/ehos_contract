defmodule Mix.Tasks.Taxvision.Report do
  @shortdoc "Raport zgodności za okres — cztery pytania, jedna strona"

  @moduledoc """
  Składa cztery pytania ekranu w jeden artefakt dla klienta.

  Zadanie jest **w drzewie klienta**, nie w `pns.*`, i to jest ta sama granica,
  co przy renderowaniu: silnik produkuje dane, aplikacja klienta produkuje ekran.
  Pozostałe zadania — `pns.graph`, `pns.trace`, `pns.check` — są widokami dla
  programisty i zostają, bo mają innego odbiorcę i inne pytanie.

      mix taxvision.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
  """

  use Boundary, classify_to: Taxvision.Report
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, a ten
    # raport jest po polsku i bywa przekierowywany do pliku.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} = OptionParser.parse!(args, strict: [since: :string, until: :string, output: :string])

    Mix.Task.run("app.start")
    PNS.Registry.load!()

    okres = [since: czas(opts[:since]), until: czas(opts[:until])]

    text =
      PNS.Registry.contracts()
      |> Enum.map(&(&1 |> PNS.Conformance.report(okres) |> Taxvision.Report.render()))
      |> Enum.join("\n")

    case opts[:output] do
      nil ->
        Mix.shell().info(text)

      path ->
        # `File.write!` zawsze zapisuje UTF-8; przekierowanie przez potok nie.
        File.write!(path, text)
        Mix.shell().info("zapisano: #{path}")
    end
  end

  defp czas(nil), do: nil

  defp czas(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> Mix.raise("--since i --until wymagają daty ISO8601, np. 2026-07-01T00:00:00Z")
    end
  end
end
