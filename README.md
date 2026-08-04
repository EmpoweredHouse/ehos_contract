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
| **Kolejność liniowa.** Warsztat daje DAG i mówi wprost „fazy nie są w pełni sekwencyjne"; kontrakt chce listy | Zlinearyzowane ręcznie. **Od tego zależy wykrywanie krawędzi wstecznych**, więc to nie jest kosmetyka | Otwarte — patrz niżej |
| **Deadline 25 dni** | Wzięty z przykładu w notatkach, **nie z warsztatu** | Warsztat. Jedyna liczba w tym kontrakcie bez źródła |
| **Reguła autoryzacyjna** | Wywnioskowana z HS28 i z tego, że aktorem fazy 3.1 jest Księgowa | Warsztat |
| **Komendy** | `RetriggerVerification` z warsztatu pominięta | Do dołożenia przy pętli ponowienia |

Wniosek jest zgodny z ADR §1 i mocniejszy, niż się spodziewałem: **z warsztatu wyszło jakieś 40% kontraktu,
i to ta łatwiejsza część.** Nazwy i przepływ są darmowe. Typy, ścieżki błędów, niezmienniki i idempotencja to
druga sesja z klientem, nie praca programisty.

Jedna rzecz do rozstrzygnięcia w modelu: **kontrakt wymaga liniowej listy zdarzeń procesu, a warsztat
opisuje graf z równoległością.** Dziś kolejność jest w `process events:` i służy wykrywaniu krawędzi
wstecznych. Jeśli fazy naprawdę biegną równolegle — a warsztat mówi, że tak: KSeF ciągnie ciągle, meczowanie
doszywa na bieżąco — to liniowa lista jest kłamstwem, a check krawędzi wstecznych stoi na kłamstwie.

## Dashboard — co wyszło, zanim cokolwiek narysowaliśmy

Nakładka jest policzalna dwoma zapytaniami: węzły z `pns_events`, krawędzie z self-joina po `causation_id`.
Nic więcej nie trzeba zapisywać, żeby odtworzyć faktyczny przebieg.

**Job w locie wygląda dokładnie jak martwa ścieżka.** Po trzech przebiegach nakładka pokazała
`registry_discrepancy_detected -> discrepancy_notification_sent` jako `dead (0x)` — choć trzeci przebieg
wszedł w tę gałąź. Job czekał w kolejce. Po `Oban.drain_queue` krawędź przeszła w `confirmed (1x)`.
**To jest pierwszy realny wymóg dashboardu: bez stanu kolejki w nakładce dashboard kłamie przy każdym
opóźnieniu.** Trzeci stan, nie dwa — *zadeklarowane i nieobserwowane* to nie to samo co *w drodze*.

**`contract_version` robi to, po co jest.** Test wstawia zdarzenie pod wersją kontraktu, której już nie ma w
binarce, i nakładka klasyfikuje je jako `:historical`, nie `:drift`. Bez tej kolumny każdy deploy usuwający
zdarzenie produkuje fałszywe alarmy.

**Graf jest dekoracją, lista nie.** 11 zdarzeń daje 3 krawędzie i diagram nie powiedział nic, czego nie
mówiła posortowana lista. Notatki §9 mają rację, że domyślnym widokiem jest lista rozbieżności. Diagram
zaczyna zarabiać przy kilkudziesięciu krawędziach, czyli nie w pilocie.

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

## Do decyzji

1. **Liniowa lista zdarzeń procesu przeciw grafowi z równoległością.** Pytanie do modelu, nie do kodu.
2. **Job w locie jako trzeci stan nakładki.** Wpływa na schemat dashboardu, więc lepiej teraz.
3. **§18 w rekordzie twierdzi mocniej, niż dowozi.** Jedna linia do poprawienia.
4. **Idempotencja powiadomień:** dwa rozjazdy w jednym miesiącu to jedno powiadomienie czy dwa?
5. **Deadline 25 dni** nie ma źródła w warsztacie.
