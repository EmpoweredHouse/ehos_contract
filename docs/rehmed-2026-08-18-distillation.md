# Rehmed — destylacja do kontraktu PNS, 2026-08-18

Po polsku, bo to materiał roboczy zespołu i cytuje klienta dosłownie — nie kod, nie jedzie z pakietem.
Nazwy techniczne zdarzeń i klucze DSL są po angielsku, `label` po polsku, zgodnie z regułą repo i
z tym, co robi `Taxvision.Contracts.AccountingMonth`.

**Wejście:** `2-Solution/` z `~/Projects/ai/rehmed-process-native` — przebiegi 1–5 (`10-event-model.md`,
`20-aggregates.md`, `30-contexts.md`, `40-slices.md`, `50-screens.md`), plus punktowo `wiki/concepts/`
i `1-Discovery/01-processes.md` tam, gdzie przebieg cytuje je skrótem. **To nie są surowe transkrypty
ani wyjście `process-extraction`** — to własna warstwa modelu solution-space klienta, sama oznaczona
`status: open`. Konsekwencja jest istotna i nie da się jej uśrednić: **każdy „dowód" poniżej jest
dowodem drugiego rzędu.** Gdzie przebieg podaje znacznik czasu z transkryptu, przepisuję go; gdzie
podaje tylko własny identyfikator, piszę identyfikator i tyle.

**Ostrzeżenie o jakości źródła, wprost z README tamtego repo:** *4 ze 115 zdarzeń to `observed`, reszta
to `stated`.* Nic tutaj nie jest potwierdzone z klientem. Ten dokument jest wejściem do pisania
kontraktu, nie kontraktem.

**Weryfikacja słownika:** `mix pns.docs --check` → `docs/contract.md: reference is current` (2026-08-18).
Kategorie poniżej rzutowane na ten plik, nie na pamięć o nim.

---

## Zanim przeczytasz procesy

Wyszły z rzutowania i są ważniejsze od pojedynczych procesów, więc idą na górę. Najpierw jedna
poprawka do kryterium, potem trzy ustalenia o kształcie kontraktu.

### 0. Poprawka do kryterium: **sekwencja, nie zegar**

Pierwsza wersja tej destylacji oceniała procesy tym, ile mają kandydatów na `trace`, i odrzuciła dwa
jako *nienadające się w ogóle*. **To było mierzenie złą miarką**, wziętą wprost ze skilla — który mówił,
że `trace` jest kategorią nośną, a proces bez niej nie jest jeszcze wart weryfikacji. Skill został
poprawiony 2026-08-18; ten dokument jest poprawiony razem z nim.

Silnik mówi co innego. **Trzy z czterech pytań ekranu liczą się bez zegara:**

| Pytanie | Mechanizm | Potrzebuje czasu? |
|---|---|---|
| które zadeklarowane ścieżki nigdy nie zostały przejechane | `PNS.Conformance` | **nie** |
| które przejścia nie są zadeklarowane | `PNS.Graph` | **nie** |
| która wersja kontraktu jest wdrożona i od kiedy | `PNS.Deployment` | **nie** |
| które assercje `trace` są naruszane | `PNS.Trace` | tak |

Do tego `PNS.Check.backward_edges` sprawdza kolejność **po `stage`, bez jednego zapytania do logu**.
`module-boundary-check` — drugi skill w tym repo — od początku miał to poprawnie: *structural tracking
(process, instance, stages — for drift/untraversed-path detection, **no timing required**)*.

**Rehmed jest domeną sekwencyjną, nie zegarową, i to jest normalny przypadek, nie ułomny.** Zdarzenia
odpala recepcja i specjalista klikając w ekrany; znaczenie ma **kolejność i to, czy ścieżka w ogóle
została przejechana**. I to jest dokładnie to, co model klienta ma najmocniejszego — jego własna
tabela *„reguły, których nikt dziś nie egzekwuje"* to w większości **twierdzenia o sekwencji**, nie
o czasie:

| Reguła z tabeli klienta | Czym jest dla silnika |
|---|---|
| wizyta płatnikowa musi zostać oznaczona jako rozliczona, inaczej płatnik nie płaci | zadeklarowana ścieżka, która nie jest przejeżdżana |
| wykonana wizyta **w ogóle** zostaje zamknięta klinicznie | jw. — i to jest te „16 wizyt niezakończonych" |
| każda wykonana wizyta płatnikowa jest zafakturowana albo wykluczona z powodem | jw. |
| korekta przypisuje się do dnia, którego dotyczy | niezmiennik + przejście, które dziś prowadzi w złe miejsce |

Żadna z nich nie potrzebuje `within`. Wszystkie cztery są policzalne z kontraktu i logu.

Konsekwencja dla czytania reszty: **tabele „kandydaci na `trace`" poniżej zostają, ale przestają być
oceną procesu.** Ocena jest w sekcjach *Etapy / bramki*, *Stany końcowe* i *Instancja*.

### 1. Granica agregatu ≠ granica `process`

Model dzieli wizytę na trzy agregaty (`AGG-01` rezerwacja, `AGG-02` dokumentacja, `AGG-03` rozliczenie,
`DEC-01`) — **wszystkie trzy mają tę samą tożsamość: `visit id`.** `AGG-10` (zgłoszenie P1) też.

W PNS `trace` **nie może przekraczać granicy procesu** (gate kompilacji: *`trace` spanning two
processes*). A wszystkie obietnice, które w tej domenie warto weryfikować, biegną **w poprzek** tych
agregatów: od wykonania wizyty do zgłoszenia w P1, od przekazania do płatności, od wyjścia pacjenta do
zamknięcia klinicznego.

> **Wniosek: to jest jeden `process :wizyta, instance: [:visit_id]` ze `stages`, a nie trzy procesy.**
> Podział na agregaty jest ustaleniem o spójności zapisu i zostaje w kodzie domeny; `process` w PNS jest
> jednostką *przebiegu*, i tu przebieg jest jeden.

Nie rozstrzygam tego za piszącego kontrakt — ale jeśli powstaną trzy procesy, **żadna z traktowanych
poważnie obietnic tej domeny się nie skompiluje**, i lepiej wiedzieć to teraz niż przy gate'cie.

### 2. Większość obietnic Rehmedu jest zakotwiczona **wstecz** od przyszłego momentu, a `trace` biegnie **w przód** od zdarzenia

`trace` liczy okno od **pierwszego wystąpienia `from`** — czyli od faktu, który się wydarzył. Tymczasem
w tej domenie kluczowe terminy są liczone od momentu **zaplanowanego w przyszłości**:

| Obietnica | Kotwica | Da się jako `trace`? |
|---|---|---|
| SMS z prośbą o potwierdzenie — 09:00 ostatniego dnia roboczego przed wizytą (`P-01`) | wstecz od terminu wizyty | **nie** |
| Bezpłatne odwołanie do zamknięcia recepcji dnia poprzedniego (`AGG-20` inv. 2, `H16`) | wstecz od terminu wizyty | **nie** |
| SMS o wygaśnięciu bonu — 2 miesiące przed (`P-09`) | wstecz od daty ważności | **nie** |
| Telefon po ~5 min nieobecności (`P-04`) | w przód od godziny startu wizyty | **tak, jeśli start jest zdarzeniem** |
| Zgłoszenie do P1 w 2 dni od zakończenia świadczenia | w przód od faktu | **tak** |

**I wniosek jest taki, że one po prostu nie należą do kontraktu.** Pierwsza wersja tego akapitu
proponowała obejście — niech planista emituje fakt „nadszedł moment przypomnienia dla tej wizyty",
a `trace` biegnie od niego. To jest dokładanie silnikowi zegara, którego ta domena nie ma:
**zdarzenia w Rehmedzie odpalają ludzie klikający w ekrany, nie harmonogram.** Przypomnienie o wizycie
jest zadaniem z terminem i ma właściciela — `F-02`, silnik zadań, siedemnaście plastrów. Wpychanie go
do kontraktu po to, żeby dało się o nim napisać asercję, odwraca zależność: mechanizm powstaje pod
narzędzie pomiaru, a nie pod pracę.

Zostaje w tabeli jako **fakt o domenie**, nie jako luka do zasypania.

Dodatkowo: `within` przyjmuje wyłącznie `:second | :minute | :hour | :day` (`PNS.Duration`). **„Ostatni
dzień roboczy" i „miesiąc" nie są jednostkami stałej długości** — nie skompilują się i nie powinny.
Kalendarz roboczy per lokalizacja (`P-03`, trzy lokalizacje, stajnia z wieczornymi slotami) jest
konfiguracją domeny, nigdy argumentem `within`.

### 3. Awaria P1 zawiesza termin ustawowy — i to jest dokładnie `:suspended`

Rozporządzenie (tekst jedn. **Dz.U. 2025 poz. 866**, obowiązek od 1 lipca 2021) mówi: przekazać
niezwłocznie, nie później niż w **2 dni** od zakończenia świadczenia ambulatoryjnego — a **w razie awarii
systemu: nie później niż 3 dni od jej usunięcia**.

To jest jeden do jednego mechanizm `depends_on` + `unavailable_looks_like` → czwarty werdykt
`:suspended` (od 6 sierpnia czytany w runtime, patrz `docs/contract.md` § Known decoration). Nie trzeba
tego nagabywać ani tłumaczyć — **regulator sam napisał semantykę zawieszenia**. Jeżeli ma powstać jeden
kontrakt PNS dla Rehmedu jako dowód, że silnik robi coś prawdziwego, to jest ten.

Zastrzeżenie: PNS zawiesza asercję, gdy zależność **była widziana jako niedostępna w oknie asercji**.
Rozporządzenie liczy 3 dni **od usunięcia awarii**, czyli przedłuża okno, a nie zawiesza werdykt.
To nie jest to samo i nie należy udawać, że jest — patrz otwarte pytania procesu 3.

---

## 1. Cykl życia wizyty — od rezerwacji do przekazania do rozliczenia

**Wejście:** `2-Solution/10-event-model.md` §3.1–3.5, `20-aggregates.md` `AGG-01`
**Jakość dowodu:** stakeholder-stated; lane 7 tablicy walidowana pierwszoosobowo z fizjoterapeutami
2026-08-12, reszta z warsztatów. `E-115` to **propozycja Appunite** (`DEC-18`), nie obserwacja.

### Kandydaci na zdarzenia

| # | Zdarzenie (słowami klienta, dokonane) | Nazwa techniczna | Dlaczego w tym procesie | Dowód |
|---|---|---|---|---|
| 1 | Pacjent umówił wizytę | `visit_booked` | tworzy przebieg | `E-14`, ESB L2 |
| 2 | Wysłano SMS z umówionym terminem | `booking_confirmation_sent` | `P-30` reaguje na 1 | `E-16`, ESB L2 |
| 3 | Wysłano SMS ze szczegółami z prośbą o potwierdzenie | `confirmation_requested` | `P-01` | `E-21`, ESB L3 |
| 4 | Oznaczono wizytę jako potwierdzoną | `visit_confirmed` | odpowiedź na 3 | `E-22`, ESB L3 |
| 5 | Zadzwoniono do klienta | `patient_called` | `P-02`, „dzwonimy do skutku" | `E-23`, W1 00:09:24 |
| 6 | Oznaczono klienta — brak kontaktu | `contact_failed` | stan pośredni `AGG-01` | `E-24`, ESB L3 |
| 7 | Klient pojawił się na wizycie | `patient_arrived` | pacjent, spoza systemu | `E-27`, ESB L3 |
| 8 | Pacjent wszedł do gabinetu | `visit_started` | `AGG-01` → `WTrakcie` | `E-40`, ESB L7 |
| 9 | **Wizyta oznaczona jako wykonana i gotowa do rozliczenia** | `visit_handed_over` | **przekazanie władzy nad ceną** | `E-115`, `DEC-18` — **propozycja** |
| 10 | Pacjent wyszedł z gabinetu | `visit_completed` | `AGG-01` → `Zrealizowana` | `E-51`, ESB L7 |
| 11 | Oznaczono wizytę jako odwołaną | `visit_cancelled` | terminal | `E-28`, ESB L4 |
| 12 | Pacjent nie przyszedł | `patient_no_show` | terminal | `E-32`, ESB L5 |
| 13 | Zwolnił się termin | `slot_released` | `E-74`, **wnioskowane** — tablica nie ma tej krawędzi (luka G5) | `E-74` |

