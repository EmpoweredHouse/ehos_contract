# Plan pracy

Zakres produktu, warunki oceny i stan recenzji żyją w rekordzie:
`~/Projects/ai/empowered-house-context/decisions/009-pns-runtime-architecture.md`; założenia, które ten
prototyp waliduje, są w [`docs/adr/architecture.md`](docs/adr/architecture.md). Ten plik to lista
roboty i tylko tu jest aktualizowany stan.

## Handoff — stan na 25 września

Utrzymywany w miejscu, nie datowany dopisek: to jest stan **teraz**. Jeśli czytasz go i coś się nie
zgadza z repozytorium, rację ma repozytorium — a ten akapit jest do przepisania.

Repozytorium biblioteki `eh_os_contract` (kontrakt procesu, dispatch zdarzeń, sprawdzanie zgodności) i jej
dashboardu; `sandbox/` to dane testowe. **Trwa pivot do v2**: DSL na Sparku z modelem domeny w stylu ESDM
(jeden kontrakt = jeden proces), event sourcing na własnym magazynie w Postgresie, crypto-shredding. Plan
zatwierdzono 25 września. **E0, E1 (szew `EhOsContract.Model`), D10–D12 i E2 (log staje się magazynem) są w
`main`. E3 (Spark i DSL domeny) jest zrobiony na `dsl-v2/e3-spark` i czeka jako PR #6. Decyzja D13 (opcje obok
bloku `do` zostają, biblioteka generuje nakładki o jedną arność więcej) jest zapisana na `dsl-v2/e4-contract-core`,
od której rusza E4. E4–E12 nie są zaczęte.** Zachowanie v1 się nie zmieniło,
poza tym, że log jest tylko do dopisywania.

### Stan repozytorium

- `main` = `origin/main` = `6646df7`, merge [PR #5](https://github.com/EmpoweredHouse/eh-os-contract/pull/5)
  (`dsl-v2/e2-store`, E2), zmergowanego przez użytkownika 25 września. Przed nim PR #4 (`c61ce5b`, D10–D12),
  PR #3 (`bfda7c7`, E1), PR #2 (`73031d2`, hook i skill przeglądu) i PR #1 (`7ce9be2`, E0).
- Na `origin` zostały zmergowane `dsl-v2/e1-decisions` i `dsl-v2/e2-store`; lokalnie też obie.
- **`dsl-v2/e3-spark`**, od `6646df7`: 10 commitów E3 (`eb80194`..`0138890`), commit dokumentów E3, sześć
  poprawek z przeglądu przed PR (`f022dfa`..`b2175b5`) i commit z tym handoffem. Wypchnięta i wystawiona jako PR
  25 września na polecenie użytkownika jako [PR #6](https://github.com/EmpoweredHouse/eh-os-contract/pull/6);
  stan odczytaj przez `gh pr view 6`.
- **`dsl-v2/e4-contract-core`**, od `dsl-v2/e3-spark` (`9fbe323`): jeden commit z D13 i tym handoffem, tylko
  lokalnie. Jeśli PR #6 dostanie poprawki przed merge'em, tę gałąź trzeba przełożyć (`git rebase`) na nową głowę
  `dsl-v2/e3-spark`; po merge'u — na `origin/main`.
- **Worktree leży pod ścieżką `.claude/worktrees/dsl-v2-e1-model-seam-ed132e`** — nazwa z E1, bo hook sesji
  pilnował tej ścieżki; gałąź w nim to `dsl-v2/e4-contract-core`, główny checkout stoi na `main`. Hook przeglądu
  czyta HEAD `$CLAUDE_PROJECT_DIR` (głównego checkoutu), nie worktree — przy PR z E2 i E3 główny checkout był na
  chwilę odczepiony na głowie gałęzi, za każdym razem za osobną zgodą użytkownika. Nowa sesja może pracować w
  świeżym worktree; wtedy najpierw `MIX_ENV=test mix deps.get` w obu pakietach i `mix deps.get` w sandboxie.
- **Przegląd przed PR**: `.claude/settings.json` (hook `PreToolUse` odmawia `gh pr create`/`gh pr new`,
  dopóki `HEAD` nie ma notatki `git notes --ref=review`) i `.claude/skills/pre-pr-review/` (połowa autora).
  Połową recenzenta zostaje `.claude/skills/review-pr/`. Notatki są lokalne, `refs/notes/review` nie jest
  wypychane.

### Co zostało — i czyje to jest

- **Przegląd i merge PR #6 (E3) — użytkownika.** Po uwagach recenzenta: poprawka, commit, kroki 3–7
  `pre-pr-review`, a przed pushem sprawdzić, że PR jest nadal otwarty.
- **Skasowanie zmergowanych gałęzi `dsl-v2/e1-decisions` i `dsl-v2/e2-store` — użytkownika**
  (`git branch -d …`, `git push origin --delete …`), i worktree po zamknięciu sesji.
- **E4–E12 — asystenta**, według dopisku „Dopisek 25 września (2) — Etap 6” niżej. Następny krok: E4 (rdzeń
  DSL-a kontraktu pod `EhOsContract.Next.Contract`) na `dsl-v2/e4-contract-core`. **Pierwszy commit E4 to
  nakładki z D13 i testy ich dwóch warunków** (opis E4 w dopisku); jeśli któryś padnie — stop i pytanie do
  użytkownika, nie obejście.
- **Lista zmian do `eh-os`** (odwrócenie D-01, zawężenie D-15, outbox, G-16, pytanie o transport v1) —
  użytkownika; jest w „D10–D12 — skąd się wzięły” w dopisku Etap 6.
- **Trzy pytania z E1 do użytkownika** (szczegóły: „E1 — co szew ujawnił” w dopisku Etap 6):
  naprawić niedeterministyczną kolejność linii `owner` w `mix eh_os_contract.check` (jedno `sort_by`,
  osobny commit) — kiedy; wpis o `EhOsContract.Model` w `CHANGELOG.md` teraz czy dopiero w E6;
  zasiane w E1 dwa przebiegi `open_month` zostają w bazie dev — czy to przeszkadza. E2 dokłada do drugiego
  pytania nową migrację i moduły `Clock` i `Store` (ustalenie 8 w „E2 — co wyszło”).
- **Publikacja na Hex — użytkownika**, decyzja niepodjęta. W repozytorium są tagi `v0.2.0` i `v0.2.1`; śladu
  publikacji nie ma.
- **F1 i F2** (`docs/adr/contract-v2.md` §16: skąd suma wizyty, który dzień dostaje korekta) oraz dziesięć
  usterek z dopisku „Dopisek 25 września” — do właścicieli procesów, przez użytkownika. Nie blokują E2–E8.

### Co przeczytać najpierw

1. `CLAUDE.md` — reguły, których złamanie kosztuje najwięcej: język kodu, `boundary`, zakaz pisania do repo
   kontekstu, brama bez `tail`, pułapka `MIX_ENV=test mix run`, dzielenie słów w zsh.
2. `docs/adr/contract-v2.md` — czym v2 ma być: DSL (§4), co generuje kontrakt (§5), katalog reguł (§6),
   zmiana zdarzenia a subskrybenci (§7), model jako dane (§9, z poprawką z E1), schemat magazynu (§10),
   dispatch (§11), konsumenci (§12), crypto-shredding (§14), decyzje (§16), co v2 odwraca w rekordzie v1
   (§18).
3. Dopisek „Dopisek 25 września (2) — Etap 6” niżej: etapy, kryteria odbioru z kontrolami, losy fikstur i
   testów, tryb pracy, a w nim **„E1 — co szew ujawnił”**.
4. Dopisek „Dopisek 25 września” niżej — mapa czterech kontraktów na ESDM: dowody za pivotem i dziesięć
   usterek, których porty nie naprawiają.
5. `packages/eh_os_contract/docs/contract.md` — DSL v1, który jest zastępowany; tabela „What refuses to
   compile” to punkt wyjścia reguł L2.
6. Przed E4: opis E4 w dopisku Etap 6 (z pierwszym commitem D13), D13 w v2 §16, v2 §4.2–4.6 (encje i przykłady
   kontraktu), §5 (co generuje kontrakt), §6 (reguły N, F, A, C, R, K) i „E3 — co wyszło”. Kod, na którym E4
   stoi: `lib/eh_os_contract/domain/{dsl,rules,build}.ex` (wzorzec rozszerzenia Sparka, reguł w jednym
   transformerze i modelu z digestem; `Rules.type_problems/2` i `Build.typespec/1` są do ponownego użycia),
   `test/support/dsl_case.ex` (kompilacja z `:debug_info`, stąd `async: false`), `lib/eh_os_contract/model.ex`
   (`fetch/1` zwraca model skompilowany). Log pisze się tylko przez `EhOsContract.Store`, czas daje
   `EhOsContract.Clock`.
7. Przed pierwszym PR: `.claude/skills/pre-pr-review/SKILL.md` — bez notatki przeglądu hook odmówi.

### Komendy

```bash
docker compose up -d && cd sandbox && mix ecto.setup && mix check
```

Postgres słucha na **5433**. Przed commitem liczy się kod wyjścia bramy, nie `tail`:
`out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"` — powód w `CLAUDE.md`, tak samo jak
ratunek dla zaśmieconej bazy testowej. Gdy krok formatowania nie zgadza się z CI, skasuj
`_build/<env>/lib/<app>/.mix/cached_dot_formatter` (zapisane w `sandbox/mix.exs` i `ci.yml`).

**W świeżym worktree** `mix ecto.setup` w `sandbox/` pobiera zależności tylko sandboxa. Brama pada wtedy na
pakiecie silnika z `Unknown dependency :ecto_sql given to :import_deps`. Przed pierwszą bramą trzeba
uruchomić `MIX_ENV=test mix deps.get` w `packages/eh_os_contract` i w `packages/eh_os_contract_web`.

### Ostatnia pełna weryfikacja

- **Lokalnie, 25 września**, na `dsl-v2/e3-spark` (`b2175b5`, a potem ten commit, który zmienia tylko
  dokumenty): brama wyżej → **EXIT=0**. Sandbox: 44 testy (42 + 2 z E3), 0 padnięć, `eh_os_contract.check` 0 błędów,
  5 ostrzeżeń, 23 informacje. Pakiet silnika: 491 testów (454 z `main` + 37 z E3), 0 padnięć, `check` 0 błędów,
  8 ostrzeżeń, 16 informacji. Pakiet web: 31 testów, 0 padnięć. Te same liczby `check` co na `main`.
- **CI**: PR #5 — przebieg `36122716953` na `b4e4a43`; `main` po merge'u — przebieg `36123110982` na
  `6646df7`. Oba `success`, więc druga baza testowa silnika (`eh_os_contract_test_commits`) powstaje na CI sama,
  z aliasu `test`. CI na PR z E3 (pierwszy przebieg ze Sparkiem) odczytaj przez `gh pr checks`.

### Otwarte pytania

- **D1–D9** (`docs/adr/contract-v2.md` §16) przyjęte z planem 25 września, z rekomendacjami; **D10–D12**
  przyjęte po E1 tego samego dnia. Nowe pytania w §19: `scope` dla komend, transport v1 między kontenerami. Każde można
  otworzyć ponownie; ponowne otwarcie to notka z datą w §16. Najbardziej brzemienne: D6 (`recorded_by` dla
  15 zdarzeń bez komendy) i D7 (przynależność cudzych zdarzeń do przebiegów przez `_event_runs`).
- **Trzy pytania z E1** — wyżej, w „Co zostało”.
- **Upcastery:** kontrakt callbacku — jeden na typ i wersję czy łańcuch — rozstrzyga etap, który pierwszy go
  potrzebuje (§19).
- **H177** z materiału Rehmedu (przekazanie wizyty jako komenda warunkowa, zamrożenie ceny przy rozliczeniu)
  przeczy DEC-18, na którym stoi `visit_handed_over`; czeka na ratyfikację u klienta.
- **API dla EHOS-a** poza nazwanym schematem `Model.to_data/1` (E10): transport i wersjonowanie specyfikuje
  EHOS. `EhOsContract.Model` z E1 nie ma jeszcze `to_data/1`: jego deklaracje v1 niosą krotki (MFA reguł,
  `within`), więc nie są JSON-em.

### Zgoda i stałe uprawnienia

**Ten blok jest do skasowania. Skasowanie go cofa uprawnienie — nie migruje ono samo między sesjami.**

Zatwierdzając plan 25 września, użytkownik zgodził się na pracę na gałęziach etapów `dsl-v2/eN-*` z
commitami bez pytania, przy zielonej bramie na każdym commicie (D9), oraz na zapis stanu do `PLAN.md` i
założeń do `docs/adr/contract-v2.md`. Tego samego dnia jednorazowo zlecił wypchnięcie gałęzi E0 i otwarcie
PR #1, a po jego merge'u — drugiego PR z tym, co do #1 nie weszło, razem z hookiem i skillem przeglądu.
Poza tym **nie** było zgody na `git push`, PR, merge, tag ani publikację na Hex — w szczególności nie
dla kolejnych etapów. Zlecając E1 (25 września), użytkownik powtórzył to samo: commity na `dsl-v2/e1-*` bez
pytania; push, PR, merge i tag tylko na jego wyraźne polecenie; przed PR skill `pre-pr-review`. Po merge'u
E1 jednorazowo zlecił wypchnięcie `dsl-v2/e1-decisions` i PR z D10–D12, a po E2 — `pre-pr-review` i PR z
`dsl-v2/e2-store`.

### Język

Rozmowa po polsku. Kod, moduledoki, komentarze, nazwy testów i komunikaty bram — po angielsku;
`docs/adr/` i `README.md` po angielsku; `PLAN.md` i `CLAUDE.md` po polsku. Pełna reguła — `CLAUDE.md`; od E3
lista miejsc, w których wolno pisać po polsku, rośnie (dopisek Etap 6).

---

## Dopisek 25 września (2) — Etap 6: pivot do DSL v2, plan wykonania

Plan zatwierdzony 25 września. **Projekt jest w [`docs/adr/contract-v2.md`](docs/adr/contract-v2.md)** —
założenia startowe v2 po angielsku, cytowane w kodzie jako `v2 §N`: DSL na Sparku z referencją encji, co
generuje kontrakt, pięć warstw sprawdzeń z katalogiem reguł, zmiana zdarzenia a subskrybenci, model jako
dane, magazyn i jego schemat, dispatch, konsumenci, crypto-shredding, zgodność na nowym logu, decyzje D1–D9,
znaleziska F1–F3, ryzyka i lista tego, co v2 odwraca w rekordzie v1. Tu jest tylko wykonanie: etapy,
kryteria odbioru, losy testów i fikstur, stan.

Decyzje, w skrócie (pełne w v2 §2 i §16): cały pivot etapami; **event sourcing od razu**; **Spark** bez
spike'u porównawczego; **własny event store w Postgresie** (zaakceptowany po porównaniu z EventStore
Commanded — v2 §2); **crypto-shredding**; ESDM jako specyfikacja funkcjonalności, **bez integracji**; zgodności
wstecz brak. Wymóg z rozmowy, doprecyzowany przez właściciela: zmiana struktury zdarzenia w jednym procesie
jest weryfikowana przez kompilator u każdego subskrybenta (v2 §7).

### Strategia

- **Strangler w pakiecie.** Najpierw szew `EhOsContract.Model`, przez który czytają wszyscy czytelnicy. v2
  rośnie obok v1: nowe nazwy nie kolidują (`Domain`, `Store`, `Dispatcher`, `Scenario`, …), a jedyny kolidujący
  moduł żyje do cięcia jako `EhOsContract.Next.Contract` — przemianowanie dotknie wtedy około 10 miejsc
  zamiast około 80. Każdy kontrakt sandboxa jest **zastępowany jednym commitem**, nigdy duplikowany; v1 znika
  w osobnych commitach usuwających; 0.3.0 na końcu.
- **Reguły każdego commita.** Brama zielona. Test v1 znika tylko razem z testem v2, który przejmuje to samo
  zachowanie — mapowanie w opisie commita. Dodawanie, usuwanie i przemianowania się nie mieszają. Delta
  `eh_os_contract.check` jest raportowana i każda nowa linia wyjaśniona. Rodzaj deklaracji wchodzi razem ze
  swoim czytelnikiem. Kontrakt nigdy nie jest naraz v1 i v2 — pilnuje tego już `check_names_declared_twice`.
- **Porty tłumaczą, nie naprawiają.** Dziesięć usterek z dopisku niżej zostaje pytaniami. Wyjątki: usterka 2
  (okno TaxVision do `unverified`) i usterka 5 (`open_month` ma źródło w US-MON-01) — jednolinijkowe commity z
  cytatem. Gdzie nowy DSL wymusza wybór, rozstrzyga materiał warsztatowy i jest cytowany.
- **Tryb pracy.** Gałąź na etap, `dsl-v2/eN-<nazwa>`, odgałęziona od poprzedniego etapu. Brama na każdym
  commicie przez `out=$(mix check 2>&1); rc=$?` — nigdy przez `tail` (powód w `CLAUDE.md`). **Push, PR, merge,
  tag i Hex są po stronie użytkownika.** Testy trafiają od razu do docelowych katalogów (`test/dsl/`,
  `test/runtime/`).

### Etapy

**E0 — Podstawy (dokumenty).** Commit mapy z 25 września; `docs/adr/contract-v2.md`; ten dopisek; nowy
handoff na górze pliku. **Zrobione 25 września** — patrz handoff.

**E1 — Szew `EhOsContract.Model` (tylko v1, bez zmiany zachowania).** Adapter v1 buduje kanoniczne dane
(v2 §9, podzbiór, który v1 ma). Czytelnicy przechodzą po jednym na commit: `Trace`, `Run`, `Conformance`,
`Graph`, `Deployment`, `Check` (i task `check`), `AsyncAPI`, `Brief`, webowy `Live.Graph` (dziś jedyny, który
woła `contract.processes()` bezpośrednio). Adapter, około 100 linii, znika przy cięciu; `Model` zostaje — to
też eksport dla EHOS-a.
*Odbiór:* żaden istniejący test nie jest edytowany; grep pokazuje, że `events/0`, `traces/0`, `processes/0` i
reszta funkcji kontraktu są wołane tylko przez adapter; `mix eh_os_contract.report` i
`mix eh_os_contract.graph --overlay --mermaid` dają identyczne bajty na bazie dev przed i po.
**Zrobione 25 września** na `dsl-v2/e1-model-seam`, 14 commitów (`6a9baf4`..`b5e9a79`) plus dwie poprawki z
przeglądu przed PR, wystawione jako PR; kryteria odbioru spełnione — szczegóły i ustalenia w „E1 — co szew ujawnił” niżej.

**E2 — Log staje się magazynem, w miejscu (V03).** `EhOsContract.Store` i `Store.Postgres` (v2 §10): globalna
blokada, strumienie, pozycja, tagi, tabela `_commands`, trigger „tylko dopisywanie”. V03 **zmienia tabelę w
miejscu i zostawia jej nazwę**, bo `Migrations` czyta numer wersji z komentarza tej tabeli; wygenerowane
migracje w trzech katalogach `priv` w tym samym commicie. Emiter v1 dopisuje przez `Store` bez warunku.
Bezpośrednie `insert!(%EhOsContract.Event{})` w 10 plikach testów (policzone 25 września grepem) przechodzą na
jednego pomocnika. Trzy pliki cofają `occurred_at` przez `update_all` (`report_test`, `run_test`,
`deployment_test`) — trigger na to nie pozwoli, więc emiter v1 przyjmuje `occurred_at` w `ctx` jako zegar
wstrzykiwany. Jeśli to okaże się większe niż kilka linii, trigger wchodzi dopiero w E6; decyzja zapisana tu.
*Odbiór:* testy czytające log (trace, trace_edges, trace_granularity, run, conformance, conformance_wire,
report, graph, deployment, dependency) przechodzą bez zmian asercji; test konfliktu wersji plus kontrola,
która przechodzi; czytelnik „pozycja > checkpoint” nie gubi zdarzenia przy dwóch transakcjach commitujących
poza kolejnością sekwencji; 50 równoległych dopisujących daje wersje 1..N bez dziur; UPDATE, DELETE i TRUNCATE
odrzucone; suita behaviouru `Store`, którą może uruchomić każda implementacja; V02 ↔ V03 w obie strony.
**Zrobione 25 września** na `dsl-v2/e2-store`, 7 commitów (`5db56e5`..`246dd11`) plus cztery poprawki z
przeglądu przed PR, wystawione jako PR. Trigger
„tylko dopisywanie” **wszedł w E2**; zegar wstrzykiwany to `EhOsContract.Clock` w zasięgu procesu, nie
`occurred_at` w `ctx` — powód i reszta ustaleń w „E2 — co wyszło” niżej.

**E3 — Spark i DSL domeny.** `{:spark, "~> 2.7.3"}`, `sourceror` tylko dev/test. Rozszerzenie `Domain`
(v2 §4.2): transformery (reguły D1–D5), model, generowany moduł typów `Values`, digest domeny. Brama pakietu
dostaje `mix spark.formatter --extensions … --check`; `.formatter.exs` eksportuje
`spark_locals_without_parens`; eksporty `boundary` (`{Domain.Dsl, []}`, `Domain`, `Model`). `CLAUDE.md`: lista
miejsc, w których wolno pisać po polsku, rośnie o `term`, `definition`, `avoid`, tłumaczenia, `where` i opisy
scenariuszy. Poprawka ADR: akapit o Ashu w design-rationale.
**Ten etap jest zarazem testem właściwości Sparka; porażka którejkolwiek wraca do użytkownika przed E4:**
każda reguła D ma test `Spark.Error.DslError` z komunikatem i plikiem:linią (w `.exs` potrzebne
`Code.put_compiler_option(:debug_info, true)`); przestawienie deklaracji nie zmienia wersji; moduł domeny
kompiluje się pod ścisłym `boundary` sandboxa z `--warnings-as-errors`; formatter działa u konsumenta przez
`import_deps`.

**Zrobione 25 września** na `dsl-v2/e3-spark`, 10 commitów (`eb80194`..`0138890`), niewypchnięte. Wszystkie
cztery właściwości Sparka przeszły; jedno zastrzeżenie wraca do użytkownika przed E4 — „E3 — co wyszło” niżej.

**E4 — Rdzeń DSL-a kontraktu, pod `EhOsContract.Next.Contract`.** `aggregate`/`dcb`, `identity` (wstrzykiwana),
`state`, `invariant`, `command`, `event` (z `recorded_by`), grupy `stage`, `process` (`correlate`, `include`,
`promise`, `cadence`, `deadline`), pola i typy (v2 §4.3), budowa modelu i digestów, reguły L2 (v2 §6: N, F, A,
C, R, K), a od D10–D11 (v2 §16) także `scope` na aktorze i query, `publish` oraz `consumes "<nazwa>"` z polami
— same deklaracje i ich reguły L2, bez runtime'u. Zmyślona fikstura `UniversalityGate` przepisana na nowy DSL; fikstury testów to moduły inline poza
skanem rejestru (wzorzec z `check_keys_test`).
**Pierwszy commit E4 (D13, v2 §16, decyzja użytkownika z 25 września): nakładki o jedną arność więcej.** Dla
każdej encji, która przyjmuje blok, biblioteka generuje z definicji encji makro `nazwa(args…, opts, do: block)`
→ `nazwa(args…, opts ++ [do: block])` (Spark czyta blok z `opts[:do]`; sprawdzone na `context` w E3). Najpierw w
DSL-u domeny (`context`, `term`, `value` — tam, gdzie encja ma encje zagnieżdżone), potem w kontrakcie. W tym
samym commicie testy warunków D13: błąd DSL-a wskazuje plik:linię deklaracji, nie nakładki; formatter u
konsumenta zostawia czteroargumentowy zapis bez nawiasów (arności nakładek eksportowane obok
`spark_locals_without_parens`, bo `mix spark.formatter` ich nie widzi); test w sandboxie na `Rehmed.Domain`
przepisanym do zapisu z §4.5 (`context …, subdomain: … do term … end`). **Jeśli pierwszy albo drugi warunek
padnie — stop, wariant A (opcje w bloku) i pytanie wraca do użytkownika.**
*Odbiór:* test na każdą regułę L2 i kontrola, która się kompiluje; złoty test modelu; słownik przypięty
testem, wyprowadzany z rozszerzenia, a nie z ręcznej listy; przykłady z v2 §4.5–4.6 kompilują się w zapisie,
w którym są napisane (poza poprawkami z D10–D12).

**E5 — Generowanie kodu, wiązanie, scenariusze, L3.** Struktury i behaviours (v2 §5), `EhOsContract.Implementation`
z makrami `emit`/`reject`/`issue` i `@before_compile`, `ScenarioCase` (zastępuje `ContractExample`, zachowuje
semantykę podciągu; reguły S, w tym S8 — inwariant bez scenariusza odmowy się nie kompiluje), kompilator Mixa
`compile.eh_os_contract` (reguły X, w tym X5–X6 — subskrybenci). Pomocnik testów bram zastępuje
`refute_compiles/2`: `Code.compile_string/1` w `Code.with_diagnostics/2` z rescue, przyjmuje
`Spark.Error.DslError`, `CompileError` albo diagnostykę poziomu error i sprawdza fragment komunikatu **oraz**
plik użytkownika. Poprawka ADR: §18.
*Odbiór:* implementacja fikstury kompiluje się pod `--warnings-as-errors`; test `CompileError` z plikiem:linią
na każdą regułę L4; usunięcie scenariusza z odmową psuje kompilację i nazywa inwariant; literówka w `by:` psuje
zwykłe `mix compile`; `mix xref graph --label compile-connected` nie pokazuje krawędzi kontrakt →
implementacja; **na parze zmyślonych kontraktów jednej aplikacji (wydawca, subskrybent): usunięcie pola
konsumowanego zdarzenia albo zmiana jego typu psuje `mix compile` z błędem wskazującym obie strony (od D11 nie ma
już `public: true` do cofnięcia) — kontrole:
dodanie pola opcjonalnego się kompiluje, a subskrybent, który zmienionego pola nie używa, kompiluje się dalej.**

**E6 — Dispatch synchroniczny i przejście VisitSettlement.** `Dispatcher`, `Codec`, `Capability`, idempotencja,
ponowienia, projekcje i polityki inline, `record/3` (D6), wiersze `_commands` (v2 §11–12); query przez tę samą
ścieżkę autoryzacji co komendy, ze `scope` i sprawdzeniem zwróconych wierszy (D10), i `EhOsContract.Plug`
wystawiający komendy i query modelu po HTTP. Jeden commit
zastępuje stary kontrakt VisitSettlement, `Rehmed.Settlement.decide/1` i `rehmed_contract_examples_test`
nowym kontraktem, domeną, implementacją i testem scenariuszy (v2 §4.5). `@version "0.3.0-dev"`, CHANGELOG
„Unreleased” — od tego commita wersje kontraktów się ruszają. Na każdym skillu baner „opisuje v1”. Poprawki
ADR: „historia, nie sourcing” i wiersz o Commanded (design-rationale), §7–8.
*Odbiór:* cztery scenariusze przechodzą; decyzja zwracająca niezadeklarowane zdarzenie rzuca wyjątek, a magazyn
się nie zmienia — kontrola: zadeklarowane zostaje dopisane; wyjątek w projekcji inline wycofuje dopis; odmowa
uprawnień niczego nie zapisuje; query o wartość `scope` spoza grantu jest odrzucone, zanim ruszy implementacja,
a implementacja zwracająca cudzy wiersz jest zatrzymana — kontrola: wartość z grantu przechodzi; konflikt jest
ponawiany; ten sam klucz idempotencji zwraca te same pozycje;
delta `check` w sandboxie dotyczy tylko linii VisitSettlement.

**E7 — Runtime asynchroniczny, fikstury, zgodność.** Efekty (Oban, joby tylko z identyfikatorami),
uporządkowane subskrypcje, process managery i timery, przebudowa, `_event_runs` (D7), nowe źródła zgodności:
w toku, padające, pokrycie scenariuszy (v2 §12–13). Wersja okablowania liczona z kontraktu i implementacji —
zmienia werdykt, więc linia w CHANGELOG. Fikstury przebudowane według tabeli niżej. Poprawki ADR: §9–10, §15,
wyzwalacz „jedno zdarzenie w dwóch procesach”.
*Odbiór:* te same scenariusze dają te same liczby werdyktów (np. „50 przebiegów → jedna linia raportu” z
`report_test`); „jeszcze nie” przechodzi w „nigdy” dopiero po opróżnieniu kolejki; przebudowa daje identyczne
wiersze; trujące zdarzenie zatrzymuje konsumenta dokładnie na swojej pozycji; dwóch runnerów nie bierze tej
samej paczki (prawdziwe commity, osobny schemat); odpalony timer uruchomiony dwa razy daje jeden dispatch.

**E8 — Crypto-shredding.** `subject` w domenie, `personal:`/`subject:` na polach, tabele kluczy i usunięć,
`Vault`, szyfrowanie w `Codec`, `erase/3`, `forget/2`, bramki (v2 §14). Przed TaxVision, bo
`registry_discrepancy_detected.diff` ma dziś `retain: :hash`. Poprawka ADR: retencja w §7–8.
*Odbiór:* w `payload` nie ma jawnego tekstu pól osobowych; po usunięciu odczyt daje `Erased`, snapshoty z tą
osobą znikają, `forget/2` się wykonało; `Conformance.as_data` identyczne przed i po (poza `generated_at`);
bramki odrzucają pola osobowe w kluczach; kontrola: osoba nieusunięta czyta się normalnie.

**E9 — Pozostałe kontrakty sandboxa.** Kolejność i zakres:
- **TaxVision**, dwa commity: kontrakt i domena; potem implementacje — `Taxvision.Tasks` jako polityka i
  komenda, miesiąc jako polityka i projekcja, `Taxvision.Notifications` jako polityka i efekt —
  `Taxvision.Api.open_month` przez dispatch, `identity_seam_test` i `periods_test` przepisane, liczby zapytań
  zmierzone od nowa i zapisane tu.
- **ClinicalVisit** — `consumes`/`include` przez cztery agregaty, process manager pogoni za dokumentacją, dwie
  obietnice; przypięcia `declared_shape_test` wyprowadzone od nowa; zdarzenia E-40 i E-51 tam, gdzie kładzie je
  materiał (AGG-01, CTX-01), z cytatem.
- **PayerSettlement** — DCB: warunek dopisu wchodzi do magazynu razem z rodzajem, który go potrzebuje.
- D6 dla 15 zdarzeń bez komendy (`recorded_by`); usuwane po drodze: każdy kontrakt v1, trzy moduły handlerów
  v1, MFA reguł.

*Odbiór:* wszystkie cztery kontrakty się kompilują i ich scenariusze przechodzą; w wyścigu DCB niezmiennik
nigdy nie pęka, a sprawdzenie konfliktu czyta tylko zakres klucza głównego; obietnica ClinicalVisit spełniona
przez `or_else` na zasianym przebiegu; **zmiana struktury zdarzenia konsumowanego między kontraktami sandboxa
(np. pola korelacji `visit_id` zdarzenia włączanego do ClinicalVisit) psuje kompilację kontraktu i
implementacji subskrybenta ze wskazaniem obu stron — kontrola: zmiana pola, którego subskrybent nie używa, go
nie dotyka.**

**E10 — Wyjścia.** Ostrzeżenia L5 (v2 §6) przypięte testem na wyjściu sandboxa; graf systemu (domena →
konteksty → kontrakty, krawędzie `consumes`) w `mix eh_os_contract.graph` i na `/graph`; `Model.to_data/1` z
nazwanym schematem dla EHOS-a, z uprawnieniami, i endpoint w API pakietu web; AsyncAPI z deklaracji `publish` (D11)
i OpenAPI z komend i query modelu (D10).

**E11 — Cięcie.** Osobne commity: usunięcie v1 (DSL, `Handler`, `Emitter`, `Job`, handlerowe części rejestru,
`dev/mix/tasks/eh_os_contract.docs.ex`, testy v1, `Rig`) — samo usuwanie; przemianowanie `Next` — samo
przemianowanie; zwinięcie migracji (D2) i regeneracja trzech katalogów `priv`; `docs/contract.md` z
`Spark.CheatSheet.cheat_sheet/1`, `docs_test` (bloki kodu się kompilują, także z README; wiersze tabeli bram ≤
testy bram w `test/dsl/`; niepusty opis każdej opcji) i brama uniwersalności przypięta od nowa z komentarzem z
datą (słownik wymieniony hurtem przez przejęcie ESDM, „zero nowych słów” liczy się od tego literału); READMEs,
`CLAUDE.md` („implementacje wskazują kontrakt, nigdy odwrotnie” zamiast „MFA, nigdy capture”; dashboard nie
pokazuje stanu biznesu, choć biblioteka prowadzi read modele klienta), CHANGELOG 0.3.0, pozostałe poprawki ADR
(v2 §18); skille — pięć przepisanych, `write-handler` wycofany na rzecz `write-decider` i `write-reaction`.
Opcjonalnie generator `mix eh_os_contract.gen.impl` na Igniterze. Potem weryfikacja końcowa.

**E12 — Integracja między aplikacjami (D11–D12, v2 §16).** Behaviour `EhOsContract.Bus` z adapterem lokalnym i
wspólną suitą testów adapterów; relay jako uporządkowana subskrypcja nad logiem (bez tabeli outboxu); inbox i
runner subskrybenta; capability `<nazwa>.subscribe` w `Model.capabilities/1`. Adaptery transportu (relay v1
EHOS-a, JetStream przez `gnat`) są po stronie EHOS-a; biblioteka nie zależy od NATS-a. Po E7 (subskrypcje) i E10
(eksport modelu). Poprawka ADR: §9–10 („bez zewnętrznego brokera”).
*Odbiór:* dwie aplikacje w teście na adapterze lokalnym — zdarzenie z `publish` dochodzi do polityki odbiorcy
dokładnie raz przy dwukrotnym doręczeniu; relay po restarcie wznawia od checkpointu i nie gubi zdarzenia
dopisanego w trakcie; wiadomość nie niesie pola spoza `fields`; fakt odbiorcy ma `causation_id` wiadomości;
kontrola: zdarzenie bez `publish` nie wychodzi.

### D10–D12 — skąd się wzięły i co zmieniają (25 września, po E1)

Po lekturze architektury EHOS-a (`~/Projects/ai/eh-os`, `docs/ADR.md` i `docs/ARCHITECTURE.md`; research w
`~/Projects/ai/ehos-knowledge` jest według jego własnego README podrzędny wobec `eh-os`) użytkownik przyjął
trzy decyzje, zapisane w v2 §16: **D10** query daje capability i ma `scope`; **D11** zdarzenie wychodzi do innej
aplikacji tylko przez `publish`, `public: true` znika; **D12** obce zdarzenie trafia do inboxu, a nie do logu
domenowego. Zmienione wyżej: E4, E5, E6, E10; dodany E12.

**Do przeniesienia do `eh-os` — przez użytkownika albo sesję w tamtym repozytorium; stąd tam nie piszemy:**
- D-01 („kontrakt nie obejmuje query”) — odwrócone przez D10; wraz z tym konsekwencja, że część query w OpenAPI
  jest obserwacją serwera: od D10 pochodzi z modelu.
- D-15, trzecia powierzchnia uprawnień („autoryzacja query zostaje w aplikacji”) — zawężona: jedno pole `scope`
  jest w kontrakcie, reszta zostaje w aplikacji; G-9 częściowo domknięte. Grant musi umieć nieść wartości zakresu.
- D-03 i ARCHITECTURE „Where the state lives” (wiersz „Outbox rows”) — w v2 log jest outboxem, relay trzyma
  checkpoint, tabeli outboxu nie ma.
- G-16 — punkt egzekucji autoryzacji subskrypcji w v1 to relay EHOS-a z tablicą routingu z grantów.
- Pytanie otwarte: co w v1 przenosi wiadomość między dwoma kontenerami, skoro D-03 mówi o relayu „in-process”.

### E1 — co szew ujawnił (25 września)

Stan: `EhOsContract.Model` (akcesory) i `EhOsContract.Model.V1` (adapter, 37 linii — plan zakładał około
100) w pakiecie silnika, `Model` w eksportach `boundary`. Nowy `test/model_test.exs` (22 testy, po przeglądzie 24) przypina, że
każdy akcesor zwraca dokładnie to, co funkcja, którą zastępuje — na pięciu fiksturach, razem z chybieniami i
treścią wyjątku. Żaden istniejący test nie jest zmieniony (`git diff --stat main` w `test/` pokazuje jeden
nowy plik). Brama zielona na każdym z 14 commitów; sandbox 42 testy, silnik 397 → 419 (po przeglądzie 421), web 31;
`eh_os_contract.check` bez żadnej dodanej ani usuniętej linii.

**Odbiór, jak sprawdzony.**
- Grep po wywołaniach `events/event_names/event?/event/processes/process/process_of/events_of/traces/
  externals/external/rules/rule/examples/examples_for/commands/command/commands_of/version/
  declaration_digests/__eh_os_contract__` na module w `packages/*/lib`, `packages/*/dev` i `sandbox/lib`:
  jedyne trafienia to `lib/eh_os_contract/model/v1.ex`, poza fałszywymi (`EhOsContract.event/2` to
  konstruktor emisji, `Sentence.rule/1`). Wywołań przez `apply` i capture nie ma. **Testy nadal wołają
  funkcje wygenerowane** — to wynika wprost z „żaden test nie jest edytowany”, a `model_test` pilnuje, że
  obie drogi się zgadzają.
- Bajty: przed pierwszym commitem zapisane w scratchpadzie sesji wyjścia obu komend, po każdym commicie
  porównane `cmp`. Identyczne za każdym razem. Porównanie pomija wyłącznie linie loggera hosta
  (`HH:MM:SS.mmm [info] Running EhOsContractHostWeb.Endpoint …`), które niosą zegar i pochodzą z bootu
  endpointu, a nie z taska.
- **Baza dev była pusta** (zero przebiegów), więc nakładka miała same `0x` i porównanie niewiele by
  dowodziło. Przed pomiarem zasiane dwa przebiegi `Taxvision.Api.open_month` (c-1, 2026-07 i 2026-08) przez
  `MIX_ENV=dev mix run`; te wiersze zostają w bazie dev na stałe. Ścieżki asynchronicznej celowo nie
  zasiewano: kolejkę mógłby opróżnić inny serwer dev na tej samej bazie i stan zmieniłby się między pomiarami.
- Ponad kryteria: tymczasowy worktree `main` w scratchpadzie, na tej samej bazie dev, dał identyczne bajty
  dla `graph --process <p> --mermaid` i `brief --process <p>` wszystkich czterech procesów, `graph` i
  `graph --overlay` bez Mermaida, `trace`, `check` (po posortowaniu, patrz niżej), dokumentów i indeksu
  AsyncAPI oraz `Conformance.as_data/1` każdego kontraktu. Różniło się tylko pole `generated_at`.

**Ustalenia.**
1. **Model musi nieść kolejność deklaracji.** v2 §9 mówi „kolekcje to mapy po nazwie”, a każdy czytelnik
   drukujący listę drukuje ją w kolejności deklaracji (węzły grafu, procesy w raporcie, wiersze briefu). Mapa
   zmieniłaby bajty. E1 trzyma listy; poprawka z datą w v2 §9. Digest i tak ignoruje kolejność, więc wersja
   się nie rusza.
2. **Czytelników wołających kontrakt bezpośrednio było szesnastu, nie dziewięciu.** Poza listą z planu:
   `Registry` (skan i `declared_events/commands`), `Emitter`, `Job`, `Instance`, `Handler` (bramki
   kompilacyjne), `Dependency` oraz przykład w moduledoku `ContractExample`. Kryterium „tylko adapter”
   wymagało ich wszystkich, więc przeszły czterema dodatkowymi commitami po dziewiątym czytelniku. Zdanie
   planu, że `Live.Graph` jest „dziś jedynym, który woła `contract.processes()` bezpośrednio”, było prawdziwe
   tylko w pakiecie web.
3. **Zależność kompilacyjna handler → kontrakt przetrwała.** Bramki w ciele makra `Handler` wołają teraz
   `Model`, a nie kontrakt, więc mogła zniknąć. `mix xref graph --label compile` w sandboxie jest identyczny z
   plikiem przed zmianą i po niej, więc krawędź nie brała się z wywołań funkcji kontraktu. Daje ją
   `Code.ensure_compiled!/1` albo rozwinięcie aliasu w makrze; nie sprawdzałem, które z nich. Warto to
   rozstrzygnąć w E5, gdzie implementacja ma zależeć od kontraktu przez `use`.
4. **`mix eh_os_contract.check` ma niedeterministyczną kolejność linii `owner … does not exist`.**
   `check_owners_exist` robi `Enum.group_by` do małej mapy z kluczami-atomami, a od OTP 26 taka mapa iteruje w
   kolejności indeksów atomów, nie alfabetycznie. Dodanie modułu zmienia kolejność tworzenia atomów, więc dwie
   pary linii (Rehmed w sandboxie, UniversalityGate w silniku) zamieniały się miejscami między przebiegami tej
   samej bramy. Istniało przed E1, E1 tylko to odsłoniło. Nie naprawione, bo E1 nie zmienia zachowania.
   Naprawa to jedno `Enum.sort_by` i osobny commit; do decyzji, w którym etapie. Delta `check` w opisach
   commitów jest dlatego raportowana dwojako: linie dodane lub usunięte (zawsze zero) i kolejność.
5. **Model nie jest cache'owany.** Każdy akcesor buduje mapę od nowa z literałów modułu, więc `emit` buduje ją
   cztery razy. Suita silnika: 2,7 s przed E1, 2,6 s po. Cache po module musiałby zauważać rekompilację, którą
   testy robią celowo; wróci do tematu E4, gdy model v2 będzie większy.
6. **Pakiet web zależy teraz od `EhOsContract.Model`.** W repozytorium i przez gita oba pakiety biorą ten
   sam commit, więc rozjazd jest niemożliwy. Przy publikacji na Hex wymaganie wersji silnika w webie musi
   wskazywać wydanie z `Model`. `CHANGELOG.md` nie ma jeszcze wpisu o nowym publicznym module; plan otwiera
   „Unreleased” w E6. Otwarte pytanie: czy wpis ma wejść wcześniej.
7. **Nazwy akcesorów to podzbiór v1**, nie lista z v2 §9: jest `processes/1` (kontrakt v1 może mieć kilka
   procesów), są `trace/2` i `module/1`, a nie ma `unit_of/2`, `run/1`, `capabilities/1` ani `module_for/3`,
   bo v1 nie ma tych pojęć. E4 dopisze je razem z modelem v2. `processes/1` i `events_of/2` znikną albo zmienią
   znaczenie przy cięciu.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`).** Pięć znalezisk:
1. Moduledoc `EhOsContract.Contract` wskazywał dawnych wołających funkcje generowane. **Poprawione**
   w `24c91ab`.
2. Każdy akcesor buduje model od nowa, także w pętlach (`Graph.static`, `Deployment.report`, `Emitter`).
   **Pominięte**, bo koszt jest zmierzony i mieści się w szumie (ustalenie 5 wyżej). Wraca w E4.
3. Moduł, który nie jest kontraktem, padał na `events/0` zamiast na funkcji, o którą pytał czytelnik.
   **Poprawione** w `64d3b9e`: teraz `ArgumentError` z nazwą modułu.
4. `Model.contract?/1` dawał `false` dla kontraktu jeszcze niezaładowanego. **Poprawione** w `64d3b9e`:
   najpierw `Code.ensure_loaded?/1`. Oba testy z tego commita zweryfikowane wstecz.
5. `EhOsContract.Model.` pisane raz przez alias, raz pełną nazwą. **Bez zmiany**: pełną nazwą tam, gdzie
   w pliku jest jedno wywołanie, tak jak w tych samych plikach `EhOsContract.Registry.contracts()`.

### E2 — co wyszło (25 września)

Stan: migracja V03 (`lib/eh_os_contract/migrations/v03.ex`, `current_version/0` = 3, migracja konsumenta
`20260925120000_upgrade_eh_os_contract_to_v3` w trzech katalogach `priv`), `EhOsContract.Store`,
`Store.Postgres`, `Store.Suite`, `EhOsContract.Clock`, emiter v1 i pomocnik testów dopisujący przez `Store`.
Druga baza testowa silnika, `eh_os_contract_test_commits` (`test/support/commit_repo.ex`), na testy, które
potrzebują prawdziwych commitów. Brama zielona na każdym z 7 commitów; sandbox 42, silnik 421 → 450, web 31;
`eh_os_contract.check` bez żadnej zmienionej linii.

**Odbiór, jak sprawdzony.**
- Testy czytające log (trace, trace_edges, trace_granularity, run, conformance, conformance_wire, report,
  graph, deployment, dependency): żadna asercja nie zmieniona. Zmieniły się tylko pomocnicze funkcje zasiewu
  — `run_test` i `report_test` emitują w przeszłości przez `Clock.at/2` zamiast przesuwać `occurred_at`
  `UPDATE`-em, a jedenaście plików pisze log przez `DataCase.record_event!/1` (albo `record_events!/1`).
- Konflikt wersji z kontrolą, 50 równoległych dopisujących → wersje 1..50 bez dziur, czytelnik „pozycja >
  checkpoint” przy dwóch transakcjach: `EhOsContract.Store.Suite`, uruchamiana w `test/store_test.exs` na
  `CommitRepo`. Zweryfikowane wstecz: bez blokady w `append/3` pada wyścig (naruszenie unikalności indeksu
  strumienia); bez blokady i bez triggera V03 pada też test kolejności commitów i test zapisu z pominięciem
  store'u. `store_test` pięć razy pod rząd zielony.
- UPDATE, DELETE i TRUNCATE odrzucone, każde z kontrolą: `test/store_schema_test.exs`.
- V02 ↔ V03 w obie strony, na wierszach zapisanych w kształcie V02: `test/migrations_test.exs`; zweryfikowane
  wstecz (numerowanie po czymś innym niż `occurred_at` psuje test). Poza tym `CommitRepo.reset!/0` przy
  każdym przebiegu suity migruje całą bazę w dół i w górę.
- Baza dev: V03 ponumerowała 12 zasianych wierszy 1..12 w kolejności `occurred_at`; `mix eh_os_contract.report`
  i `graph --overlay --mermaid` przed migracją i po niej identyczne bajt w bajt. **Baza dev jest teraz na V03**
  — wspólna z głównym checkoutem; kod z `main` nadal na niej działa, bo V03 niczego mu nie zabrania poza
  UPDATE/DELETE na logu, których v1 nie robi.

**Ustalenia.**
1. **Zegar w zasięgu procesu, nie `occurred_at` w `ctx`.** `report_test` cofał czas także zdarzeniom
   emitowanym przez handler asynchroniczny po `Oban.drain_queue/2`, a job buduje swój `ctx` z argumentów —
   klucz w `ctx` wołającego tam nie dociera. Przenoszenie czasu przez argumenty joba byłoby błędem poza
   testami, bo zakolejkowany handler działa później. `Clock.at/2` sięga każdego zdarzenia wyemitowanego w
   tym procesie w trakcie funkcji, łącznie z opróżnianą kolejką, i żadnego z innego procesu. Kilka linii,
   więc trigger wszedł w E2, zgodnie z regułą z opisu etapu. `Clock.at/2` poszerza precyzję do mikrosekund
   — przykład z jego własnego moduledoku padał na `:utc_datetime_usec` (osobny commit `246dd11`).
2. **Piszących log z pominięciem `emit` było jedenastu, nie dziesięciu.** Grep z planowania szukał
   `insert!(%Event{})`; `scale_edges_test` wstawiał przez `insert_all` i bez `actor`, co wyszło dopiero na
   `NOT NULL` z V03.
3. **Prawdziwe commity wymagały osobnej bazy, nie osobnego schematu.** Plan dla E7 mówi „osobny schemat”.
   Dla E2 wystarczyło drugie repo na drugiej bazie: `Store` dostaje repo w każdym wywołaniu, więc nic nie
   musiało znać prefiksu, a migracje i tak testują się na niej w obie strony. Wierszy z logu nie da się
   usunąć, więc baza jest czyszczona migracją w dół i w górę na starcie każdego przebiegu, a testy na niej
   są `async: false` i piszą pod własnymi nazwami. E7 może jej użyć zamiast schematu.
4. **Szkic v2 §10.1 miał trzy rzeczy do poprawki** — poprawka z datą w §10.1: `after` to słowo
   zarezerwowane (parametr nazywa się `after_position`); callbacki zwracają wiersze `EhOsContract.Event`, a
   nie `Recorded`, bo tak czytają wszyscy czytelnicy v1 (`Recorded` ma sens, gdy `Codec` zacznie dekodować,
   E6); warunek DCB i `read_query/2` wchodzą w E9 razem z PayerSettlement.
5. **`id` zostaje kluczem głównym schematu Ecto, choć kluczem tabeli jest `position`.** Dzięki temu żadne
   `Repo.get(Event, id)` ani `causation_id` nie musiało się zmienić. `position` i `recorded_at` są
   `read_after_writes`, a Ecto nie wstawia ich jawnie, więc kolumna tożsamości `GENERATED ALWAYS` działa także
   z `Repo.insert!/1`.
6. **Globalna blokada a testy konsumenta.** W transakcji Ecto Sandbox blokada dopisu trwa do końca testu,
   więc dwa testy `async: true`, które piszą log, czekają na siebie w całości. W tej suicie wszystkie testy
   piszące log są `async: false`, więc dziś nic to nie kosztuje; host z asynchronicznymi testami emisji
   zobaczy ich serializację. Do zapisania w dokumentacji dla konsumentów przy cięciu (E11).
7. **Poza zakresem E2, świadomie:** kolumny v1 zostają `varchar(255)` zamiast `text` z v2 §10.3 (zwinięcie
   migracji, D2, E11, dojdzie do ostatecznego kształtu); `EhOsContract.Key` z v2 §10.4 — nic w E2 nie liczy
   jeszcze identyfikatorów strumieni, pierwsze będą agregaty w E6; `eh_os_contract_commands` istnieje, ale nic
   do niej nie pisze do E6 — jest w V03, żeby E6 nie potrzebował V04.
8. **Zmiana dla konsumenta:** nowa migracja jest wymagana (`up(version: 3)`), a z nią publiczne moduły
   `Clock`, `Store`, `Store.Postgres`, `Store.Suite`. To powinno trafić do `CHANGELOG.md` przed wydaniem —
   dokłada się do pytania z E1, kiedy otworzyć „Unreleased”.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`).** Osiem znalezisk:
1. `emit!` zwracał payload odczytany z Postgresa (znacznik czasu jako tekst) zamiast zapisanego —
   **poprawione** w `2e2b0df`, test zweryfikowany wstecz na całej suicie.
2. Globalna blokada brana w środku transakcji umożliwia zakleszczenie z wierszami blokowanymi przez hosta
   albo handler — **pominięte jako zmiana kodu**, opisane w moduledoku `EhOsContract.Store` (weź `lock/1`
   przed blokadami wierszy). To cena decyzji z v2 §10.2; dotyczy każdego konsumenta, więc idzie do
   CHANGELOG razem z ustaleniem 8.
3. Emisja poza READ COMMITTED teraz rzuca — **pominięte** z tego samego powodu i tak samo opisane.
4. Pod `{:stream, …}` pola strumienia we wpisie były po cichu nadpisywane — **poprawione** w `40f13e0`.
5. Suita wspólna dla implementacji sprawdzała brzmienie komunikatów Postgresa — **poprawione** w `b0cb32b`;
   brzmienie przypięte w `store_test`.
6. `emit_all` dopisuje po jednym zdarzeniu (osobne zapytanie o blokadę na każde) — **pominięte**: to ścieżka
   v1, którą E6 zastępuje dispatcherem dopisującym decyzję jednym wywołaniem.
7. `Clock.at/2` przyjmował czas spoza UTC, który padał dopiero przy dopisie — **poprawione** w `df7d6e6`.
8. Suita wstrzykuje do modułu hosta funkcje pomocnicze — **bez zmiany**: mają prefiks `suite_`.

### E3 — co wyszło (25 września)

Stan: `{:spark, "~> 2.7.3"}` (plus `sourceror` tylko dev/test); `EhOsContract.Domain` i rozszerzenie
`EhOsContract.Domain.Dsl` z encjami v2 §4.2 — `context` (z `term`, `translation`, `avoid`), `actor`, `subject`,
`value` (typ albo `field`), `external`, `relation`; transformer `Domain.Rules` (D1–D5) i `Domain.Build` (model
`__eh_os_contract_model__/0`, digest, moduł `Values`); `EhOsContract.Model.fetch/1` zwraca model skompilowany,
gdy moduł go ma. `entity` z §4.2 pominięte — sama tabela mówi „deferred: nothing reads it yet”. W sandboxie
`Rehmed.Domain` (tłumaczenie domeny z v2 §4.5). Brama pakietu dostała `spark.formatter … --check`. Brama zielona
na każdym z 10 commitów; sandbox 42 → 44, silnik 454 → 484, web 31; `check` bez zmian.

**Właściwości Sparka, jak sprawdzone** (plan: porażka którejkolwiek wraca do użytkownika przed E4 — żadna nie
padła):
1. *Każda reguła D ma test `DslError` z komunikatem i plikiem:linią* — `test/dsl/domain_rules_test.exs`,
   16 testów odmowy i 5 kontroli; z pustą listą reguł pada dokładnie 16. Pod prawdziwym `mix compile` w
   sandboxie druga deklaracja `actor :manager` daje „D1: two actors are named :manager
   (lib/rehmed/domain.ex:36)”.
2. *Przestawienie deklaracji nie zmienia wersji* — `test/dsl/domain_test.exs`: dwa moduły z tymi samymi
   deklaracjami w innej kolejności, także zagnieżdżonymi (terminy, tłumaczenia, pola), mają tę samą wersję i te
   same digesty; zmiana jednostki jednej wartości rusza wersję i wyłącznie `value:money`.
3. *Moduł domeny kompiluje się pod ścisłym `boundary` sandboxa z `--warnings-as-errors`* — `Rehmed.Domain`;
   kontrola: wywołanie do `Taxvision.Periods` i do nieeksportowanego `EhOsContract.Migrations.V03` to
   „forbidden reference”.
4. *Formatter działa u konsumenta przez `import_deps`* — `mix format` zostawia `Rehmed.Domain` bez zmian; bez
   `:eh_os_contract` w `import_deps` sandboxa ten sam plik jest „not formatted”. Lista pochodzi z
   `mix spark.formatter`, a jej `--check` w bramie pakietu odrzuca listę bez jednej encji.

**Ustalenia.**
1. **Opcje nie mogą stać obok bloku `do`** — *rozstrzygnięte 25 września: wariant B, D13 w v2 §16*. Elixir czyta
   `command :x, "L", by: [:a] do … end` jako cztery argumenty, a makro encji Sparka ma pozycyjne argumenty i
   jedne opcje, więc taki zapis się nie kompiluje (`undefined function context/4`). Z blokiem opcje pisze się w
   środku (`subdomain :supporting`). Większość przykładów v2 §4.5–4.6 stawia opcje obok bloku. Do wyboru w E4:
   przepisać przykłady na opcje w bloku (zero kodu, zmienia wygląd każdego kontraktu) albo generować własne
   makra o jedną arność więcej (kod obok Sparka, który trzeba utrzymać i przetestować z formatterem). Poprawka z
   datą w v2 §4.2 i w akapicie o Ashu w design-rationale.
2. **Położenie błędu zależy od opcji kompilatora `:debug_info`.** Spark zapisuje adnotację tylko przy niej
   (`Spark.Dsl.Extension.macro_env_anno/2`). `mix compile` ją włącza dla `.ex`, więc konsument widzi plik:linię;
   kod kompilowany w teście z łańcucha jej nie ma. `EhOsContract.DslCase` włącza ją na czas jednej kompilacji —
   opcja jest globalna dla VM, więc przypadki z niej korzystające są `async: false`. Z tego samego powodu
   typespeki `Values` da się przeczytać w teście tylko z binarki skompilowanej z `:debug_info`.
3. **`boundary` sandboxa egzekwuje eksporty silnika, ale nie deklaracje `deps: [EhOsContract]`.** `Rehmed.Domain`
   z `deps: []` kompiluje się, nawet z wywołaniem `EhOsContract.Model` w czasie działania. Tak samo jest dziś z
   każdą granicą sandboxa — to nie E3, tylko sposób, w jaki `boundary` traktuje zależności spoza aplikacji.
   Komentarz w `sandbox/mix.exs` („a client tree reaching into the engine's internals fails to compile”) jest
   prawdziwy dla modułów nieeksportowanych, nie dla samej zależności. Do rozstrzygnięcia przy okazji: tryb
   ścisły dla zależności zewnętrznych albo zdanie w komentarzu.
4. **Wszystkie naruszenia w jednym `DslError`.** Spark ma jedno położenie na błąd, więc położenie to pierwsze
   naruszenie, a komunikat wymienia każde ze swoim plikiem:linią. v2 §6 zakłada „diagnostykę przed jednym
   raise” — ta forma to spełnia bez drukowania ostrzeżeń, które brama zamieniłaby w błędy.
5. **Źródła w `Rehmed.Domain`.** A-02, A-03, A-05 i CTX-01 mają pokrycie w repozytorium, metody płatności — w
   `E-55`. Numery CTX-05 i AGG-06 z v2 §4.5 nie występują w dystylacji w tym repozytorium; CTX-05 zostaje w
   komentarzu z adnotacją, że numer pochodzi z §4.5, a przy metodach płatności cytowane jest `E-55`.
6. **Sprawdzanie typów wartości jest publiczne** (`Domain.Rules.type_problems/2`, `built_in_types/0`,
   `Domain.Build.typespec/1`), bo E4 użyje tych samych typów dla pól kontraktu.
7. **Po drodze:** commit `6067bc1` poszedł, zanim porównanie bajtów raportu przeszło — skrypt łączył je przez
   `;`. Porównanie powtórzone po kompilacji dało identyczne bajty, więc opis commita jest prawdziwy, ale od tego
   miejsca commit stoi po `&&`.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`).** Siedem znalezisk:
1. Akcesory kontraktu wołane z modułem domeny padały na `KeyError` zamiast odmowy z E2 — **poprawione** w
   `f022dfa`.
2. Wersja domeny nie obejmowała `name:` i `language:` — **poprawione** w `18b271c` (klucz `"domain:<name>"`).
3. Ta sama relacja zadeklarowana dwa razy przechodziła D1, a w `digests` jedna nadpisywała drugą —
   **poprawione** w `e011238`.
4. Polski komentarz w `Rehmed.Domain` — **poprawione** w `595e2e4`; pliki E3 przejrzane też słowo po słowie.
5. Pola wartości przyjmowały `default:`, `subject:` i `personal:` bez sprawdzenia — **poprawione** w `3e282f3`
   (F3 i F5 na polach wartości domeny).
6. `unit` odrzucany przy wartości, której typ jest inną wartością liczbową — **poprawione** w `b2175b5`.
7. `Model.fetch/1` sprawdza załadowanie dwa razy na wywołanie — **pominięte**: koszt pomijalny, czas suity bez
   zmian.

### Losy fikstur

| Fikstura | Los |
| --- | --- |
| `ProcessShapes.Promised` (or_else, asynchroniczny koniec, niepotwierdzony deadline; używana przez 7 plików testów) | przebudowana w E7 |
| `ProcessShapes.Timed`, `ProcessShapes.Bare` | przebudowane w E7 |
| `UniversalityGate.TreatmentEpisode` z `Eligibility` i fake'iem `PayerRegistry` | przepisana w E4; `Eligibility.decide/1` staje się deciderem; fake zostaje; kontrakt bez implementacji poza tym (D3) |
| `ProcessShapes.Rig` (19 zdarzeń, 14 handlerów) | **rozbity, nie portowany:** krawędź wsteczna i jej trzy kontrole → E7; celowo zepsute handlery → testy wyjścia decydera i polityki w E6; pary cyklu → E6/E7; konkurujące handlery synchroniczne → dwie projekcje inline w E6; `item_noted` → E8; usunięty przy cięciu |
| `CaseHandling` (web) | przebudowany w E7 z dwiema politykami |

### Losy testów

Liczby z planowania 25 września (z listy plików, nie z uruchomienia):

| Grupa | Los |
| --- | --- |
| Zachowanie weryfikacji (~159): trace, trace_edges, trace_granularity, run, conformance, conformance_wire, report, graph, deployment, dependency, duration, brief | **zostają**; pomocnik zasiewu zmienia się w E2, fikstury w E7; asercje zmieniają się tylko tam, gdzie werdykt rusza się celowo — każda taka zmiana to linia w CHANGELOG |
| Dispatch v1 (~116): dispatch, publications, cycle, handler_failure, job_*, telemetry, payload, payload_edges, instance, scale_edges, process_shapes, registry_exclude | zachowanie wyprowadzone od nowa na runtime v2 w E6–E8; plik v1 znika, gdy każde zachowanie ma test v2 |
| Związane z DSL-em (~90): compile_gates, check_keys, check_ambiguity, command, digest, asyncapi | przepisane na Sparka; testy formy kanonicznej w `digest_test` zostają słowo w słowo |
| Przypięcia (~22): universality_gate, docs_test | ustanowione od nowa przy cięciu |
| Pakietowe (~8): package, version, boot | zostają; `boot` się zmienia, bo child staje się supervisorem |
| Web (31) | zostają, przepięte na nowy `CaseHandling` w E7 |
| Sandbox (35 statycznych) | `periods` i `identity_seam` przepisane w E9; `declared_shape` wyprowadzony od nowa w E9; testy przykładów stają się testami scenariuszy w E6/E9; `eh_os_contract_host_web` zostaje |

### Weryfikacja końcowa

1. Usunięcie trzech baz testowych i brama od zera — migracje z pustej bazy, zwinięcie poprawne.
2. CI na czystym `_build` (wypycha użytkownik).
3. Baza dev (nigdy `MIX_ENV=test mix run`): `open_month` przez trzy poziomy IAM, komendy VisitSettlement,
   przebieg ClinicalVisit ponad 24 godziny; `mix eh_os_contract.report` pokazuje naruszenie, spełnienie przez
   `or_else`, zawieszenie po `Dependency.unavailable!` i ścieżkę w toku przy nieopróżnionym efekcie.
4. Przebudowa projekcji z magazynu daje identyczne wiersze.
5. Usunięcie osoby: pola nieczytelne, liczby raportu bez zmian.
6. `mix phx.server`: `/dashboard` — status czterech kontraktów, grafy (deklarowany, nakładka, system);
   endpointy zgodności, AsyncAPI i modelu z nazwami schematów.
7. `mix eh_os_contract.graph --process clinical_visit --mermaid` zgodny z przypięciami; widok systemu z
   krawędziami `consumes`; `mix eh_os_contract.trace --instances` działa.
8. Projekt-konsument w scratchpadzie instaluje oba pakiety z gita, migruje, wykonuje dispatch, dostaje raport;
   formatter zachowuje kształt DSL-a.
9. `MIX_ENV=test mix hex.build` przechodzi czysto; kod po angielsku, sprawdzony słowo po słowie.

---

## Dopisek 25 września — cztery kontrakty rzutowane na ESDM: rdzeń, rozszerzenie, luka

Nic tu nie zostało zbudowane. To mapa na papierze i pierwszy krok kierunku ustalonego w rozmowie tego dnia:
**DSL w Elixirze przejmuje funkcjonalność ESDM** (Event-Sourced Domain Modeling, esdm.io, wersja 0.15.0 z
17 września) — jego pojęcia, reguły walidacji i narzędzia — **z opisem modelu jako DSL-em zamiast YAML-a.**
To nie jest integracja: żadnego eksportu do `.esdm.yaml`, żadnego `esdm lint`, żadnej zależności od ich
wersji schematu. ESDM jest specyfikacją tego, co model ma umieć wyrazić i sprawdzić, a nasza warstwa
weryfikacji zostaje tym, czego ESDM nie ma. Do tego strona odczytu z CQRS (read modele, zapytania) w tym samym
modelu i, później, grafy domeny w rodzaju EventCatalogu z nałożonymi danymi z logu. **Zgodność wstecz nie
obowiązuje**: kontrakty to dane testowe i nic nie działa u klienta.

Każdy element czterech kontraktów trafił do jednego z trzech koszyków:

1. **ESDM** — pojęcie, które ESDM ma (w rdzeniu albo w Given-When-Then), a nasz DSL musi przejąć; zmienia się
   nazwa albo kształt.
2. **Rozszerzenie** — ESDM nie ma nic podobnego. To cała nasza warstwa weryfikacji. „Rozszerzenie” znaczy tu
   część DSL-a ponad funkcjonalnością ESDM, nie osobny schemat ani plik.
3. **Luka** — model ESDM czegoś wymaga, a kontrakt tego nie mówi. Uzupełnienie jest decyzją modelową; przy
   każdej luce sprawdziłem, czy zapełnia ją materiał.

Źródła: schemat ESDM czytany 25 września (esdm.io i surowe pliki schematu z `thenativeweb/esdm`), cztery
kontrakty z `sandbox/`, materiał TaxVision z `taxvision-process-native/workshop_output/` i materiał Rehmedu
z `rehmed-process-native/2-Solution/` w **obecnej** wersji, czyli po zmianach z 11–17 września. Skróty: ES —
`02-event-storming.md`, DDD — `03-ddd-architecture.md`, HB — `10-ddd-headless-backend.md`, US —
`04-user-stories/`; AG — `20-aggregates.md`, CX — `30-contexts.md`, EM — `10-event-model.md`. Numery linii
z bieżących plików.

### Wynik w sześciu zdaniach

1. **Dwie trzecie DSL-a to weryfikacja, nie model domeny.** Z 36 kluczy siedmiu deklaracji dom w ESDM ma 12,
   z czego mechanicznie przechodzą trzy (`payload` zdarzenia i komendy, `command` przykładu); dziewięć wymaga
   przepisania albo decyzji. Pozostałe 24 to rozszerzenie.
2. **Prawie wszystko, czego ESDM wymaga, a kontrakty nie mówią, jest w materiale** — konteksty z klasyfikacją
   subdomen, mapy kontekstów, agregaty z inwariantami, aktorzy, read modele. Oba materiały są zrobione w
   pojęciach DDD; destylacja to wyrzuciła, bo DSL nie miał gdzie tego położyć.
3. **15 z 29 zdarzeń nie ma komendy, która by je publikowała**, a ESDM wymaga wydawcy dla każdego.
4. **Model Rehmedu wpisał dwie obietnice czasowe między inwarianty**, bo nie miał dla nich innego miejsca.
   Inwariant ESDM sprawdza się przy obsłudze komendy, więc tych dwóch nie uniesie — to jest dokładnie nasze
   `trace`. Rozszerzenie nie jest dodatkiem: łata dziurę widoczną w modelu zrobionym po ESDM-owemu.
5. **Przebieg pokrywa się z jednym agregatem tylko w PayerSettlement**, i właśnie tam potrzebne jest DCB. W
   pozostałych trzech przebieg spina kilka agregatów, w ClinicalVisit — cztery, w czterech kontekstach.
6. **Mapowanie wyciągnęło dziesięć usterek i rozjazdów w samych kontraktach**, niezależnych od ESDM — lista na
   końcu.

### Słownik, klucz po kluczu

`E` — przechodzi mechanicznie, `E*` — ESDM ma odpowiednik, ale po przepisaniu albo decyzji, `R` — nasze
rozszerzenie. Kolumna „Dokąd” podaje odpowiednik w ESDM, czyli to, co DSL musi umieć wyrazić — nie format,
do którego cokolwiek eksportujemy. Nazwy przechodzą bez zmian, chyba że przejmiemy konwencję ESDM, w której
zdarzenie nazywa się w obrębie swojego agregatu (`accounting_month_opened` → `opened` w `accounting_month`).

| Deklaracja | Klucz | Dokąd | |
| --- | --- | --- | --- |
| `event` | `label` | `description` | `E*` — ESDM nie ma pola na etykietę biznesową i niczego z niej nie czyta; u nas wymagana i czytana przez raport, więc wymóg zostaje w `R` |
| | `payload` | `data` | `E` — ESDM opisuje dane pełnym JSON Schema: zagnieżdżenia, pola opcjonalne, formaty, value objects; nasze pięć płaskich typów to podzbiór, więc to, co dziś jest, przechodzi, a reszty trzeba DSL-a nauczyć |
| | `owner` | — | `R` — moduł w kodzie; w ESDM wydawcą jest agregat przez `command.publishes` |
| | `retain` | — | `R` |
| | `identity` | — | `R` — ESDM trzyma idempotencję na konsumencie (`idempotency.owner`, `strategy`), nie na fakcie |
| | `depends_on` | — | `R` — ESDM wiąże system zewnętrzny z efektem ubocznym handlera albo z aktorem (`backedBy`), nie ze zdarzeniem |
| | `process`, `stage`, `terminal` | — | `R` |
| `command` | `label` | `description` | `E*` — jak przy `event` |
| | `payload` | `data` | `E` |
| | `principals` | `actors` | `E*` — ESDM chce nazwanych ról (`actor` z `type: human \| system`), nie samych rodzajów |
| | `process` | — | `R` — w ESDM komenda celuje w agregat albo DCB (`scope`), nie w przebieg |
| | `source` | — | `R` |
| `process` | wszystkie siedem | — | `R` — process manager w ESDM steruje; nasz `process` obserwuje przebieg |
| `trace` | wszystkie cztery | — | `R` |
| `external` | `label` | `description` | `E*` |
| | `expected_latency`, `unavailable_looks_like` | — | `R` |
| `rule` | `label` | `invariant` agregatu albo `command.constraints` | `E*` — patrz „Reguła to dwie rzeczy” niżej |
| | `function` | — | `R` — wiązanie z kodem (`decide`) |
| | `source` | — | `R` |
| `example` | `rule` | `feature.scope` (agregat) | `E*` |
| | `command` | `when: {command, data, actor}` | `E` — aktora nasze przykłady nie nazywają, ESDM go nie wymaga |
| | `given` | `given: [{event, data}]` | `E*` — mapa stanu musi stać się listą zdarzeń |
| | `then` | `then: {events: [{event, data}]}` | `E*` — ESDM wymaga danych; semantykę dopasowania (u nas podciąg) zostawia implementacji, więc ta zostaje w `R` |
| | `rejected_with` | `then: {rejection: {invariant}}` | `E*` — powód musi być nazwanym inwariantem |
| handler w kodzie | `event`, `publishes`, `async` | `policy`, `event-handler`, projekcja `read-model` | `E*` — każdy handler trzeba zaklasyfikować; tryb „synchronicznie w transakcji” nie ma odpowiednika w `deliveryGuarantee` (tylko `at-least-once \| at-most-once`), więc zostaje w `R` |

**Reguła to dwie rzeczy.** W dwóch regułach z trzech przykłady mieszają rozgałęzienie i odmowę:
`month_opens_only_on_consistent_registry` ma dwa `then:` i jedno `rejected_with:`,
`payment_lines_sum_to_the_total` — trzy i jedno. W ESDM to dwa różne miejsca: odmowa jest nazwanym
inwariantem, rozgałęzienie („zero płatności → zamknięcie bez płatności”) to `constraints` komendy. Bramka
„reguła bez przykładu się nie kompiluje” ma w ESDM odpowiednik, `uncovered-invariant`, tyle że jako
ostrzeżenie — zostaje nasza.

### `Taxvision.Contracts.AccountingMonth`

11 zdarzeń, 2 komendy, proces, `trace`, `external`, 2 reguły, 5 przykładów, 3 handlery w kodzie.

**Jeden przebieg, cztery konteksty.** Materiał dzieli to, co kontrakt trzyma jako jeden proces, między
konteksty z klasyfikacją subdomen (DDD §2, HB §1). W kontrakcie jedynym śladem tego podziału jest `owner:` —
i pokrywa się z kontekstami prawie jeden do jednego:

| Zdarzenie kontraktu | Kontekst i agregat w materiale | `owner:` dziś |
| --- | --- | --- |
| `data_completeness_confirmed` | Companies, `CompanyProfile` — raz na firmę, nie co miesiąc (DDD §4.1, US-ONB-08) | `RegistryCheck` |
| `registry_status_checked`, `registry_data_consistent`, `registry_discrepancy_detected` | Companies, `RegistryCheckLog`, komendy `CheckRegistries` i `RetriggerVerification` (DDD §4.2, HB §4.4) | `RegistryCheck` |
| `registry_check_logged` | już nie zdarzenie — „zastąpiona automatycznym wpisem” | `RegistryCheck` |
| `monthly_tasks_generated` | Work Orchestration (core); komendy generowania materiał nie nazywa | `Tasks` |
| `accounting_month_opened`, `month_closed` | Client Month (core), `AccountingMonth` (ES §12); HB zmienia nazwę na `PeriodOpened` | `AccountingMonth` |
| `discrepancy_notification_sent` | Notifications (supporting), „jedyny nadawca” | `Notifications` |

Między kontekstami materiał ma gotowe mapowanie: Client Month „publikuje `periodId` jako published language”
(HB), czyli `context-mapping` typu `published-language`.

**Agregat `AccountingMonth` jest w materiale razem z inwariantami** (ES §12): stepper Gromadzenie →
Dopasowywanie → Wynik, „otwarcie warunkowane pozytywną weryfikacją rejestrową”, „dopasowywanie warunkowane
wyciągiem”, „każdy krok ma deadline”. Stany z makiety — nieotwarty, zablokowany rejestrowo, gromadzenie,
dopasowywanie, wynik, zamknięty — pokrywają się z `stages` naszego procesu (brakuje u nas tylko wyniku).
Etapy przebiegu są więc stanami jednego agregatu, choć sam przebieg obejmuje zdarzenia czterech. Tożsamości
materiał nie podaje wprost („per firma per miesiąc”), a agregat ESDM chce jednego pola, więc klucz złożony
wymaga pola syntetycznego albo DCB.

**Komenda `open_month` to w materiale dwie komendy w dwóch kontekstach.** `Taxvision.RegistryCheck.decide/1`
robi naraz `CheckRegistries` i otwarcie; w materiale otwiera polityka P1 po `RegistryDataConsistent`, a
ręcznie — `OpenMonth` z US-MON-01. Wymagane w ESDM `publishes` rozdziela to, co u nas zlewa jedna decyzja, i
pokazuje, że `open_month` wcale nie publikuje `accounting_month_opened`: to zdarzenie powstaje dwa handlery
później. To są „dwie interpretacje `emits:`” z 5.5, tym razem na konkretnym przykładzie.

**Reguła 1 jest inwariantem z materiału, ale sięga do cudzego agregatu.** „Otwarcie warunkowane pozytywną
weryfikacją” to dosłownie inwariant `AccountingMonth`, tylko że wynik weryfikacji to zdarzenia
`RegistryCheckLog`. Póki otwiera wyłącznie polityka, wystarczy agregat; ręczne `OpenMonth` z US-MON-01
wymaga sprawdzenia przy zapisie ponad dwoma agregatami, czyli DCB. Rozgałęzienie „zgodne / rozjazd” idzie do
`constraints` komendy `CheckRegistries`. Po przepisaniu przykładów na zdarzenia `abilia:` staje się
zdarzeniami `CompanyProfile` (Abilia to własny system klienta, nie zewnętrzny), a `registries:` — danymi w
`registry_status_checked`, które dziś niesie tylko `checked_at`.

**Reguła 2 da się zapisać w ESDM, ale nie zgadza się z materiałem.** Przypisanie księgowej do firmy jest w
materiale faktem domenowym (`CaretakerAssigned`, agregat `Assignment`, DDD §4.5; HB przenosi je do Identity),
więc przykład „księgowa innej firmy” przepisuje się na zdarzenia i odmowę z nazwanym inwariantem. Założenie,
że ta reguła zostanie w rozszerzeniu, było prawdziwe tylko przy przypisaniu jako roszczeniu z tokenu. Tyle że
decyzja 19 (ES) mówi co innego niż reguła: jeden typ użytkownika, firma publiczna otwarta dla wszystkich
pracowników, prywatna dla przypisanych opiekunów i adminów. Reguła w kontrakcie pasuje tylko do firm
prywatnych.

**Handlery, po zaklasyfikowaniu:**

- `Taxvision.Tasks` (na `registry_data_consistent`) — polityka plus komenda w Work Orchestration.
- `OnMonthlyTasksGenerated` — polityka („zadania są → otwórz”), zdarzenie agregatu i projekcja. Kolejność jest
  sporna w samym materiale: ES §3.1 ma zadania **przed** otwarciem (tak robi kod), DDD §5, US-MON-A1 i HB —
  **po**.
- `Taxvision.Notifications` — polityka wysyłająca komendę do Notifications plus event handler z efektem
  ubocznym. `discrepancy_notification_sent` nie ma w ESDM prawa powstać z handlera, a materiał i tak go nie ma:
  powiadomienie to encja ze statusami wysłana / dostarczona / odczytana / potwierdzona (DDD §4.9), a HB
  publikuje tylko `NotificationDelivered`, `NotificationAcknowledged` i `NotificationDeliveryFailed`.

**Read modele są nazwane w materiale** (HB §3.3): `company_portfolio`, `company_period`, `period_tasks`,
`my_work_today`, `notification_registry`, z zasadą „każda projekcja to endpoint odczytu”. Trzy tabele pisane
dziś przez handlery odpowiadają trzem z nich. `taxvision_periods` to dane referencyjne zapisywane bez zdarzeń
— w ESDM `entity`. Systemy zewnętrzne: rejestry i poczta, oba `outbound`; kontrakt deklaruje tylko rejestry.

### `Rehmed.Contracts.ClinicalVisit`

7 zdarzeń, komenda, proces, 2 `trace`, `external`.

**Jeden przebieg, cztery konteksty, cztery agregaty:**

| Zdarzenie kontraktu | Kontekst i agregat w materiale | `owner:` dziś |
| --- | --- | --- |
| `visit_started` (E-40), `visit_completed` (E-51) | CTX-01 Umawianie i zasoby (core), AGG-01 Wizyta — przejścia bez komendy | `VisitDocumentation` |
| `visit_closed_clinically` (E-52, C-29) | CTX-03 Dokumentacja kliniczna, AGG-02 | `VisitDocumentation` |
| `documentation_task_created` | CTX-07 Koordynacja pracy, AGG-13, przez P-23 | `Tasks` |
| `p1_report_sent` (E-54) | CTX-04 Sprawozdawczość (generic, conformist wobec P1), AGG-10 | `Reporting` |
| `p1_report_failed`, `p1_reporting_not_required` | AGG-10 ma stan Błąd, ale żadne z nich nie ma numeru E-; „nie podlega” to warunek P-07, nie zdarzenie | `Reporting` |

Mapa kontekstów jest w materiale i przechodzi na ESDM jeden do jednego (CX:157–170): CTX-01↔CTX-03
`partnership`, CTX-03→CTX-04 `conformist`, CTX-04→P1 `conformist`, wszystkie → CTX-07 `open-host-service`.

**Obietnice czasowe siedzą w materiale między inwariantami.** AGG-02, inwariant 2a: „A delivered visit is
clinically closed at all”; AGG-10: zgłoszenie ma dojść do P1 „within the statutory 2 days (nothing watches —
H19)” (AG:264–269, AG:630). Żadna komenda nie może odmówić dlatego, że czegoś *nie* zrobiono, więc inwariant
ESDM tych dwóch nie uniesie. To są nasze dwie assercje `trace`, a model zrobiony po ESDM-owemu wpisał je w
jedyne miejsce, jakie miał.

**Wydawców ma jedno zdarzenie z siedmiu.** E-40 i E-51 to w materiale przejścia bez komendy, czyli
obserwacje. Wyniki P1 zapisuje się w ESDM komendą aktora systemowego `backedBy` system zewnętrzny, a materiał
nie ma aktorów systemowych — automatykę wyraża politykami (P-nn) i systemami (X-nn).

**24 godziny to w ESDM process manager z timerem, a nasze `trace` sprawdza, czy działa.** To jest podział ról
z kierunku z 25 września w najczystszej postaci: process manager (pojęcie z ESDM) opisuje sterowanie, `trace`
(rozszerzenie) — obietnicę.

Read modele z materiału (EM:569–603): R-03 („kto jest w budynku”, zasilany E-27, E-40, E-51), R-06
(zaległości dokumentacyjne, E-51 i E-52), R-16 (zadania).

### `Rehmed.Contracts.VisitSettlement`

6 zdarzeń, 5 komend, proces, reguła, 4 przykłady. **Najczystszy przypadek i wzorzec dla kroku z deciderem.**

- Agregat AGG-03 Rozliczenie wizyty (CTX-05 Rozliczenia, supporting), tożsamość: identyfikator wizyty. Jedno
  pole, więc pasuje do `identifiedBy` ESDM bez sztuczek.
- Każde zdarzenie ma komendę, która je publikuje — jedyny taki kontrakt z czterech. `publishes` wynika z
  materiału: C-23→E-45, C-31→E-55, C-30→E-53/E-56, C-46→E-84, C-68→E-115.
- **`given` przepisuje się na zdarzenia z tego samego kontraktu, jeden do jednego:** `total_minor` pochodzi z
  `visit_handed_over`, `payments` z kolejnych `payment_recorded`. Żaden przykład nie potrzebuje faktu spoza
  kontraktu.
- Value objects: kwota (`total_minor`, `amount_minor`, `delta_minor`) i linia płatności (metoda, kwota,
  płatnik). Zbiór metod jest w materiale — „K / G / przelew / bon” (AGG-06) — więc gołe `:enum` może dostać
  zbiór. Przypadek mieszany (C-61→E-106) wymaga płatnika tylko na części linii: JSON Schema to wyraża, nasz DSL
  nie, bo nie ma pól opcjonalnych.
- `business_date` jest datą, nie chwilą — w ESDM `format: date`, u nas najbliżej jest `:timestamp`.
- Read model R-07 (sumy dnia per metoda płatności) jest „corrupted by the split-payment defect”. **Znany
  defekt klienta żyje w projekcji**, czyli dokładnie w tej części, której dziś nie deklarujemy.

Dwie rzeczy do rozstrzygnięcia. `visit_handed_over` (E-115) to w materiale zdarzenie AGG-01 w CTX-01 (przez
C-68), które *otwiera* AGG-03 (`[*] --> Otwarte: E-115`); przebieg obejmuje więc zdarzenie z innego
kontekstu, do czego ESDM wymaga mapowania — a materiał je ma (CTX-01→CTX-05 `customer-supplier`). I
właściciel reguły jest niejednoznaczny w samym materiale: „Payment lines sum to the settlement total” to
inwariant 1 AGG-03, ale ta sama reguła stoi na AGG-06, a tabela reguł przypisuje ją AGG-06 (AG:108, 381,
536). W ESDM inwariant należy do jednej jednostki.

### `Rehmed.Contracts.PayerSettlement`

5 zdarzeń, 2 komendy, proces, `external`, zero assercji.

- Agregat AGG-11 Rozliczenie płatnika (CTX-06 Płatnicy zewnętrzni, generic, „ACL with a manual adapter behind
  it”). Materiał nie podaje tożsamości ani automatu stanów; klucz `[payer_id, period_id]` jest nasz.
- Komendy z materiału: C-48→E-86 i C-49→E-87 są w kontrakcie, C-47→E-85 (rejestracja w systemie płatnika)
  kontrakt świadomie pominął. Trzy zdarzenia kontraktu nie mają ani numeru E-, ani komendy.
- **Niezmiennik, którego kontrakt nie umiał zapisać, jest w ESDM DCB.** „Every delivered payer-funded visit in
  a settlement period is either included in that period's invoice, or excluded with a stated reason” (AG:694)
  przecina wizyty i okres płatnika. Moduledoc kontraktu podaje trzy powody, dla których nie wyraziło go
  `trace`: kwantyfikator po zbiorze, kotwica w cudzym przebiegu, klucz nieznany w chwili zdarzenia. DCB
  odpowiada na wszystkie trzy: tożsamość płatnik + okres, `consults` na wykonaniu wizyty, E-85, E-86,
  wykluczeniach i E-87, a kryterium rozstrzyga się przy decyzji, nie przy emisji. DEC-16 (wizyta niesie
  referencję do faktury, która ją rozliczyła) robi z obu list wyjątków „zapytania po jednym polu”.
- Ale DCB **zapobiega** przy zapisie. Sprawdzenie po fakcie — „faktura wystawiona, a dostarczona wizyta ani
  oznaczona, ani wykluczona” — wymaga logu, w którym zdarzenie może dotyczyć kilku obiektów naraz (OCEL). To
  ta sama granica, na którą trafia wyzwalacz „jedno zdarzenie w dwóch procesach” z `docs/adr/architecture.md`.
- Read model R-08 („czy płatnik zapłacił za wszystko”, zasilany E-85, E-86, E-87) z ekranem S-60 i jego
  „two exception lists”.

### Wydawcy: 15 z 29 zdarzeń bez komendy

| Dlaczego nie ma komendy | Ile | Zdarzenia |
| --- | --- | --- |
| publikuje je handler, więc w ESDM potrzebna polityka i komenda | 3 | `monthly_tasks_generated`, `accounting_month_opened`, `discrepancy_notification_sent` |
| późniejsze fazy TaxVision, niezaimplementowane | 3 | `bank_statement_received`, `turnover_matched_with_invoice`, `month_closed` |
| obserwacja, bez komendy także w materiale | 2 | `visit_started`, `visit_completed` |
| wynik integracji z P1 | 2 | `p1_report_sent`, `p1_report_failed` |
| decyzja systemu o zgłaszalności | 1 | `p1_reporting_not_required` |
| zadanie tworzone przez politykę | 1 | `documentation_task_created` |
| bez komendy w materiale | 3 | `visit_excluded_from_invoice`, `payer_visits_reconciled`, `payer_period_closed_without_invoice` |

To nie to samo co czternaście „wejść bez komendy” z dopisku 22 września (3): tamten spis liczył wejścia do
procesu z zewnątrz, ten liczy zdarzenia bez wydawcy, więc obejmuje też zdarzenia z handlerów.

### Co idzie do rdzenia, a co do rozszerzenia

**Rdzeń DSL-a** — rodzaje ESDM, których potrzebują te cztery kontrakty: `domain`, `subdomain`,
`bounded-context`, `context-mapping`, `aggregate`, `dynamic-consistency-boundary` (PayerSettlement, ręczne
otwarcie miesiąca), `entity` (okres), `value-object` (kwota, linia płatności), `command`, `event`, `policy`,
`event-handler`, `process-manager` (pogoń za dokumentacją), `read-model`, `query`, `actor`, `external-system`,
a z rozszerzeń ESDM — `feature` i `scenario` z Given-When-Then. Siedemnaście z osiemnastu; nie potrzeba tylko
`domain-service`. Materiał ma dwanaście z nich wprost, domena jest oczywista, a DCB, process manager, value
object i zapytanie jako osobny byt to nasze propozycje. Wymóg z rozmowy zostaje: rodzaj wchodzi do DSL-a
dopiero z mechanizmem, który go czyta.

**Rozszerzenie** — nasze konstrukcje, których ESDM nie ma:

- przebieg: `process` z `instance`, `stages`, `terminal`, `cadence`, `deadline`, `unverified`, `accountable` —
  z jedną zmianą, którą wymusza ta mapa: przebieg deklaruje się nad kluczem korelacji spinającym kilka
  agregatów, a nie nad jednym;
- obietnice: `trace` z `from`, `eventually`, `within`, `or_else`;
- fakt: `retain`, `identity`, `depends_on`;
- systemy zewnętrzne: `expected_latency`, `unavailable_looks_like` i werdykt `:suspended`;
- wiązanie z kodem: `owner`, funkcje decyzyjne (dziś `rule.function`), tryb dispatchu (w transakcji albo
  przez Obana);
- pochodzenie: `source` i wymagana etykieta biznesowa;
- semantyka dopasowania scenariusza (podciąg, nie równość) i wersja kontraktu na każdym zdarzeniu.

Podział na rdzeń i rozszerzenie porządkuje DSL i jego dokumentację. To jeden moduł kontraktu i jedna
kompilacja, nie dwa formaty.

### Co poza słownikiem

Funkcjonalność ESDM to nie tylko rodzaje deklaracji. Trzy rzeczy do przejęcia i jedna, w której już mamy więcej:

- **Reguły walidacji** — 47 w rdzeniu i 17 dla Given-When-Then. Przechodzą na naszą drabinę: reguły
  strukturalne (model sobie przeczy — komenda bez `publishes`, pole tożsamości spoza stanu, korelacja process
  managera, której nie niesie któreś z jego zdarzeń) stają się błędami kompilacji, a reguły modelowe (model
  spójny, ale niepełny — zdarzenie bez konsumenta, read model bez zapytania, inwariant bez scenariusza) —
  ostrzeżeniami `mix eh_os_contract.check`. Reguły modelowe ESDM sprawdzają kompletność, nie osąd, więc §14
  („harness stays out of modelling”) ich nie wyklucza.
- **Narzędzia** — widok hierarchiczny (domena → kontekst → jednostka), słownik języka kontekstu z
  tłumaczeniami i dokumentacja, strona na element z linkami. U nas taski mix; grafy — dashboard. Nazwa
  `mix eh_os_contract.docs` jest zajęta przez referencję DSL-a.
- **Domain Storytelling** — format odkrywania, sprzed modelu. Żaden z czterech kontraktów go nie potrzebuje;
  na później.
- **Wykonywanie scenariuszy** — ESDM sprawdza je tylko składniowo i zostawia uruchamianie implementacji. My
  wykonujemy przykłady jako testy już dziś (`EhOsContract.ContractExample`), więc tu nie kopiujemy.

### Usterki i rozjazdy, które mapowanie wydobyło

Niezależne od ESDM: wyszły przy sprawdzaniu, skąd wziąć brakujące elementy. **Nic z tego nie zostało
poprawione w kontraktach.**

W warstwie weryfikacji:

1. `trace :month_opens_or_is_blocked` startuje od `data_completeness_confirmed`, które w materiale zdarza się
   raz na firmę (`ConfirmDataCompleteness` na `CompanyProfile`), a w kodzie powstaje co miesiąc z decyzji,
   której wejście samo je zakłada — `completeness_confirmed: true` jest wpisane na sztywno w `Taxvision.Api`.
   Kotwica ma złą częstotliwość, a fakt jest wyjściem decyzji zamiast jej warunkiem.
2. Tej samej assercji `within: {2, :day}` nie ma w materiale; najbliżej jest ilustracja z warsztatu
   („pierwszego może … wylecieć, on naprawi rzeczy i drugiego powinno być okej”, WF 00:34:52). Od 21 sierpnia
   `unverified` obejmuje `trace`, więc tam powinna trafić.
3. Jej `or_else`, `discrepancy_notification_sent`, dzieli się na dwa zdarzenia: po warsztacie klient poprosił,
   żeby do klienta szło „dopiero po weryfikacji przez księgową, nie równolegle” (uwagi, fragment 21; otwarte
   pytanie A10).
4. `or_else` w `:reported_or_chased_within_a_day` to `documentation_task_created`, a P-23 tworzy to zadanie
   przy rezerwacji (E-14), czyli przed kotwicą `visit_completed`. `EhOsContract.Trace` liczy tylko zdarzenia
   od kotwicy (`first_at_or_after`), więc gdy P-23 powstanie, każda wizyta niezgłoszona w 24 godziny będzie
   naruszeniem, choć zadanie istnieje.

Rozjazdy kontraktu z materiałem:

5. `open_month` ma źródło: US-MON-01 („Standardowo miesiąc otwiera polityka …; operacja dostępna też
   ręcznie”, aktor Księgowa). Puste `source:` było prawdziwe wobec diagramu ES §3.1, nie wobec historyjek —
   pozycję z handoffu „`open_month` bez `source:`” zamyka ten cytat.
6. Reguła `only_company_accountant_opens_month` pasuje do decyzji 19 tylko dla firm prywatnych.
7. `registry_check_logged` w materiale nie jest już zdarzeniem, a kolejność „zadania, potem otwarcie” jest
   sporna w samym materiale (ES §3.1 kontra DDD §5, US-MON-A1 i HB); kod idzie za ES §3.1.
8. ClinicalVisit: E-40 i E-51 należą w materiale do AGG-01 w CTX-01, nie do dokumentacji. A poprawka z
   19 sierpnia („zamknięcie jest natychmiastowe”), na której stoi cały kontrakt, nie występuje w `2-Solution/`
   — tam E-52 to późniejsze zamknięcie wymagające kodów ICD, a sygnałem dla recepcji jest E-115.
9. PayerSettlement pisze „There is no API”, a CX:107 — że API płatnika jest „*unchecked*, not refused”. S-121
   (11 września) każe wystawiać fakturę ręcznie w portalu KSeF, więc E-87 może być tylko ręcznym oznaczeniem.
10. VisitSettlement: H177 (wrzesień) robi z przekazania wizyty komendę warunkową i przesuwa zamrożenie ceny na
    moment rozliczenia — „przeczy DEC-18”, na którym stoi `visit_handed_over`. Czeka na ratyfikację.

### Co dalej

**Decyzje biblioteki, przed kodem:**

- składnia: zagnieżdżone bloki (`aggregate … do … end` z komendami i zdarzeniami w środku, jak zakres w ESDM)
  czy płaskie deklaracje z kluczem zakresu, jak dziś `process:`;
- jak rozszerzenie deklaruje przebieg nad kluczem korelacji spinającym kilka agregatów;
- etykieta biznesowa: ESDM ma `description` i słownik kontekstu, my wymagamy `label` — czy etykieta zostaje,
  czy przechodzi do słownika; i co z `retain` na zdarzeniu, które przy event sourcingu byłoby źródłem prawdy;
- dane zdarzeń i komend: ESDM ma pełny JSON Schema (zagnieżdżenia, pola opcjonalne, formaty), więc zakaz pól
  opcjonalnych i płaski zbiór typów trzeba zastąpić czymś o tej sile — w składni DSL-a, nie w JSON-ie.

**Pytania do materiału albo do klienta:** usterki 1–4 i 6–10; wydawcy dla 15 zdarzeń; tożsamość AGG-10 i
AGG-11; właściciel reguły sumy linii.

**Kolejność przepisywania rdzenia**, od najczystszego:

1. VisitSettlement — jedna tożsamość, komplet komend, `given` jeden do jednego. Na nim powstaje decider
   (`decide` + `evolve`) i Given-When-Then.
2. TaxVision — podział na konteksty, handlery jako polityki i projekcje, read modele z HB §3.3.
3. ClinicalVisit — przebieg nad kilkoma agregatami, process manager, obietnice w rozszerzeniu.
4. PayerSettlement — DCB.

Poprawki z datą w `docs/adr/` (zamknięty zbiór typów, §15, „historia zdarzeń, nie event sourcing”) — gdy kod
je potwierdzi, nie wcześniej. §2 zostaje w mocy: DSL pozostaje jedynym źródłem i żaden zewnętrzny format nie
stoi obok niego.

---

## Dopisek 23 września (3) — repozytorium biblioteki, nie prototypu

Od dziś to jest repozytorium biblioteki: inne repozytoria instalują `eh_os_contract` i
`eh_os_contract_web` stąd. Sprawdzone projektem-konsumentem w scratchpadzie, który zainstalował oba pakiety
z gita, przeszedł migrację, wyemitował zdarzenie przez synchroniczny handler i dostał raport. Po drodze
wyszły cztery przeszkody, każda ma swój commit:

1. **`eh_os_contract_web` wskazywał silnik przez `path: "../eh_os_contract"`**, czego checkout `sparse:`
   nie zawiera — `mix deps.get` konsumenta padał z „Dependencies have diverged”. Ścieżka jest teraz tylko
   wtedy, gdy silnik leży obok; inaczej git z tym samym `sparse:`, które deklaruje konsument.
2. **Start wymagał dwóch ręcznych wywołań** (`Registry.load!`, `Deployment.record!`), których README
   pakietu nie wymieniało. Teraz `EhOsContract` to child do drzewa nadzoru, po repo i Obanie.
3. **`docs/contract.md` leżał poza pakietem**, a `mix eh_os_contract.docs` jechał do konsumentów i padał
   u nich na `File.Error`. Referencja jest w `packages/eh_os_contract/docs/`, task w `dev/` (kompilowany
   tylko w `:dev`/`:test`), jego `--check` w bramie pakietu, testy referencji obok bram kompilacyjnych.
4. **W katalogu głównym leżał host**, nie biblioteka. Host z TaxVision i Rehmedem jest teraz w
   `sandbox/`, jako pierwszy konsument. Brama: `docker compose up -d && cd sandbox && mix ecto.setup &&
   mix check`. `CLAUDE.md` przepisany pod nową rolę repozytorium; zdanie „to repozytorium jest
   przejściowe” odnosi się teraz do `sandbox/`, nie do całości.

Przy okazji z `CLAUDE.md` wyleciało „grafu w interfejsie nie budujemy” — dashboard ma ekran grafu od
23 sierpnia.

**Zrobione tego samego dnia:** `main` wypchnięty, tag `v0.2.0` na `fafc3cf` (niewydane sekcje obu
CHANGELOG-ów włączone w 0.2.0 i 0.1.0, żeby tag nie przeczył dacie), repozytorium przemianowane na
`EmpoweredHouse/eh-os-contract` — `@source_url` w obu pakietach, adres gita w `eh_os_contract_web/mix.exs`,
README i `origin` za nim poszły. Repozytorium jest prywatne, więc CI konsumenta potrzebuje klucza albo
tokenu. Lokalny katalog nadal nazywa się `pns_prototype`.

`mix check`: 42 + 397 + 31 testów, 0 padnięć.

## Dopisek 23 września (2) — `pns` → `eh_os_contract`

Pakiet nazywa się teraz `:eh_os_contract`, dashboard `:eh_os_contract_web`, przestrzeń nazw `EhOsContract`
(`EhOsContract.Web`), katalogi `packages/eh_os_contract` i `packages/eh_os_contract_web`, taski
`mix eh_os_contract.*`, makra `eh_os_contract_dashboard/2` i `eh_os_contract_api/2`, telemetria
`[:eh_os_contract, ...]`, znaczniki `__eh_os_contract__/0` i `__eh_os_contract_handler__/0`.

**Dlaczego „contract”, a nie „conformance”.** Biblioteka to dwie rzeczy naraz: fundament architektury
sterowanej zdarzeniami (emisja, handlery, dispatch) i sprawdzanie zgodności. Kontrakt jest tym, co czytają
obie — i przy wielu aplikacjach OTP wymieniających zdarzenia przez broker (JetStream, w planie) staje się
umową **między aplikacjami**.

**Drugim commitem przemianowane też to, co pierwszy zostawił** — bez zgodności wstecz, bo nikt tego
jeszcze nie używa: tabele `eh_os_contract_*` (wprost w `V01`/`V02`, bez migracji przejściowej; baza
postawiona od zera, użytkownik `eh_os`), rozszerzenia `x-eh-os-contract-*` w AsyncAPI, schemat
`eh_os_contract.conformance.v1`, zmienne CSS `--eh-os-contract-*`, bazy testowe, host
(`:eh_os_contract_host`, `EhOsContractHostWeb` — host, który montuje bibliotekę; nazwa hosta nie może być `EhOsContract`, bo to przestrzeń nazw i aplikacja OTP pakietu), ścieżki
montowania w hostach testowych. Dwa indeksy dostały jawne nazwy, bo wygenerowane przekraczały 63 znaki,
a Postgres obcina dłuższe identyfikatory bez błędu.

Stara nazwa zostaje wyłącznie w `docs/adr/` i w historii tego pliku, bo są zapisem — `CLAUDE.md` mówi
to w drugim akapicie. Lokalny katalog repozytorium (`pns_prototype`) i nazwa repozytorium na GitHubie
czekają na osobną decyzję.

`mix check`: 46 + 391 + 31 testów, 0 padnięć.

## Dopisek 23 września — warstwa tożsamości wycięta z silnika i z dashboardu

`PNS.Auth`, ekran kont, prowizoryczny login i domyślny resolver były z założenia, które już nie obowiązuje:
że ten projekt ma być właścicielem całego EHOS-a, a więc także dashboardu z logowaniem i zarządzaniem
tożsamościami. Produktem jest silnik zdarzeń i zgodności — i on z tego wszystkiego potrzebował jednej
rzeczy: stringa `"system"` na aktora, gdy wołający żadnego nie podał.

**Co wyleciało.**

- `pns_core`: cały `PNS.Auth` (`Actor`, `Verifier`, `LocalToken`, `OidcVerifier`, `IdentityAdmin`,
  `LocalIdentityAdmin`, `entitled?/2`), klucze konfiguracji `:auth_verifier` i `:identity_admin` — które
  przez `compile_env!` musiał ustawić **każdy** konsument `:pns` — zależność `oidcc` (z `jose` i
  `telemetry_registry`), oraz `PNS.Command` razem z `permits?/3`. `system_actor/0` przeszedł do
  `PNS.Event.system_actor/0`, obok kolumny, której dotyczy.
- `pns_web`: `LocalLogin`, trasy `/login` i `/logout`, `Live.Accounts`, `Plug.Authenticate`,
  `Resolvers.Default`. `:resolver` jest teraz **wymagany** w `pns_dashboard/2` i `pns_api/2`, bez domyślnego —
  domyślny „wpuść wszystkich” byłby pakietem decydującym za hosta, a ekran z każdym zdarzeniem w słowach
  klienta to mapa jego biznesu.
- Repo: `docker-compose.identity.yml`, `identity-poc-traefik-dynamic.yml`, `priv/poc/identity_smoke_test.exs`,
  `docs/identity-admin-guide.md`. Są w historii. Razem z nimi sprawdzenie `check_no_vendor_in_config` w
  `mix pns.check` i jego odpowiednik w `identity_seam_test.exs` — pilnowały, że w konfiguracji silnika nie
  pojawi się nazwa dostawcy tożsamości, a silnik nie ma już konfiguracji tożsamości, której mogłyby pilnować.

**Co zostało i gdzie.** Deklaracja `command` z `principals:` zostaje w DSL jako opis — kto wchodzi do
procesu którymi drzwiami, materiał z warsztatu, eksportowany w `x-pns-commands` AsyncAPI. Silnik nie
podejmuje już z niej decyzji o dostępie. Weryfikacja tokenu przeszła do `Taxvision.Identity` — jedynej
aplikacji w repo, która ma brzeg żądania — i `identity_seam_test.exs` dalej sprawdza trzy poziomy IAM,
teraz jako własność aplikacji klienta, nie silnika. Host w repo (`PnsPrototypeWeb.Resolver`) wpuszcza
wszystkich jako `:read_only`, jawnie.

**Poprawka założenia** poszła do `docs/adr/identity-seam.md` z datą: „one plug in the engine (`oidcc`) and
a `behaviour` for the user-management calls” było prawdziwe tylko przy tamtym zakresie.

**Do zważenia później, nie teraz:** `:all` i `:read_only` w `PNS.Web.Resolver` rozróżniały się wyłącznie na
ekranie kont — jedynym miejscu, gdzie dało się coś *zrobić*. Oba pozostałe ekrany i API traktują je
identycznie. Poziom `:all` jest dziś bez treści; usunięcie go zmienia behaviour, więc to osobny krok.

`mix check`: 46 + 391 + 31 testów, 0 padnięć.

## Dopisek 22 września (3) — komendy z warsztatu: osiem, nie dwadzieścia dwie

Dług „22 wejścia bez komendy" spłacony w tej części, w której da się go spłacić z materiału.
**Zadeklarowanych jest osiem nowych komend, nie dwadzieścia dwie**, i ta różnica jest wynikiem, nie
niedokończeniem.

**Skąd osiem.** Rehmed ma pełny katalog komend — `2-Solution/10-event-model.md` §4, 75 pozycji
z aktorem, produkowanymi zdarzeniami, powodem odmowy i źródłem. TaxVision ma event storming, w którym
komendy są w diagramach oznaczone jako `:::command` i jest ich w całym pliku trzy, z czego jedna
dotyczy procesu księgowego. Zmapowane na wejścia:

| Kontrakt | komenda | źródło | aktor |
| --- | --- | --- | --- |
| `VisitSettlement` | `add_service_line` | `C-23` | `A-03` specjalista |
| `VisitSettlement` | `hand_over_visit` | `C-68` | `A-03` |
| `VisitSettlement` | `record_payment` | `C-31` | `A-02` recepcja |
| `VisitSettlement` | `book_correction` | `C-46` | `A-02` |
| `PayerSettlement` | `mark_settled_with_payer` | `C-48` | `A-02` |
| `PayerSettlement` | `issue_payer_invoice` | `C-49` | `A-05` menedżer |
| `ClinicalVisit` | `close_visit_clinically` | `C-29` | `A-03` |
| `AccountingMonth` | `retrigger_verification` | storming §3.1 | Księgowa |

`C-68` jest najładniejszym dopasowaniem: katalog opisuje ją jako „jeden akt specjalisty, który
przekazuje wizytę do recepcji", a etykieta zdarzenia w kontrakcie brzmi „Wizyta oznaczona jako
wykonana i gotowa do rozliczenia". To samo zdanie dwoma drogami.

**Czego nie zadeklarowałem i dlaczego.** Czternaście wejść zostaje bez komendy, i dla każdego powód
jest ten sam: w materiale jej nie ma. Trzy z `ClinicalVisit` to wyniki integracji z P1 — odpowiedzi
cudzego rejestru, nie czyjeś działanie. `visit_started` i `visit_completed` to obserwacje („pacjent
wszedł", „pacjent wyszedł"), nie akcje. Sześć wejść `AccountingMonth` to w diagramie warsztatowym
`cron` i checki systemowe — dlatego ten proces ma dwie komendy, a nie osiem. Reszta po prostu nie
została na warsztacie nazwana.

**Wymyślenie ich byłoby tym samym błędem, co wymyślenie nazwy zdarzenia**, tylko gorszym o jedną
rzecz: `label` komendy to polska proza, którą czyta klient, więc wymyślanie etykiety to wymyślanie,
jak klient nazywa własne działania. `principals:` jest już naszą propozycją, nie odczytem — pomnożenie
tego przez czternaście niepotwierdzonych komend pomnożyłoby też założenie.

**Konsekwencja rezygnacji z `emits:`, którą widać dopiero teraz.** Pytanie „czy to wejście ma już
komendę" przestało być liczalne maszynowo: `command` niesie `process`, a nie listę zdarzeń, więc
powiązanie komenda→zdarzenie żyje wyłącznie w komentarzu cytującym `C-nn`. To jest cena decyzji
z 5.5, zapłacona świadomie — alternatywą była lista, której kompletności żadna brama nie sprawdzi.
Spis z 5.5 liczy komendy z `example` i po 5.6 mierzy już nie to; zostaje jako zapis tamtego pomiaru,
nie jako narzędzie.

**Wersje kontraktów ruszyły się drugi raz w ciągu dnia**, po 5.6. Tym razem nie przez zmianę
mechanizmu, tylko przez dopisanie deklaracji do czterech kontraktów — czyli zwykłą zmianę treści
umowy, dokładnie to, co `contract_version` ma odnotowywać:
`ClinicalVisit ae645a1c61f7 → 1b73eddb24c3`, `PayerSettlement d876412fe382 → 7f5e4371da34`,
`VisitSettlement 90bb66ae79bf → 4d78c7c2eed2`, `AccountingMonth 1cb46129609a → 715848338a42`.

**`source:` dodane do `command` tego samego dnia.** Cytaty `C-nn` przeniosły się z komentarzy do
deklaracji: 9 z 10 komend niesie dziś pointer do materiału, w tym samym sensie, w jakim ma go `rule`.

Dwie rzeczy wyszły przy przenoszeniu i obie są warte więcej niż samo pole.

**`close_settlement` potwierdziło się niezależnie.** Zadeklarowałem ją w 5.6, zanim przeczytałem
katalog komend, więc bez cytatu. Szukając źródła znalazłem `C-30 „Zamknij wizytę komercyjnie"`,
która w katalogu produkuje `E-53 / E-56` — a przykłady tej komendy emitują dokładnie
`visit_closed_commercially` i `visit_closed_without_payment`. Dwie strony zgodziły się bez mojego
udziału, co jest jedynym rodzajem potwierdzenia, jaki tu cokolwiek znaczy.

**`open_month` nie ma źródła i to jest znalezisko, nie niedbałość.** Warsztatowy diagram §3.1 otwiera
miesiąc łańcuchem checków wyzwalanym cronem i oznacza na nim dokładnie jedną komendę —
`RetriggerVerification`. **Nikt w sali nie nazwał samego otwarcia działaniem, które ktoś wykonuje.**
Komenda istnieje w kontrakcie, bo reguły są napisane jako jej odmowy; jej pochodzenie nie istnieje,
i puste `source:` mówi to wprost. To jest dokładnie ta informacja, której komentarz by nie uniósł.

**`source` wchodzi do digestu deklaracji, więc poprawienie cytatu jest zmianą umowy i tak zostanie
zapisane.** Można by argumentować, że poprawka cytatu nie zmienia tego, co uzgodniono — ale klucz
wyjęty z digestu byłby kluczem, który wolno zmienić po cichu, czyli dokładnie tym, czemu 5.1 miało
zapobiec. **Nie wychodzi natomiast do AsyncAPI**: `C-23` to nasz wewnętrzny numer, nie sprawa
konsumenta, i `rule.source` też nie jest publikowany.

**Wersje kontraktów ruszyły się trzeci raz w ciągu dnia**, bo ósmy klucz zmienia kształt każdej
deklaracji `command`: `ClinicalVisit 1b73eddb24c3 → dc77f8c24fb3`,
`PayerSettlement 7f5e4371da34 → 49239210339a`, `VisitSettlement 4d78c7c2eed2 → 2a56057b6d41`,
`AccountingMonth 715848338a42 → e3683dfa5af9`. Argument z 5.6 o „jednym commicie" dotyczył
mechanizmu i został dotrzymany; nie obejmował dokładania klucza dzień później. Wniosek na przyszłość
jest prosty i kosztował trzy przeklasyfikowania: jeśli do DSL-a ma dojść więcej niż jedna rzecz,
dochodzą razem.

---

## Dopisek 22 września (3) — demo znalazło dwie rzeczy, których 498 testów nie znalazło

Uruchomienie całości na zaseedowanym logu TaxVision, pięć migawek raportu, dashboard i endpointy.
Zero zmian w kontraktach; wszystkie zdarzenia poza jednym przeszły prawdziwym kodem domenowym.

**Pierwsza: raport twierdził coś, czego nie znaczył.** Wypisał dosłownie „BREACHED in 1 of 5 runs.
(including 1 via the fallback ending, which conforms to the rule)". „Including" czyta się jako
dopowiedzenie do naruszeń, a odnosi się do przebiegów spełnionych. Liczby były poprawne, zdanie nie —
a w artefakcie dowodowym to gorsza połowa do pomylenia. Istniejący test asercjonował „Met in all 2
runs" i „conforms to the rule", oba prawdziwe także w wersji z błędem, więc przechodził.

**Druga, poważniejsza: ekran miał własną kopię zdań raportu i już się rozjechała.** Duplikacja była
świadoma i opisana komentarzem — „struktura zdania jest na tyle mała, że skopiowanie bije wymyślanie
wspólnego renderera". Ta ocena była słuszna, kiedy obie kopie mówiły to samo cztery razy. Zanim
ktokolwiek zestawił je obok siebie, renderer tekstowy urósł o **sześć odpowiedzi, których ekran nie
miał**: adresata (`accountable`), zmierzony `deadline`, przebieg zawieszony cudzą awarią, przebieg
sądzony pod zmienioną regułą, informację, które spełnione przebiegi doszły zakończeniem awaryjnym,
i pracę czekającą w kolejce — tej ostatniej ekran nie renderował w ogóle.

Skutek był taki, że **przebieg zawieszony przez cudzą awarię wyglądał na ekranie jak zwykły.** To
jest dokładnie ten tryb awarii, który ten produkt wykrywa zawodowo, wewnątrz tego produktu.
Rozstrzygnięte na korzyść wspólnego modułu: `PNS.Report.Sentence` trzyma zdania bez wcięć i bez
struktury, `PNS.Report` składa je wcięciami, ekran składa je HTML-em. Medium decyduje, co jest
nagłówkiem, listą i czerwienią; nie decyduje, co odpowiedź mówi.

**Test antydryfowy też okazał się słabszy, niż twierdziłem, i znów wyszło to z kontroli odwrotnej.**
Pierwsza wersja chodziła po prawdziwym raporcie i porównywała HTML ze wspólną funkcją — ale prawdziwy
log ćwiczy jedną gałąź `outcome/1`, więc wstawiona z powrotem lokalna kopia o dwóch gałęziach
**przeszła**. Druga wersja podaje ekranowi assercję z wszystkimi klauzulami naraz: naruszenie,
zakończenie awaryjne, awarię zewnętrzną i zmienioną regułę. Lokalna kopia nie przejdzie tego, nie
stając się wspólną funkcją.

Fikstury testów ekranu też były zbudowane pod jego stare potrzeby, nie pod kształt raportu — brakowało
w nich `accountable`, `duration`, `in_flight` i `under_earlier_declaration`. Czyli rozjechałyby się
tak samo.

**Kolor werdyktu — naprawione osobno.** Cała linia była czerwona, razem z klauzulą mówiącą, że
awaria zewnętrzna **nie** jest naruszeniem po stronie klienta. Zdanie „to nie jest naruszenie"
wydrukowane kolorem naruszenia mówi coś odwrotnego niż znaczy. `verdict/1` i `qualifications/1`
rozdzielają jedno od drugiego: kolor obejmuje werdykt, klauzule są wyciszone. Przypięte testem
sprawdzającym, że klasa kończy się na elemencie werdyktu, i zweryfikowane odwrotnie.

Drobiazgi z uruchomienia, zapisane bez naprawiania: drugi panel grafu („declared versus observed,
every contract") jest przy tej skali nieczytelny — czterdzieści osieroconych prostokątów, bo trzy
z czterech kontraktów nie mają handlerów; krawędź driftu drukuje się jako `(1x, 1/0 runs)`, bo nie
ma procesu, więc mianownik jest pusty.

---

## Dopisek 22 września (2) — krok formatowania w bramie, i cztery rzeczy, które to odsłoniło

`mix format --check-formatted` jest od teraz pierwszym krokiem w bramie, we wszystkich trzech
projektach. Przy okazji root wchodzi do pakietów przez `mix check`, a nie `mix test` — czyli
**`pns.check` pakietu chodzi w bramie po raz pierwszy**, razem z jego własnym formatowaniem.
Bez zmian w kodzie: 51 plików przeformatowanych, wyłącznie zawijanie linii i puste linie.

**Sprostowanie do 5.7, i to jest najważniejsza część tego dopisku.** Napisałem tam, że bez eksportu
`locals_without_parens` 14 plików nie przechodzi sprawdzenia, a z eksportem 10. Obie liczby są
nieprawdziwe, bo pomiar szedł na **nieświeżej konfiguracji formatera**. Mix trzyma rozwiązaną
konfigurację w `_build/<env>/lib/<app>/.mix/cached_dot_formatter` i **nie unieważnia jej, gdy zmieni
się `.formatter.exs` zależności.** Moja pierwsza sonda przeszła, bo dotknąłem wtedy korzeniowego
`.formatter.exs`; każda następna czytała cache sprzed zmiany. Prawdziwy stan przed sprzątaniem: 11
plików w hoście, 39 w `pns_core`, 1 w `pns_web`.

Ta pułapka jest gorsza, niż wygląda, i dlatego ma komentarz w `mix.exs` i w `ci.yml`: CI zawsze
startuje z pustym `_build`, więc **maszyna dewelopera może się z bramą nie zgadzać**, a rację ma
brama. Lokalna naprawa to skasowanie tego pliku.

**Mój `.formatter.exs` z 5.7 był w połowie zepsuty.** Miał `locals_without_parens` wyłącznie pod
`export:`, czyli dla konsumentów — a to nie jest to samo, czego używa `mix format` samego pakietu.
Skutek: fikstury w `packages/pns_core/test/support/` były jedynym miejscem w repozytorium, gdzie
kontrakt zostałby przepisany z nawiasami, czyli dokładnie odwrotnie do celu. Teraz lista jest
nazwana raz i użyta dwa razy.

**Dwa brakujące `import_deps` i jedno brakujące makro w eksporcie.** Migracje dostawały
`add(:kolumna, :map)`, bo ani root, ani `pns_core` nie importowały `:ecto_sql`. A `pns_api` — makro,
które dodałem jedną pozycję wcześniej — nie było w eksporcie `pns_web`, więc host formatował je
z nawiasami, inaczej niż sąsiadujące `pns_dashboard`. Obie rzeczy są dokładnie tym, co ten krok
w bramie ma łapać, i obie znalazły się w pierwszym przebiegu po jego dodaniu.

**Nie formatowałem na ślepo.** Pierwszy przebieg `mix format` dołożył nawiasy do kontraktów i do
migracji — cofnąłem go w całości i naprawiłem konfigurację, zanim cokolwiek zapisałem. Gdyby ten
diff poszedł do commita, DSL przestałby wyglądać jak DSL w każdym kontrakcie naraz.

---

## Dopisek 22 września — etap 5 zamknięty w całości, 5.1–5.9

Plan implementacji całego etapu jest osobno; tutaj idzie stan i to, co wyszło przy pisaniu.

**Zrobione.** `PNS.Contract.declaration_digests/0` — jeden digest na deklarację, liczony w
`__before_compile__` obok `version/0`, z tych samych deklaracji, więc nie mają jak się rozjechać.
`PNS.Digest.hash/1` już umiał haszować pojedynczy term, więc w tamtym module nie przybyła ani jedna
linia. Do tego `PNS.Migrations` v02 z kolumną `declaration_digests` na `pns_deployments` i
`record!/1`, który ją zapisuje. 400 testów, brama zielona.

**Trzy rzeczy wyszły przy pisaniu i żadnej nie było w planie.**

1. **`on_conflict: :nothing` musiało stać się `{:replace, [:declaration_digests]}`.** Pierwszy boot
   po migracji trafia w wiersz zapisany przed kolumną i `:nothing` zostawiłoby go z nullem na
   zawsze — czyli mechanizm byłby ślepy dokładnie dla aktualnie wdrożonej wersji, tej jedynej,
   o którą ktokolwiek pyta. Zamiana jest bezpieczna, bo wartość jest funkcją conflict targetu:
   wiersz niesie ten sam `contract_version`, który jest haszem tych samych deklaracji. Gdyby ta
   zależność kiedyś przestała obowiązywać, to samo `{:replace, ...}` stałoby się fałszowaniem
   historii — i dlatego stoi przy nim uzasadnienie, nie tylko opcja.

2. **Napisałem `down(version: 1)` i to zdjęłoby wszystkie tabele silnika, nie tylko v02.**
   `down/1` schodzi *do* celu, więc z zapisanej wersji 2 cel 1 daje `2..1//-1`, czyli `V02.down`
   i zaraz po nim `V01.down`. Moduledoc `PNS.Migrations` ma to poprawnie od sierpnia
   (`down(version: 2)`), ja przepisałem źle. Złapane przed uruchomieniem, ale wyłącznie dlatego,
   że akurat czytałem arytmetykę zakresu — nic tego nie sprawdza. Powód dopisany do wszystkich
   trzech plików migracji konsumentów.

3. **Ścieżka upgrade'u przeszła po raz pierwszy — i CI nigdy jej nie przejdzie.** Bazy
   `pns_prototype_test` i `pns_web_test` miały już zapisane `add_pns` na v1, więc trafiły na v2
   gałęzią `recorded < target`; sprawdzone zapytaniem, obie mają dziś znacznik `2` i kolumnę.
   Ale CI stawia bazy od zera przy każdym przebiegu, więc zawsze pójdzie gałęzią świeżą. Mechanizm
   zbudowany 21 sierpnia „zanim był potrzebny" właśnie się przydał i nadal nie ma testu; dedykowany
   test z drugą bazą zostaje na liście.

**5.1 domknięte.** `diff/2` ma kategorię `declarations` z trzema listami — dodane, usunięte,
zmienione — albo `:not_recorded`, gdy któraś strona pochodzi sprzed kolumny. `PNS.Report` wypisuje
nazwy zmienionych deklaracji, a przy `:not_recorded` mówi, że nie da się porównać, zamiast napisać
„zmienionych 0". `declaration_boundaries/1` odpowiada, kiedy każda deklaracja ruszyła się ostatnio —
i to jest jedyna rzecz w 5.1, której dziś nikt nie woła: czytelnikiem będzie 5.2. 409 testów.

Kryterium odbioru sprawdzone odwrotnie i wyszło dokładnie tak, jak miało: neutralizacja
`declaration_diff/2` czerwieni pięć testów, wszystkie z jednego bloku i wszystkie twierdzące coś
o deklaracjach; neutralizacja `declaration_boundaries/1` czerwieni dwa na 327 i nic więcej, co jest
dowodem, że 5.1 stoi bez 5.2.

**Dwie rzeczy, których lista testów z planu nie przewidziała, a są tymi ostrzejszymi.** Pierwsza:
„nowa deklaracja to narodziny, nie zmiana" — bez tego rozróżnienia pierwszy deploy po dopisaniu
eventu raportowałby zmianę reguły, pod którą żaden przebieg nie mógł być sądzony. Druga: „dzień,
w którym doszła kolumna, nie jest dniem, w którym zmieniły się wszystkie deklaracje" — wiersze
bez digestów wypadają **przed** parowaniem, bo inaczej data migracji byłaby fałszywą granicą
wypadającą w środku historii każdego klienta. Obie są dziś przypięte testem.

### 5.2 — raport przestał sądzić starą historię dzisiejszą regułą

`PNS.Trace` nie został ruszony ani o linię i to było przewidziane: każdy werdykt niósł już `from_at`,
czyli moment, w którym obietnica przywiązała się do przebiegu, a `assertions/4` trzymało pełną listę
werdyktów i wyrzucało ją po `summary/1`. Partycja to jeden `Enum.split_with/2` na danych, które były
o linię od wyrzucenia. Assercja dostała dwa klucze — `declaration_changed_at` i
`under_earlier_declaration` — a `summary/1` liczy się odtąd nad przebiegami spod aktualnej
deklaracji. 413 testów, brama zielona.

Zweryfikowane odwrotnie w dwóch miejscach, bo to dwa osobne twierdzenia. Neutralizacja partycji
czerwieni trzy testy i zostawia **wszystkie 43 testy `trace`** zielone — to jest dowód, że silnik
oceny naprawdę nie został tknięty. Neutralizacja samej klauzuli renderera czerwieni jeden test,
tekstowy; dane i zdanie są przypięte osobno.

**Poprawka do planu, wprowadzona w kodzie: granicą jest ostatnia zmiana, kropka, a nie zmiana
wewnątrz okresu raportu.** Wąska reguła przepuszczała gorszy przypadek — raport za lipiec,
uruchomiony we wrześniu, na assercji zmienionej w sierpniu: nic by się nie podzieliło i każdy
lipcowy przebieg poszedłby pod regułę, której w lipcu nie było. Szersza reguła pochłania wąską
i nie kosztuje nic: gdy assercja nigdy nie drgnęła, granica jest `nil`, a raport wychodzi bajt
w bajt taki jak wcześniej — przypięte osobnym testem, bo to jest ścieżka 99% raportów.

**Błąd, który wart jest zapisania, bo jego klasa wróci.** Napisałem `"trace:\#{trace.name}"` —
z uciekniętą interpolacją. Skompilowało się bez ostrzeżenia, `Map.get` nigdy nie trafiał w klucz,
więc granica zawsze wychodziła `nil` i całe 5.2 było martwe. **A wszystkie testy kontrolne
przechodziły**, bo stan wyłączony tego mechanizmu to dokładnie zachowanie sprzed niego. Wniosek nie
jest o interpolacji: mechanizm, którego stan bezczynny wygląda jak przypadek normalny, nie jest
przypięty testem kontrolnym — potrzebuje testu twierdzącego, że granica **została znaleziona**.
Taki test jest dziś w suicie i to on to złapał.

**Ograniczenie, świadome i zapisane:** dwa kubełki, nie N. Assercja zmieniona trzy razy w okresie
daje „przed ostatnią zmianą" i „po", a wcześniejszy kubełek miesza dwie nieaktualne reguły. To jest
mniejsza nieprawda niż dzisiejsza, która zwijała je w `satisfied`, a raport drukuje datę granicy,
więc czytelnik zawęzi `--since` sam. Historii assercji nikt jeszcze nie potrzebował.

### 5.3 — wersja silnika, i reguła, która czyni z niej coś więcej niż napis

`PNS.version/0` czyta `mix.exs` atrybutem kompilacyjnym, nie przez `Application.spec(:pns, :vsn)` —
tamto zwraca charlistę i wymaga załadowanej aplikacji, a obie te rzeczy trafiłyby jako niespodzianka
do renderera i do enkodera JSON z 5.8. Wersja jest w `header/1`, bo to własność całego artefaktu, nie
bloku kontraktu, i dzięki temu `deployment/1` nie został ruszony. Jest też kluczem `engine:` w samych
danych, bo raport przechodzi granicę także jako JSON. Pakiet stoi teraz na `0.2.0`. 417 testów.

**Ta połowa jest dekoracją i test to mówi wprost:** usunięcie linii z nagłówka czerwieni jeden test
i nic więcej. Nie-dekoracją jest `packages/pns_core/CHANGELOG.md` z regułą wpisaną do pliku — zmiana
mogąca ruszyć werdykt podnosi MINOR i dostaje linię — i **żaden test tego nie wyegzekwuje.**
Jedynym trwałym mechanizmem jest punkt 7 w skillu `review-pr`: diff dotykający
`lib/pns/{trace,graph,conformance,deployment,report,run}.ex` bez wpisu w CHANGELOG wraca do autora.
Wyzwalacz jest wąski celowo, żeby dało się go stosować bez osądu.

**Wpis `0.1.0` jest retrospektywny i nie ma własnego numeru wersji.** Wymienia pięć zmian, które już
ruszyły werdykt, zanim reguła istniała — zero przebiegów jako `basis: :no_runs`, praca w kolejce jako
`:in_flight`, rozdzielenie „próbowane i padło" od „nigdy nie próbowano", czwarty werdykt `:suspended`,
`unverified` sięgające po `trace`. Wymyślanie numerów dla wydań, których nikt nie opublikował, byłoby
drugim źródłem prawdy o sekwencji, która się nie wydarzyła.

**Pułapka przy iterowaniu, warta zapisania:** `mix check` nie dotyka bazy `dev`. Po migracji v02
`MIX_ENV=dev mix pns.report` wywalał się na brakującej kolumnie, mimo że brama była zielona.
Udokumentowana komenda bramy z `CLAUDE.md` zawiera `mix ecto.setup` i to ją pokrywa — ja puszczałem
sam `mix check`. Kogo to ugryzie następnym razem: każdego, kto po migracji iteruje samą bramą.

### 5.4 — `deadline` przeczytany, po raz pierwszy od pierwszego commita

`PNS.Run` mierzy przebieg od najwcześniejszego zdarzenia do najwcześniejszego zdarzenia z
`terminal: true`. Cztery wyniki, nie dwa: `:within`, `:exceeded`, `:overdue` (otwarty, już po czasie)
i `:open` (otwarty, jeszcze w czasie, nie produkuje zdania w ogóle). `:overdue` nie może być zlany
z `:exceeded`, bo tam czas trwania jest znany, a tu tylko dolne ograniczenie — „trwał cztery dni"
i „trwa już co najmniej cztery dni" to dwa zdania. Agregat respektuje `unverified` tak samo jak
`verified_declarations/1`. Do tego `:info` w `pns.check` na proces z `deadline` bez zdarzenia
terminalnego; na żadnym prawdziwym kontrakcie się nie odpala, bo wszystkie cztery mają terminal.
436 testów.

Neutralizacja `PNS.Run.evaluate/3` czerwieni dziesięć testów, wszystkie w `run_test.exs`, i ani
jednego z pozostałych 343 — czyli nowy moduł nie ma splątań.

**Kryterium odbioru etapu 1.7 było węższe, niż twierdzi jego własny moduledoc, i to jest
najważniejsze znalezisko tej pozycji.** Plan kazał sprawdzić, czy przy zdjęciu filtra `unverified`
czerwieni się też stary test — i nie czerwienił się. Tamten test sprawdza `process.declarations`,
czyli jeden klucz, a 5.4 dołożyło `duration:`, czyli **drugą drogę, którą ta sama niepotwierdzona
deklaracja mogła wejść do raportu**. Moduledoc mówił „nie zawiera `deadline` oznaczonego
`unverified`", a test mówił coś węższego o jednym kluczu. Kryterium jest teraz strukturalnym
spacerem po całych danych procesu, więc następna pozycja dokładająca trzecią drogę jest pokryta
w dniu, w którym ląduje, a nie w dniu, w którym ktoś spojrzy.

Wyszło przy tym, że **fikstura `Promised` miała `deadline: {2, :day}` i okno assercji
`within: {2, :day}`** — ta sama liczba dla dwóch różnych obietnic. Dopóki tak było, żaden test nie
umiał odróżnić, czy wartość w raporcie przyszła z potwierdzonej assercji, czy z niepotwierdzonego
deadline'u. Rozdzielone na `{3, :day}` i `{2, :day}`, z powodem w pliku.

Dwa drobiazgi z pisania, oba warte linii. `fragment("min(?) FILTER ...")` nie ma typu Ecto, więc
wraca jako `NaiveDateTime` i każde porównanie z `DateTime` wywala się funkcją dalej — trzeba
`type(..., :utc_datetime_usec)`. I: z dwóch testów okresu tylko jeden odróżnia `having` od `where`,
bo przy `since` sprzed startu obie klauzule dają to samo; komentarz przy drugim twierdził więcej,
niż ten test pokazuje, i został poprawiony zamiast zostać jako fałszywa etykieta.

### 5.5 — eksperyment falsyfikacyjny na `command`. Wynik: mieszany, i to jest wynik

Zero zmian w kodzie. Jeden skrypt jednorazowy, puszczony dwa razy — w hoście (4 kontrakty)
i w `packages/pns_core` pod `MIX_ENV=test` (5 fikstur). Poniżej liczby, nie wrażenia.

**Krok 0 — ile komend powinno być, mierzone bez dotykania `example`.** Zdarzenie, którego żaden
handler nie publikuje, nie ma w systemie przyczyny, więc wchodzi z zewnątrz. To jest wejście do
procesu, niezależnie od tego, czy ktoś napisał do niego regułę.

| Kontrakt | wejść | komend | wejść bez komendy |
| --- | --- | --- | --- |
| `Rehmed.ClinicalVisit` | 7 | 0 | 7 |
| `Rehmed.PayerSettlement` | 5 | 0 | 5 |
| `Rehmed.VisitSettlement` | 6 | 1 | 4 |
| `Taxvision.AccountingMonth` | 8 | 1 | 6 |
| **razem** | **26** | **2** | **22** |

**To rozstrzyga pytanie, które postawiłem przed eksperymentem, i rozstrzyga przeciwko mojej własnej
wcześniejszej analizie.** Trzykrotnie podawałem „dwie komendy w korpusie" jako pomiar domeny. Nie
jest: 22 z 26 wejść do procesów nie ma żadnej deklaracji, bo `command` da się dziś wyrazić wyłącznie
jako skutek uboczny napisania reguły. Korpus jest pokryty w 8%.

Dla `D-15` to jest wynik **pozytywny**, i to mocniejszy niż cokolwiek, czego się spodziewałem:
najlepszym argumentem za deklaracją commanda jest to, że przy jej braku 22 wejścia do procesu nie
zostały nigdzie zapisane, choć każde z nich ktoś musi umieć wywołać i nie każdy będzie mógł.

**Krok A — czy komenda jest funkcją jednego procesu.** Przechodzi. Obie realne komendy emitują
wyłącznie zdarzenia jednego procesu, a ich parametry zawierają pola `instance`.

**Krok B — czy `emits:` da się wyprowadzić. Nie, i różnica nie jest jednorodna.**

| Komenda | emitowane w przykładach | osiągalne przez handlery | różnica |
| --- | --- | --- | --- |
| `:close_settlement` | 2 | 2 | **0** |
| `:open_month` | 2 | 5 | **3**, w tym `accounting_month_opened` |

Czyli dla jednej z dwóch komend oba czytania „emituje" dają ten sam zbiór, a dla drugiej różnią się
o trzy zdarzenia — łącznie z tym, od którego komenda wzięła nazwę. Decyzja o wyrzuceniu `emits:`
stoi, i stoi teraz na liczbie, a nie tylko na argumencie o kompletności zbioru.

**Krok C — czy wyprowadzona capability ma co zastępować.** Tu wyszło coś, czego nie przewidziałem.

- `:open_month` — `given` niesie `actor_roles` i `actor_company`, czyli istnieje reguła poziomu 3
  (`actor_company == company_id`), i wyprowadzona capability jej nie zastąpi.
- `:close_settlement` — `given` niesie `payments` i `total_minor`. **Ani jednego pola o aktorze.**
  Ta komenda nie ma dziś żadnej kontroli dostępu; jej jedyna reguła jest niezmiennikiem
  biznesowym.

Przewidywałem, że `D-15` padnie, jeśli każda realna decyzja dostępowa okaże się poziomem 3. Wyszło
odwrotnie i ciekawiej: dla połowy korpusu wyprowadzona capability nie byłaby nadmiarowa, tylko
**jedyną kontrolą dostępu, jaka by istniała**. To jest argument za, nie przeciw.

**Krok D — promień rażenia.** Wszystkie dziewięć kontraktów zmienia `version/0` po dołożeniu pustej
siódmej grupy. Pary przed/po zapisane do wklejenia w commit 5.6, wzorem `7c229c333c21 →
0343089e9d75` z 6 sierpnia. Przykład: `Taxvision.AccountingMonth` `7ac66ea1bb9e → 0bc94dd13b5d`.

**Kontrola odwrotna nie przeszła, i to jest osobne znalezisko.** Miałem puścić ten sam spis na
`:qualify_referral` z `UniversalityGate.TreatmentEpisode` — komendy z domeny świadomie zmyślonej —
i sprawdzić, czy choć jedna kolumna wychodzi inaczej niż dla realnych. Wychodzi identycznie jak
`:close_settlement`: różnica B pusta, zero pól o aktorze. Czyli **ten spis nie odróżnia komendy
wymyślonej od prawdziwej, kiedy prawdziwa jest prosta.** Jedyną komendą, która dała wyróżniające
się wyjście, jest `:open_month` — dwie reguły, reguła o aktorze, niepusta różnica B. Dla ciekawego
przypadku n = 1.

**Werdykt, jedną linią: `D-15` się broni, kształt z listy foundera padł, a `principals:` nie ma
w korpusie oparcia.**

- **Broni się:** deklaracja jest potrzebna (22 nieopisane wejścia) i wyprowadzalna (krok A), a dla
  połowy korpusu byłaby jedyną kontrolą dostępu (krok C).
- **Padło:** `emits:` jako klucz deklaracji. Dwa czytania, prowadzalnie różne w korpusie, żadnej
  bramy na kompletność.
- **Materiał nie rozstrzyga:** `principals:`. Silnik zna tylko `PNS.Auth.Actor` z `roles` jako
  stringami i `system_actor/0`; korpus niesie `actor_roles: ["accounting"]`, czyli rolę, nie typ
  principala. Zamknięty zbiór `[:human, :system]` byłby **naszym wymysłem, nie odczytem z korpusu** —
  i to trzeba powiedzieć founderowi wprost, bo to jest wejście, którego `D-18` wiersz 3 wymaga,
  a którego nie ma.

**Co z tego wynika dla 5.6.** Wchodzi, ale w węższym kształcie i z jawnie nazwanym długiem: klucze
`label`, `process` i `payload` mają oparcie w korpusie, `principals:` nie ma i jest propozycją do
zatwierdzenia, a dopisanie 22 brakujących komend jest robotą warsztatową z process ownerem, nie
robotą w silniku. Nie ma sensu generować deklaracji dla wejść, których nikt nie nazwał.

### 5.6 — siódma deklaracja i `accountable`, jednym commitem

`command :nazwa, label:, process:, principals:, payload:`. Bez `emits:` — decyzja z 5.5, teraz
z liczbą za sobą. `accountable:` na procesie, jako rola i **osobny klucz od `owner:`**, który na
evencie trzyma moduł; jeden klucz o dwóch typach jest dryfem, który ta biblioteka wykrywa zawodowo.
Oba w jednym commicie, bo siódma grupa rusza `version/0` każdego kontraktu nawet przy zerowej
liczbie komend, a jedna przeklasyfikacja historii jest tańsza niż dwie. Cena zapłacona raz i jawnie:

| Kontrakt | przed | po |
| --- | --- | --- |
| `Rehmed.ClinicalVisit` | `7d5f580c39a6` | `ae645a1c61f7` |
| `Rehmed.PayerSettlement` | `30e7a299b62a` | `d876412fe382` |
| `Rehmed.VisitSettlement` | `f726e92ad49d` | `90bb66ae79bf` |
| `Taxvision.AccountingMonth` | `7ac66ea1bb9e` | `1cb46129609a` |

Cztery nowe bramy kompilacyjne, każda wzorowana na istniejącej: duplikat nazwy komendy, `process:`
spoza kontraktu, `example` wskazujący niezadeklarowaną komendę (trzeci wskaźnik obok `example.rule`
i `event.depends_on`) i równość zbioru parametrów przykładu z zadeklarowanym `payload:` — równość,
nie podzbiór, bo ten DSL nie ma opcjonalności nigdzie. Plus zamknięty zbiór `principals` i typy
payloadu komendy przez ten sam gate, co event. **Neutralizacja każdej z czterech czerwieni dokładnie
jeden test, sama.** 374 testy.

**`principals:` i `accountable:` dostały czytelników w tym samym commicie**, bo inaczej byłyby
ozdobą w dniu pierwszym — a etap 2 istniał po to, żeby takie kasować. `PNS.Command.permits?/3`
rozstrzyga poziom 2; `accountable` wychodzi w nagłówku procesu w raporcie.

**`permits?/3` rzuca dla niezadeklarowanej komendy, nie zwraca `false`.** Odmowa i nazwa, której nie
ma, to dwie różne odpowiedzi, a zwracanie pierwszej w miejsce drugiej znaczy, że przemianowana
komenda zaczyna po cichu odmawiać wszystkim — czyli ta sama awaria, którą deklaracja miała usunąć,
wprowadzona poziom niżej.

**Nie wpisałem `accountable` do czterech prawdziwych kontraktów i to jest decyzja, nie
niedokończenie.** Rola adresata jest wiedzą z warsztatu, a wymyślenie jej byłoby tym samym błędem co
wymyślenie nazwy zdarzenia. Stan faktyczny brzmi „nikt nie uzgodnił, do kogo to idzie" i tak właśnie
wygląda dziś wyjście bramy: `mix pns.check` daje 5 ostrzeżeń zamiast 1, cztery nowe to dokładnie te
cztery procesy. Wpisane są tylko dwie fikstury, obie świadomie zmyślone.

**Brama uniwersalności zaczerwieniła się z projektu i jej literał został zaktualizowany z powodem
w pliku.** Dwa nowe słowa, `principals` i `accountable`, i żadne z nich nie przyszło z drugiej
domeny — kryterium etapu 1.2 mówi o opisaniu innej *domeny* bez nowych słów i trzyma się. Słowo
dodane po to, żeby wyrazić coś, czego wcześniej żadna domena nie umiała powiedzieć, jest innym
zdarzeniem i ma zostać odnotowane, a nie ukryte.

**Jedna zmiana poza zakresem, zamykająca klasę błędów:** `pns.docs.ex` miał zakodowaną listę
`order`, a kind obecny w `schema/0` i nieobecny w niej był **po cichu pomijany** w generowanej
referencji, podczas gdy `--check` raportował plik jako aktualny. To jedyny tryb awarii, którego
dokument generowany mieć nie może. Lista jest teraz uzupełniana o resztę `Map.keys(schema)`.

Przy okazji poprawione w `docs/contract.md`: „sześć deklaracji" na siedem, wiersz `deadline`
w tabeli znaczeń (mówił „nothing yet", a od 5.4 czyta go `PNS.Run`) i wypadnięcie `deadline`
z sekcji „Known decoration".

### 5.7 — pakiet daje się opublikować, a `pns_web` nie i wiadomo dlaczego

**Nazwa `pns` jest wolna na Hexie**, sprawdzone przed czymkolwiek innym, bo od tego rozgałęział się
cały punkt. Czyli `app: :pns`, katalog `pns_core` zostaje, żadnej przemianowywanej aplikacji.
`mix hex.build` produkuje dziś tarball bez ostrzeżeń, `mix docs` buduje się bez ani jednego —
były cztery, dwa moje i dwa zastane. 460 testów.

**Najdroższe znalezisko nie jest o metadanych.** `packages/pns_core/.formatter.exs` w ogóle nie
istniał, więc `mix format` u konsumenta przepisywał każdy kontrakt na `event(:x, label: "...")`.
Zmierzone: bez eksportu 14 plików nie przechodzi `--check-formatted`, z eksportem 10 — cztery
odzyskane to kontrakty. `packages/pns_web/.formatter.exs` obchodził to ręczną kopią listy i
**ta kopia była już niekompletna**: brakowało `external: 2`, `rule: 2`, `example: 2`. Teraz jest
jeden eksport i dwa `import_deps`.

**Pliki nie przechodzące `mix format --check-formatted` to osobny dług** — brama nie ma kroku
formatowania i nigdy nie miała, więc nikt tego nie widział. Nie sprzątam tego w commicie
o pakowaniu; do zrobienia osobno, razem z decyzją, czy ten krok wchodzi do bramy.
**Liczba „dziesięć", którą tu pierwotnie podałem, była nieprawdziwa — patrz dopisek o kroku
formatowania niżej; pomiar był zrobiony na nieświeżym cache'u Mixa.**

**`pns_web` nie da się opublikować i powód jest twardszy niż zwendorowany Mermaid.** `hex.build`
mówi wprost: *„Dependencies excluded from the package (only Hex packages can be dependencies):
pns"*. Pakiet zależy od `pns` ścieżką, a opublikowany może zależeć tylko od opublikowanych. Czyli
kolejność jest wymuszona, nie preferowana: najpierw `pns`, potem zamiana `path:` na `~> 0.2`,
dopiero wtedy `pns_web`. Metadane i tak wchodzą, plus `NOTICE` z licencją MIT Mermaida — tarball
redystrybuuje cudzy kod i wymaga atrybucji w pliku, nie w komentarzu.

**Poprawka do planu:** zakładałem asymetrię — że usunięcie `licenses:` wywali i test, i
`hex.build`, a usunięcie *pliku* `LICENSE` tylko test. Nieprawda: `hex.build` łapie oba, bo
`LICENSE` jest wymieniony w `files:`. Test zostaje mimo to, bo brama go uruchamia, a `hex.build`
nie — i tu jest druga poprawka: **`hex.build` nie działa z wnętrza aliasu**, choć samodzielnie
działa. Wyjąłem go zamiast owijać w shell-out pod krok, który i tak jest ręczny przed publikacją,
której nikt jeszcze nie zaplanował.

**Zastane, naprawione po drodze:** `packages/pns_core` nie miał `cli/0` z `preferred_envs`, więc
jego własny `mix check` wywalał się na `ecto.create` w `:dev`, zanim doszedł do pierwszego testu.
Alias był używalny tylko, jeśli ktoś sam dopisał `MIX_ENV=test`.

### 5.8 — zgodność wychodzi jako dane

`PNS.Conformance.as_data/2` plus `PNS.Conformance.Wire` w silniku, `pns_api/2` w `pns_web`,
zamontowane też na prawdziwym hoście pod `/api/pns`. 490 testów.

**Projekcja mieszka w silniku, nie w transporcie**, i to nie jest preferencja: kształt, który
konsument porównuje wersja do wersji, jest częścią tego, co ten pakiet obiecuje. Napisana
w pakiecie webowym byłaby własnością tego, kto akurat ją serwuje. Nierozstrzygnięta krotka albo
struktura **rzuca**, zamiast zostać zgadnięta — format drutowy dorabia się nieczytelnych pól po
jednym zgadnięciu naraz.

**Test jest strukturalnym spacerem, nie listą kluczy, i to już się opłaciło.** Chodzi po całym
wyniku i twierdzi, że nie ma tam atomu, krotki, struktury ani niestringowego klucza. Gdyby wymieniał
znane sobie klucze, przeszedłby, podczas gdy 5.2 i 5.4 dołożyły `declaration_changed_at` (DateTime)
i `duration` (krotka) — obie rzeczy, których `Jason` nie unosi.

**Żywy błąd, przewidziany w planie i potwierdzony, a potem jeszcze raz.**
`PNS.Web.Plug.Authenticate` schodził do `get_session/2`, które rzuca, gdy `fetch_session` nie
przebiegło — czyli w bezsesyjnym pipelinie API wywalał się na **każdym żądaniu bez bearer headera**,
dokładnie na tym nieuwierzytelnionym, które endpoint ma odrzucić czysto. Napisałem strażnika na
`:plug_session_fetch` i **to nadal nie działało**: endpoint stawia `Plug.Session`, więc ten klucz
jest zawsze, a brakuje `:plug_session`. Pierwszy strażnik wyglądał poprawnie i nie strzegł niczego;
złapał to test, nie czytanie.

**`{:forbidden, path}` staje się 403, a ścieżka jest porzucana.** Callback odpowiada celem
przekierowania, bo transport, dla którego powstał, to HTML. Przekierowanie jest daną użyteczną
wyłącznie dla przeglądarki — klient API idący za nim pobrałby stronę logowania i próbował sparsować
ją jako JSON. Znaczenie zostaje, reprezentacja należy do transportu. Drugi callback byłby gorszy:
każdy host implementowałby dwa, a `@optional_callbacks` robi z tego callback, którego może po cichu
nie być.

**Wystawiona ekspozycja, nazwana zamiast zredagowanej:** `report.deployment.in_log` niesie liczby
zdarzeń per wersja z datami, czyli dane o wolumenie cudzego biznesu — po drugiej stronie linii,
którą moduledoc `PNS.Conformance` rysuje między ścieżkami a firmami. Nie redaguję tego w pakiecie,
bo pakiet decydujący o wrażliwości cudzych danych to pakiet znający cudzą domenę. Zapisane
w moduledoku endpointu, żeby resolver hosta mógł zdecydować.

**Jason zadeklarowany wprost w `pns_web`** — dochodził tam wyłącznie przez `{:pns, path: ...}`, bo
Phoenix i LiveView mają go jako `optional: true`. Jedynym mechanicznym pinem „zadeklarowane, nie
odziedziczone" jest test czytający listę `deps`, bo usunięcie linii zostawia build zielony.

### 5.9 — AsyncAPI z kontraktu, i uczciwie o tym, czego standard nie unosi

`PNS.AsyncAPI.document/1` plus indeks, serwowane przez `pns_api/2` z digestem w ciele i w `ETag`.
494 testy, brama zielona.

**Zwalidowane prawdziwym walidatorem, raz, ręcznie, 22 września.** `npx @asyncapi/cli validate` na
trzech dokumentach — `ProcessShapes.Promised`, `ProcessShapes.Rig` (ma `external` i `retain`)
i `UniversalityGate.TreatmentEpisode` (ma komendę): każdy **valid, 0 błędów, 0 ostrzeżeń**. Jedna
informacja na każdym: istnieje 3.1.0. Zostajemy na 3.0.0 — podbicie wersji bez sprawdzenia, co się
w niej zmieniło, byłoby zgadywaniem. Walidatora nie ma i nie będzie w bramie: `npx` wstawiłby Node
do repozytorium, które świadomie zwendorowało bundle JS, żeby go uniknąć. Przypięte są testy
strukturalne, a to zdanie jest zapisem pomiaru, nie obietnicą, że ktoś go powtórzy.

**Co wypada i dlaczego, bo to jest treść tej pozycji, nie przypis.** `trace` nie ma w AsyncAPI
żadnej reprezentacji — czyli najostrzejsza rzecz, którą ten silnik deklaruje, jest jedyną, której
standard nie wyraża; jedzie jako `x-pns-traces`, którego żadne narzędzie AsyncAPI nie czyta. `retain`
tak samo, i tu pominięcie byłoby groźne: konsument czytający spec, który pokazuje pole i nie pokazuje,
że pole jest hashowane albo wycinane, został okłamany przez przemilczenie. `external` jest nieobecny
**świadomie** — oczywiste mapowanie na `servers` jest błędne, bo external nazywa się od faktu
biznesowego, nigdy od dostawcy, a `server` to adres dostawcy; zmapowanie złamałoby regułę przez jej
opublikowanie. Kanał nie jest procesem: kanał to adres, a proces to przebieg, więc `address` jest
jawnie `null`.

**Bramka międzypozycyjna działa w obie strony.** Test pinuje `Map.keys(PNS.Contract.schema())`, więc
ósma deklaracja zaczerwieni się tutaj i ktokolwiek ją doda, musi powiedzieć, co specyfikacja z nią
robi. `command`, który wszedł jedną pozycję wcześniej, dostał miejsce jako `x-pns-commands` —
deklaracja istniejąca i nieprodukująca niczego w specyfikacji to dokładnie ta awaria, którą miał
`mix pns.docs`.

**Dwa moje testy twierdziły więcej, niż pokazywały, i oba złapała kontrola odwrotna, nie czytanie.**
Pierwszy porównywał digesty dwóch fikstur przy „tej samej treści w innej kolejności" — a dwa
różne moduły mają z definicji różne `info.title`, więc mierzył nazwę modułu. Drugi asertował
`digest(doc) == doc["info"]["x-pns-digest"]` jako test na to, że digest liczy się **bez siebie** —
i nie czerwienił się, gdy podmieniłem usunięcie klucza na wstawienie placeholdera, bo funkcja jest
spójna ze sobą cokolwiek haszuje. Teraz testuje to, co trzeba: że digest nie zależy od tego, co
siedzi w kluczu digestu. To już drugi raz w tym etapie, kiedy krok „zweryfikuj odwrotnie" wyłapał
test-atrapę — pierwszy był przy 5.4 z `having` kontra `where`.

---

## Dopisek 21 września (12) — przegląd architektury EHOS-a: czego prototyp jeszcze nie ma

Nic tu nie zostało zbudowane. To jest lista zobowiązań wynikających z przeglądu, który ustalił relację
PNS-a do EHOS-a i przeszedł przez trzynaście rozbieżności między wizją a obiema bazami technicznymi.
Rozstrzygnięcia żyją w `~/Projects/ai/eh-os/`: `ARCHITECTURE.md` (decyzje `D-01`…`D-22`),
`ALIGNMENT.md` (rozbieżności `A-01`…`A-13`) i `DECISIONS.md` (zdania do zatwierdzenia przez foundera).

**Ustalenie ramowe.** PNS zostaje wąskim pakietem: kontrakt, log zdarzeń, zgodność. EHOS jest osobnym
systemem obok, z własnym cyklem życia i własną bazą, który uruchamia workloady klienta. PNS jest
biblioteką w runtime klienta, EHOS nie jest warstwą nad nią. Część poniższych pozycji to zmiany w DSL,
bo prototyp adaptuje się do architektury, a nie odwrotnie — tak to zostało zapisane w
`ARCHITECTURE.md`.

Trzynaście pozycji: 1–3 to zmiany w kontrakcie, 4–5 wychodzą ze struktury projektu klienta, 6–8 to
czego silnik jeszcze nie wystawia, 9–13 przyszło ze spotkania z founderem.

Ta lista nie pokrywa całego zobowiązania wobec kontraktu. `ARCHITECTURE.md` mówi wprost, że siedem
decyzji, `D-15`…`D-21`, wymaga od języka kontraktu nowej deklaracji albo klucza. Niżej jest pięć z
nich: `D-15` (pozycja 1), `D-18` (2 i 3), `D-16` (7), `D-20` (9) i `D-21` (11). Poza listą zostają
`D-17` — zatwierdzenie przypięte do wersji kontraktu, a każdy inny widok jest tylko renderem — i
`D-19`, trzy rodzaje workloadu, z których kontraktu potrzebuje jeden. Obie trzeba przejść osobno;
dopóki tego nikt nie zrobił, nie wiadomo, czy niosą robotę dla silnika, czy wyłącznie dla EHOS-a.

### Zmiany w kontrakcie

|  | Co | Dlaczego |
| --- | --- | --- |
| 1 | **`command` jako siódma deklaracja**: nazwa, `process`, jakie eventy emituje, jakie typy principala mogą go wywołać | Dziś command istnieje tylko jako klucz w `example`. Z deklaracji wyprowadza się capability, zamiast pisać osobną listę nazw uprawnień, która i tak by się rozjechała (`D-15`) |
| 2 | **`owner` na `process`**, jako rola a nie nazwisko | Raport mówiący „reguła złamana w 1 z 40 przebiegów" musi mieć adresata. Dziś `owner` jest tylko na evencie i opcjonalny (`D-18`) |
| 3 | **Klasyfikacja odpowiedzialności wyprowadzana, nie deklarowana** | `rule` z funkcją → kod; `trace` z deadlinem → platforma; command tylko dla principala-człowieka → człowiek. Wymaga pozycji 1, żeby trzeci wiersz był wyprowadzalny (`D-18`) |

Deklaracja commanda ma trzech konsumentów, nie jednego. Poza capability i klasyfikacją
odpowiedzialności wychodzi z niej klient generowany dla aplikacji, który opakowują CLI i MCP
(`D-12`). Sam klient jest robotą EHOS-a, nie PNS-a, ale wychodzi z kontraktu, więc deklaracja musi
nieść tyle, żeby dało się go wygenerować — to jest ten sam wymóg co pozycja 9.

Pierwszy krok to półdniowy eksperyment, nie implementacja: czy `command` da się podnieść z klucza w
`example` do deklaracji, nie rozwalając czterech istniejących kontraktów. Materiał jest: cztery
kontrakty, 29 eventów, dwa commandy już nazwane atomami (`:open_month`, `:close_settlement`). Jeśli nie
wyjdzie, `D-15` jest błędne i lepiej wiedzieć to przed rozmową z founderem niż po.

### Nowe bramki kompilacji

- command zadeklarowany poza namespace'em swojej aplikacji (klasa konfliktu `C-2` w `ARCHITECTURE.md`)
- proces bez odpowiedzialnego właściciela
- generowany test odmowy per command: wywołanie bez capability musi zostać odrzucone. Mechaniczne,
  więc generowane. Granularność commanda pozostaje osądem warsztatowym i nie jest sprawdzana, z tego
  samego powodu, dla którego harness nie ma opinii o tym, czy coś powinno być eventem

### Struktura projektu klienta

Dziś: jeden projekt mix, katalogi `lib/taxvision` i `lib/rehmed`, jedno `Repo`, jedna migracja
`create_taxvision_module_tables`. Model docelowy ma cztery poziomy (`D-02`):

```
jednostka wdrożenia   jeden artefakt, jeden kontener, jeden runtime, jeden schemat, jeden user bazy
  └ własność          to, co posiada jeden zespół — MOŻE się różnić od poziomu wyżej
      └ proces        jedna aplikacja OTP, jeden kontrakt, własne tabele
          └ moduł     szczegół implementacyjny
```

- aplikacja OTP per proces, każda tabela ma jednego właściciela, pilnowane przez `boundary`
- schemat i user bazy per projekt × środowisko, nie per proces. Schemat per proces broni przed
  procesem tego samego zespołu, czyli przed niczym, a kosztuje pulę połączeń na proces
- zero dostępu między schematami. Dane innego procesu przez jego punkt wejścia, nigdy przez bazę.
  Wygenerowany klient ukrywa transport, żeby wydzielenie procesu do osobnego projektu było zmianą
  konfiguracji, a nie przepisywaniem zapytań

Dwie rzeczy wyszły dopiero przy weryfikacji tego modelu i są robotą do wykonania.

**4. Własność tabeli jest konwencją egzekwowaną tylko na ścieżce idiomatycznej.** Przy jednym
schemacie i jednym userze baza nie egzekwuje nic: każda aplikacja OTP w projekcie może odczytać każdą
tabelę. To jest cena uniknięcia puli połączeń na proces i jest przyjęta świadomie. Ale egzekwowanie
powyżej bazy ma dziurę, której wcześniej nie nazwaliśmy:

| Jak sięgnąć po cudzą tabelę | Co to łapie |
| --- | --- |
| `from(e in InnyProces.Schema)` | `boundary`, przy kompilacji: moduł nieeksportowany, join niewyrażalny |
| `from(p in "inna_tabela")` | nic dzisiaj. Nie pada nazwa modułu, więc `boundary` nie ma czego sprawdzić |
| `Ecto.Adapters.SQL.query/3` | nic, i raczej nic nie będzie |

Środkowy wiersz jest domykalny i jest bliżej domknięcia, niż zapisano: callback już istnieje i już
chodzi. `Taxvision.Repo.prepare_query/3` (`lib/taxvision/repo.ex:25`, z 4 sierpnia) dostaje całe
`%Ecto.Query{}` przed wykonaniem, a `tables/1` obok niego wyciąga każdą dotkniętą tabelę z `from`,
`joins` i podzapytań, łącznie z nazwami podanymi jako string — razem z pułapką, przez którą tabela
joina nie siedzi w `source`. Brakuje więc nie callbacka, tylko dwóch rzeczy: mapy „tabela →
właściciel", której dziś nie deklaruje nic, i samej odmowy, bo na razie wynik ląduje w słowniku
procesu pod `:pns_trace_tables` i nikt go nie czyta. Dopóki tego nie ma, zdanie „podział
procesu jest tani, bo wystarczy przenieść tabele" jest prawdziwe warunkowo: tylko jeśli konwencja się
trzymała, a to trzeba sprawdzić w momencie podziału, nie założyć.

**5. Wywołanie do procesu-brata nie może uczestniczyć w transakcji wołającego**, także wtedy, gdy oba
siedzą w tym samym runtime. W jednym BEAM-ie z jednym `Repo` uczestniczenie jest domyślne, a domyślne
sprzężenie transakcyjne zamienia późniejszy podział z przeniesienia danych w zmianę semantyki, outbox
albo sagę, i robi to dokładnie w momencie, gdy podział jest potrzebny. To jest ta sama dyscyplina co
przy podziale dispatchu po granicy transakcji, rozciągnięta na granicę procesu.

### Czego silnik jeszcze nie wystawia

|  | Co | Dlaczego |
| --- | --- | --- |
| 6 | **Endpoint z danymi zgodności**, generowany przez PNS | EHOS nie może czytać bazy klienta, bo to byłoby dokładnie to przekraczanie schematów, które zakazaliśmy. Zgodność przechodzi granicę przez API, a endpoint generuje silnik, żeby nie było czternastu implementacji |
| 7 | **Generowanie i serwowanie specyfikacji**: AsyncAPI z kontraktu, OpenAPI z routera, oba pod endpointem, oba z digestem | EHOS porównuje digest instancji z tym zapisanym przy buildzie. Endpoint jest weryfikacją, nie źródłem prawdy: wersjonowana specyfikacja pochodzi z pakietu deploymentu (`D-16`) |
| 8 | **Agregat `deadline` w raporcie zgodności** | `deadline` procesu jest zadeklarowany i nie czyta go nikt: jedyni czytelnicy to filtr `unverified` w `PNS.Conformance` i renderer, który go wypisuje. Kształt jest ustalony od 6 sierpnia i niezmieniony — „N z M przebiegów przekroczyło `deadline`", retrospektywnie, w `PNS.Conformance.report/2` |

Pozycja 8 była tu zapisana jako „monitor zatrzymanego procesu", obejmujący `deadline` i `cadence`
razem — i w tym brzmieniu cofała po cichu własne rozstrzygnięcie. 6 sierpnia te dwie rzeczy zostały
rozdzielone i poszły w przeciwne strony; patrz „Rozstrzygnięte 6 sierpnia" niżej.

- `deadline` — zwężony, nie odrzucony. Liczy się wyłącznie z logu: z przebiegów, które już się
  zaczęły, ile przekroczyło uzgodniony czas trwania. Zero wiedzy o firmach, ten sam kształt, który
  `PNS.Trace` liczy dziś dla `violated`/`satisfied`. To jest pozycja 8 powyżej i jest to specyfikacja
  gotowa od sześciu tygodni, nie nowy pomysł z przeglądu. Sprawdzone przy tej korekcie: nadal
  niezbudowana.
- `cadence`'s okno „never observed" — odrzucone, nie odłożone, i argument był strukturalny: żeby
  wykryć instancję, której nie ma, trzeba wiedzieć, które powinny istnieć, a to jest wiedza o
  firmach, której silnik świadomie nie ma. Encja, która nie wyemitowała nic, jest niewidzialna dla
  systemu opartego wyłącznie na logu.

Słowo „monitor" dokładało do tego jeszcze trzecią rzecz, której żadna z tamtych decyzji nie
obejmowała: liczenie na żywo zamiast w okresowym raporcie. Ekran na żywo został odrzucony osobno,
tego samego dnia.

Jedno mogłoby przywrócić `cadence` do gry, i warto to sprawdzić zamiast przepisywać pozycję z
powrotem: EHOS wie, jakie workloady i jakie instancje powinny działać, więc mianownik, którego log
nie ma, mógłby przyjść spoza silnika. Gdyby tak było, jest to nowa decyzja z datą i z nazwanym
źródłem mianownika — nie „znany brak, nazwany w ADR".

### Po spotkaniu z founderem, 21 września — pięć pozycji, których wcześniej nie było

Powyższe wyszło z przeglądu technicznego. Poniższe z rozmowy o modelu biznesowym tego samego dnia i
dotyczy PNS-a bezpośrednio.

**9. Cały PNS ląduje po stronie Community, i to jest wiążące od pierwszego commita.** Produkt ma dwie
edycje: Community otwarte, Enterprise jako fork Community. Linia biegnie przez spójność między
aplikacjami: kontrakt, log zdarzeń i zgodność w obrębie *jednej* aplikacji są darmowe, a wnioskowanie
po wielu aplikacjach, czyli diff specyfikacji, klasy konfliktu i analiza wpływu, jest płatne.

Dla PNS-a wynika z tego jedna konkretna rzecz, którą trzeba trzymać od początku: PNS musi wystawiać
to, czego potrzebuje analiza międzyaplikacyjna, mimo że sam jej nie robi. Wygenerowane specyfikacje,
dane grafu i wynik zgodności muszą być konsumowalne przez coś, czego Community nie zawiera. Jeżeli to
nie będzie wystawione od razu, Enterprise przestanie być forkiem i stanie się rozjeżdżającą się kopią
w rok.

**10. Raport podaje wersję silnika, który go policzył.** Raport zgodności jest wyliczeniem, a ten
rekord zawiera kilka korekt tego, co liczy się jako drift: zero przebiegów, praca w kolejce, „nigdy
nie próbowano" kontra „próbowano i padło". Każda zmieniła wynik. Przy dwóch klientach na dwóch
wersjach silnika to samo pytanie dostaje dwie odpowiedzi, a raport jest dowodem dla audytora. Wersja
silnika obok `contract_version`, w tym samym miejscu, które już niesie dwie wersje.

**11. Reguły organizacji dziedziczone przez każdy kontrakt.** Firma ustala standard raz — płatność
powyżej progu wymaga drugiej akceptacji, pole z danymi osobowymi nie może trafić do żadnego eventu — i
reguła jest wciągana do każdego kontraktu, zamiast być powtarzana w każdym z osobna. Kontrakty
zostają własnością właścicieli procesów; reguły organizacji są warstwą nad nimi.

Kształt jest otwarty: deklaracja, check, czy generowana dokładka do kontraktu. Raport musi umieć
odróżnić złamanie reguły procesu od złamania reguły organizacji, bo idą do dwóch różnych ludzi. To
jest ten sam argument o adresacie co przy `owner` na procesie.

**12. Uprawnienia do odczytu eventów.** Pytanie z rozmowy dotyczyło lokalizacji logu i uprawnień, a
pierwsza połowa ma już odpowiedź, tylko nie w tym pliku: `D-03` rozstrzyga, że log domenowy zostaje
własnością aplikacji i jest jedynym podłożem, na którym liczy się zgodność, a historia przekrojowa
jedzie osobnym strumieniem integracyjnym — świadomie zaprojektowanym podzbiorem, przez outbox, z
własnym kontraktem, własnymi uprawnieniami i własną retencją. Eventy zostają więc tam, gdzie leżą, i
nie ma dylematu „wynieść albo stracić historię międzyaplikacyjną".

Otwarte zostaje to drugie: jak te uprawnienia wyglądają per event. Event niosący kwotę nie może być
czytelny dla aplikacji, która kwot widzieć nie może, a `D-03` mówi tylko tyle, że strumień ma własne
uprawnienia.

Z `D-03` wychodzi też pozycja, której na tej liście nie ma, a która ma w ADR klauzulę „od pierwszego
commita": zgodność międzyaplikacyjna potrzebuje identyfikatorów korelacji spinających oba podłoża.
`PNS.Event` niesie dziś `correlation_id` i `causation_id`, ale oba są per request w obrębie jednej
aplikacji i nic nie przechodzi przez most. To jest najtańsza rzecz z całego przeglądu i jedyna, która
drożeje z każdym wierszem dopisanym do logu.

**13. Reguły wymuszające zachowanie, doklejane do kontraktu.** Kierunek produktu to certyfikowane
środowisko, z którego aplikacje dziedziczą zgodność, a to jest mechanicznie możliwe tylko wtedy, gdy
wymagane zachowanie jest przyczepione do każdego kontraktu, a nie mamy nadziei, że ktoś pamiętał. To
jest to samo, co pozycja 11, oglądane od strony sprzedaży, i dlatego 11 jest ważniejsza, niż wygląda.

*Zastrzeżenie:* cała ta ścieżka stoi na założeniu, że jednostka certyfikująca przyjmie roszczenie
dziedziczone. Nikt tego nie wie, i pierwszym krokiem jest godzina z kimś, kto certyfikuje zawodowo.
Dopóki ta rozmowa się nie odbędzie, 13 nie jest robotą do zrobienia, tylko kierunkiem.

### Do poprawienia w zapisie, nie w kodzie

- **Nazwa repozytorium.** `eh-os-prototype` mówi coś przeciwnego niż rozdzielenie PNS-a od EHOS-a.
- **`licenses` w `packages/*/mix.exs`.** Hex tego wymaga przy publikacji.
- **Zakład 3 w ADR** („wygenerowany kod plus harness bije kompetentny zespół z powszechnym AI") został
  w przeglądzie przeformułowany: generowanie nie jest produktem, tylko tym, co sprawia, że opłaca się
  napisać kontrakt. Nie da się jednocześnie zakładać, że kod jest tani i nieznanej jakości, i że nasze
  generowanie jest lepsze. Nowy zakład brzmi: czy kontrakt może zostać cienki, skoro generowanie ma
  drugie wejście, czyli materiał warsztatowy. Wczesny sygnał: trzeci raz ręcznie pisany ten sam
  formularz.
- **Linia open source w §16–17 jest nieaktualna.** Rekord opisuje silnik otwarty w całości, z
  przychodem z warsztatu, wdrożeń, wsparcia i katalogu procesów referencyjnych. Spotkanie z founderem
  21 września ustaliło co innego: biznes produktowy, Community otwarte, Enterprise płatne jako fork,
  przychód abonamentowy, wdrożenia przez sieć partnerów. Rekord wymaga przepisania pod pozycję 9.
- **Materiał warsztatowy jest drugim wejściem generowania i nic go nie weryfikuje.** Starzeje się po
  cichu, a jakość generowania spada bez sygnału. Przy drugim warsztacie u tego samego klienta materiał
  trzeba odświeżyć, a nie dopisać.

---

## Dopisek 23 sierpnia (11) — trzeci ekran: graf, krok 2 z dopisku (10) faktycznie zbudowany

Domyka dopisek (10). `PNS.Web.Live.Graph`, `/graph`, trzeci tab w nawigacji. Dwa panele, asymetryczne
świadomie, zgodnie z ADR §9 („navigation is per-process, never global"):

- **Declared shape** — `PNS.Graph.declared_to_mermaid/2`, per wybrany proces (selektor `<select
  phx-change>`, lista z `PNS.Registry.contracts()` × `c.processes()`). Prawdziwy jest nawet dla
  kontraktu z zerem przebiegów.
- **Declared versus observed, every contract** — `PNS.Graph.overlay/1` + `to_mermaid/2`, globalny.
  Zostaje globalny nie z lenistwa: `to_mermaid/2` zawsze dobiera węzły z całego `static()`, niezależnie
  od tego, jaką listę krawędzi mu się poda — pre-filtrowanie overlayu per proces odcięłoby krawędzie,
  nie węzły, i dałoby diagram z osieroconymi skrzynkami. Zawężenie tego jest pracą w silniku, nie tym
  ekranem.

„Statyczny graf globalny" (trzecia opcja z rozmowy) nie dostał osobnego renderera — overlay już
zawiera każdą zadeklarowaną krawędź, choćby martwą, więc jest tym samym widokiem bez podświetlenia
stanu. Zawężenie zakresu zapisane wprost, nie przemilczane.

**Zero zmian w `packages/pns_core`.** Wszystko: `PNS.Graph`, `PNS.Registry`, `PNS.Deployment`,
`PNS.Conformance` już było wyeksportowane z `PNS` (`lib/pns.ex`), i dwie z trzech funkcji renderujących
mermaid już istniały gotowe do użycia.

**Pierwszy `phx-hook` w tym kodzie, i jedna prawdziwa pułapka znaleziona wyłącznie ręcznym
sprawdzeniem w przeglądarce, nie przez `mix check`.** Mermaid (`mermaid@11.17.0`, wektorowany
jednorazowo przez `npm pack mermaid@11`, nie jako zależność npm tego builda —
`packages/pns_web/assets/js/vendor/mermaid.min.js`) nie mógł zostać zaimportowany przez esbuild do
`app.js`, mimo że to jedyny plik JS, jaki trzeba było dodać. Wektorowany plik zakłada klasyczne
wykonanie skryptu globalnego: `var __esbuild_esm_mermaid_nm` na najwyższym poziomie staje się
właściwością `globalThis` tylko wtedy, gdy skrypt wykonuje się w prawdziwym zasięgu globalnym — a
`import "./vendor/mermaid.min.js"` w pliku bundlowanym przez esbuild zawija ten kod we własny zasięg,
więc drugi wiersz pliku (`globalThis.mermaid = globalThis.__esbuild_esm_mermaid_nm["mermaid"].default`)
czytał inną zmienną niż ta, którą pierwszy wiersz właśnie ustawił, i wywalał się w głębi własnego
kodu inicjalizacyjnego Mermaid z `TypeError: Cannot read properties of undefined (reading 'mermaid')`
— złapane jako `mermaid version 11.17.0` „Syntax error in text" na ekranie, dopiero po ręcznym
zalogowaniu się i kliknięciu w `/dashboard/graph`, zero sygnału z `mix check`/`Phoenix.LiveViewTest`.
Poprawka: `mermaid.min.js` jest teraz osobnym, klasycznym `<script defer>` w `root.html.heex`, przed
`app.js` (kolejność dokumentu decyduje dla dwóch `defer`), kopiowanym (nie bundlowanym) do
`priv/static/assets/` trzecim krokiem aliasu `assets.build` w `mix.exs`. `app.js` woła gołe `mermaid.*`
— identyfikator rozwiązuje się przez normalny łańcuch zasięgów do prawdziwego obiektu globalnego,
niezależnie od własnego zawinięcia przez esbuild.

Hook `MermaidRender` w `app.js`: diagram trzymany w `data-graph` (nigdy jako zaufany HTML — HEEx
escapuje go jak każdą inną interpolację), `mounted()`/`updated()` resetują `el.textContent` z tego
atrybutu i wołają `mermaid.run({ nodes: [el] })` — bez resetu drugi `run` na tym samym węźle nie ma czego
przerysować, bo mermaid zamienia zawartość na SVG przy pierwszym uruchomieniu.

**Efekt na rozmiar bundla, zaakceptowany świadomie.** `app.js` wrócił do ~143KB (mermaid nie jest już
jego częścią); `mermaid.min.js` to osobny, statyczny plik 3,5MB, serwowany przez ten sam,
już-istniejący wiersz `Plug.Static` co `app.js`/`app.css` — zero nowej konfiguracji po stronie hosta.

Testy: `packages/pns_web/test/graph_live_test.exs` (3 — pełna pętla przez prawdziwy router z realnymi
kontraktami, brak procesu w ogóle, zaznaczenie wybranego procesu w `<select>`). 32 testy w
`packages/pns_web`, było 29. `mix check` zielony wszędzie: 50 + 311 + 32 = 393.

Zweryfikowane ręcznie, w prawdziwej przeglądarce, dwa razy (raz złapało powyższą pułapkę, raz po
poprawce): login → `/dashboard/graph` → oba diagramy renderują się jako SVG (nie jako goły tekst
`flowchart`), przełączenie procesu w `<select>` przerysowuje diagram kształtu bez przeładowania strony,
zero błędów w konsoli.

**Zaparkowane, zapisane, nie zaimplementowane: analiza zmiany deklarowanego kształtu w czasie.**
`PNS.Deployment.all/1` (pełna historia wdrożeń), `diff/2` (porównanie dwóch zapisanych wdrożeń),
`versions_in_log/2` (które wersje realnie wystąpiły w logu, z zakresem czasu) już istnieją i są gotowe.
Czego nie ma: wyboru w UI dwóch punktów historii do porównania, naniesienia diffu na sam diagram, i
rekonstrukcji pełnego historycznego kształtu — `pns_deployments` zapisuje płaską listę
`events`/`edges`, nie strukturę `stages`/`trace`/`terminal`, której potrzebuje `declared_to_mermaid/2`.
Bezpiecznie odłożone: `record!/1` jest addytywne (jeden wiersz na nowe wiązanie, nigdy nie nadpisuje),
więc dopisanie bogatszego pola później nie wymaga migracji — stare wiersze zostają płaskie, nowe
dostają więcej, ten sam idiom co `deployment.ex`'s własny fallback dla logu sprzed tabeli. Jedyny koszt
zwłoki: pełna rekonstrukcja będzie możliwa tylko od dnia, w którym bogatsze pole zacznie być zapisywane
— nie retroaktywnie.

README-owy wiersz non-goali o grafie w UI nie jest jeszcze poprawiony — to osobny krok, zgodnie z
zasadą „README dogania stan faktyczny" (dopisek 9); zrobię go, gdy to zostanie zacommitowane.

## Dopisek 23 sierpnia (10) — Etap 4 był krok 1 z dwóch, nie werdyktem na zawsze; graf wraca do planu dashboardu

Rozmowa o kierunku dashboardu: (a) przenieść `mix pns.graph`/`mix pns.report` z dev-only CLI do
dashboardu na produkcji, (b) prawdziwe konta i prawdziwy login broniący dostępu.

**(b) zaparkowane, nie robimy tego tutaj.** Po namyśle: logowanie i zarządzanie kontami to zakres
osobnego, przyszłego projektu-szablonu (login + `pns` jako zależność + pełen deployment), nie tego
repozytorium — zgodnie z „nie budujemy tu aplikacji dla nikogo". `PNS.Web.LocalLogin` zostaje tym, czym
jest: prowizorką. Zero zmian kodu.

**(a) — cofnięcie generalizacji, nie złamanie non-goala.** Wiersz README „The observed-overlay graph,
in a UI" cytuje Etap 4 (`PLAN.md`, wyżej w tym pliku, przed pierwszym dopiskiem z 23 sierpnia): „11
zdarzeń dało 3 krawędzie i diagram nie powiedział nic, czego nie mówiła posortowana lista." To był
sprawdzian jednego overlayu na tamtym, cienkim zbiorze danych — nie odrzucenie kategorii „graf w
UI" jako takiej. Moduledoc `mix pns.graph` (`packages/pns_core/lib/mix/tasks/pns.graph.ex`) mówi to
wprost od początku: „`--mermaid` prints a diagram. This is the seed of the dashboard — data without
a screen, deliberately in that order: first check whether the difference is signal, then draw it." Krok
1 (CLI + mermaid, tani sposób sprawdzenia sygnału) był zawsze zapowiedzią kroku 2 (dashboard), nie
alternatywą dla niego. README, przepisując to na non-goal przy wydaniu open source (`9bdc44b`), poszedł
dalej niż to, co faktycznie sprawdzono.

**Decyzja: krok 2 się dzieje.** Wszystko, co dziś jest tylko w `mix pns.graph`/`mix pns.report`
(statyczny graf, nakładka declared/observed, kształt zadeklarowany per proces, raport zgodności) ma
ostatecznie trafić do dashboardu, nie zostać na zawsze dev-only CLI-em. README-owy wiersz non-goali
zostaje bez zmian do chwili, aż faktycznie coś z tego wyląduje w dashboardzie — ten sam zwyczaj co
dopisek (9): README dogania stan faktyczny, nie plany. Zakres pierwszego kroku implementacji (który z
trzech rodzajów grafu, na którym ekranie, jak renderować mermaid w LiveView) do rozstrzygnięcia przed
pisaniem kodu, nie w trakcie.

## Dopisek 23 sierpnia (9) — `README.md` dogonił stan faktyczny

Wiersz "A dashboard, a screen" w tabeli Non-goals obrósł trzema kolejnymi dopiskami "23 August: ..."
w jednej komórce — czytelne dla nikogo poza autorem. Skoro dashboard od dopisku (8) realnie działa na
prawdziwym hoście, przestał być non-goalem: usunięty z tabeli, nie dogrzebany czwartym dopiskiem.
Historia zostaje w `PLAN.md`/`git log`, nie w README — README od 21 sierpnia jest dla czytelnika
spoza zespołu, nie archiwum decyzji.

W zamian: nowa sekcja "Seeing the dashboard" (naturalne rozwinięcie "The four questions" — ten sam
segue, którego już tam brakowało), krótka wzmianka o `packages/pns_web` w "The package" (analogicznie
do `oban`/`oban_web`), i scalenie z już istniejącym wierszem non-goals o "Real registries, real mail,
a real OIDC provider" — dodanie "a real login screen" tam, nie osobny, dublujący wiersz.

Zweryfikowane, nie zgadywane: `mix phx.server` (polecenie w nowej sekcji) faktycznie działa i
faktycznie odpowiada pod `/dashboard` — sprawdzone ręcznie przed wpisaniem do README, nie założone
dlatego, że `:phoenix` jest teraz zależnością.

## Dopisek 23 sierpnia (8) — `pns_prototype` dostaje prawdziwego hosta Phoenixa

Domyka wątek otwarty od ekstrakcji `packages/pns_web`: dashboard żył dotąd wyłącznie w samodzielnym
hoście testowym pakietu. `PnsPrototypeWeb` (`lib/pns_prototype_web/`) to pierwszy prawdziwy host —
`Endpoint` + `Router` w drzewie nadzoru `PnsPrototype.Application`, montujące
`PNS.Web.Router.pns_dashboard/2` pod `/dashboard`, na realnym `Taxvision.Repo` i realnych kontraktach
(`Taxvision.Contracts.*`, `Rehmed.Contracts.*`) — nie na wymyślonej fikstury `CaseHandling`.

**Jedno realne znalezisko, które mógł ujawnić tylko prawdziwy, ściśle egzekwowany top-level boundary.**
`pns_dashboard/2` rozwija się inline w miejscu wywołania — makra routera Phoenixa muszą wstawić
literalny atom modułu (`live "/contract", PNS.Web.Live.ContractStatus, ...`) wprost do
skompilowanego kodu WOŁAJĄCEGO, nie `PNS.Web`. Własny test host pakietu nigdy tego nie złapał (nie ma
`top_level?: true`), ale `PnsPrototype.Application` je ma — i `boundary` słusznie odmówił kompilacji:
`PNS.Web.Live.ContractStatus`, `Live.Accounts`, `Authentication`, `Router.RedirectToContract`,
`Router.Logout`, `LocalLogin` nie były w `exports:`. To nie błąd projektowy makra — to nieunikniona
konsekwencja tego, jak działa routing Phoenixa — więc poprawka jest w `PNS.Web`'s `exports:`, poszerzona
o dokładnie te moduły, z wyjaśnieniem wprost w moduledoc, żeby nikt nie próbował tego "naprawić" inaczej
następnym razem.

**Jawne zależności zamiast tranzytywnych** — `phoenix`/`phoenix_live_view`/`phoenix_html`/
`phoenix_pubsub`/`bandit`/`lazy_html` doszły do `deps()` roota wprost, tym samym rozumowaniem co
`:telemetry` już tam ma: `PnsPrototypeWeb` woła je z nazwy, więc nie mogą być obecne tylko dlatego, że
`:pns_web` akurat ich potrzebuje.

**`PNS.Auth.LocalIdentityAdmin` musiał w końcu naprawdę wystartować.** Wcześniejszy dopisek (23
sierpnia (3)) zostawił w rootowym configu tylko klucz konfiguracyjny, bo nic nie montowało panelu kont
naprawdę — teraz coś montuje, więc `PnsPrototype.Application`'s lista dzieci dostała ten `Agent`.
Znalezione przez faktyczne uruchomienie testu, nie przez czytanie kodu.

**`.formatter.exs` (roota i `pns_web`) dostał `import_deps`/`export`, żeby `pns_dashboard/2` czytał się
jak `plug`/`live`/`scope`, nie jak zwykłe wywołanie funkcji** — `packages/pns_web/.formatter.exs`
eksportuje teraz `locals_without_parens: [pns_dashboard: 1, pns_dashboard: 2]` pod kluczem `export:`,
żeby konsument mógł to podnieść przez `import_deps: [:pns_web]`. Efekt uboczny złapany i cofnięty
przed commitem: gołe `mix format` (nie `--check-formatted`) przy okazji przeformatowało kilkanaście
plików `lib/taxvision/`/`lib/rehmed/`/`test/`, które nigdy nie były częścią bramy (`mix check` nie
uruchamia `format --check-formatted`, ustalone wcześniej w tej sesji) — cofnięte `git checkout` przed
commitem, bo to nie był zakres tego zadania.

Testy: `test/pns_prototype_web_test.exs` (6 — redirect z gołego mountu, login→dashboard z realnymi
kontraktami, read-only bez formularza grant, upgrade do live socketu, logout). 50 testów w
`pns_prototype`, było 44.

Zweryfikowane ręcznie na prawdziwym `mix run` w `MIX_ENV=dev`, bez żadnego skryptu demo: login →
dashboard z prawdziwymi, polskimi etykietami Rehmed/Taxvision → panel kont → logout, w przeglądarce, na
porcie 4000.

`mix check` zielony wszędzie: 50 + 311 + 29 = 390.

## Dopisek 23 sierpnia (7) — prowizoryczny login, `PNS.Web.LocalLogin`

Decyzja użytkownika: zanim `pns_prototype` dostanie prawdziwy host Phoenixa, warto mieć sposób, żeby
w ogóle wejść na dashboard w przeglądarce bez `?as=` (świadomie niecommitowanego hacka demo) i bez
ręcznego curl-a z nagłówkiem. `docs/adr/identity-seam.md`'s "Not decided" wymieniał "login screen
route" jako otwarte — to jest odpowiedź prowizoryczna, nie ostateczna, tego samego rodzaju co
`LocalToken` samo w sobie ("pierwsza rzecz, która znika przy podmianie").

**Zwykły formularz HTTP, nie LiveView.** Ustawienie sesji wymaga `conn`, a LiveView ma go tylko w
chwili pierwszego mountu, potem jest odcięty od każdego kolejnego requesta. `PNS.Web.LocalLogin` to
jeden `Plug`, sam decyduje GET/POST — GET renderuje formularz (kogo udajesz + rola), POST mintuje token
przez `PNS.Auth.LocalToken.sign/1` i zapisuje go w sesji pod `:pns_local_token`.

**`PNS.Web.Plug.Authenticate` nauczył się czytać token z dwóch miejsc**, nie tylko z nagłówka — nagłówek
ma pierwszeństwo (klienci API nadal działają jak wcześniej), sesja jest fallbackiem dla przeglądarki,
która nie ma jak wysyłać nagłówków samodzielnie.

**`resolve_access/1` → `resolve_access/2`, bo `{:forbidden, "/"}` przestało mieć sens.** Skoro istnieje
realny ekran logowania, przekierowanie kogoś bez dostępu na goły `"/"` (korzeń całego Endpointu, nie
mountu) było już wcześniej złym zgadywaniem — teraz `PNS.Web.Resolvers.Default` przekierowuje na
`#{base_path}/login`, co wymagało dodania `base_path` jako drugiego argumentu w całym behaviour
`PNS.Web.Resolver`. Zmiana sygnatury publicznego callbacku, nie kosmetyka — złamałaby każdy
niestandardowy resolver hosta, więc jest tu zapisana wprost, nie cicho.

**Jeden realny błąd znaleziony przez maskujący error view, drugi raz.** Test host nie miał
skonfigurowanego `render_errors`, więc prawdziwy wyjątek (tym razem zwykły
`DBConnection.OwnershipError` z pomyłki w moim własnym teście — testy logowania trafiały w
`/pns/contract`, który potrzebuje bazy, a `local_login_test.exs` nie ma `DataCase`) chował się za
`ArgumentError: no "500" html template defined`. Naprawione trwale tym razem —
`PNS.Web.TestHost.ErrorHTML` + `render_errors:` w configu test hosta — nie tylko w jednorazowym skrypcie
demo, bo to już drugi raz, kiedy ten sam brak kosztował czas na debugowanie niewłaściwego objawu.

Testy: `packages/pns_web/test/local_login_test.exs` (5 — formularz, pusty subject odrzucony, sesja
niesie aktora dalej, rola read-only też, logout czyści sesję) + zaktualizowane `resolver_test.exs`/
`router_test.exs` pod nową arność i nowe cele przekierowań. 29 testów w `packages/pns_web`, było 24.

Zweryfikowane ręcznie, całą pętlą, w prawdziwej przeglądarce: login (rola admin) → dashboard z realnymi
danymi z Postgresa → "Log out" w nawigacji → powrót na ekran logowania. Zero `?as=`, zero curl-a z
tokenem.

`mix check` zielony wszędzie: 44 + 311 + 29 = 384.

## Dopisek 23 sierpnia (6) — trasy ekranów zsymetryzowane, dwa błędy znalezione przy ręcznym klikaniu

Znalezisko z rozmowy o UX, nie z suity: `/pns` (status kontraktu) i `/pns/accounts` (konta) nie były
sobie równe — jeden ekran dostał "goły" mount path, drugi nazwaną podścieżkę. Decyzja użytkownika:
zsymetryzować. `PNS.Web.Live.ContractStatus` przeniósł się na `/contract`; goły `path` teraz
przekierowuje na `path <> "/contract"`, zanim `on_mount` w ogóle zdąży sprawdzić dostęp — bookmark do
korzenia mountu nie powinien być decyzją, tylko wskazaniem, który ekran jest "pierwszy wśród równych".

**Dwa prawdziwe błędy złapane wyłącznie ręcznym klikaniem, żaden przez `mix check`:**

1. **Nawigacja "nie działała" po poprzednim demo-buggu** — `Ecto.Adapters.SQL.Sandbox` ma domyślny
   `:ownership_timeout` 120s (żeby łapać zawieszone testy), a sesja ręcznego demo stała dłużej.
   Wygasła własność połączenia → 500 na każdym query → socket LiveView w kliencie prawdopodobnie
   utknął w stanie, w którym `<.link navigate>` nic nie robi (próba wysłania przez martwy kanał
   zamiast spaść na zwykłą nawigację). Poprawka jest w `tmp_manual_demo.exs` (niecommitowany), nie w
   pakiecie: `ownership_timeout: :infinity` dla ręcznej sesji. Nie wpływa na produkcyjny kod — to
   właściwość testowego sandboxa, nie czegoś, co `pns_web` samo w sobie robi.
2. **Redirect gubił query string.** Pierwsza wersja `RedirectToContract` robiła
   `redirect(to: path <> "/contract")` — literalnie, bez `conn.query_string`. Dla realnego hosta to
   nieszkodliwe (autoryzacja idzie nagłówkiem/cookie, nie parametrem), ale dla każdego przyszłego
   przypadku, gdzie ktoś doklei coś do URL-a mountu (`?since=`/`?until=` z okresu raportu, o którym
   już rozmawialiśmy przy ekranie 1, albo cokolwiek innego) — cichy redirect obcinający query string
   byłby bugiem czekającym na odkrycie. Poprawione ogólnie, nie tylko dla `?as=`, i przypięte testem
   (`the redirect carries the query string, not just the path`).

`PNS.Web.Layouts.nav/1` zaktualizowany na `#{base_path}/contract`. Testy: `router_test.exs` przeszedł
z `/pns` na `/pns/contract` we wszystkich asercjach treści, plus dwa nowe testy (redirect na `/contract`,
redirect z zachowanym query string) — 24 testy w `packages/pns_web`, było 22.

`mix check` zielony: 44 + 311 + 24 = 379. Zweryfikowane też ręcznie: nawigacja w obie strony, w tej
samej przeglądarce, po odświeżeniu.

## Dopisek 23 sierpnia (5) — domyślny arkusz CSS, na tym samym esbuildzie

Po pipeline JS (dopisek niżej) — mały, domyślny wygląd, żeby host montujący `pns_dashboard/2` nie
dostawał gołego HTML-a. Zakres świadomie wąski: `assets/css/app.css`, zwykłe selektory znacznikowe
(`nav`, `table`, `form`, `button`), zero frameworku — bezpieczne, bo `root_layout` zastępuje całą
stronę hosta dla tych tras, więc selektory znacznikowe nigdzie nie wyciekają.

**Jeden dodatkowy profil esbuild, nie jeden multi-entry.** Pierwsza wersja budowała `js/app.js` i
`css/app.css` jednym wywołaniem — esbuild przy wielu wejściach nazywa wyjście ścieżką względem
najbliższego wspólnego przodka, więc wyszło `assets/js/app.js`/`assets/css/app.css`, nie płaskie
`assets/app.js`/`assets/app.css`, których oczekiwał layout. Poprawka: dwa profile
(`pns_web`/`pns_web_css`), `mix assets.build` woła oba.

**Dwa miejsca, gdzie kolor niesie odpowiedź, nie tylko dekoruje** — cytat z README: „`BREACHED in 1 of
40 runs` is the whole product on one line." `outcome_class/1` w `PNS.Web.Live.ContractStatus` koloruje
dokładnie to zdanie (czerwony/pomarańczowy/zielony dla breached/pending/satisfied); `.access-badge`
robi to samo dla poziomu dostępu na obu ekranach. Jedyne dwa hooki klas dopisane do szablonów — reszta
stylu to same selektory znacznikowe, zero innych zmian w LiveView.

**Jeden realny błąd znaleziony wizualnie, nie przez `mix check`**: `<h3>Invite someone</h3>` siedział
**wewnątrz** `<form phx-submit="invite">`, a `form { display: flex }` zrobiło z nagłówka wąski flex-item
łamiący się na dwie linijki. Poprawka: nagłówek przeniesiony przed `<form>`, nie do niego — dokładnie
ten rodzaj usterki, którego żaden test HTML-owy (asercja na tekst) nie łapie, bo tekst się zgadzał,
tylko układ nie.

`mix check` zielony bez zmian: 44 + 311 + 22 = 377. Zweryfikowane też wizualnie, w tej samej ręcznie
odpalonej przeglądarce co pipeline JS.

## Dopisek 23 sierpnia (4) — pipeline JS, bo ręczne uruchomienie znalazło martwe przyciski

Znalezisko z ręcznego testu w przeglądarce (nie z suity — `Phoenix.LiveViewTest` symuluje socket w
procesie i nigdy nie dotyka prawdziwego JS): oba ekrany renderowały się poprawnie, ale `phx-click`/
`phx-submit` nic nie robiły — root layout nie ładował klienta LiveView, więc przeglądarka traktowała
formularze jak zwykłe, natywne submity. 22 zielone testy nic o tym nie mówiły, bo nie miały jak.

**`mix esbuild` (binarka, nie Node/npm)** — `assets/js/app.js` importuje `phoenix`/`phoenix_live_view`/
`phoenix_html` z `deps/` przez `NODE_PATH`, dokładnie ten trik, którego używa `mix phx.new`. Zbudowany
bundle (`priv/static/assets/app.js`, zminifikowany, 144KB) jest commitowany, nie budowany przy
`mix compile` konsumenta — pakiet ścieżkowy nie ma jak uruchomić kroku budowania za kogoś, więc
`esbuild` jest `runtime: false` i potrzebny tylko temu, kto edytuje JS (`mix assets.build`).

**Ślepy zaułek, zanim wyszło na jaw dlaczego**: pierwsza wersja serwowała bundle przez
`forward "/assets", Plug.Static, ...` zagnieżdżone w tym samym `scope` co ekrany — więc dziedziczyło
`pipe_through :browser` hosta, `protect_from_forgery` włącznie. `Plug.CSRFProtection` ma wbudowaną
ochronę przed cross-origin `<script>` i odmawia serwowania JavaScriptu przez trasę objętą CSRF,
z zasady, niezależnie od tego, czy request faktycznie jest złośliwy
(`Plug.CSRFProtection.InvalidCrossOriginRequestError`). Objawiało się jako 403, zamaskowane w dodatku
przez brak skonfigurowanego `render_errors` w hoście demo — dopiero jawny error view ujawnił prawdziwy
wyjątek. Poprawka zgodna z tym, jak robi to każda wygenerowana aplikacja Phoenix: statyczne assety
serwuje się na poziomie Endpointu, przed routerem, nie przez trasę. `pns_dashboard/2` już tego nie robi
— zamiast tego jego moduledoc wymaga jednej linijki w Endpointzie hosta (`plug Plug.Static, at:
"/pns_web/assets", from: {:pns_web, "priv/static/assets"}, gzip: false`), tej samej rangi co
`PNS.Web.Plug.Authenticate` w pipeline routera — i `test/support/test_host/endpoint.ex` niesie dokładnie
tę linijkę, więc własna suita dowodzi instrukcji, nie tylko ją zakłada.

**Zweryfikowane ręcznie, nie tylko przez `mix check`**: pełna pętla invite → grant → revoke w prawdziwej
przeglądarce, na żywo, bez przeładowania strony — dokładnie to, czego `Phoenix.LiveViewTest` nie mogło
udowodnić. `mix check` zielony bez zmian: 44 + 311 + 22 = 377.

## Dopisek 23 sierpnia (3) — drugi ekran: panel kont

Domyka dwuekranowy plan. `PNS.Web.Live.Accounts`, pod `/accounts` w tym samym `live_session` co ekran
1 — ta sama decyzja dostępu, ten sam `on_mount`, więc oba ekrany dzielą mechanizm z fundamentu bez
żadnej nowej logiki auth.

**Domyka też coś, co `docs/adr/identity-seam.md` zostawił jako "Not yet built" 9 sierpnia**: "ten ekran
woła nasze API, nigdy sidecara, nawet gdy Management API sidecara już robi wszystko, co ekran
potrzebuje. Cienki proxy w wrapperze kosztuje realny kod, którego bezpośrednia ścieżka by nie
kosztowała — ale bezpośrednia ścieżka oznacza, że frontend zna kształty żądań Zitadela, a podmiana
providera staje się przepisaniem frontendu zamiast jednej linijki konfiguracji." Ten proxy teraz
istnieje — jako zaślepka, nie jako klient Zitadela.

**Wzorzec `Verifier`/`LocalToken`/`OidcVerifier` w `lib/pns/auth.ex` powtórzony jeden do jednego**, bo to
dokładnie ta sama architektura z tego samego pliku:
- `PNS.Auth.IdentityAdmin` — behaviour, cztery callbacki (`list_users/0`, `grant_role/2`,
  `revoke_role/2`, `invite_user/2`) — "garść wywołań zarządzania użytkownikami, których potrzebuje ekran
  admina", cytat z ADR.
- `PNS.Auth.LocalIdentityAdmin` — zaślepka, jeden `Agent`, zero trwałości, startowana pusta. Jedyny
  odpowiednik `LocalToken` po stronie zarządzania, nie po stronie uwierzytelniania.
- **Świadomie brak trzeciego modułu** (`PNS.Auth.ZitadelIdentityAdmin` czy podobnego). PoC z 9-11
  sierpnia (`docs/adr/identity-seam.md`, `docs/identity-admin-guide.md`) już dowiódł, że wywołania
  Management API Zitadela działają — budowanie ich tutaj jako kodu produkcyjnego byłoby dokładnie tym,
  czego `CLAUDE.md` zabrania: "Real registries, real mail, a real OIDC provider — A behaviour plus a
  fake." Zaślepka wystarcza, żeby udowodnić mechanizm; prawdziwy klient jest realną integracją
  domenową klienta, zero sygnału dla biblioteki.
- Dispatcher w `PNS.Auth` sam: `@identity_admin = Application.compile_env!(:pns, :identity_admin)`,
  wołany przez prywatną funkcję `identity_admin/0`, dokładnie ten sam kształt co `@verifier`/`verifier/0`
  — nie atrybut w pozycji wywołania (to byłby literał modułu, którego `boundary`/kompilator by nie
  znały dla modułu hosta), tylko przez zmienną zwracaną z funkcji.

**Trzecia pułapka konfiguracyjna z ekstrakcji odezwała się tu ponownie, tym razem świadomie.**
`compile_env!` jest wymagający: skoro `PNS.Auth` teraz deklaruje `@identity_admin` obok `@verifier`,
**każdy** top-level projekt kompilujący `:pns` musi ustawić `config :pns, identity_admin: ...`, inaczej
kompilacja pada. Dodane w trzech miejscach na raz, żeby żadna z trzech zielonych bram nie zgasła:
`packages/pns_core/config/config.exs`, `packages/pns_web/config/config.exs`, i root `config/config.exs`
— w tym ostatnim tylko klucz konfiguracyjny, bez startowania procesu `Agent`, bo `pns_prototype` nie
montuje jeszcze żadnej trasy `pns_web` (`runtime: false`, zero drzewa nadzoru Phoenixa) i uruchomienie
procesu, którego nikt nie woła, byłoby zgadywaniem topologii, nie fundamentem.

**`:read_only` przestał być martwym rozróżnieniem.** Od fundamentu istniały dwa poziomy dostępu, ale
ekran 1 renderuje to samo dla obu. Ekran 2 jest pierwszym miejscem, gdzie różnica robi coś: `:all` widzi
formularze grant/revoke/invite, `:read_only` widzi tylko listę. Sprawdzane dwa razy, nie raz — ukryte
w znaczniku (`:if={@pns_web_access == :all}`) i osobno w każdym `handle_event/3`
(`with_write_access/2`), bo zdarzenie LiveView to wiadomość, którą klient może wysłać niezależnie od
tego, co faktycznie wyrenderowano — test `router_test.exs`-owym zwyczajem dowodzi obu warstw osobno,
nie tylko ukrycia przycisku.

**Nawigacja między ekranami wymagała przepchnięcia `base_path` przez sesję**, bo montowalny router nie
może zakładać, gdzie host go zamontował — ten sam powód, dla którego `pns_dashboard/2` w ogóle nie
sięga po `~p`. `PNS.Web.Router.__session__/3` (było `/2`) dokłada `"base_path" => path` do mapy sesji,
`PNS.Web.Authentication` przypisuje ją jako `@pns_web_base_path`, a `PNS.Web.Layouts.nav/1` (nowy,
współdzielony function component) buduje z niej oba linki.

Testy: `packages/pns_core/test/auth_test.exs` (5, `LocalIdentityAdmin` wprost — invite/grant/revoke/
not_found/sortowanie) i `packages/pns_web/test/accounts_live_test.exs` (4, przez prawdziwy router:
invite, grant+revoke, grant dla nieistniejącego usera, i podwójna blokada dla `:read_only`). Zero
Postgresa w drugim pliku — `LocalIdentityAdmin` to goły `Agent`, więc ten ekran jest tańszy do
przetestowania niż ekran 1.

`mix check` zielony wszędzie: `packages/pns_core` osobno (311, było 306), `packages/pns_web` osobno
(22, było 18), i z korzenia repo — 44 + 311 + 22 = 377, 0 błędów.

## Dopisek 23 sierpnia (2) — pierwszy ekran: status zgodności kontraktu

Po fundamencie (dopisek niżej) — pierwszy z dwóch ekranów, osobno od drugiego (panel kont), zgodnie z
decyzją użytkownika. `PNS.Web.Live.ContractStatus` zastępuje placeholder `Home` pod `/` w
`pns_dashboard/2`.

**Zero nowej logiki domenowej — to jest formatka, nie druga opinia o tym, czym jest zgodność.**
Ekran woła dokładnie to, co już woła `mix pns.report`: `PNS.Registry.contracts()` +
`PNS.Conformance.report(contract, [])` dla każdego kontraktu, bez selektora — ten sam powód, dla
którego `mix pns.report` też nie ma selektora: które kontrakty istnieją to fakt uruchomieniowy silnika,
nie decyzja UI. Cztery pytania renderują się jako HTML zamiast tekstu `PNS.Report`, z tymi samymi
zdaniami tam, gdzie zdanie *jest* odpowiedzią (`BREACHED in N of M runs.`, `in force since DATE`) —
świadomie zduplikowanymi w dwóch miejscach (`PNS.Report` i tu), bo to kilka linijek dla dwóch różnych
mediów, nie wspólny mechanizm, który się rozjeżdża. Jedyny wyjątek: `PNS.Duration.humanize/1` — ten
akurat MUSI być jeden, bo to moduł, który już raz naprawiał dokładnie ten błąd (zła liczba mnoga
skopiowana ręcznie w dwóch miejscach) — więc `Duration` dołączony do `exports:` w `pns.ex`, żeby
`pns_web` mogło go wołać, zamiast pisać formatowanie trzeci raz.

**`packages/pns_web` przestał być pakietem bez tabel — ale tylko w teście.** Ekran czyta prawdziwe dane
przez `PNS.Conformance`, więc jego własna suita potrzebuje repo, tak jak `packages/pns_core`. Zamiast
zgadywać, zmirrorowano dokładnie ten sam przepis: `PNS.Web.TestHost.Repo`, migracja opakowująca
`PNS.Migrations.up/0` (`priv/repo/migrations/`), `PNS.Web.TestHost.DataCase` (sandbox + czyszczenie
`PNS.Deployment` napisanego poza sandboxem przy boocie), fixture kontrakt
`PNS.Web.TestHost.Fixtures.CaseHandling` (WYMYŚLONY, dwa zakończenia z jednego punktu decyzji, mniejsza
wersja `ProcessShapes.Promised`). `ecto_sql`/`postgrex`/`oban` nie doszły do `deps()` — trafiły
tranzytywnie przez `{:pns, path: "../pns_core"}`, potwierdzone przy pierwszym `mix deps.get`, więc
pakiet produkcyjnie dalej nie ma własnych tabel/joby, tylko test je potrzebuje.

**Jak sprawdzić `:violated` bez czekania godziny.** `PNS.Trace.evaluate/3` ma `now:` właśnie po to, żeby
dało się to testować bez prawdziwego czasu — ale ten seam należy do silnika, nie do ekranu: dodawanie
`now:` jako publicznego parametru LiveView byłoby prawdziwą funkcją produktową kłamiącą o czasie, nie
testowym haczykiem. Zamiast tego: jeden test integracyjny przez prawdziwy DB (jeden przebieg,
zatwierdzony od razu przez handler — `:satisfied`, plus naturalnie nieużyta ścieżka `case_rejected` →
untraversed, bez żadnej sztuczki), i osobne testy `render/1` wprost, przez
`Phoenix.LiveViewTest.render_component(&ContractStatus.render/1, assigns)` z ręcznie zbudowanymi mapami
w kształcie, jaki faktycznie zwraca `PNS.Conformance.report/2` — pokrywają `:violated`, `:pending`,
`runs: 0`, drift obecny/pusty, deployment niepotwierdzony. Deterministyczne, zero DB, zero czekania —
mechanizm już dokładnie przetestowany 306 testami silnika, tu sprawdzana jest tylko warstwa renderowania.

**`router_test.exs` przeszedł z `async: true` na `async: false`.** Konsekwencja zmiany treści pod `/`:
odkąd ekran naprawdę odpytuje bazę, testy dostępu admina uruchamiają `ContractStatus.mount/3` z osobnego
procesu LiveView, który musi pożyczyć połączenie z sandboxa tego testu — to samo, dlaczego
`PNS.ReportTest` w silniku też jest `async: false`.

`mix check` zielony samodzielnie w `packages/pns_web/` (18 testów, było 12) i z korzenia — teraz 44 +
306 + 18 = 368, 0 błędów.

## Dopisek 23 sierpnia — `packages/pns_web`, wspólny fundament dashboardu

Nowy pakiet, wyekstrahowany od pierwszego commita tym samym wzorcem co `packages/pns_core`: własny
`mix.exs`, własny `config/config.exs` czytany tylko wtedy, gdy pakiet jest top-level, własny samodzielny
host testowy (`test/support/test_host/`), który nigdy nie dotyka `pns_prototype`. Obejmuje wyłącznie
fundament — montowalny router (`PNS.Web.Router.pns_dashboard/2`) i resolver oparty o `PNS.Auth` — nie
treść żadnego z dwóch docelowych ekranów.

**`{:pns_web, path: "packages/pns_web", runtime: false}` wchodzi do `deps()` roota**, nie tylko do CI —
decyzja, bo Phoenix ma niedługo i tak trafić do `pns_prototype`. `runtime: false` bo nic tu jeszcze nie
startuje: ten host nie ma supervisora Phoenixa.

**Mechanizm zweryfikowany na prawdziwym źródle `oban_web`** (`lib/oban/web/router.ex`,
`lib/oban/web/authentication.ex`, nie tylko dokumentacja): `live_session` z
`session: {Module, :fun, args}` — Phoenix sam woła tę funkcję z prawdziwym `conn` przy każdym mount i
reconnect, więc zero osobnego Pluga do przechowywania tokenu w sesji. `on_mount`
(`PNS.Web.Authentication`) przelicza `resolve_access/1` na nowo za każdym razem, nie raz w sesji — dokładnie
jak `Oban.Web.Authentication`.

**Świadome rozszerzenie topologii „dashboard inside the engine"**
([`docs/adr/architecture.md`](docs/adr/architecture.md) §16–17, rozstrzygnięte 6 sierpnia) — tamta decyzja
dotyczyła tekstowego `PNS.Report`, nie graficznego dashboardu web. Datowany dopisek poszedł do
`architecture.md`, nie ciche przepisanie.

**Cztery rzeczy znalezione dopiero przy recenzji planu, nie przy pierwszym pisaniu kodu** — wszystkie
potwierdzone przy faktycznym budowaniu:

- `Phoenix.PubSub` nie startuje samo — pakiet-biblioteka nie ma `mod:`. Test host startuje je ręcznie w
  `test_helper.exs`; prawdziwy host będzie musiał zrobić to samo we własnym supervisorze.
- `root_layout: {PNS.Web.Layouts, :root}` w `live_session` musi być jawny, inaczej zamontowany dashboard
  renderuje się w layout hosta (jeśli ten ma jakiś) albo się wywala.
- `PNS.Web` deklaruje `use Boundary, deps: [PNS]` — bez tego pierwsze odwołanie do `PNS.Auth` pada na
  `--warnings-as-errors`.
- `def cli, do: [preferred_envs: [check: :test]]` w `packages/pns_web/mix.exs` — bez tego `mix check`
  odpala krok `test` w `dev`, nie w `test`, i pada. `packages/pns_core` ma tę samą lukę — dziś działa
  tylko dlatego, że nikt nie odpalił tam gołego `mix check` bez wcześniejszego `MIX_ENV=test`; nie
  naprawione w tym dopisku, bo to osobne zadanie, nie część tego planu.

**Dwie zależności doszły dopiero przy pisaniu testów, nieprzewidziane w planie**: `phoenix_live_view` 1.2.x
wymaga `{:lazy_html, ">= 0.1.0", only: :test}` dla `Phoenix.LiveViewTest.live/2` — nie widać tego w drzewie
zależności `phoenix_live_view`, tylko w runtime błędzie przy pierwszym uruchomieniu testu. `bandit` został,
tak jak plan przewidywał furtkę: `adapter: Bandit.PhoenixAdapter` jest konieczny (Phoenix 1.7+ nie zgaduje
adaptera).

**Wpięcie w hosta**: `package_test_web/1` w root `mix.exs`, mirror `package_test/1` — zależność ścieżkowa
nie uruchamia testów zależności automatycznie. Trzeci blok cache + `mix deps.get` w
`.github/workflows/ci.yml`, obok istniejącego dla `packages/pns_core`.

**Zweryfikowane budowaniem, nie tylko planowaniem:** `mix check` zielony samodzielnie w
`packages/pns_web/` (12 testów) i z korzenia repo, teraz trzy suity: 44 (`pns_prototype`) + 306
(`packages/pns_core`) + 12 (`packages/pns_web`), 0 błędów, `boundary` bez naruszeń mimo nowej ścieżkowej
zależności w `deps()` roota.

## Dopisek 21 sierpnia (8) — `unverified` sięga teraz po `trace`, nie tylko po `cadence`/`deadline`

Z dystylacji Rehmed (18 sierpnia, luka 4 rozliczenia płatnika): najostrzejsza assercja w całym
zleceniu — `H38`, przyjęcie płatnika w 7 dni przy kolejce dwóch miesięcy — nie miała jak trafić do
kontraktu bez wchodzenia do raportu dowodowego jako pewnik, którego nikt nie potwierdził. Do dziś
`PNS.Conformance.verified_declarations/1` czytało `process.unverified` wyłącznie przeciw `:cadence`
i `:deadline` — nazwa assercji `trace` nigdy nie była z nią zestawiana.

**Poprawka jest jednolinijkowym filtrem w `PNS.Conformance.assertions/4`**
(`packages/pns_core/lib/pns/conformance.ex`): `trace.name not in process.unverified`, ten sam wzorzec
co już istniał dla pól procesu. `PNS.Trace.evaluate/3` nadal liczy werdykt normalnie — `unverified`
nie wyłącza mechanizmu, wyłącza tylko wejście do agregatu, który czyta klient. Zero zmian w DSL:
`unverified` już przyjmował listę atomów, `trace` już miał nazwę.

**Jedna rzecz po drodze, którą trzeba było naprawić, nie tylko dopisać.** Ostrzeżenie `mix pns.check`
o niepotwierdzonej deklaracji (`check_unverified_declarations/1`) budowało zawsze zdanie w kształcie
„`pole` = wartość nie jest potwierdzone" przez `Map.get(process, field)` — poprawne dla `:cadence`/
`:deadline`, ale dla nazwy assercji `Map.get` cicho zwróciłby `nil`, bo `trace` nie jest polem procesu.
Rozdzielone na dwa zdania: jedno dla pola procesu (bez zmian), jedno dla assercji (mówi, że werdykt
wciąż się liczy, tylko nie wchodzi do agregatu).

**Nie zamyka `H38`.** Rozliczenie płatnika ma osobną, wcześniejszą blokadę (luka 2: kotwica
`visit_delivered` należy do innego procesu, a `trace` nie przekracza granicy procesu) — mechanizm
teraz istnieje, ale ta konkretna assercja w `payer_settlement.ex` wciąż się nie da napisać.

**Zweryfikowane mutacyjnie:** usunięcie filtra z `assertions/4` wywaliło dokładnie test zbudowany, żeby
to złapać (`test/report_test.exs`, nowa fikstura `UnverifiedTraceFixture` z dwiema assercjami na
jednym procesie — jedną potwierdzoną, jedną nie, żeby kontrola nie przechodziła przez przypadek
filtra usuwającego wszystko). `mix check` zielony: 44 + 306 testów, 0 błędów.

## Dopisek 21 sierpnia (7) — cztery drobiazgi z listy „przy etapie 3", jeden z nich okazał się już zrobiony

**Zanim je robić, sprawdziłem, czy któryś już istnieje** — dobra decyzja: `info` dla assercji `trace`
bez `within` już był w `pns.check.ex` (`check_unfalsifiable_assertions/1`) z kontrolnym testem w
`test/check_ambiguity_test.exs`, sprzed tej sesji. Lista przy etapie 3 była nieaktualna. Zdjęte z
listy bez implementowania drugi raz.

**Aktor systemowy zamiast `nil`.** `PNS.Auth.system_actor/0` (`"system"`), domyślane w
`PNS.Emitter.default_ctx/1` dla obu punktów wejścia (`emit/4`, `emit_all/3`) — jeden ctx nigdy nie ma
`actor: nil` od chwili, gdy trafia do `do_emit/5`. Zdjęte: `ctx[:actor] && to_string(ctx[:actor])` w
trzech miejscach, bo warunek stał się zawsze prawdziwy. Test `process_shapes_test.exs` pinujący
`nil` jako „nierozstrzygnięte, patrz PLAN.md" zmienił się w test pinujący `"system"` jako
rozstrzygnięcie. Sprawdzone bazą: zero wierszy z `actor is null` w żadnej z trzech baz przed zmianą —
nie że to miało znaczenie, silnik i tak nigdy nie migruje starych wierszy, tylko domyśla nowe.

**Wykluczenie przestrzeni nazw z raportu, z konfiguracji silnika.** `config :pns, exclude: [...]` —
lista prefiksów namespace'ów porównywanych z `inspect/1`, odrzucanych w `PNS.Registry.load!/1` zanim
cokolwiek poniżej (check, report, graph, trace) zobaczy skanowaną binarkę. Nie z DSL — jak
zastrzeżono w oryginalnej notatce. Domyślnie puste, więc „graf pochodzi z binarki, która działa"
zostaje niezmienione, dopóki ktoś świadomie nie zawęzi.

**Zbiór wartości `:enum` — deklarowalny, opt-in.** `payload: %{status: {:enum, [:open, :closed]}}`
obok gołego `:enum`, który zostaje bez zmian i bez wymuszonej migracji istniejących sześciu miejsc w
repo (TaxVision, Rehmed, fikstury) — wymyślanie prawdziwych wartości dla `format: :enum` w
`accounting_month.ex` albo `method: :enum` w `visit_settlement.ex` byłoby dokładnie tą zmyśloną
wiedzą domenową, którą to repozytorium ma wykrywać u innych, nie produkować. Zbiór porównywany jako
stringi, nie jako termy — `[:open, "open"]` jest tą samą pomyłką co `[:open, :open]`, tylko w dwóch
reprezentacjach Elixira, i brama łapie obie tym samym mechanizmem.

**Jedna prawdziwa pułapka projektowa, znaleziona i naprawiona przed testami, nie po.** Pierwsza wersja
bramy kompilacyjnej sprawdzała legalność zbioru enum w tej samej funkcji, która sprawdza „czy to
w ogóle jest typ payloadu" — więc każdy nielegalny zbiór (pusty, z duplikatem, ze złym typem elementu)
wywalał się z ogólnym komunikatem „nie jest typem payloadu", zanim druga, bardziej szczegółowa pętla
w ogóle dostała szansę się odezwać. Druga pętla była martwym kodem od pierwszego commita. Naprawione
rozdzieleniem: pierwsza sprawdza wyłącznie kształt (`{:enum, lista}`), druga legalność
zawartości tej listy — złapane mutacyjnie, nie przeglądem: cofnięcie rozdzielenia wywaliło dokładnie
te trzy testy, które sprawdzają precyzyjny komunikat błędu.

**Zweryfikowane mutacyjnie, wszystkie cztery.** Wyłączenie domyślnego aktora, wyłączenie filtra
namespace'u, cofnięcie rozdziału kształt/legalność dla enum, wyłączenie porównania zbioru enum przy
walidacji payloadu — każde osobno wywaliło dokładnie testy zbudowane, żeby to złapać. `mix check`
zielony: 44 + 304 testy, 0 błędów, ten sam jeden warning co przed tym dopiskiem (niepotwierdzony
`deadline` TaxVision — niezwiązany).

`docs/contract.md` zaktualizowany w dwóch miejscach: tabela typów payloadu (`:enum`) i tabela
„Known decoration" (wiersz o zbiorze `:enum` usunięty, z notatką dlaczego).

## Dopisek 21 sierpnia (6) — ostatni `known_defect` rozstrzygnięty bez zmiany kodu: zawieszenie przez `or_else` zostaje

Ostatni z czterech. Inny od poprzednich trzech, bo PLAN.md od początku mówił, że to nie jest arytmetyka
do naprawienia, tylko osąd o tym, co obiecuje `trace` z `or_else` — i osąd ten należy do process ownera,
którego dla tej fikstury nie ma (`test/trace_edges_test.exs`: „INVENTED. NOT A DOMAIN.").

Scenariusz: `trace: from :opened; eventually :closed, within: {1,:day}; or_else :chased`. `:closed`
(trasa chciana) nie ma żadnej zależności — nic zewnętrznego nie mogło jej zablokować. `:chased`
(fallback) zależy od `:chaser`. Gdy `:chaser` pada i nic się nie dzieje, dzisiejszy kod zawiesza
przebieg (wyklucza naruszenie), bo którakolwiek awaitowana zależność padła — mimo że trasa chciana
była osiągalna przez cały czas i po prostu się nie zdarzyła.

Zapytany o rozstrzygnięcie w rozmowie, nie w kodzie: zostawić dzisiejsze zachowanie. Kontrakt mówi
„X albo Y", a Y było niemożliwe — to wystarcza jako powód wstrzymania werdyktu, nawet gdy X nie
zależało od niczego; węższe odczytanie (zawieszać tylko, gdy KAŻDA wciąż-możliwa trasa była
zablokowana) było na stole i odrzucone. `@tag :known_defect` zdjęty z testu asertującego węższe
odczytanie — usunięty, nie zostawiony czerwony na przyszłość, której teraz nikt nie planuje; test
pinujący dzisiejsze zachowanie jako potwierdzone dostał datę i uzasadnienie w komentarzu.
`awaited_outages/2` w [`trace.ex`](packages/pns_core/lib/pns/trace.ex) — zero zmian w kodzie,
tylko w moduledoku, żeby decyzja była zapisana tam, gdzie mechanizm.

**Cztery `known_defect` → zero.** `mix check` zielony: 44 + 289 testów, 0 błędów, 0 wykluczonych.

## Dopisek 21 sierpnia (5) — trzeci `known_defect` zamknięty: assercja liczy się teraz per element

Ostatni z trzech `known_defect` po dopisku (3): `trace` produkował jeden werdykt na przebieg niezależnie
od tego, ile razy zdarzyło się to, o czym assercja obiecuje. Okno otwierało się na pierwszym `from` w
przebiegu i zamykało na pierwszym trafieniu po nim — więc jedno spełnienie zaliczało cały przebieg, a
trafienie nie musiało nawet dotyczyć tego samego elementu, bo ewaluator nigdy nie porównywał payloadów.
Znalezisko z dystylacji Rehmed (rozliczenie płatnika): *każda wykonana wizyta jest w fakturze albo
wykluczona z powodem* — czterdzieści nierozliczonych wizyt za jedną rozliczoną raportowało się jako
spełnione. `PNS.Check.assertions_finer_than_their_run/1` już miał sygnał statyczny (`identity` `from`-a
ostro drobniejsze niż `instance` procesu); `test/trace_granularity_test.exs` miał czerwony test na
żądanie od 19 sierpnia.

**Mechanizm w [`trace.ex`](packages/pns_core/lib/pns/trace.ex):** gdy assercja jest kwantyfikowana
(ten sam warunek co check), `PNS.Trace.evaluate/3` liczy jeden element na wartość `identity`
zdarzenia `from` w przebiegu, każdy z własnym oknem od własnego najwcześniejszego `from`. Trafienie
`eventually`/`or_else` łączy się z elementem po tych samych wartościach pól `identity` w jego własnym
payloadzie — trafienie bez tych pól nie rozwiązuje żadnego elementu. To jest kierunek asekuracyjny:
fakt, którego nie da się odróżnić od elementu, który miał rozwiązać, nie rozwiązuje go przez
przypadek. Jeden werdykt przebiegu to teraz najgorszy z werdyktów jego elementów — `:violated`
jeśli którykolwiek element ma zamknięte puste okno, inaczej `:pending` jeśli którykolwiek wciąż otwarte,
inaczej `:suspended` jeśli którykolwiek wykluczony, inaczej `:satisfied` — kwantyfikator generalny, bo
obiecane było *każdy*, nie *któryś*. Zwykły przypadek (`identity` = `instance`) jest nietknięty: to samo
zapytanie, ta sama funkcja, ten sam koszt.

**Jedna świadoma strata informacji: `via: nil`, gdy elementy zamknęły się różnymi trasami.** Przebieg
spełniony częściowo przez `eventually`, częściowo przez `or_else` nie zgaduje, którą trasę wypisać —
to jest pytanie warsztatowe, nie inżynierskie, i moduledoc mówi to wprost.

**Nie zamyka Rehmedowego przypadku, który to znalazł.** Rozliczenie płatnika ma drugą, osobną lukę
(kotwica `visit_delivered` należy do innego procesu, a `trace` nie przekracza granicy procesu) — nawet po
tej poprawce ta assercja wciąż się nie da napisać. Dopisane w
[`payer_settlement.ex`](lib/rehmed/contracts/payer_settlement.ex): luka 1 zamknięta, luka 2 nie, i to jest
osobna rzecz.

**Zweryfikowane odwrotnie, nie tylko zielono:** wyłączenie kwantyfikacji, przestawienie priorytetu
`:violated`/`:pending` i zepsucie gałęzi „brak elementu"/„brak deadline'u" każde osobno wywaliło
dokładnie ten test, który miało wywalić — nie sąsiedni, nie żaden. Pokrycie `PNS.Trace` 98,17%; reszta
to niezmieniona gałąź obsługi nieznanej nazwy assercji, sprzed tej poprawki.

Zaktualizowane przy okazji: moduledoc `PNS.Trace`, moduledoc `PNS.Check.assertions_finer_than_their_run/1`
i komunikat ostrzeżenia w `mix pns.check` — wszystkie trzy opisywały poprzednio to jako defekt, który
milczy w stronę dobrych wieści; teraz opisują mechanizm i jego jedno realne ryzyko (trafienie bez pól
`identity` w payloadzie). `mix check` zielony: 44 + 290 testów, 0 błędów, jeden `known_defect` zostaje
(zawieszenie przez `or_else`).

## Dopisek 21 sierpnia (4) — drugi `known_defect` zamknięty, bo migracji nie było z czego robić

Eskejp separatora był tagowany, nie poprawiony: `PNS.Instance` zamienia `|` na `%7C` i zostawia `%`
w spokoju, więc wartość zawierająca dosłowny tekst `%7C` daje ten sam klucz przebiegu co wartość
zawierająca `|`. `PNS.Job` odziedziczył ten sam kształt na `:`/`%3A`. Powodem tagu, nie poprawki, była
cena migracji: poprawka zmienia format każdego `instance_id` i każdego klucza idempotencji, jaki
kiedykolwiek zapisano, a stare wiersze zostają w starym kodowaniu.

**Sprawdzone `psql` przed poprawką, nie założone: migracji nie było z czego robić.** `pns_events` i
`oban_jobs` mają `0` wierszy w `dev` i w `test`, a żadne wdrożenie poza tym repozytorium tego
obwodowania nie czyta — TaxVision i Rehmed są danymi testowymi, nie produkcją, więc „przeformatowane
klucze leżą w tabelach idempotencji klientów" było ryzykiem przyszłym, nie faktem o dzisiejszym stanie.
Cena, którą tag nazywał, wynosi dziś zero, i to jest właściwy moment na zamknięcie — każdy dzień
dłużej z prawdziwym ruchem podnosi tę cenę, nigdy jej nie zmniejsza.

Poprawka: `%` eskejpuje się jako `%25` przed eskejpowaniem separatora, w obu miejscach
(`PNS.Instance.encode/3`, `PNS.Job.escape/1`), żeby odwzorowanie było różnowartościowe. Test w
`payload_edges_test.exs` traci tag i zmienia się z „powinno się różnić, ale się nie różni" na
asercję, że się różni; `PNS.Job` dostał symetryczny test w `job_idempotency_test.exs` — miał tę samą
usterkę, ale nie miał własnego czerwonego testu, który by to pinował.

**Trzy `known_defect` → dwa.** Zostają: kwantyfikacja wewnątrz przebiegu (`trace_granularity_test.exs`)
— traktowana jako produkt, nie dług, patrz „Otwarte" niżej — i zawieszenie przez zależność wyłącznie
`or_else` (`trace_edges_test.exs`), osąd wymagający rozmowy z process ownerem, nie arytmetyka.

## Dopisek 21 sierpnia (3) — jeden `known_defect` zamknięty, jeden osąd doprecyzowany po drodze

`within: {0, :day}` się kompilowało, choć `PNS.Duration.t` było opublikowane jako `pos_integer()` —
brama sprawdzała tylko jednostkę, nigdy liczbę. Naprawa okazała się mieć w środku osąd, nie tylko
kod: `test/trace_edges_test.exs` ma cały blok `describe "a window of length zero"`, który celowo
wykorzystuje dzisiejszą tolerancję zera, żeby przypiąć zachowanie ewaluatora w chwili, gdy deadline
pokrywa się z otwarciem okna — a sam moduledoc pliku mówi wprost „read every test below as a
description of what happens, never as an argument that it should".

Rozstrzygnięcie: zero zostaje legalne, ujemna liczba nie. Zero ma sensowne odczytanie — „musi się
zdarzyć w tej samej chwili" — i ten odczyt jest już przetestowany i udokumentowany. Ujemna nie ma
żadnego: termin ląduje przed otwarciem okna, więc każdy przebieg jest naruszony w chwili startu.
`PNS.Duration.t` zmienione na `non_neg_integer()`, żeby typ zgadzał się z decyzją. Brama w
`PNS.Contract` odrzuca teraz `within` z liczbą ujemną lub nie-całkowitą; test `known_defect` o zerze
zamienił się w test o liczbie ujemnej i przechodzi bez tagu.

**Cztery `known_defect` → trzy.** Pozostałe trzy — kolizja `%7C`/`\|` w `instance_id`
(`payload_edges_test.exs`), kwantyfikacja wewnątrz przebiegu (`trace_granularity_test.exs`), zawieszenie
przez zależność wyłącznie `or_else` (`trace_edges_test.exs`) — czekają z innych powodów: migracja danych
klienta, kształt DSL jeszcze nienaciągnięty przez drugi realny kontrakt, i osąd wymagający rozmowy z
właścicielem procesu. `mix check` zielony, `mix test --include known_defect` w pakiecie: 3 czerwone,
zgodnie z oczekiwaniem.

## Dopisek 21 sierpnia (2) — silnik wozi własne tabele i własną suitę

Dwie ostatnie rzeczy, które trzymały pakiet przy gospodarzu, i obie zostały zapłacone. `mix check`
uruchamia teraz dwie suity: 44 testy tutaj i 285 w `packages/pns_core`.

### `PNS.Migrations` — i znacznik wersji powstał, zanim był potrzebny

Pięć tabel silnika leżało w `priv/repo/migrations/` gospodarza, wymieszanych z migracjami TaxVision,
a Oban stał jedną linijkę wyżej w tym samym katalogu i robił dokładnie odwrotnie. Schematy i
wszystkie zapytania są w pakiecie, więc aplikacja utrzymywała kopię kształtu, którego nie posiada.

Wersjonowanie w kształcie Obana, z wersją zapisaną w komentarzu na `pns_events`. Na wersji 1 nie ma
z czego migrować i właśnie dlatego mechanizm wchodzi teraz: pierwsza zmiana schematu jest momentem,
w którym jest już za późno, bo wtedy każdy konsument siedzi na nieoznaczonym `create` i nie ma stanu,
od którego można by ruszyć.

`V01` tworzy kształt docelowy, nie historię. `process` i `instance_id` są kolumnami `pns_events` od
pierwszego `create`; to, że doszły dzień później, jest faktem o tym repozytorium, nie o czyjejś bazie.

**Sprawdzone `pg_dump` przed i po, w `dev` i w `test`, oraz przeciwko bazie pakietu:** pięć tabel, ich
kolumny, kolejność kolumn, wartości domyślne, ograniczenia i trzynaście indeksów są identyczne co do
bajtu. Jedyna różnica to `COMMENT ON TABLE public.pns_events IS '1'` — czyli sam mechanizm.

Tabele Obana zostają Obana. `up/1` nie opakowuje `Oban.Migration.up/1`: opakowanie związałoby naszą
wersję z jego, ukryłoby aktualizację, o której konsument musi zdecydować sam, i pękłoby u konsumenta,
który już używa Obana do własnej roboty.

### Suita silnika stoi bez klienta — i to jest 87% suity

Nie wiedzieliśmy dotąd, ile z testów bada silnik, a ile TaxVision. Teraz wiadomo, bo szew jest
fizyczny: 289 testów w pakiecie, 44 tutaj (z tego 4 `:known_defect`, wszystkie w pakiecie i wszystkie
nadal czerwone). Sześć plików zostaje przy kliencie i każdy z powodu, który da się nazwać:

| Plik | Dlaczego zostaje |
| --- | --- |
| `periods_test.exs` | okresy to domena TaxVision, nie mechanizm |
| `identity_seam_test.exs` | trzy poziomy IAM na krawędzi żądania klienta; skanuje też moduły `:pns_prototype` i konfigurację gospodarza |
| `contract_examples_test.exs`, `rehmed_contract_examples_test.exs` | przykłady z kontraktów klienta |
| `declared_shape_test.exs` | nowy, wydzielony z `graph_test.exs` — jego assercje są o modelowaniu `Rehmed.Contracts.ClinicalVisit`, nie o rendererze: że notatka nie jest zdarzeniem, że wejście do gabinetu to inny fakt niż przyjście do przychodni, że dwa okna zagnieżdżają się na jednym celu. Przepięte na wymyśloną fiksturę nadal by przechodziły i nie sprawdzałyby już niczego |
| `docs_test.exs` | pilnuje `docs/contract.md`, patrz dług niżej |

### Trzy rzeczy, które wyszły dopiero przy przenoszeniu

1. **`docs/contract.md` jest artefaktem pakietu trzymanym jako artefakt gospodarza.** Test bram
   kompilacyjnych pojechał do pakietu, dokument został — bo wskazują na niego po tej ścieżce `CLAUDE.md`,
   `README.md`, dwa skille i dwie destylacje, a `mix pns.docs` rozwiązuje ją względem katalogu roboczego.
   Skutek: `docs_test.exs` czyta teraz przez szew, po ścieżce `packages/pns_core/test/…`. Działa
   i jest brzydkie. Do zrobienia razem z przeniesieniem dokumentu i `--path` w tasku.
2. **Fikstury nie miały trzech kształtów, które miał kontrakt klienta**, i dopiero przenoszenie to
   pokazało: procesu bez `trace`, procesu bez `external`, przebiegu z dwóch pól z `cadence`, oraz
   obietnicy z `or_else`, której drugie zakończenie jedzie przez kolejkę. Bez tego ostatniego nie da się
   odróżnić „jeszcze nie" od „nigdy" — a to jest jedyny powód, dla którego werdykt `:pending` istnieje.
   Stąd `ProcessShapes.Bare` i `ProcessShapes.Promised`. Fikstury urosły, testy nie zmalały.
3. **`ContractExamples` mieszkał w `test/support/` gospodarza**, więc własne fikstury silnika nie mogły
   sprawdzić swoich `example` bez pożyczenia modułu z drzewa klienta. Wjechał do `lib/` jako
   `PNS.ContractExample`, tak jak `Oban.Testing` siedzi w `lib/`: suita konsumenta musi go zawołać, a
   moduł kompilowany tylko pod `MIX_ENV=test` w tym pakiecie u nikogo innego nie istnieje.

Do tego jedna rzecz o konfiguracji, znów: path dependency nie wciąga konfiguracji ani `test/support/`
zależności — pakiet w drzewie gospodarza kompiluje się bez swoich fikstur, więc `mix pns.check`
w tym projekcie przestał raportować rig i bramę uniwersalności. To jest poprawne (`pns.check` gospodarza
ma mówić o kontraktach klienta) i było niewidoczne, dopóki fikstury leżały tutaj.

## Dopisek 21 sierpnia — brzegi silnika: trzy usterki, cztery ciche zielenie i jedno znalezisko spoza listy

TaxVision i Rehmed przejeżdżały wyłącznie wygodnym środkiem każdego okna i każdego typu. Ten dopisek
jest o brzegach. 324 testy, `mix check` zielony, ostrzeżenia nadal cztery plus jedno z 19 sierpnia.

### Naprawione — trzy usterki, każda z testem, który przed poprawką jest czerwony

1. **Klucz idempotencji sklejał wartości `identity` dwukropkiem i nie eskejpował niczego.** Przy
   `identity: [:a, :b]` wartości `("x:y", "z")` i `("x", "y:z")` dawały jeden klucz. Skutek jest
   cichy w najgorszy możliwy sposób: drugi fakt czyta się w tabeli idempotencji klienta jako powtórzenie
   pierwszego, jego handler nigdy nie rusza, żaden wiersz tego nie odnotowuje, a oba zdarzenia leżą
   w logu jak obsłużone. `PNS.Instance` eskejpował swój `"|"` od pierwszego dnia — dwa mechanizmy
   robiły to samo i tylko jeden miał rację.
2. **`PNS.Check.finer?/2` porównywał klucze jako listy**, więc `[:b, :a]` wobec `[:a, :b]` wychodziło
   „drobniejsze”. Fałszywy pozytyw akurat na sprawdzeniu, którego cała wartość polega na byciu
   wiarygodnym co do kierunku pomyłki — a jedyna poprawka, po którą sięgnie czytelnik, czyli
   przestawienie pól w keywordzie, nie zmienia nic. Teraz zbiory.
3. **Klucz rozłączny z `instance` nie był łapany przez nic**, i jest groźniejszy od drobniejszego:
   klucz idempotencji bierze się z `identity` i z niczego więcej, więc fakt, którego klucz nie
   zawiera przebiegu, skleja dwa przebiegi w jeden. Osobne sprawdzenie
   (`PNS.Check.facts_not_keyed_by_their_run/1`), nie gałąź sąsiada: inna populacja — każde zdarzenie,
   nie tylko kotwica assercji; inna konsekwencja — pominięty skutek, nie za łagodny werdykt; inna
   poprawka — na zdarzeniu, nie na procesie.

Oba sprawdzenia biorą teraz jawną listę kontraktów. Fikstura zbudowana po to, żeby być błędem
modelowania, weszłaby inaczej do rejestru i wisiała ostrzeżeniem na każdym `mix pns.check` w tym
repozytorium — a to jest sposób, w jaki sprawdzenie się wyłącza.

### Cztery ciche zielenie, każda z linią w `pns.check`

4. **Dwa kontrakty deklarujące tę samą nazwę zdarzenia.** Pytanie brzmiało o `declared_events/0`
   i `process_of/1` — żadne z nich nie jest dwuznaczne: pierwsze tagguje każde zdarzenie jego
   kontraktem, drugie jest generowane per kontrakt i widzi tylko własne. Dwuznaczne jest każde
   wyszukanie po samej nazwie, a dispatch jest jednym z nich: `handlers_for/1` filtruje po `event`
   i nie patrzy na `contract`. Pokazane testem, nie argumentem — `test/check_ambiguity_test.exs`
   emituje `item_measured` z kontraktu, którego nie ma w rejestrze i który nie dzieli z rigiem nic
   poza stringiem, a oba handlery riga się wykonują, w tej transakcji, na payloadzie, którego rig
   nigdy nie zadeklarował. Cicho scalają się jeszcze dwaj czytelnicy: `PNS.Graph.overlay/1`
   i `PNS.Check.stage_index/0` indeksują węzły po nazwie zdarzenia. `:error`.
5. **Dwa kontrakty deklarujące tę samą nazwę procesu.** `"<process>|<values>"` nie niesie kontraktu,
   więc to nie jest zbieżność, tylko jeden string. `overlay/1` liczy przebiegi po nazwie procesu,
   czyli obcy emitujący cokolwiek poprawia twoje pokrycie. `PNS.Trace` jako jedyny filtruje po
   kontrakcie — więc assercje zostają uczciwe obok liczb, które nie są, a to jest gorsza mieszanka niż
   jedno albo drugie osobno. `:error`.
6. **Zero kontraktów** dawało `0 errors, 0 warnings, 0 notices`, czyli dokładnie tę samą linię co czyste
   repozytorium. `:warn`, i wypisuje skonfigurowane aplikacje, bo błąd jest tam, a nie w kontraktach.
7. **`trace` bez `within` nie ma przypadku porażki**: cokolwiek po `from` ją spełnia, a przebieg bez
   niczego zostaje `:pending` na zawsze, bo okno, które musi minąć, nigdy się nie zamyka. Przypięte
   oceną rok po fakcie. `:info`, zgodnie z notatką zapisaną w `PNS.Trace` przy pisaniu ewaluatora.

Żadne z czterech nie odzywa się na materiale tego repozytorium i każde ma test kontrolny, który to
mówi — inaczej jedynym dowodem na sprawdzenie byłaby jego własna cisza.

### Przypięte, nie zmienione

`test/trace_edges_test.exs`, `test/payload_edges_test.exs`, `test/scale_edges_test.exs`.

**Jedna asymetria i jest świadoma:** trafienie dokładnie w termin jest w oknie (`in_window?`
porównuje `!= :gt`), zegar dokładnie na terminie jest już po (`pending?` porównuje `== :lt`). Obie
połowy przypięte osobno, bo czytając którąkolwiek samą chce się dopasować ją do drugiej. Cena jest
nazwana: zostaje jednoinstantowy wyścig, w którym zdarzenie zapisane mikrosekundy za późno jest sądzone
przeciw oknu, które właśnie się zamknęło.

Reszta, skrótem: trafienie w tej samej mikrosekundzie co `from` spełnia, a mikrosekundę wcześniej nie;
dwa `from` w jednym momencie to nadal jeden werdykt; `from` z przyszłości czeka, a nie jest sądzone;
awaria jest domknięta na obu końcach okna; pusty `:string` jest legalny tam, gdzie pusty `:id` nie
jest, i to nie jest niespójność; 28-cyfrowy integer przeżywa log; offset normalizuje się do UTC i nie
da się go potem odzyskać; `:enum` przyjmuje dowolny atom i dowolny string; atom wraca z logu jako
string, więc `case` po atomach przestaje pasować w dniu, w którym handler staje się asynchroniczny;
obie granice okresu raportu są domknięte, więc dwa sąsiadujące okresy liczą zdarzenie na styku dwa
razy.

Skala: 10 000 zdarzeń w jednym przebiegu → jeden werdykt, zakotwiczony na najwcześniejszym;
50 000 przebiegów → 50 000 w mianowniku. Cztery testy, 1,1 sekundy.

### Zostawione, z powodem

| Co | Dlaczego nie ruszone |
| --- | --- |
| ~~`within: {0, :day}` się kompiluje~~ — ✅ zamknięte 21 sierpnia | Rozstrzygnięcie po drodze: zero zostaje legalne (czyta się jako „w tej samej chwili”, przetestowane), tylko ujemna liczba jest odrzucana. `PNS.Duration.t` poprawione na `non_neg_integer()`. Patrz „Dopisek 21 sierpnia (3)” wyżej |
| ~~Awaria zależności zadeklarowanej wyłącznie przez `or_else` zawiesza przebieg~~ — ✅ rozstrzygnięte 21 sierpnia, bez zmiany kodu | Zapytany, kto ma decydować o tym osądzie — nie ma tu prawdziwego process ownera, fikstura jest wymyślona — zdecydowałem zostać przy dzisiejszym zachowaniu: kontrakt mówi „X albo Y", a Y było niemożliwe, i to wystarcza jako powód wstrzymania werdyktu, nawet gdy X nie zależało od niczego. `@tag :known_defect` zdjęty, bo asercja przeciwna nie ma już czekać na nic — patrz „Dopisek 21 sierpnia (6)" niżej |
| Trzy assercje samozwrotne | `from == eventually` i `from == or_else` nie mogą zawieść i kompilują się; `eventually == or_else` zawieść może, ale trwale zeruje połowę rozbicia „przez eventually / przez or_else”, czyli dokładnie tę informację, dla której werdykt niesie `via:`. Przypięte, nie zabronione — brama kompilacyjna to decyzja słownikowa |
| ~~Eskejpowanie separatora nie jest odwracalne~~ — ✅ zamknięte 21 sierpnia | Migracja, przez którą nie było jak przejść, okazała się nie istnieć: `pns_events` i `oban_jobs` są puste w `dev` i w `test`, i nigdzie indziej nie ma wdrożenia, które by to obwodowanie czytało — TaxVision i Rehmed są danymi testowymi, nie produkcją. Sprawdzone `psql` przed poprawką, nie z pamięci. Patrz „Dopisek 21 sierpnia (4)” niżej |

### Znalezisko spoza listy: eskejp, który nie jest eskejpem — ✅ zamknięte 21 sierpnia, patrz dopisek (4)

Wyszło przy pisaniu testów payloadu, nie z listy, przeciw której były pisane. `PNS.Instance` zamienia
`|` na `%7C` i zostawia `%` w spokoju, więc odwzorowanie nie jest różnowartościowe: wartość
zawierająca dosłowny tekst `%7C` daje ten sam klucz przebiegu co wartość zawierająca `|`. To jest ta
sama usterka, którą naprawia pierwszy commit tej serii, tylko węższa — i `PNS.Job` ją odziedziczył,
bo dostał to samo eskejpowanie celowo, żeby oba mechanizmy się zgadzały.

`@tag :known_defect`, nie poprawka wtedy: eskejpowanie `%` jako `%25` zmienia format każdego
`instance_id`, jaki kiedykolwiek zapisano. Stare wiersze zostają w starym kodowaniu, więc przebiegi
rozjeżdżają się na wdrożeniu, a po stronie joba przeformatowane klucze leżą w tabelach idempotencji
**klientów**. To była decyzja migracyjna, nie poprawka błędu — dopóki nie było wiadomo, czy migracja
jest z czego robiona.

**Zamknięte 21 sierpnia, patrz dopisek (4) niżej: sprawdzone `psql`, nie z pamięci — migracji nie ma z
czego robić.** `pns_events` i `oban_jobs` są puste w `dev` i w `test`, a żadne wdrożenie poza tym
repozytorium nie czyta tego obwodowania — TaxVision i Rehmed są danymi testowymi. Koszt migracyjny, który
uzasadniał tag, dziś wynosi zero.

### Drobiazg do rozstrzygnięcia przez człowieka

Przykład w moduledoku `mix pns.report` mówi `--until 2026-07-31T23:59:59Z`. Granice są domknięte, więc
ten przykład gubi wszystko, co wydarzyło się w ostatniej sekundzie miesiąca. Nie ruszone, bo nie
wiem, czy przykład ma być poprawny, czy poglądowy — a jeśli poprawny, to poprawną wartością jest
`23:59:59.999999Z`, co widać dopiero, gdy się wie, że kolumna jest `utc_datetime_usec`.

## Dopisek 20 sierpnia — silnik wyjęty do `packages/pns_core`, i ile to naprawdę kosztowało

`README.md` twierdził, że przeniesienie drzewa klienta to `git mv`, a `CLAUDE.md`, że tymczasowość jest
faktem, nie obietnicą. Nikt tego nie sprawdził, więc wyciągnięcie było jednocześnie eksperymentem.

**Dla `lib/` twierdzenie się obroniło**: `git mv lib/pns packages/pns_core/lib/pns`, własny `mix.exs`,
zależność `path`, i ani jedna linia w `lib/taxvision/` ani `lib/rehmed/` się nie zmieniła. `boundary`
pilnował tego szwu od pierwszego commita i szew okazał się prawdziwy.

**Ale trzy rzeczy wyszły dopiero przy próbie, i wszystkie są o konfiguracji, nie o kodzie:**

| # | Co pękło | Dlaczego to własność biblioteki, nie usterka |
| --- | --- | --- |
| 1 | `@repo Application.compile_env!(:pns_prototype, :repo)` w siedmiu modułach | pakiet kompiluje się przed aplikacją, która go konfiguruje. Każde wywołanie ostrzegało, że `Taxvision.Repo` nie istnieje — u prawdziwego konsumenta ostrzegałoby o jego repo. Biblioteka nie może trzymać referencji kompilacyjnej do modułu, którego użytkownik jeszcze nie napisał. Zamienione na `Application.fetch_env!/2` w runtime; traci się sprawdzenie `compile_env!`, że konfiguracja nie zmieniła się od buildu |
| 2 | `PNS.Registry.load!(app \\ :pns_prototype)` | domyślną była jedyna aplikacja, jaka wtedy była, więc pytanie nigdy nie padło. Po wyciągnięciu biblioteka z domyślną własną nazwą skanuje samą siebie, nie znajduje kontraktów i raportuje zdrowy pusty graf — `0 errors, 0 warnings, 0 notices`. Cicha porażka w stronę zieleni, ta sama rodzina co granulacja i jednostka liczby. Teraz `config :pns, applications: [...]`, a brak wpisu jest błędem, nie ciszą |
| 3 | fikstury w `test/support/` czytały nazwę aplikacji gospodarza | te same dwa wzorce co wyżej |

**Wniosek dla pakietu, nie dla tego repo:** granica modułowa была prawdziwa, a granica konfiguracyjna
nie istniała — nikt jej nie pilnował, bo w jednej aplikacji nie ma jej jak złamać. To jest dokładnie ta
klasa rzeczy, których nie da się sprawdzić inaczej niż wyciągnięciem.

Zostaje do zrobienia: `PNS.Migrations` (dziś pięć tabel silnika leży wymieszanych z migracjami TaxVision
w `priv/repo/migrations/`) i przeniesienie testów silnika do pakietu — 22 z 27 plików testowych
odwołuje się do `Taxvision`, bo `boundary` nigdy nie objął `test/`. *(Oba zrobione 21 sierpnia —
patrz dopisek na górze.)*

## Dopisek 18 sierpnia — pierwszy kontrakt z prawdziwego zlecenia

`lib/rehmed/contracts/clinical_visit.ex`: dokumentacja wizyty i zgłoszenie zdarzenia medycznego do P1,
zdestylowane z warsztatów Rehmed przez [`docs/rehmed-2026-08-18-distillation.md`](docs/rehmed-2026-08-18-distillation.md).
**Czwarty kontrakt, pierwszy, którego nikt tutaj nie wymyślił** — dotąd dowodem uniwersalności była
zmyślona domena medyczna z `test/support/`, co jest dowodem na słownik, nie na zderzenie z klientem.

Trzy rzeczy, które wyszły dopiero przy pisaniu, i żadna nie jest o Rehmedzie:

1. **Granica agregatu ≠ granica procesu, i to się tu po raz pierwszy rozjeżdża widocznie.** Cztery agregaty
   modelu klienta dzielą jeden klucz instancji. Gdyby zrobić z nich cztery procesy, jedyna assercja warta
   posiadania — od zakończenia świadczenia do zgłoszenia ustawowego — nie skompilowałaby się, bo `trace`
   nie przekracza procesu. To jest zdrowe ograniczenie, ale trzeba je znać przed modelowaniem, nie po.
2. **~~`unverified` nie obejmuje `trace`.~~ ✅ zamknięte 21 sierpnia**, patrz „Dopisek 21 sierpnia (8)".
   `PNS.Conformance.verified_declarations/1` filtrowało wyłącznie `:cadence` i `:deadline`, więc spornej
   assercji nie dało się wyłączyć z raportu dowodowego. Tutaj obie liczby były mocne (ustawa i decyzja
   klienta z datą), więc nic złego się wtedy nie działo — ale mechanizm nie powstrzymałby gorszej pary.
3. **Assercja mierzy od momentu, w którym nam powiedziano, nie w którym się wydarzyło.** Okno biegnie od
   wpisu w logu. Przy procesie, którego istotą jest odraczanie zapisu, to jest przekłamanie w stronę
   optymistyczną. Kotwica została wybrana tak, żeby zapis był współczesny zdarzeniu — ale to jest wybór
   modelujący, a nie własność silnika, i następny klient może go nie mieć.

Rehmed nie ma tu kodu i nie będzie miał: to drzewo jest wyłącznie kontraktami, bo do sprawdzenia DSL
kod nie jest potrzebny. Wszystkie zdarzenia są `declared, never observed`, czyli dokładnie ten stan, który
`pns.check` raportuje jako `info` i który notes §5 opisuje jako normalny w trakcie wdrożenia.

### Drugi kontrakt Rehmed — rozliczenie płatnika. Cztery luki, jedna groźna

`lib/rehmed/contracts/payer_settlement.ex`, ten sam dzień. Wart więcej niż pierwszy, bo jest miejscem,
w którym DSL się skończył — a przy danych testowych to jest lepszy wynik niż kontrakt napisany gładko.

| # | Luka | Waga |
| --- | --- | --- |
| 1 | ~~Assercja drobniejsza niż przebieg nie jest łapana i myli się w stronę dobrych wieści.~~ ✅ zamknięte 21 sierpnia — `PNS.Trace` liczy teraz per element, patrz „Dopisek 21 sierpnia (5)". Nie zamyka tego kontraktu: luka 2 wciąż blokuje napisanie tej assercji tutaj | było to jest produkt, teraz zamknięte jako mechanizm silnika |
| 2 | Zdarzenie należy do jednego procesu, a obietnica potrzebuje dwóch. Naturalną kotwicą jest *wizyta wykonana*, która należy do przebiegu wizyty. Scalenie procesów nie pomaga: jeden z dwóch liczników przestaje mieć sens | duże — to jest ta sama granica, o którą rozbił się pierwszy kontrakt, widziana z drugiej strony |
| 3 | `instance` to nie „pola grupujące przebieg", tylko „pola znane w chwili zdarzenia" — i DSL nigdzie tego nie mówi. `E-85` rejestracja u płatnika dzieje się przed wykonaniem, a okres rozliczeniowy nie jest wtedy znany. TaxVision tego nie ujawnił, bo miesiąc księgowy jest znany przed jakąkolwiek pracą w nim | średnie — kandydat na zdanie w `docs/contract.md` |
| 4 | ~~`unverified` nie obejmuje `trace`~~ — ✅ mechanizm zamknięty 21 sierpnia, patrz „Dopisek 21 sierpnia (8)". `H38` (przyjęcie płatnika w 7 dni) wciąż nie jest napisane w `payer_settlement.ex` — blokuje ją luka 2 (kotwica w innym procesie), osobna od tej | było z obserwacji staje się pozycją backlogu |

Dwie rzeczy, które przy okazji wyszły na plus i warto je znać jako precedens:

- **Zależność obsługiwana ręcznie nie ma obserwowalnej awarii.** `external` jest zadeklarowany i żadne
  zdarzenie nie ma `depends_on` — bo awaria to człowiek, który czegoś nie przepisał, a `:suspended` bierze
  się z zaobserwowanej niedostępności. Deklaracja bez `depends_on` jest tu poprawną odpowiedzią, nie
  niedbalstwem.
- **`retain: :persist` na polu `:string` bywa decyzją, nie zaniechaniem.** Powód wykluczenia wizyty
  z faktury musi być czytelny, więc `:hash` spełniłby kontrolę retencji i zniszczył deklarację. Kontrast
  z kontraktem klinicznym, który nie ma ani jednego `:string`, jest tu celowy i pokazuje, że kontrola
  retencji potrzebuje czytelnika, nie reguły.

### Trzeci kontrakt Rehmed — rozliczenie wizyty. Pieniądze, i czym one naprawdę są

`lib/rehmed/contracts/visit_settlement.ex` plus jedyny kawałek kodu domenowego w tym drzewie,
`lib/rehmed/settlement.ex`. Napisany po to, żeby zmierzyć się z pieniędzmi zamiast je omijać — pierwsze
dwa kontrakty Rehmed omijały, a TaxVision omija też: `turnover_matched_with_invoice` paruje obrót
z fakturą po identyfikatorach i nie niesie ani jednej kwoty, w produkcie księgowym. Trzy kontrakty,
zero kwot, i nikomu to nie wyglądało na lukę.

**Wniosek nie brzmi „brakuje typu pieniężnego".** Grosze w `:integer` to poprawna reprezentacja pieniędzy
— sumy i porównania są dokładne, a alternatywa, która wygląda przyjaźniej (dziesiętna liczba jako tekst),
traci arytmetykę i ląduje w `:string`, czyli w typie, który znaczy *tekst wpisany przez człowieka* i jako
jedyny odpala kontrolę retencji.

> **Brakuje sposobu na powiedzenie, co dana liczba liczy.** `task_count` liczy taski, `recipients`
> liczy adresatów, `amount_minor` liczy grosze — i wszystkie trzy są `:integer`, nierozróżnialne.
> Drugi kontrakt wpisujący złote w pole, w które pierwszy wpisuje grosze, kompiluje się, emituje
> i jest źle zsumowany w raporcie. Żadna brama tego nie widzi — ta sama klasa cichej,
> prawdopodobnie wyglądającej porażki co granulacja assercji wyżej.

Obejście zastosowane w kontrakcie to konwencja nazewnicza: każda kwota kończy się na `_minor`.
**Konwencja nie jest gwarancją** i nazwanie jej gwarancją byłoby tym rodzajem twierdzenia, które to
repozytorium ma wykrywać u innych.

**Jeśli kiedyś dokładamy typ, to `:decimal`, nigdy `:money`.** `:decimal` jest kształtem — dokładna
liczba dziesiętna, która nie może być floatem — i potrzebuje jej fizyka, stawki podatkowe i wagi tak samo
jak ceny. `:money` nazywa rzecz, którą rozpoznaje księgowy, czyli powtarza błąd `:period`. Próg dowodowy
niech będzie ten sam, który zabił `:period` — liczenie: przez cztery kontrakty pola, które użyłyby
`:decimal`, to trzy, wszystkie w tym jednym pliku. Za mało. I powodem, gdy przyjdzie, będzie
**dokładność, nie pieniądze**.

Trzy rzeczy przy okazji:

- **Silnik nigdy nie czyta wartości payloadu.** `identity` i `instance` biorą pola jako klucze,
  `PNS.Emitter` sprawdza kształt — liczbę czyta wyłącznie `rule` przez `example`, a `given:` jest
  **nietypowane**. Więc pieniądze w przykładach są całkowicie poza zamkniętym zbiorem. To osłabia całą
  panikę o typ pieniężny i warto to wiedzieć, zanim ktoś zacznie go dokładać.
- **Atrybut, który istnieje tylko czasem, nie może być polem** — drugi raz. Pole zadeklarowane musi być
  na każdej emisji, więc opcjonalność wyraża się osobnym zdarzeniem. Tu boli mocniej niż przy dopisku
  ICD-9: `DEC-05` chce, żeby każda linia płatności nazywała swojego płatnika, a linia opłacona prywatnie
  nie ma płatnika do nazwania. Przypadek mieszany jest w tym kontrakcie niewyrażalny i jest to
  zapisane jako luka, nie zaklejone polem nullowalnym, którego DSL i tak by nie przyjął.
- **`rule`/`example` w drugiej domenie działa i jest wykonywane.** `test/rehmed_contract_examples_test.exs`
  używa tego samego generatora co TaxVision, cztery przykłady z prawdziwymi liczbami klienta
  (150 + 50 = 200, VLW 00:19:58). Sprawdzone mutacją: odwrócenie warunku w `decide/1` wywala trzy z pięciu
  testów. „Przykład jest testem" jest własnością DSL, nie oprzyrządowania jednego kontraktu — i teraz jest
  na to drugi dowód.

### 19 sierpnia — luka granulacji przypięta testem, i obrazek dla właściciela procesu — ✅ zamknięte 21 sierpnia, patrz „Dopisek 21 sierpnia (5)" wyżej

**Test, który pada na żądanie.** `test/trace_granularity_test.exs`. Cztery testy opisują dzisiejsze
zachowanie (trzy elementy obiecane, jeden dostarczony, raport mówi `satisfied`), plus kontrola pinująca
`violated`, żeby tamte nie przechodziły z nudniejszego powodu. Piąty, otagowany `:known_defect`
i wykluczony w `test_helper.exs`, twierdzi to, co być powinno — `mix check` zostaje zielony, a
`mix test --include known_defect` jest naprawdę czerwony. Nowa fikstura nie była potrzebna:
`ProcessShapes.Rig` już miał ten kształt (`submission_reaches_inspection` biegnie między dwoma
zdarzeniami per element w procesie kluczowanym po sprawie) i nikt tego nie zauważył.

Ostrzejsza połowa znaleziska wyszła dopiero przy pisaniu testu: trafienie nie musi dotyczyć tego samego
elementu, co otwarł okno. Ewaluator szuka pierwszego wystąpienia celu po pierwszym wystąpieniu źródła
i nigdy nie porównuje payloadów.

**`PNS.Graph.declared_to_mermaid/2`** — kształt zadeklarowany jednego procesu: etapy jako tory, zdarzenia
w nich, zakończenia oznaczone, każda assercja jako strzałka z liczbą, zależność zewnętrzna na linii bez
grotu. `mix pns.graph --mermaid --process <nazwa>`.

**To nie jest graf odrzucony w etapie 4** i różnica jest rozstrzygająca, nie kosmetyczna: tamten rysował
krawędzie z rejestru handlerów, dla zespołu. Kontrakt bez implementacji ma zero krawędzi, więc tamten
obrazek dla `ClinicalVisit` to jedenaście nierozłączonych pudełek. Sekwencja kontraktu siedzi w `stages`,
`terminal` i `trace` — i żadne z tych trzech nie pojawia się na grafie handlerowym.

Zastrzeżenie zapisane przy funkcji: obrazek łatwiej pokiwać głową niż poprawić. Ma stać nad zdaniami
assercji, nie zamiast nich; miarą sesji jest liczba poprawek.

**Obrazek znalazł w kontrakcie trzy niedomiary w dwóch rundach, i to jest dowód o narzędziu, nie
o Rehmedzie.** Runda pierwsza: jedenaście pudełek, jedna strzałka — brakowało twierdzenia, że zamknięcie
kliniczne następuje po pracy, którą zamyka. Runda druga, po obejrzeniu PDF-a przez człowieka: brakowało
twierdzenia, że wywiad i zabieg poprzedzają wyjście pacjenta — i brakowało samego początku wizyty.
`E-40 Pacjent wszedł do gabinetu` nie był zadeklarowany, choć `E-51` (wyjście) był, a `AGG-01` wymienia
`E-27`, `E-40` i `E-51` jako jedną rodzinę przejść wywoływanych przez pacjenta. Wziąłem koniec
świadczenia bez jego początku.

Runda trzecia, ten sam czytelnik nad tym samym PDF-em: kolejność wewnątrz gabinetu była zła, a jednej
notatki w ogóle nie było. `E-49 Zapisano notatkę widoczną w recepcji` nie istniało w kontrakcie, a
`E-42 Powielono notatkę z poprzedniej wizyty` wisiało obok zabiegu, jakby było krokiem po nim — podczas
gdy `AGG-02` rysuje `C-19` i `C-20` jako dwie krawędzie do tego samego stanu: to jest wariant
wywiadu, nie trzeci krok. Etapy: `[:start, :interview, :treatment, :departure, :documentation, :closing,
:reporting]`.

Wzorzec we wszystkich trzech rundach ten sam i wart nazwania, bo się powtórzy: strach przed jednym fałszywym
twierdzeniem o kolejności dał zero twierdzeń, a te dwie rzeczy są trudne do odróżnienia na liście
deklaracji i trywialne do odróżnienia na rysunku. Etapy: `[:start, :delivery, :departure, :documentation,
:closing, :reporting]`. Trzy z sześciu mają jedno zdarzenie — to nie przypadek, tylko cena porządku
totalnego: „te w dowolnej kolejności, potem to jedno" kosztuje osobny tor na każdy moment.

**Jedna granica została jawnie sporna i tak ma zostać:** `:departure → :documentation` twierdzi, że
kodowanie ICD dzieje się po wyjściu pacjenta. Tablica sekwencjonuje `E-44` przed `E-51`, więc jako
opis intencji jest to nieprawda; transkrypty opisują odraczanie pod obciążeniem, więc jako opis praktyki
jest to prawda. To jest pytanie do klienta, nie rozstrzygnięcie dla nas.

**A `E-27 Klient pojawił się na wizycie` świadomie nie wszedł.** To jest poczekalnia — recepcyjne
*czeka na kanapie*, read model `R-03` — a `20-aggregates.md` ostrzega wprost, że mieszanie stanu
obecności fizycznej ze stanem przepływu pracy jest błędem, który popełniła paleta kolorów z tablicy.
`E-27` należy do procesu rezerwacji, którego nikt jeszcze nie napisał.


**Przeglądanie modułu nie wyłapało żadnego z trzech; rysunek wyłapał wszystkie.**

**Czwarta luka DSL, i jedyna z tych czterech bez obejścia: `stages` wyraża wyłącznie porządek liniowy.**
Prawdziwy kształt tej domeny to porządek częściowy — zamknięcie po wszystkim, reszta wzajemnie
nieuporządkowana. Lista faz jest porządkiem totalnym, więc wszystko nieuporządkowane musi dzielić tor,
a przez to uporządkowania, które wewnątrz toru zachodzą, są niewyrażalne. Granulacja, jednostka
liczby i porządek częściowy mają ten sam kształt: DSL przyjmuje deklarację mówiącą co innego, niż autor
sądzi, i nic tego nie sygnalizuje.

Renderer mówi o tym wprost — tor z więcej niż jednym zdarzeniem nosi w tytule `no order claimed inside`.
Bez tego pudełka bez strzałek czytają się jako *niedokończone*, a nie jako *świadomie nieuporządkowane*,
i te dwa odczyty zbierają zupełnie inne poprawki.

**Przy okazji naprawiony `within 24 hour`.** Liczba mnoga była wypisana ręcznie dla `:month` i `:day`,
reszta jednostek wpadała w gałąź ogólną. Przeniesione do `PNS.Duration.humanize/1`, czyli do modułu,
który i tak jest jedynym źródłem prawdy o jednostkach — `PNS.Report` deleguje. Przeżyło cztery
kontrakty, bo żaden nie użył godzin aż do czwartego.

## Stan na 6 sierpnia

221 testów, `mix check` przechodzi. Ostrzeżenia są cztery i wszystkie celowe (piąte doszło
19 sierpnia — patrz dopisek na górze):

1. `deadline` TaxVision bez potwierdzenia process ownera,
2. `deadline` z wymyślonej fikstury bramy uniwersalności,
3. **krawędź wsteczna** w stanowisku badawczym kształtów — kryterium odbioru 1.3,
4. **dwa handlery synchroniczne na jednym zdarzeniu** — kryterium odbioru 2.4.

Brak trzeciego albo czwartego byłby regresem, nie poprawą. Samo `mix pns.check` w środowisku dev pokazuje
jedno, bo fikstury żyją w `test/support/`.

Działa: kontrakt jako moduł Elixira z bramami kompilacyjnymi, dispatch po granicy transakcji, log zdarzeń,
`boundary`, szew tożsamości, nakładka declared vs observed z czterema stanami, tożsamość instancji procesu
i liczniki w dwóch wymiarach (wystąpienia i przebiegi), drugi kontrakt z obcej domeny bez ani jednego
nowego słowa w DSL, **ocena assercji `trace` per przebieg — cztery werdykty z czterech, **raport
nieprzejechanych ścieżek per przebieg, **`publishes:` wiąże handler w runtime, nie tylko opisuje,
**obie tożsamości wdrożenia haszują się kanonicznie, z jednego źródła, awaria handlera synchronicznego
zostawia ślad, a raport odróżnia „próbowane i nie udaje się" od „nigdy nie próbowano", cykl w runtime
jest zatrzymany na obu ścieżkach dispatchu, kolejność handlerów synchronicznych jest odtwarzalna, a job
po znikniętym handlerze jest anulowany i zapisany, payload jest walidowany przeciw zadeklarowanym typom,
a `:timestamp` jest punktem w czasie po obu stronach kolejki, telemetria emituje to, czego nie widzi
nikt inny — handlera i naruszenie kontraktu.

**Nie działa, bo nie zostało zbudowane — i to jest produkt:**

| Luka | Waga |
| --- | --- |
| `deadline` procesu jest zadeklarowany i nie czyta go nikt — jedyni czytelnicy to filtr, który go wyrzuca, i renderer, który by go wypisał; `deadline_at` w `PNS.Trace` pochodzi z `within`, czyli z innej deklaracji | to jest produkt — zwężone 6 sierpnia, patrz „Rozstrzygnięte 6 sierpnia" niżej |
| `cadence`'s „never observed" — odrzucone 6 sierpnia, patrz „Rozstrzygnięte 6 sierpnia" niżej. Sama deklaracja `cadence` zostaje: kosztuje zero kodu i raport już ją wypisuje. | zamknięte |
| ~~Zbiór wartości `:enum` nie jest deklarowalny~~ — ✅ zamknięte 21 sierpnia, `{:enum, [...]}`, patrz „Dopisek 21 sierpnia (7)” | było drobne |

## Etap 1 — rdzeń weryfikacji

**1.1 Instancja procesu. ✅ zrobione 5 sierpnia.** `instance: [...]` w DSL, brama kompilacyjna: każde
zdarzenie procesu musi nieść pola instancji. Powód jest techniczny, nie sprawozdawczy — bez tego
„eventually Y" dopasuje Y z innego przebiegu.
*Odbiór:* assercja policzona dla dwóch równoległych przebiegów nie myli ich zdarzeń. Spełnione —
`test/instance_test.exs`, przebieg c-1 otwiera miesiąc, c-2 nie, i licznik per typ zdarzenia zaliczyłby oba.

Wyszło przy okazji, w kolejności ważności:

- `instance:` jest wymagane na każdym procesie, nie opcjonalne. Obie rzeczy, które czynią z tego produkt
  — ocena `trace` i nakładka — liczą się w obrębie przebiegu, więc brama opcjonalna byłaby dokumentacją.
- **Zdarzenie w dwóch procesach nie kompiluje się.** To warunek stopu z ADR §15 zrobiony mechanicznie: dwa
  procesy to dwie tożsamości przebiegu, a w logu jest na to jedna kolumna.
- **`trace` rozciągnięty na dwa procesy nie kompiluje się** z tego samego powodu.
- Brama znalazła jedno zdarzenie: `turnover_matched_with_invoice` nie miało `period`, więc meczowanie z lipca
  liczyłoby się jako postęp w sierpniu. Dopisane.
- Liczniki mają dwa wymiary: wystąpienia i przebiegi, plus mianownik „ile przebiegów w ogóle było".
  Krawędź przejechana 49 razy przez jedną firmę i raz przez 49 firm miały wcześniej identyczny licznik.
  Świadomie liczba, nie lista — które przebiegi milczą, to pytanie o konkretną firmę.
- Zdarzenia zapisane przed tym etapem nie mają tożsamości przebiegu i już jej nie dostaną; raport pisze
  „bez tożsamości przebiegu", nie „0 przebiegów". To ten sam problem, który przy wersjach kontraktu
  rozwiązuje stan `:historical`.

**1.2 Brama uniwersalności. ✅ zrobione 5 sierpnia — PRZESZŁA.** Drugi kontrakt z innej domeny, wyłącznie
kontrakt plus fake'i, bez implementacji.

Domena medyczna jest naturalnym wyborem, bo Rehmed startuje 10.08 — ale materiału warsztatowego z Rehmed
jeszcze nie ma, więc ten kontrakt jest świadomie wymyślony i jest tak oznaczony w pliku. Testuje
**słownik DSL, nie wiedzę o domenie**.
**Poprawka do samej bramy, 5 sierpnia:** kryterium „zero nowych słów" dowodzi, że DSL opisze inną
domenę — nie że silnik na niej zadziała. `PNS.Trace` i `PNS.Conformance`, zbudowane po przejściu bramy,
dostawały z kontraktu medycznego puste listy, więc ich uniwersalność była nieprzetestowana. Brama obejmuje
od teraz mechanizmy, nie tylko słownik — inaczej ten sam dryf wróci przy 1.6 i 1.7.

*Odbiór:* zero nowych słów w DSL. Spełnione — `UniversalityGate.TreatmentEpisode`
(`test/support/`, nie drzewo klienta, nie trafia do repo kontekstu) opisuje epizod leczenia od skierowania
do zamknięcia bez ani jednego nowego słowa. Kryterium jest teraz pinowane testem, nie deklarowane:
`PNS.Contract.vocabulary/0` wystawia słownik maszynowo, a `test/universality_gate_test.exs` porównuje go z
literałem. Dopisanie `population:` wywala ten test tego samego dnia.

Co brama pokazała, w kolejności ważności:

- **`cadence` nie ma zastosowania do procesu zdarzeniowego.** Epizod leczenia nie jest należny nigdy —
  zaczyna się, kiedy wpłynie skierowanie. Słowa nie brakuje, bo `cadence` jest opcjonalna. Ale mechanizm,
  który na niej stoi — okno „never observed" — nie ma dla takiego procesu skąd wziąć długości i spada na
  fallback z zaobserwowanych odstępów. Notatki §9 traktują ten fallback jako przypadek brzegowy; dla
  procesów zdarzeniowych jest stanem normalnym. Do poprawki w rekordzie.
- **„Kontrakt plus fake'i, bez implementacji" nie jest osiągalne, jeśli kontrakt ma regułę.** Brama §18
  wymaga przykładu, przykład wskazuje MFA, a `pns.check` sprawdza, że funkcja istnieje. Albo kontrakt bramy
  nie deklaruje reguł i zostawia §18 nieprzetestowane na drugiej domenie, albo dochodzi jedna czysta funkcja
  decyzyjna. Wybrane drugie. Do poprawki w opisie zakresu 1.2 w rekordzie.
- **`owner:` może wskazywać moduł, którego nie ma, i nikt tego nie sprawdza.** Widoczne już wcześniej
  (`Taxvision.Matching`), potwierdzone na drugim kontrakcie. ✅ zrobione 5 sierpnia — `info` w
  `pns.check`, zgrupowane po module, nie po zdarzeniu.
- **`:period` jest jedynym typem w słowniku, który nie jest uniwersalny.** Brama tego nie złapała, bo
  sprawdza, czy trzeba dopisać słowo, a nie czy któreś jest zbędne. Dowód: kontrakt medyczny ma
  czternaście pól w payloadach i nie używa `:period` ani razu. To „miesiąc księgowy" przebrany za typ
  ogólny. ✅ wypadł 6 sierpnia — szczegóły przy 2.2a, w tym wniosek o samej bramie.
- **`PNS.Graph` nie ma zawężenia do procesu ani kontraktu.** Drugi kontrakt ujawnił ukryte założenie „jest
  tylko jeden" — `graph_test` liczył węzły globalnie. Notatki §9 mówią wprost „navigation is per-process,
  never global", więc to jest luka, nie preferencja. Należy do 1.7/etapu 4, nie tutaj.
- **`identity` i `instance` razem uniosły kształt, którego TaxVision nie ma.** Dziesięć wizyt w jednym
  epizodzie to dziesięć faktów w jednym przebiegu — `identity: [:episode_id, :session_no]` przy
  `instance: [:episode_id]`. Gdyby to było jedno pojęcie, jedno z dwóch byłoby nie do wyrażenia.
- **`mix check` pokazuje teraz dwa ostrzeżenia, nie jedno.** Drugie pochodzi z wymyślonego `deadline` w
  fiksturze. Rejestr skanuje całą binarkę, a w środowisku testowym fikstura w niej jest — to ta sama
  własność, dzięki której „graf pochodzi z binarki, która działa". Samo `mix pns.check` (środowisko dev)
  fikstury nie widzi i pokazuje jedno ostrzeżenie. Do rozstrzygnięcia: czy raport dowodowy ma umieć
  wykluczyć przestrzeń nazw z konfiguracji silnika. Nie z DSL — to byłoby nowe słowo.

### Dokumentacja kontraktu — zrobione 5 sierpnia

`docs/contract.md`, po angielsku, bo to dokumentacja pakietu. Trzy mechanizmy anty-driftowe, bo bez nich
ręcznie pisany opis DSL-a jest drugim źródłem prawdy — a dziś znaleźliśmy cztery takie rozjazdy między
rekordem a kodem, w tym przykład DSL w notatkach §1 z typami, których w słowniku nie ma:

1. **Referencja kluczy jest generowana** z `PNS.Contract.schema/0` przez `mix pns.docs`. `--check` w
   `mix check` wywala build, gdy blok jest nieaktualny. Sprawdzone: podmiana jednej wartości domyślnej w
   dokumencie zatrzymuje bramę.
2. **Przykład jest fikstórą, nie ilustracją** — test kompiluje każdy blok kodu z kontraktem z tego pliku.
   Ta sama zasada, którą kontrakt stosuje do reguł, zastosowana do własnej dokumentacji.
3. **Każdy klucz DSL-a musi być w dokumencie wymieniony**, a tabela „co się nie skompiluje" nie może
   obiecywać więcej bram, niż jest testów bram.

Przy okazji `schema/0` zastąpiła sześć osobnych list kluczy jednym źródłem, z którego wyprowadza się
`vocabulary/0` i walidacja nieznanych kluczy. Wcześniej były to dwie rzeczy do rozjechania się.

I wyszła z tego jedna brama: `trace` bez `from` albo bez `eventually` się nie kompiluje. Wcześniej
kompilował się i produkował bezsens — nic nie mogło go spełnić, więc każdy przebieg wychodził jako
naruszony po upływie okna. Schema wymusiła nazwanie, co jest wymagane, i wtedy stało się widać, że
wymaganie nie było egzekwowane.

## Język kodu — ✅ spłacone 5 sierpnia

**Cały kod jest po angielsku.** 54 pliki, jeden commit, bo inaczej się nie dało: bramy kompilacyjne są
przypięte testami asertującymi na fragmenty własnych komunikatów, więc zmiana komunikatu bez testu wywala
bramę, a zmiana testu bez komunikatu nie pinuje niczego.

Granicę wyznacza kto czyta string, nie katalog:

- Po angielsku wszystko, co czyta programista albo kompilator — `lib/pns/`, drzewo klienta, zadania mixa,
  fikstury i testy. Fikstury, bo jadą z pakietem; testy, bo biblioteka z komunikatami bram w jednym języku
  jest biblioteką dla jednego kraju.
- Po polsku zostają cztery rzeczy, wszystkie treść, nie kod: `label`, `source`, opisy `example` i
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

Pytanie brzmiało: czy kontrakt nie dryfuje w stronę kontraktu pod TaxVision. Słownik nie dryfuje.
Dryfowały mechanizmy i krawędzie silnika — trzy znaleziska, wszystkie naprawione:

- **`PNS.Auth.Actor` miał `company_id`** jako pole struktury, czyli silnik wiedział, że aktorzy należą do
  **firm**. Przychodnia ma placówki, spedycja terminale. Umknęło, bo brama to kontrakt plus fake'i, a szew
  tożsamości nie jest częścią kontraktu. Teraz `claims: %{}` i najemcę czyta kod domenowy.
- **`within: {1, :month}` kompilowało się i wywalało w runtime.** DSL przyjmował jednostkę, której ocena nie
  umiała policzyć. Niewidoczne, bo oba kontrakty liczą w dniach — pisząc fikstórę medyczną
  bezrefleksyjnie skopiowałem nawyk TaxVision, choć dla epizodu leczenia `{3, :month}` jest naturalniejsze
  niż `{90, :day}`. Jednostki mają teraz jedno źródło prawdy (`PNS.Duration`) dla bramy i dla arytmetyki.
- **Raport ścieżek pomijał proces bez handlerów w całości**, czyli cały kontrakt bramy uniwersalności był
  nieobecny — a nieobecność czyta się jako „nie ma o czym mówić". Teraz `basis: :no_paths`.

Znalezione tutaj i naprawione tego samego dnia: runtime pakietu mówił po polsku (`to_text`, etykiety
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
jego wartość polega na tym, że jest kontraktem bez implementacji; jest też jedyną fikstórą, na której da
się sprawdzić raport dla procesu bez ani jednej ścieżki. Dopięcie handlerów zabrałoby oba pokrycia.

*Odbiór spełniony, i ważniejsza jest druga połowa:* check zgłasza jedną krawędź wsteczną
(`OnClarificationAnswered`: subskrybuje w `resolution`, publikuje do `matching`) i milczy na trzech
kontrolach, które publikują do przodu. Sam fakt, że check znajduje przypadek zbudowany pod niego, nie
dowodzi niczego — dowodem jest milczenie na kontrolach.

Kształty pokryte: krok, który się cofa (w checku i w runtime — para domyka się po wyjaśnieniu),
**to samo zdarzenie wiele razy w jednym przebiegu** (trzy pozycje = trzy fakty, jeden przebieg),
**zdarzenie wchodzące bez komendy** (bez aktora, bez przyczyny, a z tożsamością przebiegu).

Wyszło przy okazji:

- **Wykrywanie krawędzi wstecznych było logiką bez testu** — funkcją prywatną zadania mixa. Przeniesione do
  `PNS.Check`, bo sprawdzenie, którego nikt nie sprawdza, cicho przestaje działać, a na tym stoi trigger
  przeglądu ADR §15. Reszta `mix pns.check` to nadal ~180 linii logiki całoprogramowej bez ani jednego
  testu — do przeniesienia tą samą drogą.
- **Indirekcja `defp repo, do: @repo` w `PNS.Emitter` jest nośna, nie stylistyczna.** `@repo.aggregate(...)`
  rozwija atrybut do literału modułu w pozycji wywołania, więc `boundary` widzi referencję i odrzuca ją.
  Przez zmienną — nie widzi. To jest jedyny powód, dla którego `PNS` ma `deps: []`.
- **`clarification_requested` nie ma handlera i nie jest terminalne**, bo jego kontynuacja przychodzi z
  zewnątrz. Daje linię `info` i to jest uczciwe: nie ma w DSL słowa „czeka na świat zewnętrzny" i nie
  wolno go dopisać — to byłoby nowe słowo pod jeden przypadek.
- **~~Aktor jako `nil` nie odróżnia „import" od „nie wiemy kto".~~ ✅ zamknięte 21 sierpnia.** Sensowna
  wersja postulatu „każde zdarzenie ma aktora" to nie „wymagany", a „nigdy cisza" — jawny aktor
  systemowy, `PNS.Auth.system_actor/0`. Patrz „Dopisek 21 sierpnia (7)".

**1.3b Dwa moduły potrzebujące tych samych danych. ✅ zrobione 5 sierpnia.** Nośnikiem jest tabela
`taxvision_periods`: okres przestaje być stringiem i staje się wierszem z zakresem dat.

**Zakaz joinów międzymodułowych jest znośny, i jego cena jest zmierzona, nie opowiedziana.** `Taxvision.Tasks`
ustawia `due_on`, `Taxvision.AccountingMonth` ustawia `closes_on`, oba z tego samego okresu — i każdy płaci
własnym zapytaniem. Test liczy je telemetrią Ecto: dokładnie dwa trafienia w `taxvision_periods` na jedno
otwarcie miesiąca. Notatki §14 nazywają N+1 ryzykiem, nie niespodzianką; teraz jest liczbą.

Mechanizm, który to trzyma, jest mocniejszy niż zakaz: `Taxvision.Periods` ma `exports: []`, więc schemat
`Period` jest nieosiągalny z zewnątrz i join do niego jest niewyrażalny, a nie zabroniony. Ten sam ruch,
który zamienił „zdarzenie w dwóch procesach" ze sprawdzenia w niemożliwość. Rodzeństwo dostaje `fetch!/1` —
wywołanie funkcji, nie join.

Kanonizacja zadziałała natychmiast i widać to w testach: nie da się zaksięgować w okresie, który nie
istnieje. 23 testy padły przy pierwszym uruchomieniu, bo otwierały miesiąc bez kanonicznego okresu. To nie
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
sam wiersz nie gwarantuje, że dwa zdarzenia wskażą ten sam. Prawdziwy zysk to kanonizacja: przy kluczu
obcym `"2026-7"` obok `"2026-07"` przestaje być możliwe, a nie tylko niezalecane. Zamyka też dziurę, którą
miałby okres jako data — `2026-07-15` jest poprawną datą i cichym drugim przebiegiem tego samego miesiąca.

To jest dobre miejsce na kształt „dwa moduły potrzebujące tych samych danych" i lepsze niż przykład
wymyślony: `period` występuje w zdarzeniach należących do `RegistryCheck`, `Tasks`, `AccountingMonth`,
`Notifications` i docelowo `Matching`, więc każdy z nich musi ten okres rozwiązać. ADR §5–6 zabrania joinów
międzymodułowych, a `wiki/pns/modular-design.md` daje odpowiedź: strategiczna duplikacja z nazwanym źródłem
prawdy, nie wspólna tabela. Czyli budowanie tego nie jest objazdem, tylko realizacją punktu z listy.

**Kolejność wobec etapu 1: 1.5 i 1.4 idą przed 1.3** (ustalone 5 sierpnia). Powód: `trace`, `deadline` i
`cadence` są zadeklarowane i nie czyta ich żaden mechanizm w runtime — sprawdzone, nie z pamięci. To
jest produkt, a 1.1 i 1.2 były jego warunkiem wstępnym. 1.3 wymaga decyzji domenowych i materiału
klienckiego; 1.4 i 1.5 nie wymagają ani jednej linijki TaxVision, bo oba kontrakty już deklarują assercje.

**1.4 Behawioralna weryfikacja ścieżek, per instancja. ✅ zrobione 5 sierpnia.**
*Odbiór:* spełnione. `PNS.Conformance.untraversed_paths/1`, `test/conformance_test.exs`: 50 przebiegów
zgodnych → dokładnie jedna nieprzejechana ścieżka. 49 zgodnych plus jeden rozjazd → zero.

To jest jednocześnie odpowiedź na warunek falsyfikacji z ADR-a: różnica declared vs observed jest
sygnałem, nie szumem. Pięćdziesiąt przebiegów daje jedną linię raportu. Gdyby dawało pięćdziesiąt albo
trzy, odpowiedź brzmiałaby odwrotnie.

`PNS.Conformance` jest miejscem, w którym zbiegną się cztery pytania ekranu — dziś odpowiada na pierwsze.
Dzięki temu 1.7 nie powstanie jako czwarte zadanie mixa obok trzech innych.

Dwie sytuacje, w których raport łatwo skłamie, obie przypięte testem:

- **Zero przebiegów to brak podstawy, nie trzy znaleziska.** Proces, który nigdy nie ruszył, ma wszystkie
  ścieżki nieprzejechane; wypisanie ich zamienia „nie ma danych" w „mamy trzy problemy". Raport mówi
  `basis: :no_runs` i pustą listę — ta sama zasada, na której stoi ocena assercji.
- **Job w kolejce to „jeszcze nie", nie „nigdy".** Wypisywany osobno, nie jako nieprzejechany. Bez tego
  raport kłamie przy każdym normalnym opóźnieniu.

Liczy przebiegi, nie wystąpienia — bo tylko ta liczba przy wielu klientach odróżnia ciszę od braku
ruchu. Wolumen w teście jest symulowany, ale proces nie: przebiegi idą przez kontrakt z warsztatu, a nie
przez fazy dopisane pod kryterium odbioru.

**Symulować wolumen, nie proces.** Plan produktowy chce falsyfikacji na 50 zasymulowanych przebiegach i ma
rację co do taniości, ale nie nazywa wady: proces, który sam zaprojektuję, wyprodukuje dokładnie ten sygnał,
który w niego wpiszę. Te 50 przebiegów idzie więc przez istniejący kontrakt z warsztatu, nie przez fazy,
które sam dopiszę. Kształt pochodzi wtedy z sesji z klientem, a losowe są tylko dane.

**1.5 Ocena assercji `trace`. ✅ zrobione 5 sierpnia — trzy werdykty z czterech.** Per instancja.
*Odbiór:* spełnione. `PNS.Trace`, `test/trace_test.exs`, i widać to na prawdziwych danych:
`mix pns.trace` na pięciu przebiegach mówi „spełniona 5/5, 3 przez eventually, 2 przez or_else". Dwie
zablokowane firmy są spełnione, nie naruszone.

To jest pierwszy moment, w którym cokolwiek w runtime czyta `trace`. Do teraz assercja była prozą w
składni Elixira.

Trzy decyzje semantyczne, każda przypięta testem, bo każdą da się zepsuć w drugą stronę bez łamania
niczego innego:

- **Okno liczy się od pierwszego wystąpienia `from`, nie od ostatniego.** Inaczej proces uciekałby przed
  terminem w nieskończoność, emitując `from` ponownie — a przy ponownym sprawdzeniu rejestrów to nie jest
  przypadek teoretyczny.
- **`within` obowiązuje także `or_else`.** Inaczej termin jest bezużyteczny: proces zakończony poprawnie
  trzy miesiące po terminie byłby „spełniony". Do potwierdzenia przez process ownera — to jedyna
  decyzja w tym etapie, która należy do niego, nie do nas.
- **Przebieg bez `from` nie jest oceniany wcale.** Ani spełniony, ani naruszony — nie ma o czym orzekać.
  Liczenie go jako naruszenia zrobiłoby alarm z każdej niezaczętej sprawy. Symetrycznie: zero przebiegów
  to brak podstawy do orzekania, nie zielony raport.

Wyszło przy okazji: `or_else` produkowane handlerem asynchronicznym jest `pending`, dopóki job stoi w
kolejce — ta sama lekcja, co czwarty stan nakładki. Koszt jest nazwany: job zaklinowany dłużej niż okno
policzy się jako naruszenie, i to jest poprawne, bo powiadomienie faktycznie nie poszło.

**1.5b Czwarty werdykt: `:suspended`. ✅ zrobione 6 sierpnia.** `PNS.Dependency`,
`test/dependency_test.exs`. 221 testów.

`external` i `unavailable_looks_like` były w kontrakcie od pierwszego dnia i nikt ich nie czytał. Dziś
mają czytelnika: awaria zależności w oknie assercji nie jest już naruszeniem.

**Dlaczego to najdroższy fałszywy pozytyw, jaki ten produkt umie wyprodukować.** Bez tego raport mówi
klientowi, że złamał własne ustalenie, kiedy leżał czyjś serwer. Jedyny majątek tego artefaktu to bycie
wiarygodnym — jedno takie znalezisko przed księgową i raport przestaje być czytany.

**Reguła doboru zależności jest wąska i to jest istotne: liczą się te, które deklarują zdarzenia, jakie
nie przyszły.** `from` już się stało, więc to, od czego ono zależy, działało. Suma wszystkich zależności
kontraktu byłaby gorsza — przebieg dostawałby rozgrzeszenie, bo padło coś, czego nigdy nie dotknął.

**Zawieszenie zastępuje wyłącznie naruszenie.** Nigdy nie rusza `:satisfied` — przebieg zakończony poprawnie
jest zakończony poprawnie, cokolwiek wtedy leżało — ani `:pending`, bo jest jeszcze czas. Oba kierunki
przypięte testem, bo drugi jest z tych, których nikt nie pomyśli sprawdzić.

**Nadmierne zapisywanie jest groźniejsze niż niedostateczne, i to zdecydowało o API.** Zawieszenie zabiera
znalezisko z raportu, więc mechanizm zapisujący niedostępność hojnie po cichu przestałby raportować prawdziwe
problemy — awaria w kierunku, którego nikt nie zauważa, czyli odwrotnie niż cała reszta tego silnika. Dlatego
`PNS.Dependency.observe/3` zapisuje wyłącznie to, co adapter stwierdza wprost (`{:error, :unavailable}`);
`{:error, :timeout}` przechodzi bez zapisu, dopóki ktoś nie zdecyduje inaczej w adapterze.

Zapis jest owinięty, nie do zapamiętania — ten sam kształt co `PNS.Telemetry.handler_span/2`, z tego
samego powodu: reguła, do której nikt nie jest zmuszony, wygasa.

**Obserwacje, nie przedziały.** Adapter wie, że jedno wywołanie padło. Nigdy nie wie, kiedy usługa wróciła,
bo nikt mu tego nie mówi — dowiedzenie się wymaga dopytywania, czyli health-checkera, czyli innego produktu.
Nic nie jest kluczowane przebiegiem: rejestr nie leży jednej firmie, leży wszystkim naraz, i test tego
pilnuje (jedna awaria zawiesza oba przebiegi).

**TaxVision nie umie wyprodukować zawieszenia, i to jest znalezisko, nie brak fikstury.** Jego jedyna
zadeklarowana zależność — rejestry publiczne — jest konsultowana przez krawędź żądania przed pierwszą
emisją, więc okno nigdy nie otwiera się, gdy zależność jest w grze. Ten werdykt ma znaczenie dla procesów,
których następnik sięga na zewnątrz, nie tych, których poprzednik. Demonstracja jest więc na rigu, który
jest jawnie nie-domeną — i nie dopisałem `external :mail` do kontraktu klienta, choć powiadomienie
faktycznie zależy od poczty: `unavailable_looks_like` jest polskim zdaniem, które czyta klient, a
wymyślanie go za niego to dokładnie ta zmyślona wiedza o domenie, którą PNS ma wykrywać u innych.

**1.6 Wersja kontraktu jako pierwszoklasowa odpowiedź. ✅ zrobione 5 sierpnia.**
*Odbiór:* spełnione. `PNS.Deployment`, `test/deployment_test.exs`. Raport mówi, co wdrożone, od kiedy,
jakie wersje są w logu, ile zdarzeń pochodzi z innych wersji, oraz co się zmieniło — osobno zdarzenia,
osobno ścieżki.

**Najważniejsze wyszło z ostatniej części kryterium („bez ani jednego fałszywego driftu") i było prawdziwą
dziurą, nie hipotetyczną.**

`version/0` haszuje deklaracje kontraktu. Ścieżki pochodzą z `publishes:` handlerów, których w tym
haszu nie ma. Skutek: usunięcie handlera zmienia graf, nie zmieniając ani jednej wersji stemplowanej
gdziekolwiek — więc nakładka widziała krawędź zaobserwowaną i już niezadeklarowaną, sprawdzała, że wersja
kontraktu jest wciąż aktualna, i orzekała drift dla ścieżki, która była legalnie zadeklarowana, kiedy
przejechała.

Notatki §9 mówią, że skew wersji „handled by `contract_version` on the event", i podają przykład z
**usuniętym zdarzeniem** — ten działa, bo usunięcie zdarzenia bumpuje wersję. Przypadku z usuniętym
**handlerem** rekord nie rozważa. Do poprawki w rekordzie.

Rozwiązanie: wdrożenie ma dwie tożsamości. `contract_version` to umowa, `wiring_version` to kod. Refaktor
rusza jedną i nie rusza drugiej, a to jest dokładnie rozróżnienie, na którym klientowi zależy.

Kształt zapisu: jeden wiersz na odrębne obwodowanie, przy boocie. Nic per zdarzenie — koszt to jeden
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
*Odbiór:* spełnione. `PNS.Conformance.report/2` (dane) plus `Taxvision.Report.render/1` (zdania),
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
  a `month_opens_or_is_blocked` w raporcie dla księgowej oblewa kryterium. Raport składa zdanie z etykiet
  zdarzeń, czyli ze słów, które klient już zatwierdził.

  **Rozstrzygnięte 5 sierpnia: `label` do `trace` nie wchodzi.** `trace` ma już nazwę
  (`trace :month_opens_or_is_blocked do`), brakuje mu etykiety klienckiej — i to jest różnica, która decyduje.
  Etykieta zdarzenia dodaje fakt, którego nie ma nigdzie indziej: żaden silnik nie wyprowadzi „Otwarto
  miesiąc księgowy” z `accounting_month_opened`, więc nie ma z czego dryfować. Etykieta assercji
  **powtarzałaby fakt już w pełni wyrażony** przez `from`/`eventually`/`within`/`or_else` — czyli drugą
  edytowalną reprezentację jednej rzeczy. Zmień `within: {2, :day}` na `{5, :day}` i proza dalej mówi „w ciągu
  dwóch dni”, a nic tego nie łapie. To jest argument, którym ADR §2 odrzuca zewnętrzny format dokumentacji
  jako źródło, obrócony na nasz własny DSL. Zdanie składane jest wyprowadzone, więc nie może skłamać.

  Czego assercja faktycznie nie umie powiedzieć, to dlaczego ją ustalono — „bo urząd liczy termin od
  otwarcia" `[WF 00:34:40]`. Tego w mechanice nie ma, nie da się wyprowadzić i nie ma z czego dryfować. Słowo
  na to już istnieje: `source:`, dziś tylko na `rule`. Rozszerzenie kosztuje zero nowych słów, `label`
  kosztowałoby jedno. Nie dopisane — obie nasze assercje pochodzą z warsztatu i żadna nie ma zapisanego
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
obwodowaniu nie ma — i raport nazywał to driftem, poprawnie w formie i z fałszywego powodu.

**Jedna reguła, dwie konsekwencje — po granicy transakcji, nie po preferencji.** Synchronicznie: rzuca,
transakcja się cofa, w logu nie ma ani emisji, ani zdarzenia, które ją wywołało. W kolejce: łapie się tam,
gdzie każda inna awaria handlera, ląduje w `event_handlings` z komunikatem, a zdarzenie wywołujące zostaje
— bo job leci poza transakcją, świadomie, i fakt, który go wywołał, pozostaje faktem. Sprawdzenie idzie
**przed** emisją, nie po: gdyby po, graf byłby już sprzeczny z logiem, kiedy ktokolwiek się dowie.

Naruszenie nie może być stanem danych, tylko defektem kodu — i deklaracja, i emitowana nazwa są w
handlerze statyczne. Dlatego wywala się na pierwszym teście, który handler przejedzie, i to jest cała
wartość: przenosi wykrycie z produkcji do CI.

Fikstury (`OnItemReviewed`, `OnItemEscalated`) są w rigu, bo złamany kod na potrzeby testu nie ma prawa
stać w drzewie klienta — żadna domena nie powinna nosić przykładu buga. Oba deklarują `publishes: []`, więc
nie wnoszą ani jednej krawędzi: graf, `wiring_version` i raporty ścieżek zostają nietknięte. Dwie
fikstury, nie jedna, bo jedna reguła wołana z dwóch miejsc to dokładnie to, co się rozjeżdża — i nie mogą
dzielić zdarzenia, skoro synchroniczna cofa transakcję, w której stałby job.

Naruszenie zależy od payloadu, a nie jest bezwarunkowe, i to nie jest wygoda: ten sam handler emitujący nic
nie może rzucać. Bez tej kontroli sprawdzenie reagujące na dowolny return handlera przeszłoby test
pozytywny. Zweryfikowane odwrotnie — po zneutralizowaniu reguły pada cztery z ośmiu testów, czyli
dokładnie te, które o naruszeniu cokolwiek twierdzą.

Zostaje na później: tracer kompilacji (notatki §2) przesunąłby wykrycie jeszcze wcześniej, ale to
optymalizacja momentu, nie warunek poprawności.

**2.2a Wyrzucenie `:period` ze słownika typów. ✅ zrobione 6 sierpnia.** `PNS.Contract.payload_types/0`,
`test/compile_gates_test.exs`, `test/universality_gate_test.exs`. 166 testów.

**Najpierw trzeba było słownik stworzyć, a nie tylko z niego usunąć.** Sprawdzone, nie założone: żadna
walidacja typów nie istniała — dowolny atom kompilował się jako typ payloadu. Samo przepisanie
`period: :period` na `period: :id` w jedenastu miejscach byłoby więc kosmetyką odwracalną przez przypadek,
bo nic nie stałoby na drodze następnej osobie, której `:period` będzie wygodne. Słownik jest teraz zbiorem
zamkniętym, a wyjście z niego jest błędem kompilacji: `[:id, :string, :integer, :timestamp, :enum]`.

**Czego brama uniwersalności nie umie zobaczyć — i to jest wniosek o samej bramie.** Kryterium „zero nowych
słów" pyta, czy opisanie drugiej domeny wymusiło dodanie słowa. Jest konstrukcyjnie niewidoma na
słowo, które już jest, a być nie powinno. `:period` przechodził ten test dwa dni. Znalazło go liczenie:
kontrakt medyczny ma czternaście pól payloadu i nie użył go ani razu. Brama ma teraz drugą połowę — literał
z typami, przypięty tym samym mechanizmem, co słownik kluczy.

**Cena, której `PLAN.md` się bał, nie dotyczy tej połowy.** Wcześniejsza wersja tego punktu wiązała usunięcie
`:period` z walidacją typów, bo klucz przebiegu miał zmienić się z `accounting_month|c-1|2026-07` na
`|<uuid>|<uuid>`, a „odtwarzalny z samego logu" było jawną własnością projektową. To jednak dwie różne
zmiany, i pomyliłem je: wyrzucenie typu ze słownika nie rusza wartości. Sprawdzone po zmianie — klucz
nadal brzmi `accounting_month|c-1|2026-07`. Przejście na `period_id` jako uuid to osobna decyzja klienta i
ona nadal ma czekać na 2.2b.

Komunikat błędu mówi, co napisać zamiast — „jeśli nazywa rzecz, a nie kształt, to jest `:id`" — i to jest
przypięte osobnym testem. Brama, która mówi tylko „twoje słowo jest złe", jest bramą, którą się obchodzi.

Domknięte przy okazji: `:integer` był używany piętnaście razy i nie było go w udokumentowanym słowniku;
notatki §1 pokazywały w przykładzie DSL-a `:uuid` i `:decimal`, których nigdy nie było. Referencja typów
jest teraz generowana przez `mix pns.docs` z tego samego źródła, co brama — bo ręcznie pisana kopia zbioru
zamkniętego jest pierwszym miejscem, w którym pojawia się szósty typ bez dokumentacji.

**2.2b Walidacja payloadu przeciw zadeklarowanym typom. ✅ zrobione 6 sierpnia.** `PNS.Payload.validate!/4`,
`test/payload_test.exs`. 196 testów.

**Wyszło, że to nie jest jedna rzecz, a dwie — i pierwsza była fałszywą obietnicą w moduledoku.**
`PNS.Payload` twierdził, że handler synchroniczny i asynchroniczny widzą ten sam kształt. Dla kluczy tak,
dla wartości nie: `:timestamp` był `DateTime` w jednym i tekstem ISO 8601 w drugim. Dowód, że to bolało:
kod klienta serializował ręcznie w miejscu emisji (`DateTime.utc_now() |> DateTime.to_iso8601()`) — pole
zadeklarowane jako punkt w czasie celowo trzymało tekst, bo dwa kształty były gorsze niż jeden zdegradowany.
`cast/2` odtwarza teraz wartości, obejście wypadło z `api.ex`, a deklaracja znaczy to, co mówi.

Reguła zamiast listy: cast naprawia dokładnie to, co niszczy JSON. Liczby, tekst i identyfikatory
przeżywają round trip; punkt w czasie nie. Odtwarzanie to nie koercja — `:integer` przychodzący jako `"5"`
nie jest stratą, bo JSON liczby niesie, więc to wołający podaje nie to; koercja ukryłaby defekt, który
walidacja ma ujawniać.

**Kolejność była zła przy pierwszym podejściu i to jest najważniejsze znalezisko tego punktu.** Walidowałem
**po** `retain`, z uzasadnieniem „sprawdzamy to, co faktycznie wyląduje w logu". Jest odwrotnie:

- `:hash` zamienia cokolwiek w hex string, więc pole `:string` nigdy nie mogło paść, a `:integer` nigdy
  przejść — czyli sprawdzenie przestawało obowiązywać dokładnie tam, gdzie pola niosą treść wrażliwą.
- `:drop` usuwa pole, więc zadeklarowane pole byłoby trwale brakujące i każda taka emisja odrzucona.

Drugie było utajone: `:drop` nie było używane nigdzie, więc nikt nie mógł na to wpaść. Doszła fikstura
(`item_noted`, `retain: %{note: :drop}`), która jest dziś jedynym `:drop` w repo — bo pułapka nieosiągalna to
nie to samo co nieistniejąca. Typ opisuje fakt, `retain` opisuje co log z niego zachowuje, a
zrzucenie pola nie zwalnia wołającego z deklaracji.

**Surowo na wejściu, defensywnie na wyjściu.** Nic nie waliduje przy czytaniu i to jest decyzja, nie
przeoczenie: log trzyma zdarzenia zapisane pod kontraktami, które się od tego czasu zmieniły, a raport, który
nie umie przeczytać historii, jest gorszy od takiego, który czyta ją luźno. ADR §7–8 nazywa to *read
defensively*. Przypięte testem: wiersz z payloadem bez dzisiejszego pola daje się odczytać bez wyjątku.

**Jedno sprawdzenie stało się nieosiągalne z emisji** — ten sam wzorzec, co „zdarzenie w dwóch procesach".
`PNS.Instance` rzucał, gdy pola instancji zabrakło w payloadzie; brama kompilacyjna gwarantuje deklarację,
walidacja gwarantuje obecność, a walidacja leci przed liczeniem klucza. Raise zostaje, bo funkcja jest
publiczna i wołający bezpośrednio nie ma przed sobą niczego — nieosiągalne z jednej ścieżki to nie martwe,
i to jest przypięte osobnym testem, nie komentarzem.

**Trzy pola nie są odrzucane, choć mogłyby być:** nadmiarowy klucz nieopisany w kontrakcie zostaje. Jest
odrzucany tam, gdzie to ma znaczenie — handler emitujący niezadeklarowane *zdarzenie* nie dojdzie tak daleko —
a jeden zbędny klucz jest w logu widoczny, podczas gdy brakujący jest ciszą. Ten sam argument, który
zrobił z checka retencji raport, a nie bramę.

Zweryfikowane odwrotnie: po zneutralizowaniu walidacji pada siedem z piętnastu testów tego pliku.

**2.2c `period_id` jako identyfikator. ✅ zrobione 6 sierpnia — decyzja klienta podjęta.**
Migracja `20260806130000`, `Taxvision.Periods.fetch_by_id!/1`. 207 testów.

**Przeszacowałem koszt, kiedy o to pytałem, i to jest sprostowanie do mojego własnego zdania.** Mówiłem, że
„odtwarzalny z samego logu" jest własnością, którą się traci. Nie jest: własność silnika mówi, że klucz jest
**odtwarzalny** z payloadu w logu, nie że jest czytelny. Odtwarzalność jest nietknięta. Traci się
interpretowalność gołym okiem — i to w dwóch miejscach, oba drobne: `mix pns.trace --instances` (widok
debugowy) i ktokolwiek czytający log bez joina. Raport dowodowy nie wypisuje kluczy przebiegu w ogóle —
sprawdzone renderem po zmianie, zero uuidów — bo „które przebiegi milczą" to pytanie o konkretną firmę.

**Nazwy na krawędziach, identyfikatory w środku**, i krawędzi jest dwie. Wejściowa: `Taxvision.Api` rozwiązuje
nazwę raz, i za tą linią nic w domenie nie widzi już stringa. Wyjściowa, której nie przewidziałem: temat
powiadomienia zawiera nazwę miesiąca, więc bez odwrotnego rozwiązania księgowa dostałaby maila „miesiąc
3f2a8c…-… zablokowany". Symetria wyszła z kodu, nie z planu.

**`boundary` natychmiast złapał dwie nowe zależności międzymodułowe** — `Notifications` i `Api` sięgające po
`Periods`. Zadeklarowane jawnie. To zakaz joinów robiący dokładnie to, po co jest: nowa zależność jest
**widoczna od razu**, a nie przychodzi jako join, który ktoś zauważy później.

**Moja pierwsza migracja była zła i pękła na dev-bazie.** Dodawała kolumnę `null: false` i przechodziła na
pustej bazie testowej. Stary string jest nazwą okresu, więc join odzyskujący identyfikator istnieje —
migracja robi teraz backfill, potem dokłada `NOT NULL`, i nic nie usuwa: wiersz, którego nie da się
zmigrować, zatrzymuje migrację. Migracja cicho kasująca dane biznesowe, żeby sobie przejść, jest gorsza od
takiej, która staje. Przy okazji jest to próba generalna dla klienta, którego tabele nie są puste.

**Najciekawsze znalezisko: przykład i funkcja decyzyjna przestały być tym samym kształtem.** `example`
opisuje komendę, jak ją wydaje człowiek — więc `period: "2026-07"`. Funkcja decyzyjna dostaje wejście
**po rozwiązaniu na krawędzi** — więc `period_id`. `given:` jest dokładnie tym, co zastępuje tę maszynerię, i
zawsze było. Identyfikator w przykładzie jest czytelny celowo (`"period-2026-07"`): `:id` znaczy
*identyfikator*, nie *uuid*, a wstawienie prawdziwego uuida do kontraktu wymieniłoby całą własność §18 —
że przykład da się przeczytać process ownerowi na głos — na spójność, której nic nie potrzebuje.

**Zmierzona cena wzrosła z dwóch zapytań na trzy** i trzecie jest tą kanonizacją. Jedno na krawędzi
(nazwa → identyfikator), po jednym na każdy moduł potrzebujący dat. Przypięte osobnym testem, że
zapytanie po nazwie jest dokładnie jedno — bo gdyby ktoś przeniósł rozwiązywanie do handlera, liczba
zostałaby trzy, a powód by się zmienił.

Drobiazg, który pokazuje utraconą czytelność w najmniejszym możliwym miejscu: posortowana lista kluczy
przebiegu przestała być chronologiczna, bo sortuje się po uuidzie. Test sortuje teraz obie strony.

**2.3 Ślad po awarii handlera synchronicznego. ✅ zrobione 6 sierpnia.** `PNS.HandlerFailure`,
`PNS.SyncHandlerError`, `test/handler_failure_test.exs`. 162 testy.

Plan mówił „zapis poza transakcją albo telemetria". Weszły oba i z różnych powodów: telemetria, bo
zbieranie błędów należy do narzędzi klienta (`[:pns, :handler, :exception]` z handlerem, przebiegiem i
stacktrace'em), a trwały wiersz, bo telemetria istnieje tylko tam, gdzie ktoś skonfigurował kolektor, a
luka z ADR §13 jest o artefakcie, nie o observability.

**Kryterium ma dwie połowy, które się przeciągają, i obie są przypięte.** Awaria jest zapisana i cofnięcie
zostaje w mocy — zapisanie okupione osłabieniem rollbacku wymieniłoby lukę diagnostyczną na log, który
kłamie, że fakt zaszedł, choć praca się nie wykonała.

**Osobna tabela, nie status na `pns_event_handlings`, i nie z wygody.** Każdy inny wiersz w logu mówi o czymś,
co zaszło; ten mówi o czymś próbowanym, co nie zaszło — więc nie ma na co wskazać, bo zdarzenie zostało
cofnięte i nigdy nie istniało. Klucza obcego nie ma i to jest decyzja, nie przeoczenie. Tym, co przeżywa
rollback, jest `correlation_id`, generowany przed otwarciem transakcji, i to on jest uchwytem.

**Gdzie zapis, bo to była cała trudność.** Nie tam, gdzie awaria jest zauważona — ten kod siedzi w skazanej
transakcji, więc jego insert cofnąłby się razem z nią. Zapis idzie w **najbardziej zewnętrznej ramce
emittera, tej, która transakcję otwarła, **po rollbacku, kiedy połączenie jest znowu wolne. Żadnego
drugiego połączenia, żadnego `Task`, żadnego pisania obok sandboxa w testach — a to ostatnie miało już
kiedyś cenę przy `PNS.Deployment.record!`.

**Wrapper jest transportem i nie wychodzi do wołającego.** Ramka, która wie *który handler padł na którym
przebiegu*, jest głęboko w transakcji, która zaraz zniknie; ramka, która umie trwale zapisać, nie wie nic —
kontekst musi odbyć podróż. Ale pierwsza wersja przepuszczała `PNS.SyncHandlerError` na zewnątrz i jeden
test to złapał: wołający zamiast `ArgumentError` handlera dostawał wyjątek silnika. To byłaby zmiana
łamiąca obsługę błędów u każdego klienta, wprowadzona jako efekt uboczny mechanizmu diagnostycznego. Teraz
emitter odwija i rzuca oryginał z oryginalnym stacktrace'em — samo `reraise original, __STACKTRACE__`
wskazywałoby bibliotekę, co jest gorsze niż brak wrappera, więc stacktrace jedzie w polu.

**Podwójne zawinięcie.** Emisja handlera odpala następny handler, więc `rescue` ramki wyżej zawinęłoby już
zawinięty błąd i przypisało awarię nie temu handlerowi, plus jedno zdarzenie telemetrii na ramkę. Osobna
klauzula na `PNS.SyncHandlerError` przepuszcza go bez zmian.

**Tabela ma czytelnika od pierwszego commita**, bo inaczej jest kolejną deklaracją, której nikt nie czyta — a
etap 2 istnieje po to, żeby takie usuwać. `PNS.Conformance` odróżnia „nigdy nie próbowano" od „próbowane i
nie udaje się": „zadeklarowane, nigdy nie zaobserwowane" czyta się jako martwy albo nieprzetestowany krok, a
dla handlera, który leci i pada w każdym przebiegu, oba odczyty są fałszywe i idą do złej osoby. Ścieżka z
padającym handlerem wypada z listy nieprzejechanych i wchodzi na własną. To trzeci wariant jednego błędu:
raport nie ma prawa zamieniać *braku odpowiedzi* na *odpowiedź „nie"*.

Liczy przebiegi, nie awarie — handler ponowiony czterdzieści razy dla jednego klienta to jeden padający
przebieg. `coalesce` wymagało jawnego rzutowania, bo `instance_id` jest tekstem, a `id` uuidem, i Postgres
słusznie odmawia zamiast wybrać po cichu.

**Limit nazwany, nie obejściony:** kiedy transakcję otwarł wołający, silnik nie dostaje swojej kolejki —
wyjątek wchodzi w ich transakcję i ślad jest ich do zapisania. Trwały zapis z wnętrza czyjejś skazanej
transakcji nie jest na jednym połączeniu możliwy. Przypięte testem, żeby limit był własnością, a nie
niespodzianką.

Fikstura `OnItemFlagged` jest w `intake`, nie w `resolution`, choć tam byłaby naturalniejsza: publikuje do
`matching`, więc z `resolution` byłaby drugą krawędzią wsteczną i po cichu zepsułaby kryterium odbioru
1.3, zmieniając liczbę z jednej na dwie. Sprawdzone: `pns.check` nadal zgłasza jedną.

Zweryfikowane odwrotnie: po wyłączeniu zapisu padają trzy z dwudziestu trzech testów w tych dwóch
plikach — dokładnie te, które o śladzie cokolwiek twierdzą.

**2.4 Cztery rzeczy odpornościowe. ✅ ZAMKNIĘTE 6 sierpnia.** 180 testów.

**Kolejność dwóch handlerów synchronicznych — zrobione.** Plan mówił „zdefiniowana albo zabroniona".
Wyszło jedno i drugie, i to nie jest kompromis: zdefiniowana w rejestrze, żeby zachowanie się
odtwarzało, i zgłaszana jako ostrzeżenie w `pns.check`, bo sam determinizm nie czyni tego kształtu dobrym.

Zakaz byłby za mocny: dwa handlery piszące rozłączny stan pochodny w jednej transakcji są legalne i
niezależne od kolejności. Ale „niezależne od kolejności" było twierdzeniem, którego nikt nie sprawdził —
a kolejność brała się z tego, w jakiej kolejności moduły znalazły się w liście aplikacji, więc identyczny kod
mógł zachowywać się różnie po dwóch deployach. Teraz jest sortowana po nazwie modułu: odtwarzalna i nadal
arbitralna. Ostrzeżenie mówi wprost, że jeśli kolejność ma znaczenie, to kontrakt wyraża sekwencję przez
pisownię nazwy modułu, a poprawka należy do kontraktu — jeden handler publikuje zdarzenie, na które
subskrybuje drugi, i wtedy sekwencja jest ścieżką, którą widzi nakładka.

Nie jest to brama kompilacyjna, bo oba handlery są w innych modułach i żaden nie wie o drugim w czasie
kompilacji. To własność całoprogramowa i leży tam, gdzie reszta takich — ale w `PNS.Check`, nie w zadaniu
mixa, tą samą drogą co `backward_edges/0`.

Żadne zdarzenie nie miało takiego kształtu, więc check byłby niemy, a check, którego jedynym dowodem jest
własna cisza, nie jest przetestowany. Do rigu weszła jedna para (`OnItemMeasuredFirst`/`Second`, oba
`publishes: []`, więc zero krawędzi), nazwana tak, że kolejność alfabetyczna i deklaracyjna się nie
zgadzają — czyli dokładnie pułapka, o której mówi ostrzeżenie. `mix check` pokazuje od teraz cztery
ostrzeżenia, a czwarte jest kryterium odbioru tego punktu, tak samo jak krawędź wsteczna jest kryterium 1.3.

**Łagodne odrzucenie joba po znikniętym handlerze — zrobione.** Było: `to_existing_atom` rzuca, job pada,
Oban ponawia dwa razy identycznie co trzy sekundy i kończy jako `discarded` z komunikatem, który nie mówi
dlaczego. Deterministyczna awaria ponawiana to szum, a szum w kolejce jest miejscem, w którym chowają się
awarie prawdziwe.

Teraz `{:cancel, reason}` — bez ponawiania — plus wiersz w `pns_event_handlings` ze statusem `cancelled`.
**Zapis nie jest księgowością, a odpowiedzią na pytanie z 1.6:** job zakolejkowany dla handlera, którego nie
ma, jest ścieżką zadeklarowaną przez obwodowanie, które nie jest już wdrożone — dokładnie tym faktem,
który `wiring_version` istnieje, żeby odróżnić od driftu. Cicho porzucony, log twierdziłby, że pracy nigdy nie
zakolejkowano, co jest innym i fałszywym zdaniem.

Trzy drogi do „handlera nie ma" i wszystkie znaczą dla joba to samo: atomu nigdy nie było (zmiana nazwy przy
jobach w kolejce), moduł jest, ale nie da się go wczytać, albo moduł jest i przestał być handlerem — to
ostatnie robi się, usuwając `use PNS.Handler` i zostawiając plik. Rozwiązywanie po samej nazwie wywaliłoby się
linijkę później, na wywołaniu funkcji, której nie ma.

Kontrola w tym teście padła przy pierwszym uruchomieniu, bo wybrałem jako „działający handler" fiksturę z 2.1,
która celowo emituje coś niezadeklarowanego. To jest koszt trzymania złamanego kodu w rigu i wart
zapisania: fikstury z różnych etapów potrafią się na siebie nałożyć.

**Ochrona przed cyklem — ✅ zrobione 6 sierpnia.** `test/cycle_test.exs`, 173 testy.

**Reguła jest węższa, niż się wydaje, i trzy tańsze były błędne.** Cyklem jest to samo zdarzenie dwa razy
na jednej ścieżce od emisji korzeniowej — nic więcej.

- **Limit głębokości** wymaga liczby, której nikt nie uzasadni, a ta liczba decyduje, czy prawdziwy kontrakt
  działa. Zadeklarowany graf daje ograniczenie darmo: ścieżka bez powtórzenia nie może być dłuższa niż liczba
  zdarzeń.
- **„To samo zdarzenie już było w tej transakcji"** daje fałszywy alarm na rombie: komenda emituje A, handlery
  A emitują B i C, oba publikują D. Dwa D, żadnego cyklu, bo żadne nie jest przodkiem drugiego. Przypięte
  testem — dwie pozycje w jednej komendzie dają dwa `item_paired` i dwa `case_closed`.
- **Statyczne sprawdzenie na grafie nie umie tego zrobić**, bo krawędź wsteczna nie jest cyklem. Rig ma
  jedną celowo i jest ona kryterium odbioru 1.3, więc zakaz krawędzi wstecznych zakazałby kształtu, który
  opisał warsztat.

**Łańcuch jedzie przez kolejkę i to nie jest kompletność na wyrost.** Pętla przez joby nie wyczerpuje stosu —
leci wiecznie, wolniej, a każdy skok wygląda jak zwykła praca, co czyni ją groźniejszą z dwóch. Złapanie
cyklu tylko na ścieżce synchronicznej przenosi awarię, nie usuwa jej. Łańcuch jest listą stringów, nie
atomów, bo przechodzi do argumentów joba jako JSON, a konwersja z powrotem kazałaby tabeli atomów ręczyć za
nazwę, która mogła zostać usunięta od czasu zakolejkowania.

**Mój komunikat błędu radził coś nieprawdziwego** i złapał to test asynchroniczny: pierwsza wersja
proponowała „zrób handler asynchronicznym, żeby powtórzenie stało się nowym przebiegiem". Nie pomaga —
łańcuch jedzie z jobem, więc pętla tylko zwalnia. Komunikat mówi teraz o tym wprost.

**Wyszło przy okazji, i było prawdziwym defektem 2.3:** wiersz obsługi w jobie zapisywał `"ok"`, a emisja
padała pod nim. Handlowanie i emitowanie siedzą teraz w jednej klauzuli `try`, bo wszystko, co może paść
przy działaniu na wyniku handlera — niezadeklarowana emisja, cykl, cofnięta transakcja — należy po tej samej
stronie zapisu.

**Drugi defekt, ta sama klasa co przy 1.2:** `graph_test` porównywał globalną listę krawędzi
asynchronicznych z oczekiwaniem jednego kontraktu, dwie linie pod komentarzem o ukrytym założeniu „jest tylko
jeden". Pękł, kiedy fikstura w innym kontrakcie zadeklarowała pierwszy handler asynchroniczny. Zawężone.

Zweryfikowane odwrotnie: po wyłączeniu bramy pada cztery z siedmiu testów, a suite trwa 32 sekundy
zamiast 0,1 — czyli widać dokładnie ten tryb awarii, o który tu chodzi.

**Kanoniczny hash — ✅ zrobione 6 sierpnia, wyciągnięte przed 2.2.** `PNS.Digest`, `test/digest_test.exs`.
Powód wyciągnięcia: 1.6 i 1.7 właśnie oparły klasyfikację historii na `contract_version`, więc luka
przestała być hipotetyczna — zaczęła podpierać raport dowodowy.

**Groźniejszy z dwóch defektów nie był tym, który miał w planie nazwę.** Aktualizacja OTP to zdarzenie, które
ktoś zauważa. Przestawienie dwóch bloków `event` w pliku to zwykła edycja — a `term_to_binary` liczył z
listy w kolejności deklaracji, więc wersja się ruszała, mimo że ustalenia nie. Kolejność deklaracji jest teraz
nieistotna, bo kontrakt jest zbiorem deklaracji, nie ciągiem.

Rozróżnienie, na którym stoi cały moduł: kolekcje deklaracji sortujemy, wartości wewnątrz deklaracji nie.
`instance: [:company_id, :period]` i odwrotność to dwa różne ustalenia, bo klucz przebiegu to te wartości
złączone w kolejności — posortowanie zrównałoby dwa różne klucze. To samo `stages:`, bo kolejność faz
decyduje, czy krawędź jest wsteczna.

Sortowanie idzie po kanonicznej postaci całej deklaracji, nie po kluczu `name`. Dzięki temu moduł nie
musi wiedzieć, który klucz nazywa deklarację, i nie ma grupy, której trzeba go nauczyć — `example` nie ma
`name` i to przestało być przypadkiem szczególnym.

`PNS.Deployment` liczy teraz z tego samego źródła, więc obie tożsamości wdrożenia mają jedną kanoniczną
postać, a nie jedną dobrą i jedną utwardzoną. Krawędzie są tam sortowane przed haszowaniem — to jedyne
miejsce, gdzie `PNS.Digest` potrzebuje pomocy wołającego, bo kolejność listy zachowuje świadomie.

**Cena zapłacona raz, jawnie: wersja skoczyła `7c229c333c21` → `0343089e9d75`.** Czyli poprawka wykonała
dokładnie to przeklasyfikowanie, któremu zapobiega — jednorazowo i celowo. Raport powie „zdarzeń z
wcześniejszych wersji ustaleń: N, to legalna historia", co jest uczciwe. Konsekwencja dla harmonogramu:
to musiało wejść, zanim log klienta ma historię wartą zachowania, i dlatego nie czekało na 2.2.

Fikstury (`Ordered`, `Reordered`, `Changed`) stoją w pliku `.exs`, bo rejestr skanuje listę modułów
aplikacji, a moduły z `.exs` w niej nie są — więc są niewidoczne dla grafu, tabeli wdrożeń i każdego raportu
ścieżek. Sprawdzone: `pns.check` pokazuje nadal 18 informacji i trzy kontrakty w rejestrze. Kontrakt, który
istnieje tylko po to, żeby go zahaszować, nie ma prawa wyjść w raporcie klienta jako proces bez przebiegów.

**2.5 Telemetria. ✅ zrobione 6 sierpnia — ETAP 2 ZAMKNIĘTY.** `PNS.Telemetry`, `test/telemetry_test.exs`.
206 testów.

**Dwie rodziny zdarzeń, i to, że tylko dwie, jest treścią tego punktu.** Kryterium doboru: emitujemy
wyłącznie to, czego żadne inne narzędzie w stosie nie widzi.

| Zdarzenie | Dlaczego my, a nie ktoś inny |
| --- | --- |
| `[:pns, :handler, :start/:stop/:exception]` | handlera synchronicznego nie widzi nikt — Oban zna *job*, nie handlera w środku |
| `[:pns, :contract, :violation]` | nikt inny nie wie, co klient uzgodnił; to jedyny sygnał „kod przestał zgadzać się z ustaleniami" na żywo |

Świadomie nie emitujemy: czasów zapytań (to Ecto), cyklu życia joba (to Oban), ani niczego, na co
odpowiada raport — bo to byłaby druga, przybliżona kopia własnego produktu.

**Licznik wyemitowanych zdarzeń napisałem i wyrzuciłem, i to jest uczciwsze niż go nie rozważyć.** Log ma tę
liczbę dokładnie, a metrykę dałoby się emitować tylko z wnętrza transakcji — czyli awaria handlera
synchronicznego cofałaby fakt, a licznik by go zachował. Liczba fałszywa dokładnie wtedy, gdy coś jest
zepsute, jest gorsza niż brak liczby. Do tego łamała regułę, którą sam zapisałem dwa akapity wyżej.

**Poprawiłem swój własny szew z 2.3.** Tamto zdarzenie wymyśliło własny kształt (`duration_us`, ręczne
`kind`/`reason`), bo rozwiązywałem problem diagnostyczny i nie zapytałem, co będzie musiał obejść integrator.
Teraz to `:telemetry.span/3` — `start`/`stop`/`exception`, `duration` w jednostkach natywnych, czyli kształt,
który Ecto, Phoenix i Oban już emitują. Pakiet emitujący telemetrię *prawie* konwencjonalną kosztuje każdego
integratora osobny przypadek.

**Reguła o metadanych jest regułą retencji.** Telemetria to trzecia droga na zewnątrz, po logu i
argumentach joba. Te dwie `retain` zamknął; metryka niosąca wartość payloadu otworzyłaby dokładnie tę dziurę
z powrotem. Metadane niosą nazwy i klucz przebiegu — nazwy są deklaracjami, a klucz jest w logu z założenia
i odtwarzalny z niego samego, więc oba są już tak publiczne jak log. Wartości payloadu nie są i nie pojawiają
się tam nigdy.

**`telemetry` weszło jako zależność bezpośrednia.** Było spełnione przechodnio przez Ecto i Obana — a pakiet,
którego zależność jest zaspokojona tylko dlatego, że sąsiad jej potrzebuje, pęka, kiedy sąsiad wychodzi.

**Katalog zdarzeń jest przypięty literałem** (`PNS.Telemetry.events/0`), bo nazwa zdarzenia telemetrii jest
tak samo publiczna jak nazwa funkcji: po cichej zmianie ten, kto się podłączył, przestaje cokolwiek dostawać i
dowiaduje się, gdy wykres pada na zero.

**Mój test retencji był pozorny i złapałem to przed commitem.** `item_noted` — jedyne pole na `retain: :drop`
w repo — nie miało handlera, więc nie było span-a i `refute_received` przechodziło, nie dostając niczego.
Doszedł handler, a test najpierw stwierdza, że span był, i dopiero potem czego w nim nie ma.

## Dług po stronie TaxVision

Jedna rzecz, która nie należy do silnika i nie miała dotąd swojego miejsca — komenda
`RetriggerVerification` z warsztatu została w kontrakcie pominięta. Do dołożenia razem z pętlą ponowienia,
przy prawdziwym materiale, nie przy moich założeniach o KSeF. Zapisane tutaj, bo README przestało być
dziennikiem i to był jedyny punkt roboczy, który mieszkał wyłącznie tam.

**✅ Zamknięte 22 września**, i połowicznie: `command :retrigger_verification` jest w kontrakcie,
z `source:` wskazującym `02-event-storming.md` §3.1. Sama pętla ponowienia — handler, który po tej
komendzie faktycznie przejedzie weryfikację jeszcze raz — nie istnieje, bo integracji rejestrowej
nadal nie ma. Deklaracja wyprzedza implementację świadomie: to jest wejście do procesu i ktoś musi
mieć uprawnienie, żeby je wywołać, niezależnie od tego, co się za nim dzieje.

## Etap 3 — pakiet jako pakiet

Wydzielenie do `packages/pns_core` z path dep, żeby granicę wymuszał system budowania, nie tylko `boundary`.
✅ zrobione, razem z migracjami w stylu Obana i osobną suitą — patrz dopiski 20–21 sierpnia wyżej.

Trzy skille: dodaj zdarzenie, napisz handler, zmień kontrakt — ten trzeci jest najważniejszy, bo jako
jedyny wymaga zrobienia czegoś przed napisaniem kodu. ✅ `zmień kontrakt` zrobiony 21 sierpnia
(`.claude/skills/change-contract/`) — tabela klasyfikacji delty sprawdzona przeciw źródłu: co refuduje
kompilator, co widzi `PNS.Deployment.diff/2` (tylko `events_added/removed`, `paths_added/removed` —
i nic więcej), i co jest cichą zmianą kontraktu bez żadnego wsparcia diff-owego (`retain`, `identity`,
`instance`, typ pola, parametry `trace`). Znalezisko warte zapisania osobno, nie tylko w skillu:
**`PNS.Trace.evaluate/3` nie ma wersjonowanej historii assercji** — zmiana `within`/`from`/`eventually`/
`or_else` na już zadeklarowanym `trace` reinterpretuje wszystkie historyczne przebiegi w chwili
wdrożenia, bez żadnego znaku w logu czy w tabeli wdrożeń, że werdykt liczył się pod inną obietnicą.
Nic tego dziś nie chroni; raport rozciągnięty na taką zmianę trzeba ręcznie ograniczyć `since:`.
**✅ `dodaj zdarzenie` i `napisz handler` zrobione 21 sierpnia**, równolegle, każdy w osobnym
subagencie (`.claude/skills/add-event/`, `.claude/skills/write-handler/`) — `module-boundary-check`
nie odsyła już do nieistniejących skilli, patrz jego krok 5. Znalezisko z `napisz handler`, warte
zapisania osobno: handler odczytuje `meta.event` na żywo ze skompilowanych metadanych modułu w
chwili wykonania joba, nie w chwili zakolejkowania — job zakolejkowany przed zmianą nazwy
zdarzenia, wykonany po tym, jak handler już wskazuje na nowe zdarzenie, castuje stary payload pod
nowy schemat po cichu (`lib/pns/job.ex:63`). Ten sam wzorzec co znalezisko z `zmień kontrakt` o
zmianie nazwy — teraz opisany z drugiej strony, od handlera.

**✅ CI zrobione 21 sierpnia** (`.github/workflows/ci.yml`) — jedno wywołanie `docker compose up -d
--wait` (ten sam plik co lokalnie, nie druga definicja Postgresa do rozjechania się z pierwszą), dwa
`mix deps.get` (host i `packages/pns_core` osobno — silnik jest zależnością `path`, ale
`package_test/1` woła `mix test` w nim jako osobny proces Mixa, z własnym `deps/`,
git-ignorowanym), potem `mix check`. Sprawdzone, nie założone: `mix ecto.setup` z dokumentowanej
komendy lokalnej nie jest potrzebne do przejścia bramy — usunięta lokalna baza `dev`, `mix check`
przeszedł mimo to (brama chodzi pod `MIX_ENV=test`, a bazy testowe stawia własny alias `test:`, i
hosta, i silnika). Cały workflow przejechany lokalnie od czystego stanu — usunięte `deps/`,
`_build/` obu projektów, świeże `mix deps.get` w obu, `mix check` zielony — bo `act` nie jest
zainstalowany i nie instalowałem go bez pytania.

**Czwarty skill, pierwszy dla człowieka. ✅ zrobiony 21 sierpnia** (`.claude/skills/review-pr/`) —
jak recenzować wygenerowany PR i czego nie sprawdzać, bo już pilnuje to check: kompletna lista
refuzacji kompilatora i błędów `mix pns.check` (część 1), obok listy, gdzie uwaga recenzenta
faktycznie się opłaca — ostrzeżenia/informacje `mix pns.check` wymagające osądu, `rule`/`example`
wyglądające na wymyślone, cicha edycja `identity`/`instance`/`retain`/`trace` na już zadeklarowanym
kontrakcie (odsyła do tabeli `zmień kontrakt`, nie duplikuje jej), brak twierdzenia „zweryfikowane
odwrotnie" przy poprawce błędu, polski tekst poza wąską dozwoloną powierzchnią, rozmiar diffu
niezgodny z zadeklarowanym zakresem. Notatki §8 wymieniają osiem skilli i wszystkie są dla agenta,
który pisze — a bramą jest recenzent, i dopiero teraz ma coś napisanego dla siebie.

**Etap 3 zamknięty w całości: 4/4 skille, migracje, osobna suita, CI.**

## Etap 4 — jeden ekran — nieaktualne w tym brzmieniu, patrz dopiski (10) i (11) z 23 sierpnia

Cztery pytania jako lista, nie graf. Sprawdzone: 11 zdarzeń dało 3 krawędzie i diagram nie powiedział nic,
czego nie mówiła posortowana lista. Bez alertów, bez stanu na żywo, bez czegokolwiek o konkretnej firmie.

**Zablokowane do rozstrzygnięcia:** notatki §9 mówią *„live, not a report … monitors eventually want alerts"*,
co jest w napięciu z zawężeniem zakresu. Etapy 1–3 są od tego niezależne.

Dwa zdania powyżej są już rozstrzygnięte i zostają tu jako zapis tego, co etap 4 obiecywał:

- „Jeden ekran" — są trzy, `/contract`, `/accounts` i `/graph`, nazwane rodzeństwem, żeby żaden nie
  czytał się jako kanoniczny. Dopisek (10) zapisał, dlaczego to nie jest rozrost zakresu, dopisek
  (11) zbudował trzeci.
- „Lista, nie graf" — werdykt z 11 zdarzeń dotyczył grafu globalnego i nadal stoi: osobnego
  renderera grafu globalnego nie ma. Zawężony do jednego procesu diagram mówi to, czego lista nie
  mówi — stopnie, zakończenia, okna `trace` — i to jest powód, dla którego wrócił.
- „Zablokowane do rozstrzygnięcia" — rozstrzygnięte 6 sierpnia i to rozstrzygnięcie trzyma się w
  kodzie. Ekran nie jest na żywo: żaden z trzech nie subskrybuje niczego i nie odświeża się sam,
  każdy renderuje raz na mount. Alertów nie ma i nie wchodzą.

## Etap 5 — dowód, który wie, pod jaką obietnicą się liczył

Zaplanowane 22 września, nic z tego nie zbudowane. Etap składa się z pozycji, które przeszły przez
cztery filtry: dotykają `packages/pns_core`, nie odpowiadają na pytanie o konkretną firmę, mieszczą
się w diffie do przeczytania z uwagą i nie czekają na decyzję, której nikt jeszcze nie podjął.

Relacja do dopisku (12): etap 5 bierze z tamtej listy pozycje 1, 2, 3, 6, 7 i 10, a z tego, co było
otwarte wcześniej — agregat `deadline` z 6 sierpnia i znalezisko o wersjonowaniu assercji z
21 sierpnia. Reszta trzynastu pozycji zostaje poza etapem i powód jest przy każdej niżej. Kiedy
etap 5 i dopisek (12) zaczną mówić co innego, nowszy jest etap 5 — dopisek jest zapisem przeglądu,
etap jest stanem.

### Prawda o dowodzie

Idzie pierwsze, bo jako jedyne dotyka twierdzenia, na którym stoi produkt.

**5.1 `pns_deployments` dostaje mapę `deklaracja → digest`.** `PNS.Trace.evaluate/3` czyta dziś
`contract.traces()`, czyli deklarację z dzisiaj, i stosuje ją do każdego historycznego przebiegu.
Zmiana `within`, `from`, `eventually` albo `or_else` przeklasyfikowuje więc całą historię w chwili
wdrożenia, bez znaku w logu i bez znaku w tabeli wdrożeń. Nazwane 21 sierpnia przy skillu
`change-contract`, z adnotacją „nic tego dziś nie chroni".

Oparcie tego na `contract_version` z eventu jest odruchem i jest błędne: wersja rusza się przy
każdej zmianie kontraktu, więc oznaczenie każdego przebiegu, który przeżył jakikolwiek deploy,
oznaczyłoby prawie wszystko i zamieniło raport w szum. Potrzebna jest granulacja deklaracji, nie
kontraktu — a obie potrzebne części już istnieją i nigdy się nie spotkały. `PNS.Digest` kanonizuje
pojedynczą deklarację, bo 6 sierpnia sortowanie poszło po kanonicznej postaci całej deklaracji, a
nie po kluczu `name`. `pns_deployments` trzyma per wdrożenie `events`, `edges` i `first_seen_at`.

Migracja jako `PNS.Migrations` v02 — pierwsze użycie znacznika wersji, który powstał 21 sierpnia
„zanim był potrzebny". `record!/1` liczy mapę z `PNS.Digest`, `diff/2` zyskuje kategorię zmiany
cichej.

Jedna zmiana zamyka całą klasę wymienioną w tabeli `change-contract`, nie jedną pozycję: `retain`,
`identity`, `instance`, typ pola i parametry `trace` przestają być zmianami bez wsparcia
diff-owego. `PNS.Deployment.diff/2` widzi dziś wyłącznie `events_added/removed` i
`paths_added/removed`.

*Odbiór:* zmiana `within` na już zadeklarowanym `trace` i redeploy — `diff/2` pokazuje tę assercję
jako zmienioną, z datą. Zweryfikowane odwrotnie: po zneutralizowaniu porównania padają dokładnie te
testy, które o zmianie cokolwiek twierdzą.

**5.2 Raport odróżnia werdykt liczony pod inną obietnicą.** Na 5.1. Jeżeli digest assercji zmienił
się wewnątrz okresu raportu, przebiegi sprzed zmiany nie wchodzą do `satisfied` ani `violated`,
tylko na własną linię. Ten sam ruch, który silnik wykonał już dwa razy — stan `:historical` w
nakładce i rozdzielenie „próbowane i nie udaje się" od „nigdy nie próbowano" — i ta sama reguła:
raport nie ma prawa zamieniać braku odpowiedzi na odpowiedź „nie".

*Odbiór:* raport rozciągnięty na zmianę assercji nie wymaga już ręcznego ograniczenia `since:`,
tylko sam mówi, gdzie przebiega granica.

**5.3 Raport podaje wersję silnika, a wersja zaczyna cokolwiek znaczyć.** Pozycja 10 z dopisku (12):
jedna linia obok `Version #{contract_version}` w `PNS.Report`. Sama w sobie jest ozdobą, więc idzie
z warunkiem: `CHANGELOG.md` w `packages/pns_core` i reguła, że zmiana wpływająca na werdykt podnosi
wersję. Dziś pakiet stoi na `0.1.0`, a kilka korekt zmieniło już, co liczy się jako drift — zero
przebiegów, praca w kolejce, „nigdy nie próbowano" kontra „próbowano i padło" — i nic tego nie
odnotowuje. Przy dwóch klientach na dwóch wersjach silnika to samo pytanie dostaje dwie odpowiedzi,
a raport jest dowodem dla audytora.

### Deklaracja, której nikt nie czyta

**5.4 Agregat `deadline` w `PNS.Conformance.report/2`.** „N z M przebiegów przekroczyło uzgodniony
czas trwania", retrospektywnie, bez monitora i bez alertu. Kształt ustalony 6 sierpnia i od tamtej
pory niezmieniony, więc nie ma tu żadnej decyzji do podjęcia — jest robota, która nie została
wykonana. Sprawdzone 22 września: `deadline` czyta dziś wyłącznie filtr `unverified` w
`PNS.Conformance` i renderer, który go wypisuje.

Powstaje z istniejących części: to ten sam kształt, który `PNS.Trace` liczy dla `violated`, tylko
licząc od pierwszego zdarzenia instancji, nie od zdarzenia źródłowego jednej assercji.

Idzie po 5.1, nie przed. Agregat `deadline` jest kolejnym werdyktem, a 5.1 decyduje, czy werdykt
wie, pod jaką obietnicą się liczył.

*Odbiór:* etap 2 istniał po to, żeby usuwać deklaracje bez czytelnika. Po 5.4 nie zostaje ani jedna.

### `command` jako deklaracja

Największa dziura w samym DSL-u i jedyna pozycja z przeglądu EHOS-a, która jest robotą dla
biblioteki, a nie dla platformy: kontrakt twierdzi, że opisuje proces, a wejścia do procesu istnieją
wyłącznie jako klucz w `example`.

**5.5 Pół dnia na falsyfikację, nie na implementację.** Czy `command` da się podnieść z klucza w
`example` do deklaracji, nie rozwalając czterech istniejących kontraktów. Materiału jest mniej, niż
wygląda, i trzeba to wiedzieć przed wyciągnięciem wniosku, że `D-15` się broni: cztery kontrakty i
29 eventów owszem, ale commandy są dwa (`:open_month`, `:close_settlement`) i oba siedzą w dwóch
kontraktach. `clinical_visit` i `payer_settlement` nie mają ani jednego `example`, więc ani jednego
commanda — eksperyment stoi realnie na połowie materiału.

*Odbiór:* wynik negatywny jest wynikiem. Jeśli nie wyjdzie, `D-15` jest błędne i lepiej wiedzieć to
przed rozmową z founderem niż po.

**5.6 `command` i `owner` na procesie, jednym commitem.** Tylko jeśli 5.5 wyszło. Jeden commit nie z
wygody: obie zmiany ruszają `contract_version` wszystkich czterech kontraktów, a to jest
jednorazowa przeklasyfikacja historii, którą silnik zapłacił już raz jawnie 6 sierpnia
(`7c229c333c21` → `0343089e9d75`). Dwa osobne commity to dwa skoki zamiast jednego.

**Kolizja klucza, której dopisek (12) nie nazwał, i jest to decyzja do podjęcia przed kodem.**
`owner:` istnieje dziś na evencie, wskazuje moduł, a `pns.check` weryfikuje, że ten moduł istnieje.
`owner` na procesie ma być rolą, czyli stringiem. Ten sam klucz, dwa typy, jeden check — albo osobna
nazwa, albo jawne rozdzielenie w `schema/0`. Cicha decyzja w trakcie pisania kodu jest tu najgorszym
możliwym wyjściem, bo `pns.check` przestanie sprawdzać jedno albo drugie, nie mówiąc o tym.

Trzeci konsument deklaracji, poza capability i klasyfikacją odpowiedzialności, to klient generowany
dla aplikacji (`D-12`). Sam klient jest robotą EHOS-a, ale wychodzi z kontraktu, więc deklaracja
musi nieść tyle, żeby dało się go wygenerować.

### Pakiet daje się skonsumować

**5.7 Metadane Hex w obu `mix.exs`.** Etap 3 nazywa się „pakiet jako pakiet" i jest zamknięty, a
pakietu nie da się opublikować: ani `pns_core`, ani `pns_web` nie mają `package/0`, `description`,
`licenses` ani `docs`, nie ma też `README.md` w samym pakiecie. Drobne, ale to jedyna rzecz stojąca
między zamknięciem etapu 3 a prawdą.

**5.8 Zgodność wychodzi jako dane, nie tylko jako tekst.** Pozycja 6 z dopisku (12), ale powód jest
inny niż tam zapisany: biblioteka, której jedynym wyjściem jest angielski tekst i zadanie mixa, ma
dokładnie jednego konsumenta. Że skorzysta z tego EHOS, jest skutkiem ubocznym.

`PNS.Conformance.report/2` zwraca mapę z atomami i modułami, więc przez granicę potrzeba
serializacji i endpointu. Szew montowalny w cudzym routerze już istnieje i jest sprawdzony
(`pns_dashboard/2`), więc `pns_api/2` jest tą samą konstrukcją, a autoryzację niesie
`PNS.Web.Authentication` z resolverem.

**5.9 AsyncAPI z kontraktu, z digestem.** Połowa pozycji 7, ta która jest materiałem silnika:
`schema/0`, `events/0`, typy payloadu i `PNS.Digest` już to unoszą. Drugiej połowy — OpenAPI z
routera — etap 5 nie obejmuje, bo `D-01` mówi wprost, że kontrakt nie opisuje odczytów, a router
jest własnością hosta.

### Czego etap 5 nie obejmuje i dlaczego

| Co | Powód |
| --- | --- |
| Monitor `cadence` | Odrzucony 6 sierpnia argumentem o mianowniku i nic się w kodzie od tego czasu nie zmieniło. Wraca dopiero, jeśli mianownik przyjdzie spoza silnika — wtedy jako nowa decyzja z datą, patrz pozycja 8 w dopisku (12) |
| Reguły organizacji, pozycja 11 | Kształt otwarty: deklaracja, check czy generowana dokładka. To jest decyzja, nie robota. Kiedy zapadnie, naturalnym domem jest `PNS.Check` — własność całoprogramowa, ta sama droga co `backward_edges/0` — a połowa mechanizmu istnieje już jako `retain` podniesiony o poziom |
| Generowany test odmowy per command | Silnik nie generuje dziś kodu w ogóle. Wygląda na dodatek do 5.6, a jest osobnym projektem |
| Bramka „command poza namespace'em swojej aplikacji" | Wymaga wejścia, którego silnik nie ma: co jest aplikacją. `boundary` to wie, PNS nie |
| Certyfikacja, pozycja 13 | Pierwszym krokiem jest godzina rozmowy z kimś, kto certyfikuje zawodowo, nie linia kodu |
| Egzekwowanie własności tabel, pozycja 4 | To `lib/taxvision/`, czyli dane testowe, nie biblioteka. Callback już chodzi; dokończenie jest robotą klienta |
| Identyfikatory korelacji przez most, z `D-03` | Nie da się zbudować, dopóki mostu nie ma. Zostaje zapisane przy pozycji 12 z klauzulą „od pierwszego commita", żeby nie przyszło jako retrofit |
| `mix pns.new` | Bez zmian: dopiero przy drugim kliencie |

### Kolejność w etapie 5

```
5.1 → 5.2 → 5.3       fundament dowodu, trzy małe PR-y
      ↓
5.4                   agregat deadline, na 5.1
5.5                   eksperyment, równolegle, pół dnia
      ↓
5.6                   tylko jeśli 5.5 wyszło, jeden commit z owner
5.7                   niezależne, godzina
5.8 → 5.9             niezależne od reszty
```

5.1 jest jedyną pozycją z migracją i jedyną, która coś przesądza na przyszłość; reszta jest
odwracalna. 5.5 warto puścić równolegle od razu, bo wynik negatywny zmienia kolejność wszystkiego,
co po nim.

Jedna rzecz jest do rozstrzygnięcia, zanim 5.6 dostanie choć linię kodu: kolizja klucza `owner`.
Reszta etapu ma kształt ustalony.

## Rekord: gdzie jest i czego nie wolno z nim robić

**Pakiet projektowy jest tutaj, w [`docs/adr/`](docs/adr/).** Przeniesiony 6 sierpnia z repo
kontekstu i przerobiony z rekordu decyzji na założenia początkowe: nikt ich tutaj nie akceptuje, bo
decyzja, żeby tę ideę sprawdzić, już padła. Aparat, który do rekordu należał — kto recenzował, kto
zaakceptował, zakres komercyjny — został tam.

**Do `~/Projects/ai/empowered-house-context` nie piszemy. Nigdy.** Ani commita, ani gałęzi, ani poprawki w
pliku. Reguła jest z 6 sierpnia i ma powód: pakiet żył w obu repozytoriach naraz, poprawki jechały na gałąź
tam, podczas gdy autorytatywne pliki były już tutaj, i przez pół dnia istniały dwie kopie tej samej
treści — dokładnie ten dryf, który ten produkt wykrywa zawodowo. Czytać stamtąd wolno, jeśli ktoś o to
poprosi. Pisać — nie. Zapisane też w `CLAUDE.md`.

**Poprawki z etapów 1.1–1.7 są rozliczone i są w `docs/adr/`.** Dziewięć rzeczy, w tym trzy, w których kod
obalił rekord: bullet falsyfikacyjny mówiący, że `trace` i `deadline` nie mają czytelnika (dziś `trace` ma,
`deadline` nadal nie); zakład declared-vs-observed, którego oba wymienione zabezpieczenia okazały się
niewystarczające; i skew wersji, który nie obejmował usuniętego handlera. Historia jest w `git log`, nie tutaj
— `PLAN.md` trzyma stan, nie archiwum.

Została jedna rzecz, którą rekord mówi, a kod jeszcze nie — i jedna, którą rekord mówi, a kod już nie
będzie, rozstrzygnięte, nie zaniedbane:

- **§9 „navigation is per-process, never global” — połowa zrobiona 23 sierpnia.** Widok
  zadeklarowany jest per proces: `PNS.Graph.declared_to_mermaid/2` bierze kontrakt i nazwę procesu,
  a ekran daje selektor. Overlay został globalny, i ekran świadomie tego nie obchodzi — powód jest
  teraz znany dokładnie i leży w silniku: `PNS.Graph.to_mermaid/2` wyprowadza zbiór węzłów z pełnego
  grafu statycznego niezależnie od tego, jakie krawędzie dostanie, więc odfiltrowanie samej listy
  krawędzi gubi krawędzie, nie gubiąc węzłów, i zostawia osierocone prostokąty zamiast zawężonego
  obrazka. Druga połowa jest więc robotą w `PNS.Graph`, nie w ekranie.
- **§9 okno „never observed" — odrzucone 6 sierpnia**, patrz „Rozstrzygnięte 6 sierpnia" wyżej i poprawka z
  datą w `docs/adr/technology-notes.md` §9. Rekord pytał, kiedy to zbudować; odpowiedź jest „nie budujemy",
  nie „jeszcze nie".

Gałąź `backup-polskie-opisy` usunięta 5 sierpnia po sprawdzeniu, że wszystkie siedem drzew jest w `main`.

## Kolejność

**Etap 1 zamknięty w całości.** 1.1–1.7 plus 1.5b. Brama uniwersalności przeszła, `trace` przestał być
dekoracją i ma dziś cztery werdykty z czterech, a różnica declared vs observed okazała się sygnałem —
50 przebiegów daje jedną linię raportu, i wszystkie pięć kształtów procesu jest obsłużonych.

**Etap 2 zamknięty w całości, 6 sierpnia.** 2.1–2.5. Obietnice kontraktu przestały być dekoracją: `publishes:`
wiąże handler, słownik typów jest zamknięty, wartości są walidowane, awaria synchroniczna zostawia ślad, cykl
jest zatrzymany na obu ścieżkach, a telemetria emituje to, czego nie widzi nikt inny. Etap 1 startował na
42 testach, kończył na 133; etap 2 kończy na 221.

**Etap 3 zamknięty 21 sierpnia** — pakiet, migracje, osobna suita, CI, cztery skille. Z jednym
zastrzeżeniem, które wyszło dopiero 22 września i jest pozycją 5.7: pakietu nadal nie da się
opublikować, bo żaden `mix.exs` nie ma `package/0`.

**Etap 4 zamknięty 23 sierpnia**, w brzmieniu z dopisków (10) i (11), nie w tym, które nosi nagłówek
sekcji: trzy ekrany, graf wśród nich, nie na żywo i bez alertów. Zostało pół pozycji, zawężenie
overlaya, i jest to dług w `PNS.Graph`, nie wymaganie etapu.

**Etap 5 zaplanowany 22 września, nic z niego nie zbudowane.** 5.1–5.9. Kręgosłupem jest 5.1:
werdykt, który wie, pod jaką obietnicą się liczył. Reszta to jedyna pozostała deklaracja bez
czytelnika (`deadline`), `command` jako siódma deklaracja — z eksperymentem falsyfikacyjnym przed
implementacją — i to, czego brakuje, żeby pakiet dało się skonsumować z zewnątrz.

### Co dalej: warsztat, nie kod

**Rehmed startuje 10 sierpnia, a największy zakład rekordu jest nietknięty** — czy prawdziwy process owner
przeczyta przykłady i je poprawi. Nic z etapu 2 tego nie ruszyło ani o milimetr; rusza to tylko warsztat.

Pytania przygotowane: [`docs/warsztat-rehmed.md`](docs/warsztat-rehmed.md). Zbudowane wokół zakładu, nie wokół
luk — twierdzenia z liczbami do poprawienia, nie pytania otwarte, bo pytanie otwarte daje prozę od
facylitatora, a poprawka jest jedyną rzeczą, która dowodzi, że ktoś przeczytał. Miary do zapisania dwie: ile
procent kontraktu przyszło z sali (przy TaxVision 40%) i ile przykładów właściciel poprawił.

### Rozstrzygnięte 6 sierpnia, w rozmowie (nie na warsztacie)

- **Gdzie renderuje się raport dowodowy. ✅ zrobione 6 sierpnia.** Renderer przeniósł się do silnika —
  `PNS.Report` (`lib/pns/report.ex`), `Taxvision.Report` usunięty. Zadanie mixa też: `mix taxvision.report` →
  `mix pns.report`, obok `pns.check`/`pns.graph`/`pns.trace`, bo to już nie jest szew klienta.
  **Treść też po angielsku** — dopytane osobno, bo lokalizacja kodu (moduledoc, nazwy) i lokalizacja
  wypisywanych zdań to dwie różne rzeczy. Etykiety z kontraktu (`label`, `from_label`, `to_label`) nie są
  tłumaczone i wychodzą tak, jak je zadeklarował klient — po polsku dla TaxVision. Skutek: raport dla
  TaxVision jest teraz angielskim szkieletem wokół polskich etykiet biznesowych. To jest odwrócenie decyzji z
  1.7 („raport czyta księgowa, więc jego zdania są po polsku”), zapisane jako poprawka z datą w
  [`docs/adr/architecture.md`](docs/adr/architecture.md) (§16–17) i w `CLAUDE.md`, nie jako cichy rewrite —
  test [`test/report_test.exs`](test/report_test.exs) i moduledoc `PNS.Report` mówią wprost, że to zmiana
  względem 1.7, nie kontynuacja.
- **Czy ekran jest „na żywo”.** Nie. Rekomendacja z notatki wyżej potwierdzona bez zmian.
- **`cadence`'s „never observed" (notatki §9) — odrzucone, nie odłożone.** Powód, z rozmowy: większość zdarzeń
  będzie odpalana ręcznie przez API z aplikacji frontendowej, która już pokazuje klientów, miesiące i
  faktury — czyli już odpowiada „który klient nie ma otwartego lipca" wprost, patrząc w swoje tabele. Policzenie
  tego w PNS wymagałoby wiedzieć, które konkretne instancje powinny istnieć, żeby wykryć, których nie ma —
  a to jest wiedza o firmach, której silnik świadomie nie ma (§1, `claims: %{}`, żadnego `company_id` w żadnej
  strukturze `PNS`). Notatki §9 same mówią „count, not a list", ale nawet licznik wymaga mianownika, którego
  log zdarzeń, z zasady, nie widzi — encja, która nie wyemitowała nic, jest niewidzialna dla systemu opartego
  wyłącznie na logu. To nie jest to samo pytanie co „ekran na żywo" (kwestia interfejsu), tylko strukturalny
  brak informacji, którego dokładanie oznaczałoby złamanie własnej reguły o firmach. Poprawka z datą w
  [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) §9, nie ciche wykreślenie — ten mechanizm był
  tam opisany jako „open, do zdecydowania przed budową raportu z §9", więc to jest odpowiedź na tamto pytanie,
  a nie jego ignorowanie. Deklaracja `cadence` w kontrakcie zostaje — nie kosztuje nic i raport ją już wypisuje
  jako fakt („Należny: co miesiąc"), tylko monitor okna nie wchodzi.
- **`deadline` procesu — zwężone, nie odrzucone.** W przeciwieństwie do `cadence`'s „never observed", to jest
  policzalne wyłącznie z logu, bez żadnej wiedzy o firmach: pyta „z przebiegów, które już się zaczęły
  (mają zdarzenie `from`), ile przekroczyło uzgodniony czas trwania" — ten sam kształt, co dziś liczy
  `PNS.Trace` dla `violated`/`satisfied`, tylko licząc od pierwszego zdarzenia instancji, nie od konkretnego
  zdarzenia źródłowego jednej assercji. Do zbudowania, jeszcze nie wykonane: dodać do
  `PNS.Conformance.report/2` agregat „N z M przebiegów przekroczyło `deadline`" — retrospektywna liczba w
  okresowym raporcie, nie żywy monitor per przebieg i nie alert. Frontend pokaże „ten miesiąc jest otwarty od
  30 dni" dla jednej firmy; tego nie pokaże — to wzorzec po całej bazie klientów, ta sama wartość, którą już
  sprzedaje `trace`.
- **Okres, którego definicja się zmieniła. ✅ zrobione 6 sierpnia.** Nie zmienia się: miesiąc księgowy to
  zawsze pierwszy–ostatni dzień kalendarzowego miesiąca, nikt nie ustawia zakresu ręcznie — sprawdzone przez
  przejrzenie każdego miejsca, które pisze do `taxvision_periods`: jest jedno, `Taxvision.Periods.ensure!/1`,
  i ono już liczy zakres z nazwy. Migracja
  [`20260806150000_period_is_a_calendar_month.exs`](priv/repo/migrations/20260806150000_period_is_a_calendar_month.exs)
  dokłada trzy `CHECK`, dokładnie tak, jak własna analiza wyżej przewidziała: „jeśli nie może się zmieniać,
  wystarczy constraint i zero kodu domenowego”. Zero kodu domenowego się potwierdziło — zmieniła się tylko
  migracja i testy weryfikujące ją odwrotnie (`test/periods_test.exs`, próba zapisania złego zakresu przez
  `insert_all/2`, z pominięciem `ensure!/1`).

### Otwarte, i nic z tego nie jest robotą z półki

**Do process ownera, jedno pytanie:**

- **Czy `within` obowiązuje także `or_else`.** Silnik zakłada, że tak. Jeśli u nich jest inaczej, raport
  pokazuje naruszenia, których nie ma. Jest w pytaniach warsztatowych, oznaczone jako nasze założenie.

**Nasze, nie pytanie do klienta:**

- **~~`unverified` nie obejmuje `trace`~~ — ✅ zamknięte 21 sierpnia.** Z dystylacji Rehmed (luka 4 w
  tabeli wyżej). Patrz „Dopisek 21 sierpnia (8)" niżej.
- **~~Kwantyfikacja wewnątrz przebiegu~~ — ✅ zamknięte 21 sierpnia.** Luka 1 z tabeli Rehmed
  wyżej. Patrz „Dopisek 21 sierpnia (5)" niżej.

**Drobne, wszystkie nasze — ✅ zamknięte 21 sierpnia, patrz „Dopisek 21 sierpnia (7)” niżej:**

- **~~Aktor systemowy zamiast `nil`~~** — zrobione: `PNS.Auth.system_actor/0`, domyślane w
  `PNS.Emitter.default_ctx/1`.
- **~~`info` dla assercji bez `within`~~** — już było zrobione, ta pozycja była nieaktualna: sprawdzone
  w `pns.check.ex` (`check_unfalsifiable_assertions/1`) i w `test/check_ambiguity_test.exs`, oba istniały
  przed tą sesją. Zdjęte z listy, nie zaimplementowane drugi raz.
- **~~Wykluczenie przestrzeni nazw z raportu, z konfiguracji silnika~~** — zrobione: `config :pns, exclude:
  [...]` w `PNS.Registry.load!/1`.
- **~~Zbiór wartości `:enum`~~** — zrobione: `{:enum, [...]}` obok gołego `:enum`, opt-in, zero zmian w
  istniejących kontraktach.

**Zawężenie `PNS.Graph` do procesu i kontraktu — połowa zrobiona 23 sierpnia**, patrz „Rekord"
wyżej. Zostało: `overlay/1` nie przyjmuje ani `:process`, ani `:contract`, a samo dołożenie filtra
nie wystarczy, bo zbiór węzłów bierze się z pełnego grafu statycznego w `to_mermaid/2`. Przestało
być wymaganiem etapu 4 — trzy ekrany stoją bez tego — i jest zwykłym długiem w silniku.

Zamknięte 6 sierpnia bez zmiany w DSL: `label` dla `trace` nie wchodzi — powód przy 1.7.

Kod zostaje w tym repo i przenosi się do repozytorium pilota, gdy ono powstanie; struktura jest już taka, że
to `git mv`.
