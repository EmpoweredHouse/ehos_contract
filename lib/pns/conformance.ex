defmodule PNS.Conformance do
  @moduledoc """
  Odpowiedzi na cztery pytania ekranu, liczone z kontraktu i logu.

  Dziś jedno: **które zadeklarowane ścieżki nigdy nie zostały przejechane.**
  Pozostałe trzy — nieudeklarowane przejścia, naruszone assercje (`PNS.Trace`) i
  wersja kontraktu — dołożą 1.6 i 1.7. Ten moduł jest miejscem, w którym się
  zbiegną, żeby raport nie powstał jako czwarte zadanie mixa obok trzech innych.

  ## Dlaczego to nie jest po prostu `state: :dead` z nakładki

  Nakładka odpowiada per **krawędź** i per **typ zdarzenia**: „ta krawędź ma
  zero przejazdów". Raport musi odpowiadać per **przebieg**, bo to jest jedyna
  odpowiedź, która przy wielu klientach cokolwiek znaczy. I musi nie kłamać w
  dwóch sytuacjach, w których łatwo skłamać:

  **Zero przebiegów to brak podstawy do orzekania, nie trzy nieprzejechane
  ścieżki.** Proces, który nigdy nie ruszył, ma wszystkie krawędzie
  nieprzejechane — i wypisanie ich jako znalezisk zamienia „nie ma danych" w
  „mamy trzy problemy". To ta sama zasada, na której stoi ocena assercji:
  bez `from` nie ma czego oceniać. Dlatego przy zerze przebiegów raport mówi
  `basis: :no_runs` i **pustą** listę.

  **Job czekający w kolejce to „jeszcze nie", nie „nigdy".** Ścieżka, której
  zdarzenie wyprodukuje job stojący w kolejce, jest wypisana osobno, a nie jako
  nieprzejechana. Bez tego raport kłamałby przy każdym normalnym opóźnieniu — i
  to jest lekcja, którą nakładka odrobiła jako czwarty stan.

  ## Granica

  Raport mówi o **ścieżkach**, nie o firmach. Jeśli 47 z 50 przebiegów nie
  przeszło ścieżką, znalezieniem jest ścieżka i liczba; które to przebiegi, jest
  pytaniem o stan biznesu i należy do aplikacji klienta.
  """

  alias PNS.{Deployment, Graph, Trace}

  @doc """
  All four of the screen's questions for one contract over a period, as data.

  This module produces the answers; it does not render them. The wording of a
  client-facing report belongs to the client application, because the engine
  cannot know the language its readers speak — every business string in here
  comes from the contract's own `label`, which is the one place written in the
  client's language.

  ## `unverified` declarations are omitted, not marked

  A process declaration the process owner has not confirmed **does not appear**.
  `mix pns.check` warns about it on every run, which is right for a developer
  check, but an evidence report is a different artifact with a different reader:
  a number the client never agreed to, printed next to numbers they did, reads as
  measured. A false metric is worse than a missing one when it is the metric the
  product sells.
  """
  @spec report(module(), keyword()) :: map()
  def report(contract, opts \\ []) do
    paths = untraversed_paths(opts)
    nodes = Graph.static().nodes
    labels = Map.new(nodes, &{to_string(&1.event), &1.label})
    declared_by = Map.new(nodes, &{to_string(&1.event), &1.contract})

    %{
      contract: contract,
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: Deployment.report(contract, opts),
      processes:
        for process <- contract.processes() do
          answers = Enum.find(paths, &(&1.process == process.name))

          %{
            process: process.name,
            label: process.label,
            runs: (answers && answers.instances) || 0,
            declarations: verified_declarations(process),
            untraversed: label_edges(answers && answers.untraversed, labels),
            in_flight: label_edges(answers && answers.in_flight, labels),
            assertions: assertions(contract, process, labels, opts)
          }
        end,
      drift: drift(contract, labels, declared_by, opts)
    }
  end

  @doc """
  Process declarations that may appear in an evidence report: those the process
  owner has confirmed.

  Public because it is the rule the acceptance criterion of stage 1.7 is about,
  and a rule that cannot be tested directly is a rule that quietly stops
  applying. `unverified` lists what is excluded.
  """
  @spec verified_declarations(map()) :: [%{key: atom(), value: term()}]
  def verified_declarations(process) do
    for key <- [:cadence, :deadline],
        key not in process.unverified,
        value = Map.get(process, key),
        not is_nil(value) do
      %{key: key, value: value}
    end
  end

  # **An assertion is reported as the sentence the process owner confirmed**, not
  # as its name. `trace` is the one declaration without a `label`, so a technical
  # atom is all a name could contribute — and a client-facing report that prints
  # `month_opens_or_is_blocked` fails the criterion of being readable without
  # explanation.
  #
  # Composing it from the event labels is not a workaround: those labels are the
  # words the client already agreed to, and the sentence they compose is the
  # assertion. Whether the process owner also wants to *name* assertions is a
  # question for the workshop, not for us — recorded in PLAN.md rather than
  # answered by adding a key.
  @spec assertions(module(), map(), map(), keyword()) :: [map()]
  defp assertions(contract, process, labels, opts) do
    for trace <- contract.traces(), contract.process_of(trace.from).name == process.name do
      verdicts = Trace.evaluate(contract, trace.name, opts)
      label = fn name -> name && Map.get(labels, to_string(name), to_string(name)) end

      %{
        trace: trace.name,
        from_label: label.(trace.from),
        eventually_label: label.(trace.eventually),
        or_else_label: label.(trace.or_else),
        within: trace.within
      }
      |> Map.merge(Trace.summary(verdicts))
    end
  end

  # A drift edge has no contract of its own: its **target** is undeclared, which
  # is what makes it drift, so there is nothing there to attribute. Its
  # **source** is declared, and that is what attributes the finding — otherwise
  # every contract's report would list every other contract's drift.
  @spec drift(module(), map(), map(), keyword()) :: [map()]
  defp drift(contract, labels, declared_by, opts) do
    for edge <- Graph.overlay(opts),
        edge.state == :drift,
        Map.get(declared_by, to_string(edge.from)) == contract do
      %{
        from: to_string(edge.from),
        to: to_string(edge.to),
        from_label: labels[to_string(edge.from)],
        to_label: labels[to_string(edge.to)],
        count: edge.count
      }
    end
  end

  @spec label_edges([map()] | nil, map()) :: [map()]
  defp label_edges(nil, _labels), do: []

  defp label_edges(edges, labels) do
    for edge <- edges do
      %{
        from: edge.from,
        to: edge.to,
        from_label: labels[to_string(edge.from)],
        to_label: labels[to_string(edge.to)],
        async: edge.async,
        in_flight: edge.in_flight
      }
    end
  end

  @doc """
  Ścieżki zadeklarowane w kontrakcie, którymi **nie przeszedł żaden przebieg**,
  pogrupowane po procesie.

  Zwraca też mianownik (`instances`) i osobno ścieżki czekające w kolejce, bo
  bez jednego i drugiego liczba nieprzejechanych ścieżek nie ma znaczenia.
  """
  def untraversed_paths(opts \\ []) do
    krawedzie =
      Graph.overlay(opts)
      # Tylko krawędzie **zadeklarowane**. Zaobserwowane-niezadeklarowane to drift,
      # czyli inne pytanie ekranu, i mieszanie ich w jednej liście robi z raportu
      # worek.
      |> Enum.filter(& &1.handler)
      |> Enum.group_by(& &1.process)

    # Iteracja po **procesach z rejestru**, nie po krawędziach z logu. Wersja
    # grupująca po krawędziach pomijała proces, który nie ma ani jednego
    # handlera — czyli cały kontrakt bramy uniwersalności był w raporcie
    # **nieobecny**. A nieobecność czyta się jako „nie ma o czym mówić", i to
    # jest ta sama cisza udająca zdrowie, którą ten produkt ma wykrywać.
    for contract <- PNS.Registry.contracts(), process <- contract.processes() do
      report(contract, process, Map.get(krawedzie, process.name, []))
    end
    |> Enum.sort_by(&to_string(&1.process))
  end

  # Proces bez ani jednej zadeklarowanej ścieżki. Może mieć przebiegi — i wtedy
  # to jest znalezisko samo w sobie: zdarzenia lecą, a nic nie jest podłączone.
  defp report(contract, process, []) do
    %{
      process: process.name,
      contract: contract,
      paths: 0,
      instances: 0,
      basis: :no_paths,
      untraversed: [],
      in_flight: []
    }
  end

  defp report(contract, process, edges) do
    runs = edges |> Enum.map(& &1.of_instances) |> Enum.max()

    %{
      process: process.name,
      contract: contract,
      # Mianownik dla samego znaleziska: „2 z 3 nieprzejechane" znaczy co innego
      # niż „2 z 40". Liczony tutaj, nie w drukarce, bo to część odpowiedzi.
      paths: length(edges),
      instances: runs,
      basis: if(runs > 0, do: :runs, else: :no_runs),
      untraversed: if(runs > 0, do: Enum.filter(edges, &untraversed?/1), else: []),
      in_flight: Enum.filter(edges, &(&1.in_flight > 0))
    }
  end

  # Nieprzejechana znaczy: **zero przebiegów** nią przeszło i nic na nią nie
  # czeka w kolejce. Licznik przebiegów, nie wystąpień — bo to jest jedyna
  # liczba, która przy wielu klientach odróżnia ciszę od braku ruchu.
  defp untraversed?(edge), do: edge.instances == 0 and edge.in_flight == 0
end
