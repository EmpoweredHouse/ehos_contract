# PNS — silnik weryfikacji zgodności

Odpowiada na jedno pytanie:

> **Czy wdrożony kod robi to, co mówi ustalony proces?**

Nie „czy ten moduł działa" — to mówią testy. Nie „czy serwer stoi" — to mówi monitoring. Trzecie pytanie jest
tym, którego dziś nie odpowiada nic: **faktura, która miała pójść, nie poszła, i nic nie zawiodło**, bo kod
się nie wykonał. Żaden alert nie zadzwoni, każdy dashboard jest zielony.

Mechanizm: proces jest zadeklarowany jako **kontrakt** — kod w repozytorium klienta, zatwierdzany przez
process ownera. Z kontraktu wynika struktura, testy i graf zdarzeń. Log zdarzeń mówi, co faktycznie zaszło.
**Różnica między jednym i drugim jest produktem.**

Ekran ma **cztery pytania i ani jednego więcej**: które ustalone ścieżki nigdy nie zostały przejechane, co
zaszło poza ustaleniami, które assercje `trace` są naruszane, która wersja ustaleń jest wdrożona i od kiedy.

## Co jest czym w tym repozytorium

`lib/pns/` to **silnik** i przyszły pakiet na hex. `lib/taxvision/` to **jedna aplikacja klienta, która jest
tu tymczasowo** — przypadek testowy, na którym sprawdzamy, czy założenia silnika się trzymają. Granicy
pilnuje `boundary` od pierwszego commita, więc ta tymczasowość jest faktem, nie obietnicą: przeniesienie
drzewa klienta obok jego repozytorium to `git mv`.

Z tego wynikają trzy rzeczy, o które łatwo się potknąć:

**To nie jest template.** Nie ma `mix pns.new`, nie ma generycznego wyciągu, drzewo klienta nazywa się
`taxvision`, a nie `my_app`. Zabezpieczenie jest mechaniczne, bo deklaratywne nie działa — spike bez tego
zamienia się w template, którego nie chcemy budować przed drugim klientem.

**Silnik mówi po angielsku, wliczając raport.** Do 6 sierpnia było odwrotnie — silnik produkował dane, zdania
produkowała aplikacja klienta (`Taxvision.Report`), bo raport czyta księgowa. Renderer przeniósł się do
silnika (`PNS.Report`, `mix pns.report`) i wypisuje po angielsku; etykiety z kontraktu (`label`,
`from_label`, `to_label`) nadal wychodzą dosłownie, w języku, w którym je zadeklarował klient — silnik nie
tłumaczy cudzych słów, tłumaczy tylko własne.

**Silnik nie wie nic o firmach.** Nie ma `company_id` w żadnej strukturze `PNS`. Najemcę czyta kod domenowy z
`actor.claims`, bo przychodnia ma placówki, a spedycja terminale. Pytanie „która firma nie zamknęła lipca"
należy do aplikacji klienta — gdy PNS zacznie na nie odpowiadać, staje się drugim, gorszym ekranem tej
aplikacji.

## Uruchomienie

```bash
docker compose up -d && mix deps.get && mix ecto.setup && mix check
```

`mix check` to `compile --force --warnings-as-errors`, `pns.check`, `pns.docs --check` i `test`.
**Musi przechodzić.** Postgres słucha na **5433**, nie 5432 — lokalny bywa zajęty, a to ma stać na czystej
maszynie bez pytania, co jeszcze nasłuchuje.

`--warnings-as-errors` jest konieczne, nie estetyczne: `boundary` raportuje naruszenia jako **ostrzeżenia**,
więc bez tego przełącznika granice są dokumentacją. Sprawdzone celowym naruszeniem.

```bash
mix pns.check                # sprawdzenia całoprogramowe: krawędzie wsteczne, konkurujące handlery, sieroty, niepotwierdzone deklaracje
mix pns.graph                # graf statyczny z rejestru
mix pns.graph --overlay      # nałożony na log zdarzeń
mix pns.graph --mermaid      # diagram
mix pns.trace                # ocena assercji `trace` z logu — liczby, nie lista przebiegów
mix pns.trace --instances    # pojedyncze przebiegi; widok do debugowania, nie dla klienta
mix pns.docs                 # regeneracja referencji kluczy w docs/contract.md
mix pns.report                # raport zgodności za okres — cztery pytania, jedna strona
mix pns.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
```

## Gdzie co jest

