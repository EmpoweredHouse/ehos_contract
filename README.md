# Prototyp PNS — kontrakt, moduły, jeden proces z eventami

Środowisko testowe dla decyzji 008 (`empowered-house-context/decisions/008-pns-runtime-architecture.md`).
Jeden ograniczony proces z warsztatu TaxVision, zaimplementowany po to, żeby sprawdzić twierdzenia, których
proza nie rozstrzyga.

## Uruchomienie

```bash
docker compose up -d && mix deps.get && mix ecto.setup && mix check
```

`mix check` to `compile --warnings-as-errors`, `pns.check` i `test`. Musi przechodzić.

```bash
mix pns.graph                # graf statyczny z rejestru
mix pns.graph --overlay      # nałożony na log zdarzeń
mix pns.graph --mermaid      # diagram
mix pns.trace                # ocena assercji `trace` z logu, per przebieg
mix pns.trace --instances    # to samo z pojedynczymi przebiegami (widok do debugowania)
mix pns.check                # sprawdzenia całoprogramowe
```

Postgres słucha na **5433**, nie 5432 — lokalny Postgres bywa zajęty, a to ma stać na czystej maszynie bez
pytania, co jeszcze nasłuchuje.

## Trzy rozstrzygnięcia z góry

**Kod zostaje.** Struktura jest ta, którą notatki §15 przewidują dla pierwszego klienta: `lib/pns/` (to, co
będzie pakietem) obok `lib/taxvision/` (aplikacja klienta), granica pilnowana przez `boundary`. Przeniesienie
obok repozytorium klienta jest `git mv`.

**To nie jest template.** Przegląd z 3 sierpnia ostrzegł, że spike bez tej deklaracji staje się tym
template'em, którego §16–17 odmawia budować. Zabezpieczenie jest mechaniczne, nie deklaratywne: **nie ma
`mix pns.new`** (§15 stawia to przy drugim kliencie), nie ma generycznego wyciągu, drzewo klienckie nazywa
się `taxvision`, nie `my_app`.

**Tożsamość jest w zakresie, ale bez providera.** Szew jest prawdziwy — behaviour, walidacja podpisu, zero
credentiali w silniku. Implementacją jest lokalny HMAC, nie Zitadel: stawianie providera dla prototypu to
koszt bez sygnału. Podmiana na `oidcc` to jedna linia w `config.exs`, co jest całym sensem szwu.

## Czego tu celowo nie ma

| | Dlaczego |
|---|---|
| Dashboard | Najpierw sprawdzić, czy różnica jest sygnałem. `PNS.Graph` produkuje dane, na których dashboard stanie — patrz *Dashboard* niżej |
| Wyświetlanie logu | Log jest zapisywany i odpytywany, nie renderowany |
| Warstwa web, API | `Taxvision.Api` jest odpowiednikiem pipeline'u Phoenixa napisanym bez Phoenixa. REST przeciw GraphQL jest w decyzji 008 otwarte — budowanie API przesądzałoby otwartą decyzję |
| `mix pns.new` | §15 krok 2: dopiero przy drugim kliencie |
| Prawdziwe rejestry, prawdziwy mail | Behaviour plus fake |
| Fazy 3.2–3.4 | Zadeklarowane w kontrakcie, nieobsłużone. To demo stanu *declared, never observed*, nie niedokończona robota |

## Wynik: co przeszło, co się zmieniło pod ręką

38 testów, 0 błędów. Cztery twierdzenia potwierdzone, jedno dowiezione w połowie.

**1. Kontrakt jako moduł Elixira — działa.** DSL akumulujący `event`/`process`/`trace`/`external`/`rule`/
`example`, `@before_compile` generujący zapytania, `version/0` jako hash deklaracji. Jeden proces z
warsztatu to 11 zdarzeń i ~180 linii deklaracji. Czyta się.

**2. Podział dispatchu po granicy transakcji — działa, i semantyka awarii jest taka, jak zapisano.** Handler
synchroniczny, który rzuci, cofa zdarzenie, jego skutki i wstawiony job. `emit/4` ma 50 linii, więc argument
za własną warstwą emisji zamiast `oban-events` stoi.

