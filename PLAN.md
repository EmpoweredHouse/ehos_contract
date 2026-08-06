# Plan pracy

Zakres produktu, warunki oceny i stan recenzji żyją w rekordzie:
`~/Projects/ai/empowered-house-context/decisions/008-pns-runtime-architecture.md`. **Ten plik to lista roboty** i tylko tu jest
aktualizowany stan.

## Stan na 6 sierpnia

162 testy, `mix check` przechodzi. Ostrzeżenia są **trzy** i wszystkie celowe: `deadline` TaxVision bez
potwierdzenia process ownera, `deadline` z wymyślonej fikstury bramy uniwersalności, oraz **krawędź wsteczna
w stanowisku badawczym kształtów — która jest kryterium odbioru 1.3, więc jej brak byłby regresem.**
Samo `mix pns.check` w środowisku dev pokazuje jedno — fikstury żyją w `test/support/`.

Działa: kontrakt jako moduł Elixira z bramami kompilacyjnymi, dispatch po granicy transakcji, log zdarzeń,
`boundary`, szew tożsamości, nakładka declared vs observed z czterema stanami, **tożsamość instancji procesu
i liczniki w dwóch wymiarach (wystąpienia i przebiegi)**, **drugi kontrakt z obcej domeny bez ani jednego
nowego słowa w DSL**, **ocena assercji `trace` per przebieg — trzy werdykty z czterech**, **raport
nieprzejechanych ścieżek per przebieg**, **`publishes:` wiąże handler w runtime, nie tylko opisuje**,
**obie tożsamości wdrożenia haszują się kanonicznie, z jednego źródła**, **awaria handlera synchronicznego
zostawia ślad, a raport odróżnia „próbowane i nie udaje się" od „nigdy nie próbowano"**.

**Nie działa, bo nie zostało zbudowane — i to jest produkt:**

| Luka | Waga |
| --- | --- |
| `deadline` procesu jest zadeklarowany i **nie czyta go nikt** — jedyni czytelnicy to filtr, który go wyrzuca, i renderer, który by go wypisał; `deadline_at` w `PNS.Trace` pochodzi z `within`, czyli z innej deklaracji | to jest produkt |
| `cadence` jest **przenoszona**, ale nikt nie liczy z niej okna — mechanizm „never observed" z notatek §9 nadal nie istnieje | to jest produkt |
| Typy payloadu nie są sprawdzane; kontrakt mówi `:integer` i nic nie pilnuje | obietnica kontraktu |

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
**Poprawka do samej bramy, 5 sierpnia:** kryterium „zero nowych słów" dowodzi, że DSL **opisze** inną
domenę — nie że silnik na niej **zadziała**. `PNS.Trace` i `PNS.Conformance`, zbudowane po przejściu bramy,
dostawały z kontraktu medycznego puste listy, więc ich uniwersalność była nieprzetestowana. **Brama obejmuje
od teraz mechanizmy, nie tylko słownik** — inaczej ten sam dryf wróci przy 1.6 i 1.7.

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

### Dokumentacja kontraktu — zrobione 5 sierpnia

`docs/contract.md`, po angielsku, bo to dokumentacja pakietu. Trzy mechanizmy anty-driftowe, bo bez nich
ręcznie pisany opis DSL-a jest **drugim źródłem prawdy** — a dziś znaleźliśmy cztery takie rozjazdy między
rekordem a kodem, w tym przykład DSL w notatkach §1 z typami, których w słowniku nie ma:

1. **Referencja kluczy jest generowana** z `PNS.Contract.schema/0` przez `mix pns.docs`. `--check` w
   `mix check` wywala build, gdy blok jest nieaktualny. Sprawdzone: podmiana jednej wartości domyślnej w
   dokumencie zatrzymuje bramę.
2. **Przykład jest fikstórą, nie ilustracją** — test kompiluje każdy blok kodu z kontraktem z tego pliku.
   Ta sama zasada, którą kontrakt stosuje do reguł, zastosowana do własnej dokumentacji.
3. **Każdy klucz DSL-a musi być w dokumencie wymieniony**, a tabela „co się nie skompiluje" nie może
   obiecywać więcej bram, niż jest testów bram.

Przy okazji `schema/0` zastąpiła sześć osobnych list kluczy jednym źródłem, z którego wyprowadza się
`vocabulary/0` **i** walidacja nieznanych kluczy. Wcześniej były to dwie rzeczy do rozjechania się.

I wyszła z tego jedna brama: **`trace` bez `from` albo bez `eventually` się nie kompiluje.** Wcześniej
kompilował się i produkował bezsens — nic nie mogło go spełnić, więc każdy przebieg wychodził jako
naruszony po upływie okna. Schema wymusiła nazwanie, co jest wymagane, i wtedy stało się widać, że
wymaganie nie było egzekwowane.

## Język kodu — ✅ spłacone 5 sierpnia

**Cały kod jest po angielsku.** 54 pliki, jeden commit, bo inaczej się nie dało: bramy kompilacyjne są
przypięte testami asertującymi na fragmenty własnych komunikatów, więc zmiana komunikatu bez testu wywala
bramę, a zmiana testu bez komunikatu nie pinuje niczego.

Granicę wyznacza **kto czyta string**, nie katalog:

- Po angielsku wszystko, co czyta programista albo kompilator — `lib/pns/`, drzewo klienta, zadania mixa,
  fikstury i testy. Fikstury, bo jadą z pakietem; testy, bo biblioteka z komunikatami bram w jednym języku
  jest biblioteką dla jednego kraju.
- Po polsku zostają cztery rzeczy, wszystkie **treść, nie kod**: `label`, `source`, opisy `example` i
  `unavailable_looks_like` w kontrakcie; raport dla księgowej; nazwy tasków i temat powiadomienia.
  Dokumentacja repo też zostaje — nie jedzie z pakietem.

