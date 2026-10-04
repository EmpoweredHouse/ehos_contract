# Usprawnienia dashboardu kontraktów — notatki robocze

Plik roboczy, poza gitem. Ekran: Graph (`/dashboard/graph`). Źródła: `sandbox/lib/rehmed/domain.ex` (domena)
i `sandbox/lib/rehmed/contracts/*.ex` (kontrakty).

## 1. Mapa kontekstów — kliknięcie otwiera panel szczegółów

**Pomysł:** klik w kontekst albo system zewnętrzny na mapie → panel boczny ze szczegółami tego elementu.

**Kontekst** (np. „Umawianie i zasoby”) — źródło: `context` w `domain.ex`

- etykieta, poddomena, źródło w materiale
- pojęcia (`term` wewnątrz `context`): definicja, czego unikać i dlaczego, tłumaczenia
- relacje z innymi kontekstami (`relation`), z parami słów (`terms:`)
- kontrakty w tym kontekście (`context: …` w `use EhOsContract.Contract`)
- encje tego kontekstu (`entity`, np. „Usługa” z polem „Raportowana do P1” w Konfiguracji)

**System zewnętrzny** (np. P1) — źródło: `external` w `domain.ex`

- kierunek, jak wygląda jego niedostępność, operacje

**Ocena:** warto. Mapa pokazuje dziś same nazwy, a słownika — najważniejszej treści kontekstu — nie ma
w webie nigdzie. Szczegóły są tam, gdzie patrzysz, a ekran nie rośnie. Tylko web: węzły mają już
identyfikatory z rodzajem i nazwą (`context_scheduling`). Kliknięcia obsługuje nasz skrypt, nie Mermaid
(polityka bezpieczeństwa EHOS-a).

## 2. Sekcja „Aktorzy” pod mapą kontekstów

**Pomysł:** opis wszystkich aktorów domeny w jednym miejscu. Dziś aktorów widać tylko przy jednym
procesie naraz (żółte prostokąty niżej na ekranie).

**Ocena miejsca:** dobre — aktorzy, jak mapa, należą do całej domeny, nie do procesu.

**Forma:** tabela pod mapą, ludzie i systemy osobno.


| Aktor    | Rola w EHOS        | Za co odpowiada  | Źródło   |
| -------- | ------------------ | ---------------- | -------- |
| Recepcja | `rehmed.reception` | `responsibility` | `source` |


- systemy zamiast roli: za jakim systemem stoją (`backed_by`) i kontekst
- klik w wiersz → ten sam panel boczny: wszystko, co rola może, pogrupowane po kontraktach (komendy,
query, zapisywane fakty), nazwy uprawnień jak w EHOS-ie, procesy, za które odpowiada (`accountable:`)

Źródło: `actor` w `domain.ex`; co może — `by:`, `recorded_by:`, `accountable:` w kontraktach.
Ten sam panel otwiera klik w aktora (żółty prostokąt, np. „Specjalista”) na „Declared versus observed,
this process”.
W sandboxie opis (`responsibility`) ma tylko Manager — do dopisania jako dane testowe.

## 3. Graf systemu — etykiety zdarzeń na strzałkach

**Pomysł:** na strzałkach między kontraktami etykieta zdarzenia zamiast nazwy technicznej —
„Pacjent wyszedł z gabinetu” zamiast `visit_completed`.

Źródło: etykieta `event` w kontrakcie nadawcy (np. `scheduling.ex`: `event :visit_completed, "Pacjent wyszedł z gabinetu"`); strzałka powstaje z `consumes` u odbiorcy. Rysuje to `graph/system.ex` w silniku.

**Ocena:** warto — to jedyny tekst na tym grafie, którego właściciel procesu nie przeczyta.

**Decyzja:** opcja (flaga) w `graph/system.ex`, z której korzysta tylko web. Bez flagi wszystko rysuje się
jak dziś — `mix eh_os_contract.graph` i reszta silnika bez zmian.

## 4. „Contract status” — co jest jednym przebiegiem