**3. Reguła bez przykładu nie kompiluje się — działa. „Przykład jest testem" — w połowie.** Brama §18 jest
prawdziwa i jest testem. Ale kontrakt trzyma **MFA, nie capture**, żeby nie zależeć od domeny w czasie
kompilacji — więc rozwiązanie funkcji następuje w runtime testu, przez generator w
`contract_examples_test.exs`. Rekord twierdzi mocniej, niż dowozi: przykład jest testem *pod warunkiem, że
ktoś napisał ten generator*. To jedna linia do poprawienia w §18, nie zmiana decyzji.

**4. Trzy poziomy IAM są rozdzielone w kodzie — działa.** Jedna ścieżka żądania, trzy różne odpowiedzi:
podpis nie pasuje → `:unauthenticated`; brak claimu `accounting` → `:forbidden` **przed** kodem domenowym,
weryfikowane brakiem wiersza w logu; rola jest, ale to nie jej firma → odrzucenie regułą z kontraktu, jako
zapisany przypadek. Trzeciego nie da się przejść konfiguracją providera, bo provider nie wie, czym jest
miesiąc księgowy.

**5. Hook Ecto istnieje — odroczenie confinementu jest bezpieczne.** `prepare_query/3` dostaje cały
`%Ecto.Query{}` przed wykonaniem, więc tabele wychodzą strukturalnie z `from` i `joins`. Szkielet
odłożonego checka leży w `Taxvision.Repo`, wyłączony. Ograniczenia i pułapka z nazwą tabeli joina — w
docstringu tego modułu.

**`boundary` faktycznie pilnuje.** Sprawdzone celowym naruszeniem: odwołanie z `Taxvision.Tasks` do schematu
`Taxvision.Notifications` daje `forbidden reference`, a `mix compile --warnings-as-errors` zwraca 1. Bez tego
przełącznika granice są dokumentacją — samo `boundary` raportuje ostrzeżenia.

## Findings: co trzeba było dołożyć do wyniku warsztatu

To jest bezpośredni test twierdzenia, że wynik warsztatu jest **discovery-grade, nie generation-grade**
(ADR §1). Nazwy zdarzeń, polityka P1, aktorzy i niezmienniki agregatu przyszły z warsztatu. Wszystko
poniżej trzeba było wymyślić, żeby to się skompilowało:

| Czego brakowało | Co zrobiliśmy | Kto powinien to rozstrzygnąć |
|---|---|---|
| **Kształty payloadów.** Warsztat daje nazwy zdarzeń i polskie opisy, zero pól | Każde pole wymyślone | Warsztat, jedna sesja na proces |
| **Słownik typów.** Okazał się nośny: `:string` dla wszystkiego zrobiło z checka retencji szum na 33 pozycje | `:id`, `:period`, `:timestamp`, `:enum`, `:string` = tekst wpisany przez człowieka | My — to jest decyzja narzędziowa |
| **Ścieżki błędów.** „Blokada i powiadomienie" jest w P1; co przy niedostępnym rejestrze, nie ma nigdzie | `unavailable_looks_like`: zawieszenie, nie negatywna weryfikacja | Warsztat — to jest pytanie prawne, nie techniczne |
| **Klucze idempotencji.** Brak w całym warsztacie | `company_id` + `period` | My, ale wymaga potwierdzenia |
| **Stany terminalne.** Stepper nie mówi, co kończy proces | Zablokowanie na rozjeździe jest terminalne tak samo jak zamknięcie miesiąca | Process owner |
| **Kolejność.** Warsztat daje DAG i mówi wprost „fazy nie są w pełni sekwencyjne"; pierwsza wersja kontraktu chciała płaskiej listy | Format zmieniony: `stages:` — kolejność między fazami, brak twierdzeń wewnątrz fazy | Rozwiązane, patrz niżej |
| **Deadline 25 dni** | Wzięty z przykładu w notatkach, **nie z warsztatu** | Warsztat. Jedyna liczba w tym kontrakcie bez źródła |
| **Reguła autoryzacyjna** | Wywnioskowana z HS28 i z tego, że aktorem fazy 3.1 jest Księgowa | Warsztat |
| **Komendy** | `RetriggerVerification` z warsztatu pominięta | Do dołożenia przy pętli ponowienia |