| Czego szukasz | Gdzie |
| --- | --- |
| **Jak napisać kontrakt** — klucze, wymagane/opcjonalne, co się nie skompiluje | [`docs/contract.md`](docs/contract.md) |
| Co jest zrobione, co dalej, co wyszło z pisania kodu | [`PLAN.md`](PLAN.md) — **jedyne miejsce, gdzie aktualizuje się stan** |
| Dlaczego silnik działa tak, a nie inaczej — 18 decyzji, `§N` z komentarzy | [`docs/adr/architecture.md`](docs/adr/architecture.md) |
| Kształty kodu, schematy, pułapki — `notes §N` z komentarzy | [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) |
| Konwencje, których łatwo złamać | [`CLAUDE.md`](CLAUDE.md) |
| **Pytania na warsztat** — czego zabrakło przy TaxVision, żeby kontrakt się skompilował | [`docs/warsztat-rehmed.md`](docs/warsztat-rehmed.md) |
| **Jakie skille istnieją, w jakiej kolejności, i jak to się ma do `process-native-software`** | [`docs/warsztat-narzedzia.md`](docs/warsztat-narzedzia.md) |

Dokumentacja kontraktu jest generowana z `PNS.Contract.schema/0`, jej przykład jest kompilowany testem, a
tabela „co się nie skompiluje" ma pokrycie w testach bram. Trzy mechanizmy, bo ręcznie pisany opis DSL-a
jest **drugim źródłem prawdy** — czyli dokładnie tą awarią, którą ten produkt wykrywa u innych.

## Struktura

```
lib/pns/                 silnik — 3718 linii, przyszły pakiet
  contract.ex            DSL, @before_compile, bramy kompilacyjne, version/0
  handler.ex             sprawdzenia w ciele makra; publishes: wiąże też w runtime
  registry.ex            skan binarki przy boocie — graf pochodzi z kodu, który działa
  emitter.ex             emit/4: log, handlery synchroniczne, joby — jedna granica transakcji
  event.ex               log zdarzeń i log obsług
  job.ex                 worker Obana, korelacja przez granicę procesu
  instance.ex            tożsamość przebiegu z `instance:`, liczona przy emisji
  trace.ex               ocena assercji per przebieg — cztery werdykty
  dependency.ex          obserwacje niedostępności zależności; czytelnik `unavailable_looks_like`
  conformance.ex         cztery pytania ekranu jako dane
  deployment.ex          dwie tożsamości wdrożenia: kontrakt i obwodowanie
  digest.ex              kanoniczna postać deklaracji, wspólna dla obu haszy
  handler_failure.ex     ślad po awarii handlera synchronicznego, poza cofniętą transakcją
  graph.ex               statyczny, zaobserwowany, nałożenie
  auth.ex                szew tożsamości: behaviour + lokalny HMAC
  telemetry.ex           katalog zdarzeń: handler i naruszenie kontraktu, nic więcej
  check.ex, duration.ex  logika checków i jednostki czasu — jedno źródło prawdy

lib/taxvision/           aplikacja klienta — tymczasowo, jako przypadek testowy
  contracts/             kontrakt na jeden proces z warsztatu
  api.ex                 krawędź żądania: trzy poziomy IAM
  registry_check.ex      czysta funkcja decyzyjna (polityka P1)
  periods.ex             okresy jako kanoniczne wiersze; nazwy na krawędziach, identyfikatory w środku
  report.ex              raport po polsku — bo to klient go czyta
  adapters/              behaviour + fake

test/support/
  universality_gate/     drugi kontrakt, WYMYŚLONY — brama uniwersalności, nie klient
  process_shapes/        stanowisko badawcze kształtów i mechanizmów — NIE domena
```

## Co wyszło z warsztatu, a co trzeba było wymyślić

Najbardziej użyteczny wynik dotąd i bezpośredni test założenia §1, że **wynik warsztatu jest
discovery-grade, nie generation-grade.** Z warsztatu przyszły nazwy zdarzeń, polityka, aktorzy i
niezmienniki. Wszystko poniżej trzeba było wymyślić, żeby to się skompilowało:

| Czego brakowało | Kto powinien to rozstrzygnąć |
| --- | --- |
| **Kształty payloadów** — warsztat daje nazwy zdarzeń i polskie opisy, zero pól | Warsztat, jedna sesja na proces |
| **Słownik typów** — nośny: `:string` dla wszystkiego zrobiło z checka retencji szum na 33 pozycje | My — to decyzja narzędziowa |
| **Ścieżki błędów** — „blokada i powiadomienie" jest w polityce; co przy niedostępnym rejestrze, nie ma nigdzie | Warsztat — to pytanie prawne, nie techniczne |
| **Klucze idempotencji** — brak w całym warsztacie | My, ale wymaga potwierdzenia |
| **Stany terminalne** — stepper nie mówi, co kończy proces | Process owner |
| **Termin 25 dni** — wzięty z przykładu w notatkach, **nie z warsztatu** | Warsztat. Jedyna liczba w kontrakcie bez źródła |

