defmodule ProcessShapes.Rig do
  @moduledoc """
  # TO NIE JEST DOMENA I NIE UDAJE ŻADNEJ.

  Stanowisko badawcze dla **kształtów procesu** z etapu 1.3. Nazwy są celowo
  bezbarwne — `item`, `case`, `pairing` — bo gdyby brzmiały jak księgowość albo
  jak medycyna, ktoś przeczytałby to jako wiedzę o domenie. Nie ma tu ani
  jednego twierdzenia o czyimkolwiek procesie.

  Dlaczego osobny plik, a nie handlery dopięte do kontraktu bramy
  uniwersalności: ten drugi jest artefaktem etapu 1.2 i jego wartość polega na
  tym, że jest **kontraktem bez implementacji**. Jest też jedyną fikstórą, na
  której da się sprawdzić raport dla procesu bez ani jednej zadeklarowanej
  ścieżki. Dopięcie handlerów zabrałoby oba te pokrycia.

  ## Po co to jest

  Plan produktowy wymienia kształty, które biblioteka musi obsłużyć niezależnie
  od domeny. Trzy z nich wymagają **handlerów**, więc żaden kontrakt bez
  implementacji ich nie sprawdzi:

  | Kształt | Gdzie tutaj |
  | --- | --- |
  | Krok, który się cofa | `OnClarificationAnswered` — subskrybuje w `resolution`, publikuje do `matching` |
  | To samo zdarzenie wiele razy w jednym przebiegu | `item_paired`, raz na pozycję |
  | Zdarzenie wchodzące bez komendy | `item_received` — wpada z zewnątrz, bez aktora |

  Kształt „krok, który się cofa" jest kryterium odbioru 1.3 i jest tu
  **zbudowany celowo**, razem z trzema kontrolami, które krawędzią wsteczną
  **nie są**. Sam fakt, że check znajduje skonstruowany przypadek, nic nie
  dowodzi — dowodem jest to, że nie znajduje go w pozostałych trzech.

  Kształt odpowiadający warsztatowemu „obrót bez faktury, potem para się
  domyka" — bo tak wygląda każda kompensacja, nie tylko księgowa.
  """

  use PNS.Contract

  event :item_received,
    label: "Wpłynęła pozycja do sparowania",
    owner: ProcessShapes.Intake,
    # **Zdarzenie wchodzące bez komendy.** Nikt go u nas nie wywołał, więc
    # payload musi nieść tożsamość przebiegu sam z siebie i nie ma aktora.
    payload: %{case_id: :id, item_no: :integer, amount: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_paired,
    label: "Pozycja sparowana",
    owner: ProcessShapes.Matching,
    # **To samo zdarzenie wiele razy w jednym przebiegu.** Tożsamość faktu
    # zawiera numer pozycji, tożsamość przebiegu nie.
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :matching

  event :pairing_unresolved,
    label: "Pozycja bez pary",
    owner: ProcessShapes.Matching,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :matching

  event :clarification_requested,
    label: "Poproszono o wyjaśnienie",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  event :clarification_answered,
    label: "Wyjaśnienie dostarczone",
    owner: ProcessShapes.Resolution,
    # Też wchodzi bez komendy — odpowiedź przychodzi z zewnątrz.
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  event :case_closed,
    label: "Sprawa zamknięta",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, paired: :integer},
    process: :pairing,
    stage: :resolution,
    terminal: true

  process :pairing,
    label: "Parowanie pozycji",
    stages: [:intake, :matching, :resolution],
    instance: [:case_id]
end

defmodule ProcessShapes.Intake do
  @moduledoc "Właściciel fazy `intake`. Czysta decyzja, zero wejścia/wyjścia."

  def decide(%{amount: amount}) when amount > 0, do: :pair
  def decide(_), do: :unresolved
end