**Pomysł:** obok „Runs in this period” dopisek, czego dotyczy liczba: „one run = one visit (`visit_id`)”,
„= payer × period (`payer_id`, `period_id`)”. Źródło: `correlate` w `process` kontraktu.

**Ocena:** objaśnia odpowiedź, nie dodaje piątego pytania — pasuje do ekranu zgodności. Kto odpowiada, jak
często i termin już tam są. Osobnej karty procesu na ekranie Graph nie robimy; usługi domenowe pomijamy.

## 5. „Declared versus observed, this process” — pełny automat

Automat to fioletowy prostokąt (np. „Pogoń za dokumentacją wizyty”), zegar to szara pigułka
(np. `documentation_due`). Źródło: `process_manager` w kontrakcie. Rysuje `graph/contract.ex` — flaga dla
webu, jak w punkcie 3.

- **Start:** strzałka „uruchamia” od zdarzenia startowego do automatu — „Pacjent wyszedł z gabinetu” →
„Pogoń…”. Dziś to zdarzenie stoi bez strzałek. Źródło: `starts_on`.
- **Koniec:** bez strzałki wstecz — oznaczenie pod zdarzeniem, które zatrzymuje automat: „Zamknięto wizytę
przez specjalistę” + linijka „ends «Pogoń za dokumentacją wizyty»”. Źródło: `ends_on`.
- **Czas zegara:** na pigułce — „documentation_due · after 24 h”, a dla zegara z `at:` „next_month · at
check_at”. Źródło: `timer … wait:` albo `at:`. Zegarów może być wiele, każdy ma swoją pigułkę.



## 6. Panel po kliknięciu w komendę albo zdarzenie

**Pomysł:** klik w niebieski (komenda) albo pomarańczowy (zdarzenie) prostokąt na „Declared versus observed,
this process” i na grafie agregatu → panel boczny z tym, czego nie ma na rysunkach.

- **Komenda** (`command`): kto może wydać (`by:`) i nazwa uprawnienia w EHOS-ie (`rehmed.close_visit_clinically`),
zawężenie (`scope:`), pola.
- **Zdarzenie** (`event`): pola, kto je zapisuje (`recorded_by:`), czy kończy przebieg (`terminal`), od jakiego
systemu zależy (`depends_on:`), kto je odbiera (`consumes`, reakcje), czy wychodzi do innej aplikacji
(`publish`).

Bez `source`, bez listy `emits` (są strzałki), bez scenariuszy (punkt 8).

**Pole — tak samo w każdym panelu, gdzie są pola** (komenda, zdarzenie, odpowiedź query, model odczytu, stan):

- nazwa, typ, etykieta, wymagane, wartość domyślna;
- **dane osobowe:** „dane osobowe pacjenta — w logu szyfrowane, znikają po jego usunięciu” (`personal:`) albo
„wskazuje pacjenta — w logu jawnie” (`subject:`); typ osoby z `subject` w `domain.ex`. Zamiast osobnej listy
danych osobowych dla całej domeny;
- **typ będący wartością domeny:** jej lista wartości z etykietami („Karta / Gotówka / Przelew / Bon”) i
jednostka („Kwota, w groszach”) — źródło: `value` w `domain.ex`;
- **pole wskazujące encję:** „identyfikator: Usługa” — źródło: `{:id, :service}` i `entity` w `domain.ex`.



## 7. Polskie etykiety etapów w danych sandboxa

**Pomysł:** `stage :documentation, "Dokumentacja"` itd. w kontraktach sandboxa, żeby „Declared shape”
pokazywał „Wyjście pacjenta / Dokumentacja / Zamknięcie” zamiast `departure / documentation / closing`.
Silnik już pokazuje etykietę etapu, gdy jest — zmiana tylko w danych testowych.

## 8. Scenariusze po kliknięciu w „N scenarios” na grafie agregatu

