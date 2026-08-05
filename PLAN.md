# Plan pracy

Zakres produktu, uzasadnienie i lista zmian w rekordzie żyją w
`~/Projects/ai/empowered-house-context/output/20260804-pns-product-plan.md`. **Ten plik to lista roboty** i
tylko tu jest aktualizowany stan.

## Stan na 5 sierpnia

69 testów, `mix check` przechodzi. Ostrzeżenia są **dwa** i oba są celowe: `deadline` TaxVision bez
potwierdzenia process ownera oraz `deadline` z fikstury bramy uniwersalności, która jest wymyślona w całości.
Samo `mix pns.check` w środowisku dev pokazuje jedno — fikstura żyje w `test/support/`.

Działa: kontrakt jako moduł Elixira z bramami kompilacyjnymi, dispatch po granicy transakcji, log zdarzeń,
`boundary`, szew tożsamości, nakładka declared vs observed z czterema stanami, **tożsamość instancji procesu
i liczniki w dwóch wymiarach (wystąpienia i przebiegi)**, **drugi kontrakt z obcej domeny bez ani jednego
nowego słowa w DSL**.

**Nie działa, bo nie zostało zbudowane — i to jest produkt:**

| Luka | Waga |
| --- | --- |
| `trace` i `deadline` są zadeklarowane i **nie czyta ich nikt** | to jest produkt |
| Typy payloadu nie są sprawdzane; kontrakt mówi `:integer` i nic nie pilnuje | obietnica kontraktu |
| Awaria handlera synchronicznego nie zostawia śladu | diagnostyka |

## Etap 1 — rdzeń weryfikacji

**1.1 Instancja procesu. ✅ zrobione 5 sierpnia.** `instance: [...]` w DSL, brama kompilacyjna: każde
zdarzenie procesu musi nieść pola instancji. Powód jest techniczny, nie sprawozdawczy — bez tego
„eventually Y" dopasuje Y z innego przebiegu.
*Odbiór:* assercja policzona dla dwóch równoległych przebiegów nie myli ich zdarzeń. **Spełnione** —
`test/instance_test.exs`, przebieg c-1 otwiera miesiąc, c-2 nie, i licznik per typ zdarzenia zaliczyłby oba.

Wyszło przy okazji, w kolejności ważności:

- `instance:` jest **wymagane na każdym procesie**, nie opcjonalne. Obie rzeczy, które czynią z tego produkt
  — ocena `trace` i nakładka — liczą się w obrębie przebiegu, więc brama opcjonalna byłaby dokumentacją.
- **Zdarzenie w dwóch procesach nie kompiluje się.** To warunek stopu z ADR §15 zrobiony mechanicznie: dwa
  procesy to dwie tożsamości przebiegu, a w logu jest na to jedna kolumna.
- **`trace` rozciągnięty na dwa procesy nie kompiluje się** z tego samego powodu.
- Brama znalazła jedno zdarzenie: `turnover_matched_with_invoice` nie miało `period`, więc meczowanie z lipca
  liczyłoby się jako postęp w sierpniu. Dopisane.
- Liczniki mają **dwa wymiary**: wystąpienia i przebiegi, plus mianownik „ile przebiegów w ogóle było".
  Krawędź przejechana 49 razy przez jedną firmę i raz przez 49 firm miały wcześniej identyczny licznik.
  Świadomie **liczba, nie lista** — które przebiegi milczą, to pytanie o konkretną firmę.
- Zdarzenia zapisane przed tym etapem nie mają tożsamości przebiegu i już jej nie dostaną; raport pisze
  „bez tożsamości przebiegu", nie „0 przebiegów". To ten sam problem, który przy wersjach kontraktu
  rozwiązuje stan `:historical`.

**1.2 Brama uniwersalności. ✅ zrobione 5 sierpnia — PRZESZŁA.** Drugi kontrakt z innej domeny, wyłącznie
kontrakt plus fake'i, bez implementacji.

Domena medyczna jest naturalnym wyborem, bo Rehmed startuje 10.08 — ale **materiału warsztatowego z Rehmed
jeszcze nie ma**, więc ten kontrakt jest świadomie wymyślony i jest tak oznaczony w pliku. Testuje
**słownik DSL, nie wiedzę o domenie**.
*Odbiór:* **zero nowych słów w DSL.** **Spełnione** — `UniversalityGate.TreatmentEpisode`
(`test/support/`, nie drzewo klienta, nie trafia do repo kontekstu) opisuje epizod leczenia od skierowania
do zamknięcia bez ani jednego nowego słowa. Kryterium jest teraz **pinowane testem**, nie deklarowane:
`PNS.Contract.vocabulary/0` wystawia słownik maszynowo, a `test/universality_gate_test.exs` porównuje go z
literałem. Dopisanie `population:` wywala ten test tego samego dnia.