Dwie rzeczy wyszły przy okazji i są warte więcej niż samo sprzątanie:

- **Polska odmiana liczebnika w grafie zniknęła w całości.** Istniała, żeby nie wypisać „2 przebiegów" na
  diagramie — trzy klauzule arytmetyki na `rem(n, 100)`. Przy angielskim wyjściu silnika zwija się do
  `1 run` / `n runs`. Cała kategoria problemu „gramatyka w bibliotece" nie została rozwiązana, tylko
  **usunięta**, i to jest lepszy argument za regułą niż sama reguła.
- **Fikstura bramy uniwersalności jest teraz po angielsku, a kontrakt TaxVision obok niej po polsku** — i to
  nie jest niespójność. Reguła koduje pytanie „czy człowiek czyta ten string jako zdanie w swoim języku".
  Wymyślony epizod leczenia nie ma process ownera ani klienta. Kontrakt TaxVision ma obu.

**`@doc` i `@spec` na wszystkich publicznych funkcjach `lib/pns/`** — zrobione w tym samym commicie, razem z
`@type` dla kształtów opisanych wcześniej tylko prozą (`PNS.Trace.verdict`, `PNS.Registry.handler`,
`PNS.Duration.t`, `PNS.Contract.declaration`).

## Dryf sprawdzony przed 1.3, 5 sierpnia

Pytanie brzmiało: czy kontrakt nie dryfuje w stronę kontraktu pod TaxVision. **Słownik nie dryfuje.
Dryfowały mechanizmy i krawędzie silnika** — trzy znaleziska, wszystkie naprawione:

- **`PNS.Auth.Actor` miał `company_id`** jako pole struktury, czyli silnik wiedział, że aktorzy należą do
  **firm**. Przychodnia ma placówki, spedycja terminale. Umknęło, bo brama to kontrakt plus fake'i, a szew
  tożsamości nie jest częścią kontraktu. Teraz `claims: %{}` i najemcę czyta kod domenowy.
- **`within: {1, :month}` kompilowało się i wywalało w runtime.** DSL przyjmował jednostkę, której ocena nie
  umiała policzyć. Niewidoczne, bo **oba** kontrakty liczą w dniach — pisząc fikstórę medyczną
  bezrefleksyjnie skopiowałem nawyk TaxVision, choć dla epizodu leczenia `{3, :month}` jest naturalniejsze
  niż `{90, :day}`. Jednostki mają teraz jedno źródło prawdy (`PNS.Duration`) dla bramy i dla arytmetyki.
- **Raport ścieżek pomijał proces bez handlerów w całości**, czyli cały kontrakt bramy uniwersalności był
  nieobecny — a nieobecność czyta się jako „nie ma o czym mówić". Teraz `basis: :no_paths`.

Znalezione tutaj i **naprawione tego samego dnia**: runtime pakietu mówił po polsku (`to_text`, etykiety
mermaida, komunikaty błędów kompilacji). To inna oś uniwersalności niż DSL-owa — bez znaczenia dla tego
pilota, blokująca dla paczki na hex. Patrz „Język kodu" niżej; do etapu 3 zostaje samo wydzielenie
`packages/pns_core`.

**1.3 Kształty procesu, zasymulowane.** Cel: instancja żyjąca tygodniami, zdarzenie tego samego typu wiele
razy w jednej instancji, krok który się cofa, zdarzenie wchodzące bez komendy, dwa moduły potrzebujące tych
samych danych.
*Odbiór:* `pns.check` zgłasza krawędź wsteczną przy domykaniu pary i nie zgłasza jej tam, gdzie jej nie ma.

**1.3a ✅ zrobione 5 sierpnia — trzy kształty z pięciu.** `ProcessShapes.Rig` w `test/support/`, jawnie
**nie domena**: nazwy bezbarwne (`item`, `case`, `pairing`), bo gdyby brzmiały jak księgowość albo medycyna,
ktoś przeczytałby je jako wiedzę o czyimś procesie.

Osobna fikstura, a nie handlery dopięte do kontraktu bramy uniwersalności — ten drugi jest artefaktem 1.2 i
jego wartość polega na tym, że jest kontraktem **bez** implementacji; jest też jedyną fikstórą, na której da
się sprawdzić raport dla procesu bez ani jednej ścieżki. Dopięcie handlerów zabrałoby oba pokrycia.

*Odbiór spełniony, i ważniejsza jest druga połowa:* check zgłasza **jedną** krawędź wsteczną
(`OnClarificationAnswered`: subskrybuje w `resolution`, publikuje do `matching`) i **milczy na trzech
kontrolach**, które publikują do przodu. Sam fakt, że check znajduje przypadek zbudowany pod niego, nie
dowodzi niczego — dowodem jest milczenie na kontrolach.

Kształty pokryte: **krok, który się cofa** (w checku i w runtime — para domyka się po wyjaśnieniu),
**to samo zdarzenie wiele razy w jednym przebiegu** (trzy pozycje = trzy fakty, jeden przebieg),
**zdarzenie wchodzące bez komendy** (bez aktora, bez przyczyny, a z tożsamością przebiegu).

Wyszło przy okazji:

- **Wykrywanie krawędzi wstecznych było logiką bez testu** — funkcją prywatną zadania mixa. Przeniesione do
  `PNS.Check`, bo sprawdzenie, którego nikt nie sprawdza, cicho przestaje działać, a na tym stoi trigger
  przeglądu ADR §15. **Reszta `mix pns.check` to nadal ~180 linii logiki całoprogramowej bez ani jednego
  testu** — do przeniesienia tą samą drogą.