defmodule ProcessShapes.Matching do
  @moduledoc """
  Właściciel fazy `matching`.

  **Repo z konfiguracji, nie referencją do modułu klienta** — dokładnie jak
  `PNS.Emitter`. Wskazanie `Taxvision.Repo` wprost dawało naruszenie granicy
  (`boundary`: „not a sibling, a parent, or a dep of some ancestor") i słusznie:
  stanowisko badawcze silnika nie ma prawa sięgać do drzewa klienta.
  """

  import Ecto.Query

  @repo Application.compile_env!(:pns_prototype, :repo)

  @doc """
  Ile pozycji w **tym przebiegu** ma dany stan.

  Liczone po `instance_id`, nie po typie zdarzenia — bo to samo zdarzenie
  występuje w jednym przebiegu wiele razy, a licznik per typ policzyłby cudze
  pozycje. To jest ten sam błąd, który etap 1.1 naprawiał w nakładce, tylko
  popełniony wewnątrz handlera.
  """
  def count(case_id, type) do
    instance_id = "pairing|#{case_id}"
    # Przez zmienną, nie przez `@repo.aggregate(...)` wprost — i to jest powód,
    # dla którego `PNS.Emitter` ma tę samą, z pozoru zbędną indirekcję.
    # Atrybut w pozycji wywołania rozwija się do **literału modułu**, więc
    # `boundary` widzi referencję i słusznie ją odrzuca.
    repo = repo()

    repo.aggregate(
      from(e in PNS.Event, where: e.instance_id == ^instance_id and e.type == ^type),
      :count
    )
  end

  defp repo, do: @repo

  @doc "Sprawa domyka się, kiedy każda nierozstrzygnięta pozycja dostała wyjaśnienie."
  def closable?(case_id) do
    count(case_id, "pairing_unresolved") <= count(case_id, "clarification_answered")
  end
end

defmodule ProcessShapes.Resolution do
  @moduledoc "Właściciel fazy `resolution`. Tu mieszka krok, który się cofa."
end

defmodule ProcessShapes.Intake.OnItemReceived do
  @moduledoc false

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_received,
    publishes: [:item_paired, :pairing_unresolved]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no} = payload, _ctx) do
    base = %{case_id: case_id, item_no: item_no}

    case ProcessShapes.Intake.decide(payload) do
      :pair -> {:ok, [PNS.event(:item_paired, base)]}
      :unresolved -> {:ok, [PNS.event(:pairing_unresolved, base)]}
    end
  end
end

defmodule ProcessShapes.Matching.OnPairingUnresolved do
  @moduledoc "Kontrola: `matching` → `resolution`, czyli do przodu."

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :pairing_unresolved,
    publishes: [:clarification_requested]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:clarification_requested, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Resolution.OnClarificationAnswered do
  @moduledoc """
  **Kryterium odbioru 1.3: krok, który się cofa.**

  Subskrybuje `clarification_answered` z fazy `resolution` i publikuje
  `item_paired` z fazy `matching` — czyli para domyka się **wstecz**, po tym jak
  proces poszedł już dalej. Warsztat opisuje dokładnie ten kształt: obrót bez
  faktury, potem faktura dochodzi i para się domyka.

  `mix pns.check` **ma to zgłosić**. Jedna krawędź wsteczna jest normalna;
  rosnąca liczba znaczy, że decyzja ADR §15 „procesy obserwowane, nie kierowane"
  się nie sprawdza — i o tym mówi trigger przeglądu.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :clarification_answered,
    publishes: [:item_paired]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_paired, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Matching.OnItemPaired do
  @moduledoc """
  Kontrola: `matching` → `resolution`, do przodu.

  Zamyka sprawę, kiedy nic nie zostało nierozstrzygnięte. Liczy **z logu, po
  tożsamości przebiegu** — bo to samo zdarzenie występuje w jednym przebiegu
  wiele razy i licznik per typ zdarzenia policzyłby cudze pozycje.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_paired,
    publishes: [:case_closed]

  @impl PNS.Handler
  def handle(%{case_id: case_id}, _ctx) do
    if ProcessShapes.Matching.closable?(case_id) do
      sparowane = ProcessShapes.Matching.count(case_id, "item_paired")
      {:ok, [PNS.event(:case_closed, %{case_id: case_id, paired: sparowane})]}
    else
      :ok
    end
  end
end
