# AppuniteEquipment — destylacja do kontraktu EhOsContract, 2026-10-03

Po polsku, bo to materiał roboczy zespołu i cytuje rozmówców dosłownie — nie kod, nie jedzie z pakietem.
Nazwy techniczne po angielsku, `label` po polsku, jak w `docs/rehmed-2026-08-18-distillation.md`.

**Wejście:** trzy źródła, różnej wagi.

| Skrót | Co | Waga |
|---|---|---|
| `T l.N` | Notatka z rozmowy z Magdą (osoba zarządzająca sprzętem), 2026-10-02, linia N pliku. **Nie transkrypt nagrania** — l.48: „Nie nagrywam dźwięku, tylko spisuję tekst". Bez podpisów mówców, z błędami rozpoznania (niżej). | stakeholder-stated, drugiego rzędu |
| `E` | Odpowiedzi Emila w rozmowie z 2026-10-03. Emil zna proces i jest na razie jedynym, kogo można dopytać. | stakeholder-stated |
| `A:F`, `A:G` | Zrzuty list wyboru z arkusza: kolumna F „Aktualny status", kolumna G „Dalsze działania w Office" (2026-10-03). Arkusza w całości nie widziałem — zakładek i pozostałych kolumn nie znam. | observed (tylko słownik) |

**Podsumowanie na górze notatki nie jest źródłem.** Twierdzi, że M1 „są wycofywane ze sprzedaży" — rozmówczyni
mówi odwrotnie (T l.66, potwierdzone przez E: M1 idą na sprzedaż), i wprowadza nazwisko, którego transkrypt nie
zawiera. Cytuję tylko część „Transcript".

**Błędy rozpoznania w transkrypcie**, czytane tu tak:

| W tekście | Czytam jako | Na podstawie |
|---|---|---|
| „spółki" (l.76–78) | „z półki" | kontekst: „w pierwszej kolejności bierzemy z reużytku" |
| „ERA" (l.74) | MacBook Air | kontekst: dla operacyjnych, obok „PRO" |
| „inergo", „Winergo", „INERGO" | Innergo | E: „dokładnie Innergo" |
| „refarbist" (l.64) | refurbished | — |
| „Daga", „Dagusia" | Dagmara | E |
| „ustawienie kompanii" (l.58) | ustawienie komputera | `unverified` |

---

## Zanim przeczytasz procesy

### 1. Komputer żyje latami i chodzi w pętli — to jest sygnał dla biblioteki

