# Plan pracy

Zakres produktu, uzasadnienie i lista zmian w rekordzie żyją w
`~/Projects/ai/empowered-house-context/output/20260804-pns-product-plan.md`. **Ten plik to lista roboty** i
tylko tu jest aktualizowany stan.

## Stan na 4 sierpnia

42 testy, `mix check` przechodzi, jedno celowe ostrzeżenie (`deadline` bez potwierdzenia process ownera).
Działa: kontrakt jako moduł Elixira z bramami kompilacyjnymi, dispatch po granicy transakcji, log zdarzeń,
`boundary`, szew tożsamości, nakładka declared vs observed z czterema stanami.

**Nie działa, bo nie zostało zbudowane — i to jest produkt:**

| Luka | Waga |
| --- | --- |
| `trace` i `deadline` są zadeklarowane i **nie czyta ich nikt** | to jest produkt |
| Nie istnieje pojęcie **instancji procesu** — nakładka liczy per typ zdarzenia | blokuje produkt |
| Typy payloadu nie są sprawdzane; kontrakt mówi `:integer` i nic nie pilnuje | obietnica kontraktu |
| Awaria handlera synchronicznego nie zostawia śladu | diagnostyka |

## Etap 1 — rdzeń weryfikacji

**1.1 Instancja procesu.** `instance: [...]` w DSL, brama kompilacyjna: każde zdarzenie procesu musi nieść
pola instancji. Powód jest techniczny, nie sprawozdawczy — bez tego „eventually Y" dopasuje Y z innego
przebiegu.
*Odbiór:* assercja policzona dla dwóch równoległych przebiegów nie myli ich zdarzeń.

**1.2 Brama uniwersalności.** Drugi kontrakt z innej domeny (medyczna — Rehmed startuje 10.08), wyłącznie
kontrakt plus fake'i, bez implementacji.
*Odbiór:* **zero nowych słów w DSL.** Jeśli trzeba dopisać choćby jedno słowo specyficzne dla domeny, DSL jest
źle zaprojektowany i etapy 1.3+ są do przepisania. Dlatego to jest tutaj, a nie na końcu — dziś nie mamy
żadnego dowodu na uniwersalność: jeden kontrakt, jedna domena, jeden autor.

**1.3 Kształty procesu, zasymulowane.** Fazy 3.2–3.4 dostają kontrakt, handlery i moduły, **bez** parsera
MT940, bez KSeF, bez produkcyjnego parowania. Wyciąg to lista obrotów podana wprost, parowanie to zgodność
kwoty i daty. Cel: instancja żyjąca tygodniami, zdarzenie tego samego typu wiele razy w jednej instancji, krok
który się cofa, zdarzenie wchodzące bez komendy, dwa moduły potrzebujące tych samych danych.
*Odbiór:* instancja przechodzi cztery fazy; `pns.check` zgłasza krawędź wsteczną przy domykaniu pary i nie
zgłasza jej tam, gdzie jej nie ma. Koszt 2–3 dni.

**1.4 Behawioralna weryfikacja ścieżek, per instancja.**
*Odbiór:* przy 50 przebiegach, z których żaden nie wszedł w gałąź blokującą, raport pokazuje jedną
nieprzejechaną ścieżkę. Przy jednym przebiegu w tę gałąź — zero.

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

## Zaczynając

Od 1.1, potem natychmiast 1.2 — dopóki brama uniwersalności nie przejdzie, każdy kolejny etap jest budowany na
niesprawdzonym założeniu. Kod zostaje w tym repo i przenosi się do repozytorium pilota, gdy ono powstanie;
struktura jest już taka, że to `git mv`.