- **Indirekcja `defp repo, do: @repo` w `PNS.Emitter` jest nośna, nie stylistyczna.** `@repo.aggregate(...)`
  rozwija atrybut do **literału modułu** w pozycji wywołania, więc `boundary` widzi referencję i odrzuca ją.
  Przez zmienną — nie widzi. To jest jedyny powód, dla którego `PNS` ma `deps: []`.
- **`clarification_requested` nie ma handlera i nie jest terminalne**, bo jego kontynuacja przychodzi z
  zewnątrz. Daje linię `info` i to jest uczciwe: nie ma w DSL słowa „czeka na świat zewnętrzny" i **nie
  wolno go dopisać** — to byłoby nowe słowo pod jeden przypadek.
- **Aktor jako `nil` nie odróżnia „import" od „nie wiemy kto".** Sensowna wersja postulatu „każde zdarzenie
  ma aktora" to nie „wymagany", a **„nigdy cisza"** — jawny aktor systemowy. Do rozstrzygnięcia.

**1.3b Dwa moduły potrzebujące tych samych danych. ✅ zrobione 5 sierpnia.** Nośnikiem jest tabela
`taxvision_periods`: okres przestaje być stringiem i staje się wierszem z zakresem dat.

**Zakaz joinów międzymodułowych jest znośny, i jego cena jest zmierzona, nie opowiedziana.** `Taxvision.Tasks`
ustawia `due_on`, `Taxvision.AccountingMonth` ustawia `closes_on`, oba z tego samego okresu — i **każdy płaci
własnym zapytaniem**. Test liczy je telemetrią Ecto: dokładnie dwa trafienia w `taxvision_periods` na jedno
otwarcie miesiąca. Notatki §14 nazywają N+1 ryzykiem, nie niespodzianką; teraz jest liczbą.

Mechanizm, który to trzyma, jest mocniejszy niż zakaz: **`Taxvision.Periods` ma `exports: []`**, więc schemat
`Period` jest nieosiągalny z zewnątrz i join do niego jest **niewyrażalny**, a nie zabroniony. Ten sam ruch,
który zamienił „zdarzenie w dwóch procesach" ze sprawdzenia w niemożliwość. Rodzeństwo dostaje `fetch!/1` —
wywołanie funkcji, nie join.

Kanonizacja zadziałała natychmiast i widać to w testach: **nie da się zaksięgować w okresie, który nie
istnieje.** 23 testy padły przy pierwszym uruchomieniu, bo otwierały miesiąc bez kanonicznego okresu. To nie
był regres, a wymaganie, którego wcześniej nie było — okresy zakłada teraz setup, a jeden test pilnuje, że
wymaganie faktycznie obowiązuje.

Nie zmieniałem payloadów na `period_id`: to należy do 2.2 razem z wyrzuceniem `:period` ze słownika typów, bo
przed 2.2 płacimy czytelnością klucza przebiegu bez niczego w zamian. Zapisane wyżej.

**Kształt „instancja żyjąca tygodniami"** jest pokryty testami okna assercji (`{2, :day}`, `{3, :day}`) i
**nie wymagał niczego od silnika** — log jest append-only, a `instance_id` grupuje niezależnie od upływu
czasu. Zapisane, żeby nie budować pod niego zegara na niby.

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

**1.4 Behawioralna weryfikacja ścieżek, per instancja. ✅ zrobione 5 sierpnia.**
*Odbiór:* **spełnione.** `PNS.Conformance.untraversed_paths/1`, `test/conformance_test.exs`: 50 przebiegów
zgodnych → dokładnie **jedna** nieprzejechana ścieżka. 49 zgodnych plus jeden rozjazd → **zero**.

To jest jednocześnie odpowiedź na warunek falsyfikacji z ADR-a: **różnica declared vs observed jest
sygnałem, nie szumem.** Pięćdziesiąt przebiegów daje jedną linię raportu. Gdyby dawało pięćdziesiąt albo
trzy, odpowiedź brzmiałaby odwrotnie.

`PNS.Conformance` jest miejscem, w którym zbiegną się cztery pytania ekranu — dziś odpowiada na pierwsze.
Dzięki temu 1.7 nie powstanie jako czwarte zadanie mixa obok trzech innych.

Dwie sytuacje, w których raport łatwo skłamie, obie przypięte testem:

- **Zero przebiegów to brak podstawy, nie trzy znaleziska.** Proces, który nigdy nie ruszył, ma wszystkie
  ścieżki nieprzejechane; wypisanie ich zamienia „nie ma danych" w „mamy trzy problemy". Raport mówi
  `basis: :no_runs` i pustą listę — ta sama zasada, na której stoi ocena assercji.
- **Job w kolejce to „jeszcze nie", nie „nigdy".** Wypisywany osobno, nie jako nieprzejechany. Bez tego
  raport kłamie przy każdym normalnym opóźnieniu.

Liczy **przebiegi, nie wystąpienia** — bo tylko ta liczba przy wielu klientach odróżnia ciszę od braku
ruchu. Wolumen w teście jest symulowany, ale **proces nie**: przebiegi idą przez kontrakt z warsztatu, a nie
przez fazy dopisane pod kryterium odbioru.

**Symulować wolumen, nie proces.** Plan produktowy chce falsyfikacji na 50 zasymulowanych przebiegach i ma
rację co do taniości, ale nie nazywa wady: proces, który sam zaprojektuję, wyprodukuje dokładnie ten sygnał,
który w niego wpiszę. Te 50 przebiegów idzie więc przez **istniejący kontrakt z warsztatu**, nie przez fazy,
które sam dopiszę. Kształt pochodzi wtedy z sesji z klientem, a losowe są tylko dane.