Co brama pokazała, w kolejności ważności:

- **`cadence` nie ma zastosowania do procesu zdarzeniowego.** Epizod leczenia nie jest należny nigdy —
  zaczyna się, kiedy wpłynie skierowanie. Słowa nie brakuje, bo `cadence` jest opcjonalna. Ale mechanizm,
  który na niej stoi — okno „never observed" — nie ma dla takiego procesu skąd wziąć długości i spada na
  fallback z zaobserwowanych odstępów. Notatki §9 traktują ten fallback jako przypadek brzegowy; dla
  procesów zdarzeniowych jest **stanem normalnym**. Do poprawki w rekordzie.
- **„Kontrakt plus fake'i, bez implementacji" nie jest osiągalne, jeśli kontrakt ma regułę.** Brama §18
  wymaga przykładu, przykład wskazuje MFA, a `pns.check` sprawdza, że funkcja istnieje. Albo kontrakt bramy
  nie deklaruje reguł i zostawia §18 nieprzetestowane na drugiej domenie, albo dochodzi jedna czysta funkcja
  decyzyjna. Wybrane drugie. Do poprawki w opisie zakresu 1.2 w rekordzie.
- **`owner:` może wskazywać moduł, którego nie ma, i nikt tego nie sprawdza.** Widoczne już wcześniej
  (`Taxvision.Matching`), potwierdzone na drugim kontrakcie. ✅ **zrobione 5 sierpnia** — `info` w
  `pns.check`, zgrupowane po module, nie po zdarzeniu.
- **`:period` jest jedynym typem w słowniku, który nie jest uniwersalny.** Brama tego nie złapała, bo
  sprawdza, czy trzeba **dopisać** słowo, a nie czy któreś jest zbędne. Dowód: kontrakt medyczny ma
  czternaście pól w payloadach i nie używa `:period` ani razu. To „miesiąc księgowy" przebrany za typ
  ogólny. Rozstrzygnięte — wypada, szczegóły przy 2.2.
- **`PNS.Graph` nie ma zawężenia do procesu ani kontraktu.** Drugi kontrakt ujawnił ukryte założenie „jest
  tylko jeden" — `graph_test` liczył węzły globalnie. Notatki §9 mówią wprost „navigation is per-process,
  never global", więc to jest luka, nie preferencja. Należy do 1.7/etapu 4, nie tutaj.
- **`identity` i `instance` razem uniosły kształt, którego TaxVision nie ma.** Dziesięć wizyt w jednym
  epizodzie to dziesięć faktów w jednym przebiegu — `identity: [:episode_id, :session_no]` przy
  `instance: [:episode_id]`. Gdyby to było jedno pojęcie, jedno z dwóch byłoby nie do wyrażenia.
- **`mix check` pokazuje teraz dwa ostrzeżenia, nie jedno.** Drugie pochodzi z wymyślonego `deadline` w
  fiksturze. Rejestr skanuje całą binarkę, a w środowisku testowym fikstura w niej jest — to ta sama
  własność, dzięki której „graf pochodzi z binarki, która działa". Samo `mix pns.check` (środowisko dev)
  fikstury nie widzi i pokazuje jedno ostrzeżenie. **Do rozstrzygnięcia:** czy raport dowodowy ma umieć
  wykluczyć przestrzeń nazw z konfiguracji silnika. Nie z DSL — to byłoby nowe słowo.

**1.3 Kształty procesu, zasymulowane.** Cel: instancja żyjąca tygodniami, zdarzenie tego samego typu wiele
razy w jednej instancji, krok który się cofa, zdarzenie wchodzące bez komendy, dwa moduły potrzebujące tych
samych danych.
*Odbiór:* instancja przechodzi cztery fazy; `pns.check` zgłasza krawędź wsteczną przy domykaniu pary i nie
zgłasza jej tam, gdzie jej nie ma. Koszt 2–3 dni.

**Przeskalowane 5 sierpnia: celem są kształty, nie fazy TaxVision.** Pierwsza wersja tego punktu mówiła
„fazy 3.2–3.4 dostają kontrakt, handlery i moduły" i to jest pomylenie pojazdu z celem — dodatkowo
najdroższego z dostępnych pojazdów. Kształty, które da się wymusić na kontrakcie syntetycznym, idą na
kontrakt syntetyczny, gdzie nie kosztują ani jednej decyzji domenowej. TaxVision wchodzi tam, gdzie inaczej
się nie da, i przy prawdziwym materiale, nie przy moich założeniach o KSeF.