**Pomysł:** klik w napis „1 scenario”, „2 scenarios”, „may be refused · 1 scenario” → panel ze scenariuszami
tej ścieżki, z treścią: stan wyjściowy (zdarzenia z danymi), polecenie z danymi, wynik (zdarzenia z danymi
albo „odrzucone: <treść reguły>”).

Źródło: `scenario` w kontrakcie. Które scenariusze należą do której ścieżki, liczy dziś silnik
(`graph/unit.ex`) — wystawi to jako funkcję, żeby liczba na rysunku i lista w panelu się nie rozjechały.
Model i wersje bez zmian.

## 9. Panel automatu i polityki

**Pomysł:** na „Declared versus observed, this process” przy automacie (fioletowy) i polityce linijka
„N scenarios” (także „0 scenarios”) — widać, że da się kliknąć. Klik → panel:

- **reguły** — wszystkie: `constraint`, a przy automacie też `invariant`. Np. polityka w Sprawozdawczości:
„Do P1 zgłaszamy tylko zamknięcia usług raportowanych do P1; pozostałe pomijamy”. Dziś nigdzie;
- **dostarczenie i idempotencja** — jedna linijka: w tej samej transakcji czy później (`delivery:`), po czym
rozpoznaje powtórkę i kto pilnuje (`idempotency: [key:, owner:]`);
- **scenariusze z treścią:**
  - automat — pogrupowane po tym, co go budzi: start, zegar, zdarzenie w trakcie. Każdy: tytuł, stan wyjściowy
  z danymi, wynik (wydaje komendę z danymi / nastawia albo kasuje zegar / kończy się / co pamięta po tym);
  - polityka — zdarzenie z danymi → wydaje komendę z danymi albo nic; reguła, którą ilustruje.

Źródło: `process_manager` / `policy` i `scenario` z `scope :<nazwa>` w kontrakcie. Scenariuszy reakcji nie ma
dziś nigdzie — ani na rysunkach, ani w liczniku „Contract status”. Napis na prostokącie przez tę samą flagę
co punkt 3.

## 10. Panel query

**Pomysł:** klik w query na „Declared versus observed, this process” (np. „Zestawienie dnia dla recepcji”
w Rozliczeniach; z linijką „N scenarios” jak w punkcie 9) → panel: parametry (nazwa, typ, wymagany), kto może
pytać i nazwa uprawnienia w EHOS-ie, z jakiego modelu odczytu czyta, lista czy jeden wiersz, po czym jest
zawężana, pola odpowiedzi (jak w punkcie 6) i scenariusze: parametry → oczekiwane wiersze.

Źródło: `query` w kontrakcie (`params`, `by:`, `reads:`, `returns:`, `scope:`); pola odpowiedzi to pola
modelu odczytu, z którego query czyta. Parametry query nie mogą być osobowe — DSL nie ma tam takiej opcji.

## 11. Panel efektu

**Pomysł:** klik w efekt na „Declared versus observed, this process” (np. „Wyślij zgłoszenie do rejestru P1”
w Sprawozdawczości) → panel: na jakie zdarzenie reaguje, który system i **którą operację** woła
(`submit_report` w P1), jego reguły (`constraint`), dostarczenie i idempotencja (jak w punkcie 9).

Źródło: `effect` w kontrakcie (`handles:`, `calls:`, `idempotency:`, `delivery:`), operacja z `external` w
`domain.ex`. Dziś widać tylko prostokąt i strzałkę „calls” do P1. Efekt nie ma scenariuszy (nie da się go
uruchomić w scenariuszu).

## 12. Panel modelu odczytu

**Pomysł:** klik w model odczytu na „Declared versus observed, this process” (np. „Zestawienie dnia per metoda
płatności” w Rozliczeniach) → panel: z jakich zdarzeń się buduje, jego pola (jak w punkcie 6), które query z
niego czytają, dostarczenie (w tej samej transakcji czy później).

Źródło: `read_model` w kontrakcie (`projects:`, `field`, `delivery:`) i `query … reads:`.

---

**Plan roboczy — usunąć przed mergem.**