**1.5 Ocena assercji `trace`. ✅ zrobione 5 sierpnia — trzy werdykty z czterech.** Per instancja.
*Odbiór:* **spełnione.** `PNS.Trace`, `test/trace_test.exs`, i widać to na prawdziwych danych:
`mix pns.trace` na pięciu przebiegach mówi „spełniona 5/5, 3 przez eventually, 2 przez or_else". Dwie
zablokowane firmy są **spełnione**, nie naruszone.

To jest pierwszy moment, w którym cokolwiek w runtime **czyta** `trace`. Do teraz assercja była prozą w
składni Elixira.

Trzy decyzje semantyczne, każda przypięta testem, bo każdą da się zepsuć w drugą stronę bez łamania
niczego innego:

- **Okno liczy się od pierwszego wystąpienia `from`, nie od ostatniego.** Inaczej proces uciekałby przed
  terminem w nieskończoność, emitując `from` ponownie — a przy ponownym sprawdzeniu rejestrów to nie jest
  przypadek teoretyczny.
- **`within` obowiązuje także `or_else`.** Inaczej termin jest bezużyteczny: proces zakończony poprawnie
  trzy miesiące po terminie byłby „spełniony". **Do potwierdzenia przez process ownera** — to jedyna
  decyzja w tym etapie, która należy do niego, nie do nas.
- **Przebieg bez `from` nie jest oceniany wcale.** Ani spełniony, ani naruszony — nie ma o czym orzekać.
  Liczenie go jako naruszenia zrobiłoby alarm z każdej niezaczętej sprawy. Symetrycznie: zero przebiegów
  to brak podstawy do orzekania, nie zielony raport.

Wyszło przy okazji: **`or_else` produkowane handlerem asynchronicznym jest `pending`, dopóki job stoi w
kolejce** — ta sama lekcja, co czwarty stan nakładki. Koszt jest nazwany: job zaklinowany dłużej niż okno
policzy się jako naruszenie, i to jest poprawne, bo powiadomienie faktycznie nie poszło.

**1.5b Czwarty werdykt: `:suspended`.** Nie da się go policzyć, bo **nic w systemie nie zapisuje, że
zależność zewnętrzna była niedostępna** — `unavailable_looks_like` jest dziś zdaniem, którego nikt nie
czyta. Do tego czasu awaria rejestru w oknie assercji liczy się jako naruszenie, czyli obwiniamy klienta za
cudzy serwer.

Warunek wstępny jest po stronie silnika i mały: log obserwacji niedostępności per `external`, zapisywany
przez adapter na szwie, który już istnieje. Świadomie **obserwacje, nie przedziały** — adapter wie tylko,
że jedno wywołanie padło, a nie kiedy usługa wróciła. Zawieszona = w oknie assercji jest obserwacja
niedostępności zależności, od której zależy któreś zdarzenie tej ścieżki (`depends_on`).

Przy okazji do rozstrzygnięcia: **assercja bez `within` jest niefalsyfikowalna** — nie da się jej naruszyć,
więc jest dekoracją. Kandydat na `info` w `pns.check`; dziś obie nasze assercje mają `within`, więc byłoby
zero znalezisk.

**1.6 Wersja kontraktu jako pierwszoklasowa odpowiedź. ✅ zrobione 5 sierpnia.**
*Odbiór:* **spełnione.** `PNS.Deployment`, `test/deployment_test.exs`. Raport mówi, co wdrożone, od kiedy,
jakie wersje są w logu, ile zdarzeń pochodzi z innych wersji, oraz co się zmieniło — osobno zdarzenia,
osobno ścieżki.

