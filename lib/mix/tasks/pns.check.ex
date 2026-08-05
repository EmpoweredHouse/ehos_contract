defmodule Mix.Tasks.Pns.Check do
  @shortdoc "Sprawdzenia całoprogramowe kontraktu i handlerów"

  @moduledoc """
  Wszystko, co wymaga zobaczenia **wszystkich** modułów naraz.

  Podział jest wymuszony modelem kompilacji, nie wybrany: makro widzi jeden
  plik, więc sprawdza to, co jeden plik może pokazać. To, że każde
  zadeklarowane zdarzenie ma handler albo jest terminalne, że nie ma sierot i
  że deklaracje zgadzają się z rzeczywistością — należy tutaj.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @vendors ~w(zitadel keycloak workos auth0 okta authentik fusionauth supertokens)

  @impl Mix.Task
  def run(_args) do
    # Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, więc
    # `mix pns.check > raport.txt` przycina każdy kodepoint do bajtu: `ł` wychodzi
    # jako `B`. Etykiety zdarzeń są po polsku, bo to język klienta.
    :io.setopts(:standard_io, encoding: :unicode)

    Mix.Task.run("compile")
    Application.load(:pns_prototype)
    PNS.Registry.load!()

    findings =
      []
      |> check_events_have_handlers()
      |> check_owners_exist()
      |> check_rule_functions_exist()
      |> check_traces_resolve()
      |> check_backward_edges()
      |> check_retain_on_free_text()
      |> check_no_vendor_in_config()
      |> check_unverified_declarations()

    report(findings)
  end

  # Każde zadeklarowane zdarzenie ma handler albo jest terminalne.
  defp check_events_have_handlers(findings) do
    for event <- PNS.Registry.declared_events(), reduce: findings do
      acc ->
        handlers = PNS.Registry.handlers_for(event.name)
        terminal? = event.terminal

        cond do
          handlers != [] ->
            acc

          terminal? ->
            acc

          true ->
            # To nie jest błąd: zdarzenie zadeklarowane i nieobsłużone jest
            # jawnym demo warstwy "declared, never observed". Ale musi być
            # widoczne, bo różnica między "celowo" i "zapomniane" jest w
            # głowie autora, nie w kodzie.
            [{:info, "zdarzenie #{inspect(event.name)} bez handlera i nieoznaczone jako terminalne (#{inspect(event.contract)})"} | acc]
        end
    end
  end

  # `owner` był jedyną deklaracją zdarzenia, której **nie czytał żaden
  # mechanizm** — jedno miejsce przepisywało ją do węzła grafu i na tym koniec.
  # Skutek: kontrakt wskazywał właściciela, którego modułu nigdy nie było, a
  # kompilacja i check przechodziły. Deklaracja, której nikt nie sprawdza, jest
  # komentarzem w składni Elixira.
  #
  # `info`, nie błąd: właściciel niezaimplementowanej jeszcze fazy to normalny
  # stan w trakcie wdrożenia, dokładnie jak zdarzenie bez handlera.
  #
  # Zgrupowane **po module, nie po zdarzeniu**, i to nie jest kosmetyka. Wersja
  # per zdarzenie dawała czternaście linii na dwa kontrakty, z czego dziesięć
  # powtarzało tę samą informację. Tak zaczynał check retencji, zanim wyszło, że
  # check krzyczący na wszystko jest wyłączany w ciągu tygodnia.
  defp check_owners_exist(findings) do
    PNS.Registry.declared_events()
    |> Enum.reject(&is_nil(&1.owner))
    |> Enum.reject(&Code.ensure_loaded?(&1.owner))
    |> Enum.group_by(& &1.owner, & &1.name)
    |> Enum.reduce(findings, fn {owner, events}, acc ->
      ile = if length(events) == 1, do: "1 zdarzenia", else: "#{length(events)} zdarzeń"

      [{:info,
        "właściciel #{inspect(owner)} nie istnieje jako moduł, a jest zadeklarowany dla " <>
          "#{ile}: #{inspect(events)}"} | acc]
    end)
  end

  # `rule` wskazuje MFA, więc nikt nie sprawdzi za nas, że funkcja istnieje.
  defp check_rule_functions_exist(findings) do
    for contract <- PNS.Registry.contracts(), rule <- contract.rules(), reduce: findings do
      acc ->
        {module, function, arity} = rule.function

        if Code.ensure_loaded?(module) and function_exported?(module, function, arity) do
          acc
        else
          [{:error, "reguła #{inspect(rule.name)} wskazuje #{inspect(module)}.#{function}/#{arity}, której nie ma"} | acc]
        end
    end
  end

  defp check_traces_resolve(findings) do
    all_events = PNS.Registry.declared_events() |> Enum.map(& &1.name) |> MapSet.new()

    for contract <- PNS.Registry.contracts(), trace <- contract.traces(), reduce: findings do
      acc ->
        missing =
          [trace.from, trace.eventually, trace.or_else]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&MapSet.member?(all_events, &1))

        if missing == [] do
          acc
        else
          [{:error, "trace #{inspect(trace.name)} nie rozwiązuje #{inspect(missing)}"} | acc]
        end
    end
  end

  # Logika siedzi w `PNS.Check`, nie tutaj: jako funkcja prywatna zadania mixa
  # była logiką bez testu, a to jest sprawdzenie, na którym stoi trigger
  # przeglądu ADR §15.
  defp check_backward_edges(findings) do
    Enum.reduce(PNS.Check.backward_edges(), findings, fn edge, acc ->
      [{:warn,
        "krawędź wsteczna w #{inspect(edge.module)} — #{edge.process}: " <>
          "publikuje w #{edge.publishes_in}, subskrybuje w #{edge.subscribes_in}"} | acc]
    end)
  end

  # Raport, nie błąd. Brama kompilacyjna na pola osobowe była rekomendowana
  # w przeglądzie i **odrzucona**: brakujący dowód jest cichą awarią produktu,
  # a nadmiar danych jest widoczny i naprawialny.
  #
  # Pierwsza wersja flagowała każde pole typu `:string` i dała 33 informacje na
  # 11 zdarzeń, w tym każde `company_id`. Check, który krzyczy na wszystko, jest
  # wyłączany w ciągu tygodnia. Sygnał wymaga, żeby kontrakt **odróżniał
  # identyfikator od wolnego tekstu** — więc `:id`, `:period`, `:timestamp` i
  # `:enum` są osobnymi typami, a `:string` znaczy "tekst, który wpisał człowiek".
  defp check_retain_on_free_text(findings) do
    for event <- PNS.Registry.declared_events(),
        {field, type} <- event.payload,
        type == :string,
        not Map.has_key?(event.retain, field),
        reduce: findings do
      acc ->
        [{:info, "#{inspect(event.name)}.#{field} to wolny tekst bez `retain` — trafi do logu dosłownie"} | acc]
    end
  end

  # Deklaracje, których process owner nie potwierdził. Nie błąd — świadomy stan
  # przejściowy. Ale musi być widoczny za każdym przebiegiem, bo fałszywa
  # metryka jest gorsza niż jej brak: to metryka, którą produkt sprzedaje.
  defp check_unverified_declarations(findings) do
    for contract <- PNS.Registry.contracts(),
        process <- contract.processes(),
        field <- process.unverified,
        reduce: findings do
      acc ->
        [{:warn,
          "proces #{inspect(process.name)}: `#{field}` = #{inspect(Map.get(process, field))} " <>
            "nie jest potwierdzone przez process ownera — nie liczy się do raportu dowodowego"} | acc]
    end
  end

  # Szew tożsamości: nazwa vendora w schemacie konfiguracji silnika łamie go.
  defp check_no_vendor_in_config(findings) do
    haystack = :pns_prototype |> Application.get_all_env() |> inspect() |> String.downcase()

    case Enum.filter(@vendors, &String.contains?(haystack, &1)) do
      [] -> findings
      found -> [{:error, "nazwa vendora tożsamości w konfiguracji silnika: #{inspect(found)} — szew złamany"} | findings]
    end
  end

  defp report(findings) do
    for {level, message} <- Enum.reverse(findings) do
      prefix =
        case level do
          :error -> "BŁĄD "
          :warn -> "UWAGA"
          :info -> "info "
        end

      Mix.shell().info("#{prefix} #{message}")
    end

    counts = Enum.frequencies_by(findings, &elem(&1, 0))

    Mix.shell().info(
      "\npns.check: #{Map.get(counts, :error, 0)} błędów, " <>
        "#{Map.get(counts, :warn, 0)} ostrzeżeń, #{Map.get(counts, :info, 0)} informacji"
    )

    if Map.get(counts, :error, 0) > 0, do: exit({:shutdown, 1})
  end
end