**Z warsztatu wyszło jakieś 40% kontraktu, i to ta łatwiejsza część.** Nazwy i przepływ są darmowe; typy,
ścieżki błędów, niezmienniki i idempotencja to druga sesja z klientem, nie praca programisty. Termin 25 dni
stoi w kontrakcie z `unverified: [:deadline]` i **nie liczy się do raportu dowodowego**, dopóki go nikt nie
potwierdzi — bo liczba, której klient nie uzgodnił, wypisana obok liczb uzgodnionych, czyta się jako
zmierzona.

## Dwa diagramy, dla dwóch różnych czytelników

Oba wychodzą z `mix pns.graph` i **nie pokazują tego samego**. Mylenie ich kosztowało już raz odrzucenie
pomysłu, który nie był tym odrzucanym — patrz `PNS.Graph.declared_to_mermaid/2`.

| Co | Dla kogo | Skąd bierze treść |
| --- | --- | --- |
| `--overlay --mermaid` | zespół | krawędzie z rejestru handlerów + liczniki z logu |
| `--process <nazwa> --mermaid` | **właściciel procesu, przed budową** | `stages`, `terminal`, `trace` i `depends_on` z kontraktu |

Drugi jest jedynym, który ma sens dla kontraktu **bez implementacji**: bez handlerów krawędzi jest zero,
więc nakładka takiego kontraktu to same nierozłączone pudełka.

### Diagram nakładki

```bash
mix pns.graph --overlay --mermaid --output doc/graf-nakladki.mmd
mmdc -i doc/graf-nakladki.mmd -o doc/graf-nakladki.png -b white -s 3
```

Diagram w repo jest z **danych demonstracyjnych**, nie z prawdziwego przebiegu: pięć firm w jednym miesiącu,
trzy przechodzą weryfikację, dwie idą w blokadę, kolejka zatrzymana. Bez zatrzymanej kolejki czwarty stan
nakładki nie miałby czego pokazać.

### Diagram kształtu zadeklarowanego

```bash
mix pns.graph --mermaid --process clinical_visit --output wizyta.mmd
mmdc -i wizyta.mmd -o wizyta.pdf
```

**PDF, nie PNG**, jeśli to idzie na sesję z klientem: rozmiar wychodzi z liczby zdarzeń, a nie z `-s`,
i skalowanie nie rozmywa polskich znaków. `mmdc` rozpoznaje format po rozszerzeniu — `-o out.png`,
`-o out.pdf` i `-o out.svg` to ta sama komenda.

Etapy z więcej niż jednym zdarzeniem noszą w tytule `no order claimed inside`, bo wewnątrz etapu kontrakt
nie twierdzi nic o kolejności — i pudełka bez strzałek muszą się czytać jako decyzja, nie jako brak.
**Szeroki, luźny obrazek jest wtedy prawdziwym wynikiem**, a nie usterką układu: to kontrakt, który
deklaruje mało. Dociąganie go niewidzialnymi krawędziami sugerowałoby kolejność, której nikt nie uzgodnił.

Jeśli `mmdc` zgłosi brak `chrome-headless-shell` w konkretnej wersji, a w `~/.cache/puppeteer/` leży inna —
wskaż mu ją, zamiast pobierać drugą przeglądarkę:

```bash
mmdc -i in.mmd -o out.png -p <(echo '{"executablePath":"'"$HOME"'/.cache/puppeteer/chrome-headless-shell/<wersja>/chrome-headless-shell-mac-arm64/chrome-headless-shell"}')
```

Wypis przez potok psuje polskie znaki: Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, i
przycina każdy kodepoint do bajtu — `ł` staje się `B`. Dlatego `--output` pisze plik przez `File.write!`, a
nie przekierowaniem.

## Czego tu celowo nie ma

| | Dlaczego |
| --- | --- |
| Ekran, dashboard | Najpierw trzeba było sprawdzić, czy różnica jest sygnałem. Jest — 50 przebiegów daje jedną linię raportu |
| Graf w interfejsie | Sprawdzone: 11 zdarzeń dało 3 krawędzie i diagram nie powiedział nic, czego nie mówiła posortowana lista |
| Warstwa web, API | REST przeciw GraphQL jest otwarte; budowanie API przesądzałoby otwartą decyzję |
| `mix pns.new` | Dopiero przy drugim kliencie — generator buduje się, kiedy coś zostało skopiowane dwa razy |
| Prawdziwe rejestry, prawdziwy mail, provider OIDC | Behaviour plus fake. Szew działa, podmiana to jedna linia konfiguracji |
| Alerty, widoki operacyjne, zbieranie metryk | Wydajność to GCP, błędy to Datadog, **stan biznesu to aplikacja klienta**. `PNS.Telemetry` to szew, do którego się podłączają — emituje wyłącznie to, czego nie widzi nikt inny: handlera i naruszenie kontraktu |

Pełna lista z uzasadnieniami jest w [`CLAUDE.md`](CLAUDE.md); stan i luki — w [`PLAN.md`](PLAN.md).
