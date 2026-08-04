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
  graph.ex        statyczny, zaobserwowany, nałożenie
lib/taxvision/    aplikacja klienta
  contracts/      kontrakt na proces
  api.ex          krawędź żądania: trzy poziomy IAM
  registry_check.ex    czysta funkcja decyzyjna (polityka P1)
  authorization.ex     czysta funkcja: reguła domenowa
  tasks.ex, accounting_month.ex, notifications.ex    moduły z własnymi tabelami
  adapters/       behaviour + fake
```

## Rozstrzygnięte 4 sierpnia

| Pytanie | Decyzja |
|---|---|
| Powtórzony rozjazd w tym samym miesiącu | `identity: [:company_id, :period, :diff]` — ten sam rozjazd nie spamuje, inny daje nowe powiadomienie. Wersja bez `diff` połykała drugi, inny problem |
| Job w kolejce w nakładce | Trzeci stan `in_flight`, wdrożony teraz, bo po zbudowaniu ekranów byłby zmianą modelu danych |
| Krawędź „ta sama komenda" | Rysowana, ale kropkowaną linią bez grotu i z jawnym podpisem |
| Termin 25 dni | Zostaje z `unverified: [:deadline]`; `pns.check` zgłasza to za każdym przebiegiem i deklaracja nie liczy się do raportu dowodowego |

## Czego w pakiecie nie ma, a jest w rekordzie

`lib/pns` to 1263 linie, które dowodzą tego, po co powstały. Cztery luki, w kolejności wagi:

1. **Monitor zaległych procesów i ocena assercji `trace`.** Jedno i drugie jest zadeklarowane w kontrakcie i
   **nieczytane przez nikogo**. To jest produkt: „faktura, która miała pójść, nie poszła, i nic nie
   zawiodło" wykrywa się dokładnie tym. Prototyp dowiózł instalację, nie produkt.
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
