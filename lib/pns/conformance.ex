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

  alias PNS.Graph

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