Wniosek jest zgodny z ADR §1 i mocniejszy, niż się spodziewałem: **z warsztatu wyszło jakieś 40% kontraktu,
i to ta łatwiejsza część.** Nazwy i przepływ są darmowe. Typy, ścieżki błędów, niezmienniki i idempotencja to
druga sesja z klientem, nie praca programisty.

## Trzy poprawki formatu po pierwszym przebiegu

Rdzeń DSL wytrzymał kontakt z prawdziwą domeną — sześć typów deklaracji, `@before_compile`, hash wersji.
Ale trzy rzeczy w formacie były źle postawione i są już poprawione.

**Idempotencja wróciła do kontraktu.** Klucz siedział na handlerze (`idempotency_key:`), co było zgodne z
notatkami §4 i **sprzeczne z ADR §9–10**, który mówi wprost, że idempotencja jest własnością kontraktu.
Rację ma ADR, z dwóch powodów. Pytanie „dwa rozjazdy w jednym miesiącu to jedno powiadomienie czy dwa"
należy do process ownera, a on czyta kontrakt, nie moduły handlerów. I tożsamość faktu jest jedna, a
handlerów tego samego zdarzenia może być wiele — trzymana na handlerze rozjeżdżałaby się między nimi.

Teraz zdarzenie deklaruje `identity: [:company_id, :period]`, a handler asynchroniczny bez tego się nie
kompiluje — z komunikatem odsyłającym do kontraktu. Doszły dwie bramki: pole z `identity` musi istnieć w
payloadzie i nie może być usuwane przez `retain: :drop`, bo klucz zniknąłby razem z nim.
**Do zmiany w notatkach §4.**

**Przykłady pinują regułę, nie całe wyjście funkcji.** `then:` znaczy teraz „wśród wyemitowanych zdarzeń,
w tej kolejności", nie „dokładnie te". Wcześniej przykład reguły *„bez zgodnej weryfikacji miesiąc się nie
otwiera"* wymieniał cztery zdarzenia, z czego trzy nie miały z tą regułą nic wspólnego — dodanie jednego
zdarzenia do przepływu wywalało wszystkie przykłady tej reguły, choć reguła się nie zmieniła. Przy
pięćdziesięciu regułach to maszyna do fałszywych alarmów, czyli do wyłączenia testów. Po poprawce przykłady
tej reguły wymieniają jedno zdarzenie i **czytają się jak reguła**.

**Kolejność jest między fazami, nie między zdarzeniami.** Zamiast płaskiej listy `events:` proces deklaruje
`stages:`. Warsztat mówi jedno i drugie: *„to jest jeden długi proces"* oraz *„fazy nie są w pełni
sekwencyjne … sekwencyjne są **bramki**"*. Liniowa lista była naszym pomysłem podanym jako model klienta —
a na niej stało wykrywanie krawędzi wstecznych, czyli trigger przeglądu §15. Teraz krawędź wsteczna liczy
się po fazach: dwa zdarzenia tej samej fazy nigdy nią nie są, bo kontrakt nie twierdzi nic o ich kolejności.
`events:` zostaje jako skrót dla procesu bez bramek i znaczy dokładnie tyle: jedna faza, zero twierdzeń.

**Do zmiany w notatkach §1:** `stages:` i `identity:` w przykładzie DSL, oraz słownik typów payloadu.

## Czwarta poprawka formatu: przynależność deklaruje zdarzenie, nie proces

Wyszła z pytania „po co w ogóle jest `process`" zadanego przy czytaniu kontraktu — czyli z czytelności, nie
z awarii. Ale odpowiedź okazała się mocniejsza niż kosmetyczna.

Było tak, że proces wymieniał swoje zdarzenia w `stages:`, więc **każda nazwa zdarzenia była w kontrakcie
napisana dwa razy**: raz w `event`, raz w liście fazy. Jedenaście zdarzeń to dwadzieścia dwie wzmianki,
dodanie zdarzenia to dwie edycje oddalone o sto linii, a czytając `event` nie wiedziałeś, gdzie ono siedzi.

Teraz zdarzenie mówi o sobie samo:

```elixir
event :month_closed,
  label: "Zamknięto miesiąc księgowy",
  payload: %{company_id: :id, period: :period},
  process: :accounting_month,
  stage: :closing,
  terminal: true

process :accounting_month,
  label: "Cykl miesięczny księgowy",
  stages: [:verification, :opening, :collection, :matching, :closing],
  instance: [:company_id, :period],
  cadence: {1, :month}
```