**Tabela `periods` po stronie TaxVision — rozstrzygnięte 5 sierpnia, należy tutaj.** Okres przestaje być
stringiem `"2026-07"` i staje się wierszem: identyfikator, nazwa, zakres dat od–do. Zysk nie jest taki, jak
się na pierwszy rzut oka wydaje — „jeden period istnieje" daje też unikalny indeks na kolumnie tekstowej, a
sam wiersz nie gwarantuje, że dwa zdarzenia wskażą ten sam. Prawdziwy zysk to **kanonizacja**: przy kluczu
obcym `"2026-7"` obok `"2026-07"` przestaje być możliwe, a nie tylko niezalecane. Zamyka też dziurę, którą
miałby okres jako data — `2026-07-15` jest poprawną datą i cichym drugim przebiegiem tego samego miesiąca.

To jest **dobre miejsce na kształt „dwa moduły potrzebujące tych samych danych"** i lepsze niż przykład
wymyślony: `period` występuje w zdarzeniach należących do `RegistryCheck`, `Tasks`, `AccountingMonth`,
`Notifications` i docelowo `Matching`, więc każdy z nich musi ten okres rozwiązać. ADR §5–6 zabrania joinów
międzymodułowych, a `wiki/pns/modular-design.md` daje odpowiedź: strategiczna duplikacja z nazwanym źródłem
prawdy, nie wspólna tabela. Czyli budowanie tego nie jest objazdem, tylko realizacją punktu z listy.

**Kolejność wobec etapu 1: 1.5 i 1.4 idą przed 1.3** (ustalone 5 sierpnia). Powód: `trace`, `deadline` i
`cadence` są zadeklarowane i **nie czyta ich żaden mechanizm w runtime** — sprawdzone, nie z pamięci. To
jest produkt, a 1.1 i 1.2 były jego warunkiem wstępnym. 1.3 wymaga decyzji domenowych i materiału
klienckiego; 1.4 i 1.5 nie wymagają ani jednej linijki TaxVision, bo oba kontrakty już deklarują assercje.

**1.4 Behawioralna weryfikacja ścieżek, per instancja.**
*Odbiór:* przy 50 przebiegach, z których żaden nie wszedł w gałąź blokującą, raport pokazuje jedną
nieprzejechaną ścieżkę. Przy jednym przebiegu w tę gałąź — zero.

**Symulować wolumen, nie proces.** Plan produktowy chce falsyfikacji na 50 zasymulowanych przebiegach i ma
rację co do taniości, ale nie nazywa wady: proces, który sam zaprojektuję, wyprodukuje dokładnie ten sygnał,
który w niego wpiszę. Te 50 przebiegów idzie więc przez **istniejący kontrakt z warsztatu**, nie przez fazy,
które sam dopiszę. Kształt pochodzi wtedy z sesji z klientem, a losowe są tylko dane.

**1.5 Ocena assercji `trace`.** Per instancja, cztery werdykty: spełniona, naruszona, zawieszona (okno
niedostępności adaptera), w toku.
*Odbiór:* przy zablokowanym miesiącu assercja jest **spełniona przez `or_else`**, nie naruszona — blokada to
poprawne zakończenie, tylko nie takie, jak chcieliśmy.

**1.6 Wersja kontraktu jako pierwszoklasowa odpowiedź.** Która wersja wdrożona, od kiedy, jakie wersje w logu,
co się zmieniło.
*Odbiór:* po zmianie kontraktu raport mówi, które ścieżki są nowe, które zniknęły i które zdarzenia pochodzą z
poprzedniej wersji — **bez ani jednego fałszywego driftu.**

**1.7 Raport zgodności za okres.** Cztery pytania, jedna strona, etykiety biznesowe.
*Odbiór:* czytelny bez tłumaczenia, co znaczą kolumny, i nie zawiera `deadline` oznaczonego `unverified`.

## Etap 2 — obietnice kontraktu, które dziś są dekoracją

**2.1 Handler emituje tylko to, co zadeklarował.** Dziś `emitter` i `job` nie znają `publishes`, więc handler
może zadeklarować `[:x]`, wyemitować `:y` i przejść kompilację oraz `pns.check`, o ile `:y` jest w kontrakcie.
Check w `emit` przenosi wykrycie z produkcji do pierwszego testu, kilkanaście linii. Tracer kompilacji
(notatki §2) przesuwa je jeszcze wcześniej, ale jest optymalizacją momentu, nie warunkiem poprawności.

**2.2 Walidacja payloadu przeciw zadeklarowanym typom**, plus generowane testy zgodności.