### Kształt payloadu

| Zdarzenie | Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|---|
| wszystkie | `visit_id` | która wizyta | `:id` | `AGG-01` tożsamość |
| `visit_booked` | `patient_id` | kto | `:id` | `AGG-05` |
| `visit_booked` | `service_id` | jaka usługa — z niej wynika flaga P1, czas trwania, cena | `:id` | `AGG-15` |
| `visit_booked` | `specialist_id` | kto wykonuje; „dział" stemplowany osobno (`DEC-21`) | `:id` | `AGG-18` |
| `visit_booked` | `location_id` | Krobia / Jutrosin / stajnia — **nie ma agregatu `Lokalizacja`**, a cztery inne go czytają | `:id` | `20-aggregates.md` § sweep |
| `visit_booked` | `scheduled_at` | termin | `:timestamp` | `AGG-08` |
| `confirmation_requested` | `channel` | SMS albo e-mail — dwa kanały, potwierdzone 2026-08-14 | `:enum` (zbiór niedeklarowalny) | `X-05` |
| `patient_called` | `attempt_at` | **kiedy ta próba** — bez tego druga próba jest tą samą | `:timestamp` | `E-23`, retry ~1h |
| `visit_handed_over` | `total_amount` | kwota, która staje się ostateczna | **nie mieści się** — brak typu pieniężnego | `DEC-18` |
| `visit_cancelled` | `cancelled_at` | moment wobec terminu bezpłatnego odwołania | `:timestamp` | `P-03` |

### Tożsamość

- **Ta sama rzecz dwa razy:** dla większości zdarzeń `[:visit_id]` wystarcza — wizyta jest umawiana raz.
  **Wyjątkiem jest `patient_called`**: „dzwonimy do skutku i zaznaczamy sobie, że nie odebrał raz o tej
  godzinie, próbujemy za godzinę" (VLW 00:09:30 wg `U-10`). Klucz musi zawierać `attempt_at`, inaczej
  druga próba zostanie połknięta przez pierwszą — dokładnie ta klasa błędu, którą w TaxVision złapało
  `diff` w `identity`.
- **Dowód:** `E-23`, `P-02`; `U-10` w `50-screens.md`.

### Instancja