Podział przebiega po pytaniu **„ilu tego jest"** — tej samej regule, która rozstrzygnęła `identity` kontra
`instance`. Faza i terminalność są jedne na zdarzenie, więc idą na zdarzenie. Kadencja, termin i tożsamość
przebiegu są jedne na proces. W `process` zostaje **porządek faz**, bo to jedyna rzecz, której zdarzenie nie
może o sobie powiedzieć.

**Jedna brama kompilacyjna przez to zniknęła i to jest wynik, nie regres.** „Zdarzenie należy do co najwyżej
jednego procesu" było sprawdzeniem — przy pojedynczym kluczu `process:` stało się **niewyrażalne**. To jest
warunek stopu z ADR §15 (*„stop if processes nest or one event belongs to two"*) załatwiony kształtem
deklaracji zamiast checkiem. **Do poprawienia w rekordzie**, bo notatka z 5 sierpnia mówi jeszcze „błąd
kompilacji".

W zamian doszły trzy bramy pilnujące nowego kształtu: zdarzenie nie wskaże nieistniejącego procesu ani
nieistniejącej fazy, a zdarzenie w procesie z fazami musi powiedzieć, w której jest — bo inaczej byłoby
dziurą w wykrywaniu krawędzi wstecznych. `events:` zniknęło z `process` całkowicie.

## Dashboard — co wyszło, zanim cokolwiek narysowaliśmy

Nakładka jest policzalna dwoma zapytaniami: węzły z `pns_events`, krawędzie z self-joina po `causation_id`.
Nic więcej nie trzeba zapisywać, żeby odtworzyć faktyczny przebieg.

**Job w locie wyglądał dokładnie jak martwa ścieżka — poprawione.** Po trzech przebiegach nakładka
pokazywała `registry_discrepancy_detected -> discrepancy_notification_sent` jako `dead (0x)`, choć przebieg
wszedł w tę gałąź; job czekał w kolejce. Bez tego dashboard kłamałby przy każdym normalnym opóźnieniu.

Nakładka ma teraz **cztery stany**: `confirmed`, `in_flight`, `dead`, `historical`. `in_flight` czyta stan
kolejki Obana, a lista *zadeklarowane, nigdy nie zaobserwowane* pomija zdarzenia, które wyprodukuje job
czekający w kolejce — bo inaczej lista i stan krawędzi mówiłyby dwie różne rzeczy o tym samym zdarzeniu.

**Rodzeństwo jednej komendy dostało własny rodzaj krawędzi.** Trzy zdarzenia otwierające miesiąc nie mają
między sobą przyczynowości — powstają razem, z jednej komendy — więc wisiały na diagramie bez połączeń i
wyglądały na błąd. Rysowane są teraz linią **kropkowaną bez grotu**, z podpisem „ta sama komenda", liczone
po `correlation_id` przy `causation_id IS NULL`. Osobny styl jest tu istotny: gdyby wyglądały jak strzałki,
ktoś przeczytałby je jako przyczynowość i zbudował na tym logikę.

**`contract_version` robi to, po co jest.** Test wstawia zdarzenie pod wersją kontraktu, której już nie ma w
binarce, i nakładka klasyfikuje je jako `:historical`, nie `:drift`. Bez tej kolumny każdy deploy usuwający
zdarzenie produkuje fałszywe alarmy.

**Renderer diagramu miał dwa błędy, które widać tylko na wyjściu.** Pierwsza wersja rysowała wyłącznie
krawędzie, więc z jedenastu zadeklarowanych zdarzeń pokazywała pięć — niezaimplementowane fazy były
niewidoczne dokładnie w narzędziu, które ma pokazywać, czego nie ma. Po poprawce trzy zdarzenia wyszły jako
martwe, choć były w logu: brałem stan węzła z krawędzi, a `data_completeness_confirmed` nie ma żadnej
krawędzi, bo nikt na nie nie subskrybuje. **Zdarzenie może być zaobserwowane bez ani jednej krawędzi** i to
jest normalny przypadek. Stan węzła idzie z liczników zdarzeń, stan krawędzi z `causation_id`.

**Trzy zdarzenia otwierające wiszą bez strzałek — i to jest prawda, która wygląda na błąd.** Emituje je
jedna funkcja decyzyjna jako rodzeństwo jednej komendy, więc nie ma między nimi przyczynowości i graf
słusznie jej nie rysuje. Dla process ownera wygląda to jednak na trzy niepowiązane fakty. Kandydat na
czwarty rodzaj krawędzi w nakładce: „w tej samej komendzie", rysowany z `correlation_id`.

**Graf jest dekoracją, lista nie.** 11 zdarzeń daje 3 krawędzie i diagram nie powiedział nic, czego nie
mówiła posortowana lista. Notatki §9 mają rację, że domyślnym widokiem jest lista rozbieżności. Diagram
zaczyna zarabiać przy kilkudziesięciu krawędziach, czyli nie w pilocie.

**Wypis przez potok psuł polskie znaki.** `mix pns.graph --mermaid > plik.mmd` zamieniał `ł` (U+0142) na
`B` (0x42): Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, i przycina każdy kodepoint do
bajtu. Etykiety zdarzeń są po polsku, bo to język klienta — więc to nie kosmetyka, a uszkodzony artefakt.
Oba zadania wymuszają teraz `encoding: :unicode`, a `pns.graph` ma `--output`, które pisze plik przez
`File.write!`. Diagram w `doc/graf-nakladki.png` jest generowany tak:

```bash
mix pns.graph --overlay --mermaid --output doc/graf-nakladki.mmd
mmdc -i doc/graf-nakladki.mmd -o doc/graf-nakladki.png -b white -s 3
```

Jeśli `mmdc` zgłosi brak `chrome-headless-shell` w konkretnej wersji, a w `~/.cache/puppeteer/` leży
inna — wskaż mu ją zamiast pobierać drugą przeglądarkę:
`mmdc … -p <(echo '{"executablePath":"'"$HOME"'/.cache/puppeteer/chrome-headless-shell/<wersja>/chrome-headless-shell-mac-arm64/chrome-headless-shell"}')`

Diagram w repo jest generowany z **danych demonstracyjnych**, nie z prawdziwego przebiegu: pięć firm w
jednym miesiącu, trzy przechodzą weryfikację, dwie idą w blokadę, kolejka zatrzymana. Bez zatrzymanej
kolejki czwarty stan nakładki nie miałby czego pokazać.

## Graf z kontraktu — czy to ma szanse

Ma, z jednym zastrzeżeniem, które warto znać.

Krawędzie pochodzą z deklaracji `publishes:`, nie z czytania ciał funkcji. Makro sprawdza, że deklaracja
zgadza się z kontraktem — **nie sprawdza, czy handler publikuje tylko to, co zadeklarował.** Do tego
potrzebny jest tracer kompilacji z notatek §2, którego tutaj nie ma.

Skutek jest lepszy, niż się wydaje: handler publikujący coś niezadeklarowanego tworzy prawdziwą krawędź w
logu, więc nakładka pokazuje ją jako **`drift`**. To, co tracer wyłapałby przed wdrożeniem, log wyłapuje po
pierwszym przebiegu. Tracer jest optymalizacją momentu wykrycia, nie warunkiem poprawności — i to jest
argument, żeby go teraz nie budować.

## Struktura

```
lib/pns/          to, co będzie pakietem hex
  contract.ex     DSL, @before_compile, brama §18, version/0
  handler.ex      sprawdzenia w ciele makra, zależność kompilacyjna od kontraktu
  registry.ex     skan binarki przy boocie, :persistent_term
  emitter.ex      emit/4 — cały §9 w jednej funkcji
  event.ex        log zdarzeń i log obsług
  job.ex          worker Obana, korelacja przez granicę procesu
  auth.ex         szew tożsamości: behaviour + lokalny HMAC
  instance.ex     tożsamość przebiegu: klucz z `instance:`, liczony przy emisji
  graph.ex        statyczny, zaobserwowany, nałożenie
lib/taxvision/    aplikacja klienta
  contracts/      kontrakt na proces
  api.ex          krawędź żądania: trzy poziomy IAM
  registry_check.ex    czysta funkcja decyzyjna (polityka P1)
  authorization.ex     czysta funkcja: reguła domenowa
  tasks.ex, accounting_month.ex, notifications.ex    moduły z własnymi tabelami
  adapters/       behaviour + fake
test/support/
  universality_gate/   drugi kontrakt, WYMYŚLONY — brama uniwersalności, nie klient
```

## Instancja procesu — co zmieniło się 5 sierpnia

`identity` odpowiada na pytanie „co czyni dwa wystąpienia **tym samym faktem**". Brakowało odpowiedzi na
inne: „co czyni dwa zdarzenia częścią **tego samego przebiegu**". Proces deklaruje teraz
`instance: [:company_id, :period]`, a każde jego zdarzenie musi te pola nieść — inaczej się nie kompiluje.

**To nie jest pole sprawozdawcze.** Bez niego assercja *„po potwierdzeniu kompletu danych miesiąc się
otwiera"* jest prawdziwa globalnie, kiedy otworzył się **czyjkolwiek** miesiąc. Test dwóch równoległych
przebiegów pokazuje to wprost: c-1 się otwiera, c-2 idzie w blokadę, a licznik per typ zdarzenia zalicza oba.

**Liczniki mają dwa wymiary i osobno każdy kłamie.** Krawędź przejechana 49 razy przez jedną firmę i raz
przez 49 firm miały identyczny licznik. Nakładka podaje teraz wystąpienia, przebiegi i mianownik — ile
przebiegów procesu w ogóle było. Świadomie jest to **liczba, nie lista**: które przebiegi milczą, to pytanie
o konkretną firmę i należy do aplikacji klienta.

**Dwie bramy wyszły z jednej kolumny w logu.** `instance_id` jest jedno na zdarzenie, więc zdarzenie
należące do dwóch procesów nie ma jednej tożsamości przebiegu — i nie kompiluje się. To jest warunek stopu
z ADR §15 („*stop if processes nest or one event belongs to two*") zrobiony mechanicznie, zamiast czekać na
przegląd. Z tego samego powodu `trace` nie może rozciągać się na dwa procesy.

**Brama zapłaciła za siebie przy pierwszym uruchomieniu.** `turnover_matched_with_invoice` niosło
`company_id`, `turnover_id` i `invoice_id`, ale nie `period` — więc sparowany obrót nie mówił, do którego
miesiąca należy, i meczowanie z lipca liczyłoby się jako postęp w przebiegu sierpniowym. Jedno z jedenastu
zdarzeń, wykryte kompilatorem, nie przeglądem.

**Zdarzenia sprzed tego etapu nie dostaną tożsamości przebiegu wstecz.** Kolumny są nullowalne, a raport
pisze przy nich „bez tożsamości przebiegu", nie „0 przebiegów" — bo drugie czytałoby się jako cisza, a to
jest historia. Ten sam problem, który przy wersjach kontraktu rozwiązuje stan `:historical`.

## Brama uniwersalności — przeszła, i co przy okazji pokazała

Do 5 sierpnia dowód na to, że DSL nie jest księgowy, brzmiał *„jeden kontrakt, jedna domena, jeden autor"* —
czyli nie był dowodem. `UniversalityGate.TreatmentEpisode` w `test/support/` opisuje epizod leczenia od
skierowania do zamknięcia. **Ani jednego nowego słowa w DSL.**

Ten kontrakt jest **wymyślony w całości** i ma to napisane w pierwszej linii moduledoca. Warsztatu z Rehmed
jeszcze nie ma; gdyby ten plik udawał kontekst kliencki, byłby dokładnie tym rodzajem zmyślonej wiedzy o
domenie, którą PNS ma wykrywać u innych. Nie jest drzewem klienta i nie idzie do repozytorium kontekstu.

**Kryterium jest teraz testem, nie zdaniem.** `PNS.Contract.vocabulary/0` wystawia słownik maszynowo, a test
porównuje go z literałem. Dopisanie do DSL słowa specyficznego dla domeny — na czele z `population`, jedynym,
które ten test kiedykolwiek oblało — wywala go tego samego dnia, a nie przy przeglądzie za kwartał.

Cztery rzeczy wyszły przy okazji i żadna nie jest brakującym słowem:

**`cadence` nie ma zastosowania do procesu zdarzeniowego.** Miesiąc księgowy jest należny co miesiąc; epizod
leczenia nie jest należny nigdy — zaczyna się, kiedy wpłynie skierowanie. Słowo jest opcjonalne, więc DSL
przechodzi. Ale okno *„never observed"* liczy się właśnie z kadencji, więc dla procesów zdarzeniowych nie ma
skąd wziąć długości i spada na fallback z zaobserwowanych odstępów. Notatki §9 traktują ten fallback jako
przypadek brzegowy — **dla całej klasy procesów jest stanem normalnym.**

**„Kontrakt plus fake'i, bez implementacji" nie jest osiągalne, jeśli kontrakt ma regułę.** Brama §18 wymaga
przykładu, przykład wskazuje MFA, `pns.check` sprawdza, że funkcja istnieje. Albo kontrakt bramy nie
deklaruje reguł — i wtedy §18 zostaje nieprzetestowane na drugiej domenie — albo dochodzi jedna czysta
funkcja decyzyjna. Doszła jedna, i to jest poprawka do opisu zakresu, nie do bramy.

**`identity` i `instance` razem uniosły kształt, którego TaxVision nie ma.** Dziesięć wizyt w jednym epizodzie
to dziesięć faktów w jednym przebiegu: `identity: [:episode_id, :session_no]` przy `instance: [:episode_id]`.
Gdyby to było jedno pojęcie, jedno z dwóch byłoby nie do wyrażenia — i to jest najlepszy wynik tej bramy,
bo rozdzielenie zrobiono dzień wcześniej z zupełnie innego powodu.

**Drugi kontrakt natychmiast ujawnił ukryte założenie „jest tylko jeden".** `graph_test` liczył węzły grafu
statycznego globalnie i porównywał z liczbą zdarzeń jednego kontraktu. `PNS.Graph` nie ma zawężenia ani do
procesu, ani do kontraktu, a notatki §9 mówią wprost *„navigation is per-process, never global"*. To luka,
nie preferencja — należy do etapu 1.7.

## Rozstrzygnięte 4 sierpnia

| Pytanie | Decyzja |
|---|---|
| Powtórzony rozjazd w tym samym miesiącu | `identity: [:company_id, :period, :diff]` — ten sam rozjazd nie spamuje, inny daje nowe powiadomienie. Wersja bez `diff` połykała drugi, inny problem |
| Job w kolejce w nakładce | Trzeci stan `in_flight`, wdrożony teraz, bo po zbudowaniu ekranów byłby zmianą modelu danych |
| Krawędź „ta sama komenda" | Rysowana, ale kropkowaną linią bez grotu i z jawnym podpisem |
| Termin 25 dni | Zostaje z `unverified: [:deadline]`; `pns.check` zgłasza to za każdym przebiegiem i deklaracja nie liczy się do raportu dowodowego |

## Czego w pakiecie nie ma, a jest w rekordzie

`lib/pns` to 1263 linie, które dowodzą tego, po co powstały. Cztery luki, w kolejności wagi:

1. **Monitor zaległych procesów.** `deadline` i `cadence` są zadeklarowane w kontrakcie i **nieczytane przez
   nikogo**. To jest produkt: „faktura, która miała pójść, nie poszła, i nic nie zawiodło" wykrywa się
   dokładnie tym. *Ocena `trace` — zrobiona 5 sierpnia, `PNS.Trace`. Monitor terminów zostaje.*
2. **Typy payloadu nie są sprawdzane.** Kontrakt mówi `task_count: :integer` i nic tego nie pilnuje.
   Notatki §6 wymieniają payload conformance jako w pełni generowalny test.
3. **Awaria handlera synchronicznego nie zostawia śladu** — transakcja cofa wiersz obsługi razem ze
   zdarzeniem. Formalnie poprawne, diagnostycznie puste.
4. **Brak ochrony przed cyklem w runtime.** `pns.check` widzi krawędź wsteczną, ale nic nie zatrzyma
   rekurencji A→B→A.

Drobniejsze, realne: `version/0` liczy hash przez `term_to_binary`, więc aktualizacja OTP mogłaby zmienić
`contract_version` bez zmiany kontraktu; kolejność handlerów synchronicznych zależy od kolejności skanu
modułów; `PNS.Job` rozwiązuje handler po nazwie modułu, więc zmiana nazwy przy jobach w kolejce wysypuje je
trwale; `retain` działa tylko na płaskim payloadzie; brak telemetrii i cienkiego user-managementu.
