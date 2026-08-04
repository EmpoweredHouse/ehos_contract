defmodule PNS.Graph do
  @moduledoc """
  Graf statyczny, graf zaobserwowany i ich nałożenie (notatki §5, §9).

  Graf statyczny = możliwe (nadzbiór). Graf zaobserwowany = faktyczne
  (podzbiór, ważony). **Iloczyn tych dwóch jest produktem.**

  Nakładka nie jest sumą dwóch grafów. Każda krawędź ma stan i dwa niezależne
  wymiary: wolumen i zdrowie. Krawędź, która odpaliła 50 000 razy, i taka, która
  odpaliła dwa razy, wyglądają identycznie w renderowaniu trójstanowym — stąd
  grubość osobno.

  Ten moduł **nie rysuje dashboardu**. Produkuje dane, na których dashboard
  stanie, i dzięki temu można sprawdzić, czy różnica jest sygnałem, czy szumem,
  zanim ktokolwiek narysuje pierwszy ekran.
  """

  import Ecto.Query

  @repo Application.compile_env!(:pns_prototype, :repo)

  alias PNS.{Event, Registry}

  @doc """
  Graf z deklaracji: węzły to zdarzenia z kontraktów, krawędzie z rejestru
  handlerów. Pochodzi z binarki, która działa, nie z pliku obok.
  """
  def static do
    nodes =
      for event <- Registry.declared_events() do
        %{
          event: event.name,
          label: event.label,
          owner: event.owner,
          contract: event.contract,
          contract_version: event.contract.version(),
          depends_on: event.depends_on,
          terminal?: terminal?(event)
        }
      end

    %{nodes: nodes, edges: Registry.edges()}
  end

  @doc """
  Graf z logu. Krawędź obserwowana to `causation_id` — zdarzenie, które
  powstało z innego zdarzenia. Nic więcej nie trzeba zapisywać, żeby odtworzyć
  faktyczny przebieg.
  """
  def observed(opts \\ []) do
    repo = repo()
    since = Keyword.get(opts, :since)

    events = from(e in Event, as: :event) |> maybe_since(since)

    node_counts =
      events
      |> group_by([event: e], [e.type, e.contract_version])
      |> select([event: e], {e.type, e.contract_version, count(e.id)})
      |> repo.all()
      |> Enum.reduce(%{}, fn {type, version, count}, acc ->
        Map.update(acc, type, %{count: count, versions: [version]}, fn existing ->
          %{count: existing.count + count, versions: [version | existing.versions]}
        end)
      end)

    edge_counts =
      events
      |> join(:inner, [event: e], parent in Event, on: e.causation_id == parent.id, as: :parent)
      |> group_by([event: e, parent: p], [p.type, e.type])
      |> select([event: e, parent: p], {p.type, e.type, count(e.id)})
      |> repo.all()
      |> Map.new(fn {from, to, count} -> {{from, to}, count} end)

    %{nodes: node_counts, edges: edge_counts}
  end

  @doc """
  Nałożenie. Trzy stany plus czwarty, który jest całym powodem, dla którego
  `contract_version` siedzi na zdarzeniu:

  | Stan | Znaczenie |
  |---|---|
  | `:confirmed` | zadeklarowane i zaobserwowane |
  | `:dead` | zadeklarowane, nigdy nie zaobserwowane — martwa ścieżka albo nieprzetestowana |
  | `:drift` | zaobserwowane, niezadeklarowane |
  | `:historical` | zaobserwowane pod inną wersją kontraktu — legalna historia, **nie** drift |

  Bez czwartego stanu każdy deploy, który usuwa zdarzenie, produkuje fałszywe
  alarmy, a dashboardowi przestaje się wierzyć w ciągu dwóch releasów.
  """
  def overlay(opts \\ []) do
    static = static()
    observed = observed(opts)

    declared_edges = MapSet.new(static.edges, &{to_string(&1.from), to_string(&1.to)})
    current_versions = MapSet.new(static.nodes, & &1.contract_version)

    from_declared =
      for edge <- static.edges do
        key = {to_string(edge.from), to_string(edge.to)}
        count = Map.get(observed.edges, key, 0)

        %{
          from: edge.from,
          to: edge.to,
          handler: edge.handler,
          async: edge.async,
          count: count,
          state: if(count > 0, do: :confirmed, else: :dead)
        }
      end

    from_observed =
      for {{from, to}, count} <- observed.edges, not MapSet.member?(declared_edges, {from, to}) do
        versions = get_in(observed.nodes, [to, :versions]) || []
        historical? = Enum.all?(versions, &(not MapSet.member?(current_versions, &1)))

        %{
          from: from,
          to: to,
          handler: nil,
          async: nil,
          count: count,
          state: if(historical?, do: :historical, else: :drift)
        }
      end

    from_declared ++ from_observed
  end

  @doc """
  Zdarzenia zadeklarowane i nigdy nie zaobserwowane.

  Okno jest tu słabym punktem i trzeba to powiedzieć wprost: prawidłowo
  pochodzi z `cadence:` procesu — instancja jest brakująca, kiedy minął cykl
  bez niej, nie kiedy minęło dowolne okno. Miesięczne zamknięcie flagowane jako
  martwe po tygodniu to szum, który zabija zaufanie do całego widoku.
  """
  def declared_never_observed(opts \\ []) do
    observed = observed(opts)

    for node <- static().nodes, not Map.has_key?(observed.nodes, to_string(node.event)) do
      process = Enum.find(node.contract.processes(), &(node.event in &1.events ++ &1.terminal))

      %{
        event: node.event,
        label: node.label,
        contract: node.contract,
        process: process && process.name,
        cadence: process && process.cadence
      }
    end
  end

  @doc """
  Diagram nakładki.

  Węzły są wypisywane **wszystkie**, także te bez żadnej krawędzi. Pierwsza
  wersja rysowała tylko krawędzie i przy jedenastu zadeklarowanych zdarzeniach
  pokazywała pięć — czyli niezaimplementowane fazy były niewidoczne dokładnie w
  narzędziu, które ma pokazywać, czego nie ma. Dla widoku *declared vs observed*
  to nie jest kosmetyka, a błąd.
  """
  def to_mermaid(overlay, opts \\ []) do
    static = static()
    # Stan węzła bierze się z liczników zdarzeń, **nie z krawędzi**. Pierwsza
    # wersja czytała go z krawędzi i pokazywała trzy zaobserwowane zdarzenia
    # jako martwe — bo nikt na nie nie subskrybuje, więc nie występują w żadnej
    # krawędzi. Zdarzenie może być zaobserwowane bez ani jednej krawędzi i to
    # jest normalny przypadek, nie wyjątek.
    observed = observed(opts).nodes

    nodes =
      for node <- static.nodes do
        entry = Map.get(observed, to_string(node.event))
        state = if entry, do: "confirmed", else: "dead"
        {node.event, state, node.label, entry && entry.count}
      end

    node_lines =
      for {event, _state, label, count} <- nodes do
        suffix = if count, do: " (#{count}x)", else: ""
        ~s(    #{event}["#{label}#{suffix}"])
      end

    edge_lines =
      for edge <- overlay do
        # `-. tekst .->` i `|etykieta|` wykluczają się w składni mermaida —
        # dla strzałki kropkowanej wszystko idzie w pipe'y.
        {arrow, label} =
          if edge.async,
            do: {"-.->", "#{edge.count}x async"},
            else: {"-->", "#{edge.count}x"}

        "    #{edge.from} #{arrow}|#{label}| #{edge.to}"
      end

    class_lines =
      nodes
      |> Enum.group_by(fn {_e, state, _l, _c} -> state end, fn {e, _s, _l, _c} -> e end)
      |> Enum.map(fn {state, events} -> "    class #{Enum.join(events, ",")} #{state}" end)

    Enum.join(
      ["flowchart LR"] ++
        node_lines ++
        edge_lines ++
        class_lines ++
        [
          "    classDef confirmed fill:#c8e6c9,stroke:#2e7d32,color:#000",
          "    classDef dead fill:#eeeeee,stroke:#9e9e9e,color:#616161,stroke-dasharray: 4 3"
        ],
      "\n"
    )
  end

  def to_text(overlay) do
    overlay
    |> Enum.sort_by(&{&1.state, -&1.count})
    |> Enum.map_join("\n", fn edge ->
      mode = if edge.async, do: "async", else: "sync "
      state = edge.state |> Atom.to_string() |> String.pad_trailing(10)
      "  #{state} #{mode}  #{edge.from} -> #{edge.to}  (#{edge.count}x)"
    end)
  end

  defp terminal?(event) do
    Enum.any?(event.contract.processes(), &(event.name in &1.terminal))
  end

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [event: e], e.occurred_at >= ^since)

  defp repo, do: @repo
end