W TaxVision i w Rehmed przebieg to sprawa z początkiem i końcem (miesiąc, wizyta). Tu główną historią jest
**komputer**: przyjęty z faktury, potem wielokrotnie *wydany → zwrócony → (Innergo) → ustawiony → wydany*,
aż do jednego z pięciu zakończeń. Jeden komputer przechodzi tę pętlę kilka razy (T l.94: „spis wszystkich
komputerów w historii AppUnite, które nawet były lata temu").

To zderza się z dwiema rzeczami w silniku:

- **`stage` i krawędzie wstecz.** Kolejność między etapami jest jedynym twierdzeniem o porządku, jakie
  kontrakt składa (`EhOsContract.Graph`), i jest liniowa; `mix eh_os_contract.check` ostrzega `backward-edge`,
  gdy reakcja wydaje komendę, której zdarzenia leżą we wcześniejszym etapie
  (`EhOsContract.Check.Contracts`). Tu powrót z „w użytku" do „w biurze" jest **normalną ścieżką**, nie dryfem.
- **Przebieg = życie komputera** to przebieg bez terminu i zwykle bez końca przez lata. Raport „ścieżki nigdy
  nie przejechane" liczy się po zakończonych przebiegach albo po wszystkich — trzeba sprawdzić, co pokaże.

Trzy kształty do wyboru przy pisaniu kontraktu (to decyzja dla autora kontraktu i dla `PLAN.md`, nie tutaj):

| Kształt | Przebieg | Za | Przeciw |
|---|---|---|---|
| A. Jeden proces na komputer | `correlate :serial_number`, przyjęcie → zakończenie | jedna historia, tak jak arkusz Inventory | pętla wraca do wcześniejszych etapów |
| B. Komputer jako agregat + proces per **przydział** | `correlate :assignment_id`, wydanie → zwrot | przebieg ma koniec, etapy idą do przodu | przyjęcie, Innergo i sprzedaż wypadają poza każdy przydział |
| C. Komputer jako agregat + proces per **pobyt w biurze** | od powrotu do ponownego wydania | etapy liniowe: wrócił → (Innergo) → ustawiony → wydany | sztuczna jednostka, nikt tak nie mówi |

**Stan (2026-10-03, E):** **B**, i tak jest napisany kontrakt (`sandbox/lib/appunite_equipment/`, `PLAN.md`, dopisek 3 października); A wciąż rozważane — B przegrywa tym, że przyjęcie, Innergo, formatowanie i sprzedaż wypadają poza każdy przydział, A — tym, że wymaga zmiany w bibliotece (etapy dziś idą tylko do przodu). C odpada: nikt tak nie mówi.

To jest pierwszy materiał, który to sprawdza, i dlatego jest wartościowy niezależnie od tego, czy kontrakt
powstanie w pełni.

### 2. Dwie kolumny arkusza to dwa odczyty, nie dwa pola

`A:F` mówi, **gdzie komputer jest i u kogo**. `A:G` mówi, **co Magda ma z nim zrobić**, póki leży w biurze —
to lista zadań. Obie dziś przestawia się ręcznie. W kontrakcie obie wynikają z historii: „wrócił z Innergo,
nieustawiony od tego czasu" *jest* „Office / Do ustawienia". Żadna nie powinna być polem, które się wpisuje.

### 3. Domena bez zegara

Nie padła żadna obietnica z liczbą, którą AppUnite komuś składa (niżej, *Obietnice*). Jedyna liczba — ~tydzień
w Innergo — to czas dostawcy. Proces jest weryfikowalny przez bramy, zakończenia i ścieżki, jak Rehmed.

### 4. Czy formatowanie kasuje ustawienie — sprawdzone w dokumentacji Apple

Tak: wymazanie Maca usuwa z dysku wszystko, także profil MDM i włączony FileVault. Apple wprost ostrzega, że
wymazanie Maca z FileVaultem bez „Erase All Content and Settings" kończy się ponowną instalacją macOS
([Erase Apple devices](https://support.apple.com/en-za/guide/deployment/dep0a819891e/web)). Czy MDM wraca
**sam**, zależy od tego, czy komputer jest w Apple Business Manager (Automated Device Enrollment): wtedy
wymazany komputer przy pierwszym uruchomieniu zapisuje się znowu według ustawień organizacji
([Automated Device Enrollment](https://support.apple.com/en-us/102300)). Bez tego — ręcznie. Dla kontraktu
wniosek jest ten sam: po `computer_wiped` i `service_returned` reguła I1 wymaga nowego `computer_set_up`.
Czy AppUnite używa ABM — `unverified`.

---

## Domena

### Subdomeny i konteksty

| Kontekst (słowa klienta) | Nazwa techniczna | Rodzaj | Dowód |
|---|---|---|---|
| sprzęt, „dostęp i nadanie sprzętu" | `equipment` | `:supporting` | T l.58 |
| onboarding / offboarding (zadania w Notion) | `onboarding` | `:supporting`, **poza zakresem** — tylko źródło faktów | T l.54–58, l.100 |
| umowy przekazania i zdania sprzętu | `handover_documents` | `:generic`, **poza zakresem** | T l.100–102 |
| księgowość (faktura sprzedaży) | `accounting` | `:generic`, **poza zakresem** | E |

### Słownik — kontekst `equipment`

| Termin | Definicja, jak padła | Unikać | Dowód |
|---|---|---|---|
| Office | komputer jest w biurze; co dalej — mówi „Dalsze działania" | — | A:F, T l.90 |
| z półki / reużytek | komputer używany, dostępny w biurze, bierze się go przed nowym | „spółki" (błąd rozpoznania) | T l.66, l.76–78 |
| New | nowa osoba ma zamówiony komputer i czekamy na dostawę | — | A:F, E |
| ustawienie | standardowe ustawienia, np. MDM i szyfrowanie dysku; bez nich komputera się nie wydaje | „konfiguracja" — `unverified`, czy w ogóle pada | E |
| W użytku | komputer jest u pracownika | — | A:F, T l.94 |
| Zastępczy | komputer wydany pracownikowi, którego komputer ma awarię | — | A:F, T l.94 |
| W trakcie zwrotu | pracownik oddaje komputer, jeszcze nie dotarł | — | A:F, T l.106 |
| Innergo spa | komputer jest w Innergo (czyszczenie albo naprawa) | — | A:F, T l.106 |
| For sale | komputer w biurze, przeznaczony do sprzedaży | — | A:G, T l.94 |
| Do wyczyszczenia | komputer w dobrym stanie, który przed odłożeniem na półkę Magda formatuje sama, bez Innergo | — | A:G, E |
| ryneczek | wewnętrzna sprzedaż komputerów For sale pracownikom: kto pierwszy, ten lepszy; gdy nikt się nie zgłasza — Allegro | — | E |
| wycofana generacja | procesor, od którego firma się odcięła jako przestarzałego; dziś M1, bo na rynku jest M5. Taki komputer idzie na sprzedaż | — | T l.66, E |
| Current | zakładka: kto z jakiego komputera korzysta | — | T l.90–94 |
| Inventory | zakładka: wszystkie komputery w historii, ze statusami | — | T l.94 |
| Sold / Charity / Utylizacja / Lost | zakończenia: sprzedany, oddany, zutylizowany, zgubiony lub skradziony | — | A:F, E |

### Relacje między kontekstami

| Upstream | Downstream | Jak | Dowód |
|---|---|---|---|
| onboarding (rekrutacja) | equipment | po podpisaniu umowy osoba „wlatuje" do zadań; Magda czyta | T l.58 |
| equipment | handover_documents | Dagmara czyta numer seryjny i datę z zakładki, robi umowę przekazania; datę zwrotu — dokument zdania. Magda tych dokumentów nie widzi | T l.100–102 |
| equipment | accounting | po sprzedaży księgowość wystawia fakturę | E |
| Innergo | equipment | Magda przepisuje statusy i raport z konta w Innergo do komentarza | T l.106–108 |

**Ustalenie (E):** rekrutacja i Dagmara wchodzą do kontraktu jako aktorzy, którzy **ręcznie wpisują fakt** — bez
busa między aplikacjami.

### Aktorzy

| Aktor | Human / system | Kontekst | Dowód |
|---|---|---|---|
| Magda — osoba zarządzająca sprzętem | `:human` | equipment | T l.58, E |
| Dagmara — umowy przekazania i zdania | `:human` | handover_documents | T l.100, E |
| rekrutacja — wpisuje nową osobę po podpisaniu umowy | `:human` | onboarding | T l.58 |
| pracownik — dostaje, zwraca, zgłasza, że parametry nie wystarczają | `:human` | equipment | T l.84 |
| księgowość — wystawia fakturę sprzedaży | `:human` | accounting | E |
| kupujący — pracownik (Paweł, Tadeusz) albo ktoś z Allegro | **nie aktor**: niczego w procesie nie wydaje, Magda notuje sprzedaż | — | T l.96, E |

Innergo nie jest aktorem: nic samo nie wpisuje, Magda przepisuje z jego panelu.

### Podmioty danych osobowych

| Podmiot | Identyfikowany przez | Dowód |
|---|---|---|
| pracownik | identyfikator pracownika — **nie** imię i nazwisko, którymi dziś są wiersze Current | T l.92 |
| kupujący spoza firmy | nie trzymać w kontrakcie; dane ma faktura księgowości, kontrakt — tylko jej numer | E, wniosek |

### Wartości

| Wartość | Kształt | Co ją psuje | Poprawna | Niepoprawna | Dowód |
|---|---|---|---|---|---|
| numer seryjny | numer seryjny Apple: wielkie litery i cyfry ASCII. Starsze Maki — 12 znaków z kodem fabryki, daty i konfiguracji; od 2021 (pierwsze M1) — losowy, 10 znaków (Apple zapowiadał 8–14) | znaki spoza `[A-Z0-9]`, długość spoza 8–14 | 10 losowych znaków | z małymi literami albo spacją | E („format komputerów Apple"), MacRumors 2021-03-09 |
| profil sprzętu | jeden z: `developer` (MacBook Pro, dziś M5 Pro), `operations` (MacBook Air) | inny profil | — | — | T l.74 |
| procesor | jeden z: M1…M5 (+ Pro/Max?) | `unverified` | M5 Pro | — | T l.66, l.74 |
| wycofane generacje | lista procesorów; zmienia się w czasie (dziś `[M1]`) — decyzja zespołu, nie stała | procesor spoza listy procesorów | `[M1]` | — | E |
| kwota | grosze, PLN | ujemna | — | — | E (cena z faktury, koszt naprawy, cena sprzedaży) |
| numer przesyłki | tekst | `unverified` | — | — | E |

### Systemy zewnętrzne

| System | Wysyła / odbiera | Niedostępny wygląda tak | Brak odpowiedzi = odmowa? | Dowód |
|---|---|---|---|---|
| sklep i serwis Apple (Innergo) — panel zamówień, statusy serwisu, rejestr gwarancji | oba, **ręcznie przez Magdę** | nie padło | nie padło | T l.88, l.106, E |
| zadania onboardingu i offboardingu (Notion) | tylko odbiera do nas, ręcznie | nie padło | — | T l.58 |
| serwis aukcyjny (Allegro) — wystawienie i porównanie cen | tylko wysyła, ręcznie | nie padło | — | E |

Wszystkie trzy obsługuje człowiek, więc w kontrakcie nie ma tu żadnego `effect` — są fakty, które człowiek notuje.

---

## Proces 1 — życie komputera

**Kontekst:** `equipment` · **Jakość dowodu:** stakeholder-stated (T + E), słownik statusów observed (A).

### Fakty i kandydaci, którzy faktami nie są

| # | Kandydat | Nazwa | **Co od tego zależy** | Werdykt | Dowód |
|---|---|---|---|---|---|
| 1 | komputer zamówiony dla nowej osoby | `computer_ordered` | onboarding czeka na dostawę; zapas wobec zaplanowanych onboardingów | fakt | A:F „New", E |
| 2 | komputer przyszedł, spisany z faktury | `computer_received` | bez niego nie da się ustawić; od daty zakupu biegnie gwarancja | fakt | T l.88–90, E |
| 3 | komputer ustawiony (MDM, szyfrowanie) | `computer_set_up` | **wydanie jest bez niego odmawiane** | fakt | E |
| 4 | komputer wydany pracownikowi | `computer_issued` | Dagmara robi umowę przekazania; Current; każdy zwrot | fakt | T l.100–102 |
| 5 | wydany jako zastępczy | — | odesłanie zepsutego; status Zastępczy | **wariant #4**, pole `as: :replacement` — `unverified`, czy osobny fakt | T l.94, E |
| 6 | pracownik zostaje z zastępczym | `replacement_kept` | status Zastępczy → W użytku | fakt `unverified` — zależy od tego, czy zastępczy musi kiedyś wrócić | E |
| 7 | zwrot rozpoczęty („W trakcie zwrotu") | `return_started` | Dagmara: data zwrotu → dokument zdania; ścieżka „nie dotarł" | fakt | A:F, T l.100, l.106 |
| 8 | zwrot dotarł do biura | `computer_returned` | Office; kolejka Magdy | fakt | wniosek z A:F |
| 9 | Magda decyduje: do Innergo / do wyczyszczenia / do ustawienia / na sprzedaż | — | tylko jej własna kolejka | **nie fakt**: plan Magdy; fakt to dopiero wykonanie (#9a, #10, #15) | A:G, E |
| 9a | komputer sformatowany przez Magdę przed odłożeniem na półkę | `computer_wiped` | **kasuje ustawienie** — znowu „Do ustawienia" | fakt | A:G, E, dokumentacja Apple (niżej) |
| 10 | wysłany do Innergo (czyszczenie lub naprawa) | `sent_for_service` | Innergo spa; czeka na powrót | fakt | T l.106–108, E |
| 11 | wrócił z Innergo z diagnozą | `service_returned` | **kasuje ustawienie** — znowu „Do ustawienia" | fakt | T l.108, E |
| 12 | raport Innergo w komentarzu | — | nic | **pole** #11 | T l.106 |
| 13 | koszt naprawy zapisany | — | nic poza sumą kosztów | **pole** #11 | E |
| 14 | gwarancja | — | prowadzi ją Innergo | **poza zakresem**; zostaje data zakupu w #2 | E |
| 15 | wystawiony na sprzedaż (For sale) | `put_up_for_sale` | zakładka For Sale; nie wydaje się go już pracownikowi | fakt | T l.94, A:G, E |
| 16 | zarezerwowany na ryneczku — kto pierwszy, ten lepszy; wpisuje Magda | `computer_reserved` | **odmowa drugiej rezerwacji**; sprzedaż temu, kto zarezerwował | fakt | T l.96, E |
| 16b | rezerwacja przepadła (ktoś się rozmyślił) | `reservation_dropped` | komputer wraca na ryneczek | fakt — „teoretycznie tak", rzadki | E |
| 16a | wystawiony na Allegro, bo nikt się nie zgłosił | `listed_externally` | **zamyka ryneczek** — rezerwacja po nim jest odmawiana | fakt (wcześniej pole; zmienione po odpowiedzi E) | E |
| 17 | sprzedany — w chwili wystawienia faktury przez księgowość; wpisuje Magda | `computer_sold` | **koniec**; wyszarzony w Inventory | fakt, terminalny | T l.110–112, E |
| 18 | oddany (Charity) | `computer_donated` | koniec | fakt, terminalny | A:F |
| 19 | zutylizowany | `computer_disposed` | koniec | fakt, terminalny | A:F |
| 20 | zgubiony / skradziony (Lost) | `computer_lost` | koniec — odnalezienie „mała szansa", nie modelujemy | fakt, terminalny | A:F, E („ostatnio jeden został ukradziony") |
| 21 | wysłany pocztą / odebrany osobiście | — | nic | **pole** #4 (numer przesyłki, pusty przy odbiorze osobistym) | E |
| 22 | data otrzymania | — | Dagmara | **pole** #4 — to data **wysłania** | E |
| 23 | Magda „aktualizuje statusy" | — | — | **nie fakt**: status wynika z faktów | T l.66, l.112 |

**25 kandydatów (bez #23): 18 faktów (w tym #6 `unverified`), 7 pól, wariantów, planów lub spraw poza zakresem.**

### Decydowane czy notowane

| Fakt | Komenda (kto) | Czy można odmówić |
|---|---|---|
| `computer_ordered` | `order_computer` (Magda) | nie padło |
| `computer_received` | `receive_computer` (Magda) | numer seryjny już w inwentarzu — wniosek, `unverified` |
| `computer_set_up` | `set_up_computer` (Magda) | komputer nie w biurze — wniosek |
| `computer_issued` | `issue_computer` (Magda) | **tak** — I1, I2, I3 |
| `replacement_kept` | `keep_replacement` (Magda) | nie jest zastępczy — wniosek |
| `return_started` | `start_return` (Magda, przy offboardingu, wymianie, awarii) | nie jest wydany — wniosek |
| `computer_returned` | notowany przez Magdę | — |
| `computer_wiped` | `wipe_computer` (Magda) | nie w biurze — wniosek |
| `sent_for_service` | `send_for_service` (Magda) | nie w biurze — wniosek |
| `service_returned` | notowany przez Magdę (odpowiedź Innergo) | — |
| `put_up_for_sale` | `put_up_for_sale` (Magda) | nie w biurze — wniosek |
| `computer_reserved` | `reserve_computer` (Magda, gdy pracownik się zgłosi) | **tak** — I6, I7 |
| `reservation_dropped` | `drop_reservation` (Magda) | nie zarezerwowany — wniosek |
| `listed_externally` | `list_externally` (Magda) | zarezerwowany — wniosek |
| `computer_sold` | notowany przez Magdę po fakturze księgowości | nie wystawiony — wniosek; zarezerwowany przez kogoś innego — I6 |
| `computer_donated`, `computer_disposed` | Magda | nie padło |
| `computer_lost` | Magda | — |

### Co musi być prawdą

| # | Reguła | Zakres | Przypadek odmowy | Dowód |
|---|---|---|---|---|
| I1 | Komputera bez standardowych ustawień nie wydaje się pracownikowi. Po czyszczeniu w Innergo i po formatowaniu przez Magdę ustawia się od nowa. | jeden komputer | komputer wrócił z Innergo (Office / Do ustawienia), Magda próbuje go wydać → odmowa. **Skonstruowany** z reguły, nie z wydarzenia | E |
| I2 | Wydaje się tylko komputer, który jest w biurze. | jeden komputer | komputer w Innergo spa, próba wydania → odmowa. **Wniosek** ze statusów | A:F |
| I3 | Komputera wystawionego na sprzedaż nie wydaje się. | jeden komputer | `unverified` | A:G, wniosek |
| I4 | Po zakończeniu (Sold, Charity, Utylizacja, Lost) nic się z komputerem nie dzieje. | jeden komputer | sprzedany komputer, próba wysłania do Innergo → odmowa. **Wniosek** | T l.110–112 |
| I5 | Komputera wycofanej generacji (dziś M1) nie wydaje się pracownikowi — idzie na sprzedaż. Decyzja zespołu, nie Magdy przy każdym komputerze. | jeden komputer + lista wycofanych | M1 wrócił od pracownika, Magda próbuje go wydać nowej osobie → odmowa. **Skonstruowany** | T l.66, E |
| I6 | Komputer z ryneczku rezerwuje pierwszy, kto się zgłosi; drugiej rezerwacji nie ma. | jeden komputer | Paweł zarezerwował komputer, zgłasza się Tadeusz → odmowa. **Skonstruowany** z imion z T l.96 | T l.96, E |
| I7 | Po wystawieniu na Allegro ryneczek jest zamknięty. | jeden komputer | komputer na Allegro, zgłasza się pracownik → odmowa. **Skonstruowany** | E |
| — | Programista dostaje Pro, operacje — Air. | — | **nie reguła**: przy wymianie pracownik wybiera z propozycji (T l.84). Wytyczna | T l.74 |
| — | Najpierw z półki, potem nowy. | — | **nie reguła**: E „może, nie wiem". Preferencja | T l.66, E |

### Pola

| Fakt | Pole | Typ | Osobowe | Dowód |
|---|---|---|---|---|
| `computer_ordered` | dla kogo (onboarding), profil | identyfikator, profil | tak, pracownika | E |
| `computer_received` | numer seryjny, model/procesor, cena, data zakupu, numer faktury zakupu | numer seryjny, procesor, kwota, data, tekst | nie | T l.88, E |
| `computer_issued` | pracownik, data wysłania, numer przesyłki (opcjonalny), jako zwykły / zastępczy | identyfikator, data, tekst, jeden z | tak, pracownika | T l.102, E |
| `return_started` | data zwrotu, powód (offboarding / wymiana / awaria) | data, jeden z | tak (przez wydanie) | T l.100 |
| `sent_for_service` | powód (czyszczenie / naprawa) | jeden z | nie | E |
| `service_returned` | diagnoza (raport), koszt | tekst, kwota | nie | T l.106–108, E |
| `put_up_for_sale` | cena wywoławcza (porównana z Allegro) | kwota | nie | E |
| `computer_reserved` | pracownik, data | identyfikator, data | tak, pracownika | E |
| `computer_sold` | cena, numer faktury sprzedaży, kanał (ryneczek / Allegro) | kwota, tekst, jeden z | nie — kupującego nie trzymamy | E |

### Przebieg

- **Jedna sprawa:** życie komputera od zamówienia (albo przyjęcia, dla kupionych bez zamówienia — `unverified`) do zakończenia. Kształt — patrz „Zanim przeczytasz", pkt 1.
- **Powtarzają się:** `computer_issued`, `return_started`, `computer_returned`, `sent_for_service`, `service_returned`, `computer_set_up` — każde wielokrotnie. Kolejne odróżnia tylko kolejność.

### Zakończenia

| Zakończenie | Dobre / złe / neutralne | Dowód |
|---|---|---|
| Sold | neutralne (zwykły koniec) | T l.110, E |
| Charity | neutralne | A:F |
| Utylizacja | neutralne | A:F |
| Lost | złe | A:F, E |

### Etapy i bramy

| Brama | Co blokuje | Twierdzona czy typowa | Dowód |
|---|---|---|---|
| przyjęty → ustawiony | ustawienie | twierdzona (nie ma czego ustawiać) | wniosek |
| ustawiony od ostatniego czyszczenia → wydany | wydanie | **twierdzona** | E |
| w biurze → Innergo / sprzedaż / wydanie | wszystko poza biurem | twierdzona przez statusy | A:F, A:G |
| zwrot → (Innergo albo formatowanie u Magdy) → ustawienie → półka | odłożenie na półkę | twierdzona: „przed odłożeniem na półkę trzeba go sformatować"; **nie każdy zwrot idzie do Innergo**, decyduje Magda. `unverified`: czy zwrot może pominąć oba | E |
| wystawiony → zarezerwowany → sprzedany | sprzedaż na ryneczku | twierdzona | E |
| wystawiony → na Allegro → sprzedany | sprzedaż poza firmą; zamyka ryneczek | twierdzona | E |
| zepsuty u pracownika → zastępczy wydany → zepsuty odesłany | odesłanie | typowa — „najpierw dostaje zastępczy, potem odsyła zepsuty" | E |

### Reakcje

| Gdy | To | Rodzaj | Razem czy po | Dowód |
|---|---|---|---|---|
| `computer_issued` | Dagmara robi umowę przekazania | dziś: Dagmara czyta zakładkę. W kontrakcie: odczyt dla Dagmary | po | T l.100–102 |
| `return_started` | Dagmara robi dokument zdania | jw. | po | T l.100 |
| `service_returned` | komputer wraca do kolejki „Do ustawienia" | odczyt (kolejka), nie reakcja | — | E |
| kupujący znaleziony | księgowość wystawia fakturę | człowiek; `unverified`, jak dziś księgowość się dowiaduje | po | E |

### Co ludzie czytają

| Co | Kto | Zawężone do | Dowód |
|---|---|---|---|
| Current — kto ma który komputer | Magda, Dagmara | wszystkie wydane | T l.90–92 |
| Inventory — historia ze statusami | Magda | wszystkie, z zakończonymi | T l.94 |
| For Sale / ryneczek — dostępne do kupna, z rezerwacjami | Magda, pracownicy | wystawione | T l.94–96, E |
| Dalsze działania w Office — kolejka Magdy | Magda | w biurze | A:G |
| do umów — seryjny i data wydania / zwrotu | Dagmara | nowe wydania i zwroty | T l.100–102 |
| zapas wobec zaplanowanych onboardingów | Magda | gotowe w biurze + zamówione | T l.78 — **dziś nikt tego nie liczy**, Magda „wchodzi za jakiś czas i patrzy" |
| koszty na komputer | `unverified`, kto | — | E |

### Obietnice

| # | Po | W ciągu | Potem | Inaczej | Komu | Dowód |
|---|---|---|---|---|---|---|
| — | `sent_for_service` | ~1 tydzień | `service_returned` | nie padło | Innergo wobec AppUnite | T l.108 — „około", `unverified` |

**Zero obietnic AppUnite.** „Komputer czeka na pracownika" to staranie bez liczby (E: „nie ma terminu"), a do tego
liczy się wstecz od daty startu — to byłby timer, nie obietnica. Ewentualna obietnica Innergo jest
zobowiązaniem dostawcy: można ją zadeklarować jako `unverified`, jeśli ktoś chce widzieć, kiedy serwis się
przeciąga.

### Termin, rytm, odpowiedzialność

- **Termin całej sprawy:** brak — komputer żyje latami.
- **Rytm:** brak; proces wywołują zdarzenia (onboarding, zgłoszenie, offboarding).
- **Kto odpowiada:** Magda.

### Scenariusze

| Dane | Gdy | Wtedy | Prawdziwy? | Dowód |
|---|---|---|---|---|
| nowy M5 Pro przyjęty, nieustawiony | Magda wydaje go nowej osobie | odmowa — I1 | skonstruowany | E |
| komputer wrócił z Innergo po czyszczeniu | Magda wydaje go bez ponownego ustawienia | odmowa — I1 | skonstruowany | E |
| komputer w Innergo spa | Magda wydaje go jako zastępczy | odmowa — I2 | skonstruowany | A:F |
| pracownikowi padł komputer | Magda wydaje zastępczy, pracownik odsyła zepsuty, zepsuty idzie do Innergo, wraca po ~tygodniu | pracownik zostaje z zastępczym, naprawiony wraca do biura | typowy | T l.94, l.108, E |
| M1 wrócił od pracownika | Magda wystawia go na sprzedaż, Paweł chce kupić, księgowość wystawia fakturę | Sold, wyszarzony | typowy | T l.66, l.96, E |
| komputer u pracownika | został skradziony | Lost | **prawdziwy**, „ostatnio" | E |
| M1 wrócił od pracownika | Magda wydaje go nowej osobie | odmowa — I5 | skonstruowany | T l.66, E |
| Paweł zarezerwował komputer na ryneczku | rezerwuje Tadeusz | odmowa — I6 | skonstruowany | T l.96, E |
| komputer wystawiony na Allegro | zgłasza się pracownik | odmowa — I7 | skonstruowany | E |
| Paweł zarezerwował, rozmyślił się | Magda zwalnia rezerwację, rezerwuje Tadeusz | rezerwacja Tadeusza | skonstruowany | E |
| komputer na ryneczku, nikt się nie zgłasza | Magda wystawia na Allegro, księgowość wystawia fakturę | Sold, kanał Allegro | typowy | E |
| komputer wrócił w dobrym stanie | Magda formatuje, ustawia, odkłada na półkę | Office, gotowy | typowy | E |

### Otwarte pytania

| Pytanie | Blokuje |
|---|---|
| Czy komputery są w Apple Business Manager (automatyczne zapisanie do MDM)? Wtedy po wymazaniu MDM wraca sam przy pierwszym uruchomieniu, ale ustawienie i tak trzeba potwierdzić | czy `set_up_computer` to praca, czy tylko sprawdzenie |
| Czy zwrot może trafić na półkę bez formatowania i bez Innergo? | brama „przed półką" |
| „New" przy komputerze kupionym na zapas, nie dla konkretnej osoby — jest? | czy `computer_ordered` ma zawsze adresata |
| Zakładki i kolumny arkusza poza F i G | pola |

---

## Proces 2 — sprzęt dla osoby

**Kontekst:** `equipment` (z faktami wpisywanymi przez rekrutację) · **Jakość dowodu:** stakeholder-stated.

Druga strona tej samej historii: osoba, nie komputer. Tu przebieg ma początek i koniec, więc pasuje do silnika
bez pętli.

### Fakty

| # | Kandydat | Nazwa | Co od tego zależy | Werdykt | Dowód |
|---|---|---|---|---|---|
| 1 | nowa osoba po podpisaniu umowy, z datą startu | `hire_announced` (wpisuje rekrutacja) | Magda zaczyna; zamówienie albo komputer z półki | fakt | T l.58 |
| 2 | komputer przydzielony / wydany | = `computer_issued` z procesu 1 | — | **wspólny** z procesem 1 | — |
| 3 | pracownik zgłasza, że parametry nie wystarczają | `replacement_requested`? | rozmowa i propozycja | **otwarte**: dziś to rozmowa (T l.84), nic nie odmawia | T l.84 |
| 4 | awaria | `failure_reported`? | wydanie zastępczego | **otwarte** | T l.94, E |
| 5 | odejście, z datą | `departure_announced` (wpisuje rekrutacja/HR?) | zwrot | fakt, `unverified` kto wpisuje | T l.96, l.100 |
| 6 | pracownik nie oddał albo oddał uszkodzony — pokrywa koszt / potrącenie | `cost_charged`? | koniec złej ścieżki offboardingu | **otwarte**: dzieje się w kadrach, nie u Magdy | E |
| 7 | umowa przekazania / zdania wysłana przez Dagmarę | — | nic w tym procesie | **poza zakresem** (E: Dagmara wpisuje fakt — ale nic na niego nie czeka) | T l.100 |

### Kluczowa sprzeczność kształtu

`computer_issued` ma dwie korelacje: **numer seryjny** (proces 1) i **pracownika** (proces 2). W silniku zdarzenie
należy do jednego kontraktu i jednego `correlate`. Opcje dla autora kontraktu: jeden kontrakt z procesem po
komputerze i read modelem po pracowniku (proces 2 tylko jako odczyt); albo `dcb` nad komputerem i pracownikiem,
jeśli pojawi się reguła po obu (np. „jeden pracownik — jeden komputer w użytku, plus zastępczy"). Taka reguła
**nie padła** — nie wymyślam jej.

### Reguły

| Reguła | Status | Dowód |
|---|---|---|
| pracownik nie wybiera komputera przy onboardingu | sprzeczność: przy wymianie wybiera z propozycji (T l.84). Oba twierdzenia od tej samej osoby, o różnych sprawach | T l.68–70, l.84 |

### Zakończenia

| Zakończenie | Rodzaj | Dowód |
|---|---|---|
| zwrot dotarł | dobre | T l.96 |
| koszt pokryty przez pracownika / potrącenie | złe | E |

### Obietnice, termin

Brak. „Komputer czeka na pracownika" bez liczby (E).

---

## Między procesami

| Proces | Fakty / odrzucone | Reguły z odmową | Bramy | Zakończenia | Obietnice |
|---|---|---|---|---|---|
| życie komputera | 18 / 7 | 4 z E (I1, I5, I6, I7), 3 z wniosku | 4 | 4, jedno złe | 0 (1 dostawcy, `unverified`) |
| sprzęt dla osoby | 2 (+4 otwarte) / 1 | 0 | — | 2, jedno złe | 0 |

### Gotowość

- **Gotowe do pierwszego kontraktu:** proces 1 w kształcie agregatu `Computer` — fakty, I1–I4, zakończenia,
  odczyty. Brak obietnic nie przeszkadza.
- **Do decyzji przed pisaniem:** kształt przebiegu (A/B/C wyżej) — to praca nad biblioteką, do `PLAN.md`.
- **Wymaga kolejnego przejścia:** proces 2 — czy to osobny kontrakt, czy tylko odczyt po pracowniku.