**Wyrzucenie `:period` ze słownika typów należy tutaj** — rozstrzygnięte 5 sierpnia. `:id`, `:timestamp`,
`:enum`, `:string`, `:integer` mówią o kształcie danych; `:period` mówi o księgowości, czyli biblioteka
wie coś o domenie klienta. Okres staje się zwykłym `:id`, a czym jest — wie aplikacja klienta.

Kolejność jest tu istotna i wynika z kosztu: dziś klucz przebiegu brzmi `accounting_month|c-1|2026-07` i
człowiek czyta z niego wszystko. Po zmianie na identyfikatory brzmi `accounting_month|<uuid>|<uuid>`, a
**„odtwarzalny z samego logu" było jawną własnością projektową klucza przebiegu** — do odczytania dowodu
trzeba będzie drugiej bazy. Zrobione przed 2.2 oznacza zapłacenie tej ceny bez niczego w zamian, bo typy
nadal niczego nie pilnują. Zrobione razem z 2.2 — `:id` faktycznie znaczy „identyfikator" na poziomie
castowania, nie tylko w dokumentacji.

Przy okazji do domknięcia: `:integer` jest używane w obu kontraktach i nie ma go w udokumentowanym
słowniku, a notatki §1 pokazują w przykładzie `:uuid` i `:decimal`, których nie ma nigdzie. Słownik ma
jedno źródło prawdy — `PNS.Contract.vocabulary/0` — i reszta ma się z nim zgadzać.

**2.3 Ślad po awarii handlera synchronicznego.** Transakcja cofa wiersz obsługi razem ze zdarzeniem, więc
najciekawsza awaria jest niewidoczna. Zapis poza transakcją albo telemetria.

**2.4 Cztery rzeczy odpornościowe.** Ochrona przed cyklem w runtime; zdefiniowana albo zabroniona kolejność
dwóch handlerów synchronicznych na jednym zdarzeniu; **kanoniczny hash `version/0`** (dziś aktualizacja OTP
może przekwalifikować całą historię na `historical`); łagodne odrzucenie joba po znikniętym handlerze.

**2.5 Telemetria.** `:telemetry` emitowana tutaj; zbieranie, wykresy i alerty należą do GCP i Datadoga.

## Etap 3 — pakiet jako pakiet

Wydzielenie do `packages/pns_core` z path dep, żeby granicę wymuszał system budowania, nie tylko `boundary`.
Migracje w stylu Obana. Trzy skille: dodaj zdarzenie, napisz handler, zmień kontrakt — ten trzeci jest
najważniejszy, bo jako jedyny wymaga zrobienia czegoś **przed** napisaniem kodu. CI z `mix check`.

**Czwarty skill, pierwszy dla człowieka:** jak recenzować wygenerowany PR i **czego nie sprawdzać**, bo już
pilnuje to check. Notatki §8 wymieniają osiem skilli i wszystkie są dla agenta, który pisze — a bramą jest
recenzent.

## Etap 4 — jeden ekran

Cztery pytania jako lista, nie graf. Sprawdzone: 11 zdarzeń dało 3 krawędzie i diagram nie powiedział nic,
czego nie mówiła posortowana lista. Bez alertów, bez stanu na żywo, bez czegokolwiek o konkretnej firmie.

**Zablokowane do rozstrzygnięcia:** notatki §9 mówią *„live, not a report … monitors eventually want alerts"*,
co jest w napięciu z zawężeniem zakresu. Etapy 1–3 są od tego niezależne.

## Rekord: co czeka na przegląd

Gałąź **`docs/pns-record-corrections-etap-1`** w repo kontekstu, jeden commit, **niewypchnięta**. Zawiera
cztery poprawki z etapów 1.1–1.2 plus nowy kształt `event`/`process` i sprostowanie do triggera ADR §15
(„jedno zdarzenie w dwóch procesach" nie jest błędem kompilacji, a rzeczą niewyrażalną). Dług spłacony.

**Uwaga przy odgałęzianiu od tego repozytorium:** decyzji 008 ani notatek technologicznych **nie ma na
`main`** — żyją wyłącznie na `docs/pns-architecture-adr`, która bywa przepisywana. Gałąź odbita od niej
osierocieje po każdym rebase i wymaga `rebase --onto`. Zdarzyło się to raz, 5 sierpnia.

## Kolejność

1.1 i 1.2 zamknięte — brama uniwersalności przeszła, więc etapy 1.3+ nie stoją już na niesprawdzonym
założeniu. **Dalej: 1.5, potem 1.4, potem 1.3**, z powodów zapisanych przy 1.3.

Kod zostaje w tym repo i przenosi się do repozytorium pilota, gdy ono powstanie; struktura jest już taka, że
to `git mv`.