- **Jeden przypadek:** jedna wizyta, od `visit_booked` do jednego z trzech końców.
- **Równolegle dla tego samego aktora:** **tak i to normalne** — pacjent może mieć serię wizyt („terapia
  miorelaksacyjna 5 razy, 2 razy w tygodniu", W2 01:01:28), a specjalista prowadzi ~100 wizyt dziennie na
  trzy lokalizacje. Rozróżnia je `visit_id`; **nie `patient_id`**.
- ⚠️ **Wizyta dwuosobowa (`H35`, zamknięte 2026-08-15) łamie 1:1 wizyta↔pacjent:** jedna usługa, dwa
  gabinety, opcjonalny split płatności. Jeśli `instance` ma być `[:visit_id]`, to para musi być dwiema
  wizytami albo jedną wizytą z listą pacjentów w payloadzie — **nierozstrzygnięte, blokuje kształt payloadu.**

### Powtarzalne zdarzenia w jednej instancji

| Zdarzenie | Więcej niż raz? | Co odróżnia drugie od pierwszego | Dowód |
|---|---|---|---|
| `patient_called` | **tak** | godzina próby; „próbujemy za godzinę", plus jeszcze raz w dniu wizyty | `P-02`, W1 00:09:24 |
| `confirmation_requested` | niejasne | jedno przypomnienie w projekcie `P-01`; czy przy braku odpowiedzi leci drugie — nie powiedziano | `P-01` |
| `visit_handed_over` | **tak, i to jest rozstrzygnięcie** | zmiana cenotwórcza po przekazaniu **otwiera wizytę ponownie i re-notyfikuje** (`DEC-18`) | `AGG-01` inv. 8 |
| `visit_booked` | nie | — | `AGG-01` |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `Zrealizowana` — pacjent wyszedł z gabinetu | dobre | `AGG-01`, `E-51` |
| `Odwołana` | neutralne; złe po terminie → rodzi `AGG-20` | `E-28`, `P-03` |
| `Nieobecność` | złe; rodzi `AGG-20` i licznik do czarnej listy | `E-32`, `P-06` |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| Kwalifikacja specjalisty do usługi | rezerwację | `AGG-01` inv. 2 — **dziś nieegzekwowane**, tryb `warn` proponowany |
| Zasób (sprzęt wyłącznie) zajęty | rezerwację; **przestrzeń nie blokuje, ma pojemność** (`DEC-22`) | `AGG-01` inv. 3 |
| PESEL przed rezerwacją **dla płatnika zewnętrznego** | rezerwację płatnikową | `AGG-01` inv. 4 |
| **PESEL przed rozpoczęciem wizyty — dla każdej** | start wizyty | **`U-11`, otwarte** — model tego nie ma, a „nie można odbyć wizyty bez PESEL-u" |
| Horyzont opublikowanego grafiku (~2 mies.) | rezerwację | `AGG-01` inv. 5 |
| `visit_handed_over` przed rozliczeniem | rozliczenie | `AGG-01` inv. 7 — **`U-09` mówi, że tej bramki nikt nie zamawiał i ma być ostrzeżeniem** |

⚠️ **Nie wolno wnioskować sekwencji `Potwierdzona → Obecny` jako jedynej.** `U-10` (otwarte): wizyta
niepotwierdzona **odbywa się** — recepcja dzwoni do skutku i zakłada, że pacjent przyjdzie. Brakujące
przejścia `Umówiona → Obecny` i `Umówiona → Nieobecność` nie chronią żadnej reguły.

### Kandydaci na `trace`

| # | Po (from) | W ciągu | Wtedy (eventually) | Inaczej (or_else) | Czy `within` wiąże też ścieżkę zapasową? | Komu obiecane | Dowód |
|---|---|---|---|---|---|---|---|
| 1 | `visit_started_time_reached` **(zdarzenie nie istnieje — trzeba je zmaterializować)** | `{5, :minute}` | `patient_arrived` | `patient_called` | **niepowiedziane** | pacjentowi, słabo | `P-04`, ESB L5, „~5 min grace" |
| 2 | `visit_booked` | **niepowiedziane** | `booking_confirmation_sent` | — | nie dotyczy | pacjentowi | `P-30` — SMS „automatic", **żadne źródło nie podaje N** |
| 3 | `visit_handed_over` | **niepowiedziane** | `payment_recorded` | `visit_closed_without_payment` | **niepowiedziane** | wewnętrznie | `P-08` — istnieje powiadomienie o zakończeniu bez płatności, ale bez terminu |

**Ten proces jest ubogi w obietnice **czasowe** i bogaty w twierdzenia o sekwencji** — a to drugie jest
tym, co go czyni wartym kontraktu. Trzy najgłośniejsze terminy domeny (przypomnienie, bezpłatne
odwołanie, wygaśnięcie bonu) są zakotwiczone wstecz i **nie należą tu** (ustalenie 0 i 2). Zostaje to,
co silnik liczy bez zegara, i jest tego dużo: sześć bramek, trzy stany końcowe z czego dwa złe,
i przejścia, które model uznaje za sporne.

**Najostrzejszy pojedynczy przypadek w całej destylacji jest właśnie tutaj.** `U-10`: wizyta
niepotwierdzona **odbywa się**, a maszyna stanów dochodzi do `Obecny` wyłącznie z `Potwierdzona`.
To jest, w słowniku silnika, **zadeklarowana ścieżka, której nie da się przejechać, przy zdarzeniu,
które dzieje się codziennie** — czyli dokładnie to, co overlay pokazuje jako pierwsze. Nie potrzeba
do tego ani jednej liczby.

### Kadencja

- **Zdarzeniowa.** Wizyta zaczyna się telefonem pacjenta, nie kalendarzem. `cadence` nie dotyczy.
- Jeden wyjątek obok procesu: **okno zapisów** otwiera się datą — prywatni ~15., płatnicy ~20. (`P-33`,
  `E-101`/`E-102`, RBS 00:44:43). To jest kadencja **grafiku**, nie wizyty.

### Retencja / dane wrażliwe

| Pole | Kategoria | Handler potrzebuje surowej wartości? | Proponowana polityka | Dowód |
|---|---|---|---|---|
| `patient_id` | PII pośrednio | tak | `:persist` | — |
| PESEL (jeśli trafi do payloadu wizyty) | **dane zdrowotne + krajowy identyfikator** | **tak** — bez niego nie ma zgłoszenia P1 | `:persist`, wymuszone przez P1 | „nie można odbyć wizyty bez PESEL-u" |
| `note` / ważna notatka pacjenta (`E-113`) | tekst pisany ręcznie o pacjencie | do wyświetlenia — tak | **`:hash` zabija funkcję; `:drop` zabija ekran** — patrz otwarte pytania | `E-113`, RBS 00:24:22 |

### Zależności zewnętrzne

| Zależność (fakt biznesowy) | Jak wygląda niedostępność, słowami klienta | Czy „brak odpowiedzi" = „odpowiedź nie"? | Dowód |
|---|---|---|---|
| Kanał wiadomości do pacjenta (SMS + e-mail) | numery zagraniczne „praktycznie nigdy nie dochodzą"; parser odpowiedzi wywraca się na interpunkcji — „Tak." nie jest rozpoznawane | **Zdecydowanie nie, i to jest sedno.** Brak odpowiedzi na prośbę o potwierdzenie **nie jest odwołaniem** — recepcja dzwoni do skutku, a wizyta się odbywa. Zlanie tych dwóch stanów jest dokładnie tym, czego `U-10` dotyczy | `X-05`, `H4`; `U-10` |

### Reguły i przykłady

| Reguła | Przykład, który zadziałał | Przykład, który poszedł źle | Dowód |
|---|---|---|---|
| Bezpłatne odwołanie do zamknięcia recepcji ostatniego dnia roboczego przed wizytą | „wizytę można bezpłatnie odwołać do środy do 17:00" — komunikat w potwierdzeniu | **wizyta o 20:00 odwołana o 16:00 tego samego dnia** jest dziś bezpłatna przy odczycie kalendarzowym — cztery godziny uprzedzenia, czyli dokładnie przypadek, dla którego opłata istnieje | `H16` zamknięte 2026-08-17 |
| Kara nie przywiera do wizyty umówionej **po** minięciu jej własnego terminu odwołania | pacjent umawia się w środę po południu na czwartek — nie miał okna, więc nie odpowiada | brak reguły czyni wrogim `S-13` (dzwonienie z listy rezerwowej na zwolniony termin) | `AGG-20` inv. 6, propozycja 2026-08-15 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Albo: nieweryfikowane |
|---|---|---|
| ~5 minut karencji przed telefonem o nieobecność | ESB L5 | liczba z tablicy, nie zmierzona |
| retry telefonu ~1h, plus jeszcze raz w dniu wizyty | W1 00:09:24 | — |
| ~100 wizyt dziennie na trzy lokalizacje | `AGG-01` § Throughput | **brak cytatu w przebiegu — traktować jako rząd wielkości** |
| horyzont grafiku ~2 miesiące | W1 00:04:41 | — |
| `visit_handed_over` istnieje | — | **nieweryfikowane: propozycja Appunite `DEC-18`, sprzeczna z tym, co mówili specjaliści** (`U-09`) |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| Czy `visit_handed_over` w ogóle powstanie, i jako blokada czy ostrzeżenie? | `stages`, `terminal`, cały `trace` #3 | `U-09`: nikt tego nie zamawiał, a fizjoterapeuta powiedział wprost, że status jest niepotrzebny |
| Wizyta dwuosobowa — jedna instancja czy dwie? | `instance`, payload | `H35` rozstrzygnięte co do biznesu, nie co do kardynalności |
| Czy „ważna notatka" może iść do logu zdarzeń w ogóle? | `retain` | PNS ma `:persist`/`:hash`/`:drop` i **żadnej kategorii „dane zdrowotne"** |

---

## 2. Dokumentacja kliniczna wizyty i zamknięcie kliniczne

**Wejście:** `20-aggregates.md` `AGG-02`, `10-event-model.md` §3.7
**Jakość dowodu:** **najlepsza w korpusie** — lane 7 walidowana pierwszoosobowo z fizjoterapeutami
2026-08-12; `E-41`, `E-42`, `E-44` oznaczone `observed`.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Zebrano wywiad pacjenta | `history_taken` | pierwszy zapis dokumentacji | `E-41`, **observed** |
| 2 | Powielono notatkę z poprzedniej wizyty | `previous_note_copied` | alternatywne wejście | `E-42`, **observed** |
| 3 | Wykonano zabieg | `treatment_performed` | rdzeń | `E-43`, dodane 2026-08-13 |
| 4 | Wybrano ICD-10 / ICD-9 | `diagnosis_coded` | ładunek P1 | `E-44`, **observed**, ~2 min na kod |
| 5 | Zapisano notatkę widoczną w recepcji | `reception_note_written` | przekracza granicę do recepcji | `E-49` |
| 6 | Zalecono termin kolejnej wizyty | `follow_up_recommended` | `C-24`, `S-111` | `E-46` |
| 7 | Zamknięto wizytę przez specjalistę | `visit_closed_clinically` | **wyzwala P-07 → P1** | `E-52` |

### Kształt payloadu

| Zdarzenie | Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|---|
| wszystkie | `visit_id` | — | `:id` | `AGG-02` tożsamość = visit id |
| `diagnosis_coded` | `icd10` | rozpoznanie — główna przyczyna i współistniejące | **`:string` z zastrzeżeniem**: to jest wartość ze słownika, czyli konceptualnie `:enum`, ale zbioru nie da się zadeklarować, a słownik jest ogromny („milion słowników, które trzeba mieć u siebie") | zweryfikowane 2026-08-13 wobec KIF i NFZ |
| `diagnosis_coded` | `icd9` | zrealizowana procedura (ICD-9 PL CM) | jak wyżej | jw. |
| `diagnosis_coded` | `icd9_supplement` | **dopisek wolnym tekstem, gdy nic nie pasuje** — „ten program nie przyszukuje fali uderzeniowej, więc wpisujemy zabiegi fizjoterapeutyczne i ja do góry dopisuję" | `:string` — i to jest tekst pisany przez człowieka o pacjencie | W2 00:46:28, `S-30` |
| `visit_closed_clinically` | `specialist_id` | kto zamknął; **tylko wykonujący może** | `:id` | `AGG-02` inv. 3, egzekwowane dziś |
| `history_taken` | treść wywiadu | — | `:string`, dane zdrowotne | `E-41` |

> **`:string` to „tekst, który wpisał człowiek" i jedyny typ, na który reaguje kontrola retencji** — pole
> `:string` bez `retain` trafia do logu dosłownie. Tutaj to oznacza wywiad medyczny i dopisek kliniczny
> w logu zdarzeń. **To jest decyzja do podjęcia świadomie, nie efekt uboczny.**

### Tożsamość

- `[:visit_id]` dla zamknięcia; dla `diagnosis_coded` — **niejasne**: czy poprawienie kodu to ten sam
  fakt, czy nowy? Korpus mówi tylko, że rozporządzenie przewiduje ścieżkę „dane uzyskane później
  przesyła się niezwłocznie", co sugeruje, że **korekta kodu jest nowym faktem**, nie nadpisaniem.
  Nie zgaduję klucza — do potwierdzenia.

### Instancja

- **Jeden przypadek:** dokumentacja jednej wizyty. Ta sama `visit_id` co proces 1 → patrz ustalenie 1.
- **Równolegle:** nie dla tej samej wizyty; **tak** dla specjalisty (16 wizyt niezamkniętych naraz).

### Powtarzalne zdarzenia w jednej instancji

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `diagnosis_coded` | prawdopodobnie tak (korekta) | niejasne — patrz Tożsamość | rozporządzenie, ścieżka „dane uzyskane później" |
| `visit_closed_clinically` | nie | — | `AGG-02` |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `ZamkniętaKlinicznie` | dobre | `AGG-02` |
| **Nigdy niezamknięta** | **złe i najczęstsze** — „ona ma 16 wizyt niezakończonych", a dla każdej zgłoszenie do P1 nigdy nie leci | W1 02:20:04; `AGG-02` inv. 2a |

⚠️ Ten drugi koniec **nie ma dziś zdarzenia** — jest brakiem zdarzenia. W kontrakcie musi mieć postać
`or_else` albo nie da się go policzyć.

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| ICD-10 **i** ICD-9 przed zamknięciem klinicznym — **tylko dla usług oflagowanych jako raportowane do P1** | zamknięcie kliniczne | `DEC-19`, **propozycja**, sprzeczna z ustaleniem sali z 2026-08-13 („przypominaj, nie blokuj") |
| Tylko wykonujący specjalista zamyka | zamknięcie | `AGG-02` inv. 3, **egzekwowane dziś** |

Model jest tu ostrożny i warto to przenieść: bramka jest darmowa **dopiero** dlatego, że `DEC-18`
przeniósł pieniądze poza to zamknięcie. Bez `DEC-18` blokuje pacjenta stojącego przy ladzie — i to jest
to, czego specjaliści odmówili: „to jest dla mnie nie do przejścia".

### Kandydaci na `trace`

| # | Po | W ciągu | Wtedy | Inaczej | Czy wiąże ścieżkę zapasową? | Komu obiecane | Dowód |
|---|---|---|---|---|---|---|---|
| 1 | `visit_completed` (pacjent wyszedł z gabinetu) | **`{24, :hour}`** | `visit_closed_clinically` | `documentation_overdue_task_created` | **niepowiedziane** | wewnętrznie, i pośrednio regulatorowi | **decyzja klienta 2026-08-13**: termin zamknięcia wizyty to 24 h, świadomie wewnątrz ustawowych 48 |
| 2 | `visit_booked` | do terminu wizyty | `documentation_task_created` | — | nie dotyczy | wewnętrznie | `P-23` — zadanie powstaje **przy rezerwacji**, nie po fakcie |

**`trace` #1 jest jedyną obietnicą w tym procesie z liczbą i z datą decyzji.** I ma pułapkę, którą
korpus już zdiagnozował: pierwotny watchdog klienta miał 48 h, czyli **dokładnie tyle co termin ustawowy**
— „powiadamia menedżera w momencie, w którym termin już minął. To jest sekcja zwłok, nie ostrzeżenie".
Dlatego 24 h, i dlatego eskalacja musi zapalić się **przed** 24 h, nie na 24 h.

### Kadencja

- **Zdarzeniowa.** Ale uwaga na rytm: etap 4 modelu („weryfikacja zaległości") dzieje się **wsadowo, per
  specjalista, później** — to jedyne miejsce w tej domenie, gdzie kadencja mogłaby mieć sens, i **nikt
  nie podał częstotliwości.**

### Retencja / dane wrażliwe

| Pole | Kategoria | Handler potrzebuje surowej? | Polityka | Dowód |
|---|---|---|---|---|
| `icd10`, `icd9` | **dane zdrowotne** | **tak** — idą do P1 | `:persist` wymuszony przez zależność zewnętrzną | ładunek P1 |
| `icd9_supplement` | dane zdrowotne, tekst wolny | tak, drukowany/wysyłany | `:persist`; `:hash` czyni go bezużytecznym | W2 00:46:28 |
| wywiad | dane zdrowotne | tak | — | `E-41` |

> **To jest najostrzejsze zderzenie tej destylacji z PNS.** `retain` ma trzy wartości i żadna nie mówi
> „to są dane medyczne, log ma inny reżim niż tabela". Jednocześnie retencja dokumentacji medycznej to
> ustawowe 20 lat (Radosław: „tam jest po 20 lat, czy ileś trzeba" — jego własna liczba, podana
> z widoczną niepewnością, nieweryfikowana). **Log zdarzeń z ICD staje się dokumentacją medyczną.**
> Nie rozstrzygam tego tutaj; nazywam, bo to nie jest szczegół implementacyjny.

### Zależności zewnętrzne

Żadnej w tym procesie — dokumentacja powstaje lokalnie. Zależność pojawia się dopiero przy wysyłce
(proces 3).

### Reguły i przykłady

| Reguła | Przykład, który zadziałał | Przykład, który poszedł źle | Dowód |
|---|---|---|---|
| Zamknięcie kliniczne wymaga obu kodów dla usług raportowanych | fizjoterapia, rehabilitacja — flaga domyślnie włączona (`DEC-20`) | **jazda konna, beauty, fitness nigdy nie są bramkowane** — flaga per usługa; cztery usługi graniczne (endermologia, masaż, komora, hipoterapia) wymagają potwierdzenia, nie domyślności | `H21` odpowiedziane 2026-08-17 |
| Zamknąć może tylko wykonujący | egzekwowane dziś | recepcja zamyka i wysyła do P1, gdy specjalista jeszcze nie skończył — „no to nie może tak być" | VLW, `AGG-02` inv. 3 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Albo: nieweryfikowane |
|---|---|---|
| ICD-10 = rozpoznanie, ICD-9 = procedura | zweryfikowane 2026-08-13 wobec KIF i NFZ | — |
| ~2 min na kod | ESB L7 | szacunek uczestnika |
| 16 wizyt niezamkniętych u jednej osoby | W1 02:20:04 | jednorazowa obserwacja, nie miara |
| termin zamknięcia = 24 h | decyzja klienta 2026-08-13 | — |
| „Rehmed zatrudnia ludzi do ręcznego audytu kompletności kodów" | W1 02:19:33 | — |
| **czy Medyk pozwala zamknąć bez kodów** | — | **nieweryfikowane, `H58`** — dowód pośredni, „minuta pracy" żeby sprawdzić |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| Czy korekta kodu to nowy fakt czy nadpisanie? | `identity` na `diagnosis_coded` | nikt nie opisał ścieżki korekty w systemie |
| Czy dokumentacja medyczna może żyć w logu zdarzeń przez 20 lat? | `retain`, cała architektura logu | PNS nie ma kategorii danych zdrowotnych |
| Czy `documentation_overdue_task_created` to zdarzenie procesu, czy zadanie z innego kontekstu? | `or_else` w `trace` #1 | `F-02` jest fundamentem współdzielonym; `trace` nie przekracza procesów |

---

## 3. Sprawozdawczość zdarzeń medycznych do P1

**Wejście:** `20-aggregates.md` `AGG-10`, `wiki/concepts/P1 Medical Event Reporting.md`,
`1-Discovery/01-processes.md` §995–999
**Jakość dowodu:** mechanika — stakeholder-stated i częściowo `observed` (`E-54`); **termin — zweryfikowany
wobec aktu prawnego**, jedyny taki w całym korpusie.

> **To jest proces, dla którego warto napisać kontrakt PNS w pierwszej kolejności.** Ma zewnętrznie
> narzucony termin z liczbą, ma ładunek o zdefiniowanych polach, ma zdefiniowaną awarię i ma stan,
> którego dziś **fizycznie nie da się zobaczyć** — czyli dokładnie klasę pytania, na którą silnik
> odpowiada: *czy wdrożony kod robi to, co mówi zadeklarowany proces.*

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Zamknięto wizytę przez specjalistę | `visit_closed_clinically` | **wyzwalacz**, dzielony z procesem 2 | `E-52`, `P-07` |
| 2 | Wysłano informację do systemu P1 | `p1_report_sent` | fakt spełnienia obowiązku | `E-54`, **observed** |
| 3 | — *(odrzucenie lub brak łączności)* | `p1_report_failed` | stan `Błąd` w `AGG-10`; **nie ma nazwy klienta** | `AGG-10`, `S-46` |
| 4 | — *(minęły 2 dni ustawowe)* | `p1_report_overdue` | stan `Przeterminowane`; **nie ma nazwy klienta i nie da się go dziś zobaczyć** | `AGG-10` |

⚠️ **Zdarzenia 3 i 4 nie pochodzą ze słów klienta — są odczytane ze stanów, które model narysował.**
Zgodnie z regułą repo nazywam to wprost zamiast udawać cytat. Bez nich `or_else` nie ma czym być.

### Kształt payloadu

Ładunek jednego „zdarzenia medycznego", z wiki (`P1 Medical Event Reporting`, potwierdzone wobec KIF):

| Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|
| `visit_id` | nasza tożsamość zgłoszenia | `:id` | `AGG-10` |
| `facility_id` + miejsce/region świadczenia | identyfikator podmiotu | `:id` | wiki P1 |
| `patient_pesel` | PESEL pacjenta | **`:id` co do kształtu; krajowy identyfikator co do wrażliwości** | „dane pacjenta to jest PESEL, dlatego musi być zbierane" |
| `occurred_at` | data i godzina | `:timestamp` | wiki P1 |
| `event_type`, `event_mode` | rodzaj i tryb zdarzenia | `:enum` (zbiór niedeklarowalny; kod usługi **6 „Wizyta"** dla praktyki prywatnej) | KIF |
| `icd10`, `icd9` | rozpoznanie i procedura | `:string` z zastrzeżeniem jak w procesie 2 | KIF/NFZ |
| `practitioner_number` | numer prawa wykonywania zawodu; kod grupy zawodowej fizjoterapeuty = **6** | `:id` | KIF |

### Tożsamość

- **`[:visit_id]`** — jedno zdarzenie medyczne na wizytę. Ale patrz niżej `H64`: jeśli P1 potwierdza
  pojedyncze zdarzenie odróżnialnie od sukcesu transportu, to ponowienie po błędzie **nie jest nowym
  faktem** i klucz jest poprawny; jeśli nie, to nie wiadomo, co znaczy „wysłane".
- **Dowód:** `AGG-10`; `H64` podniesione 2026-08-18, **otwarte**.

### Instancja

- **Jeden przypadek:** jedno zgłoszenie dla jednej wizyty.
- **Ta sama `visit_id` co procesy 1 i 2** → patrz ustalenie 1. `trace` „wykonano wizytę → zgłoszono do
  P1" **nie skompiluje się**, jeśli to będą dwa procesy.

### Powtarzalne zdarzenia w jednej instancji

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `p1_report_failed` | **tak** — kolejka ponowień | moment próby; **nikt nie podał liczby ani odstępu ponowień** | `S-46` |
| `p1_report_sent` | zależy od `H64` | — | `H64` |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `Wysłane` | dobre | `AGG-10` |
| `Przeterminowane` — minęły 2 dni | **złe, ustawowe naruszenie, i dziś niewidoczne** | `AGG-10`: „stan, którego dziś nie da się zobaczyć — nic nie pilnuje terminu" |

**Świadomie nie ma stanu `Niekompletne`** — `DEC-19` czyni ładunek poprawnym z konstrukcji. To jest cały
argument za bramką na `C-29`, wyrażony jako brakujący stan.

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| Zamknięcie **specjalisty**, nigdy recepcji | wysyłkę | VLW: „jeśli zamknie recepcja i wyśle na [P]1, a tamten jeszcze nie zakończył? No to nie może tak być" |
| Flaga „usługa raportowana" na katalogu | całą instancję — proces nie powstaje dla masażu, beauty, fitnessu, stajni | `H21`, `DEC-20` |
| Certyfikat placówki załadowany i ważny | wysyłkę w ogóle | „certyfikaty wgrane są w system i na podstawie tych certyfikatów są raportowane te wizyty" |

### Kandydaci na `trace` — **rdzeń całej destylacji**

| # | Po | W ciągu | Wtedy | Inaczej | Czy wiąże ścieżkę zapasową? | Komu obiecane | Dowód |
|---|---|---|---|---|---|---|---|
| **1** | **`visit_completed`** — zakończenie świadczenia ambulatoryjnego | **`{2, :day}`** | `p1_report_sent` | `p1_report_overdue` | **musi** — inaczej zgłoszenie spóźnione o trzy miesiące liczy się jako spełnione | **regulatorowi**, ustawowo | **Dz.U. 2025 poz. 866**; obowiązek od 2021-07-01 |
| 2 | `visit_closed_clinically` | `{2, :day}` | `p1_report_sent` | `p1_report_overdue` | jw. | jw. | `P-07` — dyspozycja leci na zamknięciu |

> ⚠️ **Te dwa nie są wariantami tego samego. Różnią się kotwicą i tylko jeden jest zgodny z prawem.**
>
> Rozporządzenie liczy 2 dni **od zakończenia świadczenia** (dla świadczenia trwającego kilka dni — od
> jego rozpoczęcia). Nie od zamknięcia dokumentacji. Tymczasem dyspozycja do P1 leci na zamknięciu
> klinicznym (`P-07`), a zamknięcie kliniczne bywa odroczone o dni — „16 wizyt niezakończonych".
>
> **Konsekwencja jest brutalna i warto ją postawić wprost:** kontrakt zakotwiczony na `#2` będzie
> raportował zieleń, podczas gdy Rehmed łamie termin. Asercja mierzyłaby wtedy sprawność wysyłki,
> a nie zgodność — i byłaby dokładnie tym rodzajem fałszywej metryki, przed którym broni `unverified`
> w `PNS.Process`.
>
> **Zalecenie: `#1`.** `#2` można dodać obok jako miarę wewnętrzną, ale nie zamiast.

### Kadencja

- **Zdarzeniowa.** Uwaga na fałszywy trop: specjaliści opisywali wysyłkę do P1 jako „cykl 24-godzinny" —
  to **nie jest** termin ustawowy, tylko prawdopodobnie wsadowy harmonogram Medyka. Detal implementacyjny
  dostawcy, nie kadencja procesu. Warto potwierdzić, bo jeśli nowy system wysyła od razu, część dzisiejszej
  zawodności znika sama.

### Retencja / dane wrażliwe

| Pole | Kategoria | Handler potrzebuje surowej? | Polityka | Dowód |
|---|---|---|---|---|
| `patient_pesel` | krajowy identyfikator + kontekst zdrowotny | **tak, bezwzględnie** — bez PESEL-u nie ma czego wysłać | `:persist`. **`:hash` jest tu niemożliwy** | „nie wiecie, jak wysłać" |
| `icd10` / `icd9` | dane zdrowotne | tak | `:persist` | ładunek |
| `practitioner_number` | dane osobowe pracownika | tak | `:persist` | KIF |

**To jest proces, w którym cały ładunek musi być trzymany w postaci surowej.** Żadne pole nie jest
kandydatem na `:hash` ani `:drop`. Jeśli PNS ma tu cokolwiek obiecywać, to na poziomie dostępu i okresu
przechowywania, a nie `retain`.

### Zależności zewnętrzne

| Zależność | Jak wygląda niedostępność, słowami klienta | „Brak odpowiedzi" = „odpowiedź nie"? | Dowód |
|---|---|---|---|
| **Krajowy rejestr zdarzeń medycznych** (P1 / e-Zdrowie) | „cały czas źle funkcjonuje", konkretnie dla kodów fizjoterapeutycznych; do tego certyfikat/klucz, który trzeba mieć wgrany i aktualny | **Nie wiadomo, i to jest `H64`.** Jeśli P1 nie zwraca odróżnialnego potwierdzenia pojedynczego zdarzenia, to sukces transportu jest jedynym sygnałem — a wtedy „wysłane" nie znaczy „przyjęte" | `X-01`; `H64`; „58 dni deweloperskich siedzi na tym kontekście" |

`unavailable_looks_like`, do napisania zdaniem po polsku: *odrzucenie zgłoszenia albo brak łączności
z krajowym rejestrem; certyfikat wygasł albo nie został wgrany.*

**I tu wraca ustalenie 3.** Rozporządzenie przewiduje własną semantykę awarii: **3 dni od usunięcia
awarii**. PNS na `depends_on` + obserwację niedostępności daje werdykt `:suspended` — czyli „nie
oceniamy tego przebiegu". **To nie jest to samo co „okno przesuwa się o 3 dni od naprawy".** Różnica
jest realna: przebieg zawieszony znika z licznika, przebieg z przedłużonym oknem nadal może go naruszyć.
Zalecenie: użyć `:suspended` i **powiedzieć w raporcie, że to przybliżenie** — albo podnieść to jako
brakującą zdolność silnika, ale nie udawać, że pasuje idealnie.

### Reguły i przykłady

| Reguła | Przykład, który zadziałał | Przykład, który poszedł źle | Dowód |
|---|---|---|---|
| Raportowane są świadczenia zdrowotne udzielane w ramach rejestracji podmiotu leczniczego | fizjoterapia — Rehmed jest podmiotem leczniczym dla tej linii | **masaż nie podlega** — „jak byśmy robili kamienicę od masażu, to nie musimy tego robić… to nie są wszystkie procedury medyczne" | wiki P1, cytat wprost |
| Termin: 2 dni od zakończenia świadczenia | — | **watchdog klienta na 48 h zapala się dokładnie w chwili, gdy termin minął** — „to jest sekcja zwłok, nie ostrzeżenie". Stąd decyzja o 24 h | `01-processes.md` §999 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Albo: nieweryfikowane |
|---|---|---|
| 2 dni, od zakończenia świadczenia; 3 dni od usunięcia awarii | **Dz.U. 2025 poz. 866**, tekst jednolity | zweryfikowane 2026-08-13 — jedyna taka pozycja w korpusie |
| pola ładunku | wiki P1 + KIF | — |
| kod grupy zawodowej fizjoterapeuty = 6, kod usługi 6 „Wizyta" | KIF | — |
| „cykl 24-godzinny" wysyłki | specjaliści | **nieweryfikowane** — prawdopodobnie harmonogram Medyka |
| czy P1 potwierdza pojedyncze zdarzenie | — | **nieweryfikowane, `H64`** — odpowiedź jest w dokumentacji integracji, nie na warsztacie |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| **Od czego liczą się 2 dni: od wyjścia pacjenta czy od zamknięcia klinicznego?** | `from` w `trace` #1 — czyli wszystko | akt prawny mówi „od zakończenia świadczenia"; system dziś wyzwala na zamknięciu. **Do rozstrzygnięcia z prawnikiem lub z dokumentacją P1, nie na warsztacie** |
| Czy `Wysłane` dzieli się na `Wysłane` i `Potwierdzone`? | `eventually`, definicja „gotowe" w kolejce ponowień | `H64` |
| Ile ponowień, w jakich odstępach? | `identity` na `p1_report_failed` | nikt nie podał |

---

## 4. Rozliczenie wizyty

**Wejście:** `20-aggregates.md` `AGG-03`, `10-event-model.md` §3.8
**Jakość dowodu:** stakeholder-stated; dwa potwierdzone defekty.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Dodano dodatkową usługę do rozliczenia | `service_line_added` | zmienia cenę **i** czas trwania; jedyny zapis specjalisty, którego nie wolno odroczyć | `E-45`, W2 00:51:18 |
| 2 | Pacjent opłacił wizytę | `payment_recorded` | K / G / przelew / bon; split dozwolony i **wadliwy** | `E-55` |
| 3 | Podzielono rachunek między płatników | `bill_split` | część na płatnika przelewem, część prywatnie | `E-106`, RBS 00:45:53 |
| 4 | Recepcja zamknęła wizytę | `visit_closed_commercially` | terminal | `E-56` |
| 5 | Powiadomiono o zakończeniu wizyty bez płatności | `unpaid_visit_flagged` | `P-08` | `E-57` |
| 6 | Zaksięgowano korektę po zamknięciu dnia | `settlement_corrected` | `C-46` | `E-84` |

### Kształt payloadu

| Zdarzenie | Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|---|
| wszystkie | `visit_id` | — | `:id` | `AGG-03` |
| `service_line_added` | `service_id`, `amount` | **kwota** | **NIE MIEŚCI SIĘ** — brak typu pieniężnego w zamkniętym zbiorze | `E-45` |
| `payment_recorded` | `method` | gotówka / karta / przelew / bon | `:enum` | `E-55` |
| `payment_recorded` | `amount` | kwota linii | **NIE MIEŚCI SIĘ** | `AGG-03` inv. 1 |
| `bill_split` | `payer_id` per linia | każda linia nazywa swojego płatnika i swój kanał rozliczenia | `:id` | `DEC-05` |

> **To jest miejsce, w którym zamknięty zbiór typów PNS realnie uwiera.** `AGG-03` inv. 1 brzmi *linie
> płatności sumują się do całości* — i to jest niezmiennik o pieniądzach. Do wyboru: grosze jako
> `:integer` (działa, ale typ przestaje mówić prawdę o jednostce), albo `:string` (traci arytmetykę).
> **Nie proponuję dokładać `:money` do DSL** — to jest dokładnie ten ruch, którym `:period` wszedł
> i po dwóch dniach wyszedł. Zapisuję jako znalezisko dla kogoś, kto podejmie decyzję świadomie.

### Tożsamość

- `[:visit_id]` dla zamknięcia; **`payment_recorded` powtarza się** przy splicie → klucz musi zawierać
  coś, co odróżnia linię (`method` + `amount`? kolejność?). **Nie zgaduję** — to jest dokładnie ten
  kształt dziury, który w TaxVision zamknęło włożenie `diff` do `identity`.

### Instancja

- **Jeden przypadek:** rozliczenie jednej wizyty. Znowu `visit_id`.
- **Równolegle:** etapy 2 i 3 modelu **nakładają się** — recepcja rozlicza przy ladzie, gdy specjalista
  jeszcze pisze. To jest cały argument za `DEC-01` i jednocześnie argument za tym, żeby w PNS był to
  **jeden proces ze stages**, nie dwa procesy (ustalenie 1).

### Powtarzalne zdarzenia w jednej instancji

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `service_line_added` | **tak** | usługa i moment | `E-45` |
| `payment_recorded` | **tak** — split | metoda i kwota; **niedookreślone** | `E-55`, „split allowed but buggy" |
| `settlement_corrected` | tak | — | `E-84` |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `Zamknięte` po opłaceniu | dobre | `AGG-03` |
| `BezPłatności` → `Zamknięte` | złe, ale dozwolone | `C-30`, `P-08` |
| `Skorygowane` → `Zamknięte` | neutralne | `C-46` |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| `visit_handed_over` przed rozliczeniem | całe wejście do procesu | `DEC-18` — **i `U-09` mówi, że jeśli to ma być tylko ostrzeżenie, rozliczenie musi otwierać się wcześniej, np. z rozpoczęciem zabiegu** |

### Kandydaci na `trace`

| # | Po | W ciągu | Wtedy | Inaczej | Wiąże zapasową? | Komu | Dowód |
|---|---|---|---|---|---|---|---|
| 1 | `visit_handed_over` | **niepowiedziane** | `payment_recorded` | `unpaid_visit_flagged` | niepowiedziane | wewnętrznie | `P-08` istnieje, terminu nie ma |
| 2 | `service_line_added` | **żadne — „od razu, zanim dojdzie osoba"** | widoczne w recepcji | — | — | recepcji | `P-26`, `DEC-17`, W1 02:36:39 |

⚠️ **`trace` #2 jest pułapką i nie należy go pisać.** Klient poprosił o **moment**, nie o interwał —
„Od razu, zanim dojdzie osoba". `DEC-17` odpowiada na to pushem po socketach, przy którym **nie ma okna
do zabudżetowania**. Zapisanie tego jako `within: {30, :second}` byłoby wymyśleniem liczby, której nikt
nie powiedział, i zamieniłoby gwarancję transportu w asercję o opóźnieniu. Zostawić poza kontraktem.

### Kadencja

- **Zdarzeniowa.**

### Retencja / dane wrażliwe

| Pole | Kategoria | Surowa? | Polityka | Dowód |
|---|---|---|---|---|
| kwoty | niewrażliwe | tak | `:persist` | — |
| `method` | niewrażliwe | tak | `:persist` | — |
| `payer_id` | dane o płatniku pacjenta → **pośrednio o pacjencie** | tak | `:persist` | `DEC-05` |

### Zależności zewnętrzne

| Zależność | Niedostępność słowami klienta | „Brak odpowiedzi" = „nie"? | Dowód |
|---|---|---|---|
| **Kasa fiskalna** (drukarka paragonu) | brak integracji w ogóle — „przeklepywane ręcznie na urządzeniu" | nie dotyczy | `X-06`; **odrzucone 2026-08-18 mimo 6 dni w umowie** |
| **Bramka płatności / przedpłata** | — | — | `X-07`; **odrzucone**, a to ona czyniła karę ściągalną |

**Obie są `scope: out` i obie zostawiają koszt.** Do kontraktu nie wchodzą; zapisane, żeby nie wróciły
jako „przeoczenie".

### Reguły i przykłady

| Reguła | Przykład, który zadziałał | Przykład, który poszedł źle | Dowód |
|---|---|---|---|
| Linie płatności sumują się do całości | — | **split odwraca znak** — „dzienny raport jest błędny dokładnie w te dni, kiedy to ma znaczenie" | W1 02:02:07 |
| Rozliczenie z karnetu to konsumpcja salda, nie przychód | — | **liczone dwa razy** — „Ja w systemie widzę dwa tysiące"; widok dzienny zawyżony, miesiąc się zgadza | `P-27`, uzgodnione 2026-08-13 |
| Rozliczenie może nieść kilka linii płatnika | pakiet LuxMed pokrywa usługę za **300 zł**, specjalista dodaje drugą w trakcie, recepcja dzieli: część przelewem na płatnika, część kartą prywatnie | dziś recepcja rozbija to na **dwie rezerwacje**, przez co pacjent dostaje **dwa SMS-y potwierdzające** na jedną wizytę | `E-106` RBS 00:45:53; W1 02:09:54 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Nieweryfikowane |
|---|---|---|
| split odwraca znak | W1 02:02:07 | — |
| podwójne księgowanie karnetu | „Ja w systemie widzę dwa tysiące" | — |
| 300 zł jako wartość usługi płatnikowej | RBS 00:45:53 | pojedynczy przykład, nie cennik |
| „jeden płatnik na wizytę" | W1 02:03:55 | **to ograniczenie Medyka, nie reguła biznesowa — `DEC-05` mówi, żeby go NIE przenosić** |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| Jak reprezentować kwoty? | payload każdego zdarzenia pieniężnego | zamknięty zbiór typów nie ma pieniędzy |
| Co odróżnia drugą linię płatności od pierwszej? | `identity` | nikt nie opisał splitu na poziomie danych |
| `C-30` znaczy dwie różne rzeczy („zamknij bez płatności" i „zamknij komercyjnie") | nazwy zdarzeń | model sam to zauważa i zostawia nierozstrzygnięte |

---

## 5. Rozliczenie płatnika zewnętrznego

**Wejście:** `20-aggregates.md` `AGG-11`, `10-event-model.md` §3.12
**Jakość dowodu:** **najcieńszy z procesów, które warto kontraktować** — sześć zdarzeń na przepływ, który
decyduje o tym, czy płatnik nam zapłaci, a główne źródło to rozmowa z niepotwierdzonym mapowaniem mówców.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Zarejestrowano wizytę w systemie płatnika | `visit_registered_with_payer` | **przed udzieleniem świadczenia** | `E-85`, ręcznie (`H9`) |
| 2 | Oznaczono wizytę jako rozliczoną u płatnika | `visit_marked_settled_with_payer` | **kliknięcie nośne — bez niego płatnik po prostu nie płaci** | `E-86` |
| 3 | Wystawiono fakturę miesięczną dla płatnika | `payer_invoice_issued` | comiesięczny moduł, uruchamiany przez managera | `E-87`, `C-49` → `A-05` |
| 4 | Zmapowano nazwę usługi płatnika na własną | `payer_service_aliased` | „terapia miorelaksacyjna" = „terapia manualna" | `E-88` |

### Kształt payloadu

| Zdarzenie | Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|---|
| 1, 2 | `visit_id`, `payer_id` | — | `:id` | `AGG-11` |
| 3 | `period` | miesiąc rozliczeniowy | **`:id`** — i to jest właściwa odpowiedź, nie nowy typ; `:period` był w DSL przez dwa dni i wyleciał | `docs/contract.md` § Payload types |
| 3 | `invoice_id` | **`DEC-16`: wizyta niesie referencję do faktury, która ją rozliczyła** — „nierozliczona" to brak tej referencji | `:id` | `DEC-16` |
| 3 | `amount` | kwota faktury | **nie mieści się** | — |

### Tożsamość

- 1 i 2: `[:visit_id, :payer_id]`.
- 3: `[:payer_id, :period]`.
- **Dowód:** `AGG-11`; `DEC-16`.

### Instancja

- **Jeden przypadek:** **miesiąc rozliczeniowy jednego płatnika** — `instance: [:payer_id, :period]`.
- ⚠️ **To jest inna instancja niż wizyta**, więc to **musi** być osobny `process` od wizyty — i wtedy
  `trace` „wizyta wykonana → ujęta w fakturze" **nie skompiluje się**, bo przekracza procesy.
  To jest dokładnie ta sama pułapka co w ustaleniu 1, tylko tu wychodzi w drugą stronę: **nie da się
  scalić**, bo klucze są różne. Do rozwiązania po stronie modelu domeny, nie DSL.
- **Równolegle:** tak — trzej płatnicy, każdy swój miesiąc.

### Powtarzalne zdarzenia w jednej instancji

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `visit_registered_with_payer` | tak — raz na wizytę w miesiącu | `visit_id` | `AGG-11` |
| `payer_invoice_issued` | **nie powinno**; korekty niezamodelowane | — | luka |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| Faktura wystawiona i wszystkie wizyty ujęte | dobre | `AGG-11` inv. 4 |
| **Wizyta wykonana i nieujęta** | **złe — utracony przychód** | „jeśli czegoś nie uwzględni to będziemy stratni" |
| **Wizyta zafakturowana, nigdy niepotwierdzona jako rozliczona u płatnika** | **złe — nie zapłacą albo spór** | „jeśli wyliczy za dużo to będzie problem z LuxMed" |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| Rejestracja w systemie płatnika **przed** udzieleniem świadczenia | wykonanie wizyty płatnikowej | `AGG-11` inv. 1 |
| PESEL przy zapisie na płatnika | rezerwację | tablica: „[LuxMed, Enelmed, TuZdrowie] Pacjent musi podać PESEL przy zapisie" |
| Konsultacja płatnikowa jako **obowiązkowa brama bez terapii**, zastępująca skierowanie | wejście na terapię | W2 01:03:55–01:04:57 |

### Kandydaci na `trace`

| # | Po | W ciągu | Wtedy | Inaczej | Wiąże zapasową? | Komu | Dowód |
|---|---|---|---|---|---|---|---|
| 1 | `visit_completed` (płatnikowa) | **`{1, :month}`** → **NIE SKOMPILUJE SIĘ** | `visit_marked_settled_with_payer` | — | — | płatnikowi, i sobie | `AGG-11` inv. 2 |
| 2 | `visit_marked_settled_with_payer` | koniec okresu rozliczeniowego | `payer_invoice_issued` **albo** wykluczenie z podanym powodem | — | — | płatnikowi | `AGG-11` inv. 4 |

> **Oba są kalendarzowe i żaden nie przejdzie przez `PNS.Duration`.** Miesiąc nie ma stałej długości —
> gate odmawia kompilacji i ma rację. Obejście jest to samo co w ustaleniu 2: **zmaterializować koniec
> okresu jako zdarzenie** (`settlement_period_closed`) i liczyć `within` od niego, albo przyjąć
> `{30, :day}` i **powiedzieć wprost, że to nie jest miesiąc.**
>
> Druga trudność jest głębsza: obietnica brzmi *„każda wykonana wizyta płatnikowa jest albo ujęta
> w fakturze okresu, albo wykluczona z podanym powodem"*. To nie jest „po zdarzeniu A następuje B" —
> to jest **kwantyfikator po zbiorze**, a `trace` mówi o pojedynczym przebiegu. Jeśli instancją jest
> `[:payer_id, :period]`, to `from` musiałoby padać raz na wizytę wewnątrz przebiegu miesiąca —
> co działa **tylko** jeśli wizyty są zdarzeniami tego procesu, a nie tamtego. **To jest realna
> decyzja modelowa i nie wolno jej podjąć przypadkiem.**

### Kadencja

- **Miesięczna** — `cadence: {1, :month}` jest legalne (kadencja nie liczy kalendarza, patrz
  `PNS.Duration` moduledoc).
- ⚠️ Ale: kadencję czyta dziś **tylko raport, dla samej deklaracji**. Monitor „nigdy nieobserwowany"
  został **odrzucony 6 sierpnia**, nie odłożony. Więc deklaracja `cadence` tu **nic nie pilnuje** —
  i trzeba to powiedzieć, zamiast sprzedawać jako mechanizm.
- **Dowód:** miesięczny moduł, manager otwiera, weryfikuje dane, wystawia. Bez automatyzacji.

### Retencja / dane wrażliwe

| Pole | Kategoria | Surowa? | Polityka | Dowód |
|---|---|---|---|---|
| `patient_pesel` przy rejestracji u płatnika | krajowy identyfikator | tak — „sprawdzamy po PESEL-u w systemie Luxmedowym" | `:persist` | tablica |
| `payer_id`, `period` | niewrażliwe | tak | `:persist` | — |

### Zależności zewnętrzne

| Zależność | Niedostępność słowami klienta | „Brak odpowiedzi" = „nie"? | Dowód |
|---|---|---|---|
| **System płatnika zewnętrznego** (trzy instancje jednego typu: LuxMed, Enelmed, TuZdrowie) | **nie ma API** — „ręczne przepisanie do panelu płatnika". Niedostępność to człowiek, który nie kliknął | **Nie.** Brak oznaczenia „rozliczone" nie znaczy, że płatnik odmówił — znaczy, że nikt nie kliknął, a skutek jest ten sam: nie płacą | `X-02`–`X-04`, `F-05` |

`unavailable_looks_like`: *panel płatnika niedostępny albo wizyta nie została w nim odnotowana przez
człowieka.* **Zastrzeżenie: to jest zależność, której niedostępność nie jest obserwowalna maszynowo** —
więc `depends_on` nie da tu `:suspended` z niczego. Deklaracja byłaby ozdobą i lepiej ją pominąć niż
udawać.

### Reguły i przykłady

| Reguła | Zadziałało | Poszło źle | Dowód |
|---|---|---|---|
| Nazwa usługi płatnika mapuje się na dokładnie jedną własną | „terapia miorelaksacyjna" → „terapia manualna" | bez aliasu **sumy się nie zgadzają** i `R-08` kłamie | `E-88` |
| Plan terapii jest nasz; **uprawnienie pacjenta u płatnika nie jest** | specjalista wpisuje „terapia miorelaksacyjna 5 razy, 2 razy w tygodniu" i recepcja to widzi | „10 łącznie można dobrać" to **rozmiar planu, nie saldo** — pacjent mógł zużyć sesje gdzie indziej. **Żaden ekran nie może pokazywać pozostałego limitu** | `H48` zamknięte 2026-08-17 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Nieweryfikowane |
|---|---|---|
| Enelmed i TuZdrowie działają identycznie jak LuxMed | potwierdzone 2026-08-14 | — |
| kliknięcie „rozliczone" jest nośne | `E-86` | — |
| konsultacja płatnikowa 20–30 min, bez terapii | W2 01:03:55 | — |
| **czy po wizycie jest jeszcze kliknięcie w panelu płatnika** | — | **nieweryfikowane, `H47` otwarte** — nie zmienia projektu, zmienia to, co system ma śledzić |
| **obowiązek przyjęcia pacjenta LuxMed w 7 dni przy kolejce 2 miesięcy** | RBS 00:45:00 | **`H38` otwarte** — to jest potencjalnie najostrzejszy `trace` w całej domenie i **nikt nie potwierdził, że taki obowiązek istnieje** |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| **Czy obowiązek „7 dni" jest realny?** | osobny, bardzo mocny `trace` | `H38`, otwarte; odpowiada Radosław |
| Czy wizyty są zdarzeniami procesu miesięcznego, czy procesu wizyty? | `instance`, i czy `trace` #2 w ogóle istnieje | decyzja modelowa nikogo nie zapytana |
| Co znaczy „koniec okresu rozliczeniowego" jako fakt? | `from` w `trace` #2 | miesiąc nie jest jednostką `within` |

---

## 6. Opłata karna za nieodwołaną wizytę

**Wejście:** `20-aggregates.md` `AGG-20`, `10-event-model.md` `E-111`/`E-112`
**Jakość dowodu:** mieszana — praktyka 50% jest `as-is`, cały cykl życia obligacji jest **propozycją
Appunite z 2026-08-15**, a metryka pochodzi z pisemnego wymagania klienta.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Naliczono karę | `penalty_charged` | powstaje przy nieobecności/spóźnionym odwołaniu | `E-111`, REQ LISTA 1 §8 |
| 2 | Pobrano karę | `penalty_collected` | **osobna liczba, o którą klient prosi na piśmie** | `E-112` |
| 3 | — *(umorzenie z powodem)* | `penalty_waived` | wyjątek chorobowy | `C-67`; **stan bez nazwy klienta** |

### Kształt payloadu

| Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|
| `penalty_id` | tożsamość obligacji | `:id` | `AGG-20` |
| `patient_id` | komu | `:id` | — |
| `origin_visit_id` | **z której wizyty powstała** | `:id` | krok 2 mechanizmu |
| `settled_visit_id` | **na której wizycie została pobrana** — inna niż powyżej | `:id` | krok 5 mechanizmu |
| `amount` | 50% wartości wizyty, **zamrożone w dniu nieobecności** | **nie mieści się** | „snapshot the price at the no-show" |
| `waiver_reason` | powód umorzenia, wpisany ręcznie | `:string` | inv. 4 |

### Tożsamość

- `[:penalty_id]`. **Nie `[:origin_visit_id]`** — bo obligacja żyje dłużej niż wizyta, która ją zrodziła.
- **Dowód:** `DEC-15`, `AGG-20`.

### Instancja

- **Jeden przypadek:** jedna obligacja, od naliczenia do pobrania / umorzenia / przedawnienia.
- ⚠️ **To jest jedyny proces w tej domenie, który przecina dwie wizyty.** Rodzi się na wizycie A,
  jest ujawniany przy rezerwacji wizyty B i pobierany przy rozliczeniu wizyty B. **`instance` nie może
  być `visit_id` w żadnej z dwóch ról.**
- **Równolegle:** niepowiedziane — czy pacjent może mieć dwie nieściągnięte kary naraz? Model tego
  nie rozstrzyga.

### Powtarzalne zdarzenia

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `penalty_charged` | raz na obligację; **wiele obligacji na pacjenta** | `penalty_id` | — |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `Pobrana` | dobre | `C-65` |
| `Umorzona` z powodem | neutralne | `C-67` |
| **`Przedawniona` — pacjent nie wraca** | **złe i niepoliczalne dziś** | `AGG-20` |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| **Kara nie przywiera do wizyty umówionej po minięciu jej własnego terminu odwołania** | naliczenie | inv. 6, propozycja 2026-08-15 |
| Ujawnienie przy rezerwacji kolejnej wizyty | nic — to odczyt, nie zmiana stanu | inv. 5; „przy następnej rejestracji musimy sprawdzać poprzednie rejestracje i poinformować o dodatkowym koszcie" |

### Kandydaci na `trace`

**Żadnego — i to jest fakt o domenie, nie werdykt o procesie.**

Nikt nigdy nie powiedział, w jakim czasie kara ma zostać pobrana. `Przedawniona` znaczy „pacjent nie
wraca" — nie ma terminu, jest brak zdarzenia bez końca. Wpisanie tu jakiegokolwiek `within` byłoby
wymyśleniem liczby.

**Strukturalnie natomiast jest to jeden z ciekawszych procesów w całym zestawie**, i pierwsza wersja
tej sekcji odrzuciła go niesłusznie. Ma trzy stany końcowe, z czego jeden — `Przedawniona` — jest
**dziś niepoliczalny**, a klient prosi o tę liczbę na piśmie (`REQ LISTA 1 §8`: osobno naliczone,
osobno skutecznie pobrane). To jest podręcznikowe *zadeklarowana ścieżka, nigdy nieprzejechana*:
`penalty_collected` istnieje w modelu i nie istnieje w rzeczywistości, bo mechanizm, który czynił ją
osiągalną — kaucja — jest poza zakresem. Overlay pokazałby to bez jednej liczby, i pokazałby
**dokładnie tę metrykę, o którą klient prosił**.

### Kadencja

- **Zdarzeniowa.**

### Retencja / dane wrażliwe

| Pole | Kategoria | Surowa? | Polityka | Dowód |
|---|---|---|---|---|
| `waiver_reason` | **powód chorobowy = dane zdrowotne wpisane ręcznie** | do wyświetlenia recepcji — tak | **konflikt: `:string` bez `retain` idzie do logu dosłownie** | inv. 4, RCP 00:07:11 |

### Zależności zewnętrzne

| Zależność | Niedostępność | „Brak" = „nie"? | Dowód |
|---|---|---|---|
| **Przedpłata / kaucja** | **nie istnieje — odrzucona ze scope'u** | — | `X-07`; **i to jest sedno trudności tego procesu**: kaucja jest mechanizmem, który czyni karę ściągalną, a bez niej `S-105` mierzy coś, czego projekt nie może poprawić |

### Reguły i przykłady

| Reguła | Zadziałało | Poszło źle | Dowód |
|---|---|---|---|
| Kara = 50% wartości wizyty | — | wartość **musi być zamrożona w dniu nieobecności**, bo inaczej zmienia się z cennikiem, zanim pacjent wróci | ESB L4; adjustacja 2026-08-15 |
| Nieopłacona kara blokuje kolejną rezerwację | „musisz zapłacić od razu **200 zł**, a nie **150**" — realne liczby | dziś recepcja sprawdza z pamięci, **a Medyk kiedyś miał takie ostrzeżenie i je usunięto — nikt nie powiedział dlaczego** | VLW 00:19:58; `H56` otwarte |
| Późne odwołanie ≠ nieobecność | — | klient prosi o **osobne liczniki** odwołań, przełożeń i nieobecności; zlanie ich w „nie przyszedł" psuje raport | REQ §8 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Nieweryfikowane |
|---|---|---|
| 50% | ESB L4 | praktyka, nie regulamin |
| 200 zł zamiast 150 zł | VLW 00:19:58 | jeden przykład |
| trzy nieobecności → czarna lista | ESB L5, tablica | **`U-13` otwarte: model zgubił konsekwencję, która jest w dwóch niezależnych źródłach**, i mówi dodatkowo, że czarna lista powinna być **wartością wyliczaną** (trzy nieobecności **i** co najmniej jedna nieopłacona kara), a nie stanem z ręcznym wyjściem |
| cały cykl życia obligacji | — | **nieweryfikowane: propozycja Appunite 2026-08-15** |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| Czy pacjent może mieć dwie otwarte kary? | `instance`, `identity` | niepowiedziane |
| Kiedy kara się przedawnia? | jakikolwiek `trace` | nikt nie podał terminu |
| Czy czarna lista jest stanem czy wyliczeniem? | `terminal` na procesie pacjenta | `U-13`, otwarte |

---

## 7. Zaświadczenie

**Wejście:** `20-aggregates.md` `AGG-12`, `10-event-model.md` §3.9
**Jakość dowodu:** stakeholder-stated; rejestr wydań ma **podstawę prawną**, nie preferencję.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dlaczego tutaj | Dowód |
|---|---|---|---|---|
| 1 | Klient zawnioskował o zaświadczenie | `certificate_requested` | start | `E-62` |
| 2 | Dodano zadanie o wydanie zaświadczenia | `certificate_task_created` | `P-12` | `E-63` |
| 3 | Ustalono termin wymagany przez pacjenta | `certificate_due_date_agreed` | „ktoś potrzebuje do 31" | `E-114`, RBS 00:06:05 |
| 4 | Wypełniono zaświadczenie z szablonu | `certificate_filled` | jeden szablon, stała góra i dół, wolne ciało | `E-64` |
| 5 | Wysłano zaświadczenie | `certificate_sent` | — | `E-65` |
| 6 | Klient podpisał odbiór | `certificate_pickup_signed` | **punkt całego przepływu**, nie księgowość wokół niego | `E-66` |
| 7 | Oznaczono zadanie jako zakończone | `certificate_task_closed` | `P-13` | `E-67` |

### Kształt payloadu

| Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|
| `certificate_id`, `patient_id` | — | `:id` | `AGG-12` |
| `requested_by` | **kto prosił** — pole, którego `R-17` nie miało | `:string` albo `:id`, zależnie czy to zawsze osoba z systemu | `H18` zamknięte 2026-08-17 |
| `form` | **w jakiej formie wyszło** — drugie nowe pole | `:enum` | jw. |
| `due_date` | termin wymagany przez pacjenta | `:timestamp` | `E-114` |
| `body` | wolne ciało zaświadczenia | `:string`, **dane zdrowotne** | `E-64` |

**Wniosek nie jest przechowywany** — tworzy zadanie i przestaje istnieć: „bo to by były kolejne dwie
kartki" (01:28:22). To jest decyzja o retencji podjęta przez klienta i warto ją zapisać jako `:drop`
albo jako brak pola, nie jako przeoczenie.

### Tożsamość

- `[:certificate_id]`. Pacjent może wnioskować wielokrotnie.

### Instancja

- **Jeden przypadek:** jedno zaświadczenie, od wniosku do podpisanego odbioru.
- **Równolegle:** tak, jeden pacjent może mieć dwa wnioski.

### Powtarzalne zdarzenia

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `certificate_sent` | możliwe (ponowna wysyłka) | niepowiedziane | — |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| Podpisany odbiór, zadanie zamknięte | dobre | `E-66`, `P-13` |
| **Nieodebrane** | **niezamodelowane** — model nie ma tego końca | luka |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| Podpisany odbiór przed zamknięciem zadania | zamknięcie | `AGG-12`, `P-13` |

### Kandydaci na `trace`

| # | Po | W ciągu | Wtedy | Inaczej | Wiąże zapasową? | Komu | Dowód |
|---|---|---|---|---|---|---|---|
| 1 | `certificate_requested` | **termin z payloadu, nie stała** | `certificate_sent` albo `certificate_pickup_signed` | — | — | **pacjentowi** | `E-114` |

> ⚠️ **`within` jest stałą w deklaracji, a tutaj termin jest różny dla każdego przypadku** — „ktoś
> potrzebuje do 31". Tego nie da się wyrazić jako `within: {N, :unit}`. Albo termin staje się polityką
> („zawsze w ciągu X dni roboczych") i wtedy jest `trace`, albo zostaje per przypadek i wtedy jest
> **zadaniem z terminem** (`F-02`), nie asercją kontraktu. **Nikt nie powiedział, które.**

### Kadencja

- **Zdarzeniowa.**

### Retencja / dane wrażliwe

| Pole | Kategoria | Surowa? | Polityka | Dowód |
|---|---|---|---|---|
| `body` | **dane zdrowotne** | tak — to jest dokument | `:persist`; „treść ląduje do historii pacjenta" | Ania 01:28:09 |
| wniosek | — | nie | **nie przechowywany w ogóle** | 01:28:22 |

**Rejestr wydań jest obowiązkiem prawnym, nie preferencją:** „my musimy prowadzić rejestr wszystkich
dokumentów, które wychodzą z gabinetu" (01:25:18). I jego cel jest obronny: „znajdziesz zaświadczenie
[i powiesz], że my nie dbamy o twoje dane medyczne. I my wtedy sobie patrzymy — okej, takie zaświadczenie
pan Kowalski wziął sobie" (01:26:13). **Rejestr jest tu aktywem RODO, nie ryzykiem.**

### Zależności zewnętrzne

Żadnej — chyba że `H20` wróci na „tak", i wtedy pojawia się podpis elektroniczny jako zależność.

### Reguły i przykłady

| Reguła | Zadziałało | Poszło źle | Dowód |
|---|---|---|---|
| Zaświadczenie trafia do historii pacjenta, wniosek nie | „tak, zaświadczenie ląduje do historii pacjenta, ale wniosek już nie" | — | 01:28:22 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Nieweryfikowane |
|---|---|---|
| rejestr jest obowiązkiem | 01:25:18 | — |
| pola rejestru: kto wydał, na kogo, kto prosił, kiedy, w jakiej formie | `H18` 2026-08-17 | — |
| **czy podpis elektroniczny wystarcza prawnie** | — | **`H20`, otwarte, potrzebny prawnik.** Jeśli tak, przepływ kurczy się do dwóch kroków i **cały agregat się zawala** |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| `H20` — podpis elektroniczny | istnienie połowy zdarzeń tego procesu | prawnik |
| Czy termin jest polityką czy per przypadek? | czy `trace` #1 w ogóle istnieje | niepowiedziane |
| Co, gdy pacjent nie odbierze? | stan końcowy | model nie ma tego końca |

---

## 8. Zamknięcie dnia

**Wejście:** `20-aggregates.md` `AGG-07`, `10-event-model.md` §3.11
**Jakość dowodu:** stakeholder-stated; jeden potwierdzony defekt.

### Kandydaci na zdarzenia

| # | Zdarzenie | Nazwa techniczna | Dowód |
|---|---|---|---|
| 1 | Zamknięto dzień | `day_closed` | `E-83`, proces 10 |
| 2 | Zaksięgowano korektę po zamknięciu dnia | `day_correction_posted` | `E-84` |

### Kształt payloadu

| Pole | Znaczenie | Typ DSL | Dowód |
|---|---|---|---|
| `location_group_id` | Krobia + stajnia razem, Jutrosin osobno — **ustalone strukturą firmy, nie konfiguracją** | `:id` | `AGG-07` tożsamość |
| `business_date` | **którego dnia dotyczy** | `:timestamp` | inv. 3 |
| `posted_date` | kiedy wpisano — **dziś system myli to z powyższym** | `:timestamp` | `E-84`, znany defekt |
| kwoty per metoda płatności | — | **nie mieszczą się** | `R-07` |

### Tożsamość

- **`[:location_group_id, :business_date]`** — wprost z modelu.

### Instancja

- **Jeden przypadek:** jeden dzień jednej grupy lokalizacji.
- **Równolegle:** tak, dwie grupy zamykają ten sam dzień niezależnie.

### Powtarzalne zdarzenia

| Zdarzenie | Więcej niż raz? | Co odróżnia | Dowód |
|---|---|---|---|
| `day_correction_posted` | **tak** | co koryguje i kiedy wpisano | `E-84` |

### Stany końcowe

| Zakończenie | Dobre/złe | Dowód |
|---|---|---|
| `Zamknięty` | dobre | `AGG-07` |
| `Skorygowany` → wraca do `Zamknięty` | neutralne; **korekta nie otwiera dnia ponownie** | `AGG-07` |

### Etapy / bramki

| Bramka | Co blokuje | Dowód |
|---|---|---|
| Zamknięty dzień jest niezmienny inaczej niż przez korektę | edycję | inv. 2 |

### Kandydaci na `trace`

**Żadnego zakotwiczonego w zdarzeniu.** Obietnica „dzień zostaje zamknięty tego samego dnia" jest
zakotwiczona w kalendarzu, nie w fakcie — to kadencja, nie asercja.

**Ale twierdzenie o sekwencji jest tu mocne i dziś fałszywe**, co czyni proces wartym kontraktu bez
żadnego `trace`: `Skorygowany` wraca do `Zamknięty`, nigdy do `Otwarty`, a korekta przypisuje się do
dnia, którego dotyczy. Dziś przypisuje się do dnia wpisania, więc zamknięte dni cicho dryfują —
i **typ wpisu korygującego w ogóle nie istnieje**, przez co personel wpisuje ponownie. Zadeklarowane
przejście, którego nie ma czym przejechać.

### Kadencja

- **`cadence: {1, :day}`, per grupa lokalizacji.** Jedyny proces w tej destylacji, gdzie kadencja jest
  naturalna i prawdziwa.
- ⚠️ I znów: **nic jej nie pilnuje.** Monitor „nigdy nieobserwowany" odrzucono 6 sierpnia. Deklaracja
  trafia do raportu jako deklaracja. **Jeśli kadencja ma tu cokolwiek znaczyć, to jest to argument
  za zbudowaniem czegoś, co ją czyta — a nie za zadeklarowaniem jej i przemilczeniem, że nic nie robi.**

### Retencja / dane wrażliwe

Nic wrażliwego — kwoty i daty.

### Zależności zewnętrzne

| Zależność | Niedostępność | Dowód |
|---|---|---|
| **Kasa fiskalna** | brak integracji; `Separate Ways` w mapie kontekstów | `X-06`, odrzucone |

### Reguły i przykłady

| Reguła | Zadziałało | Poszło źle | Dowód |
|---|---|---|---|
| Korekta przypisuje się do dnia, którego dotyczy | — | **dziś przypisuje się do dnia wpisania** — zamknięte dni cicho dryfują | `E-84`, inv. 3 |
| Krobia i stajnia zamykają się razem | — | — | proces 10 |

### Źródła / nieweryfikowane

| Twierdzenie | Źródło | Nieweryfikowane |
|---|---|---|
| grupowanie lokalizacji | proces 10 | — |
| korekta trafia w zły dzień | `E-84` | znany defekt, nie zmierzony |
| **typ wpisu korygującego nie istnieje dziś** | `AGG-07` | to dlatego personel wpisuje ponownie i raport dryfuje |

### Otwarte pytania tego procesu

| Pytanie | Blokuje | Czego brakuje |
|---|---|---|
| Czy istnieje termin na zamknięcie dnia? | `deadline` na procesie | niepowiedziane; „zamykamy na koniec dnia" nie jest terminem |

---

## Czego świadomie nie destylowałem

Cisza nie jest tym samym co „nie ma", więc wymieniam z powodem.

| Obszar | Dlaczego nie |
|---|---|
| **Analityka i koszty** (`CTX-09`, `AGG-19`, `R-09`–`R-15`) | to są odczyty, nie procesy. Nie ma w nich obietnicy, którą przebieg mógłby naruszyć. Model sam mówi, że to **jedna księga zdarzeń plus model wymiarowy** (`F-06`), a to jest infrastruktura pod raporty, nie proces do weryfikacji |
| **Konfiguracja, katalog usług, pracownicy** (`CTX-10`) | CRUD z jedną prawdziwą regułą (kwalifikacje). Nic czasowego |
| **Komunikacja z pacjentem** (`CTX-08`) | to nie jest proces, tylko **wątek przez cztery inne** — model to wprost stwierdza: sześć zdarzeń SMS-owych zaprojektowanych w izolacji. Zdarzenia komunikacyjne siedzą w procesach 1 i 7, gdzie mają kotwicę |
| **Karnety i bony** (`AGG-04`, `AGG-14`) | mają cykl życia, ale jedyna obietnica czasowa — ostrzeżenie 2 miesiące przed wygaśnięciem — jest zakotwiczona wstecz (ustalenie 2), a wygaśnięcie to upływ, nie fakt. Do rozważenia w drugiej kolejności |
| **Grafik i zasoby** (`AGG-08`, `AGG-16`) | rdzeń domeny wg mapy kontekstów (`CTX-01` = jedyny `core`) — **i mimo to zero obietnic czasowych.** To jest problem spełniania ograniczeń, nie procesu. Wart uwagi jako ostrzeżenie: **najważniejszy kontekst biznesowo jest tym, w którym PNS ma najmniej do powiedzenia** |
| **Zadania** (`AGG-13`, `F-02`) | fundament współdzielony przez 17 plastrów. Jest terminem dla innych procesów, a `trace` nie przekracza granicy procesu — więc zadanie musi być albo zdarzeniem procesu, który je zrodził, albo niczym w kontrakcie |
| **Stajnia** (`AGG-17`) | model wprost: rekreacja, bez dokumentacji klinicznej i bez obowiązku P1 |

---

## Podsumowanie procesów

Pierwsze trzy kolumny to **to, co overlay weryfikuje bez zegara**. Czwarta to połowa czasowa i jest
normalne, że jest mała.

| # | Proces | Bramki | Stany końcowe (w tym złe) | `trace` | Pola poza zbiorem typów | Największa luka |
|---|---|---|---|---|---|---|
| 1 | Cykl życia wizyty | **6** | 3 (2 złe) | 3, z czego **0 ma podane N** | kwoty | `U-10`: ścieżki, której nie da się przejechać |
| 2 | Dokumentacja kliniczna | 2 | 2 (**1 złe i najczęstsze**) | **2, jeden z liczbą i datą decyzji (24 h)** | ICD to `:enum` bez zbioru | czy dokumentacja medyczna może żyć w logu |
| 3 | **Sprawozdawczość P1** | 3 | 2 (1 złe, **dziś niewidoczne**) | **2, obie z liczbą ustawową; jedna zgodna z prawem** | brak | **od czego liczą się 2 dni** |
| 4 | Rozliczenie wizyty | 1 | 3 | 2, z czego jeden nie powinien powstać | **kwoty — wszędzie** | jak reprezentować pieniądze |
| 5 | Rozliczenie płatnika | 3 | 3 (**2 złe, oba kosztują pieniądze**) | 2, **obie kalendarzowe, obie się nie skompilują** | kwoty | instancja przecina granicę wizyty |
| 6 | Opłata karna | 2 | 3 (**1 niepoliczalny, a klient prosi o tę liczbę**) | 0 | kwoty | nikt nie podał żadnego terminu |
| 7 | Zaświadczenie | 1 | 1 + **1 niezamodelowany** (nieodebrane) | 1, z terminem per przypadek | brak | `H20` może zlikwidować pół procesu |
| 8 | Zamknięcie dnia | 1 | 2 | 0 (to kadencja) | kwoty | przejście, którego nie ma czym przejechać |

## Ustalenia międzyprocesowe

### Wspólne wzorce tożsamości i instancji

- **`visit_id` jest tożsamością czterech agregatów naraz** (`AGG-01`, `AGG-02`, `AGG-03`, `AGG-10`).
  W PNS to jest jeden `process` ze `stages`, nie cztery procesy — patrz ustalenie 1. To jest **najważniejsza
  pojedyncza decyzja** przed napisaniem pierwszej linii kontraktu.
- **Dwa procesy mają instancję, która nie jest wizytą:** rozliczenie płatnika (`[:payer_id, :period]`)
  i opłata karna (`[:penalty_id]`, przecinająca dwie wizyty). Oba są przez to odcięte od `trace`
  łączącego je z wizytą.
- **Zamknięcie dnia ma instancję kalendarzową** (`[:location_group_id, :business_date]`) — jedyną taką.

### Pola, które powtarzalnie nie mieszczą się w zamkniętym zbiorze

- **Kwoty pieniężne — w pięciu z ośmiu procesów.** Rozważane obejścia: grosze jako `:integer` (arytmetyka
  działa, typ kłamie o jednostce) albo `:string` (typ nie kłamie, arytmetyka znika). **Nie proponuję
  `:money`** — dokładnie tym ruchem wszedł `:period` i po dwóch dniach wyleciał, bo typ nazywający rzecz
  zamiast kształtu jest biblioteką znającą jedną domenę. Ale w Rehmedzie pieniądze są w niezmienniku
  (`AGG-03` inv. 1: *linie sumują się do całości*), więc to nie jest kosmetyka.
- **Kody słownikowe (ICD-10, ICD-9, rodzaj i tryb zdarzenia, metoda płatności).** Konceptualnie `:enum`,
  ale **zbioru nie da się zadeklarować** (znana ozdoba w `docs/contract.md`), a tutaj słowniki są
  ogromne i zewnętrzne — „milion słowników, które trzeba mieć u siebie". Efekt: albo `:string`
  (i wtedy kontrola retencji traktuje kod ICD jak tekst pisany przez człowieka, co akurat jest prawdą
  o wrażliwości i nieprawdą o pochodzeniu), albo `:enum` bez żadnej gwarancji.
- **Brak kategorii „dane zdrowotne" w `retain`.** `:persist`/`:hash`/`:drop` mówią, **co zostaje**, nie
  **jakiego reżimu wymaga**. W tej domenie połowa payloadów to dokumentacja medyczna z ustawowym okresem
  przechowywania. To jest największa różnica między tą domeną a TaxVision i **nie znika przez ostrożne
  pisanie kontraktu.**

### Procesy z zerem kandydatów na `trace` — i co weryfikują zamiast tego

Fakt o domenie, nie werdykt. Każdy z tych trzech ma zadeklarowaną ścieżkę, która dziś nie jest
przejeżdżana — czyli materiał dla overlaya, bez jednej liczby.

- **Opłata karna** — `penalty_collected` istnieje w modelu i nie w rzeczywistości, bo kaucja jest poza
  zakresem. **Klient prosi o tę liczbę na piśmie.**
- **Zamknięcie dnia** — typ wpisu korygującego nie istnieje, więc przejście `Zamknięty → Skorygowany`
  nie ma czym się odbyć, a personel wpisuje ponownie.
- **Grafik i zasoby** — rdzeń biznesowy wg mapy kontekstów, zero obietnic czasowych **i zero
  sekwencji**: to jest problem spełniania ograniczeń („czy ta rezerwacja może istnieć"), nie proces.
  **To jedyny z trzech, o którym PNS naprawdę nie ma nic do powiedzenia** — i warto to wiedzieć przy
  wyborze pilota, bo to jest jednocześnie to, co dla Rehmedu najbardziej różnicujące.

### Promises zakotwiczone wstecz — poza kontraktem

Przypomnienie przed wizytą, termin bezpłatnego odwołania, ostrzeżenie o wygasającym bonie. `trace`
biegnie w przód od faktu, więc żadnego z nich nie wyrazi. **Należą do `F-02`**, silnika zadań, który
i tak powstaje pod siedemnaście plastrów. Nie są luką w kontrakcie i nie są powodem, żeby dokładać mu
harmonogram.

### Sygnał gotowości

Oceniane **strukturą w pierwszej kolejności**: proces z jasną instancją, uporządkowanymi etapami
i uczciwymi stanami końcowymi jest gotowy niezależnie od tego, czy ma choć jeden `trace`.

- **Gotowe do pierwszego szkicu:** **3 (P1)** i **2 (dokumentacja)** — mają jedno i drugie: dwie liczby
  z zewnętrznym źródłem *oraz* stan końcowy, którego dziś nie da się zobaczyć. Do tego **1 (cykl życia
  wizyty)**, którego pierwsza wersja tej sekcji nie umieściła tu tylko dlatego, że liczyła `trace`:
  sześć bramek, trzy stany końcowe i `U-10` — ścieżka, której nie da się przejechać przy zdarzeniu
  codziennym. **To jest najlepszy pojedynczy materiał demonstracyjny w całym zestawie.**
- **Gotowe strukturalnie, wymagają potwierdzenia jednego faktu:** **6 (kara)** — czy pacjent może mieć
  dwie otwarte naraz; **8 (zamknięcie dnia)** — nic więcej, poza świadomością, że kadencji nic nie czyta.
- **Wymagają rundy z klientem, bo otwarte pytanie zmienia payload albo istnienie asercji:** 4, 5, 7.

### Jedno zastrzeżenie do całości

**Wszystko powyżej jest dowodem drugiego rzędu.** Czytałem model solution-space, nie transkrypty.
Ten model jest starannie zrobiony, sam się audytuje i sam wykrył u siebie cztery przypadki, w których
odpowiedziany hotspot nigdy nie dotarł do artefaktów — ale jest warstwą pośrednią i **jego własne
README mówi, że 4 ze 115 zdarzeń to `observed`.** Zanim cokolwiek z tego trafi do kontraktu, który
klient zobaczy, trzeba potwierdzić przynajmniej: kotwicę dwóch dni P1 (proces 3), istnienie
`visit_handed_over` (`U-09`) i termin, w jakim kara ma być pobrana (proces 6).