**Najważniejsze wyszło z ostatniej części kryterium („bez ani jednego fałszywego driftu") i było prawdziwą
dziurą, nie hipotetyczną.**

`version/0` haszuje **deklaracje kontraktu**. Ścieżki pochodzą z `publishes:` **handlerów**, których w tym
haszu nie ma. Skutek: usunięcie handlera zmienia graf, nie zmieniając ani jednej wersji stemplowanej
gdziekolwiek — więc nakładka widziała krawędź zaobserwowaną i już niezadeklarowaną, sprawdzała, że wersja
kontraktu jest wciąż aktualna, i orzekała **drift** dla ścieżki, która była legalnie zadeklarowana, kiedy
przejechała.

Notatki §9 mówią, że skew wersji „handled by `contract_version` on the event", i podają przykład z
**usuniętym zdarzeniem** — ten działa, bo usunięcie zdarzenia bumpuje wersję. Przypadku z usuniętym
**handlerem** rekord nie rozważa. **Do poprawki w rekordzie.**

Rozwiązanie: **wdrożenie ma dwie tożsamości.** `contract_version` to umowa, `wiring_version` to kod. Refaktor
rusza jedną i nie rusza drugiej, a to jest dokładnie rozróżnienie, na którym klientowi zależy.

Kształt zapisu: jeden wiersz na odrębne obwodowanie, przy boocie. **Nic per zdarzenie** — koszt to jeden
insert na deploy, a nie kolumna na każdym zdarzeniu, i log zostaje tym, czym był. Pytanie o drift zadaje się
teraz wprost krawędzi („czy była kiedykolwiek zadeklarowana"), a nie przez wersję zdarzenia docelowego.

Cena jest nazwana, nie ukryta: log starszy niż tabela wdrożeń nie ma czym się wylegitymować i wraca do starej
heurystyki po `contract_version`. Jawnie, bo raport, który zgaduje bez powiedzenia tego, jest gorszy od
raportu, który przyznaje się do luki.

Dwie rzeczy przy okazji:

- **`since` to pierwsze zdarzenie pod wdrożoną wersją, nie moment deployu.** Silnik nie jest o deployach
  informowany, tylko je obserwuje. Wdrożenie, które nic nie wyemitowało, ma `since: nil` — wdrożone i
  niedowiedzione, co jest uczciwsze niż data, której nie znamy.
- **Hash obwodowania jest kanoniczny z konstrukcji** — z posortowanych stringów, nie z `term_to_binary`.
  `version/0` nadal ma tę wadę (luka 2.4, aktualizacja OTP może przekwalifikować historię) i `PNS.Deployment`
  jest wzorem dla tamtej poprawki.
- **Zapis przy boocie idzie poza sandboxem**, więc w środowisku testowym wiersze commitowały się na stałe i
  przeciekały do każdego testu. Czyszczone w setupie, wewnątrz transakcji sandboxa; zachowanie produkcyjne
  nietknięte.

**1.7 Raport zgodności za okres. ✅ zrobione 5 sierpnia — ETAP 1 ZAMKNIĘTY.**
*Odbiór:* **spełnione.** `PNS.Conformance.report/2` (dane) plus `Taxvision.Report.render/1` (zdania),
`mix taxvision.report`, `test/report_test.exs`.

Cztery pytania w jednym artefakcie, po polsku, zdaniami:

```
RAPORT ZGODNOŚCI — 2026-07-01 – 2026-07-31
USTALENIA
  Wersja ustaleń 7c229c333c21, obowiązuje od 2026-08-05.
PROCES: Cykl miesięczny księgowy
  Przebiegów w tym okresie: 5.
  Należny: co miesiąc.
  Wszystkie ustalone kroki zostały w tym okresie wykonane.
  Ustalenie: po „Potwierdzono komplet danych historycznych" w ciągu 2 dni następuje
            „Otwarto miesiąc księgowy", albo „Wysłano powiadomienie o rozjeździe…".
    Dotrzymane we wszystkich 5 przebiegach. (w tym 2 przez drugie z tych zakończeń…)
ROZBIEŻNOŚCI
  Brak: nic nie zaszło poza ustaleniami.
```

**Termin 25 dni w raporcie nie występuje** i to jest twarda część kryterium. Filtr siedzi w
`PNS.Conformance.verified_declarations/1`, publicznej — bo reguła, której nie da się przetestować wprost,
jest regułą, która cicho przestaje obowiązywać. Test dowodzi obu stron: z `unverified: [:deadline]` termin
nie wychodzi, a po jego zdjęciu wychodzi. Bez tej drugiej połowy pierwsza przechodziłaby też przy zepsutym
filtrze.

Trzy rzeczy rozstrzygnięte przy okazji:

- **Renderowanie jest po stronie klienta, nie silnika.** `PNS.Conformance` produkuje dane, `Taxvision.Report`
  zamienia je w zdania. Silnik nie wie, w jakim języku czyta jego odbiorca — a ten raport czyta księgowa.
  Gdyby nagłówki generował pakiet, artefakt dowodowy byłby dwujęzyczny bez powodu. Zadanie mixa też jest
  w drzewie klienta (`mix taxvision.report`); `pns.graph`, `pns.trace` i `pns.check` zostają, bo mają innego
  odbiorcę i inne pytanie.
- **`trace` jest jedyną deklaracją bez `label`** — więc nazwa techniczna byłaby wszystkim, co można wypisać,
  a `month_opens_or_is_blocked` w raporcie dla księgowej oblewa kryterium. Raport składa **zdanie z etykiet
  zdarzeń**, czyli ze słów, które klient już zatwierdził.

  **Rozstrzygnięte 5 sierpnia: `label` do `trace` nie wchodzi.** `trace` ma już nazwę
  (`trace :month_opens_or_is_blocked do`), brakuje mu etykiety klienckiej — i to jest różnica, która decyduje.
  Etykieta zdarzenia **dodaje fakt**, którego nie ma nigdzie indziej: żaden silnik nie wyprowadzi „Otwarto
  miesiąc księgowy” z `accounting_month_opened`, więc nie ma z czego dryfować. Etykieta assercji
  **powtarzałaby fakt już w pełni wyrażony** przez `from`/`eventually`/`within`/`or_else` — czyli drugą
  edytowalną reprezentację jednej rzeczy. Zmień `within: {2, :day}` na `{5, :day}` i proza dalej mówi „w ciągu
  dwóch dni”, a **nic tego nie łapie**. To jest argument, którym ADR §2 odrzuca zewnętrzny format dokumentacji
  jako źródło, obrócony na nasz własny DSL. Zdanie składane jest wyprowadzone, więc **nie może skłamać**.

  Czego assercja faktycznie nie umie powiedzieć, to **dlaczego ją ustalono** — „bo urząd liczy termin od
  otwarcia" `[WF 00:34:40]`. Tego w mechanice nie ma, nie da się wyprowadzić i nie ma z czego dryfować. Słowo
  na to **już istnieje**: `source:`, dziś tylko na `rule`. Rozszerzenie kosztuje zero nowych słów, `label`
  kosztowałoby jedno. **Nie dopisane** — obie nasze assercje pochodzą z warsztatu i żadna nie ma zapisanego
  pochodzenia, a czy process owner ma uzasadnienia warte zapisania, to pytanie warsztatowe.
- **Raport wymagał `until:`**, którego nie miało nic. Samo `since` znaczy „od X do teraz", więc lipcowy
  raport wygenerowany we wrześniu zawierałby sierpień — a dowód, który zmienia się przy ponownym wydruku,
  nie jest dowodem. Doszło do `PNS.Graph`, `PNS.Trace` i `PNS.Deployment`.

Przy okazji jeden błąd wart nazwania: `versions_in_log` filtrowałem przez `is_nil(^since) or ...`, co Ecto
słusznie odrzuca — porównanie pola z przypiętym `nil` nie jest ani prawdą, ani fałszem. Zapytanie składa się
teraz przez kompozycję, jak w `PNS.Graph`.

## Etap 2 — obietnice kontraktu, które dziś są dekoracją

**2.1 Handler emituje tylko to, co zadeklarował. ✅ zrobione 6 sierpnia.**
`PNS.Handler.verify_publications!/2`, `test/publications_test.exs`. 141 testów.

Reguła mieszka w `PNS.Handler`, nie w `PNS.Emitter` — bo tam już siedzi jej kompilacyjna połowa, a
**deklaracja sprawdzana w jednym pliku i dotrzymywana w drugim to gotowy rozjazd.** Wołana z dwóch miejsc:
[emitter.ex:190](lib/pns/emitter.ex:190) i [job.ex:45](lib/pns/job.ex:45).

**Sprzężenie z 1.6, którego ten punkt wcześniej nie nazywał.** `wiring_version` liczy się z `publishes:`
([deployment.ex:214](lib/pns/deployment.ex:214)), więc tożsamość wdrożenia była haszem deklaracji, których
nikt nie weryfikował. Handler emitujący poza deklaracją produkował krawędź, której w żadnym zapisanym
obwodowaniu nie ma — i raport nazywał to driftem, **poprawnie w formie i z fałszywego powodu.**

**Jedna reguła, dwie konsekwencje — po granicy transakcji, nie po preferencji.** Synchronicznie: rzuca,
transakcja się cofa, w logu nie ma ani emisji, ani zdarzenia, które ją wywołało. W kolejce: łapie się tam,
gdzie każda inna awaria handlera, ląduje w `event_handlings` z komunikatem, a **zdarzenie wywołujące zostaje**
— bo job leci poza transakcją, świadomie, i fakt, który go wywołał, pozostaje faktem. Sprawdzenie idzie
**przed** emisją, nie po: gdyby po, graf byłby już sprzeczny z logiem, kiedy ktokolwiek się dowie.

Naruszenie **nie może być stanem danych, tylko defektem kodu** — i deklaracja, i emitowana nazwa są w
handlerze statyczne. Dlatego wywala się na pierwszym teście, który handler przejedzie, i to jest cała
wartość: przenosi wykrycie z produkcji do CI.

Fikstury (`OnItemReviewed`, `OnItemEscalated`) są w rigu, bo **złamany kod na potrzeby testu nie ma prawa
stać w drzewie klienta** — żadna domena nie powinna nosić przykładu buga. Oba deklarują `publishes: []`, więc
nie wnoszą **ani jednej krawędzi**: graf, `wiring_version` i raporty ścieżek zostają nietknięte. Dwie
fikstury, nie jedna, bo jedna reguła wołana z dwóch miejsc to dokładnie to, co się rozjeżdża — i nie mogą
dzielić zdarzenia, skoro synchroniczna cofa transakcję, w której stałby job.

Naruszenie zależy od payloadu, a nie jest bezwarunkowe, i to nie jest wygoda: **ten sam handler emitujący nic
nie może rzucać.** Bez tej kontroli sprawdzenie reagujące na dowolny return handlera przeszłoby test
pozytywny. Zweryfikowane odwrotnie — po zneutralizowaniu reguły pada **cztery z ośmiu** testów, czyli
dokładnie te, które o naruszeniu cokolwiek twierdzą.

Zostaje na później: tracer kompilacji (notatki §2) przesunąłby wykrycie jeszcze wcześniej, ale to
optymalizacja momentu, nie warunek poprawności.

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

**2.3 Ślad po awarii handlera synchronicznego. ✅ zrobione 6 sierpnia.** `PNS.HandlerFailure`,
`PNS.SyncHandlerError`, `test/handler_failure_test.exs`. 162 testy.

Plan mówił „zapis poza transakcją **albo** telemetria". Weszły **oba i z różnych powodów**: telemetria, bo
zbieranie błędów należy do narzędzi klienta (`[:pns, :handler, :exception]` z handlerem, przebiegiem i
stacktrace'em), a trwały wiersz, bo **telemetria istnieje tylko tam, gdzie ktoś skonfigurował kolektor**, a
luka z ADR §13 jest o **artefakcie**, nie o observability.

**Kryterium ma dwie połowy, które się przeciągają, i obie są przypięte.** Awaria jest zapisana **i cofnięcie
zostaje w mocy** — zapisanie okupione osłabieniem rollbacku wymieniłoby lukę diagnostyczną na log, który
kłamie, że fakt zaszedł, choć praca się nie wykonała.

**Osobna tabela, nie status na `pns_event_handlings`, i nie z wygody.** Każdy inny wiersz w logu mówi o czymś,
co zaszło; ten mówi o czymś **próbowanym, co nie zaszło** — więc nie ma na co wskazać, bo zdarzenie zostało
cofnięte i nigdy nie istniało. Klucza obcego nie ma i to jest decyzja, nie przeoczenie. Tym, co przeżywa
rollback, jest `correlation_id`, generowany przed otwarciem transakcji, i to on jest uchwytem.

**Gdzie zapis, bo to była cała trudność.** Nie tam, gdzie awaria jest zauważona — ten kod siedzi w skazanej
transakcji, więc jego insert cofnąłby się razem z nią. Zapis idzie w **najbardziej zewnętrznej ramce
emittera**, tej, która transakcję otwarła, **po** rollbacku, kiedy połączenie jest znowu wolne. Żadnego
drugiego połączenia, żadnego `Task`, żadnego pisania obok sandboxa w testach — a to ostatnie miało już
kiedyś cenę przy `PNS.Deployment.record!`.

**Wrapper jest transportem i nie wychodzi do wołającego.** Ramka, która wie *który handler padł na którym
przebiegu*, jest głęboko w transakcji, która zaraz zniknie; ramka, która umie trwale zapisać, nie wie nic —
kontekst musi odbyć podróż. Ale pierwsza wersja przepuszczała `PNS.SyncHandlerError` na zewnątrz i **jeden
test to złapał**: wołający zamiast `ArgumentError` handlera dostawał wyjątek silnika. To byłaby zmiana
łamiąca obsługę błędów u każdego klienta, wprowadzona jako efekt uboczny mechanizmu diagnostycznego. Teraz
emitter odwija i rzuca **oryginał z oryginalnym stacktrace'em** — samo `reraise original, __STACKTRACE__`
wskazywałoby bibliotekę, co jest gorsze niż brak wrappera, więc stacktrace jedzie w polu.

**Podwójne zawinięcie.** Emisja handlera odpala następny handler, więc `rescue` ramki wyżej zawinęłoby już
zawinięty błąd i przypisało awarię **nie temu handlerowi**, plus jedno zdarzenie telemetrii na ramkę. Osobna
klauzula na `PNS.SyncHandlerError` przepuszcza go bez zmian.

**Tabela ma czytelnika od pierwszego commita**, bo inaczej jest kolejną deklaracją, której nikt nie czyta — a
etap 2 istnieje po to, żeby takie usuwać. `PNS.Conformance` odróżnia **„nigdy nie próbowano" od „próbowane i
nie udaje się"**: „zadeklarowane, nigdy nie zaobserwowane" czyta się jako martwy albo nieprzetestowany krok, a
dla handlera, który leci i pada w każdym przebiegu, **oba odczyty są fałszywe** i idą do złej osoby. Ścieżka z
padającym handlerem wypada z listy nieprzejechanych i wchodzi na własną. To trzeci wariant jednego błędu:
raport nie ma prawa zamieniać *braku odpowiedzi* na *odpowiedź „nie"*.

Liczy **przebiegi, nie awarie** — handler ponowiony czterdzieści razy dla jednego klienta to jeden padający
przebieg. `coalesce` wymagało jawnego rzutowania, bo `instance_id` jest tekstem, a `id` uuidem, i Postgres
słusznie odmawia zamiast wybrać po cichu.

**Limit nazwany, nie obejściony:** kiedy transakcję otwarł wołający, silnik nie dostaje swojej kolejki —
wyjątek wchodzi w ich transakcję i ślad jest ich do zapisania. Trwały zapis z wnętrza czyjejś skazanej
transakcji nie jest na jednym połączeniu możliwy. Przypięte testem, żeby limit był własnością, a nie
niespodzianką.

Fikstura `OnItemFlagged` jest w `intake`, **nie w `resolution`**, choć tam byłaby naturalniejsza: publikuje do
`matching`, więc z `resolution` byłaby **drugą krawędzią wsteczną** i po cichu zepsułaby kryterium odbioru
1.3, zmieniając liczbę z jednej na dwie. Sprawdzone: `pns.check` nadal zgłasza jedną.

Zweryfikowane odwrotnie: po wyłączeniu zapisu padają **trzy z dwudziestu trzech** testów w tych dwóch
plikach — dokładnie te, które o śladzie cokolwiek twierdzą.

**2.4 Cztery rzeczy odpornościowe.** Ochrona przed cyklem w runtime; zdefiniowana albo zabroniona kolejność
dwóch handlerów synchronicznych na jednym zdarzeniu; łagodne odrzucenie joba po znikniętym handlerze.

**Kanoniczny hash — ✅ zrobione 6 sierpnia, wyciągnięte przed 2.2.** `PNS.Digest`, `test/digest_test.exs`.
Powód wyciągnięcia: 1.6 i 1.7 właśnie oparły klasyfikację historii na `contract_version`, więc luka
przestała być hipotetyczna — zaczęła podpierać raport dowodowy.

**Groźniejszy z dwóch defektów nie był tym, który miał w planie nazwę.** Aktualizacja OTP to zdarzenie, które
ktoś zauważa. **Przestawienie dwóch bloków `event` w pliku to zwykła edycja** — a `term_to_binary` liczył z
listy w kolejności deklaracji, więc wersja się ruszała, mimo że ustalenia nie. Kolejność deklaracji jest teraz
nieistotna, bo kontrakt jest **zbiorem** deklaracji, nie ciągiem.

Rozróżnienie, na którym stoi cały moduł: **kolekcje deklaracji sortujemy, wartości wewnątrz deklaracji nie.**
`instance: [:company_id, :period]` i odwrotność to dwa różne ustalenia, bo klucz przebiegu to te wartości
złączone w kolejności — posortowanie zrównałoby dwa różne klucze. To samo `stages:`, bo kolejność faz
decyduje, czy krawędź jest wsteczna.

Sortowanie idzie po kanonicznej postaci **całej** deklaracji, nie po kluczu `name`. Dzięki temu moduł nie
musi wiedzieć, który klucz nazywa deklarację, i nie ma grupy, której trzeba go nauczyć — `example` nie ma
`name` i to przestało być przypadkiem szczególnym.

`PNS.Deployment` liczy teraz z tego samego źródła, więc **obie tożsamości wdrożenia mają jedną kanoniczną
postać**, a nie jedną dobrą i jedną utwardzoną. Krawędzie są tam sortowane przed haszowaniem — to jedyne
miejsce, gdzie `PNS.Digest` potrzebuje pomocy wołającego, bo kolejność listy zachowuje świadomie.

**Cena zapłacona raz, jawnie: wersja skoczyła `7c229c333c21` → `0343089e9d75`.** Czyli poprawka wykonała
dokładnie to przeklasyfikowanie, któremu zapobiega — jednorazowo i celowo. Raport powie „zdarzeń z
wcześniejszych wersji ustaleń: N, to legalna historia", co jest uczciwe. **Konsekwencja dla harmonogramu:
to musiało wejść, zanim log klienta ma historię wartą zachowania**, i dlatego nie czekało na 2.2.

Fikstury (`Ordered`, `Reordered`, `Changed`) stoją **w pliku `.exs`**, bo rejestr skanuje listę modułów
aplikacji, a moduły z `.exs` w niej nie są — więc są niewidoczne dla grafu, tabeli wdrożeń i każdego raportu
ścieżek. Sprawdzone: `pns.check` pokazuje nadal 18 informacji i trzy kontrakty w rejestrze. Kontrakt, który
istnieje tylko po to, żeby go zahaszować, nie ma prawa wyjść w raporcie klienta jako proces bez przebiegów.

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
(„jedno zdarzenie w dwóch procesach" nie jest błędem kompilacji, a rzeczą niewyrażalną).

**Druga partia — z etapów 1.3–1.7 — dopisana 5 sierpnia jako `9897c91` na tej samej gałęzi.** Dwa commity,
jeden przegląd, i podział widoczny w treści: co kod obalił (1–3) wobec tego, czego rekord żądał jako dowodu
(4–5). Sprawdzone w kodzie, nie z pamięci, w kolejności wagi:

1. **ADR „What would falsify this", ostatni bullet, jest dziś w połowie nieprawdziwy.** Mówi, że `trace`
   i `deadline` nie mają czytelnika. 1.5 dał czytelnika `trace`; **`deadline` nadal go nie ma** i to jest
   sprawdzalne — patrz tabela luk wyżej. Poprawka mówi „połowa zrobiona, i wiemy która", nie „zrobione”.
2. **ADR „What we are betting on", zakład declared-vs-observed: liczba jest, zabezpieczenia są nie te.**
   1.4 dał liczbę (50 → 1, 49+1 → 0). Ale akapit wymienia `cadence` i `contract_version` jako to, co
   trzyma fałszywe pozytywy w ryzach, a **cadence nie stosuje się do procesu zdarzeniowego** (poprawione
   w §15, nie w tym akapicie) i **`contract_version` nie obejmuje usuniętego handlera** (1.6). Doszły dwa
   źródła, których rekord nie zna wcale: **zero przebiegów** i **job w kolejce**. Zabezpieczeń jest cztery.
3. **ADR §16–17, tabela „What ships": `Dashboard — inside the engine`.** 1.7 rozdzielił dane od zdań, bo
   silnik nie wie, w jakim języku czyta jego odbiorca. Albo dashboard w silniku dostaje **szew na renderer
   klienta**, albo raport dowodowy — pozycja **komercyjna** w tej samej sekcji — jest artefaktem klienta.
   Dziś w kodzie jest to drugie i nie było decyzją, tylko konsekwencją. **Zapisane jako piąte otwarte
   pytanie ADR-a, nie jako fakt** — decyzja jest tania teraz i droga, kiedy klient wypuści własny raport.
4. **ADR §5–6, trigger „Not before the split is validated": dowód jest.** 1.3b — dwa zapytania na jedno
   otwarcie miesiąca, liczone telemetrią, i `exports: []` czyniące join **niewyrażalnym**. `Consequences`
   „Query counts rise" ma liczbę zamiast przymiotnika.
5. **ADR §15, trigger „compensation smearing": dostarczony, i ważniejsze jest jak.** Wykrywanie krawędzi
   wstecznych było prywatną funkcją zadania mixa **bez testu** — trigger przeglądu decyzji provisional stał
   na sprawdzeniu, którego nikt nie sprawdzał. Przeniesione do `PNS.Check`. Natomiast „nesting is still
   unenforced" **zostaje prawdą**: 1.3 pokrył pięć kształtów i zagnieżdżenia nie było wśród nich — to do
   potwierdzenia, nie do zmiany.

Notatki, nie ADR: §9 version skew (usunięty handler), §9 „navigation is per-process, never global" wobec
braku zawężenia w `PNS.Graph`, §9 okno „never observed" bez implementacji, §14 N+1 jako liczba, §5 o
`basis:` i licznikach w dwóch wymiarach.

Jedno otwarte pytanie **zwężone, nie zamknięte**: „what the evidence report says about a period whose
definitions changed" — okres jest teraz wierszem z zakresem dat, a okno raportu jest na `occurred_at`, nie
na okresie.

**Uwaga przy odgałęzianiu od tego repozytorium:** decyzji 008 ani notatek technologicznych **nie ma na
`main`** — żyją wyłącznie na `docs/pns-architecture-adr`, która bywa przepisywana. Gałąź odbita od niej
osierocieje po każdym rebase i wymaga `rebase --onto`. Zdarzyło się to raz, 5 sierpnia.

Gałąź `backup-polskie-opisy` **usunięta 5 sierpnia** po sprawdzeniu, że wszystkie siedem drzew jest w
`main` i że commit `c54becb` ma niezmieniony SHA.

## Kolejność

**Etap 1 zamknięty w całości.** 1.1–1.7. Brama uniwersalności przeszła, `trace` przestał być dekoracją, a różnica
declared vs observed okazała się sygnałem — 50 przebiegów daje jedną linię raportu, a wszystkie pięć
kształtów procesu jest obsłużonych. **Dalej: etap 2** — obietnice kontraktu, które dziś są dekoracją.

Z etapu 1 zostaje otwarte **jedno**: **1.5b**, werdykt `:suspended`, czekający na log niedostępności
zależności. Język kodu spłacony 5 sierpnia (`a0ec986`), rekord rozliczony w całości — dwa commity na
`docs/pns-record-corrections-etap-1`.

Zamknięte 5 sierpnia bez zmiany w DSL: **`label` dla `trace` nie wchodzi** — powód przy 1.7. Do process
ownera zostaje jedna rzecz z etapu 1, węższa niż się wydawała: **potwierdzenie, że `within` obowiązuje także
`or_else`.**

Kod zostaje w tym repo i przenosi się do repozytorium pilota, gdy ono powstanie; struktura jest już taka, że
to `git mv`.
