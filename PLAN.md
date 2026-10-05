# Plan pracy

Zakres produktu, warunki oceny i stan recenzji żyją w rekordzie:
`~/Projects/ai/empowered-house-context/decisions/009-pns-runtime-architecture.md`; założenia, które ten
prototyp waliduje, są w [`docs/adr/architecture.md`](docs/adr/architecture.md). Ten plik to lista
roboty i tylko tu jest aktualizowany stan.

## Handoff — stan na 5 października, wieczór (DD0, N1, N2 w `main`; N3, W1, W2 w PR-ach; następny jest W3)

Utrzymywany w miejscu, nie datowany dopisek: to jest stan **teraz**. Jeśli czytasz go i coś się nie
zgadza z repozytorium, rację ma repozytorium — a ten akapit jest do przepisania.

Repozytorium biblioteki `eh_os_contract` (kontrakt procesu, dispatch zdarzeń, sprawdzanie zgodności), jej
dashboardu i pakietu `eh_os_contract_auth`; `sandbox/` to dane testowe. Pivot do v2 (DSL na Sparku, model domeny w
stylu ESDM, event sourcing na własnym magazynie, crypto-shredding) **ma za sobą E0–E11**, a po nich #53–#56 (tabele
poza `public`, klucz blokady per schemat, każda nazwa w formie). **E12 — integracja między aplikacjami — jest
zamknięte i w `main`**: E12a (#57, `Bus`), E12b (#58, relay), E12c (#59, inbox), E12d (#61, `call/3`), E12e (#62,
dokumentacja); pytania, które zostawiło, to issues #63–#66 (#67). Po E12 w `main` są jeszcze: plan generatora
manifestu v2 odzyskany z worktree (#68), termin pobierania kluczy w auth (#69, odzyskany z #36) i sprawdzenie planu
EH wobec dzisiejszego kodu (#70).

**EH — generator `ehos.manifest/v2` — jest zamknięty i w `main`** (#73, merge `743e91d`, z EH3 wmergowanym do
niego jako #74): `EhOsContract.Auth.EhosYaml.read/1` czyta `ehos.yaml` jak EHOS, a `mix eh_os_contract.manifest`
pisze z niego v2 w miejsce v1 — „EH2 — co wyszło” i „EH3 — co wyszło” pod „EH — odpowiedź EHOS-a”.

**EB — logowanie przeglądarki przez EHOS w `eh_os_contract_auth`** ([#78](https://github.com/EmpoweredHouse/eh-os-contract/issues/78))
— plan w „Dopisek 2 października — EB”, specyfikacja w `docs/adr/browser-session.md`. **EB1 jest w `main`** (#82,
merge `7a2bcb7`), a po nim [#83](https://github.com/EmpoweredHouse/eh-os-contract/issues/83): `ehos.yaml/v2` z
kluczem `sign_in` (`eh-os` D-69) w czytniku i generatorze (#84, merge `ef0e94d`) — „Dopisek 2 października (2)”.
**EB jest zamknięte i w `main`**: EB2a (#85), EB2b (#86), EB3a (#87), EB3b (#88, merge `da9f56f`) — „EB3b — co
wyszło”. Ekranów logowania biblioteka nie ma i mieć nie będzie: formularz logowania, odmowy i wylogowanie to strony
EHOS-a (`EhosWeb.SignInController`, `PersonLive.Login`); host dokłada tylko link „Zaloguj” i przycisk „Wyloguj”.

**#99 — cykl życia agregatu — jest zamknięty w kodzie i w `main`** (4 października): LC0 #120 (sprzęt AppUnite jako
trzecie dane testowe), LC1 #121 (DSL i reguły `T1`–`T4`), LC2 #122 (status w `State`, `from:`, strażnik w
dispatchu), LC3 #123 (raport), LC4a #124 (`Computer` na cyklu życia, `T4` dla drobniejszych odmów), LC4b #125
(diagram w `graph` i na dashboardzie), #126 (utrata tylko z `W użytku`, poprawka użytkownika po obejrzeniu
diagramu) — „Dopisek 4 października — #99” i „LC… — co wyszło”. Po nim #128 (AppUnite: zapotrzebowanie na
komputer, kontrakt `Demands`) — „Dopisek 4 października (2)”.

**Następna praca to program DD — „DDD sprawdzane przez kod”** (zatwierdzony przez użytkownika 5 października): 53
etapy — DD0 w fali 0 i 52 w pięciu falach. **Jedynym miejscem ze stanem programu jest tabela „Postęp” w „Dopisek 5
października — DD”**; tam też decyzje z odrzuconymi opcjami, projekt każdego etapu, decyzje przed etapami i ryzyka.
Fala 1: N1, N2 w `main` (#137, #138); N3, W1, W2 w otwartych PR-ach #139, #142, #143 (stos); następny jest W3
(publiczne, czyste jądro `Trace`), potem W4, T1+T1s, X1, S4 w dowolnej kolejności.

### Stan repozytorium

- **`origin/main` = `f0e473d`** (merge #138, N2; przed nim #137 N1, #135 DD0, każdy z poprawką po przeglądzie
  CodeRabbita i `.coderabbit.yaml` dla PR-ów na dowolną gałąź).
- **Otwarte PR-y — stos, merge po kolei:** [#139](https://github.com/EmpoweredHouse/eh-os-contract/pull/139) N3
  (`dsl/n3-timer-label`, na `main`) → [#142](https://github.com/EmpoweredHouse/eh-os-contract/pull/142) W1
  (`engine/w1-schema-version`, na #139) → [#143](https://github.com/EmpoweredHouse/eh-os-contract/pull/143) W2
  (`engine/w2-day-tags`, na #142). Po merge'u jednego baza następnego przechodzi na `main` (albo `gh pr edit <n>
  --base main`); jeśli przyjdą poprawki do `main`, zmergować `main` w dół stosu — konflikt w CHANGELOG jest
  prawdopodobny, bo W1 przeniósł wpisy DD do górnej sekcji „Unreleased”.
- Wcześniej `6ce4c30` (merge #126, ostatni PR #99). Przedtem `eb0c8a1` (merge #103: #98,
  budżet bajtów klucza — „#98 — co wyszło”). Przedtem `b6a96dd` —
  #101 (handoff po #96), `90a83f2` — #102 (EP1, z sesji `esdm-dsl-comparison`), `0b7bc84` — #100 (poprawki
  CodeRabbita do #95), `b65b8b7` — #97 (#96, F8/F9), `996d89f` — #95 (granice wartości). CI `main` na `90a83f2` —
  `success`; na `eb0c8a1` (przebieg `37135771176`) w toku przy pisaniu. CI PR-a #103 — `success`, CodeRabbit bez
  uwag. Historia `main` z merge'ami PR-ów; gałęzie liniowe. **Otwartych PR-ów brak** poza tym handoffem.
- **#95 zmergowano bez dwóch ostatnich commitów** (poprawek z komentarzy CodeRabbita) — przyszły osobno jako #100,
  razem z błędem, który przegląd w nich znalazł. W `main` jest wszystko; zapis w „Granice wartości z żądania”.
- **Gałęzie:** gałęzie tej pracy usunięte na GitHubie i lokalnie 3 października, za zgodą użytkownika (EB, EH, #71,
  #89, discovery, #65, #93, #95, #96, #100, a także przypadkowy `revert-95-engine/bounded-values` — revert z przycisku
  GitHuba, bez PR-a); `engine/issue-98-key-budget` (#103) — po merge'u, za zgodą użytkownika. Zostało 59 innych gałęzi na GitHubie, zmergowanych dawno — nieruszane z wyboru użytkownika.
- **Worktree (5 października, wieczór):** `computer-ordering-process-f84437` — sesja DD (`engine/w2-day-tags`);
  `plan-md-incomplete-actions-27a0e4` (trzyma `dsl/n2-subscribe` — tam powstały poprawki po przeglądach #135/#138),
  `esdm-dsl-comparison-d82750`, `ep4-ep5-user-questions-95855b` — innych sesji, nie ruszać.
- **Bazy Postgresa są wspólne dla wszystkich worktree** (`eh_os_contract_host_dev`, `…_host_test`,
  `eh_os_contract_test`, `…_test_commits`, `eh_os_contract_web_test`, `eh_os_contract_auth_test`), schemat V01 z
  ręcznymi poprawkami z E11f i E12c, baza auth na V03. **Brama obok cudzego `phx.server` albo cudzych testów potrafi
  paść na `too_many_connections`** (3 października, dwa razy: 9 padnięć silnika w `SchemaTest` i `AppendLockTest`,
  sam silnik przechodził) — wtedy `mix check`
  każdego pakietu osobno, po kolei, i zapisać, że tak było.
- **Otwarte na GitHubie:** #64 (okno retencji inboxu —
  czeka na EHOS), #63 (kształt `call/3` — do pierwszych innych drzwi), #49 (materiał klientów poza repozytorium).
  **W `EmpoweredHouse/eh-os`: #91–#96 i #111** — nasze potrzeby wobec EHOS-a („Dopisek 1 października”).
- **`ehos-ledger`** przypina `eh-os-contract` i puszcza w CI `mix eh_os_contract.manifest`; bump przypięcia — w tamtym
  repozytorium. Od #95/#100 dokumenty OpenAPI i AsyncAPI z polem `:id` albo `:integer` mają nowy
  `x-eh-os-contract-digest`; po #98 nowy ma dokument OpenAPI **każdego** kontraktu z komendą (opis odpowiedzi 422).

### Co zostało — i czyje to jest

- **Program DD — następna praca z kodem.** Stan, kolejność i zależności: tabela „Postęp” w „Dopisek 5 października
  — DD”. Kolejno:
  1. **W `main`:** DD0 (#135), N1 (#137), N2 (#138). **Użytkownik:** merge #139 (N3), potem #142 (W1), potem #143
     (W2); po każdym ☑ w tabeli robi asystent przy następnym etapie.
  2. **Asystent:** W3 na nowej gałęzi od `engine/w2-day-tags` (tabela „Postęp” żyje na stosie); potem W4, T1+T1s, X1,
     S4. Start etapu: ◐ i gałąź w tabeli; koniec: „### <ID> — co wyszło (data)”; po merge'u ☑ i numer PR-a.
  3. **Użytkownik, przy etapie:** pytania z „Do decyzji przed etapem” (pierwsze: `cadence` przed P1d; V02 albo
     V01 w miejscu przed T2a i P2h; potwierdzenie etykiet timerów sandboxa — „N3 — co wyszło”); po każdej fali „dalej czy
     stop” i kiedy podbić przypięcie w aplikacji AppUnite (`~/Projects/ai/appunite_equipment`) i `ehos-ledger`.
- **AppUnite — zapotrzebowanie (`Demands`) jest w `main`** (#128); dwa pytania z przeglądu i etapy `Computers`
  wobec cyklu życia czekają na użytkownika — „Dopisek 4 października (2)”, „Otwarte z przeglądu”.
- **Po #99, decyzja użytkownika (4 października): raport wystarczy.** Zwrot odnotowany z błędnym przydziałem
  zwalnia komputer do ponownego wydania, a prawdziwy przydział zostaje otwarty — raport pokazuje jego niedokończony
  przebieg i to jest odpowiedź. *Odrzucone:* agregat przydziału w `Assignments` z odmową zwrotu cudzego przydziału
  (nowa jednostka bez reguły z materiału, która by jej wymagała); strażnik w `Computer` z komendą „uzgodnij zwrot”
  (reguła spoza materiału). Wątek CodeRabbita na #124 zamknięty z tą odpowiedzią; issue #99 zamknięte.
- **Po #99, biblioteka (bez przykładu, nie budujemy):** przejście z kilku statusów rysowane jako strzałka z
  każdego; `or_rejects:` per status zamiast odmowy w decyzji; enum read modelu czytający etykiety cyklu życia.
- **Ryzyka zostawione świadomie przy #98** (#103, issue zamknięte): zdarzenie przechodzi dispatch, a menedżer, który miałby
  zacząć na nim przebieg, staje (wybór „stoi”); komenda wydana przez reakcję i odrzucona `:key_too_long` dalej się
  wywraca; `issued_by` w indeksie idempotencji bez granicy długości (sprzed #98, wymaga credentialu wydawcy).
- **Pytanie z #96 o pusty `:id` jako wartość pola korelacji** — od #100 pusty `:id` jest odmawiany także przy
  dekodowaniu, więc pytanie dotyczy już tylko starych wierszy logu.
- **Zostawione świadomie:** #63, #64, #49 (wyżej).
- **Wady `oidcc` 3.9.0** — zgłoszone jako erlef/oidcc#552–#555; nasz kod ich nie potrzebuje.
- **Po stronie EHOS-a, nie tutaj:** szablon `ehos_app` (krok 7) i test na klastrze (krok 8); bump w `ehos-ledger`;
  port `4001.0` — [eh-os#111](https://github.com/EmpoweredHouse/eh-os/issues/111).
- **Wybór użytkownika na potem:** fikstury akceptacyjne (po #49), drobne reguły z „Otwartych pytań”, E13 (graf jako
  API), a poza etapami: proces na porcie 4000, wdrożenie E8 u hosta, publikacja na Hex.
- **Lista zmian do `eh-os`** — issues
  [eh-os#91](https://github.com/EmpoweredHouse/eh-os/issues/91)–[#96](https://github.com/EmpoweredHouse/eh-os/issues/96)
  i tabela w „Dopisek 1 października”. Nowa potrzeba: wiersz w tabeli i issue.
- **EP — proza w kontrakcie** (decyzja użytkownika z 3 października): EP1 → EP2 → EP3, potem EP4 i EP5 po
  decyzjach o kształcie — „Dopisek 3 października — EP”. **EP1–EP3 w `main`** (#102, #106, #107; poprawka
  hooka przeglądu dla worktree — #105). **EP4 w `main`** (#109; wiersze read modelu odrzucone — „Przed EP4”).
  **EP5a w `main`** (#111, operacje systemów zewnętrznych). **EP5b w `main`** (#112, odpowiedzialność aktora i
  pary terminów relacji; przypadkiem cofnięte w #114, przywrócone w #115 razem z poprawką słownika po przeglądzie
  CodeRabbita). **Plan EP skończony**; odłożone z niego: `invariant` encji i tożsamość
  `static` (każde dopiero z przykładem z materiału), sprawdzanie kodu wobec prozy przez LLM (na później).

### Co przeczytać najpierw

1. `CLAUDE.md` — brama bez `tail`, `MIX_ENV=test mix run`, polszczyzna tylko w wymienionych stringach (`label` po
   polsku w fiksturach testów jest dozwolony), wyrażenia regularne z flagą `u` i `[0-9]`, zsh bez dzielenia słów.
2. `PLAN.md`, „Dopisek 5 października — DD” — decyzje, tabela „Postęp” (jedyne miejsce ze stanem programu) i
   zasady jej prowadzenia, projekt etapu, który zaczynasz, „Konwencje każdego PR-a”, decyzje przed etapem, ryzyka.
3. `PLAN.md`, „Dopisek 4 października — #99” i „LC… — co wyszło” — cykl życia (`from:`, `or_rejects:`), na którym
   stoi program; „Dopisek 4 października (3)” — trzecia analiza ESDM i decyzja o etykiecie timera (N3).
4. `packages/eh_os_contract/docs/contract.md`, tabela kodów odmów — pilnuje jej `test/docs_test.exs`; każdy nowy
   kod tam trafia.
5. Starsze ustalenia przy kluczach i wartościach: „#98 — co wyszło”, „#96 — co wyszło”, „Granice wartości z żądania”.
6. `.claude/skills/pre-pr-review/SKILL.md` — dwa przeglądy równolegle, próba odwrotna, notatka w
   `refs/notes/review`; hook czyta `HEAD` głównego checkoutu, więc PR-y tu idą przez `gh api …/pulls`.

### Komendy

```bash
docker compose up -d && cd sandbox && mix ecto.setup
out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"
```

Brama idzie z `sandbox/` i woła `mix check` trzech pakietów; Postgres słucha na **5433**. **W świeżym worktree**
najpierw `MIX_ENV=test mix deps.get` w `packages/eh_os_contract`, `packages/eh_os_contract_web` i
`packages/eh_os_contract_auth` oraz `mix deps.get` w `sandbox/`. `docs/rules.md` regeneruje
`MIX_ENV=test mix eh_os_contract.rules` w pakiecie silnika. Do oglądania czegokolwiek `MIX_ENV=dev`. Grafy:
`mix eh_os_contract.graph --process <nazwa> --mermaid | --map <domena> | --system <domena> [--overlay] | --contract
<Moduł> [--overlay] [--unit <nazwa>]` — bez flagi obrazu task odmawia z opisem użycia. `docs/dsl/` regeneruje
`MIX_ENV=test mix eh_os_contract.docs`. Ekran `/dashboard/graph` w preview `eh_os_contract_host` (port 4010, CSP
EHOS-a).

**Z sesji Claude Code na tej maszynie SSH do GitHuba odmawia.** Pobieranie i push przez HTTPS z credentialem `gh`:

```bash
git -c credential.helper='!gh auth git-credential' fetch https://github.com/EmpoweredHouse/eh-os-contract.git +refs/heads/main:refs/remotes/origin/main
```

```bash
git -c credential.helper='!gh auth git-credential' push https://github.com/EmpoweredHouse/eh-os-contract.git <gałąź>:<gałąź>
```

Praca przerwana w pół — patch w scratchpadzie albo commit WIP na własnej gałęzi, nigdy gołe `git stash`.

**Pułapki** (poza listą w `CLAUDE.md`):
- nowe słowo DSL-a → `MIX_ENV=test mix spark.formatter --extensions EhOsContract.Domain.Dsl,EhOsContract.Contract.Dsl`
  w pakiecie silnika, a w `sandbox/` i pakiecie web skasować
  `_build/*/lib/*/.mix/cached_dot_formatter`, inaczej `mix format` doda nawiasy;
- fikstury kompilowane ze stringów w testach: numer linii w asercji to linia w stringu, nie w pliku testu;
- próba odwrotna: kopia pliku w scratchpadzie, mutacja, test, `cp` z kopii i `cmp` — nie `git stash` i **nie
  `git checkout -- plik`**, które cofa do HEAD razem z niezacommitowaną zmianą (E11f: zmazało refaktor, nałożony
  ponownie z tego samego skryptu);
- `~s(...)` kończy się na pierwszym `)`; fikstury v2: kontrakt bez procesu się nie kompiluje (R1), `publish … as:`
  wersjonowane (D11), `consumes "<nazwa>"` wymaga pól, `send` koliduje z `Kernel.send/2` (N2); opcja encji Sparka z
  blokiem idzie **do środka bloku** (`promise :x do unverified true … end`);
- dwa kontrakty o jednej nazwie procesu muszą mieć różne domeny (X7);
- test pakietu z bazą i drugi `mix` w tym samym pakiecie naraz się gryzą (wspólne `_build` i bazy testowe
  `eh_os_contract_test`, `…_commits`, bez partycji) — agentów z testami puszczać po kolei;
- Mermaid przed rysowaniem usuwa element o identyfikatorze, który rysuje (opis w `assets/js/app.js`);
- `\n` w heredocu `"""` testu z fiksturą to prawdziwa nowa linia w kompilowanym źródle — atom `:"x\n"` zajmuje
  wtedy dwie linie i przesuwa numery linii w asercjach; nazwę z nową linią pisz `#{"\\n"}` albo licz linie od nowa;
- `for` w Elixirze musi zaczynać się generatorem — filtr (`kind != …`, `:x in list`) idzie po generatorze;
- **hook `gh pr create` sprawdza notatkę przeglądu na `HEAD` głównego checkoutu** (`$CLAUDE_PROJECT_DIR`), nie
  worktree, z którego idzie PR — z worktree odmawia mimo notatki na głowie gałęzi. #57 i #58 wystawione przez
  `gh api repos/EmpoweredHouse/eh-os-contract/pulls -f base=main -f head=<gałąź> -f title=… -F body=@<plik>` po
  sprawdzeniu `git notes --ref=review show HEAD` w worktree; użytkownik o tym wie;
- `git grep -E` na tej maszynie nie rozumie `\b` i milczy, zamiast odmówić (w E11b `git grep -iP` też raz dał zero
  przy 38 plikach z trafieniem) — wynik „nic nie zostało” potwierdzać drugim narzędziem (`grep -rE`, `git grep -w`).

### Ostatnia pełna weryfikacja

- **5 października, wieczór, `engine/w2-day-tags` @ `5c3a619`** (kod W2; głowa `586eb07` dokłada tylko `PLAN.md`):
  `mix check` w `sandbox/` EXIT=0 — `check` sandboxa 0 / 29 / 10, silnika 0 / 75 / 6 (nowe ostrzeżenie:
  `event-without-consumer` dla `:day_closed` rigu); sandbox 194, silnik 1280, web 51, auth 286 + 1 property. CI:
  #139 @ `9c55d15` i #142 @ `0e0ac01` — job `check` success; #143 @ `586eb07` w toku przy pisaniu.
- **5 października, `docs/dd0-programme` po merge'u `main`:** bramy nie uruchamiano — gałąź różni się od `main`
  tylko `PLAN.md` (`git diff origin/main -- . ':!PLAN.md'` pusty). CI `main` na `af59a48` (#128) — `check` `success`.
- **#98 @ `1b0816d`** (głowa #103, na `b6a96dd` z EP1): pełna brama znowu padła na `too_many_connections` (5 testów
  `AppendLockTest`, 4 `SchemaTest`); sandbox 145 w niej, a pakiety osobno — EXIT=0: silnik **1170** (z testami EP1),
  `check` 0 / 71 / 6; web 52; auth 285 + 1 property. CI PR-a — `success`.
- **#98 @ `657e38c`** (przed rebase'em na `b6a96dd`; rebase dołożył tylko `PLAN.md` z #101 i EP1 z #102): pełna
  brama padła na `too_many_connections` (9 testów silnika, cudzy `phx.server`); sandbox przeszedł w niej (145,
  `check` 0 / 29 / 9), a `mix check` każdego pakietu osobno — EXIT=0: silnik **1164**, `check` 0 / **71** / 6 (+3
  ostrzeżenia rigu `KeyRig`: `:loaded` bez odbiorcy, `:watch` bez `ends_on` i bez scenariusza); web 52; auth 285 +
  1 property. Na `32187fc` (pierwszy commit) pełna brama z `sandbox/` — EXIT=0.
- **Lokalnie, 3 października wieczorem, na `main` = `0b7bc84`** (główny checkout po `mix deps.get` w trzech pakietach
  i `sandbox/`): brama z `sandbox/` → **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik **1151**, `check` 0 / 68
  / 6; web 52; auth 285 + 1 property. CI `main` na `0b7bc84` — `success` (job `check`).
- **#100 @ `2a7ebad`:** pełna brama padła na `too_many_connections` (cudzy `phx.server`); sandbox przeszedł w niej,
  a `mix check` każdego pakietu osobno — EXIT=0 (silnik 1139, web 52, auth 285 + 1 property).
- **#97 @ `7d3997e`:** brama z `sandbox/` → EXIT=0 — silnik 1150, reszta jak wyżej.
- **Lokalnie, 3 października, po rebase'ach na `9e61834`:** brama z `sandbox/` → **EXIT=0** na każdej głowie —
  #93 @ `3a675bb`: sandbox 145, silnik 1129, web 52, auth 285 + 1 property; #95 @ `0446abd`: silnik **1138**, reszta
  jak wyżej. Liczby dla #96 — „#96 — co wyszło”.
- **Lokalnie, 2 października, na `56876b2`** (#89 po przeglądzie, `auth/issue-89-loopback`): brama z `sandbox/` →
  **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1114, `check` 0 / 68 / 6; web 52; auth **278** + 1 property.
- **Lokalnie, 2 października, na `f63596e`** (EB3b po przeglądzie, `eb/eb3b-applications`): brama z `sandbox/` →
  **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1114, `check` 0 / 68 / 6; web 52; auth **274** + 1
  property. CI `main` na `499ea0b` (EB3a) — `success`.
- **Lokalnie, 2 października, na `auth/issue-71-keys-hardening`** (#71, od `65d7caf`): brama z `sandbox/` →
  **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1114, `check` 0 / 68 / 6; web 52; auth **149** + 1 property.
- **Lokalnie, 2 października, na `claude/issue-72-assessment-923997`** (#72, od `01ac970`): brama z `sandbox/` →
  **EXIT=0** — sandbox 145; silnik **1114** (+10, budzenie runnerów); web 52; auth 138 + 1 property.
- **`main` = `743e91d`** (merge #73, EH): drzewo jak `2bda2b7`, ostatni commit PR-a; lokalnie na `2bda2b7` brama z
  `sandbox/` → **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1104, `check` 0 / 68 / 6; web 52; auth **138** + 1
  property. CI PR-a na `3263d1d` — `success`; CI `main` na `743e91d` — sprawdzić.
- **Lokalnie, 1 października, na `ac8d694`** (EH3 po trzech rundach przeglądu, `eh/eh3-manifest-v2`): brama z
  `sandbox/` → **EXIT=0** — sandbox **145**, `check` 0 / 29 / 9; silnik 1104, `check` 0 / 68 / 6; web 52; auth
  **137** + 1 property.
- **Lokalnie, 1 października, na `ee67995`** (EH2 po trzech rundach przeglądu, `eh/eh2-ehos-yaml`): brama z
  `sandbox/` → **EXIT=0** — sandbox 144, `check` 0 / 29 / 9; silnik 1104, `check` 0 / 68 / 6; web 52; auth **115**.
- **Lokalnie, 1 października, na `main` = `aadcbd1`** (baza EH, przed pierwszym commitem `eh/eh2-ehos-yaml`): brama z
  `sandbox/` → **EXIT=0** — sandbox 144, `check` **0 / 29 / 9**; silnik **1104**, `check` **0 / 68 / 6**; web 52;
  auth **71**. CI `main` na `aadcbd1` (przebieg `36860580158`, job `check`) — `success`.
- **Lokalnie, 1 października, na `dsl-v2/e12e-docs`** (E12e po przeglądzie; sama dokumentacja): brama z `sandbox/`
  → **EXIT=0**, liczby jak dla E12d niżej. CI `main` na `7aa0496` (merge #61) — sprawdzić.
- **Lokalnie, 1 października, na `9d1ae58`** (E12d po przeglądzie, `dsl-v2/e12d-call`): brama z `sandbox/` →
  **EXIT=0** — sandbox 144, `check` 0 / 29 / 9; silnik **1104** (1094 + `call_test.exs` 9 + Plug 1), `check`
  **0 / 68 / 6**; web 52; auth 68. CI `main` na `67253bf` (merge #59) — sprawdzić
  (`gh run list --repo EmpoweredHouse/eh-os-contract --branch main --limit 2`).
- **Lokalnie, 1 października, na `0038a71`** (E12c po dwóch rundach przeglądu): brama z `sandbox/` → **EXIT=0** —
  sandbox 144, `check` 0 / 29 / 9; silnik **1094** (+4 testy keepera), `check` **0 / 68 / 6**; web 52; auth **68**.
- **Lokalnie, 1 października, na `da2b841`** (E12c po pierwszej rundzie przeglądu, głowa kodu `bab57b3`): brama z `sandbox/` →
  **EXIT=0** — sandbox 144, `check` 0 / 29 / 9; silnik **1090** (1088 + kolizja klucza 1 + broker leżący przy
  starcie 1), `check` **0 / 68 / 6**; web 52; auth **67** (+1, pomocnik testów i `.subscribe`).
- **Lokalnie, 1 października, na drzewie kodu `0692740`** (głowa kodu E12c przed przeglądem): brama z `sandbox/` → **EXIT=0** —
  sandbox 144, `check` 0 / 29 / 9; silnik **1088**, `check` **0 / 68 / 6**; web 52; auth 66. Szczegóły i commity
  pośrednie — „E12c — co wyszło”. Brama bazowa tej sesji na `66c3637` — te same liczby co niżej dla `842a2f1`.
- **Lokalnie, 1 października, na `main` = `842a2f1`** (po merge'u #58; drzewo kodu jak `25e51d5`): brama z
  `sandbox/` → **EXIT=0** — sandbox 144, `check` 0 / 29 / 9; silnik **1073**, `check` 0 / 67 / 6; web 52; auth 66.
- **CI:** PR #58 (`check`, przebieg `36791662027`) — `success`; `main` na `7e4e4cc` (`36788298869`) — `success`;
  `main` na `842a2f1` (`36825204797`, job `check`) — `success`.
- **Lokalnie, 1 października, na `25e51d5`** (głowa kodu E12b po przeglądzie): brama z `sandbox/` → **EXIT=0** —
  sandbox 144, `check` 0 / 29 / 9; silnik **1073** (1059 + 14: relay 12, runner na `CommitRepo` 1, `--reset`
  relaya 1), `check` **0 / 67 / 6** — o jedno ostrzeżenie i jedną uwagę więcej, obie z fikstury `BusRig` i
  zamierzone (`event-without-consumer` dla `:cancelled`, kontroli zdarzenia, które nie wychodzi;
  `free-text-not-personal` dla notatki, która zostaje w sklepie); web 52; auth 66. Pełna brama także na `472102e`;
  commity poprawek sprawdzane testami relaya, runnera i taska oraz kompilacją z `--warnings-as-errors`. CI `main`
  na `7e4e4cc` (merge #57) — `success`.
- **Lokalnie, 1 października, na `fb6bf46`** (głowa kodu E12a po przeglądzie): brama z `sandbox/` → **EXIT=0** —
  sandbox 144, `check` 0 / 29 / 9; silnik **1059** (1028 + 31 testów `Bus.Local` i suity), `check` 0 / 66 / 5; web
  52; auth 66. Te same liczby `check`, co przed E12a. Commity poprawek między `5ce8c90` a `fb6bf46` sprawdzane
  testem `bus_local_test.exs` i kompilacją z `--warnings-as-errors`, pełna brama na `5ce8c90` i na `fb6bf46`.
- **Lokalnie, 30 września, na `main` = `6e1658a`** (po merge'u #56): brama z `sandbox/` → **EXIT=0** — sandbox 144
  testy, `eh_os_contract.check` 0 / 29 / 9; silnik **1028**, `check` 0 / 66 / 5; web 52; auth 66; `docs/dsl` i
  `docs/rules.md` aktualne. Drzewo `6e1658a` jest identyczne z głową #56 (`e002519`).
- **CI:** PR #56 na `e002519` (przebieg `36778876263`, job `check`) — `success`; `main` na `0e6e10f`
  (`36761436783`) — `success`; `main` na `6e1658a` (`36779783368`) — `success`.
- **Dwie bramy naraz z dwóch worktree gryzą się o wspólne bazy** — 30 września pierwsza brama tej sesji padła na
  `too_many_connections`, bo w tej samej minucie bramę puszczała sesja PR-a #53. Przed bramą sprawdzić, czy żaden
  inny BEAM z worktree tego repozytorium nie chodzi.
- Wcześniejsze przebiegi — w zapisach „co wyszło” poszczególnych etapów.

### Otwarte pytania

- *Rozstrzygnięte 3 października (#66): skrót zamiast wartości, której tabela nie utrzyma.* Opis sprzed decyzji:
  **Surowa wartość zakresu w decyzjach auth** — [#66](https://github.com/EmpoweredHouse/eh-os-contract/issues/66) (z przeglądu E12d, sprzed niego): wartość pola zakresu „jak wysłana”
  idzie do kolumny `scope_value` (`text`) decyzji `eh_os_contract_auth`; znak `\u0000` z JSON-a albo zły UTF-8 z
  query stringa (`%FF`) wywraca zapis decyzji — 500 zamiast odmowy; długi napis — wiersz na żądanie. Możliwe:
  odmowa wartości spoza UTF-8 bez NUL przed pytaniem `Authorizer`, limit długości — nowy powód odmowy, do decyzji.
- *Rozstrzygnięte 3 października (#64): wszystko zostaje, host mierzy; okno czeka na retencję transportu EHOS-a.*
  Opis sprzed decyzji: **Retencja `eh_os_contract_inbox`** — [#64](https://github.com/EmpoweredHouse/eh-os-contract/issues/64) (z E12c): wiersz na fakt na inbox, na zawsze; czyszczenie po wieku skraca
  okno, w którym ten sam fakt pod nowym id (FM-08) jest rozpoznany — granica do decyzji użytkownika.
- **Kształt `EhOsContract.call/3` do sprawdzenia przy drugich prawdziwych drzwiach** (3 października: odłożone
  decyzją użytkownika do pierwszych innych drzwi) — [#63](https://github.com/EmpoweredHouse/eh-os-contract/issues/63) (z E12d) — zbudowany na
  zapas z jednego użytkownika (Plug), wbrew zasadzie z 27 września, z wyboru użytkownika. Wyzwalacz: pierwsze inne
  drzwi dla surowych danych z credentialem (formularz LiveView, job z credentialem osoby, MCP), przed ich
  produkcją i najlepiej przed wydaniem 0.3.0; lista pytań — „E12d — co wyszło”, „Do powrotu”.
- *Rozstrzygnięte 1 października („Przed E12d”): E12d teraz.* Opis sprzed decyzji: **czy publiczne wejście dla
  surowych danych robić teraz** — termin z 27 września stał na przesłance, że inbox to drugie drzwi dla surowych
  danych; zbudowany inbox nie autoryzuje i dekoduje sam, a komendy wydaje polityka strukturą.
- *Rozstrzygnięte 3 października (#65): krok liczony z inboxu.* Opis sprzed decyzji: **Zgodność nie widzi polityki
  inboxu** — [#65](https://github.com/EmpoweredHouse/eh-os-contract/issues/65) (z E12c): `Paths` nie ma kroku dla zdarzenia odebranego, więc ekran nie
  mówi, czy polityka na nim była przejechana. Możliwe: krok liczony z komend `policy:<nazwa>`, których przyczyna
  jest w `eh_os_contract_inbox`; albo zostawić — do decyzji użytkownika.
- *Rozstrzygnięte 1 października (D1, „Przed E12c”): wiadomość niesie klucz z `idempotent_on`.* Opis sprzed
  decyzji: **E12c, przed startem — decyzja użytkownika: czy wiadomość niesie wartości `idempotent_on`.** Inbox kluczuje
  `(nazwa, id wiadomości)`, a id to `<id zdarzenia>/<nazwa wersjonowana>`, więc dwa zdarzenia o tych samych
  wartościach `idempotent_on` (np. `visit_id`) to dwie wiadomości i dwie reakcje; `eh-os` FM-08 chce jednej. Możliwe:
  piąte pole `Bus.Message` z wartościami (inbox kluczuje po nich), albo nic (subskrybent sam w swojej jednostce).
- *Rozstrzygnięte 1 października (D2, „Przed E12c”): kolejność w drzewie silnika.* Opis sprzed decyzji: **E12c,
  przed startem — decyzja użytkownika: kiedy powstaje konsument odbiorcy względem relaya wydawcy.**
  `Bus.Local` daje nowemu konsumentowi tylko to, co opublikowano po jego pierwszej subskrypcji, a relay wydawcy
  startuje od głowy logu — w dwóch aplikacjach w jednym BEAM-ie relay uruchomiony przed konsumentem publikuje w
  próżnię. Możliwe: kolejność startu w drzewie hosta, konsument rejestrowany przy pierwszym boocie jak wiersz relaya,
  albo zostawić to transportowi (JetStream trzyma strumień).
- **H177** z materiału Rehmedu przeczy DEC-18 — czeka na klienta.
- **Runner read modelu `:in_transaction`** odpytuje co sekundę — wraca przy pomiarze; tam też nakładka na `/graph`
  bez granicy czasu, podwójny mount, koszt raportu z całej historii przebiegów i 17 s testu skali (niezłapane;
  „E11a — co wyszło”).
- **Dwie domeny o jednym `name:`** dałyby zdublowane identyfikatory bloków na `/graph` — sprawa rejestru.
- **Z E11a, bez decyzji:** reguła v2 w miejsce `promise-finer-than-run` (kandydat na E11f); pusty `:string` jako
  wartość pola korelacji; termin `{1, :hour}` w raporcie bez liczby.
- **Z przeglądu E11b, sprzed E11b, bez decyzji:** `config :eh_os_contract, exclude:` dopasowuje prefiks bez granicy
  modułu (`"ProcessShapes.Promised"` wycina też `ProcessShapes.PromisedLate`), a `Implementations.build/1` go nie
  stosuje (konsumenci wyłączonego kontraktu dostają wpisy dispatchu i wiersze subskrypcji). Zmiana zmienia znaczenie
  konfiguracji hosta — do użytkownika; kandydat na E11f.
- **Z PR-a #53:** klucz blokady dopisu jest stały, a blokady doradcze są wspólne dla całej bazy — *rozstrzygnięte
  30 września: klucz per schemat, osobny PR* („Klucz blokady dopisu per schemat — co wyszło”).
- **Z przeglądu #50, sprzed #50: `name:` domeny nie jest sprawdzane** — *rozstrzygnięte 30 września: odmowa D11 w
  regułach domeny, z podkreślnikiem* („`name:` domeny jako przestrzeń nazw — co wyszło”). Opis sprzed decyzji: `name:`
  jest przestrzenią nazw publikacji. `name: :"acme.billing"` publikuje `"acme.billing.x.v1"` — przechodzi oba
  sprawdzenia D11, a na brokerze leży w przestrzeni aplikacji `acme` (`acme.>`); wraca w E12, gdy nazwy staną się
  tematami i capability `<nazwa>.subscribe`. Inne złe nazwy (`:"shop-"`, `:"my shop"`, wielkie litery) zamykają się
  same — żadna publikacja nie przejdzie — ale odmowa wskazuje publikację, nie domenę. Możliwe: odmowa w regułach
  domeny dla `name:` spoza gramatyki segmentu przestrzeni nazw (z `_` albo bez — bez `_` odpada `:dispatch_rig` z
  fikstur i każda domena OTP nazwana z podkreślnikiem); albo w `namespaces/1` porównanie pierwszego segmentu z
  nazwą domeny. Nowy powód odmowy widoczny dla hosta.
- **Z przeglądu `name:` domeny, sprzed tej zmiany** — *oba zrobione 30 września na tej samej gałęzi, na polecenie
  użytkownika* („`$` w nazwach i nazwy aktorów — co wyszło”). Opis sprzed decyzji:
  (1) **N1, D9 i ścieżki stron kończą wzorzec na `$`**, nie `\z` (`contract/rules/names.ex`, `domain/rules.ex` przy
  D9, `pages.ex`) — `command :"pay\n"` przechodzi N1, a capability `"acme.pay\n"` trafia do `Model.capabilities`,
  ścieżki OpenAPI i manifestu EHOS-a; ta sama klasa co `$` → `\z` w #55. (2) **Nazwy aktorów domeny nie mają
  sprawdzenia formy** — `actor :"*"` albo `:"billing.clerk"` w domenie `acme` daje rolę `acme.*` /
  `acme.billing.clerk` w manifeście; z przestrzeni aplikacji nie wychodzi, ale czy EHOS czyta `*` albo `>` w roli jako
  wzorzec, jest poza tym repozytorium. Możliwe: snake_case jak N1, z `\z`.
- **Z przeglądu poprawek `$` i aktorów, sprzed nich** — *nazwy elementów domeny zrobione 30 września, na polecenie
  użytkownika, na `dsl-v2/domain-names-snake-case`* („Nazwy elementów domeny — co wyszło”); zostaje reszta z tego
  punktu. Opis sprzed decyzji: **nazwy pozostałych elementów domeny nie mają sprawdzenia formy** — wartości, encje, konteksty, podmioty,
  systemy zewnętrzne, poddziedziny; sprawdzana jest tylko unikalność (D1). `value :"a/b"` daje moduł zagnieżdżony
  `D.Values.A.B`, `:money_amount` i `:money__amount` — ten sam `MoneyAmount`; `context :"front desk"` psuje
  identyfikator węzła Mermaida na mapie kontekstów; strony (`mix eh_os_contract.pages`) odmawiają dopiero przy
  generowaniu. Możliwe: jedna reguła snake_case dla wszystkich nazw domeny (`DslRules.snake_case?/1` już jest), jak
  N1 dla kontraktu. Obok, niżej: pole użyte jako `scope:` staje się kluczem w `scp` EHOS-a i nie ma sprawdzenia formy
  poza F1 (wraca, gdy manifest poniesie zakresy); `Model.capabilities/1` przy zapytaniu i zdarzeniu nagrywanym o
  jednej nazwie traci jedno bez kompilatora L3 (D14 łapie to w L3, zamyka się bezpiecznie); mapa capability liczona
  od nowa przy każdym dispatchu z credentialem (do pomiaru).
- **Z przeglądu nazw elementów domeny, sprzed tej zmiany** — *(1) i (2) zrobione 30 września na polecenie
  użytkownika, w PR-ze #56* („Kolizja nazw kontraktu i nazwy pól — co wyszło”); (3) i (4) zostają. Opis sprzed
  decyzji: (1) **kolizja nazw kontraktu po `Macro.camelize`** — N1 sprawdza tylko równość, a `event :visit_closed`
  obok `event :visit_closed_` kompiluje się z ostrzeżeniem „redefining module …Events.VisitClosed” (sprawdzone
  tymczasowym testem 30 września): jedno zdarzenie dostaje strukturę drugiego; bez `--warnings-as-errors` host tego
  nie zobaczy. Możliwe: ta sama odmowa co D1 dla wartości, w N1, w przestrzeni nazw, która generuje moduły. (2) **Nazwy
  pól** — wartości, encji i kontraktu — mają tylko unikalność (encje) i zakaz wiodącego `__` (F1); `field :"Invoice
  No"` trafia do klucza typespeca, JSON Schemy i strony, a pole wartości zadeklarowane dwa razy daje w JSON Schemie
  ostatnią definicję przy `required` z pierwszej. (3) Etykiety krawędzi Mermaida nie są escapowane (`pipes/1`), a
  trafiają do nich nazwy pól kontraktu — (2) zamyka to przy okazji. (4) Kolizja stron `context :values` z
  `value :index` (`values/index.md`) — odmawia dopiero `mix eh_os_contract.pages`.
- *Rozstrzygnięte 3 października: klucz to drukowalny ASCII do 255 bajtów (#93), a pole korelacji to `:id` do 255
  bajtów, najwyżej sześć (#95, #96).* Opisy sprzed decyzji, dwa niżej.
- **Z E11f, bez decyzji:** klucz idempotencji z etykietą aktora dłuższy niż ~2,7 KB daje 500 (limit długości byłby
  nowym powodem odmowy, widocznym dla hosta); ten sam aktor z tym samym kluczem dostaje stary paragon, także gdy nowa
  komenda ma inny zakres albo treść (opcja „skrót treści” odrzucona).
- **Z przeglądu E11c, sprzed E11c, bez decyzji:** (1) wartość pola korelacji albo nagłówek `idempotency-key`
  dłuższe niż ~2,7 KB wywracają dopis błędem Postgresa („index row size exceeds maximum” w indeksie `_event_runs`,
  strumienia albo idempotencji) — 500 zamiast odmowy; (2) `_commands` ma tylko indeks idempotencji, więc `Paths`
  (filtr po `contract`, `outcome`, `issued_by LIKE`) czyta całą tabelę przy każdym raporcie — do pomiaru razem z
  runnerem read modelu.
- **Z przeglądu E11d-1, sprzed E11:** (1) **klucz idempotencji jest globalny** (*zrobione w E11f-1: w zakresie
  aktora*; zostaje odtworzenie paragonu przez tego samego aktora po zawężeniu jego zakresu — „E11f — co wyszło”) —
  `Dispatcher` szuka przyjętej komendy po `idempotency_key`, `contract` i `type`, a unikalny indeks jest na samym
  kluczu; przez HTTP klucz to nagłówek klienta. Aktor B z tym samym uprawnieniem, który zgadnie klucz A (np.
  `"req-81"` z `docs/authorization.md`), dostaje paragon A — `command_id`, wygenerowaną tożsamość, pozycje; w kodzie
  także zdarzenia z odszyfrowanymi polami osobowymi — a użyty zawczasu klucz sprawia, że prawdziwa komenda A wraca
  jako `duplicate: true` bez wykonania. Możliwe: klucz w zakresie aktora (i skrót treści), albo wymóg klucza
  niezgadywalnego w dokumentacji. (2) Partia `rewrap!` trzyma `FOR UPDATE` na 500 wierszach kluczy z wywołaniem
  vaulta na wiersz, a `erase/3` bierze blokadę dopisu i czeka na te wiersze — przy wolnym KMS wszystkie dispatche
  czekają. (3) `mix eh_os_contract.rewrap` uruchamia całego hosta (`app.start`: Endpoint, kolejki Obana, runnery).
- **Z E11e:** test „no longer fits” — *zrobione w E11f-2*; upcasterów nie ma — bez decyzji; nazwa modułu kontraktu
  na wierszach — *rozstrzygnięte w E11f*: zostaje tożsamością kontraktu, zmiany nazwy modułu z historią się nie robi.
- **D1–D14** przyjęte; w v2 §19: transport v1 między kontenerami, kontrakt upcasterów.

### Zgoda i stałe uprawnienia

**Ten blok jest do skasowania. Skasowanie go cofa uprawnienie — nie migruje ono samo między sesjami.**

W sesjach E11b–E11f (29–30 września), w sesji #56 (30 września), w sesji E12a–E12b, w sesji E12c i w sesji EH
(1 października) użytkownik potwierdzał: commity bez pytania na gałęziach etapu przy zielonej bramie
na każdym commicie; zapis stanu do `PLAN.md` i założeń z datą do `docs/adr/`. **W nowej sesji obowiązuje to
dopiero po ponownym potwierdzeniu przez użytkownika.** Push, PR, merge, tag i Hex — tylko na wyraźne polecenie,
przed PR skill `pre-pr-review`. Do `~/Projects/ai/empowered-house-context` nie piszemy nigdy; do
`~/Projects/ai/eh-os` też nie (tylko czytanie).

### Język

Rozmowa po polsku. Kod, moduledoki, komentarze, nazwy testów, komunikaty, commity, opisy PR, `docs/adr/`,
`README.md` — po angielsku; `PLAN.md` i `CLAUDE.md` po polsku. Pełna reguła — `CLAUDE.md`.

## Dopisek 5 października (2) — manifest oferuje query i zapisy (#133, `eh-os` D-73)

**Skąd.** Test polowy (aplikacja `EmpoweredHouse/appunite-equipment`, z `ehosctl init`, wdrożona przez EHOS na
lokalnym k3d): osoba z jedyną rolą aplikacji zalogowała się przez EHOS i dostała odmowę na pierwszej stronie —
`missing_capability` na query `inventory_list`, w `eh_os_contract_auth_decisions`. `ehos.manifest/v2` znał tylko
capability komendy, więc generator pomijał query i zapisy (`recorded_by:`), rola w EHOS ich nie miała, a credential
też nie. Każda aplikacja, której ludzie czytają przez kontrakt, była na EHOS bezużyteczna.

**Decyzja użytkownika (5 października): naprawić w bibliotekach, nie obchodzić w aplikacji.** Odrzucone:
obejście w aplikacji (strony czytają tabele read modeli wprost przez Ecto — lista działa od razu, ale zapisy dalej
odrzucone, a odczyt traci autoryzację kontraktu) i zatrzymanie testu na tym wyniku.

**Kształt (decyzja użytkownika, zapisana w `eh-os` jako D-73, accepted):** capability ma dokładnie jeden z kluczy
`command`, `query`, `record`, a `name` go powtarza. Odrzucone: `kind` + `declaration` (komenda staje się wyjątkiem albo
przemianowanie zmienia digest każdego manifestu) i osobne listy `offers.queries`/`offers.records` (role, unikalność,
diff i podgląd musiałyby znać trzy listy, a credential niesie i tak same nazwy).

**Co zrobione tutaj:**

- `mix eh_os_contract.manifest` emituje komendy, query i zapisy, które może wykonać ludzki aktor; role trzymają
  wszystkie trzy. EHOS sprzed D-73 taki manifest odrzuci — najpierw wdraża się EHOS.
- **N1 rozszerzone:** query nie może nosić nazwy zdarzenia, które zapisuje aktor. Obie są capability
  `<domena>.<nazwa>`, a od D-73 manifest oferuje obie. Luki nie było — reguła L3 D14 odrzucała tę parę, gdy działa
  kompilator Mixa — ale N1 odrzuca ją już przy kompilacji samego kontraktu, zanim `Model.capabilities/1` zlałby obie
  w jedną capability.
- **Query i komenda ze `scope:`** trafiają do manifestu bez wartości zakresu, więc każde wywołanie przez EHOS kończy
  się `:unscoped_grant` (zamknięte, nic nie przyznaje), dopóki wiązanie nie umie nieść wartości (D-40).
- Bez scope'ów: query ze `scope:` wychodzi jak komenda ze `scope:` dziś, a wiązanie wartości to D-40 (proposed).

## Dopisek 5 października — DD: DDD sprawdzane przez kod (program, decyzje, postęp)

**Skąd.** Ocena biblioteki z perspektywy DDD (sesja 4–5 października) wskazała luki strukturalne:
- kontrakt = jeden proces = jeden klucz (R1/R2) zamiast kontrakt = model kontekstu; sztuczne procesy (`ksef_intake`,
  `client`); proces end-to-end `clinical_visit` mieszka w kontrakcie sprawozdawczości;
- dane, na których stoi decyzja, przychodzą od wołającego (`p1_reported`, `total`), więc przez `EhOsContract.Plug`
  da się je podrobić;
- mapa kontekstów to etykiety (sprawdzany tylko kierunek); polityka domyślnie `:in_transaction` także między
  kontekstami;
- tożsamość zdarzeń i kontraktów pochodzi z nazw procesu i modułu; `schema_version` nigdy nie jest zapisywany,
  upcasterów brak;
- obietnice, przejścia cyklu życia i kolejność etapów nie mają scenariuszy ani zgodności na logu; dryf jest z
  konstrukcji pusty; `cadence` nikt nie ocenia;
- kolizje nazw: `terminal:` ×2, `scope` ×2, `consumes` dla dwóch mechanizmów, `identity` obok `identified_by`.

Cel programu: każdą regułę DDD, którą da się zapisać, przypiąć do sprawdzającego — kompilator (L2/L3), `check`
(L5), test generowany z kontraktu, dispatch albo raport zgodności. Plan zatwierdzony przez użytkownika
5 października. **Ten dopisek jest źródłem prawdy o programie**; kopia sesyjna planu
(`~/.claude/plans/przygotuj-plan-na-wprowadzenie-giggly-magpie.md`) nie jest aktualizowana.

**Zasada nadrzędna (użytkownik, 4 października): ESDM to nie wyrocznia.** Nazwy i kształty DSL-a uzasadniamy
merytorycznie: znaczenie w literaturze DDD (tak czytają je ludzie i LLM generujący kod), to, co robi silnik, jedno
słowo = jedno znaczenie w obu DSL-ach, koszt zmiany. Zgodność z ESDM najwyżej rozstrzyga remis — i trzeba mówić,
gdzie ESDM jest słaby (przykład: schemat process managera osadza go w domenie, a strona pojęcia — w kontekście).

### Decyzje użytkownika (4–5 października)

1. **Moduł procesu w dwóch krokach.** Najpierw `process` w kontrakcie opcjonalny (R2 tylko dla zdarzeń procesu),
   potem `use EhOsContract.Process` łączący zdarzenia wielu kontraktów; `stage` i koniec przebiegu wychodzą z
   jednostek. *Odrzucone:* tylko opcjonalny `process` (proces end-to-end zostałby w kontrakcie jednego kontekstu);
   bez zmian.
2. **Nazwy:** status `terminal:` → `final:`; scenariusz `scope` → `target`; `consumes "<nazwa>"` → `subscribe
   "<nazwa>"`; encja `identified_by:` → `identity` (deklaruje i wstrzykuje pole `:id`, jak w jednostce).
   *Odrzucone (asystent, po eksploracji):* przeniesienie `terminal:` zdarzeń do procesu od razu — około 130 miejsc
   wobec około 10 przy statusie; `terminal:` zdarzeń znika w P2h razem z modułem procesu.
3. **Zaufane wejścia:** najpierw `supplied_by: :host`, potem `reads:` z `given_entity`. *Odrzucone:* tylko
   `supplied_by:`; od razu `reads:`.
4. **Mapa kontekstów jako błędy L3.** *Odrzucone:* ostrzeżenia L5; bez wiązania.
5. **DD0 na gałęzi od `docs/esdm-analysis-oct4`** (lokalna, niewypchnięta; jej dwa commity z trzecią analizą ESDM
   wchodzą razem z DD0). *Odrzucone:* czekać na jej merge; pominąć ją.
6. **Stałe uprawnienia sesji z 5 października:** commity bez pytania na gałęziach etapu przy zielonej bramie;
   push, PR, merge i tag tylko na wyraźne polecenie. Obowiązuje tylko w tamtej sesji — patrz „Zgoda i stałe
   uprawnienia”.

Wycofane propozycje asystenta, po przeglądzie merytorycznym 4 października: zmiana nazwy `entity` (zostaje — to
encja w sensie Evansa, z cyklem życia poza logiem; poprawia się definicja); osobny rodzaj dla jednostki bez decyzji
(zamiast niego znacznik „tylko rejestruje” i reguła L5 w etapie L2 — osobny rodzaj zalegalizowałby jednostkę bez
reguł, a `ksef_inbox` nie ma deduplikacji tylko dlatego, że nie miała czytelnika w E9); zmiana `process` /
`process_manager` (oba terminy ustalone). Decyzja z gałęzi `docs/esdm-analysis-oct4` stoi: etykieta timera
wymagana i pozycyjna (etap N3 = EP6). Uwaga asystenta do rozważenia przed N3: zdanie timera składane z deklaracji,
jak zdanie obietnicy, nie dryfuje względem `wait:`; jeśli etykieta zostaje, nazywa cel („Termin dokumentacji”), nie
czas („Doba na dokumentację”).

### Postęp — jedyne miejsce, gdzie żyje stan programu

Zakres jest duży, a kontekst sesji będzie się często zmieniał, więc stan żyje tutaj, nie w rozmowie:
- **Start etapu:** status ◐ i nazwa gałęzi w tabeli, w pierwszym commicie etapu.
- **Pytanie z tabeli „Do decyzji przed etapem”:** odpowiedź użytkownika jako „### Przed <ID> — decyzje użytkownika
  (data)”, z odrzuconymi opcjami.
- **Koniec etapu:** „### <ID> — co wyszło (data)” pod tym dopiskiem (gałąź, rozstrzygnięcia mechaniki z
  odrzuconymi, przegląd, brama); po merge'u status ☑ i numer PR-a.
- **Koniec sesji:** tabela i blok „Handoff” na górze pliku pokazują następny etap; w rozmowie nie zostaje nic, czego
  nie ma tutaj.
- **Po każdej fali:** decyzja użytkownika „dalej czy stop”, tag wersji, notatka migracyjna dla aplikacji testowej
  AppUnite (`~/Projects/ai/appunite_equipment`) i `ehos-ledger`.
- **Kolejność w fali 1:** N1 → N2 → N3, reszta w dowolnej kolejności; etapy bez wspólnych plików mogą iść równolegle
  w osobnych worktree.

☐ nie zaczęte · ◐ w toku · ☑ w `main`

| Etap | Fala | Zakres | Zależy od | Status |
|---|---|---|---|---|
| DD0 | 0 | program i postęp w `PLAN.md` | — | ☑ #135 |
| N1 | 1 | `final:`, `target`, `identity` encji, definicja encji | DD0 | ☑ #137 |
| N2 | 1 | `subscribe "<nazwa>"` | DD0 | ☑ #138 |
| N3 | 1 | etykieta timera (EP6) | DD0 | ◐ `dsl/n3-timer-label`, PR #139 |
| W1 | 1 | zapis `schema_version` | DD0 | ◐ `engine/w1-schema-version`, PR #142 (na #139) |
| W2 | 1 | tagi dnia przy dopisie | DD0 | ◐ `engine/w2-day-tags`, PR #143 (na #142) |
| W3 | 1 | publiczne, czyste jądro `Trace` | DD0 | ☐ |
| W4 | 1 | `Decision`, `Lifecycle.allowed/3`, `Lifecycle.moves/3` | DD0 | ☐ |
| T1 | 1 | `supplied_by: :host`, F10, `Supplier` | DD0 | ☐ |
| T1s | 1 | sandbox: `p1_reported`, `total` | T1 | ☐ |
| X1 | 1 | reakcja `:in_transaction` między kontekstami | DD0 | ☐ |
| S4 | 1 | `transition-without-scenario` | DD0 | ☐ |
| ID1 | 2 | `id:` kontraktu deklarowany | N1 | ☐ |
| ID2 | 2 | każdy kontrakt z `id:` | ID1 | ☐ |
| ID3 | 2 | `id:` wymagany, typ `"<id>.<zdarzenie>"` | ID2 | ☐ |
| ID4 | 2 | wiersze i klucze po `id` | ID3 | ☐ |
| P1a | 2 | kroki per kontrakt, procesy osobno (wire v3) | ID3 | ☐ |
| P1b | 2 | nic nie zakłada procesu | P1a | ☐ |
| P1c | 2 | R1: najwyżej jeden proces | P1b | ☐ |
| P1d | 2 | sandbox bez sztucznych procesów | P1c, decyzja o `cadence` | ☐ |
| P1e | 2 | testy bez szablonowych procesów | P1c | ☐ |
| P2a | 2 | jeden model procesu dla czytelników | P1d | ☐ |
| P2b | 2 | DSL `EhOsContract.Process` | P2a | ☐ |
| P2c | 2 | L3 procesu, `_event_runs` z indeksu | P2b, ID4 | ☐ |
| P2d | 2 | raporty, wdrożenia, `check` po procesach | P2c | ☐ |
| P2e | 2 | grafy i strony procesu | P2d | ☐ |
| P2f | 2 | procesy sandboxa jako moduły | P2d | ☐ |
| P2g | 2 | rigi i testy o procesach | P2d | ☐ |
| P2h | 2 | stare słowa i kolumny znikają (migracja) | P2f, P2g | ☐ |
| M1 | 3 | mapa kontekstów L3, wartości jako referencje | P2h | ☐ |
| T2a | 3 | `reads:`, decyzja z trzema argumentami, `inputs` | N1 | ☐ |
| T2b | 3 | `given_entity` | T2a | ☐ |
| T2s | 3 | sandbox: `book_visit` czyta usługę | T2b | ☐ |
| A1 | 3 | `actor_is` | T1 | ☐ |
| A2 | 3 | Rehmed AGG-02 inw. 3 | A1, T2s | ☐ |
| B2 | 3 | kubełek w `match:` | W2 | ☐ |
| B3 | 3 | DCB z generowaną tożsamością | DD0 | ☐ |
| B4 | 3 | Rehmed: rezerwacja jako DCB | B2, B3 | ☐ |
| S2 | 3 | scenariusze obietnic | W3, P2b | ☐ |
| S3 | 3 | sandbox: scenariusze obietnic | S2, P2f | ☐ |
| O1 | 3 | kolejność etapów w przebiegu | P2d | ☐ |
| O2 | 3 | ekran: kolejność etapów | O1 | ☐ |
| V1 | 4 | upcasty deklaratywne | W1, P2h | ☐ |
| V2 | 4 | upcast przez callback | V1 | ☐ |
| V3 | 4 | zamek schematów | V1, przebudowy sandboxa | ☐ |
| V4 | 4 | zamek wobec upcastów | V3 | ☐ |
| V5 | 4 | wersja umowy i wersja tekstu | P2h | ☐ |
| PC1 | 4 | generatory (StreamData opcjonalne) | W4 | ☐ |
| PC2 | 4 | `PropertyCase` | PC1, T2a, A1 | ☐ |
| L1 | 5 | słownik połączony z kodem | N1 | ☐ |
| L2 | 5 | rdzeń: reguły i znacznik „tylko rejestruje” | DD0 | ☐ |
| L3 | 5 | typowane referencje do agregatów | ID3 | ☐ |
| L4 | 5 | widok właściciela bez adnotacji technicznych | P2e | ☐ |

### Program — szczegóły etapów

Numery linii w nawiasach odnoszą się do `origin/main` = `303b418` (4 października) i przesuwają się z kolejnymi
zmianami — nazwa funkcji jest ważniejsza niż numer.

#### Fala 1 — fundamenty (małe, niezależne)

**N1 — zmiany nazw** (mechaniczne, jeden PR na słowo albo jeden ze słowami osobno w commitach)
- Status `terminal:` → `final:`: `contract/dsl.ex` `@status` (493-497), `rules/lifecycles.ex` T3/T4,
  `lifecycle.ex` `index/1`, `graph/lifecycle.ex`, `computers.ex` (4), web fixture `case_handling.ex`, testy LC.
- Scenariusz `scope` → `target`: `dsl.ex` `Scenario` (277-290, schemat 1117), `rules/scenarios.ex` S1
  (`target/2`, `resolved/4`), `build.ex` `scenario/2` (klucz surowy znika, zostaje rozwiązany `target`); sandbox 10,
  testy 23.
- Encja `identified_by:` → `identity` (wstrzykuje `:id`, wymagane, nieosobowe): `domain/dsl.ex` `@entity`
  (330-345), `domain/rules.ex` D6 (`entity_shape/2` upraszcza się), `pages.ex`, `graph/contract.ex`; nowa
  definicja: „encja, której cykl życia prowadzi kod aplikacji albo inny system, poza tym logiem; kontrakty
  wskazują ją przez tożsamość”. `docs/contract.md` — zdanie, że to encja w sensie Evansa z cyklem życia poza logiem.
- Każde słowo: `vocabulary` pin (`test/dsl/*_vocabulary_test.exs`), `.formatter.exs`, `docs/dsl/`, CHANGELOG
  („a host has to act”), dopisek z datą w `docs/adr/contract-v2.md` §4.2.

**N2 — `subscribe "<nazwa>"`**: osobna encja w `dsl.ex` (dziś jedna `@consumes` 844-867 z `from: atom | string`);
`consumes` przyjmuje tylko moduł. Przepiąć `Rules.received/1` (rules.ex 104-110), D11/D12 (`rules/boundaries.ex`
70-90, 224-264), A4/R4, `Build.consumes/1`, `Implementations.inboxes/2`, `Model.subscriptions/1` (capability
`<nazwa>.subscribe` bez zmian). Sandbox 0, testy 13 + `bus_rig/stock.ex` + auth 1.

**N3 — etykieta timera (EP6, decyzja z gałęzi)**: `@timer` z `args: [:name, :label]`; ~24 deklaracje w testach,
2 w sandboxie (etykiety z materiału), przykład ADR §4.6 przez `@amendments` w `contract_examples_test.exs`.
Wytyczna w skillu `write-reaction`: etykieta nazywa cel („Termin dokumentacji”), nie czas.

**W1 — `schema_version` zapisywany**: `Dispatcher.entry/4` (1232-1262) ustawia `schema_version`;
`Consumer.decode!/5` odmawia wiersza z wersją wyższą niż deklaracja. Bez zmian wersji kontraktów.

**W2 — tagi dnia przy dopisie**: `Dispatcher.tags/3` (1268-1272) dodaje dla każdego wymaganego, nieosobowego pola
`:date`/`:timestamp` tag `"<pole>.day:YYYY-MM-DD"` (UTC); `Key.bucket_field?/2`, `Key.day_tag/2`. Ten sam powód co
EM1: log jest tylko do dopisywania, starsze zdarzenia nigdy nie dostaną tagu.

**W3 — publiczne, czyste jądro `Trace`**: `Trace.trace/2` (z `evaluate_promise/3` 150-177) i
`Trace.judge(trace, occurrences, now:, outages:, identity:)` nad prywatnymi `verdict/6` (344-371) i `aggregate/2`
(276-288); `evaluate/3` = wiersze z bazy → `judge/3`. Test bez bazy. Raport bajt w bajt ten sam.

**W4 — wspólne reguły decyzji**: publiczne `Lifecycle.allowed/3` i `Lifecycle.moves/3` (dziś prywatne `index/1`,
`allowed/3` 160-176); moduł `EhOsContract.Decision` (`admitted/5`, `held!/6`) z kodu `emitted!/2` (1182-1217),
`lifecycle!/4` i kopii w ScenarioCase (`within!/5`, `in_lifecycle!/4`); `Contract.Data.cast/3` z prywatnego
`cast/3` ScenarioCase. Refaktor bez zmiany zachowania.

**T1 — `supplied_by: :host`**
- `dsl.ex` `Field` + `@field`; model trzyma klucz tylko gdy ustawiony.
- **F10** (L2, `rules/fields.ex`): tylko pola komendy i zdarzenia z `recorded_by:`; nie na polu `scope:`.
- Drzwi: `Dispatcher.prepare/5` (394-406) — pole obecne w wejściu (także `null`) to `{f, :supplied}` (422), po
  `permit_undecoded/5` (403 przed 422). Wartość daje behaviour hosta `EhOsContract.Supplier` (`supply/2`, wzorzec
  `Authorizer`: `impl/0` z konfiguracji, `run/4` sprawdza klucze i `Codec.problems/4`, błąd nazywa pole, nie wartość).
  `dispatch/3` z kodu hosta ufa strukturze.
- D9 `@refusals` (+ `:supplied`), `OpenAPI.command_fields/2` pomija pole, `json_schema.ex`, `pages.ex`.
- **T1s** sandbox: `close_visit_clinically.p1_reported`, `close_settlement.total` + `SBX/lib/eh_os_contract_host/
  supplier.ex`; `rehmed_authorization_test.exs` oczekuje `{"invalid": {"p1_reported": "supplied"}}`.

**X1 — reakcja `:in_transaction` na zdarzeniu innego kontekstu**: L3 obok `x5/3` w `contract/links/siblings.ex`
(kontekst siostry jest w `Links.contract/1`): błąd, gdy `delivery` niezadeklarowane (domyślne w `dsl.ex` 627, 743
zmienić na `nil` rozwiązywane w `Build`), ostrzeżenie L5 `in-transaction-across-contexts`, gdy jawne. Sandbox:
`report_on_clinical_close`, `month_opens_on_consistent_registry` dostają jawne `delivery:` (+ `idempotency` przy
`:at_least_once`, P3).

**S4 — `transition-without-scenario`** (L5): `check/catalog.ex` + `completeness.ex` `untaken_transitions/1` —
przejście pokazane, gdy scenariusz komendy (nie `rejected`) z `given` dochodzącymi do `from` (`Lifecycle.walk/2`)
oczekuje zdarzenia, które je wykonuje (`Lifecycle.decided!/4`); przejścia ze zdarzeń tylko rejestrowanych pomijane.
AppUnite: dopisać scenariusze albo wyjaśnić ostrzeżenia w PR.

#### Fala 2 — tożsamość i proces

**ID1 — `id:` kontraktu, deklarowany i sprawdzany**: `use EhOsContract.Contract, id: "rehmed.settlement"`
(`contract.ex` 44-68), poza digestem. D11 (L2 format: pierwszy segment = `name:` domeny, potem snake_case, bez
`:`/`|`, ≤ ~100 B; L3 w `Links.Domain.namespaces/1`), X7 unikalność.
**ID2 — każdy kontrakt nazywa `id:`** (mechaniczne, ~120 linii): `DslCase.contract/2` (`test/support/dsl_case.ex`
42-51), rigi, 11 kontraktów sandboxa, fikstury web/auth, README, `docs/contract.md`.
**ID3 — `id:` wymagany; typ zdarzenia `"<id>.<zdarzenie>"`**: jedno miejsce — `Build.event/4` (build.ex 200-209).
Literały typów w `test/runtime/*` i `sandbox/test/*`, przepięcie dwóch wersji (`sources_test.exs:17`,
`contract_domain_services_test.exs:315`), `@amendments` dla `use` z ADR §4.5. Dopisek do D1 w ADR §16.
**ID4 — wiersze i klucze po `id`** zamiast `inspect(module)`: Dispatcher (`entry/4` 1238, `write_row!/4` 1320,
`idempotent/2` 1004, klucz 260), `TimerJob` 116, `Personal` 243 (`"eh_os_contract"`), `Deployment` (133, 170, 293),
`Dependency` (113, 143), `Paths` (340, 361, 396, 517), `Conformance` (252, 382), `Coverage` 114; klucze konsumentów
`"<id>:<rodzaj>:<nazwa>"` (`implementations.ex` 284, 372, 420; `consumer.ex` 210, 287; `process_manager.ex` 150;
`paths.ex` 277); `Consumer.decode!(consumer, row)` bez `row.contract`; API web po `id`.

**P1a — kroki per kontrakt, procesy osobno** (przesuwa werdykty): `paths.ex` liczy wystąpienia, nie przebiegi
(`runs` → `taken`, `Paths.activity/2`); `Conformance.from_model/2` → `%{contract, module, activity, paths,
lifecycles, scenarios, drift}`, `Conformance.process/2` = dzisiejszy `process_report`; wire
`eh_os_contract.conformance.v3`; `report.ex`, `report/sentence.ex`, graf, `contract_status_live.ex`.
**P1b — nic nie zakłada procesu**: manifest auth (`manifest.ex:259`, pole `"process"` → id kontraktu + issue w
`eh-os`), `graph_live.ex` 46-75, `events_without_consumer` liczy zdarzenia cyklu życia jako czytane.
**P1c — R1: najwyżej jeden proces**; bez procesu grupa etapu albo `terminal:` zdarzenia odrzucone. Dopisek z datą
do wymagania 7 (v2 §3).
**P1d — sandbox bez sztucznych procesów** (PR na domenę): Rehmed `scheduling`, `clinical_documentation`,
`settlement`; TaxVision `document_intake`, `registry_watch`; AppUnite `computers`, `demands`. Zostają:
`clinical_visit`, `accounting_month`, `assignments`, `payer_settlement` (do decyzji o `cadence`). Każde nowe
`event-without-consumer` wyjaśnione w PR.
**P1e — testy deklarują proces tylko tam, gdzie są o procesie** (szablonowe bloki `process`/`terminal:`/`stage`;
bez `sources_test`).

**P2a — jeden model procesu dla czytelników** (refaktor): `Model.process/1`, `Model.process_events/1`; przepiąć
`Run.runs_of/1`, `Trace`, `Paths.runs_of/3`, `Conformance.process/2`, `Graph.declared/2`, `Check.process_findings/1`,
`Check.Contracts.backward/1`, `events_without_consumer`, `Deployment.row/2`, `Implementations.included/1`, `Pages`.
Odbiór: raport i `graph --overlay` sandboxa bajt w bajt.
**P2b — DSL `EhOsContract.Process`** (kompilacja): `lib/eh_os_contract/process.ex`, `process/{dsl,rules,build}.ex`;
`use … id:, domain:, label:, accountable:, source:`; `correlate`, `stage name, label, include: [{Kontrakt, ev |
[ev]}]` (`no_depend_modules` jak `consumes`), `ends_on [..]`, `promise`, `deadline`. L2: R2/R3/R5/R6/F9/D11/N1.
`docs/dsl/process-dsl.md`, formatter, `docs_test` `@layers`. Uwaga: nigdy aliasować w bibliotece (kolizja z
`Process` Elixira).
**P2c — powiązania i przebiegi**: L3 `contract/links/processes.ex` (X1, X2, X5, X6 przez
`Links.Siblings.problems/4`, X7, D11); indeks typ → procesy w `Implementations.build/1`; dispatch pisze
`_event_runs` dla każdego procesu obejmującego zdarzenie (`included_runs/3`).
**P2d — raporty, wdrożenia, `check` po procesach**: wiersz `Deployment` na proces (granice deklaracji obietnic),
L5 po procesach (`deadline-without-terminal-event` = „bez `ends_on`”), zdarzenie czytane przez proces.
**P2e — grafy i strony procesu**: `Graph.process_to_mermaid/2`, `graph --process <id>`, selektor w `graph_live`,
`pages` `processes/<id>.md`, `View`.
**P2f — procesy sandboxa jako moduły** (PR na domenę): `Rehmed.Processes.ClinicalVisit`,
`Taxvision.Processes.AccountingMonth`, `AppuniteEquipment.Processes.Assignment` (kontrakt `Assignments` znika).
**P2g — rigi i testy o procesach** (`ProcessShapes`, `DispatchRig.Branch`, `KeyRig.Audit`, `UniversalityGate`,
`LifecycleRig`, fikstury web/auth).
**P2h — stare słowa i kolumny znikają**: z DSL kontraktu `@process`, `@include`, etapy w jednostkach, `terminal:`
zdarzenia; reguły R1/R4 i procesowe części R2–R6, `Rules.Fields.correlated/1`; **migracja** (V02 albo V01 w
miejscu — decyzja niżej): usunąć `process`/`instance_id` z `_events` i `_commands`; `@amendments` ADR §4.5; dopiski z datą w ADR §10.3, §13, D5, D7;
skille `add-event`, `change-contract`, `contract-distillation`, `module-boundary-check`. Odbiór: grep `terminal:` w
zdarzeniach, `process :` i etapów w jednostkach = 0.

#### Fala 3 — granice i decyzje

**M1 — mapa kontekstów jako L3** (+ punkt 6: wartość z `context:` w innym kontekście = referencja)
| Relacja | Co wolno odbiorcy (`consumes`) |
|---|---|
| `conformist`, `shared_kernel`, `partnership`, `customer_supplier` | wszystko jak dziś |
| `anticorruption_layer` | zdarzenie dostawcy bierze tylko polityka (tłumacz) |
| `open_host_service`, `published_language` | tylko zdarzenia, które dostawca `publish`uje, w kształcie publikacji |
| `separate_ways` | nic |

Kierunek i `separate_ways` awansują z L5 na L3; „brak relacji” zostaje ostrzeżeniem L5. Włączenie zdarzenia do
modułu procesu nie jest referencją. Kod: nowa grupa L3 obok `crossings/2` (`completeness.ex` 722-745 rozwiązuje
kontekst siostry). Sandbox: poprawić relacje albo kontrakty i powiedzieć to w PR.

**T2a — `reads: [service: :service_id]`**: opcja komendy; **A8** (L2): pole komendy typu `{:id, encja}`;
behaviour `EhOsContract.Entities` (`fetch/3`, `impl/0`, `UnfitRowError`); dispatch czyta raz na komendę (retry
używa tych samych wierszy), `:not_found` → `{f, :unknown}` (422, D9); **decyzja dostaje trzeci argument**
`(command, state, reads)` — `callbacks.ex` `of/3`, I2, `decide/7`; kolumna `inputs :map` w `_commands`
(migracja jak w P2h) — encje nie mają pól osobowych (D6). *Odrzucone (mechanika):* `Meta.inputs` (Meta znaczy kto/kiedy i
wraca z logiem), wstrzyknięcie do stanu.
**T2b — `given_entity`**: encja scenariusza, **S12** (L2), rozszerzenie X9; gałąź agregatu w `scenario_case.ex`
(443-507) woła z arnością 3.
**T2s — sandbox**: `book_visit` czyta `:service` i utrwala flagę P1 w `visit_booked` (AGG-15, w chwili rezerwacji).

**A1 — `actor_is`**: podencja komendy `actor_is :specialist_id, or_rejects: :inwariant`; **A9** (L2: pole stanu
`:id`, nieosobowe; inwariant w `rejects:`; nie na `creates:`; komenda z `by:`); X2: `by:` ma aktora `:human`.
Dispatch po `fold/6`, przed `decide/7` (attempt/2 783-805), tylko dla aktorów z credentialem (`:system` i reakcje
przechodzą); odmowa jak bramka LC2 (wiersz `rejected`). Scenariusz `actor :specialist, as: "specialist-ewa"`
(makro jak `Generated.identity/2`, nie `subject:`), S7 rozszerzone.
**A2 — Rehmed AGG-02 inw. 3**: `visit_completed` dostaje `specialist_id` z `supplied_by: :host` (supplier wpisuje
`actor.subject`); dokumentacja wizyty staje się DCB konsultującą `visit_completed` i `visit_booked` po `visit_id`
(bez nowych nazw zdarzeń — nazwy tylko z warsztatu), więc stan zna specjalistę i flagę P1 utrwaloną przy
rezerwacji (T2s): `close_visit_clinically` dostaje `actor_is`, a pole `p1_reported` znika z komendy. Zamknąć
ustalenie z E9a.

**B2 — kubełek w `match:`**: `consults :visit_booked, match: [:specialist_id, scheduled_at: :day], for:
:book_visit`; `boundary/3` (1064-1075) liczy tag z pola komendy (`Key.day_tag/2`) — bez pola wyliczanego przez
wołającego; A4/X6 rozszerzone.
**B3 — DCB z generowaną tożsamością** (rozluźnić A6; `generate_identity/4` już czyta jednostkę).
**B4 — Rehmed: rezerwacja jako DCB** `dcb :visit, identity :visit_id, generated: :uuid`, inwariant
`:one_visit_at_a_time_per_specialist`, `ends_at` w rezerwacji; scenariusze: kolizja odrzucona, styk dozwolony,
odwołany termin wolny, inny specjalista dozwolony; test wyścigu jak w EM1.

**S2 — scenariusze obietnic** (w modułach procesu): wyzwalacz `promise :nazwa, at: "…"`, `given … at:`, `outage
:p1, at:`, wynik `verdict:` (`:satisfied | :violated | :pending | :suspended`) i `via:`; S1/S2/S3 rozszerzone,
**S11** (kształt), X4 (awaria systemu, od którego zależy zdarzenie); ScenarioCase woła `Trace.judge/3` (W3).
**S3 — sandbox**: obietnica `medical_event_reported_within_statutory_window` (spełniona przez wysłanie, przez
`or_else`, złamana po 2 dniach, zawieszona przy awarii P1); TaxVision `month_opens_or_is_blocked`.

**O1 — kolejność etapów w przebiegu**: `lib/eh_os_contract/stage_order.ex` — pierwsze zdarzenie późniejszego
etapu przed pierwszym zdarzeniem wcześniejszego (który w przebiegu wystąpił); pominięty etap nie jest ustaleniem;
zapytanie po `_event_runs` ⋈ `_events` (min pozycja na przebieg i typ); klucz `out_of_order` w raporcie procesu,
`Sentence.out_of_order/1`, wire addytywnie. **O2**: ekran statusu.

#### Fala 4 — ewolucja modelu i testy właściwości

**V1 — upcasty deklaratywne**: encja `upcast from, rename: [stare: :nowe], default: [pole: wartość]` w `event`;
**V1** (L2, `rules/versions.ex`): `from` pokrywa `1..schema_version-1`, bez tożsamości, bez domyślnej wartości dla
pola osobowego. `lib/eh_os_contract/upcast.ex` w `Consumer.decode_all!/3` (154-178) przed `Codec.subjects`
(159); aliasy ścieżek dla `Personal.opener/3` (AAD = typ|ścieżka|…, personal.ex:594); obejścia: `Relay.message/2`
(75-90), `Trace.item_occurrences/4` (tylko tożsamość, chroniona przez V1).
**V2 — upcast przez callback** `with: :funkcja` w implementacji jednostki (I2), strażnik: zaplombowane wartości
wychodzą nietknięte.
**V3 — zamek schematów** `eh_os_contract.lock` w katalogu projektu hosta (obok `mix.lock`), JSON kluczowany typem
zdarzenia; `mix eh_os_contract.schema [--check | --forget TYP]`; w bramie sandboxa po `eh_os_contract.check`;
rigi biblioteki bez zamka (logika testowana na mapach w pamięci).
**V4 — zamek wobec upcastów**: zmiany zgodne (pole opcjonalne dodane, usunięte, wymagane → opcjonalne, nowy członek
enuma, `:integer` → `:decimal`) bez nowej wersji; reszta wymaga `rename:`/`default:`/`with:`; zmiany osobowości
i tożsamości nieobsługiwane. Przykład z materiału: `amount_minor` → `amount` z wartością z `unit:` (TaxVision).
**V5 — wersja umowy i wersja tekstu**: `version` (pola, komendy, `emits`/`rejects`/`by`, nazwy reguł, cykl życia,
obietnice) i `text_digest` (etykiety, `source:`, scenariusze) w `Build.version/3`/`digests/3`; `Deployment` zapisuje
obie; raport rozróżnia „zmieniła się umowa” od „zmieniły się słowa”.

**PC1 — generatory** (`{:stream_data, "~> 1.1", optional: true}`, moduł w `if Code.ensure_loaded?(StreamData)`
jak `plug.ex`): wartości w granicach `Codec`, wartości dziedziny z `satisfied_by`, `command/3`, `event/3`,
`entity_row/3`, `history/3` (spacer po `Lifecycle.moves/3`).
**PC2 — `use EhOsContract.PropertyCase, contract: C, max_runs: 50`**: `evolve/2` totalne na legalnych historiach;
decyzja nie rzuca na legalnym wejściu i mieści się w `Decision.held!/6`; status zgodny z grafem; opcjonalne
`holds?/2`. Odbiór: celowy defekt `reopen_visit` w `LifecycleRig` złapany; sandbox `rehmed_settlement` z `holds?/2`.

#### Fala 5 — język i rdzeń

**L1 — słownik połączony z kodem**: opcja domeny `code_language:` (domyślnie `:en`); tłumaczenie terminu na ten
język wyznacza słowo identyfikatorów; strona słownika: termin → deklaracje; L5 `word-without-term` (notka, ranking
po częstości), `term-of-another-context` (ostrzeżenie).
**L2 — rdzeń**: L5 `core-command-never-refuses` (komenda kontekstu `:core` bez `rejects:`/`or_rejects:`, poza
wydawanymi przez reakcje) i `core-unit-records-only`; znacznik „tylko rejestruje” na stronach i grafie.
**L3 — typowane referencje do agregatów** `{:id, :visit}`: X3 przyjmuje nazwę jednostki domeny (nazwa musi być
jednoznaczna w domenie), `refers_to` dla jednostek, `crossings/2` je liczy, graf je rysuje.
**L4 — widok właściciela**: `pages` i graf procesu bez `delivery`, `idempotency`, F8/F9.

---

#### Konwencje każdego PR-a

- Nowy klucz modelu tylko tam, gdzie ustawiony (`build.ex` `command/2` 174-192, `without_empty/2`), test, że
  nietknięty kontrakt zachowuje wersję.
- Nowy kod odmowy: komunikat `"KOD: "` w rules/links, wiersz w `docs/contract.md`, asercja w `test/dsl/**`
  (`test/docs_test.exs` tego pilnuje). Nowe kody: F10, A8, A9, S11, S12, V1 (+ rozszerzenia S1–S3, S7, A4, A6, D9,
  X2, X4, X6, X9).
- Nowe słowo DSL-a: `doc:`, `MIX_ENV=test mix eh_os_contract.docs`, `mix spark.formatter --extensions …`, skasować
  `cached_dot_formatter` w sandboxie i web.
- Reguła L5: wpis w `check/catalog.ex`, funkcja w `check/completeness.ex` albo `check/contracts.ex`,
  `mix eh_os_contract.rules`, test `test/check_*` z kontrolą.
- `@doc` i `@spec` na publicznych funkcjach; eksporty `boundary`.
- Zapisy: CHANGELOG (werdykt → MINOR; „a host has to act”), `PLAN.md` po polsku z odrzuconymi opcjami, dopiski z
  datą w `docs/adr/contract-v2.md` (przykłady kompilowane — `@amendments`), skille.
- Schemat bazy zmieniają tylko T2a i P2h (V02 albo V01 w miejscu): odtworzyć bazy testowe, przywrócić wspólną
  bazę po bramie (pułapka z `CLAUDE.md`).
- Skill `review-pr`: dopisać nowe pliki przesuwające werdykty (`stage_order.ex`, `upcast.ex`, `process/*`).

#### Weryfikacja

- Każdy PR: `mix check` pakietu i brama sandboxa (EXIT=0), testy odmów z kontrolą (`DslCase`), runtime
  (`DataCase`), scenariusze sandboxa.
- Refaktory bez zmiany zachowania (W3, W4, P2a): `mix eh_os_contract.report` i `graph --overlay --mermaid` sandboxa
  bajt w bajt przed i po (skrypt w scratchpadzie).
- PR-y przesuwające werdykty (P1a, P2d, P2h, O1, X1): diff raportu i `check`; zmieniają się tylko zamierzone linie;
  każde nowe ostrzeżenie wyjaśnione.
- Ekrany (P1a, P2e, O2): podgląd hosta sandboxa (`/dashboard`, port 4010), zrzut ekranu.
- Odbiory fal: (1) Plug odrzuca `p1_reported` (422), dwie reakcje między kontekstami mają jawne `delivery`;
  (2) `clinical_visit` jako moduł procesu, raport: kontrakty i procesy, zero `terminal:` w zdarzeniach;
  (3) dziesięć rezerwacji tego samego terminu → jedna przyjęta; scenariusze obietnic bez bazy; rig z relacją ACL
  odrzuca read model na zdarzeniu dostawcy (sandbox nie ma ACL między kontekstami); `close_visit_clinically` bez
  pola `p1_reported`; (4) zmiana pól bez `schema_version` nie przechodzi
  `eh_os_contract.schema --check`; `PropertyCase` łapie defekt rigu.

#### Do decyzji przed etapem (rekomendacja domyślna)

| Przed | Pytanie | Domyślnie |
|---|---|---|
| T2a, P2h | migracja: nowa wersja V02 czy edycja V01 w miejscu (od 4 października aplikacja testowa AppUnite ma bazę) | V02 |
| P1d | `cadence`: oceniać (okno bez przebiegu) czy usunąć | usunąć; wraca z czytelnikiem |
| P2b | `use EhOsContract.Process` wymaga `id:` i `label:` | tak |
| P2b | `deadline` bez `ends_on` | błąd L2 w module procesu |
| P1b | pole `"process"` w manifeście EHOS-a | id kontraktu + issue w `eh-os` |
| P1e | sprzątanie szablonowych procesów w testach | tak |
| W2 | tagi miesiąca obok tagów dnia | tylko dzień |
| T2a | `reads:` po polu stanu, nie tylko komendy | później |
| S2 | `at:` przy `given` poza scenariuszami obietnic | dozwolone |
| A1 | wyjątek dla roli (menedżer) w `actor_is` | poza zakresem |
| M1 | kształt konsumpcji `publish` w jednej aplikacji | `consumes` wskazuje publikację, silnik podaje kształt publikacji bez brokera |
| V3 | plik zamka: nazwa i miejsce | `eh_os_contract.lock` w katalogu projektu |
| L3 | składnia referencji do agregatu | `{:id, :visit}`, nazwa jednostki jednoznaczna w domenie |

#### Ryzyka

- Wspólny Postgres wszystkich worktree (migracje V01 w T2a i P2h, typy w ID3/ID4) — odtwarzać i przywracać bazy.
- Aplikacja testowa AppUnite i `ehos-ledger` łamią się na falach 1–2 — notatka migracyjna i tag po każdej fali.
- Proces dodany po historii nie ma przebiegów dla starych zdarzeń — zmierzyć zdarzenia bez wiersza `_event_runs`;
  później `mix eh_os_contract.runs --rebuild`.
- `EhOsContract.Process` obok `Process` Elixira — bez aliasu w bibliotece.
- Czas bramy (PropertyCase — małe `max_runs`), koszt zapytań kolejności etapów (indeks `(process, instance_id)`).
- Zakres: ~45 PR-ów. Po każdej fali decyzja „dalej czy stop” w `PLAN.md`.

### N1 — co wyszło (5 października)

Gałąź `dsl/n1-names` (na `docs/dd0-programme`, bo DD0 to jeszcze PR #135). Trzy słowa, każde osobnym commitem
na zielonej bramie, każde z wpisem w CHANGELOG („a host has to act”, przesuwa wersję) i jednym dopiskiem z datą w
`docs/adr/contract-v2.md` §4.2.

- **`final:` na statusie** (`e7383ed`). `terminal:` zdarzenia zostaje do P2h. Komunikaty T3, T4 i odmowy
  dispatchu mówią „final”. Przesuwa wersję każdego kontraktu z cyklem życia (AppUnite `Computers`, `Demands`).
- **`target` w scenariuszu** (`d00921f`). Zamiana tylko w blokach `scenario` (skrypt z kontekstem; `scope`
  komendy i query nietknięty, ~25 miejsc pominiętych świadomie). Model traci surowy klucz `scope`, zostaje
  rozwiązany `target`. Przesuwa wersję każdego kontraktu ze scenariuszem; przypięta wersja `DispatchRig.Ledger`
  `06808eb90e9f` → `2d4f6e4d01fe`.
- **`identity` encji** (`e40ead9`): biblioteka wstrzykuje pole jako pierwsze w modelu encji (wymagane,
  nieosobowe `:id`, kształt jak w jednostce); nowa definicja encji (Evans, cykl życia poza logiem) w opisie DSL-a,
  `contract.md` i dopisku ADR. **Rozstrzygnięcie asystenta (mechanika):** encja dostaje opcję `issued_by:`, bo pole
  tożsamości potrafiło mieć wydawcę (faktura z KSeF) i samo wstrzyknięcie by go zgubiło; model trzyma wydawcę na
  wstrzykniętym polu, więc graf i `domain_issuers` czytają go bez zmian, a D8 i reguła kierunku sprawdzają opcję
  encji. *Odrzucone:* makro `identity :x, issued_by: …` jak `generated:` w jednostce (więcej kształtu bez
  potrzeby — opcje w nagłówku encji wystarczą); pole tożsamości deklarowane ręcznie obok `identity` (przeczy
  decyzji 2 o wstrzyknięciu). D6: tożsamość w snake_case i bez pola o tej nazwie. Przesuwa wersję domeny Rehmed.
- **Przegląd** (dwa przeglądy równolegle na `docs/dd0-programme..dsl/n1-names`). Poprawność: brak błędów; 7 uwag —
  naprawione: odmowa D6 mówi, gdzie przenieść `issued_by:` pola, które było tożsamością (`1b67089`, próba odwrotna:
  bez podpowiedzi pada tylko ten test), wydawca dopasowany na `nil`, ustalenie kierunku nazywa encję, tekst
  katalogu reguł, nawiasy przy `target`, komentarz w teście słownika (`21a743e`); pominięte: wspólny helper
  pola tożsamości dla jednostki i encji (refaktor poza zakresem zmiany nazw). Bezpieczeństwo i wydajność: nic od
  średniej wagi; uwagi informacyjne — po zmianie wersji pusta lista dryfu (cecha każdego „Moves the version”, bez
  zmian) i wstrzyknięte pole bez `label:` (pominięte — wróci z przykładem).
- **Brama:** EXIT=0 na każdym commicie; `eh_os_contract.check` sandboxa 0 / 29 / 10, silnika 0 / 74 / 6; sandbox 194,
  silnik 1261, web 51, auth 285 + 1 property.
- **Dla aplikacji AppUnite i `ehos-ledger`:** `terminal: true` na statusie → `final: true`; `scope` w scenariuszu →
  `target`; `identified_by:` + pole → `identity:` (+ `issued_by:` na encji).

### Przed N3 — decyzje użytkownika (5 października)

**Etykieta timera — wymagana, pozycyjna, i nazywa cel, nie czas:** `timer :documentation_due, "Termin
dokumentacji", wait: {24, :hour}, …`. Czas mówi deklaracja (`wait:`/`at:`), a strony pokazują go obok etykiety, więc
etykieta nie dryfuje, gdy ktoś zmieni `wait:` z doby na dwie. *Odrzucone:* dowolny tekst klienta, jak w decyzji z
4 października („Doba na dokumentację” — dryfuje względem `wait:`); bez etykiety, ze zdaniem składanym przez silnik
z `wait:`/`at:` i `issues:`, jak przy obietnicy (N3 stałby się etapem stron i grafu, a timer dalej nie miałby
słowa klienta). Wytyczna „cel, nie czas” idzie do skilla `write-reaction`; sprawdzić jej nie da się.

### N2 — co wyszło (5 października)

Gałąź `dsl/n2-subscribe` (na N1). `consumes "<nazwa>"` → `subscribe "<nazwa>", as: …`; `consumes` znaczy już
tylko zdarzenia siostrzanego kontraktu z tego logu. Model bez zmian, więc **żadna wersja się nie przesuwa**; wpis w
CHANGELOG („a host has to act”), dopisek z datą w ADR §4.2, `contract.md`, skille `change-contract` i
`write-reaction`.

- **Rozstrzygnięcia asystenta (mechanika):** obie encje Sparka budują tę samą strukturę `Consumes`, z
  znacznikiem `via`, więc reguły (D11, D12, K1, N1), `Build` i model dalej rozróżniają je po typie `from`.
  *Odrzucone:* osobna struktura i osobna kolekcja w modelu (większy diff i przesunięcie wersji każdego kontraktu
  z subskrypcją, bez zysku dla hosta).
- **Stara forma dostaje odmowę z podpowiedzią.** Pierwsza wersja zawęziła `from:` `consumes` do modułu w schemacie
  — wtedy `consumes "…"` padało na „expected atom”, a pola i `as:` atomem na „undefined function field/2”.
  Przegląd to złapał: teraz K1 odmawia `consumes "<nazwa>"` zdaniem z deklaracją `subscribe` do napisania, a D11
  sprawdza tylko subskrypcje, więc stara forma jest odmówiona raz. *Odrzucone:* odmowa w schemacie (nie mówi, co
  napisać). D11 nie odmawia już listy zdarzeń — `subscribe` jej nie przyjmuje.
- **Przegląd** (`dsl/n1-names..dsl/n2-subscribe`). Poprawność: 6 uwag, wszystkie naprawione — odmowa starej formy
  (`via` + K1; próba odwrotna: bez niej pada tylko jej test), N1/F nazywają zdarzenie z innej aplikacji „subscribed
  event”, nieaktualne zdania w `dsl.ex`, `bus.ex`, `graph/system.ex`, `build.ex`, `consumes.ex`, `supervisor.ex`,
  `inbox.ex`, lokalizacja w asercji D11, ten zapis. Bezpieczeństwo i wydajność: nic; żadna ścieżka nie czyta
  zdarzenia opublikowanego jak siostrzanego ani odwrotnie, capability `<nazwa>.subscribe` i inboxy bez zmian.
- **Brama:** EXIT=0; `check` sandboxa 0 / 29 / 10, silnika 0 / 74 / 6; sandbox 194, silnik 1263, web 51, auth 286 +
  1 property.
- **Dla aplikacji AppUnite i `ehos-ledger`:** `consumes "<nazwa>", as: …` → `subscribe "<nazwa>", as: …`.

### N3 — co wyszło (5 października)

Gałąź `dsl/n3-timer-label` (na N2). `timer :documentation_due, "Termin dokumentacji", wait: {24, :hour}, …` —
etykieta wymagana, pozycyjna, nazywa cel (decyzja „Przed N3”). Czytelnicy: strona process managera (etykieta i czas
z deklaracji: „1 day after it is set”, „at `review_at`”), `@doc` callbacku, węzeł timera w grafie, a przez
`Paths` także zdania raportu zgodności i dashboardu o kroku timera. Przesuwa wersję każdego kontraktu z timerem
(przypięte wersje: `DispatchRig.Ledger` `2d4f6e4d01fe` → `ccaadcbebb04`, `sources_test` `0233079a0430` →
`fbeab3316603`). Wpis w CHANGELOG, dopisek z datą w ADR, przykład §4.6 przez `@amendments`, wytyczna w
`write-reaction`.

- **Etykiety sandboxa nie są z materiału** (wbrew projektowi etapu): „Termin dokumentacji” (Rehmed) to przykład
  użytkownika z decyzji przed N3, „Termin sprawdzenia rejestrów” (TaxVision) — propozycja asystenta z etykiety
  process managera. Do potwierdzenia przez właściciela procesu; przegląd to złapał. **Rozstrzygnięte 5 października**
  (po recenzji CodeRabbita na #139), decyzja użytkownika: TaxVision → „Weryfikacja rejestrowa”, słowa materiału
  (`02-event-storming.md` §3.1, „Otwarcie miesiąca: weryfikacja rejestrowa”), z `source:`; Rehmed zostaje przy
  „Termin dokumentacji”, zatwierdzone przez użytkownika jako właściciela procesu danych testowych — materiał nie ma
  tu polskiej nazwy (P-23 mówi o „statutory window”, klient proponował watchdog 48 h). *Odrzucone:* „Otwarcie
  miesiąca” (nazwa fazy, nie tego, co timer wywołuje); zostawić obie etykiety otwarte.
- **Przegląd** (`dsl/n2-subscribe..dsl/n3-timer-label`). Poprawność: 9 uwag — naprawione (`1523867`): CHANGELOG o
  zdaniach raportu i nieaktualny komentarz w `report/sentence.ex`, test odmowy timera bez etykiety i etykieta w
  asercji §4.6, polski przykład w komentarzu `dsl.ex`, porządek komentarzy i martwa gałąź w `pages.ex`, strzałka
  przy timerze bez `issues:`, podwójne szukanie timera w `doc.ex`, ten zapis i nieaktualne pytanie w Handoffie;
  pominięte: czas obok etykiety także w `@doc` i na grafie (rozszerzenie decyzji, nie jej wykonanie — do decyzji,
  jeśli strona nie wystarczy). Bezpieczeństwo i wydajność: nic; etykieta escapowana jak każda inna, nie trafia do
  harmonogramu, zadań Obana ani logu.
- **Brama:** EXIT=0; `check` sandboxa 0 / 29 / 10, silnika 0 / 74 / 6; sandbox 194, silnik 1264, web 51, auth 286 +
  1 property.
- **Dla aplikacji AppUnite i `ehos-ledger`:** każdy `timer :x, wait:/at: …` → `timer :x, "<cel>", wait:/at: …`.
- **Fala 1 po N3:** N1–N3 zrobione; zostają W1–W4, T1, T1s, X1, S4 w dowolnej kolejności.

### W1 — co wyszło (5 października)

Gałąź `engine/w1-schema-version` (na N3). Dispatch zapisuje `schema_version` zdarzenia w wierszu (do teraz każdy
wiersz miał 1, domyślną kolumny); odczyt wiersza nowszej wersji niż deklaruje działający kod rzuca
`EhOsContract.NewerSchemaError` (nazywa wiersz, nigdy wartość), sprawdzane przed czytaniem podmiotów z payloadu.
Wiersz starszej wersji dekoduje się jak dotąd — do upcastów (V1). Żadna wersja kontraktu się nie przesuwa; rig
`LifecycleRig` ma `:note_added` w wersji 2.

**Decyzja użytkownika (5 października), po przeglądzie: kod starszy niż wiersz czeka.** Subskrypcja, process
manager i relay stoją na wierszu nowym krokiem `{:waiting, position}` — nic się nie przesuwa, próba nie jest
liczona, runner próbuje co 5 s i rusza sam po aktualizacji węzła; efekt dostaje `snooze` 30 s (Oban 2.23 podbija
wtedy `max_attempts`, więc nie liczy); komenda na strumieniu z takim wierszem dalej odrzucona jako `failed`.
*Odrzucone:* tylko nazwany wyjątek, z liczeniem prób jak dziś (rozbieżność wersji przy wdrożeniu po kolei kończy
się subskrypcją `failing` na stałe, a wyjście przez `--skip` gubi reakcję, i odrzuconym zadaniem efektu); W1 tylko
zapisuje wersję, a odmowa razem z V1 (stary węzeł dalej czyta nowe pola ze starym znaczeniem, a relay publikuje je
innym aplikacjom).

- **Rozstrzygnięcia asystenta (mechanika):** relay sprawdza wersję w `Subscription.relay/2`, nie w
  `Relay.message/2` — ta zostaje czystą funkcją na zdarzeniu (testy budują je ręcznie); partia z nowszym zdarzeniem
  idzie zdarzenie po zdarzeniu, a relay staje na nim. Wpisy CHANGELOG programu DD (N1–N3, W1) przeniesione do górnej
  sekcji „Unreleased”, gdzie stoi wpis z #134 — wcześniej trafiały do sekcji 0.3.0.
- **Przegląd** (`dsl/n3-timer-label..engine/w1-schema-version`). Poprawność: 9 uwag — naprawione: zatrzymanie
  subskrypcji i odrzucanie efektów (decyzja wyżej), relay omijający sprawdzenie, nazwany wyjątek, sprawdzenie przed
  podmiotami, testy ścieżek dispatchu, subskrypcji, efektu i relaya (próba odwrotna każdej: pada tylko jej test),
  strażnik `is_integer` (kolumna jest `NOT NULL`), sekcja i treść CHANGELOG, `@doc` `decode!/1` i opis
  `schema_version` w DSL-u. **Zostawione do V1/V3:** wiersz *starszej* wersji niż deklaracja dekoduje się bez
  pytania — także każdy wiersz sprzed W1, który mówi 1 bez względu na deklarację; strażnikiem ma być reguła `check`
  z ADR §10.6 (wiersze starszej wersji bez upcastu), której jeszcze nie ma — od W1 ma znaczenie. Bezpieczeństwo i
  wydajność: ta sama uwaga o zatrzymaniu (średnia, naprawiona); komunikat bez wartości; wiersza nowszej wersji nie da
  się wstrzyknąć przez inbox ani relay; koszt jednego porównania na wiersz.
- **Drugi przegląd** (poprawka `746dbf7`): bez błędów w ścieżkach; naprawione (`417a501`) — ostrzeżenie o czekaniu raz
  na pozycję zamiast co 5 s, backoff efektu po wielu `snooze` liczony z prób, które się odbyły (domyślny Obana
  skalował przez `max_attempts` i po 9 minutach czekania dawał ponowienie po dniach), strażnik `is_integer`,
  moduledoc relaya, testy relaya z nowszym wierszem za starszym i process managera (próba odwrotna każdego).
  Pominięte: partia read modelu (do 499 zdarzeń) przeliczana i wycofywana co 5 s podczas czekania — koszt tylko na
  czas wdrożenia. Odnotowane w CHANGELOG: inbox odpowiada `:nack` i wiadomość wraca. Czekanie bez końca po
  wycofaniu wdrożenia widać tylko w logu i opóźnieniu pozycji — widoków operacyjnych nie budujemy (`CLAUDE.md`).
- **Brama:** EXIT=0; `check` sandboxa 0 / 29 / 10, silnika 0 / 74 / 6; sandbox 194, silnik 1273, web 51, auth 286 +
  1 property.
- **Dla aplikacji AppUnite i `ehos-ledger`:** nic do zmiany w kodzie; przy wdrożeniu po kolei z podniesioną wersją
  zdarzenia subskrypcje starego węzła czekają (ostrzeżenie w logu) — nie `--skip`.

### Przed W2 — decyzja użytkownika (5 października)

**Tylko tagi dnia** (`<pole>.day:YYYY-MM-DD`, UTC), bez tagów miesiąca. Jedyny czytelnik w planie — B2, kubełek w
`match:` (jedna wizyta naraz na specjalistę) — pyta o dzień; miesiąc wróci ze swoim czytelnikiem. *Odrzucone:* dzień i
miesiąc od razu (dwa tagi więcej na każde pole daty bez czytelnika; za to wiersze sprzed dodania miesiąca go nie
będą miały — to koszt świadomie przyjęty).

### W2 — co wyszło (5 października)

Gałąź `engine/w2-day-tags` (na W1). Dispatch dokłada przy dopisie tag `<pole>.day:YYYY-MM-DD` dla każdego wymaganego,
nieosobowego pola `:date` lub `:timestamp` (albo wartości domeny na nim opartej), obok tagów `:id`. Data ma swój
dzień; znacznik czasu — dzień, na który przypada w strefie domeny. Nic tych tagów jeszcze nie czyta (czytelnik: B2).
Rig `DispatchRig` rejestruje `:day_closed` (jedno `event-without-consumer` więcej w `check` silnika, 74 → 75) i ma
wartość `:business_day`.

**Decyzja użytkownika (5 października), po przeglądzie: dzień w strefie domeny, nie UTC.** Przykład z Rehmed: wizyta
o 00:30 w Warszawie 6 października to 22:30 UTC 5 października — w dniu UTC nie zderzyłaby się w B2 z wizytą o 9:00
6 października, a zapisanego tagu nie da się poprawić. Domena deklaruje `time_zone: "Europe/Warsaw"` (domyślnie
`"Etc/UTC"`). *Odrzucone:* UTC, jak w decyzji przed W2 (dzień lokalny wymagałby innego tagu, którego historia nie
będzie miała); odsunięcie W2 do B2 (historia sprzed B2 bez tagów).

- **Rozstrzygnięcia asystenta (mechanika):** strefę czyta baza stref, którą konfiguruje host (`config :elixir,
  :time_zone_database`) — pakiet nie przywozi żadnej, `tz` tylko w jego testach i w hoście sandboxa. *Odrzucone:*
  `tzdata` (pobiera dane przez sieć w czasie działania), twarda zależność pakietu od `tz` (wybór za hosta). **D13**
  (L2) odmawia strefy, której skonfigurowana baza nie zna, także gdy moduł bazy nie istnieje; **start węzła** odmawia,
  gdy baza, z którą działa, nie zna strefy domeny (`Registry.load!`). Domena bez strefy zachowuje wersję; trzy domeny
  sandboxa (Rehmed, TaxVision, AppUnite) są w Warszawie.
- **Przegląd** (dwa przebiegi). Pierwszy (tagi): bez błędów; dane osobowe nieoznaczone `personal:` są już jawnie w
  payloadzie, tag ich nie odsłania bardziej; ryzyko dnia UTC → decyzja wyżej; brakujący test wartości opartej na dacie
  dodany; wpis CHANGELOG z działaniem hosta („ustaw `time_zone:` przed aktualizacją”). Drugi (strefa, `539f0ec`): bez
  błędów; naprawione w `5c3a619` — sprawdzenie strefy przy starcie, D13 przy brakującym module bazy; bez zmian — alias
  UTC (`"UTC"`) przesuwa wersję, choć dni są te same; niezaładowana domena liczy dni w UTC (v2 §8). Próba odwrotna
  każdej poprawki: pada tylko jej test.
- **Dla B2:** zdarzenia sprzed W2 (aplikacja AppUnite, `ehos-ledger`) nie mają tagów dnia — B2 potrzebuje reguły na
  to (odmowa kubełka nad historią sprzed W2 albo udokumentowana data odcięcia).
- **Brama:** EXIT=0; `check` sandboxa 0 / 29 / 10, silnika 0 / 75 / 6; sandbox 194, silnik 1280, web 51, auth 286 +
  1 property.
- **Dla aplikacji AppUnite i `ehos-ledger`:** ustawić `time_zone:` domeny **przed** podbiciem; strefa inna niż UTC
  wymaga `{:tz, "~> 0.28"}` i `config :elixir, :time_zone_database, Tz.TimeZoneDatabase`.

## Dopisek 4 października (3) — pokrycie ESDM po EP1–EP5 i #99

**Trzecia analiza, po „Analiza pokrycia ESDM (27 września)” i porównaniu z 3 października („Dopisek 3 października — EP”).**
ESDM bez zmian: `thenativeweb/esdm` `main` = `295e1ca` (29 września), wydanie 0.15.0 — schematy `core`,
`given-when-then` i 73 reguły jak przy obu poprzednich analizach. Biblioteka na `303b418` (#127): referencja obu
DSL-i (`docs/dsl/`), `docs/rules.md`, tabela odmów w `docs/contract.md`, decyzje w „EP4/EP5a/EP5b — co wyszło” i
w dopisku o #99.

**Domknięte od 3 października:** `constraints` polityki, efektu i process managera oraz `invariants` process
managera (EP2 — szczebel 1 przez `illustrates:`, efekt prozą); oczekiwany `state` w scenariuszu process managera
(EP4); `idempotency` z właścicielem `:self | :downstream | :infrastructure` (EP4, P3); `capabilities` systemu jako
`operation` z X4 i `operation-never-called` (EP5a — nazwa inna, bo „capability” to uprawnienie aktora);
`responsibilities` aktora jako `responsibility` (EP5b); `terms` mapowania jako pary sprawdzane wobec słowników, także
w `partnership` (EP5b — świadome odstępstwo); `source:` na każdej deklaracji (EP1). Reguły lintera: 13 z nazwą ESDM
bez zmian, doszły własne (`prose-without-scenario`, `operation-never-called`) i kody S10, T1–T4, F8–F9.

**Różnice, które zostają:**
- *Odrzucone, z powodem w tym pliku:* `at-most-once` i `owner: not-required` (zgodność nie odróżni zgubionego
  zdarzenia od niezaszłego); `owner: none` (P3 wymaga idempotencji przy `:at_least_once` — celowo surowiej);
  `paradigm`, `metadata`, wolne `description`, generatory poza `:uuid`; `feature` i Domain Storytelling; wiersze
  read modelu w scenariuszu (EP4); `endsWhen` jako warunek prozą (u nas zdarzenie `ends_on`).
- *Odłożone do przykładu z materiału:* `invariants` encji (decyzja (b) przed EP2); tożsamość `static`.
- *Nigdy nierozstrzygnięte — jedyne luki:* `category` systemu zewnętrznego; opis timera (ESDM `timers{name,
  description}`, u nas timer ma `source`, nie ma etykiety); proza przy pojedynczej reakcji process managera (ESDM
  `reactions{when, rule}`; u nas reguły na całym process managerze, `on`/`starts_on` bez prozy). Wszystkie trzy —
  szczebel 0 drabiny. Pytania o kształt zadane użytkownikowi 4 października — decyzje niżej.

**Ponad ESDM:** wykonywanie modelu (dispatch, log, reakcje, inbox i publikacja), scenariusze jako testy i drabina
prozy, proces z obietnicami, raport zgodności, crypto-shredding, wersja schematu zdarzenia, dokumentacja w
callbackach (EP3) i od #99 cykl życia agregatu (statusy i przejścia liczone przez silnik) — ESDM go nie ma.

**Decyzje użytkownika (4 października):**
- **Etykieta timera — wymagana, pozycyjna**, jak przy każdej innej deklaracji: `timer :documentation_due, "Doba na
  dokumentację", wait: {24, :hour}, …`. Czytelnicy: strony, `@doc` callbacku timera, graf. Bez zgodności wstecz —
  dwa timery sandboxa dostają etykietę z materiału. *Odrzucone:* etykieta opcjonalna (`label:` — timer bez niej
  dalej jest samą nazwą i nic tego nie zgłasza); bez zmian (znaczenie timera tylko w etykiecie process managera i w
  scenariuszach).
- **`category` systemu zewnętrznego — pominięte.** Etykieta systemu już mówi, czym jest, a kategoria nie ma
  czytelnika, który by na jej podstawie coś sprawdził albo narysował inaczej („rodzaj wchodzi z czytelnikiem”).
  *Odrzucone:* atom z listy zamkniętej z grupowaniem w grafie i na stronie domeny (lista bez przykładu, który by jej
  potrzebował); dowolny string jak w ESDM (proza bez nazwy i bez drogi wyżej — wbrew drabinie).
- **Proza przy pojedynczej reakcji process managera — pominięta.** Reguły na process managerze i `illustrates:` w
  scenariuszu konkretnego wyzwalacza już łączą regułę z reakcją i ją testują (np. trzy scenariusze `state`
  `monthly_registry_check` z EP4); proza przy `on` byłaby drugim miejscem na to samo zdanie. *Odrzucone:* `keeps:`
  w reakcji (nowe słowo wskazujące regułę — kształt pozwala je dodać, gdy przykład tego wymaga); etykieta reakcji
  jak ESDM `rule` (proza bez nazwy).
- **Po tej decyzji pokrycie ESDM jest pełne** w tym sensie, że każda różnica jest decyzją z powodem albo czeka na
  przykład z materiału. Do zbudowania zostaje etykieta timera — mały etap (propozycja asystenta: **EP6**).

## Dopisek 4 października (2) — AppUnite: zapotrzebowanie na komputer (`Demands`)

**Skąd.** Emil rozpisał proces z głowy jeszcze raz (szkic `cf.pdf`, opisany w destylacji, dopisek 4 października) i
odpowiedział na pytania o niego. Szkic zaczyna się od **osoby**: nowa osoba albo kradzież prowadzą do zakupu w
Innergo albo do komputera z półki. Model tego nie miał — zamówienie było komputerem bez numeru seryjnego, z
opcjonalnym „dla kogo”, a kradzież niczego nie otwierała.

**Decyzje użytkownika (4 października):**
1. **Komputer powstaje przy rejestracji z faktury, osoba przychodzi potem** („wolę, żeby był wprowadzony komputer, a
   później przypisana osoba”). *Odrzucone:* komputer od zamówienia (stan „New” komputera) — tak było od #120.
2. **Przypisanie, konto pracownika, paczka i kurier to jeden ruch z wydaniem.** *Odrzucone:* osobny status
   „przypisany” i agregat przydziału — nie ma momentu między przypisaniem a wydaniem.
3. **Zapotrzebowanie otwierają cztery powody:** nowa osoba, kradzież, awaria, wymiana; **zamyka je tylko wydanie**.

**Rozstrzygnięcia asystenta (mechanika):**
- **Nowy kontrakt `Demands`** z agregatem zapotrzebowania i cyklem życia `Otwarte → New → Zaspokojone` (osobny
  przebieg, osobna korelacja — nie da się go zmieścić w `Computers`). `issued` niesie wymagane `demand_id`.
- **Dwie polityki `:in_transaction`** na zdarzeniach `Computers`: wydanie zamyka zapotrzebowanie, kradzież otwiera
  nowe dla tej osoby; nową osobę, awarię i wymianę otwiera Magda. *Odrzucone:* `:at_least_once` — skutek ma być
  zdecydowany w transakcji zdarzenia. Wyjątek cofa oba; **odmowa już nie** (niżej, otwarte).
- **Tożsamość komputera zostaje generowana.** *Odrzucone:* numer seryjny jako tożsamość — tożsamość to `:id`, więc
  ginie sprawdzenie formatu Apple (wartość `:serial_number`). Niezmiennik `received_once` znika: pilnował tylko, że
  zamówiony komputer spisuje się raz, a dziś spisanie go tworzy. **Numeru seryjnego dwa razy nie pilnował ani on, ani
  nic dziś** (dwa zamówienia mogły dostać ten sam numer); spisanie, które tworzy komputer, wymaga klucza
  idempotencji, więc ta sama faktura wysłana dwa razy z tym samym kluczem daje jeden komputer.
- **`lost` niesie przydział i osobę** — utrata jest tylko od pracownika (#126), więc oba są znane. `Assignments`
  kończy nim przydział: wczorajsze ustalenie „skradziony komputer zostawia przydział otwarty” jest rozwiązane.
- **Odczyt „Zapotrzebowania”** (kto czeka, od kiedy, czy zamówiony); „Inventory” traci wiersze „New”.

**Otwarte z przeglądu (do decyzji użytkownika):**
1. **Wydanie na zapotrzebowanie, które nie czeka.** `issue_computer` z literówką w `demand_id`, z cudzym zapotrzebowaniem
   albo z już zaspokojonym przechodzi: polityka dostaje odmowę (`from:`), a odmowa reakcji zostawia pierwszą komendę
   (dispatcher, krok 7). Prawdziwe zapotrzebowanie zostaje na liście czekających. Opcje: (a) wydanie odmawia, gdy
   zapotrzebowanie nie czeka albo jest kogoś innego — decyzja komputera musiałaby czytać zapotrzebowanie (granica
   `dcb` nad dwoma kontraktami); (b) odmowa polityki `:in_transaction` cofa całe zdarzenie — zmiana semantyki
   biblioteki; (c) raport wystarczy, jak przy zwrocie cudzego przydziału.
2. **Kradzież odnotowana tam, gdzie jej być nie może, i tak otwiera zapotrzebowanie.** `lost` z biura albo drugi raz
   dla tego samego komputera jest dopisywany (zdarzenie rejestrowane spoza cyklu życia) i polityka reaguje — z osobą
   i przydziałem, które wpisał rejestrujący. Pytanie do biblioteki: czy reakcja ma widzieć zdarzenie rejestrowane,
   którego cykl życia nie dopuszcza.

**Otwarte:** etapy procesu `Computers` (`intake → use → sale → ending`) powtarzają kolejność, którą dziś mówi cykl
życia, i nic nie sprawdza, że się zgadzają — do decyzji użytkownika (opcje: reguła w bibliotece, usunięcie etapów,
bez zmian).

## Dopisek 4 października — #99: cykl życia agregatu (stany i przejścia)

**Skąd.** Trzecia domena testowa, sprzęt AppUnite (`sandbox/lib/appunite_equipment/`, od LC0 w `main`),
ma komputer, który latami krąży w pętli: wydany → zwrot → w biurze → u resellera → w biurze → wydany… aż do
sprzedaży, darowizny, utylizacji albo zgubienia. Właściciel procesu myśli statusami (arkusz: jedna kolumna, dziesięć
wartości). DSL nie ma słowa na status: żyje w `evolve/2` (`:status` w stanie agregatu) i w enumie read modelu.
`stage` mówi tylko o kolejności do przodu, więc pętla siedzi w jednym etapie (`:use`) jako niepołączone pudełka.

**Komentarz użytkownika na #99 (zgodność z DDD), przyjęty jako warunki:** (1) status wynika ze zdarzeń, nikt go nie
ustawia — żadnej komendy „ustaw status”; (2) w cyklu życia tylko stany, od których zależą decyzje — „Zastępczy”
to cecha przydziału, „New” to „ordered”, kolumna „dalsze działania” to read model; (3) cykl życia należy do jednego
agregatu w jednym kontekście — komputer i przydział to dwa cykle, bez sklejania między `Computers` i `Assignments`.

**Propozycja asystenta (4 października, odpowiedź na #99) — do zatwierdzenia:**
- **Przejścia deklarowane, status liczy silnik.** `lifecycle do state …; transition :in_office, :issued, :in_use
  end` w agregacie. Status wynika z samych nazw zdarzeń, więc dispatch liczy go w tym samym przejściu po strumieniu i
  wstrzykuje do `State` jako pole tylko do odczytu (jak tożsamość); `evolve/2` go nie liczy. Rozjazd niemożliwy z
  konstrukcji. *Odrzucone (asystent):* kompilator sprawdza `evolve/2` względem deklaracji (opcja „declared” z
  issue) — statycznie niewykonalne, `evolve/2` to dowolny kod; status wyprowadzany z istniejącego `evolve/2` bez
  deklaracji (opcja „derived”) — dryfuje, nic go nie pilnuje.
- **Szczebel 2 drabiny:** zdarzenie wyemitowane spoza grafu (np. `issued` z `:at_reseller`) to defekt jak zdarzenie
  spoza `emits:` — wyjątek, nic nie dopisane.
- **Zgodność bez piątego pytania:** przejścia nigdy nieprzejechane = „zadeklarowane ścieżki nigdy nie przejechane”
  dla grafu z cyklami; przejścia niezadeklarowane — tylko w historii sprzed deklaracji, w istniejącym pytaniu.
- **Obok etapów, nie zamiast:** etap to widok procesu (run, korelacja, obietnice), cykl życia — widok agregatu.
- **Etykiety:** nazwa stanu po angielsku niesie znaczenie, `label` — słowo klienta; enum read modelu może czytać
  etykiety z cyklu życia.
- **Granice:** jedna oś (np. `set_up` w `Computer` zostaje flagą w `evolve/2`); zdarzenie spoza przejść dozwolone w
  każdym stanie nieterminalnym i statusu nie zmienia; odczyt historii z przejściami spoza grafu się nie wywraca
  (wiersz w skillu `change-contract`); tylko agregat, nie DCB; stany terminalne zgodne z `terminal:` zdarzeń.
- **Rozmiar:** 3–4 PR-y — DSL i reguły (osiągalność, stan początkowy, terminalne), status w `State` i strażnik w
  dispatchu, raport zgodności, diagram stanów w `graph` i na dashboardzie, sandbox.

**Decyzje użytkownika (4 października):**
1. **Materiał AppUnite wchodzi do `sandbox/`** jako trzecie dane testowe, na tych samych prawach co TaxVision i
   Rehmed: kontekst do sprawdzania biblioteki, który z nią nie zostanie (#49 — przeniesienie do osobnego repo, a
   docelowo usunięcie). *Odrzucone:* budowa bez materiału (nie budujemy bez przykładu); osobne repo przed #99
   (blokowałoby #99 na #49).
   **Reguła z tej odpowiedzi:** cykl życia ma być rozwiązaniem ogólnym, zgodnym z DDD; AppUnite jest przykładem,
   który ma się zmieścić, nie kształtem, pod który budujemy. Gdy szczegół przykładu nie pasuje do ogólnego
   rozwiązania, zmienia się przykład — i mówi się to w PR-ze.
2. **Warunek wstępny komendy: `from:` z nazwanym inwariantem.** Komenda deklaruje stany, z których wolno ją wydać;
   dispatch sprawdza je przed decyzją i odmawia kodem **zadeklarowanego `invariant`** (nazwa, etykieta, `source`,
   scenariusz odmowy) — nie kodem wygenerowanym. Odmowy drobniejsze niż sam stan (w AppUnite wydanie komputera
   wystawionego na sprzedaż, `:for_sale_not_issued`) zostają w decyzji. *Odrzucone:* wygenerowany wspólny kod
   (gubi słowa klienta i scenariusze odmów); odmowy tylko ręczne (reguła „tylko z biura” powtórzona przy każdej
   komendzie, nic jej nie wiąże z cyklem życia).
3. **Status liczy silnik, z samych typów zdarzeń; przejścia bez warunków na polach zdarzenia.** Tylko taki graf da
   się sprawdzić statycznie i narysować; warunek na danych to reguła biznesowa — decyzji albo innego agregatu.
   *Odrzucone:* przejścia z warunkiem na polu (kod zamiast deklaracji, dla jednego przykładu); status w `evolve/2`.

**Ustalenia z czytania kodu AppUnite (4 października), które poprawiają propozycję:**
- **Zdarzenia rejestrowane (`recorded_by:`) nie są decyzjami.** `returned`, `service_returned` i `lost` wchodzą przez
  `record/3`; zwrot sprzedanego komputera się wydarzył i odrzucić go nie można. Strażnik („spoza grafu to defekt”)
  dotyczy więc tylko zdarzeń **decydowanych**; zdarzenie rejestrowane spoza grafu jest dopisywane, statusu nie
  zmienia, a raport pokazuje je jako przejście niezadeklarowane — także w **nowym** logu, nie tylko w historii sprzed
  deklaracji (poprawka punktu „Zgodność bez piątego pytania” wyżej).
- **Status w AppUnite zależy od pola zdarzenia:** `returned` przenosi do biura tylko przy zgodnym `assignment_id`.
  Z decyzji 3 zwrot przenosi do biura zawsze; zgodność przydziału to sprawa cyklu przydziału w `Assignments`
  (warunek 3 użytkownika). Scenariusz zwrotu cudzego przydziału zmienia się w LC4.

**Kolejność budowy** — każda część osobnym PR-em, z `pre-pr-review` przed następną:
- **LC0** — materiał AppUnite w `sandbox/` bez zmian w bibliotece (przebazowany na `main`).
- **LC1** — DSL `lifecycle` w agregacie i reguły: stan początkowy, osiągalność, stany terminalne zgodne z
  `terminal:`, zdarzenia przejść należą do agregatu, `lifecycle` w `boundary` odrzucony; `from:` wskazuje stany i
  inwariant. `docs/dsl/`, `docs/rules.md`, `CHANGELOG.md`.
- **LC2** — status w `State` liczony przez dispatch i `ScenarioCase`; strażnik zdarzeń decydowanych; odmowy z
  `from:`; zdarzenia rejestrowane spoza grafu dopisywane bez zmiany statusu.
- **LC3** — raport zgodności: przejścia nigdy nieprzejechane, przejścia niezadeklarowane.
- **LC4** — diagram stanów w `graph` i na dashboardzie; `Computer` w AppUnite na cyklu życia (bez ręcznych
  strażników statusu); wiersz w skillu `change-contract`.

### LC1 — co wyszło (4 października)

Na `dsl/lc1-lifecycle`, na gałęzi LC0 (#120).
- **Słowa:** `lifecycle do status …; initial :status, on: :event; transition from, :event, to end` w agregacie;
  `from:` i `or_rejects:` w komendzie. Rozstrzygnięcia asystenta (mechanika): **`status`, nie `state`** —
  `state do` to już pamięć agregatu; **`initial` jako osobne słowo** — przed pierwszym zdarzeniem agregatu nie ma,
  więc start to przejście „znikąd”, jak pseudostan początkowy w UML; **`or_rejects:`** — w stylu `or_else`
  obietnicy. *Odrzucone:* zarezerwowany status startowy w `transition` (np. `:none`) — nazwa, której klient nie
  może użyć; `from: [in_office: :only_from_the_office]` — status i odmowa w jednej liście, nieczytelne.
- **Reguły `T1`–`T4`** (L2): kształt, odwołania i determinizm (jedno zdarzenie z jednego statusu do jednego), graf
  (każdy status osiągalny, tylko terminalny bez wyjścia; pętla w ten sam status nie jest wyjściem), `from:` z
  `or_rejects:` i przejściami. **Świadomie poza regułami:** (1) zgodność stanów terminalnych z `terminal:`
  zdarzeń — `terminal:` kończy przebieg procesu, a przebieg może mieć inną korelację niż agregat (`Assignments`
  po przydziale); (2) wymóg, że z każdego statusu da się dojść do terminalnego — cykl życia bez końca jest
  legalny (konto); (3) `from:` obowiązkowe przy komendzie, której zdarzenia wszystkie przesuwają status — bez
  `from:` zła komenda w złym statusie będzie defektem w LC2, nie odmową; zostawione autorowi kontraktu.
- **`lifecycle` w `dcb`** odrzuca L1 (błąd kompilacji „undefined function lifecycle/1”), nie kod `T`. *Odrzucone:*
  słowo w `dcb` tylko po to, żeby je odrzucić — weszłoby do wygenerowanej dokumentacji granicy.
- **Model:** `lifecycle` w jednostce oraz `from`/`or_rejects` w komendzie tylko tam, gdzie zadeklarowane — żaden
  istniejący digest się nie rusza. Przejście z listy statusów to w modelu jedno przejście na status.
- **Przegląd** (dwa równolegle): bezpieczeństwo i wydajność — pusty `from:` w przejściu znikał z modelu bez słowa
  (poprawione, `T2`); poprawność — opis `from:` obiecywał odmowę, której silnik jeszcze nie robi (poprawione do
  LC2), pętla w ten sam status liczona jako wyjście (poprawione), duplikaty `from:` (deduplikowane), mylący
  komunikat przy dwóch identycznych `initial` (poprawiony), test `dcb` bez sprawdzenia komunikatu (poprawiony),
  `source:` w `initial` (dodane, zanim ktoś go użyje). Bez zmian: powtarzane zbiory w `precondition/5` (kilka
  komend na agregat), kolejna kopia `did_you_mean`.

### LC2 — co wyszło (4 października)

Na `dsl/lc2-lifecycle-dispatch`, na gałęzi LC1 (#121).
- **`EhOsContract.Lifecycle`** — czyste funkcje: status z nazw zdarzeń (`walk/2`, `step/3`), `admits?/2` dla
  `from:`, `decided!/4` dla tego, co zdecydowano. Dispatch i `ScenarioCase` czytają przez nie.
- **Status w `State` jako pole `status`** (enum statusów), poza polami stanu w modelu — deklaracja cyklu życia
  nie rusza digestu stanu. `T1` odmawia pola stanu albo tożsamości `:status` obok cyklu życia.
- **Dispatch:** status z typów **wszystkich** wierszy strumienia (nie tylko tych, które składa `evolve/2`), liczony
  przed dekodowaniem — komenda odrzucona przez `from:` niczego nie odszyfrowuje. `evolve/2` widzi status sprzed
  każdego zdarzenia, a po ostatnim silnik nadpisuje to, co `evolve/2` zostawił. Odmowa z `or_rejects:` pisze
  wiersz `rejected` jak odmowa decyzji. Zdarzenie zdecydowane spoza grafu — wyjątek, nic nie dopisane; **przed
  startem agregatu wolno zdecydować tylko zdarzenie `initial`** (rozstrzygnięcie asystenta po przeglądzie:
  inaczej agregat miałby historię bez statusu). Zdarzenie rejestrowane nigdy nie jest odrzucane za niepasowanie.
- **Pokrycie scenariuszy:** `given` scenariusza agregatu z cyklem życia liczy też typy, na których status się
  rusza — inaczej odmowa komendy na niezałożonej wizycie liczyła się jako scenariusz „pacjent już przyszedł”
  (z przeglądu; test pada na starym kodzie).
- **`@doc` callbacku** mówi, w jakich statusach komenda jest wydawana i na czym silnik ją odrzuca.
- **Rig:** `LifecycleRig` (zmyślony, wizyta) — implementacja nie czyta statusu do odmów, a scenariusze odmów
  przechodzą, bo odmawia silnik.
- **Przegląd** (dwa równolegle): poprawność — pokrycie (wyżej, poprawione), zdarzenie spoza grafu przed startem
  (poprawione), `ScenarioCase` składał stan przed sprawdzeniem `from:` (poprawione, teraz jak dispatch), komunikat
  scenariusza ukrywał odmowę silnika (poprawiony). Bez zmian: składanie stanu zapisane dwa razy (dispatch i
  `ScenarioCase` dzielą `walk`/`decided!`, nie samo składanie — różne źródła: wiersze i struktury), powtarzane
  sortowania, `status/2` używany tylko w testach (zostaje dla LC3), brak testu `in_lifecycle!` w `ScenarioCase`
  (ta sama `decided!`, testowana bezpośrednio). Bezpieczeństwo i wydajność — `evolve/2` zwracające nie-stan dawało
  `KeyError` z całym stanem w komunikacie, czyli z danymi osobowymi (poprawione: komunikat nazywa moduł); status
  przed dekodowaniem (poprawione). Bez zmian: koszt O(zdarzenia × przejścia) na komendę — pomijalny przy odczycie
  całego strumienia.

### LC4b — co wyszło (4 października)

Na `graph/lc4b-lifecycle-diagram`, na gałęzi LC3 (#123).
- **Diagram:** `Graph.Lifecycle` — start (czarna kropka), statusy w słowach klienta (kolor stanu agregatu), końce
  grubszym obrysem, przejścia podpisane etykietą zdarzenia. Flowchart Mermaid, nie `stateDiagram`: te same dane
  grafu co pozostałe obrazy i ten sam renderer na dashboardzie. Z logiem: liczby, „not yet”, „never” — z raportu
  LC3 (`Conformance.lifecycles/2`, publiczne), nic liczone osobno; niezadeklarowane ruchy kropkowaną pętlą.
- **`mix eh_os_contract.graph --contract M --lifecycle NAME [--overlay]`.**
- **Dashboard:** na ekranie grafu diagram cyklu życia przy jednostce, z logiem; na ekranie kontraktu sekcja
  „Lifecycle” zdaniami raportu. Fikstura dashboardu (`CaseHandling`) dostała cykl życia.
- **Sprawdzone w przeglądarce:** diagram renderuje się na dashboardzie sandboxa przez Mermaid i jego sposób
  wstawiania SVG (CSP — style przez CSSOM); polskie etykiety, kolory, pętla niezadeklarowanego ruchu.
- **Przegląd** (dwa równolegle): obie strony — ekran grafu czytał cały log raz na jednostkę z cyklem życia,
  w kwadracie i dwa razy na wejście (poprawione: raport raz na kontrakt, `lifecycles:` do rysunku, tylko po
  podłączeniu socketu; pierwszy, statyczny render rysuje deklarację). Poprawność — `--since` bez `--overlay`
  przy `--lifecycle` (odrzucane), pusty nagłówek na ekranie kontraktu (warunkowy, jak w raporcie tekstowym), test
  „każde zdanie z `Sentence`” bez cyklu życia (rozszerzony), komunikat zadania dla kontraktu bez cyklu życia,
  `Lifecycle.of/1` zamiast `Map.has_key?`, moduledoc ekranu grafu, README. Bez zmian: strzałki budowane z
  deklaracji i dopasowywane do raportu (poprawne; brak dopasowania → bez liczby, nie wyjątek); brak pamięci
  podręcznej między wyborami procesów jednego kontraktu.
- **Pułapka (4 października):** migracja z niezmergowanej gałęzi zmienia **wspólną** bazę testową sandboxa
  (`eh_os_contract_host_test`, stała nazwa) wszystkim worktree. Migracja LC4a usunęła kolumnę, której `main` używa;
  brama LC4b (na LC3, bez LC4a) padła na trzech scenariuszach Inventory. Przywrócone ręcznie (kolumna z
  powrotem, wiersz migracji usunięty). Do przeniesienia do `CLAUDE.md`.

### LC4a — co wyszło (4 października)

Na `sandbox/lc4a-appunite-lifecycle`, od `main` po #122. LC4 podzielone (rozstrzygnięcie asystenta, mały diff):
**LC4a** — AppUnite na cyklu życia i skill; **LC4b** — diagram stanów w `graph` i na dashboardzie, na LC3.
- **`Computer` na cyklu życia:** dziesięć statusów słowami arkusza (`A:F`) — `New`, `Office`, `W użytku`,
  `W trakcie zwrotu`, `Innergo spa`, `For sale` i cztery końce (`Sold`, `Charity`, `Utylizacja`, `Lost`, każdy
  terminalny); `Zastępczy` zostaje cechą przydziału (warunek 2 użytkownika), `set_up` flagą. Utrata z każdego
  statusu, który się nie skończył. Pole `:status` zniknęło ze stanu; każda komenda ma `from:` z inwariantem, który
  już był; z decyzji zniknęły strażniki statusu z trzynastu komend — zostały tylko odmowy drobniejsze niż status
  (wycofana generacja, brak ustawień, rezerwacje, Allegro, „na sprzedaż”).
- **Ustalenie dla biblioteki — `T4` był za ostry:** odrzucał status w `from:`, z którego żadne zdarzenie komendy
  nie wychodzi. `issue_computer` musi być wydawane z `:for_sale`, żeby odmówić `:for_sale_not_issued` (osobna
  reguła właściciela procesu, `A:G`), czego wymaga decyzja 2 („drobniejsze odmowy zostają w decyzji”). `from:` mówi,
  gdzie decyzja się odbywa, nie gdzie przyjmuje — taki status jest dozwolony, **jeśli `rejects:` ma regułę inną niż
  `or_rejects:`** (zawężone po przeglądzie: bez niej decyzja mogłaby tylko rzucić wyjątek); zostaje też „emitowane
  zdarzenie, którego żaden status z `from:` nie wypuszcza”. *Odrzucone:* usunąć `:for_sale_not_issued` z kontraktu — dopasowanie
  przykładu do biblioteki, której reguła była błędna.
- **Decyzja 3 w przykładzie:** zwrot innego przydziału przenosi komputer do biura — scenariusz „dotarł zwrot
  innego przydziału” teraz oczekuje `wiped`, a odczyt „Inventory” wraca do warunku tylko na status (kolumna
  przydziału z #120 usunięta nową migracją). Zgodność przydziałów to sprawa `Assignments`.
  **Otwarte — skutek decyzji 3 (z przeglądu):** zwrot zarejestrowany z błędnym przydziałem (literówka, spóźniona
  paczka poprzedniego przydziału) przenosi komputer do biura i pozwala wydać go komuś innemu, a prawdziwy
  przydział zostaje otwarty. `Assignments` dziś niczego nie odrzuca: widać to tylko w raporcie, jako przebieg
  przydziału bez `returned`. Przed decyzją 3 chronił przed tym warunek w `evolve/2`. Do rozstrzygnięcia przez
  użytkownika, czy `Assignments` ma dostać agregat przydziału (z cyklem życia i odmową zwrotu cudzego przydziału),
  czy raport wystarczy.
- **`evolve/2`** czyta status silnika (zwrot i powrót z Innergo zmieniają stan tylko z `:returning` i
  `:in_service`), nigdy go nie ustawia.
- **Poprawka użytkownika (4 października, po obejrzeniu diagramu):** utrata tylko z `W użytku` — materiał zna jedną
  („komputer u pracownika — skradziony”, E). Utrata z każdego statusu była uogólnieniem asystenta, spoza
  materiału; na diagramie dawała sześć strzałek „zgubiony albo skradziony” i graf wyglądał, jakby opisywał głównie
  utratę. Utrata odnotowana gdzie indziej jest dopisywana i raport pokazuje ją jako niezadeklarowaną; „Inventory”
  rusza wiersz tylko z `issued`/`replacement`. *Do rozważenia przy bibliotece:* przejście z kilku statusów rysowane
  jako osobna strzałka z każdego — czytelne przy dwóch, nie przy sześciu.
- **Skill `change-contract`:** wiersz o dodaniu cyklu życia do agregatu z historią.
- **Bez zmian:** enum statusu w read modelu „Inventory” powtarza etykiety cyklu życia — czytanie ich z cyklu życia
  byłoby nowym słowem DSL-a, bez drugiego przykładu.
- **Przegląd** (dwa równolegle): poprawność — rozluźnienie `T4` za szerokie (zawężone), zdanie w skillu o raporcie
  sprzed LC3 (oznaczone), migracja padała na bazie sprzed #120 (`remove_if_exists`), wpisy w CHANGELOG
  (poprawione), „dziewięć” strażników (trzynaście komend). Bez zmian: wiersze „Inventory” z danych dev sprzed
  zmiany nie są przeliczane, bo deklaracja read modelu się nie zmieniła (dane testowe; `reset/0` na żądanie);
  odmowa `:for_sale` w decyzji zamiast `or_rejects:` per status — nowe słowo bez drugiego przykładu.
  Bezpieczeństwo — każdy dawny strażnik ma odpowiednik, żadna komenda nie dociera do decyzji tam, gdzie wcześniej
  nie docierała; skutek decyzji 3 wyżej, jako otwarte.
### LC3 — co wyszło (4 października)

Na `conformance/lc3-lifecycle`, od `main` po #122.
- **Raport, klucz `lifecycles`:** dla każdego agregatu z cyklem życia — ile agregatów miało zdarzenie w okresie,
  każde zadeklarowane przejście (także start, `initial`) z liczbą przejechań, **nieprzejechane** (puste, gdy żaden
  agregat nie miał zdarzenia — jak przy zerze przebiegów) i **niezadeklarowane**: zdarzenie, którego graf nie
  dopuszcza tam, gdzie agregat stał (historia sprzed deklaracji, zarejestrowane, które nie pasowało, zdarzenie po
  końcu), liczone po `(status, zdarzenie)`. To dwa pierwsze z czterech pytań, zadane przejściom — bez piątego.
- **Liczenie:** `Lifecycle.tally/2`, czyste — status przez cały strumień, liczone tylko zdarzenia z okresu.
  Niezadeklarowane statusu nie rusza, jak nie ruszyło go przy dopisaniu.
- **„Jeszcze nie” zamiast „nigdy”** (z przeglądu): przejście osiągalne ze statusu, w którym stoi agregat, który
  się nie skończył, idzie do `pending`, nie do nieprzejechanych — wizyta wciąż umówiona może zostać odwołana.
  Ta sama reguła, co kroki w toku procesu. W grafie z pętlą (komputer) to znaczy: dopóki jakiś komputer żyje,
  prawie nic nie jest „nigdy” — i to jest uczciwa odpowiedź, bo jeszcze może się stać.
- **Wydajność** (z przeglądu): czytane są tylko strumienie agregatów ze zdarzeniem w okresie (podzapytanie), każdy
  w całości, strumieniowo (`Repo.stream`) — pamięć to najdłuższy strumień, nie log. Wiersze bez `stream_id` nie
  należą do żadnego agregatu. Graf indeksowany raz na wywołanie.
- **Przegląd** (dwa równolegle): bezpieczeństwo i wydajność — nieograniczone czytanie całej historii (poprawione),
  wiersze bez strumienia sklejane w jeden agregat (poprawione). Poprawność — „nigdy” dla przejść, które czekają
  (poprawione, `pending`), powielona decyzja „czy przesunęło” (teraz `allowed/3` mówi `:moved`/`:stayed`),
  kolejność niezadeklarowanych (stała), „in start” jak nazwa statusu (teraz „before the aggregate started”), testy
  pętli i zdarzenia startowego, które jest też przejściem (dopisane). Bez zmian: filtr po nazwie kontraktu przy
  przemianowanym module (jak `drift`, opisane w komentarzu), `NaiveDateTime` w `since:` (dziś nikt go nie podaje).
- **Tekst raportu:** sekcja `LIFECYCLE: <etykieta agregatu>`; na wire klucz dopisany do
  `eh_os_contract.conformance.v2` (addytywnie, bez nowej wersji kształtu), start to `null`.
- **Poza LC3:** dashboard i diagram (LC4).

## Dopisek 3 października (2) — #94: style dashboardu z pakietu `ehos_design`, kopia usunięta

`eh-os` D-72 przeniósł design system do pakietu `ehos_design` (EmpoweredHouse/ehos-tools, tag
`ehos_design-v0.1.0` = `a65b9c86`). `eh_os_contract_web` bierze go jako zależność **tylko `:dev`,
`runtime: false`**: `assets/css/app.css` importuje `deps/ehos_design/packages/ehos_design/priv/css/colors_and_type.css`
(zwykłe tokeny, nie warstwę Tailwinda/daisyUI), a `mix assets.build` kopiuje fonty i teksty OFL do
`priv/static/assets/fonts/`. Zbudowany `app.css` i fonty zostają w repo, więc host nic nowego nie pobiera.
Usunięte: `assets/css/vendor/empoweredhouse/` z `SOURCE.md`, `.gitattributes` pakietu, skill
`sync-design-system` — odświeżenie to teraz przesunięcie refa i przebudowa.

**Sprawdzone:** plik tokenów i wszystkie 10 plików fontów w pakiecie są bajt w bajt identyczne z kopią, więc
`mix assets.build` daje **identyczny** `priv/static/assets/app.css` (minifikacja wycina komentarze ze
ścieżką, więc nawet one się nie różnią) i identyczne fonty.

**Co wyszło przy pisaniu:**

- **`ehos-tools` jest prywatne, a CI robi `mix deps.get` w pakiecie web, które pobiera też zależności
  `:dev`.** Bez tokenu ten krok by padł. CI pobiera teraz `--only test`; brama zależności nie potrzebuje,
  bo czyta tylko to, co zbudowane i scommitowane. Sandbox dostaje pakiet przez `path:` i zależności `:dev`
  dziecka nie ciągnie (sprawdzone). **Dostępu do `ehos-tools` potrzebuje każdy, kto robi zwykłe
  `mix deps.get` w pakiecie web** (Mix pobiera zależności wszystkich środowisk), nie tylko ten, kto
  przebudowuje assety — bez niego `mix deps.get --only test`, co mówi README pakietu.
- **Testy `design_system_test.exs` czytały kopię**, a w `MIX_ENV=test` pakietu nie ma. Test hasha i
  `.gitattributes` zniknęły razem z kopią; tokeny design systemu to teraz to, co definiuje zbudowany
  `app.css`, a nie warstwa. „Warstwa nie nadpisuje tokenu” sprawdza się po nazwie: warstwa definiuje
  wyłącznie `--eh-os-contract-*`. Doszedł test, że warstwa importuje tokeny z `ehos_design`. Brama
  pakietu przechodzi z `deps/ehos_design` i bez niego.
- **Przegląd przed PR** dołożył dwa testy w miejsce tego, co dawał hash kopii: katalog fontów trzyma
  dokładnie osiem fontów i dwa teksty OFL (kopiowanie tylko dodaje, więc font usunięty w nowej wersji pakietu
  zostałby serwowany), a gdy `deps/ehos_design` jest pobrane, zbudowany arkusz definiuje każdy token pakietu
  i warstwa żadnego z nich nie nadpisuje — to łapie przesunięty `ref:` bez `mix assets.build`. W CI pakietu
  nie ma, więc tam ten test się nie definiuje; łapie lokalnie, u tego, kto ruszył ref.
- Poprawka z datą w `docs/adr/dashboard-design-system.md`.

## Dopisek 3 października — trzecie dane testowe: sprzęt AppUnite (`sandbox/lib/appunite_equipment/`)

Rozmowa Emila z osobą, która w AppUnite prowadzi komputery pracowników (zamówienie, wydanie, zwrot, Innergo,
sprzedaż) — dziś w Excelu i Notion. Destylacja: `docs/appunite-equipment-2026-10-03-distillation.md`; Emil zna proces
i odpowiadał na pytania zamiast rozmówczyni. Domena `AppuniteEquipment.Domain` i dwa kontrakty, `Computers` i
`Assignments`, z implementacją, odczytem „Inventory” i 30 scenariuszami (11 reguł, każda z odmową). Emil planuje osobne repozytorium dla tego
procesu; tu jest, dopóki go nie ma, na prawach danych testowych jak TaxVision i Rehmed.

### Decyzje

- **Kształt przebiegu — B: komputer jako agregat, przebieg per przydział** (Emil, 3 października). Przegrały:
  **A** — jeden przebieg na całe życie komputera z etapami (przegrało tym, że etapy kontraktu twierdzą kolejność
  tylko do przodu, a komputer latami chodzi w pętli wydany → zwrócony → Innergo → ustawiony → wydany; wymagałoby
  zmiany w bibliotece; Emil „jeszcze się zastanawia”); **C** — przebieg per pobyt w biurze (nikt tak nie mówi).
- **Jak B wyszło w kodzie** (rozstrzygnięte przy pisaniu, mechanika): wszystkie decyzje w jednym agregacie
  `:computer` w `Computers`, bo każda reguła dotyczy jednego komputera; `Assignments` **nie ma żadnej jednostki** —
  `consumes` trzy zdarzenia przydziału (`issued`, `return_started`, `returned`) i deklaruje ich kolejność w procesie
  skorelowanym po `assignment_id`. Przegrało: `dcb` przydziału, który konsultuje zdarzenia komputera — decyzja
  wydania musiałaby czytać cudzy strumień, a `Computers` z kolei potrzebowałby zdarzeń przydziału do „czy jest w
  biurze”; dwa kontrakty konsumujące się nawzajem dla reguł, które są o jednej rzeczy. Kontrakt `Computers` musi i
  tak mieć swój proces (R1).
- **Proces komputera ma cztery etapy, `intake → use → sale → ending`, a cała pętla siedzi w `use`** (Emil, 3
  października, po obejrzeniu grafów). Pierwsza wersja nie miała etapów, a jej kształt na dashboardzie był jednym
  rzędem 17 pudełek, który nic nie mówił. Początek i koniec życia komputera idą tylko do przodu (nic się nie zamawia
  po użyciu, nic nie schodzi ze sprzedaży), więc etapy twierdzą prawdę; wewnątrz `use` kolejności nie ma.
  Przegrały: **widok cyklu życia w bibliotece** (statusy i przejścia, z krawędziami wstecz) — najbliższy temu, jak
  myśli właściciel procesu, ale to nowe pojęcie w DSL-u, więc poszło jako issue
  [#99](https://github.com/EmpoweredHouse/eh-os-contract/issues/99), nie do tego kontraktu; **ładniejsze rysowanie
  procesu bez etapów** — nadal nic by nie twierdziło.
- **Przydział ma trzy etapy, `issue → return → arrival`**, nie dwa: w jednym etapie `return` kolejność „zwrot
  rozpoczęty → dotarł do biura” nie była twierdzona, więc paczka bez rozpoczętego zwrotu nie byłaby widoczna.
- **Tożsamość komputera jest generowana przy zamówieniu, a numer seryjny jest polem z faktury.** Przegrało: numer
  seryjny jako tożsamość — zamówiony komputer (status `New`) nie ma jeszcze numeru.

### Ustalenia dla biblioteki

1. **Kontrakt bez jednostek, tylko `consumes` i `process`, kompiluje się i przechodzi `check`.** Pierwszy taki w
   repozytorium. Działa jako „soczewka”: drugi przebieg na zdarzeniach, które decyduje inny kontrakt. Nie ma testu
   dispatchu, który pokazuje runy per przydział w raporcie — do dopisania, zanim się na tym oprze.
2. **Komputer skradziony w trakcie przydziału zamyka komputer, a przydział zostaje otwarty.** `lost` nie niesie
   `assignment_id`, a pole korelacji nie może być opcjonalne (F4). Raport pokaże taki przydział jako niedokończony.
   Nierozstrzygnięte, czy to błąd modelu, czy brakująca konstrukcja (zakończenie przebiegu zdarzeniem bez jego
   korelacji).
3. **Lista wycofanych generacji (dziś `[:m1]`) nie ma domu w DSL-u.** To decyzja zespołu, która zmienia się z
   rynkiem; siedzi w implementacji jako `@withdrawn`, a reguła w kontrakcie mówi o niej zdaniem. Wartość domeny
   z danymi, które zmieniają się bez deployu, to coś, czego DSL dziś nie wyraża.
4. **Statusy, którymi właściciel procesu myśli o procesie, nie mają w DSL-u słowa** — żyją w `evolve/2` i w enumie
   odczytu. Etapy twierdzą kolejność tylko do przodu, więc pętla jest jednym etapem bez kolejności w środku.
   Issue [#99](https://github.com/EmpoweredHouse/eh-os-contract/issues/99).
5. **Zero obietnic czasowych** — trzecia domena sekwencyjna (por. Rehmed). Jedyna liczba, ~tydzień w Innergo, to
   czas dostawcy, nie zobowiązanie AppUnite.
## Dopisek 3 października — EP: proza w kontrakcie, drabina od nazwy do testu

**Porównanie z ESDM powtórzone 3 października.** `thenativeweb/esdm` na `295e1ca` (29 września): od `cf17780`,
na którym stoi „Analiza pokrycia ESDM (27 września)”, zmieniły się tylko dwa pliki CI, więc model to nadal 0.15.0.
Klucz po kluczu ze schematów `core` i `given-when-then` i reguła po regule (73): rodzaje, które przejęliśmy, są
pokryte, scenariusze GWT też, narzędzia mają odpowiedniki (`check --format json`, `docs/rules.md`, `view`,
`glossary`, `pages`, `graph`). Brakuje pól, które w ESDM są prozą albo metadanymi: `constraints` na `policy`,
`event-handler` i `process-manager`; `invariants` na `process-manager` i `entity`; prozy `rule` przy reakcji process
managera i opisu timera; `responsibilities` aktora; `category` i `capabilities` systemu zewnętrznego; `terms`
relacji jako par (u nas płaska lista, także w relacji symetrycznej, gdzie ESDM ich nie ma); `paradigm`;
`description` i `metadata` na każdym elemencie; `at-most-once` i `idempotency.owner`; tożsamości `static` i
generatorów innych niż `:uuid`; oczekiwanego `state` w scenariuszu process managera i scenariusza read modelu ze
zmaterializowanymi wierszami. Poza zakresem bez zmian: `feature` i Domain Storytelling.

**Dlaczego proza się liczy** (użytkownik): droga to warsztat → kontrakt → aplikacja owinięta wokół kontraktu, a kod
aplikacji generuje LLM. Proza kontraktu jest jego kontekstem, a później materiałem na sprawdzenia, które ograniczają
niedeterminizm generowania. Przykład z materiału: reguła polityki `report_on_clinical_close` („do P1 zgłaszamy
tylko usługi podlegające zgłoszeniu, resztę pomijamy”, `P-07`) żyje dziś w `@moduledoc` implementacji, a nie w
kontrakcie; dwa scenariusze ją ilustrują, ale nic ich z nią nie wiąże; wygenerowane `@callback` nie mają `@doc`.

**Decyzje użytkownika (3 października):**
- **Drabina prozy jako reguła DSL-a.** Każda nowa proza ma nazwę i stoi na jednym ze szczebli: **0** — nazwana
  proza (nazwa, tekst, `source`: kontekst dla LLM-a, kotwica strony, `@doc`, graf); **1** — zilustrowana
  scenariuszem, który ją nazywa (test wykonywany, `check` ostrzega o regule bez scenariusza); **2** — wykonywana
  (`reject`, walidator, przykłady — dziś inwariant, ograniczenie komendy, inwariant wartości, reguła serwisu).
  Proza ze szczebla 0 może później wejść wyżej bez zmiany kształtu. *Odrzucone:* wolne `description:` na każdej
  deklaracji, jak w ESDM (więcej kontekstu dla LLM-a, ale tekstu bez nazwy nie da się powiązać ze scenariuszem ani
  do niego linkować — zostaje prozą na zawsze).
- **Pierwsza runda: EP1 → EP2 → EP3**, każda część osobnym PR-em, każdy na gałęzi od poprzedniego, z
  `pre-pr-review` po każdej. EP4 i EP5 — po EP3, niżej.
- **Reguła bez scenariusza to ostrzeżenie, nie błąd** — jak `reaction-without-scenario`. *Odrzucone:* błąd jak S8
  (scenariusz odmowy jest jedynym dowodem inwariantu; regułę reakcji sprawdza też raport zgodności na logu).

**EP1 — `source:` na każdej deklaracji.** Dziś mają go agregat, granica, komenda, zdarzenie, inwariant,
ograniczenie, encja, subdomena, kontekst, termin i serwis; nie mają `policy`, `effect`, `process_manager`, `timer`,
`read_model`, `query`, `actor`, `external`, `value`, `relation`, `process`. Ślad z warsztatu do kontraktu, który
`contract-distillation` i tak produkuje. Czytelnicy: `pages`, `@doc` (EP3). *(Poprawione 3 października po
przeglądzie EP1: `view` jest drzewem struktury i nie pokazuje `source` żadnego rodzaju — nie jest czytelnikiem.)*

**EP2 — nazwane reguły reakcji i scenariusz, który je ilustruje.**
- `constraint` (kształt ograniczenia komendy) na `policy`, `effect` i `process_manager`; `invariant` na
  `process_manager`.
- Scenariusz `illustrates: :nazwa` (atom albo lista); nowa reguła `check` z ostrzeżeniem: ograniczenie reakcji,
  ograniczenie query albo inwariant process managera bez scenariusza, który je ilustruje. Ograniczenie query wchodzi
  tym samym ze szczebla 0 na 1 (scenariusz z `answers`).
- Nowa odmowa kompilacji: `illustrates:` nazywa regułę, której cel scenariusza nie ma.
- **Do decyzji przed budową — `invariant` encji.** Encja nie ma implementacji ani scenariuszy, więc na drabinie
  stanęłaby na szczeblu 0 bez drogi wyżej. Opcje: (a) jak inwariant wartości, z `violated_by`/`satisfied_by` i
  funkcją w implementacji encji (nowy `use … entity:`); (b) odłożyć, póki materiał nie da przykładu.
- Przykład docelowy: `constraint :only_reportable_services, "Do P1 zgłaszamy tylko usługi podlegające zgłoszeniu;
  pozostałe pomijamy", source: "P-07"` w `report_on_clinical_close` i `illustrates: :only_reportable_services` w
  obu jej scenariuszach. *(W budowie, 3 października: nazwa wyszła `only_reported_services`, za etykietą pola
  usługi „Raportowana do P1” (`AGG-15`) — „EP2 — co wyszło”.)*

**EP3 — proza dociera do kodu.** Wygenerowane `@callback` dostają `@doc` złożony z kontraktu: etykieta deklaracji
i wywołania, reguły, które go dotyczą (ze szczeblem), odmowy, które wolno zwrócić, tytuły scenariuszy, `source`.
Implementacje sandboxa przestają powtarzać regułę w `@moduledoc`. Skille `write-decider` i `write-reaction`
startują od nazwanych reguł: każda ma scenariusz, zanim powstanie kod.

**Po EP3 — EP4 i EP5, do decyzji przed budową** (propozycja asystenta):
- **EP4 — co da się wykonywać:** oczekiwany `state` w scenariuszu process managera (po
  `data_completeness_confirmed` stan `monthly_registry_check` ma `check_at`); scenariusz read modelu z oczekiwanymi
  wierszami read modelu, nie tylko odpowiedzią query; `idempotency` z właścicielem (`:self` / `:downstream` /
  `:infrastructure`), bo to różnica w kodzie efektu — przy `send_p1_report` z `:downstream` klucz idzie do P1.
  Właściciel zmienia kształt `idempotency:` każdej reakcji, więc to osobna decyzja o kształcie.
- **EP5 — systemy i granice, droga do sprawdzeń:** `capability` na `external` i `calls: {:p1, :submit_report}` w
  efekcie (reguły: wywołanie niezadeklarowanej zdolności, zdolność nieużywana); `responsibility` aktora jako nazwana
  proza; `terms` relacji jako pary słów z obu stron (czyta je słownik i reguła w duchu `label-with-avoided-term`;
  `terms` w `partnership` Rehmedu — do rozstrzygnięcia, ESDM ich tam nie ma).

**Odrzucone propozycje asystenta (3 października), każda z powodem:**
- `at-most-once` — zgubione zdarzenie wygląda jak niezaszłe, raport zgodności przestaje mierzyć
  (`docs/adr/technology-notes.md`, tabela transportów).
- `paradigm` — magazyn read modelu jest hosta; byłaby tylko podpowiedzią.
- `metadata` (`labels`, `annotations`) — bez czytelnika.
- Generatory tożsamości poza `:uuid` — w ESDM to tylko nazwa, nic jej nie wykonuje.
- `feature` i Domain Storytelling — bez zmian wobec 27 września.
- Tożsamość `static` — dopiero z przykładem bytu w jednej instancji z materiału.
- Sprawdzanie kodu wobec prozy przez LLM w CI — samo niedeterministyczne; najwyżej podpowiedź dla recenzenta,
  nie brama. Na później.

### EP1 — co wyszło (3 października)

Na `dsl/ep1-source` (od `origin/main` = `0b7bc84`, po rebase z `64f888b`), niewypchnięte.
- **`source:`** w kontrakcie na `policy`, `effect`, `process_manager`, `timer`, `read_model`, `query`, `process`;
  w domenie na `actor`, `subject`, `value`, `external`, `relation`. `subject` ponad listę z planu
  (rozstrzygnięcie asystenta: „pacjent” też jest z materiału, `A-01`). `consumes` i `publish` bez — to okablowanie
  między kontraktami, nie fakt z warsztatu.
- **Klucz w modelu zawsze, pusty poza digestem.** Kontrakt i domena bez `source:` mają te same wersje co przed
  EP1 — test przypina dosłownie wersje policzone kodem z `origin/main` (`304120633fb2`, `6111225e8fc9`).
  Pierwsza wersja usuwała pusty klucz z modelu (wzorzec z EM3); przegląd: to drugi kształt modelu obok rodzajów,
  które `source` miały od początku, i EP3 czytające `policy.source` padłoby na `KeyError`. Teraz `nil` znika
  dopiero w formie do digestu. Ustawienie albo zmiana źródła przesuwa digest deklaracji i wersję kontraktu, jak
  etykieta — tak samo jak dotąd w zdarzeniu i komendzie.
- **Czytelnik — `pages`:** `_Source: …_` na stronie deklaracji (polityka, efekt, process manager, read model,
  query — przez istniejący nagłówek), w sekcji procesu i na stronie wartości; przy aktorze, podmiocie, systemie,
  relacji i timerze w ich wierszu.
- **Sandbox jako dane testowe:** źródła przeniesione z komentarzy tylko tam, gdzie identyfikator wskazuje jedną
  deklarację — `P-07`, `A-01`, `X-01`, `X-02, X-03, X-04`, `E-55` w Rehmedzie; `03 §3` (dwie relacje),
  `03 §4.10`, `03 §5, step 2`, `P6`, `03 §4.2` w TaxVision. Pominięte: `# A-02, A-03, A-05` nad trzema aktorami
  (nie wiadomo, który do którego), relacje Rehmedu (komentarz nie mówi jednoznacznie, że opisuje każdą), aktorzy
  integracji TaxVision (komentarz mówi, że materiał ich nie nazywa).
- Słownik przypięty w obu testach słownictwa, `docs/dsl/` wygenerowane, linia w `CHANGELOG.md`.
- **Brama zielona** na `a80905d` (po rebase na #100 i poprawce z przeglądu): **EXIT=0**, sandbox 145 testów,
  `check` 0 / 29 / 9 (bez zmian); silnik 1157 (1135 przed rebase + testy #93–#100), `check` 0 / 68 / 6 (bez
  zmian); web 52; auth 285 + 1 właściwość. Część podejść padła na `too_many_connections` — wspólny Postgres
  zapchany przez procesy innej sesji, nie przez kod.
- **Przegląd** (dwa równolegle): poprawność — 8 uwag, poprawione cztery (kształt modelu, test digestu, który nie
  mógł paść, `view` w planie, relacja symetryczna bez testu); bezpieczeństwo i wydajność — bez defektu. Bez
  zmian: zmiana źródła przesuwa wersję (jak etykieta i `source` zdarzenia); `_Source: …_` bez escapowania, jak
  dotychczasowe strony; identyfikatory w komentarzach zostają tam, gdzie komentarz coś wyjaśnia. Odłożone do EP3
  (skille): w `source` identyfikatory z materiału, nie nazwiska — `source` idzie do modelu dla EHOS-a i na
  strony, a nic nie sprawdza w nim danych osobowych.

### Przed EP2 — decyzje użytkownika (3 października)

- **`invariant` encji — odłożony** (opcja (b)). Encja nie ma implementacji ani scenariuszy, więc inwariant stałby na
  szczeblu 0 bez drogi wyżej; wraca, gdy materiał da przykład. *Odrzucone:* (a) jak inwariant wartości, z
  `violated_by`/`satisfied_by` i funkcją w implementacji encji (nowy `use … entity:` bez przykładu w materiale).
- **`constraint` efektu — proza bez drogi wyżej.** Efekt nie jest celem scenariusza (S6: jego wynik jest poza
  logiem), więc jego ograniczenie stoi na szczeblu 0 i `check` o nim nie ostrzega — jawny wyjątek od drabiny, opisany
  w `docs/rules.md`, jak `reaction-without-scenario` pomija efekty. LLM dostaje regułę w EP3 (`@doc`). Przykład z
  materiału: `look_up_registries`, „adapter trzyma limity i retry” (03 §4.2). *Odrzucone:* bez `constraint` na
  efekcie (reguła zostaje w kodzie, poza kontraktem); scenariusze efektów najpierw (nowy mechanizm z fałszywym
  adapterem — osobny, duży etap).

### EP2 — co wyszło (3 października)

Na `dsl/ep2-rules` (od `origin/main` = `b6a96dd`, po #101), niewypchnięte.
- **DSL:** `constraint` w `policy`, `effect` i `process_manager`, `invariant` w `process_manager` (encja inwariantu
  jednostki z innym opisem); `illustrates:` w scenariuszu (atom albo lista).
- **S10** (nowa odmowa): `illustrates:` nazywa regułę, której cel scenariusza nie ma, albo jedną dwa razy; każde
  `illustrates:` na scenariuszu komendy — ta pokazuje swoje reguły przez `rejected`. **N1** rozszerzone:
  ograniczenia polityki i efektu raz każde, ograniczenia i inwarianty process managera razem.
- **`prose-without-scenario`** (nowe ostrzeżenie `check`): ograniczenie polityki, process managera albo query,
  inwariant process managera, którego żaden scenariusz deklaracji nie ilustruje. Bez efektu (decyzja wyżej) i bez
  deklaracji, której żaden scenariusz nie uruchamia — tę zgłasza raz `reaction-without-scenario`. S10 i `check`
  czytają jedną listę reguł, `Rules.Scenarios.illustratable/2`.
- **Czytelnicy:** `pages` (sekcje „Constraints”/„Invariants”, „— illustrates …” przy scenariuszu), `view
  --details` (reguły pod reakcją). `@doc` — EP3.
- **Model:** nowe klucze tylko tam, gdzie zadeklarowane; wersje przypięte w EP1 dalej się zgadzają.
- **Sandbox:** `report_on_clinical_close` ma `only_reported_services` (`P-07`), oba jej scenariusze je ilustrują;
  `look_up_registries` ma `within_registry_limits` („adapter trzyma limity i retry”, 03 §4.2) — proza efektu.
- **Przegląd** (dwa równolegle): poprawność — 10 uwag, poprawione: podwójne ostrzeżenie dla deklaracji bez
  scenariusza, mylący komunikat S10 na scenariuszu komendy, powtórzona nazwa w `illustrates:`, `view --details`
  bez reguł reakcji, powód „raport zgodności” podany też dla query w `rules.md`, zdublowana lista reguł w S10 i
  `check`, trzy kopie sekcji „Constraints” na stronach, kopia encji inwariantu, nazwa przykładu w planie, braki
  testów (query, timer, powtórzenie, linie fikstury liczone z treści). Bezpieczeństwo i wydajność — bez defektu;
  etykiety reguł bez escapowania na stronach i w modelu dla EHOS-a jak dotychczasowe etykiety.
- **Sprawdzenia odwrotne:** wyłączone S10, wyłączone ostrzeżenie, puste ograniczenia polityki w digeście, brak
  filtra deklaracji bez scenariusza, brak odmowy powtórzeń, stary `view.ex` — każde wywraca dokładnie swoje testy.
- **Brama zielona** na `e8c2b05`: **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1166, `check` 0 / 68 / 6
  (bez zmian: żaden istniejący kontrakt nie dostał `prose-without-scenario`); web 52; auth 285 + 1 właściwość.
  Wcześniejsze podejścia padały na `too_many_connections` albo stawały w testach silnika na wspólnym Postgresie
  zajętym przez inne sesje; same testy silnika z `--trace` przechodziły w 64 s.
- **Po rebase na `9b959e4`** (#103 — budżet bajtów klucza, #104): brama znowu zielona, **EXIT=0** — sandbox 145,
  `check` 0 / 29 / 9; silnik 1179 (1170 z `main` + 9 z EP2), `check` 0 / 71 / 6 — trzy ostrzeżenia więcej
  przyniósł #103 (tyle zapisuje plan na `main`), żadnego `prose-without-scenario`; web 52; auth 285 + 1 właściwość.

### EP3 — co wyszło (3 października)

Na `dsl/ep3-docs` (od `origin/main` = `24904b8`, po #105 i #106), niewypchnięte.
- **`EhOsContract.Contract.Doc`** składa z modelu kontraktu `@doc` każdego callbacku wygenerowanego behaviouru i
  rozszerza jego `@moduledoc`: etykieta i źródło deklaracji, co wolno wyemitować albo wydać, reguły, które tam
  obowiązują — każda ze szczeblem drabiny (scenariusz, który na niej odmawia albo ją ilustruje, albo „prose
  alone”) — i scenariusze callbacku. Zdarzenie konsumowane mówi, skąd przychodzi: jego etykieta jest u
  rodzeństwa albo w innej aplikacji, a kontrakt nie kompiluje się względem nich (rozstrzygnięcie asystenta: bez
  zależności kompilacyjnej między kontraktami). `b <Behaviour>.<callback>` w IEx to wypisuje — sprawdzone na
  `report_on_clinical_close`. Model, digest i wersje bez zmian.
- **Sandbox:** `ReportOnClinicalClose` nie powtarza już reguły `P-07` w `@moduledoc`, tylko wskazuje
  ograniczenie kontraktu.
- **Skille:** `write-decider` i `write-reaction` startują od nazwanych reguł i ich scenariuszy, czytają `b`
  callbacku i nie powtarzają reguły w moduledocu; `write-reaction` każe dać regule scenariusz z `illustrates:`
  przed kodem. `contract-distillation` i `add-event`: w `source:` identyfikator materiału, nigdy nazwisko
  (odłożone z przeglądu EP1).
- `docs/contract.md` — akapit o dokumentacji callbacków; CHANGELOG.
- **Przegląd** (dwa równolegle): poprawność — 9 uwag, wszystkie poprawione: callback komendy pisał „prose alone” o
  inwariancie, na którym odmawia scenariusz innej komendy (sprzeczne z moduledociem, a S8 jest spełnione); moduł
  query, będący też behaviourem, nie dostawał moduledocu z regułami; „Dcb” zamiast „Dynamic consistency
  boundary”; timer bez źródła; reguły jednostki bez ograniczeń komend; `evolve` process managera mówiło o
  „decision”; dopasowanie zdarzenia konsumowanego obok `Model.consumed/2` (przy przemianowaniu mogło wskazać nie
  tego sąsiada); reguły serwisu poza wspólnym formatem; braki testów (reakcja process managera, serwis, timer
  dosłownie, granica i query w skompilowanych chunkach). Bezpieczeństwo i wydajność — bez defektu; opisy
  scenariuszy trafiają teraz do dokumentacji, więc `contract-distillation` mówi, że opis nazywa przypadek, nigdy
  prawdziwą osobę. Każda poprawka sprawdzona odwrotnie.
- **Brama zielona** na `c042d42`: **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1184 (1179 + 5), `check`
  0 / 71 / 6 (bez zmian); web 52; auth 285 + 1 właściwość.

### Przed EP4 — decyzje użytkownika (3 października)

- **Oczekiwany stan process managera — `state %{…}` w scenariuszu.** Nowy wynik obok `issues`/`sets`: pola, które
  run trzyma po wyzwalaczu, porównane częściowo; odmowa, gdy pola nie ma w stanie. Przykład z materiału:
  `monthly_registry_check` po `data_completeness_confirmed` ze stycznia ma `check_at` = 1 lutego, a gałęzi
  `evolve`, w której potwierdzenie innego miesiąca zostawia datę, nic dziś nie sprawdza. *Odrzucone:* sama data
  timera (`sets :next_month, at: …`) — węższe, nie złapie pola stanu, które nie jest datą timera; nic nie robić —
  gałąź „inny miesiąc” zostaje bez testu.
- **Wiersze read modelu w scenariuszu — odrzucone.** Magazyn read modelu jest hosta (ten sam powód co odrzucone
  `paradigm`); wykonywalnym sprawdzeniem zostaje `answers` query. *Odrzucone:* `rows [...]` w scenariuszu
  (nowy callback oddający wiersze silnikowi i deklaracja opisująca wiersze, nie odpowiedź); najpierw rozstrzygnąć,
  co deklaruje `read_model`. **Ustalenie przy pytaniu:** `daily_totals` deklaruje `business_date, method, total`,
  a `Rehmed.Settlement.DailyTotals` trzyma wiersz na płatność z `amount` — zadeklarowany kształt jest kształtem
  odpowiedzi, nie wierszy. Osobna sprawa, bez etapu.
- **`idempotency: [key: :event_id, owner: :self]`** — `owner` w `:self | :downstream | :infrastructure`, oba
  wymagane; zmienia kształt każdej reakcji, bez zgodności wstecz. *Odrzucone:* osobny klucz `idempotency_owner:`
  obok (bez zmiany deklaracji, ale dwa klucze, które znaczą razem, i właściciel opcjonalny); nic nie robić
  (właściciel w kodzie i moduledocu).

### EP4 — co wyszło (3 października)

Na `dsl/ep4-executable` (od `origin/main` = `8f685cf`, po #108).
- **`state` w scenariuszu process managera.** `ScenarioCase` składa krok tak jak runtime
  (`EhOsContract.ProcessManager`): callback dostaje stan sprzed zdarzenia, potem `evolve/2` składa zdarzenie; po
  timerze stan się nie zmienia. Porównanie na wymienionych polach, jak `expect`. S3: pole spoza stanu i
  korelacji, wartość złego typu; S6: `state` dwa razy, `state` w scenariuszu komendy, polityki, query; sam `state`
  wystarcza za wynik. W modelu tylko tam, gdzie jest — żadna inna wersja się nie rusza.
- **Sandbox:** `monthly_registry_check` ma trzy scenariusze stanu — pierwsze potwierdzenie (1 lutego), sprawdzony
  miesiąc przesuwa datę (1 marca), inny miesiąc jej nie rusza. Sprawdzenie odwrotne: gałąź „inny miesiąc”
  przesuwająca datę wywraca scenariusz (i dwa starsze testy runtime `AccountingMonthTest`).
- **`idempotency`:** w modelu mapa `%{key:, owner:}`. P3 odmawia `owner: :downstream` poza efektem — polityka i
  process manager wydają komendy temu silnikowi, a ten kluczuje je sam (`Consumer.reaction_key/5`), więc
  polityki w fiksturach dostały `:infrastructure`. `send_p1_report` — `:downstream` (P1 dostaje klucz;
  sandbox bez P1 kluczuje zapis); `look_up_registries` — `:self`. Jedno zdanie o właścicielu w `@doc`
  callbacku i na stronie reakcji (`Doc.idempotency/1`).
- **Wersje:** każdy kontrakt z `idempotency` ma nową wersję. Przypięte wersje przesunięte świadomie, z
  komentarzem: `sources_test` (`304120633fb2` → `0233079a0430`), księga `DispatchRig.Ledger` (`4e94b8af0057` →
  `06808eb90e9f`). Linia w CHANGELOG.
- **`docs/adr/contract-v2.md`:** poprawka z datą przy §4.6 (efekt z `idempotency: :downstream` — test kompiluje
  tę sekcję dosłownie, więc linia przepisana) i przy P3.
- `docs/contract.md` (akapit, wiersze P3 i S6), `docs/dsl/`, `.formatter.exs`, skill `write-reaction`.
- **Brama zielona** przed przeglądem: **EXIT=0** — sandbox 148 (145 + 3 scenariusze stanu), `check` 0 / 29 / 9;
  silnik 1194 (1184 + 10), `check` 0 / 71 / 6 (bez zmian); web 52; auth 285 + 1 właściwość.
- **Przegląd** (dwa równolegle). Poprawione, każde osobnym commitem ze sprawdzeniem odwrotnym:
  - efekt z `owner: :infrastructure` kompilował się, a `@doc` obiecywał deduplikację przez silnik, której
    `EffectJob` nie robi; `:infrastructure` z kluczem innym niż `:event_id` też. P3 odmawia obu;
  - eksport modelu dla EHOS-a nie redagował `state` scenariusza;
  - wartość korelacji podana w `state` budowała run, więc asercja nie mogła paść;
  - runner składał stan także z kroku, którego silnik nie bierze (`given` przed startem runu, wyzwalacz po
    `ends_on`); scenariusz ze `state` teraz na tym pada. Scenariusze bez `state` jak dotąd;
  - CHANGELOG: nowy kształt `idempotency` w „Changed — a host has to act”.

  Bez zmian:
  - `send_p1_report` z `:downstream`, choć sandbox kluczuje zapis: deklaracja opisuje host z P1, a moduledoc mówi,
    że sandbox P1 nie ma;
  - zdublowane zdanie „holds …” w `pages` i `Doc` oraz drugie budowanie zdarzenia w `held!` — kosmetyka.

  Pominięte, poza zakresem:
  - `key` przy `:self`/`:downstream` to dowolny atom; sprawdzanie go wobec pól obsługiwanych zdarzeń to nowa
    reguła;
  - pole korelacji w S3 sprawdzane jak `:id` — wartość złego typu pada dopiero w teście, z nazwą pola.

  Bezpieczeństwo i wydajność: poza powyższym bez defektu. Do stron trafiają tylko nazwy pól stanu, nie wartości.
- **CodeRabbit (#109), jedna uwaga — poprawiona:** scenariusz ze `state`, którego zdarzenia mają dwie wartości
  korelacji (`given` wizyty A, wyzwalacz wizyty B), składał je w jeden stan, a runtime założyłby dwa runy. Taki
  scenariusz teraz pada. Przegląd poprawki: to samo dotyczyło **każdego** scenariusza process managera (np. z
  `issues`), więc sprawdzenie stoi przed składaniem stanu, dla wszystkich; linia w CHANGELOG. Bez zmian:
  porównanie przed rzutowaniem (korelacja to `:id` albo identyfikator — F8 — więc surowe dane wystarczają).
  Pominięte: pole korelacji spoza tożsamości jednostki, pominięte w danych — silnik nie bierze takiego zdarzenia,
  runner je składa; sprzed EP4, osobna sprawa.
- **Brama zielona po przeglądzie:** **EXIT=0** — sandbox 148, `check` 0 / 29 / 9; silnik 1198, `check` 0 / 71 / 6;
  web 52; auth 285 + 1 właściwość.

### Przed EP5 — decyzje użytkownika (3 października)

- **Operacje systemu zewnętrznego (ESDM: `capabilities`) — opcjonalne, ścisłe, gdy są.** System w domenie może
  zadeklarować operacje (`operation :submit_report, "…", source: "X-01"`); gdy je ma, każde `calls:` do niego nazywa
  jedną
  (`calls: {:p1, :submit_report}`), a goły `:p1` jest odmową. Odmowa: operacja, której system nie deklaruje;
  ostrzeżenie `check`: operacja, której nie woła żaden efekt. **Nazwa `operation`, nie `capability`** (decyzja
  użytkownika, tego samego dnia): „capability” to w tej bibliotece uprawnienie aktora z EHOS-a
  (`EhOsContract.Capability`, `Model.capabilities/1`). *Odrzucone:* `capability` jak ESDM (dwa znaczenia jednego
  słowa w jednej bibliotece); `offers` (czasownik, słabo czyta się jako rzeczownik w modelu i komunikatach). *Odrzucone:* zawsze wymagane (łamie każdy kontrakt
  z `calls:`, a system tylko wejściowy, jak KSeF, musiałby coś deklarować); sama proza bez reguł (nic nie łączy
  efektu z tym, o co prosi).
- **`responsibility` aktora — nazwana proza, szczebel 0.** `responsibility :name, "tekst", source:` w aktorze;
  czytają strony, słownik i `@doc` komend, które aktor wydaje. Przykład: 03 §4.10, „zakres pracy wynika z
  obowiązków, nie uprawnień”. *Odrzucone:* powiązanie `fulfils:` w komendzie z ostrzeżeniem (nowe słowo bez
  przykładu, który by go wymagał — kształt pozwala je dodać później); pominięcie.
- **`terms` relacji — pary, także w partnerstwie.** `terms: [{"Wizyta", "Wizyta"}]`, słowo pierwszej i drugiej
  strony, każde sprawdzane wobec słownika swojego kontekstu. Świadome odstępstwo od ESDM, który w relacji bez
  kierunku terminów nie ma: Rehmed ich tam potrzebuje („Wizyta” znaczy co innego w umawianiu i w dokumentacji).
  *Odrzucone:* pary tylko w relacjach z kierunkiem, jak ESDM (Rehmed traci terminy partnerstwa); płaska lista ze
  sprawdzeniem (nie mówi, które słowo odpowiada któremu).
- **Podział (rozstrzygnięcie asystenta):** EP5a — operacje z regułami; EP5b — odpowiedzialność i pary terminów.
  Dwa PR-y, bo operacje dotykają domeny, kontraktu, wiązania między nimi i `check`.

### EP5a — co wyszło (3 października)

Na `dsl/ep5a-capabilities` (od `origin/main` = `64a7864`, po #109).
- **Domena:** `operation :name, "…", source:` w `external`; D1 — nazwa snake_case, raz w systemie. Model trzyma
  `operations: []` zawsze, digest pomija pustą listę — wersje domen bez operacji bez zmian (pilnuje tego wersja
  przypięta w EP1).
- **Kontrakt:** `calls:` przyjmuje `:p1` albo `{:p1, :submit_report}`. W modelu `calls` zostaje listą systemów
  (każdy dotychczasowy czytelnik — graf, `check`, zależności, raport — bez zmian), a nazwane operacje idą do
  `operations` tylko tam, gdzie są.
- **X4** (L3, bo kontrakt nie kompiluje się względem domeny): operacja, której system nie deklaruje (z podpowiedzią),
  i goły `calls:` do systemu z operacjami (z listą do wyboru). **`operation-never-called`** — ostrzeżenie `check`.
- **Czytelnicy:** `@doc` callbacku efektu i jego strona („Calls `p1` (`submit_report`).”, `Doc.calls/1`), strona
  domeny — operacje pod systemem.
- **Sandbox:** `:p1` — `submit_report` (`X-01, AGG-10`), `:registries` — `look_up_company` (03 §4.2); oba efekty
  nazywają swoją. Na żywo: goły `calls: :p1` w Rehmedzie — kompilacja pada z X4 i podpowiedzią.
- **Sprawdzenia odwrotne:** bez ochrony digestu pada wersja domeny z EP1; bez X4 dla operacji — test odmów; bez
  ostrzeżenia — test `check`.
- `docs/contract.md`, `docs/dsl/`, `docs/rules.md`, skille `write-reaction` i `contract-distillation`, CHANGELOG.
- **Przegląd** (dwa równolegle). Poprawione, ze sprawdzeniem odwrotnym: powtórzone wywołanie
  (`[{:p1, :a}, {:p1, :a}]`) dwa razy w modelu i dwie identyczne odmowy X4; `Enum.uniq` na `calls` także
  efektów bez operacji (mógł przesunąć digest); ostrzeżenie o operacjach systemu, którego żaden efekt nie woła,
  obok `orphan-external-system` — teraz tylko dla wołanego systemu; ostrzeżenie wskazywało linię systemu, nie
  operacji; niezrozumiały komunikat dla `{:mail, :send}` przy systemie bez operacji; strona efektu traciła
  dwukropek („Calls:”) także bez operacji; nawiasy przy `operation` w sandboxie. Bez zmian: etykieta operacji na
  stronie bez escapowania (jak każda etykieta, string autora kontraktu); pojedyncze backticki (nazwy snake_case
  z D1); P2 drukuje krotki w `calls` (tylko komunikat). Pominięte: operacje na systemie `:inbound` (ostrzeżenie je
  pokaże; reguła byłaby nowa); graf i `view` bez operacji; test digestu porównuje dwie domeny nowym kodem —
  przesunięcie łapie wersja przypięta w EP1.
- **Brama zielona po przeglądzie:** **EXIT=0** — sandbox 148, `check` 0 / 29 / 9; silnik 1208, `check` 0 / 71 / 6;
  web 52; auth 285 + 1 właściwość. Pierwsze podejście padło na formacie: stary `cached_dot_formatter` w
  `_build/test` sprzed nowego słowa (pułapka opisana w `sandbox/mix.exs`); po jego usunięciu czysto.
- **Brama zielona** przed przeglądem: **EXIT=0** — sandbox 148, `check` 0 / 29 / 9 (bez zmian: obie operacje
  sandboxa są wołane); silnik 1206 (1198 + 8), `check` 0 / 71 / 6; web 52; auth 285 + 1 właściwość.

### EP5b — co wyszło (4 października)

Na `dsl/ep5b-actors-relations` (od `dsl/ep5a-capabilities`, #111). W `main` przez #112; #114 cofnął je przypadkiem,
#115 przywrócił (drzewo jak po #112) i dołożył poprawkę z przeglądu CodeRabbita: termin bez tłumaczenia na żądany
język zachowuje w słowniku linię pary relacji.
- **`responsibility`** w aktorze — `name`, `label`, `source`; D1: snake_case, raz w aktorze. Model trzyma listę
  zawsze, digest pomija pustą. **Czytelnicy: strona domeny** (pod aktorem). **Odstępstwo od decyzji — `@doc`
  komend nie czyta odpowiedzialności** (rozstrzygnięcie asystenta): `@doc` składa się przy kompilacji
  kontraktu z jego modelu, a kontrakt nie kompiluje się względem domeny (v2 §8 — zależność kompilacyjna
  rekompilowałaby każdy kontrakt przy zmianie domeny). Słownik też nie — jest per kontekst, a aktor nie
  musi mieć kontekstu. Zostaje strona.
- **`terms` relacji jako pary** `{"Wizyta", "Wizyta"}`, w modelu `[["Wizyta", "Wizyta"]]` (dla JSON-a). Pierwsze
  słowo — upstream albo pierwszy z `between:`. **D5**: słowo końca-kontekstu musi być terminem jego słownika;
  koniec-system (np. `upstream: :p1`) słownika nie ma, więc jego słowo nie jest sprawdzane. W relacji
  symetrycznej digest czyta pary w kolejności posortowanych końców — `between` zapisane odwrotnie z
  odwróconymi parami daje tę samą wersję.
- **Słownik** pod terminem: „_In `clinical_documentation` (partnership): "Wizyta"._” — sprawdzone na Rehmedzie
  (`mix eh_os_contract.glossary --domain rehmed`). **Strona domeny**: „· terms: "Wizyta" ↔ "Wizyta"” przy
  relacji.
- **Sandbox:** partnerstwo Rehmedu w parach; `manager` — `overdue_reports` (`P-25`); `accountant` w TaxVision —
  `company_month` (03 §4.10, HS28) i `registry_discrepancy` (03 §4.2).
- **Sprawdzenia odwrotne:** ochrona digestu odpowiedzialności (pada wersja domeny z EP1), kolejność par w
  partnerstwie, D5, słownik — każde wywraca swój test.
- `docs/contract.md`, `docs/dsl/`, skill `contract-distillation`, CHANGELOG.
- **Przegląd** (dwa równolegle). Poprawione, ze sprawdzeniem odwrotnym: strona kontekstu nie pokazywała pary, którą
  pokazuje słownik (teraz oba czytają `Glossary.across/3`); słownik przedstawiał koniec-system jak kontekst ze
  słownikiem („_In external `p1`_”) i gubił parę w tłumaczeniu (`--language`); dwie kopie „który koniec pierwszy”
  (teraz `Domain.Build.sides/1`); `pairs/1` rozpoznawało relację po kształcie mapy (teraz po rodzaju); powtórzona
  para przechodziła (D1); test kierunku nie łapał zamiany końców (para lustrzana dawała te same komunikaty);
  pomocnicze `digest_form` w `domain_rules_test` nie znało operacji, odpowiedzialności ani par; komentarz o
  słowniku jako czytelniku odpowiedzialności. CHANGELOG: kształt `terms` w eksporcie modelu. Bez zmian: etykiety
  i słowa bez escapowania na stronach (jak każda etykieta); stary płaski `terms` daje ogólny błąd Sparka, nie kod D
  (bez zgodności wstecz, jedno użycie w sandboxie).
- **Brama zielona po przeglądzie:** **EXIT=0** — sandbox 148, `check` 0 / 29 / 9; silnik 1216, `check` 0 / 71 / 6;
  web 52; auth 285 + 1 właściwość.

## Dopisek 2 października (2) — #83: `ehos.yaml/v2` i `sign_in`; podział EB2

**Decyzje użytkownika (2 października, wieczorem):**

- **EB2 to dwa PR-y**: EB2a — przechowywanie (V03, szyfrowanie z S3, kontekst klienta z `from_manual/5`, losowy
  `client_secret`, klucz JWK poza argumentami funkcji, które mogą paść, endpoint tokenu w `FakeEhos` i `kid` w
  asercji), EB2b — przeglądarka (router, plug `Session`, `actor/1`, wylogowanie), domyka #81. *Odrzucone:* jeden PR,
  jak w tabeli części — diff za duży, żeby go przeczytać z uwagą.
- **[#83](https://github.com/EmpoweredHouse/eh-os-contract/issues/83) idzie przed EB2a**, osobnym małym PR-em.
  *Odrzucone:* po EB2a albo po całym EB. #83 nie zależy od EB, a bez niego nic nie zaloguje nikogo na klastrze: EHOS
  daje workloadowi `EHOS_CLIENT_ID` i klucz klienta tylko wtedy, gdy manifest ma `sign_in` (D-69).
- **Zgłoszenie wad `oidcc` w `erlef/oidcc`** — użytkownik zlecił je asystentowi, tego samego dnia: erlef/oidcc#552–#555.

**Co ustalono przy czytaniu EHOS-a** (`main` = `2cd95cb`; `ehos.yaml/v2` z
[eh-os#147](https://github.com/EmpoweredHouse/eh-os/pull/147), `99e036b`, w żadnym wydaniu):

- **Schemat v2 to v1 plus jedno**: klucz `sign_in`, obiekt z opcjonalnym `applications` — najwyżej 16 różnych nazw
  aplikacji w regule EHOS-a (`$defs.application`). `const` i `title` mówią `v2`.
- **Obok schematu EHOS sprawdza dwie rzeczy** (`Ehos.Applications.EhosYaml.V2`):
  - `sign_in` wymaga wpisu `serves` o nazwie `web` z `public: true` (domyślnie `public` to `false`);
  - `applications` nie wymienia aplikacji, którą nazywa plik; w manifeście — aplikacji manifestu
    (`Manifest.V2.own_application/2`).
- **Manifest trzyma `sign_in` w tym samym miejscu**, także puste, bo `sign_in: {}` coś znaczy. Generator już dziś
  przenosi każdy klucz `ehos.yaml` bez zmian, więc `sign_in` przejdzie sam, gdy czytnik przyjmie v2.

**Plan #83** (gałąź `eh/issue-83-ehos-yaml-v2`, od `7a2bcb7`):

- `priv/schemas/ehos.yaml/v2.json` — kopia pliku EHOS-a bajt w bajt, z przypiętym SHA-256 jak v1; `versions/0` daje
  obie wersje.
- **Dwie reguły EHOS-a obok schematu, tylko te od `sign_in`, sprawdzane tutaj.** Czytnik odrzuca `sign_in` bez
  publicznego `web` i `applications` z nazwą z `application` pliku; generator odrzuca `applications` z nazwą
  aplikacji, którą sam wyliczył z domeny, bo `ehos.yaml` zwykle jej nie pisze. Wybór asystenta, jak prosi #83.
  *Odrzucone:* zostawić je EHOS-owi, jak unikalne nazwy i porty w `serves`. Tamte łamie literówka, którą widać w
  pliku; te dwie łamie samo dopisanie `sign_in`, a odmowa przy wdrożeniu przychodzi dopiero po zbudowaniu obrazu.
- Testy: plik v2 przyjęty; odmowy w korpusie (`sign_in` bez publicznego `web`, `sign_in` w v1, powtórzona nazwa,
  własna aplikacja); manifest z `sign_in` równy napisanemu ręcznie.

### #83 — co wyszło (2 października)

Gałąź `eh/issue-83-ehos-yaml-v2`, od `7a2bcb7`. Zrobione według planu wyżej:
- `ehos.yaml/v2.json` jest kopią z przypiętym SHA-256 `de53…8c38` (blob `750773f`, ten sam co w `main` EHOS-a).
- Czytnik sprawdza obie reguły `sign_in` po schemacie, jak EHOS. Plik, który odrzuca schemat, dostaje tylko powody
  schematu.
- Generator odrzuca `applications` z nazwą aplikacji, którą znalazł.
- Nowy powód dla `uniqueItems`: „must list each value once”.
- Auth: 180 → 191 testów.

**Przegląd przed PR-em**, dwa równolegle:
- **Bezpieczeństwo i wydajność:** nic istotnego. Nowy kod widzi tylko plik, który przeszedł schemat; `sign_in` nie
  niesie sekretu; kopia schematu zgadza się bajt w bajt.
- **Poprawność:** zachowanie zgodne z EHOS-em w każdym sprawdzonym przypadku. Poprawione:
  - dwie asercje, które pasowały do każdej mapy;
  - brakujące przypadki: `web` z `public: false` obok publicznego `api` i plik łamiący obie reguły naraz;
  - `@doc` `read/1` obiecywał „każdy powód”, choć reguły `sign_in` działają dopiero po schemacie;
  - przykład v2 w README bez `health`.

  Każdy nowy test ma próbę odwrotną.
- **Bez zmian:**
  - `Manifest.build/3` na `applications`, które nie jest listą, rzuca `Protocol.UndefinedError` (zgłosiły oba
    przeglądy). `build/3` bierze mapę z `read/1`, a task zawsze ją tak buduje;
  - reguły `sign_in` nie są związane z wersją. Pozwala na nie tylko v2, a v3 to nowa kopia i nowy przegląd;
  - manifest oczekiwany napisany ręcznie z tego samego pliku. EHOS nie ma fikstury manifestu z `sign_in`; kształt
    sprawdzony w `Manifest.V2`.
- Informacyjnie: EHOS liczy `sign_in` do skrótu manifestu, nie do skrótu uprawnień, więc dopisanie aplikacji nie
  wymaga `ehos.application.register`. Zgoda drugiej strony to D-64, po stronie EHOS-a.

**Sprawdzone na żywo:** `mix eh_os_contract.manifest` w `MIX_ENV=dev` w `sandbox/` na pliku v2 ze scratchpada.
`application: rehmed` z `sign_in.applications: [taxvision]` daje manifest z `ehos_yaml: "ehos.yaml/v2"` i tym samym
`sign_in`. Z `[rehmed]` task odmawia z linią 8 i ścieżką `sign_in.applications[0]`.

## Dopisek 2 października — EB: sesja przeglądarki w `eh_os_contract_auth` (#78), plan

[#78](https://github.com/EmpoweredHouse/eh-os-contract/issues/78): drugi Plug w `eh_os_contract_auth`, dla sesji
przeglądarki zamiast tokenu bearer. To krok 6 etapu 9 EHOS-a i odpowiedź na
[eh-os#95](https://github.com/EmpoweredHouse/eh-os/issues/95). Protokół rozstrzygają `eh-os` D-64 i D-66. To, co
zostawiają pakietowi, jest w **[`docs/adr/browser-session.md`](docs/adr/browser-session.md)** (S1–S11, `proposed`).
Ten dopisek zapisuje plan i decyzje użytkownika.

**Co ustalono przy czytaniu źródeł** (`oidcc` 3.9.0, `oidcc_plug` 0.5.1, `jose` 1.11.12; EHOS `main` z 2
października):

- **Refresh przez `Oidcc.refresh_token/5` nie działa z EHOS-em w dzisiejszej postaci.** EHOS odpowiada na refresh
  bez ID tokenu (`response(issued, rotated.token, nil)` w `lib/ehos/sign_in/token.ex`). `oidcc_token:refresh/3`
  zwraca wtedy `{error, sub_invalid}`, i to **po** wywołaniu, więc zrotowany refresh token przepada. Każda sesja
  skończyłaby się przy pierwszym odnowieniu.
- **`oidcc` po cichu słabnie**, gdy discovery czegoś nie mówi. `iss` jest sprawdzany tylko przy
  `authorization_response_iss_parameter_supported: true`. PKCE znika bez `code_challenge_methods_supported`. Z
  `private_key_jwt` spada na kolejną metodę. Discovery EHOS-a dziś mówi wszystko, czego trzeba, ale pakiet
  wymusza te rzeczy sam (S6).
- **`oidcc_plug` 0.5.1 wymaga `oidcc ~> 3.7`.** CVE-2026-75759 naprawia dopiero 3.9.0, więc `oidcc` przypinamy
  osobno. `oidcc` wymaga OTP 27; CI ma 27.2.
- **`oidcc_plug` trzyma nonce i weryfikator PKCE w sesji Plug**, czyli w ciasteczku hosta. Host musi je szyfrować
  (S2).
- **`oidcc` ma wymienny adapter HTTP** (`oidcc_http_adapter`), więc testy grają EHOS-a funkcją, bez portu, jak
  JWKS w `KeyCase`.
- **Luki po stronie EHOS-a:**
  - workload nie zna adresów innych aplikacji, a `resource` to adres — `sign_in.applications` podaje nazwy;
  - format `EHOS_CLIENT_KEY_FILE` nie jest ustalony;
  - `post_logout_redirect_uri` nie jest wyliczany.

**Decyzje użytkownika (2 października):**

- **Refresh: EHOS zwraca ID token także przy refreshu** — [eh-os#133](https://github.com/EmpoweredHouse/eh-os/issues/133)
  (S10). *Odrzucone:* własne żądanie odnowienia — asercja `private_key_jwt` przez JOSE, POST przez Req,
  credential sprawdzany `verify/2`. Nie czekałoby na EHOS, ale przenosi kod protokołu z certyfikowanej biblioteki
  do naszego i odchodzi od D-64.
- **Luki jako issues w `eh-os`:** adresy innych aplikacji —
  [eh-os#134](https://github.com/EmpoweredHouse/eh-os/issues/134); format klucza klienta i
  `post_logout_redirect_uri` — [eh-os#135](https://github.com/EmpoweredHouse/eh-os/issues/135). Do czasu odpowiedzi
  obie rzeczy są w konfiguracji.
- **Interfejs** (S7):
  - dziecko `EhOsContract.Auth.SignIn` z `config :eh_os_contract_auth, sign_in: [...]`;
  - `forward "/auth/ehos", EhOsContract.Auth.SignIn.Router` (logowanie, callback, wylogowanie);
  - plug `EhOsContract.Auth.Session`;
  - `Session.actor/1` i `Session.credential/2` — tylko w tych dwóch funkcjach odbywa się odnawianie.

  *Odrzucone:* plug, który odnawia przy każdym żądaniu strony. Odnawiałby także dla stron, które niczego nie
  wołają, wbrew „on demand only” z D-64.
- **Refresh token, ID token i credentiale szyfrowane w tabeli kluczem z `SECRET_KEY_BASE`** (S3), z ADR-em —
  decyzja zmieniona tego samego dnia.
  - **Jak:** `Plug.Crypto.KeyGenerator` i `MessageEncryptor` (w `plug_crypto` 2.x XChaCha20-Poly1305); dane
    powiązane to hash sesji i kolumna; opcja `secret_key_base:` w `sign_in:`.
  - **Pierwszy wybór był inny:** bez szyfrowania, bo bez klucza prywatnego klienta (`private_key_jwt`) refresh
    token niczego nie odnowi.
  - **Dlaczego zmiana:** komentarz CodeRabbita do #79 pokazał, że credentiale da się odtworzyć z każdej kopii
    bazy, póki nie wygasną (do 10 minut), także credentiale innych aplikacji (S8). A argument „rotacja
    `SECRET_KEY_BASE` wylogowuje wszystkich” był chybiony: ciasteczko sesji podpisuje ten sam klucz, więc jego
    rotacja i tak wylogowuje. Koszt: około 50–80 linii z testami w EB2.

  *Odrzucone:*
  - bez szyfrowania — zostawia credentiale w backupie, replice i zrzucie;
  - osobny klucz od EHOS-a — drugi sekret do dostarczania bez zysku;
  - vault silnika — jest od crypto-shreddingu danych osobowych;
  - `pgcrypto` — klucz jechałby do bazy z każdym zapytaniem.
- **Decyzje pakietu idą do ADR-a** (`docs/adr/browser-session.md`), nie tylko tutaj. Zapisuje je z odrzuconymi
  opcjami: S1 zależności, S2 ciasteczko, S4 dzierżawa, S5 skutki odmów, S6 nadpisane domyślne, S8 credential
  innej aplikacji, S9 ID token jako bearer, S11 bez joba. Status `proposed`, do akceptacji przez właściciela
  produktu.

**Mechanika rozstrzygnięta przez asystenta** (wyjaśnienie i odrzucone opcje w ADR-ze):

- dzierżawa w kolumnach wiersza sesji, brana jednym `UPDATE … RETURNING` z zegarem bazy, zapis po wywołaniu z
  `WHERE lease_holder = $me`;
- liczby: 30 s zapasu ważności, 15 s dzierżawy, 10 s timeoutu wywołania, czekający co 200 ms najwyżej 15 s;
- `invalid_target` zapamiętany na 10 minut;
- `check_peer_ip: false` (ingress z kilkoma podami) i `retrieve_userinfo: false`.

**Części** (gałęzie od `main`, jak EA — każda następna od poprzedniej):

| Część | Zakres | Czeka na |
| --- | --- | --- |
| **EB1** | Testy: ID token jako bearer odrzucony (`:bad_signature`), credential z `client_id` przyjęty. Zależności `oidcc ~> 3.9`, `oidcc_plug ~> 0.5.1`. `EhOsContract.Auth.SignIn`: konfiguracja, klucz klienta jako JWK D-68 (PEM i inny kształt odrzucone przy starcie), worker dostawcy, sprawdzenie discovery przed pierwszym logowaniem. README: OTP 27. | — |
| **EB2** | Migracja V03: `eh_os_contract_auth_sessions` (hash tokenu sesji, `subject`, `sid`, `auth_time`, `refresh_token`, `id_token`, kolumny dzierżawy) i `eh_os_contract_auth_session_credentials` (`session_id`, `resource`, `token`, `expires_at`, `refused_until`); tokeny szyfrowane (S3). Router: logowanie, callback, wylogowanie. Plug `Session`, `actor/1` na credentialu z wymiany kodu. Fałszywy EHOS jako adapter `oidcc` w `test/support/`. | — |
| **EB3** | Dzierżawa i `refresh_token/5`, `resource` dla innych aplikacji, `credential/2`, skutki z S5, timeouty. `CommitRepo` i baza `eh_os_contract_auth_test_commits` do testów na prawdziwych commitach (współbieżność, brak transakcji). Test `Oidcc.refresh_token/5` bez mocka na odpowiedzi w kształcie z #80. | — (eh-os#133 w `main` EHOS-a; testy na `main`, nie na wydaniu) |

Do każdej części: CHANGELOG, README („Signing people in”), `@doc` i `@spec`, eksporty `Boundary`, przegląd
`pre-pr-review`. Sandbox bez zmian — nie ma w nim EHOS-a. Pierwszym konsumentem jest szablon `ehos_app`
(krok 7 EHOS-a), a dowodem całości jego test klastrowy (krok 8).

*Odbiór:* kryteria z #78, każde testem — mapa w „Confirmation” ADR-a.

**Odpowiedź EHOS-a, 2 października, po południu.** Zespół EHOS założył u nas dwa issues:

- **[#80](https://github.com/EmpoweredHouse/eh-os-contract/issues/80): refresh zwraca ID token.**
  - Sprawdzone na `main` EHOS-a: `rotated/5` w `lib/ehos/sign_in/token.ex` mintuje go przez `id_token/3`.
    Najnowszy tag to `v0.3.0`, bez tej zmiany.
  - EB3 rusza bez czekania, testy na `main` EHOS-a. S10 w ADR-ze ma notkę z datą.
  - Wiersz sesji trzyma ID token z każdego odnowienia. Pierwszy też by działał, bo EHOS sprawdza w
    `id_token_hint` tylko `sub`, `sid` i `auth_time`. Wybór asystenta: brak kosztu, a w wierszu zostaje
    najnowszy podpisany token.
  - Test pełnego `Oidcc.refresh_token/5` jest u nas, na odpowiedzi fałszywego EHOS-a w kształcie z #80.
    Prawdziwy endpoint sprawdza krok 8 EHOS-a.
- **[#81](https://github.com/EmpoweredHouse/eh-os-contract/issues/81): `eh-os` D-68**, `proposed`, w `main` przez
  eh-os#140. Ustala trzy rzeczy:
  - plik klucza to tylko JWK z `kid` (odcisk RFC 7638), `use: "sig"` i `alg: "Ed25519"` — bez PEM;
  - `post_logout_redirect_uri` to dokładnie `https://<host>/`;
  - `EHOS_SIGN_IN_APPLICATIONS` to obiekt JSON nazwa → `https://<aplikacja>.<środowisko>.<domena>`.

  **D-68 przyjęte przez użytkownika 2 października.** Akceptacja to
  [eh-os#141](https://github.com/EmpoweredHouse/eh-os/pull/141), w chwili zapisu otwarta. EB1 od razu idzie
  według D-68: tylko JWK, przy starcie sprawdzane `kty`, `crv`, `x`, `d`, `use`, `alg` i `kid` = odcisk; adres po
  wylogowaniu wyliczany, nie konfigurowany. *Odrzucone:* stan przejściowy (PEM i JWK, adres jako opcja) do
  osobnego PR-a — obsługa PEM weszłaby do kodu tylko po to, żeby ją wyciąć.
  - **Jedno odstępstwo od #81, rozstrzygnięte przez asystenta.** #81 każe pakietowi domyślnie brać `applications`
    z `EHOS_SIGN_IN_APPLICATIONS`. Pakiet nie czyta jednak żadnej zmiennej sam (README, „Configuration from
    EHOS's environment”), więc mapuje ją host w `config/runtime.exs`, tak jak `EHOS_ISSUER`, a szablon
    `ehos_app` robi to za niego. Skutek dla EHOS-a ten sam.

### EB1 — co wyszło (2 października)

Gałąź `eb/eb1-sign-in-config`, od `main` = `db07862` (merge #79).

**Commity:**
- `53f941d` — testy weryfikatora: ID token jako bearer odrzucony (`:bad_signature`), credential z `client_id`
  przyjęty, `KeyCase.credential/3` z `drop:`.
- `10685d2` — `EhOsContract.Auth.SignIn` na workerze `oidcc`.
- Poprawki po przeglądzie (ten zapis): `SignIn` jako własny proces na wzór `Keys` i adapter `SignIn.Http`.

**Co jest:**
- `config :eh_os_contract_auth, sign_in:` sprawdzane przy starcie:
  - klucz to dokładnie JWK z D-68 — PEM, nadmiarowy albo brakujący element, zły `use`, `alg`, `crv` lub `kty`,
    `kid` niebędący odciskiem i `x` niepasujący do `d` — wszystko odrzucone;
  - adres to `https://<host>` małymi literami, bez portu i ścieżki;
  - issuer to https bez query, fragmentu i danych logowania — także bez wyjątku dla localhost, bo `oidcc` i tak
    odrzuca endpointy http;
  - `secret_key_base` ma co najmniej 64 bajty;
  - `sign_in:` jako mapa jest odrzucane bez wypisywania jej treści.
- Callback i adres po wylogowaniu są wyliczane z `address`.
- Proces trzyma discovery i klucze razem albo wcale, odświeża co 5 minut, a przy błędzie ponawia od 1 do 30 s.
- `provider/1` czyta z własnego ETS-u, nigdy nie czeka i nigdy nie rzuca.
- `refresh/1` pobiera od razu.
- Transport (`SignIn.Http`) idzie tylko przez https, bez przekierowań, czyta najwyżej 64 KiB i kończy wywołanie
  po jednym terminie 10 s. Ten sam adapter dostaje `oidcc` do każdego swojego wywołania.

**Przegląd przed PR-em:** dwa równolegle. Wszystkie znaleziska poprawione, z dwoma wyjątkami: jedno bez zmian,
jedno przeniesione do EB2.

Zgłoszone przez obydwa przeglądy:
- **Worker `oidcc` przy domyślnym `backoff_type: :stop` kładzie aplikację, gdy EHOS leży.** Poprawione już w
  `10685d2`, potem zastąpione własnym procesem.
- **Dekoder `oidcc` rzuca `case_clause` na względnym URI**, poza backoffem — pętla awarii aż do drzewa hosta.
  Teraz wyjątek to odrzucony dokument.
- **Tabela workera to `bag`, który rośnie.** Po zmianie dokumentu każdy odczyt idzie wywołaniem do workera, z
  czekaniem do 5 s. Teraz własny `set`.
- **`provider/1` rzucał po zatrzymaniu dziecka, a `:persistent_term` zostawał.** Teraz tabela ginie z procesem,
  a `config/1` i `refresh/1` odpowiadają jak dla niezaczętego.

Tylko z przeglądu bezpieczeństwa:
- **`httpc` szedł za przekierowaniem, także na http, i bez limitu rozmiaru.** Teraz własny transport.
- **Endpointy discovery bez https przechodziły, a `HS*` obok `Ed25519` w algorytmach ID tokenu dawało klucz
  `oct` z `client_secret`.** Teraz dokument z endpointem http nie jest trzymany, a `HS*` i `none` dają
  `:symmetric_id_token_alg`.
- **`sign_in:` jako mapa wypisywało `SECRET_KEY_BASE` w stacktrace startu.** Teraz odrzucane bez treści.

Tylko z przeglądu poprawności:
- **Nieudane pobranie kluczy przy starcie nie było ponawiane, a `provider/1` mówił `:ok`.** Teraz dokument bez
  kluczy nie jest trzymany i oba pobierane są ponownie.
- **`random_exponential` dawał 10–30 s zamiast 1–30 s.** Teraz własne podwajanie od 1 s.
- **Adres z portem albo wielkimi literami przechodził**, a EHOS porównuje dokładnie. Teraz odrzucany.
- **Asercja `cacerts != []` była pusta, a test TLS obiecywał więcej, niż sprawdzał.** Zastąpione testem tego,
  co trafia do połączenia.
- **Próba kontrolna ID tokenu nie miała `auth_time`.** Teraz ma te same claimy.

Bez zmian:
- **Ponowne czytanie pliku klucza przy restarcie.** Sekret jest zamontowany na cały czas życia poda, więc
  restart czyta ten sam plik. Brak pliku w trakcie pracy to zepsute wdrożenie, które ma się pokazać, a nie
  zostać przykryte.

Przeniesione do EB2:
- **Losowy `client_secret` przy każdym starcie.** W S6 zmienione z „fixed non-secret binary”.
- **`JOSE.JWK` bez maskowania w `inspect`.** Klucz nie może trafić do argumentów niczego, co może paść.
- **Test, że nagłówek asercji klienta niesie `kid` klucza.** Wymaga prawdziwego żądania tokenu.

**Decyzja asystenta przy przeglądzie: własny proces zamiast workera `oidcc`** — dopisek z datą w S1 ADR-a.
Kontekst klienta w EB2 powstanie z `Oidcc.ClientContext.from_manual/5` i trafi do `oidcc_plug` przez
`client_store`.

*Odrzucone:*
- owinięcie workera opiekunem z opóźnionym restartem — nie naprawia kluczy niepobieranych ponownie ani
  rosnącej tabeli;
- czytanie wewnętrznej tabeli workera po nazwie — zależy od nieopisanego szczegółu `oidcc`.

**Zgłoszone w `erlef/oidcc`** 2 października, na polecenie użytkownika, każde z odtworzeniem na 3.9.0 (kod w ich
`main` na `4914d8d` bez zmian) przez fałszywego dostawcę w adapterze HTTP:
- brak ponowienia kluczy po udanym dokumencie — [erlef/oidcc#552](https://github.com/erlef/oidcc/issues/552);
  przy okazji wyszło, że `refresh_jwks_for_unknown_kid/2` przy `jwks = undefined` kładzie worker `function_clause`;
- `bag` w tabeli workera — [erlef/oidcc#553](https://github.com/erlef/oidcc/issues/553);
- `case_clause` w `parse_setting_uri_https` — [erlef/oidcc#554](https://github.com/erlef/oidcc/issues/554). Dotyczy
  `userinfo_endpoint`, `end_session_endpoint`, `pushed_authorization_request_endpoint` i `mtls_endpoint_aliases`;
  `token_endpoint` i `jwks_uri` idą przez `parse_setting_uri`, który nie sprawdza schematu wcale;
- dolna granica `random_exponential` — [erlef/oidcc#555](https://github.com/erlef/oidcc/issues/555).

**Weryfikacja:**
- Każde nowe zabezpieczenie ma próbę odwrotną: mutacja w kopii, test, `cp` z kopii i `cmp`. Każda wywraca
  dokładnie jeden, właściwy test: przekierowanie, limit rozmiaru, http w adapterze, termin, wyjątek dekodera,
  https endpointów, porównanie issuera, algorytmy symetryczne, jednorazowy log, podwajanie backoffu.
- Wcześniej, w `53f941d` i `10685d2`: ID token, `client_id`, `backoff_type`, sprawdzenie discovery, `x`
  wobec `d`.

### EB2a — co wyszło (2 października)

Gałąź `eb/eb2a-session-store`, od `ef0e94d` (merge #84).

**Co jest:**
- **V03:** `eh_os_contract_auth_sessions` i `eh_os_contract_auth_session_credentials`, od razu z kolumnami
  dzierżawy, żeby EB3 nie potrzebował V04. Credential jest kluczowany adresem aplikacji, tym, który EHOS dostaje w
  `resource`, także dla własnej aplikacji (`address`).
- **`SignIn.Sessions`** (wewnętrzny): `create/2`, `fetch/2`, `delete/1`.
  - Przeglądarka dostaje 32 losowe bajty, tabela ich SHA-256.
  - Refresh token, ID token i credentiale są zaszyfrowane (`SignIn.Cipher`, XChaCha20-Poly1305 z `plug_crypto`
    2.2). Klucz jest wyprowadzony raz przy starcie dziecka; dane powiązane to hash wiersza i kolumna, a dla
    credentialu kolumna z adresem aplikacji.
  - Wartość, która się nie odszyfrowuje, kończy sesję i kasuje wiersz.
  - `create/2` kasuje w tej samej transakcji sesje starsze niż 12 h od `auth_time` (S11).
- **`SignIn.client_context/1`:** kontekst `oidcc` z tego, co trzyma dziecko, budowany na wywołanie.
- **Losowy `client_secret`** przy każdym starcie, poza `inspect`.
- **`FakeEhos` ma endpoint tokenu** w kształcie `Ehos.SignIn.Token` dla wymiany kodu.
- Auth: 191 → 212 testów (206 przed poprawkami z przeglądu).

**Decyzje asystenta:**
- **Klucz prywatny w kontekście klienta.** Ani struct `oidcc`, ani `JOSE.JWK` nie chowa go przed `inspect`, więc
  „klucz nigdy w argumentach czegoś, co może paść” da się zapewnić tylko w naszym kodzie. Funkcje biorą nazwę
  dziecka i czytają klucz w środku; kontekst powstaje na wywołanie i nie jest nigdzie trzymany. Zostaje to, co
  wypisze sam `oidcc`, gdy padnie — poza naszym zasięgiem; zapisane w ADR-ze (S1, poprawka z datą).
  *Odrzucone:* opakowanie klucza w domknięcie (`oidcc` bierze `client_jwks` jako rekord JOSE i z domknięciem nie
  ruszy); kontekst w `conn.assigns` (każdy crash Plug wypisuje `conn`).
- **`ClientStore` dla `oidcc_plug` przechodzi do EB2b**, bo bez routera nikt go nie woła. Bez `refresh_jwks/1`:
  callback dostaje tylko kontekst i nie zna nazwy dziecka, a dziecko i tak odświeża klucze co 5 minut.
- **Credential po adresie, nie po nazwie aplikacji.** `credential/2` w EB3 przyjmie nazwę i zamieni ją na adres z
  `applications`; tabela trzyma to, co poszło do EHOS-a.

**Przegląd przed PR-em**, dwa równolegle. Oba znalazły to samo najpoważniejsze:
- **Klucz szyfru i tokeny EHOS-a w raporcie z awarii.** `create/2` dopasowywał argument w nagłówku funkcji, a
  `MessageEncryptor.encrypt/4` sprawdza typ strażnikiem poza swoim `rescue`. Wystarczył `nil` w miejscu refresh
  tokenu (`oidcc` daje `refresh: :none`), żeby w górnej ramce stał klucz, albo brak pola, żeby `KeyError` wypisał
  wszystkie tokeny. Teraz najpierw jest sprawdzany kształt, a odmowa wymienia tylko nazwy pól i typy.
  „Klucz nigdy w argumentach” z pierwszej wersji tego zapisu było więc nieprawdą; poprawione też w ADR-ze.

Poprawione, każde z testem, który bez poprawki pada:
- `fetch/2` oddawał sesję starszą niż 12 h, póki nikt inny się nie zalogował (oba przeglądy). Teraz limit jest
  sprawdzany też przy odczycie.
- `subject`, `sid` i `auth_time` były jawne i poza danymi powiązanymi (oba przeglądy), więc ktoś z prawem zapisu
  do tabeli mógł przepisać wiersz na inną osobę. Teraz są w danych powiązanych ID tokenu.
- Czyszczenie po 12 h szło w transakcji nowego logowania. Teraz to osobna instrukcja przed nią.
- Test czyszczenia logował dwie pierwsze sesje na prawdziwym zegarze, więc nie pokazywał, który zegar czyta
  czyszczenie. Teraz wszystko idzie pod `Clock.at`, w czasie, do którego prawdziwy zegar nie doszedł.
- `client_context/1` czytał to, co trzyma dziecko, dwa razy. Teraz czyta raz (bez testu: wyścig co 5 minut).
- `plug_crypto` nie był zadeklarowany, a `plug` przyjmuje też 1.x, czyli AES-GCM. Teraz `~> 2.0`.
- Drobne: opis `FakeEhos.grant/4`, nieużywany `signer/1`, pusty `case` w `Cipher.decrypt/3`, asercja o
  skasowanym wierszu w teście credentialu.

Bez zmian:
- dwa zapytania i kopia konfiguracji na odczyt sesji — oba po indeksie, a ścieżkę na każdą stronę układa
  dopiero EB2b;
- pomocnicze funkcje testów skopiowane z `sign_in_test.exs` — wspólny moduł, gdy dojdzie trzeci plik (EB2b).

**Przeniesione do EB2b:**
- `ClientStore`;
- opcje wywołań z S6 w jednym miejscu, z `preferred_auth_methods: [:private_key_jwt]`. Bez nich `oidcc` po cichu
  wysłałby losowy sekret, gdyby dokument wymienił metodę `client_secret_*` (przegląd bezpieczeństwa);
- `actor/1` bierze aktora z credentialu sprawdzonego `verify/2`, nigdy z kolumny `subject`;
- README „Signing people in” do końca.

**Weryfikacja:** każde zabezpieczenie ma próbę odwrotną (mutacja w kopii, `cp`, `cmp`). Sprawdzone mutacje: stały
sekret, kontekst bez klucza klienta, dane powiązane bez kolumny, bez wiersza, credential bez adresu, brak
szyfrowania, surowy token zamiast hasha, brak czyszczenia po 12 h i wiersz, który zostaje po nieudanym
odszyfrowaniu. Każda wywraca właściwe testy.

### EB2b — co wyszło (2 października)

Gałąź `eb/eb2b-browser-routes`, od `445be88` (merge #85).

**Co jest:**
- **`SignIn.Router`** pod `/auth/ehos`, na `Authorize` i `AuthorizationCallback` z `oidcc_plug` przez
  `SignIn.ClientStore`:
  - `GET /sign-in` — PKCE wymagane, 503 przy dostawcy, z którym nie da się zalogować;
  - `GET /callback` — opcje z S6 w jednym miejscu: `preferred_auth_methods: [:private_key_jwt]`,
    `check_peer_ip: false`, `retrieve_userinfo: false`, transport pakietu. Potem nowy token sesji w odnowionej
    sesji Plug i powrót tylko na ścieżkę lokalną;
  - `POST /sign-out` — `Plug.CSRFProtection` w środku, `Oidcc.Logout.initiate_url/3` z `id_token_hint` i
    adresem po wylogowaniu wyliczonym z `address`.
- **`Session`** (plug) i **`Session.actor/2`** — aktor zawsze z credentialu sprawdzonego `verify/2`, nigdy z
  kolumny `subject`.
- **`FakeEhos`** podpisuje podanym kluczem i sprawdza PKCE oraz `redirect_uri`.
- Eksport z granicy pakietu: `Session`, `SignIn.Router`.
- Auth: 212 → 227 testów przed przeglądem.

**Decyzje asystenta:**
- **Router jako zwykły `Plug`, nie `Plug.Router`.** Trzy trasy i nazwa dziecka z opcji, bez makr.
- **Plug przypisuje tylko `subject`, `sid` i `auth_time`.** Każdy crash Plug wypisuje `conn`, a z nim
  `assigns`.
- **Bez własnej kontroli `expires_at` w `actor/2`.** `verify/2` odrzuca wygasły credential według
  `EhOsContract.Clock`; mutacja, która usuwała moją kontrolę, przeżyła, więc była zbędna. `expires_at` odczyta
  odnawianie (EB3), z zapasem 30 s.
- **Ścieżki tras** — `sign-in`, `callback`, `sign-out`; ADR (S7) mówił tylko „logowanie, callback,
  wylogowanie”, więc poprawka z datą.
- **Odmowa przy callbacku jest logowana samą nazwą powodu.** Niektóre powody `oidcc` niosą token, który
  odrzucił.

**Zamyka [#81](https://github.com/EmpoweredHouse/eh-os-contract/issues/81):** JWK z D-68 (EB1), adres po
wylogowaniu dokładnie `https://<host>/` (test tutaj), `EHOS_SIGN_IN_APPLICATIONS` mapowane przez hosta (EB1).

**Weryfikacja:** próby odwrotne — otwarte przekierowanie, brak adresu po wylogowaniu, brak CSRF, zachowany
podrzucony token, `check_peer_ip: true`. Każda wywraca dokładnie swój test.

**Przegląd przed PR-em**, dwa równolegle. Poprawione, każde z testem, który bez poprawki pada:
- **Pętla logowania** (poprawność: High, bezpieczeństwo: Medium). Callback nie sprawdzał credentialu, więc taki,
  którego każda strona odmawia (inna publiczność, brak kluczy), kręcił przeglądarką przez SSO EHOS-a bez końca i
  przy każdym obrocie pisał wiersz. Teraz `verify/2` przy callbacku, a `sub` credentialu musi być tym z ID
  tokenu. Do tego plug przekierowuje tylko przy braku sesji albo wygasłym credentialu; inna odmowa daje 401.
- **Podrzucony token CSRF przeżywał logowanie** (oba). `renew: true` przy sesji w ciasteczku tylko podpisuje je
  na nowo, z każdym kluczem. Teraz `clear_session/1` i `delete_csrf_token/0`, jak `renew_session` w
  `phx.gen.auth`.
- **Ponowne logowanie zostawiało stary wiersz ważny przez 12 h** (oba). Teraz jest kasowany.
- **Pusty `sub`, `sid` albo refresh token, albo `auth_time` poza zakresem, dawały 500** (poprawność). Teraz 401.
- **`fetch()` strony po wygaśnięciu dostawał 302 do EHOS-a, przez granicę originów** (poprawność). Teraz
  przekierowanie dostaje tylko nawigacja (`sec-fetch-mode: navigate` albo `Accept` z `text/html`).
- `actor(conn)` po plugu z `assign_actor: true` czyta przypisanego aktora zamiast drugiego odczytu z bazy;
  `Authorize.Error` z `oidcc_plug` daje 503 (bez testu: wyścig co 5 minut); `return_to`, który nie jest UTF-8,
  wraca na `/`; odpowiedź tokenu znika z `conn.private` po odczycie; dwie martwe kontrole usunięte.

Bez zmian:
- logi przy callbacku bez sesji i przy niedostępnym EHOS-ie — sama objętość logu, bez bazy i bez EHOS-a;
- dwa zapytania i odszyfrowanie całej sesji na każde żądanie — do EB3, które i tak czyta `expires_at`;
- zdublowane pomocnicze funkcje odpowiedzi w routerze i plugu;
- `actor/2` na `conn` bez pobranej sesji rzuca wyjątek — opisane w `@doc`, to błąd okablowania hosta.

Zapisane jako znane granice (ADR, S7): dwa logowania naraz w dwóch kartach (jedno miejsce w sesji
`oidcc_plug`) i wylogowanie przy niedostępnym EHOS-ie, które kończy sesję tylko tutaj. Informacyjnie:
`return_to` z zapytaniem trafia w `state` do logów EHOS-a; aktor zawsze z credentialu, więc host, który
autoryzowałby po `assigns.eh_os_contract_session.subject`, polega na tym, że EHOS trzyma `sub` równe.

Auth: 212 → 233 testów.

### EB3a — co wyszło (2 października)

Gałąź `eb/eb3a-renewal`, od `6b280dd` (merge #86). **EB3 podzielone przez asystenta na dwa PR-y**, jak EB2, dla
małego diffu:
- **EB3a** — odnawianie własnego credentialu; zamyka #80;
- **EB3b** — `credential/2` dla innych aplikacji (`resource`, odmowa `invalid_target` zapamiętana na 10 minut,
  dwa `resource` → dwa credentiale); zamyka #78.

*Odrzucone:* jeden PR, jak w tabeli części.

**Co jest:**
- **`SignIn.Renewal`** (wewnętrzny) — S4 krok po kroku:
  - szybka ścieżka przy więcej niż 30 s ważności;
  - dzierżawa jednym `UPDATE` na zegarze bazy, na 15 s (po drugim przeglądzie 30 s, niżej);
  - ponowny odczyt wiersza;
  - `Oidcc.Token.refresh/3` bez mocka, z `private_key_jwt` i terminem 10 s;
  - zapis z odbiorem dzierżawy w jednej transakcji, strzeżonej `lease_holder`;
  - czekający co 200 ms, najwyżej 15 s.

  Skutki z S5 wiersz po wierszu, bez `invalid_target`, który należy do EB3b.
- **`Sessions`:** `take_lease/3`, `release/2`, `renewed/4`, `end_session/1`; `token_hash` w strukturze (poza
  `inspect`) dla danych powiązanych przy ponownym szyfrowaniu.
- **`SignIn.Http.last_status/0`** — status ostatniej odpowiedzi w procesie wołającym. Bez niego odpowiedź 2xx
  odrzucona przez `oidcc` (token przepadł) i brak odpowiedzi (token zostaje) wyglądają tak samo.
- **`Session`:** `actor/2` i plug z `assign_actor: true` odnawiają. `:ehos_unavailable` i `:renewal_busy` dają
  503; sesja zakończona przy odnawianiu — przekierowanie do logowania.
- **`FakeEhos`:**
  - refresh w kształcie `Ehos.SignIn.Token`: ścisła rotacja, drugi raz ten sam token unieważnia rodzinę;
  - ID token przy odnowieniu dokładnie z claimami z #80;
  - własny zegar (`advance/2`), hak `on_refresh/2` i odpowiedzi, których EHOS nie daje (`refresh_answer/2`).
- **`CommitRepo`** i baza `eh_os_contract_auth_test_commits` dla testów na zatwierdzonych danych.
- Auth: 233 → 248 testów przed przeglądem.

**Decyzje asystenta:**
- **Liczby jako stałe, nie opcje.** S4 mówił „opcje ze sprawdzeniem przy starcie”; żaden host ich nie potrzebuje.
  Poprawka z datą w ADR-ze. *Odrzucone:* opcje teraz — sprawdzenie kolejności i konfiguracja bez użytkownika.
- **Status ostatniej odpowiedzi w słowniku procesu.** *Odrzucone:*
  - rozpoznawanie po kształcie błędu `oidcc` — lista powodów 2xx jest długa i może się zmienić;
  - własne żądanie refresh — S10 odrzucił.
- **Czas czekającego jako wewnętrzna opcja `Renewal.credential/4`**, tylko dla testów. Bez niej test
  „czekający się poddaje” trwałby 15 s.

**Weryfikacja:** próby odwrotne — brak dzierżawy, 2xx traktowane jak brak odpowiedzi, każdy błąd kończący
sesję, zapis bez strażnika dzierżawy, brak zwolnienia dzierżawy, margines 0, wygasły credential oddany,
dzierżawa ignorująca zegar bazy, brak 503 w plugu. Każda wywraca właściwe testy. Jedno miejsce bez testu:
ponowny odczyt wiersza po wzięciu dzierżawy (S4, krok 3) chroni przed wyścigiem, którego nie da się ustawić
deterministycznie.

**Przegląd przed PR-em**, dwa równolegle. Poprawione, każde z testem, który bez poprawki pada:
- **Odnowiony credential zapisywany bez kontroli z callbacku** (poprawność). Credential odrzucany przez
  `verify/2` dawał 401 przez 10 minut, a credential innej osoby — jej aktora. Teraz sprawdzane są `verify/2`,
  `sub`, a w ID tokenie `sid` i `auth_time`; inaczej koniec sesji.
- **Przejęcie przeterminowanej, niezwolnionej dzierżawy** (bezpieczeństwo). Nowy właściciel prezentował token,
  który poprzedni mógł już zużyć, a to unieważnia logowanie w każdej aplikacji. Teraz koniec sesji. `take_lease/3`
  zwraca poprzedniego właściciela (CTE z `FOR UPDATE`).
- **Wyjątek `oidcc` na treści 2xx** (JWT zamiast JSON, JSON, który nie jest obiektem) zostawiał zużyty token
  (poprawność). Teraz `rescue` → koniec sesji, a wyjątek nigdy nie jest wypisywany.
- **Brak przerwy po nieudanym odnowieniu** (oba). Każde żądanie sesji wołało EHOS po kolei, każde do 10 s, a
  czekający blokowali mimo ważnego credentialu. Teraz pauza 5 s w dzierżawie; ważny credential oddawany od razu.
- **`last_status` z poprzedniego żądania** (oba). `oidcc` potrafi odmówić przed jakimkolwiek wywołaniem, a wtedy
  liczył się status sprzed niego. Teraz `forget_status/0` tuż przed wywołaniem.
- **2xx ponad 64 KiB liczone jako brak odpowiedzi** (oba). Teraz status jest zapisywany przed limitem.
- **`expires_at` z lokalnego zegara po odpowiedzi** (oba). Teraz najwyżej `exp` credentialu, od chwili startu
  wywołania, także przy callbacku. `expires_in` ≤ 30 s → koniec sesji (odnawianie na każde żądanie).
- **Zmiana klucza w EHOS-ie kończyła sesje** (poprawność). Teraz `refresh_jwks` raz na odnowienie.
- **Plug czytał sesję dwa razy** (oba). Teraz przekazuje odczytaną do szybkiej ścieżki.
- **Wpis w CHANGELOG** zgubiony przez błąd w moim skrypcie (poprawność). Dopisany.
- **`FakeEhos`:** sprawdzenie i oznaczenie zużytego tokenu w jednym kroku `Agent`.

Bez zmian:
- odpytywanie co 200 ms czekających — tylko przy wygasłym credentialu i trwającym odnowieniu (najwyżej 10 s);
- ponowny odczyt po wzięciu dzierżawy bez testu — wyścig nie do ustawienia deterministycznie.

Auth: 248 → 260 testów.

**Drugi przegląd** (samych poprawek, jeden przebieg; pierwszy padł na błędzie połączenia z API). Poprawione, każde
z testem, który bez poprawki pada, poza dzierżawą 30 s (stała):
- **Dzierżawa 15 s była za krótka**: wywołanie (10 s), ponowne pobranie kluczy przy nieznanym `kid` (do 30 s) i
  własne pobranie kluczy przez `verify/2` (10 s). Przy rotacji klucza pod obciążeniem groziło masowe wylogowanie
  przez „przejęcie”. Teraz dzierżawa 30 s i czekanie na klucze najwyżej 5 s (`SignIn.refresh/2`).
- **`verify/2` odmawiający z naszego powodu** (`:unknown_key`, `:no_keys`) kończył sesję mimo dobrego tokenu.
  Teraz odnowienie jest zapisywane; test rotacji przechodzi bez ręcznego `Keys.refresh`.
- **Margines sprawdzany na `expires_in`, a nie na przyciętym `expires_at`.** Teraz `beyond_margin?/1`, także przy
  callbacku.
- **`:busy` przy skasowanym wierszu oddawał credential sesji, która już się skończyła**, a `lease_holder` był
  sprzed dzierżawy. Teraz świeży odczyt.
- `exit` i `throw` z `oidcc` łapane (bez testu: żadna ścieżka `oidcc` ich dziś nie rzuca); wynik w nieznanym
  kształcie traktowany jak błąd; asercja czasu `< 150` ms usunięta (niestabilna, a równość wystarcza).
- ADR: S5 przy timeoucie (pauza, nie zwolnienie), dzierżawa 30 s i co znaczy „prezentowany raz” — po timeoucie
  ten sam token idzie ponownie po pauzie, co D-64 akceptuje.

Bez zmian: wyjątek przed wywołaniem `oidcc` zostawia dzierżawę, a sesja kończy się po 30 s jako przejęcie —
ostrożne i rzadkie; podwójne `verify/2` przy odnawiającym żądaniu.

Auth: 260 → 263 testów.

### #63–#66 — decyzje i co wyszło (3 października)

Polecenie użytkownika po #89. Asystent przedstawił każde issue z przykładem i rekomendacją; **użytkownik przyjął
wszystkie cztery rekomendacje.** Gałąź `engine/issue-65-received-paths`, na `auth/discovery-endpoints` (#91).

**Decyzje użytkownika (3 października), z opcjami, które przegrały:**
- **#66 — wartość zakresu, której tabela nie utrzyma, zapisana jako `sha256:<hex>`.** Dotyczy NUL, złego UTF-8 i
  wartości ponad 256 bajtów; decyzja bez zmian. *Odrzucone:*
  - nowy powód odmowy przed `Authorizer` — widoczny dla hosta;
  - limit długości jako odmowa — to samo;
  - skrót każdej wartości — gubi wartość audytu w każdym wierszu.
- **#65 — krok `zdarzenie odebrane → polityka → komenda`, liczony z inboxu.** Przesuwa werdykt, stąd wpis w
  CHANGELOG. *Odrzucone:* zostawić i napisać w raporcie, że reakcje na inne aplikacje nie są mierzone — jedno z
  czterech pytań ekranu zostałoby bez odpowiedzi.
- **#64 — wszystko zostaje; host mierzy tabelę swoimi narzędziami** (zapytania w doc `Inbox`); okno czeka na to,
  jak długo transport EHOS-a może dostarczyć ponownie. *Odrzucone:*
  - okno konfigurowane przez hosta — ogranicza FM-08 zgadywaną liczbą;
  - czyszczenie według retencji transportu — EHOS-a, jeszcze nieznanej;
  - widok rozmiaru na dashboardzie — dashboard pokazuje zgodność, nie operacje (CLAUDE.md).
- **#63 — bez zmian do pierwszych innych drzwi** (formularz LiveView, job z credentialem, MCP). *Odrzucone:* zmiana
  kształtu teraz — znów zgadywanie z jednego przypadku, przed czym ostrzega samo issue.

**Co jest:**
- **#66.** `Auth.authorize/2`: `recorded/1` — skrót dla NUL, złego UTF-8, ponad 256 bajtów i wartości zaczynającej się
  od `sha256:` (żeby zapisany `sha256:` był zawsze skrótem biblioteki). Credential z NUL w `sub` to `:bad_signature`.
- **#65.** `Paths`: krok dla każdego `consumes "<nazwa>"`, który obsługuje polityka:
  - asynchroniczny;
  - liczony z `eh_os_contract_commands` złączonych z `eh_os_contract_inbox` po `causation_event_id`, po dokładnych
    kluczach inboxów;
  - ograniczony `received_at`, które inbox pisze teraz zegarem silnika;
  - bez przejmowania porażek subskrypcji polityki.

  Graf rysuje zdarzenie odebrane; `wiring_version` zmienia się raz.
- **#64.** Doc `Inbox`: co trzyma, dlaczego i jak to zmierzyć.

**Przegląd przed PR-em** — #66 w jednym przebiegu (poprawność i bezpieczeństwo razem, zmiana na 20 linii), potem #65
z poprawkami #66 w dwóch równoległych. Poprawione, każde z testem:
- #66: wartość podrobiona na skrót; NUL w `sub`; przykład `%FF` w CHANGELOG nieprawdziwy dla HTTP (Plug go odrzuca;
  wektorem jest NUL); README i komentarz kolumny;
- #65:
  - pełny skan inboxu w każdym raporcie (oba) — teraz dokładne klucze i nic dla kontraktu bez inboxu;
  - `LIKE` z `_` w nazwie modułu (oba);
  - porażki subskrypcji i komend polityki przypisane krokowi odebranemu;
  - `received_at` z zegara bazy;
  - test `since:`.

Bez zmian:
- **ścieżka odebrana, która zawsze pada, wygląda na nieprzejechaną** — inbox wycofuje porażkę razem z wierszem;
  opisane w `Paths` i CHANGELOG. Naprawa (zapis porażki poza transakcją) to osobna decyzja;
- **indeks na `inbox(id)` albo `commands(causation_event_id)`** — V01 zmieniany w miejscu, a bazy są wspólne; po
  dokładnych kluczach strona inboxu idzie po kluczu głównym. `issued/2` skanuje komendy tak samo od E7c;
- **NUL w `Actor.credential/3` w silniku**, nie tylko w auth — należy do zgłoszonego zadania o bajtach silnika;
- **długość `sub`** — wymaga wycieku klucza EHOS-a.

Auth: 284 → 285 testów; silnik: 1114 → 1117. Brama z `sandbox/` → **EXIT=0** — sandbox 145, `check` 0 / 29 / 9;
silnik 1117, `check` 0 / 68 / 6; web 52; auth 285 + 1 property.

### Po #89 — punkty końcowe discovery (2 października)

Prośba użytkownika po merge'u #90. Gałąź `auth/discovery-endpoints`, od `762521e`.

**Co było:** dokument discovery był trzymany, gdy jego punkty końcowe zaczynały się od `https://`. Przechodziło
`https://evil.example\@ehos.test/oauth/authorize`, a przeglądarka wysłana tam do logowania idzie do
`evil.example`. Na liście w ogóle nie było `pushed_authorization_request_endpoint`, a `oidcc` wysyła tam żądanie
z asercją klienta, gdy tylko dokument go podaje.

**Co jest:**
- każdy punkt końcowy z listy według reguły z #89 (`Address.check`, ze ścieżką, bez http) **i u źródła issuera**
  (schemat, host, port), bo EHOS podaje wszystkie u siebie;
- PAR na liście;
- transport (`SignIn.Http`) według tej samej reguły dla każdego wywołania, niezależnie od pola dokumentu;
- odmowa `{:endpoints_refused, nazwy}` w miejsce `{:not_https, nazwy}`;
- ADR S6 z datowaną poprawką.

**Decyzje asystenta:**
- **Źródło issuera wymagane.** *Odrzucone:* sama reguła adresu — punkt końcowy na innym hoście dostałby kod,
  weryfikator PKCE i asercję.
- **Zapytanie w punkcie końcowym odrzucane.** *Odrzucone:* dopuszczenie, jak RFC 6749 §3.1 — EHOS go nie używa, a
  reguła jest EHOS-a.
- **`mtls_endpoint_aliases` poza listą** — `oidcc` sięga po nie tylko przy `tls_client_auth`, a ten wymaga `ssl:` w
  `request_opts`, którego klient nie ma.

**Przegląd przed PR-em**, dwa równolegle. Poprawione: źródło issuera (bezpieczeństwo), transport (oba), komentarz
listy, nazwy funkcji, opis reguły w dokumentach, testy z zapytaniem, użytkownikiem i `\@` w punktach serwerowych.
Bez zmian: uwierzytelnienie żądania PAR nieprzypięte do `private_key_jwt` — `oidcc_plug` nie przekazuje
`preferred_auth_methods`, EHOS nie podaje PAR; zapisane w S6 jako znana granica. Podagent przeglądu uruchomił
mimo zakazu `mix test` pakietu auth w trakcie bramy; brama i tak przeszła, a po poprawkach poszła ponownie.

Auth: 278 → 284 testy.

### #89 — co wyszło (2 października)

[#89](https://github.com/EmpoweredHouse/eh-os-contract/issues/89), założone przez użytkownika z przeglądu poprawki
eh-os#118. Gałąź `auth/issue-89-loopback`, od `da9f56f` (merge #88).

**Co było:** wyjątek dla pętli zwrotnej przy pobieraniu kluczy czytał hosta przez `URI.parse/1`, które pomija sposób
zapisu części użytkownika. `http://evil.example\@localhost/...` miało dla niego hosta `localhost` i przechodziło po
zwykłym http, a EHOS i przeglądarka czytają hosta jako `evil.example`. Finch też łączył się z `localhost`, więc wada
to rozjazd z EHOS-em i przeglądarkami, nie pobieranie z `evil.example`.

**Co jest:** `EhOsContract.Auth.Address` (wewnętrzny) — reguła EHOS-a dla jego issuera (`check_issuer/1`,
eh-os#161, w chwili zapisu otwarty):
- adres czyta się z powrotem tak, jak go zapisano (`URI.new/1` → `URI.to_string/1`), port schematu na boku;
- bez użytkownika, zapytania i fragmentu;
- host: DNS małymi literami, IPv4 w jedynej kropkowej postaci albo `::1`;
- port 1–65535.

Dwie rzeczy rozstrzyga wołający: `path:` i `plain_on_loopback:`.

| Gdzie | Ścieżka | Zwykłe http na pętli |
| --- | --- | --- |
| adres zbioru kluczy (`Keys.check!/1`) | tak | tak |
| `issuer` w `Auth.child_spec/1` (nowe, także obok `jwks_url`) | nie | tak, jak u EHOS-a |
| `issuer` przy logowaniu (`SignIn`) | nie | nie (`oidcc`) |
| `address` i `applications` logowania (`origin!/2`) | nie | nie |

Odrzucony adres w komunikacie: sam schemat, host i port („with more, not shown”), jak `shown/1` u EHOS-a.

**Decyzje asystenta:**
- **Jeden moduł z regułą EHOS-a, dla wszystkich miejsc, które biorą adres.** *Odrzucone:* poprawka tylko w
  `Keys.check!/1` (zakres issue) — `issuer` przy logowaniu i adresy logowania miałyby dalej starą regułę i ten sam
  rozjazd.
- **Ścieżka dozwolona tylko w adresie kluczy.** *Odrzucone:* kopia 1:1 bez ścieżki — `jwks_url` ma ścieżkę z
  natury.
- **`issuer` z ukośnikiem na końcu albo ścieżką odrzucany przy starcie.** Zmiana widoczna dla hosta, ale EHOS
  takiego `iss` nigdy nie publikuje, więc żadna działająca konfiguracja nie pada; dotąd taka kończyła się
  `:wrong_issuer` na każdym credentialu. *Odrzucone:* przycinanie ukośnika jak dotąd — ukrywało rozjazd z `iss`.

**Weryfikacja:** próby odwrotne — bez kontroli użytkownika, bez odczytu wstecz, bez zakresu portu, bez kontroli
hosta liczbowego, bez wyrażenia DNS, http wszędzie, http dla issuera logowania, bez postaci z portem schematu,
ścieżka ignorowana, `shown/1` jako `inspect`, issuer niesprawdzany w `child_spec`, `origin!` bez reguły. Każda
wywraca co najmniej jeden test; odczyt wstecz dopiero po dodaniu `HTTPS://`, `:0443` i `:/`.

**Przegląd przed PR-em**, dwa równolegle, potem jeden przebieg samych poprawek. Poprawione, każde z testem:
- **`issuer` ze ścieżką**, a w hoście tylko weryfikującym niesprawdzany wcale obok `jwks_url` (poprawność);
- **adresy logowania nadal przez `URI.parse/1`** — `https://127.1` przechodziło (oba);
- **hasło z adresu w komunikacie odmowy** (oba) — teraz `Address.shown/1`;
- **CHANGELOG przesadzał** (bezpieczeństwo) — Finch łączył się z `localhost`.

Przebieg samych poprawek (jeden, oba punkty widzenia) — same Low. Poprawione:
- `applications`, które nie jest mapą, było wypisywane w całości razem z niesprawdzonymi adresami (z testem);
- CHANGELOG mówi, że `issuer` sprawdza dziecko, a `issuer:` podany `verify/2` albo plugowi — nie;
- README: lista sprawdzeń logowania przy starcie; martwe `trim_trailing` przy adresie discovery.

Bez zmian:
- **punkty końcowe z discovery** sprawdzane tylko prefiksem `https://` (bezpieczeństwo, Low) — wymagałoby
  skompromitowanego EHOS-a po TLS; **załatwione zaraz potem**, na prośbę użytkownika — „Po #89 — punkty końcowe
  discovery”;
- **`::1` dozwolone, choć Mint bez `inet6` się z nim nie połączy** — było przedtem, odmawia bezpiecznie;
- **`shown/1` czyta przez `URI.parse/1`**, więc przy `\@` pokazuje `localhost`, a przy `:0443` adres wygląda na
  poprawny — sekretu nie ujawnia, a tak samo robi `shown/1` EHOS-a;
- **issuer z jawnym portem domyślnym** (`https://ehos.test:443`) przechodzi, choć EHOS pisze `iss` bez niego —
  reguła EHOS-a też go przyjmuje;
- **`https://[::1]` odrzucane jako `address`** logowania — tak było przedtem; D-68 nie zna takich adresów.

Auth: 274 → 278 testów.

### #98 — co wyszło (3 października)

Na `engine/issue-98-key-budget`. Klucz liczony po escapowaniu, razem z nazwą przed nim, przeciw
`EhOsContract.Key.budget/0`; F9 = 6 zostaje jako odmowa kształtów przy kompilacji. Poprawka z datą w
`docs/adr/contract-v2.md` (F9 był próbką), wpis w CHANGELOG („a host has to act”).

**Decyzje użytkownika (3 października), z odrzuconymi opcjami:**
1. *Budżet: jeden, 2048 bajtów* sumy kolumn tekstowych wpisu indeksu (strumień; `process` + `instance_id`; strumień
   timerów menedżera `"$pm:<klucz>:<korelacja>"`, najdłuższy klucz przebiegu menedżera). Odrzucone: 2600 (zapas
   tylko ~70 bajtów do ~2667, które zostają z 2704), budżet na tabelę (różnice kilka bajtów, trzy stałe).
2. *Odmowa `{:error, :key_too_long}`, HTTP 422 `{"error": "key_too_long"}`*. Odrzucone: `{:invalid, pola}` (żadne
   pole samo nie jest za długie), 413 (dotyczy rozmiaru ciała, a ciało może być małe).
3. *Menedżer stoi*: `EhOsContract.Key.TooLongError` przed zapisem, subskrypcja `failing` na tym zdarzeniu do
   ręcznego `skip` — jak każda awaria, zgodnie z „nigdy nie pomijaj” subskrypcji. Odrzucone: pomijanie z zapisem
   (przebieg traci krok po cichu), stanie + sprawdzanie kluczy menedżerów przy dispatchu (komenda zależna od
   istniejących reakcji, większy zakres).
4. *#101 zmergowany przed #98* — PR startuje od `main` z aktualnym handoffem.

**Decyzje techniczne (asystenta):** sprawdzenie strumienia przed transakcją (z tożsamości komendy, tylko agregat —
boundary nie ma `stream_id`); przebiegi w `commit/3` przed `Personal.prepare` i `for_writing`, bo zwrócony błąd nie
cofa transakcji i zostawiłby utworzone klucze podmiotów; odmowa bez wiersza w `_commands`, jak `:subject_erased`.
Wyjątek `Key.TooLongError` zagnieżdżony i eksportowany jak `Authorizer.OutsideScopeError`. Rig `KeyRig` (trzy
kontrakty), bo żaden istniejący nie ma klucza z trzech pól, a dopiero trzy pola `:id` przekraczają 2048.

**Przegląd (dwa równolegle, na `32187fc`):**
- *Poprawione:* (1) obaj: menedżer sprawdzał klucz przed odczytem rekordu, więc stawał na zdarzeniu, które i tak
  by zignorował — jedno spreparowane żądanie zatrzymywało go dla wszystkich przebiegów, a replay starego logu też
  stawał; teraz tylko przy `starts?` (`e3218b9`), test pada na starym miejscu (próba odwrotna: kod mutanta równy
  `32187fc`, czerwony tylko ten test). (2) CHANGELOG obiecywał 422 także dla komendy wydanej przez reakcję — ta dalej
  się wywraca (polityka `:in_transaction` → 500); (3) klucz ponad budżetem zapisany przed #98 jest teraz odmawiany —
  CHANGELOG mówi, jak go znaleźć (`octet_length`). Usunięty test porównujący dwie stałe.
- *Bez zmian:* `runs_fit` przed powtórnym sprawdzeniem idempotencji pod blokadą — kolejność celowa (przed
  `for_writing`); powtórne liczenie przebiegów w `runs_fit` i `entry/4` — te same funkcje, nie rozjadą się.
- *Pominięte, ryzyka:* wyżej, „Co zostało”. Tagi (GIN), inbox, `subject_keys`, argumenty Obana i zapas 2048 —
  sprawdzone, w porządku.

### #96 — co wyszło (3 października)

Na `engine/issue-96-key-rules`, od `engine/bounded-values` (#95), bo limit sześciu pól liczy się z 255 bajtów na
`:id`, które wprowadza dopiero #95. Dwie odmowy przy kompilacji, przyjęte przez użytkownika 3 października (#96):

- **F8 — pole korelacji jest `:id`.** Pole zdarzenia, które nazywa `correlate` procesu albo menedżera procesu,
  i pole stanu menedżera, które nazywa jego `correlate`, ma typ `:id`, `{:id, encja}` albo wartość domeny opartą na
  `:id`. W L2 (`Rules.Fields`) odmowa dla typu wbudowanego, enuma i listy; wartość domeny w L3 (`Links.Domain`), gdzie
  domena jest znana — odmowa mówi, na czym wartość stoi (`:money, which rests on :integer`).
- **F9 — klucz ma najwyżej sześć pól**: tożsamość jednostki, `correlate` procesu, `correlate` menedżera
  (`EhOsContract.Key.max_fields/0`).

**Decyzje techniczne (asystenta), z odrzuconymi opcjami:**
- *Nowe kody F8 i F9.* Odrzucone: dopisanie warunków do F4 (opcjonalne i osobowe), R2 i P4 — tabela odmów i
  CHANGELOG pokazałyby wtedy zmianę starego kodu zamiast nowej odmowy, a host szuka nowej.
- *F8 w L2 i L3.* Odrzucone: samo L2, ostrożnie jak A4 (każda wartość domeny odmówiona) — odrzuciłoby korelację na
  wartości opartej na `:id`, jak okres w TaxVision (`value :period, :id`), czyli kształt, który jest poprawny.
- *Pole stanu menedżera też.* `correlate` menedżera, który obsługuje tylko zdarzenia rodzeństwa, bierze typ z pola
  stanu, jeśli stan je deklaruje — bez tego `:string` w stanie przechodziłby X6.

**Pomiar (Postgres 17, 3 października) — inny niż w issue, i próbkowany, nie dowiedziony.** Issue podało: cztery
losowe pola po 255 bajtów i trzy pola samych `|` dają 3344 bajtów i odmowę. U nas pola samych `|` (`%7C` po
escapowaniu) przechodzą, bo wpis indeksu jest kompresowany, gdy to oszczędza ćwierć. Najgorszy jest tekst losowy z
około ćwiercią `|` i `%`: każdy daje trzy bajty, a całość prawie się nie kompresuje. Wyniki (losowe nazwy, po 40–60
prób na punkt):
- **siedem pól** pada w 32–59 próbach na 60 już za nazwą 40 bajtów;
- **sześć pól** nie padło ani razu za nazwą do 60 bajtów. Klucz przebiegu ma nazwę procesu dwa razy (kolumna
  `process` i prefiks `instance_id`), więc za nazwą procesu około 100 bajtów zaczyna padać (2–19 na 40). Klucz
  menedżera ma nazwę raz, ale jest nią `<pełny moduł kontraktu>:process_manager:<nazwa>` — w sandboxie już około 70
  bajtów; wytrzymał 140, dalej nie mierzone;
- **pięć pól** nie padło nigdzie do 140 bajtów nazwy.

Nazwa procesu to atom z kontraktu (`process :visit`), zwykle kilkanaście bajtów, więc klucz przebiegu przy sześciu
polach trzyma. Klucz menedżera nie jest tak bezpieczny: moduł kontraktu w zagnieżdżonej przestrzeni nazw hosta ma
łatwo 100 bajtów i więcej. Ale to próbka: nieskompresowany najgorszy przypadek sześciu pól to 6×765+5 = 4595 bajtów, więc każdy klucz z
dużą domieszką `|`/`%` wchodzi tylko dzięki kompresji, a ktoś, kto dobiera bajty, może celować w jej próg. Przegląd
bezpieczeństwa tego nie dowiódł ani nie obalił. Inny `default_toast_compression` (`lz4`) nie był mierzony.

**Przegląd (dwa równolegle, na `8d71afd`):**
- *Poprawione:* (1) menedżer, którego stan nie deklaruje pola korelacji, bierze typ z pierwszego zdarzenia lokalnego z
  tym polem, także nieobsługiwanego — F8 tego nie widział, a X6 porównywał potem rodzeństwo z tym typem; teraz F8
  sprawdza każde takie zdarzenie (`42547fb`). (2) Kontrakt bez własnych jednostek, który tylko `include`-uje zdarzenia
  rodzeństwa: X6 nie porównywał typu, bo żadne zdarzenie lokalne go nie nadawało — teraz porównuje z `:id`. (3)
  Jedno znalezisko na pole, które nazywa i proces, i menedżer — z testem. (4) Komunikat F8 nie twierdzi już, że tylko
  `:id` ma granicę długości (`:integer` też ma): „correlate only on an identifier, an :id of at most 255 bytes, as
  match: does”. (5) Test L3 dla wartości `{:id, encja}`.
- *Druga runda (na `45819c5`):* poprawka (1) sprawdzała **każde** zdarzenie lokalne z polem, a `Build` bierze typ
  tylko z pierwszego — więc odmawiała poprawnego kontraktu (późniejsze, niezwiązane zdarzenie z `ref :string`).
  Teraz F8 sprawdza dokładnie to pierwsze, w tej samej kolejności, w której czyta je `Build`, a jednostka, której
  tożsamość ma to pole, nadaje `:id` i nic nie trzeba sprawdzać (trzecia runda, na `8b881cd`). Testy: dwa kontrolne
  (późniejsze zdarzenie i wcześniejsza tożsamość — padają na wersji sprawdzającej każde zdarzenie) i jeden na jedno
  znalezisko, gdy obsługiwane zdarzenie też nadaje typ (pada bez `uniq_by`). Wiersz F8 w tabeli
  odmów mówi o tym przypadku. Klucz menedżera z pełnym modułem — wyżej, w pomiarze.
- *Bez zmian:* F8 odmawia też `:integer`, `:date` i enuma, choć są krótkie — tak brzmiała przyjęta reguła („typ
  bazowy `:id`, jak `match:`”). Treść komunikatu powtórzona w L2 i L3 — świadomie, jak przy F7.
- *Pominięte, sprzed tej zmiany:* X6 bierze typ lokalny z dowolnego zdarzenia lokalnego z polem, także
  niewłączonego — szersze, niż trzeba, ale ten typ i tak trzyma F8; X6 odmawia dwóch różnych wartości domeny, obu na
  `:id` (`same_type?`); pole komendy o nazwie pola korelacji trafia do nieindeksowanego `_commands.instance_id`, a
  wartość bez `String.Chars` wywraca tam `Key.escape`. Gwarancje F8 i X6 zależą od kompilatora L3 u hosta
  (`compilers: … ++ [:eh_os_contract]`); bez niego zostają ustaleniem `mix eh_os_contract.check`.
- *Pominięte, poza zakresem:* klucz inboxu (`Bus.Message.key`) bez granicy długości — sprzed tej zmiany; nasz relay
  daje skrót albo `<uuid>/<nazwa>`, a kto publikuje, rozstrzyga grant transportu.

**Do decyzji użytkownika:**
1. *Rozstrzygnięte 3 października: (c), issue [#98](https://github.com/EmpoweredHouse/eh-os-contract/issues/98) —
   budżet bajtów klucza liczony przy dispatchu i w menedżerze; F9 = 6 zostaje. Odrzucone (a) — nie ogranicza modułu
   w kluczu menedżera i dalej jest próbką; (b) — też próbka.* Opis sprzed decyzji:
   **Czy sześć pól z próbki wystarczy.** Możliwe: (a) zostawić F9 = 6 i dodać limit nazwy procesu, jednostki i
   menedżera, np. 64 bajty (N1, nowy powód odmowy) — dla nazw do 60 bajtów próbka nie dała ani jednego padnięcia,
   ale **nie ogranicza to modułu w kluczu menedżera**; trzeba by go też skrócić (np. skrót modułu w kolumnie
   `name`, co zmienia klucz istniejących wierszy); (b) zejść do pięciu — pięć pól nie padło nigdzie do 140 bajtów
   nazwy; (c) deterministycznie: przy dispatchu i przy zapisie menedżera policzyć długość klucza po escapowaniu i
   odmówić ponad budżet (nowa odmowa 422 dla hosta, a dla menedżera — błąd zapisu z czytelnym powodem zamiast
   wyjątku Postgresa). Rekomendacja: (c), osobnym issue — jako jedyna daje gwarancję, a nie próbkę, i pokrywa nazwę
   modułu; F9 = 6 zostaje jako odmowa przy kompilacji kształtów, które i tak by padały.
2. **Pusty `:string` jako wartość pola korelacji** (z E11a) — po F8 to pytanie o pusty `:id`; bez zmian.

### Granice wartości z żądania (3 października)

Pięć znalezisk przeglądu bezpieczeństwa #93; użytkownik przyjął wszystkie propozycje. Gałąź `engine/bounded-values`,
na `engine/unstorable-bytes` (#93). Każda granica to `{pole, :type}` (422); odczyt logu nie pyta o żadną.

**Decyzje użytkownika (3 października), z opcjami, które przegrały:**
- **`:id` najwyżej 255 bajtów** — wpis btree/GIN ~2,7 KB. *Odrzucone:* sprawdzanie długości zbudowanego klucza
  przed transakcją — późno i w jednym miejscu z wielu.
- **`:integer` w int64 — odwraca decyzję z 29 września** (`763cec0`, zapisaną tylko w teście: „The column is JSON
  and the BEAM has bignums, so nothing truncates”). Asystent pokazał konflikt przed zmianą; użytkownik wybrał
  ograniczenie wejścia. *Odrzucone:*
  - bignumy w logu, granica tylko dla parametrów zapytania — read model hosta z `bigint` dalej padałby na komendzie;
  - bez granicy.
- **`:decimal` skończony, wykładnik i współczynnik do tysiąca cyfr.** Przy pisaniu wyszło, że **Decimal 3.1.1 sam
  zatrzymuje wybuch pamięci**, który zgłosił przegląd: tekst parsuje w granicach decimal128 (34 cyfry, wykładnik do
  6144), a `:normal` powyżej 6178 cyfr rzuca `ArgumentError`. Zostały `NaN`/`Infinity` i struktura z kodu (500).
- **`:date`/`:timestamp` w latach 1–9999.**
- **Query string spoza UTF-8 to 400 `query_is_not_utf8`**, po autoryzacji. *Odrzucone:* zostawić Phoenixowi — goły
  Plug daje 500.

**Weryfikacja:** próby odwrotne, każda granica osobno, odczyt logu ograniczony i Plug bez `rescue`. Każda wywraca
test. Granica `:id` w `decode/4` dostała osobny test, bo zapytanie i komenda łapią ją i tak w `fits?`.

**Przegląd przed PR-em**, dwa równolegle. Poprawione, każde z testem:
- `query_is_not_utf8` obejmował też za długi (Plug: 414) i za głęboki query string (oba) — teraz
  `invalid_query_string` ze statusem Plug;
- wartość zakresu do 8 MB dalej szła do `Authorizer` na ścieżce odmowy (oba) — `sent/2` do 255 bajtów;
- JSON Schema (OpenAPI, AsyncAPI) bez granic (poprawność) — `minLength`/`maxLength`, `format: int64`;
- granice zapisane dwa razy — jedno `within?/2`; akapit „Bounds” w złym miejscu; `@doc` `decode/4` mówi, kiedy
  granice obowiązują.

Zapisane, nie zmienione — **granice obowiązują wszędzie, gdzie wartość wchodzi do logu** (oba przeglądy):
- inbox traktuje cudze opublikowane zdarzenie jak wejście;
- komenda reakcji ze starego zdarzenia, zdarzenie decydenta ze stanu i usługa domenowa też są sprawdzane;
- agregat z tożsamością ponad 255 bajtów nie przyjmie kolejnej komendy;
- arytmetyka decydenta poza granicami kończy komendę błędem.

Danych produkcyjnych nie ma, a zgodności wstecz biblioteka nie obiecuje (kierunek z 25 września), więc granica
przy każdym zapisie. *Odrzucone:* granice tylko na wejściu z żądania — stara wartość wracałaby do logu bez
sprawdzenia, a struktura z kodu hosta też. Węższe granice (`varchar(n)`, suma w read modelu) są domeny — jako
niezmiennik wartości.

**Do decyzji użytkownika** (nowe odmowy przy kompilacji, przegląd bezpieczeństwa):
- `correlate` na polu `:string` buduje klucz btree bez granicy;
- tożsamość lub korelacja z siedmiu i więcej pól `:id` przekracza ~2,7 KB wpisu.

Pominięte: przykłady w scenariuszach nie są sprawdzane granicami przy kompilacji — padną w teście scenariusza.

Silnik: 1126 → 1135.


**CodeRabbit, 3 października (po przestawieniu #95 i #97 na `main`)** — cztery komentarze do kodu #95, wszystkie
wprowadzone:
- `Codec.decode/4` przyjmował pusty `:id`, a `problems/4` go odrzucał; inbox bierze zdarzenie samym dekodowaniem,
  więc pusty identyfikator docierał do polityki. Granica `:id` to teraz 1–255 bajtów w `within?/2`.
- **Decimal ponad 34 cyfry nie czytał się z logu** (ważne): Decimal 3.1.1 parsuje tekst tylko w granicach decimal128,
  a nasza granica to tysiąc cyfr — zdarzenie zapisane z kodu z 35 cyframi nie dałoby się złożyć. Kodek czyta teraz
  zwykłą formę (`-123.456`), w której log zapisuje wartość, z zerami z końca z powrotem do wykładnika. *Odrzucone:*
  zejście z granicą do 34 cyfr — zmienia to, co host może zapisać, a kłopot jest w odczycie, nie w granicy.
- JSON Schema: `minimum`/`maximum` dla `:integer` (`format` tylko adnotuje) i `x-eh-os-contract-max-bytes` dla `:id`
  (`maxLength` liczy znaki).

### Bajty, których tabele silnika nie utrzymają (3 października)

Zadanie zgłoszone w przeglądzie #66 i uruchomione przez użytkownika. Gałąź `engine/unstorable-bytes`, od `762521e`.
Wszystkie trzy przypadki odtworzone testem (`test/runtime/unstorable_bytes_test.exs`) jako `Postgrex.Error`, czyli
500. Do tego dwa nowe: NUL w parametrze query (`%00`) i klucz idempotencji bez limitu długości (wpis btree
indeksu unikalnego ma ~2,7 KB).

**Decyzje użytkownika (3 października), za rekomendacją:**
- **Tekst z NUL albo złym UTF-8 w polu `:string`/`:id` nie pasuje do typu** — istniejący problem `:type`, 422
  `{"invalid": {"<pole>": "type"}}`. *Odrzucone:*
  - nowy rodzaj problemu (`:not_text`) — nowa wartość dla klientów;
  - ciche usunięcie NUL — zmienia dane bez słowa.
- **Klucz idempotencji wywołującego: drukowalne ASCII `0x21`–`0x7E`, najwyżej 255 bajtów**, inaczej nowy powód
  `:idempotency_key_invalid` (Plug: 400). *Odrzucone:*
  - skrót klucza jak w #66 — chowa błąd klienta, kolumna z dwoma rodzajami wartości;
  - samo ASCII bez limitu — zostawia 500 dla długiego klucza.

**Co jest:**
- `Codec`: `text?/1` w `decode` i `fits?`, więc jedna zmiana obejmuje każdą drogę: HTTP, `call/3`, query, `dispatch/3`
  ze struktury i inbox.
- `Dispatcher.keyed/1` w `dispatch/3` i `record/3`, po autoryzacji i polach. Klucz reakcji też (po uwadze
  CodeRabbita: aktor reakcji to struktura, którą zbuduje każdy wywołujący; klucze biblioteki i tak przechodzą).
- Plug: 400 i wiersz w tabeli.
- CHANGELOG w „Changed — a host has to act”.

**Weryfikacja:** próby odwrotne — tekst jako dowolny binarny, NUL dozwolony, bez sprawdzenia klucza, bez limitu,
nagranie bez sprawdzenia, Plug bez 400. Każda wywraca co najmniej jeden test.

**Przegląd przed PR-em**, dwa równolegle. Poprawione, każde z testem:
- **zapieczętowana wartość osobowa z NUL, zapisana przed regułą, przestałaby się otwierać** (poprawność) — odczyt
  logu (`:opened`) nie sprawdza tekstu ponownie;
- **wartość zakresu z NUL dalej szła „jak wysłana” do `Authorizer`**, a `eh_os_contract_auth` zapisuje ją w kolumnie
  tekstowej (oba) — teraz `nil`, więc `:outside_scope`, niezależnie od #66;
- CHANGELOG i doc: reguła klucza surowsza, niż wymagają kolumny, a pusty nagłówek to teraz 400; inbox odrzuca
  wiadomość także o pole, którego polityka nie zapisuje;
- OpenAPI: wzorzec nagłówka i opis 400; wyrażenie klucza `{1,255}` z komentarzem, czemu bez `u`;
- testy: nagranie, pusty nagłówek, lista.

Bez zmian w tym PR-ze — **znalezione przez przegląd bezpieczeństwa, każde to nowa odmowa, do decyzji
użytkownika**:
- `:decimal` z ogromnym wykładnikiem — `"1E1000000000"` (25 bajtów) przy zapisie w formie `:normal` buduje ~16 GB
  (HIGH, uśpione: żaden kontrakt sandboxa nie ma `:decimal`); także `NaN`, `Infinity`;
- `:id` bez limitu długości przy indeksach btree i GIN (~2,7 KB) — 500;
- `:integer` bez zakresu — przepełnienie `numeric` w `jsonb`, `bigint` w read modelu hosta, bignum w zapytaniu;
- `:date` i `:timestamp` poza zakresem Postgresa;
- zły UTF-8 w query stringu — `Plug.Conn.InvalidQueryError` (Phoenix: 400, goły Plug: 500).

Poza zakresem, informacyjnie: `correlation_id`/`causation_id` od bezpośredniego wywołującego `dispatch/3`, podmiot
`Actor.credential/3` z NUL, klucz wiadomości inboxu od transportu.

**Uwagi CodeRabbita na #93**, trzy, wszystkie przyjęte, każda z testem tam, gdzie zmienia zachowanie: dowolne bajty
tylko dla wartości otwartej z pieczęci (`:opened`), nie przy każdym `open:`; `@doc` dla publicznego
`Codec.text?/1`; bez zwolnienia klucza reakcji. Przegląd tej poprawki (jeden przebieg): klucz pochodny reakcji przy
bardzo długich nazwach (ponad ~208 bajtów na kontrakt i nazwę) albo cytowanym module łamałby regułę i blokował
reakcję — teraz taki jeden jest skrótem `<rodzaj>:sha256:<hex>`, a każdy inny zostaje w dawnej postaci, więc
ponowne dostarczenie nie robi drugiej komendy; `open: :opened` od wywołującego wpuszczałby dowolne bajty — `decode/4`
przyjmuje tylko funkcję albo `nil`; doc `dispatch/3` mówi o kluczu reakcji. Silnik: 1124 → 1126.

Silnik: 1114 → 1124.

### EB3b — co wyszło (2 października)

Gałąź `eb/eb3b-applications`, od `499ea0b` (merge #87). Ostatnia część EB. WIP `020a3a5` z poprzedniej sesji
(`resource` i `invalid_target` w `Renewal`, `Sessions.refused/4`) wszedł w zwykłe commity.

**Co jest:**
- **`Session.credential/3`** — sesja (`conn` albo mapa sesji LiveView), nazwa aplikacji z
  `sign_in: [applications: ...]`, opcje z `sign_in:`. Idzie przez `Renewal.credential/4` z adresem tej aplikacji,
  pod tą samą dzierżawą co własny credential. Zwraca surowy token EHOS-a, bez `verify/2` (S8).
- **`resource` w odnowieniu** innej aplikacji (`body_extension` w `Oidcc.Token.refresh/3`); własna go nie wysyła.
- **`invalid_target`** → `{:error, :refused}`:
  - zapamiętane w `refused_until` na 10 minut;
  - refresh token zostaje, sesja żyje dla każdej innej aplikacji;
  - dzierżawa zwolniona, a trzymany credential tej aplikacji skasowany — w jednej transakcji, strzeżonej
    `lease_holder`.
- **`FakeEhos`:**
  - grant ma mapę `"applications"` (adres → `aud`);
  - `resource` spoza niej to 400 `invalid_target` **przed** oznaczeniem tokenu jako zużytego — jak
    `Ehos.SignIn.Token` na `main` EHOS-a;
  - następca tokenu trzyma grant logowania, nie pojedynczego credentialu;
  - `applications/2` — rola nadana albo zabrana w międzyczasie;
  - `refresh_answer(:invalid_target)`.
- **Przy starcie** dziecko odmawia adresu z `applications` równego własnemu `address` (D-69).
- ADR: datowane poprawki w S5 i S7.
- Auth: 263 → 270 testów przed przeglądem.

**Decyzje asystenta:**
- **Odmowa kasuje trzymany credential tej aplikacji.** *Odrzucone:* zostawić go, aż wygaśnie (pierwsza wersja
  WIP-u) — `freshness/2` i tak by go nie oddał, a każda kopia w tabeli to kolejna do chronienia (S3).
- **Nieznana nazwa → `ArgumentError`.** *Odrzucone:* `{:error, :unknown_application}` — to literówka w kodzie
  hosta, nie stan osoby; krotka błędu byłaby obsłużona jak odmowa i schowałaby literówkę.
- **`credential/3` bierze tylko `sign_in:`.** *Odrzucone:* opcje `verify/2` jak w `actor/2` — credential innej
  aplikacji nie jest tu weryfikowany (S8).
- **`invalid_target` dla własnej aplikacji to zwykła odpowiedź z błędem** (pauza, token zostaje). EHOS tak nie
  odpowiada bez `resource`. *Odrzucone:* koniec sesji (propozycja przeglądu) — EHOS nic nie zużył, więc koniec
  kosztowałby logowanie za nic; i zapamiętanie odmowy (pierwsza wersja) — każda strona sesji dawałaby 401 przez
  10 minut.
- **Własny adres w `applications` odrzucany przy starcie.** *Odrzucone:* odmowa przy każdym wywołaniu
  `credential/3` — błąd konfiguracji wychodziłby dopiero na stronie.

**Weryfikacja:** próby odwrotne (Python, `cp` z kopii):
- bez `resource`;
- `resource` zawsze;
- bez klauzuli `invalid_target`;
- odmowa niepamiętana, wieczna albo na 20 min;
- odmowa zostawiająca token albo dzierżawę;
- `credential/3` z własnym adresem;
- fałszywy EHOS zużywający token przy `invalid_target`.

Każda wywraca co najmniej jeden test EB3b.

**Przegląd przed PR-em**, dwa równolegle. Poprawione, każde z testem, który bez poprawki pada (poza `kept/3`):
- **Odmowa zapisywana bez dzierżawy** (oba). Wylogowanie w drugiej karcie w trakcie wywołania kończyło się
  naruszeniem klucza obcego i 500. Teraz `refused/4` strzeżone `lease_holder` jak `renewed/4`; `:lost` →
  `{:error, :signed_out}`.
- **Adres własnej aplikacji w `applications`** (oba). `credential/3` oddawał jej własny credential jako cudzy.
  Teraz odmowa przy starcie. Widoczne dla hosta, nowa odmowa konfiguracji — w CHANGELOG jako „Changed”.
- **`invalid_target` dla własnej aplikacji** zapamiętywał odmowę (oba). Teraz klauzula tylko dla innej
  aplikacji.
- `kept/3` obsługuje `:refused` (poprawność; nieosiągalne, bez testu); martwe `refused_until: nil` usunięte;
  zdanie w `@doc` i README, że token zostaje na serwerze (bezpieczeństwo). Dopisany test braku odpowiedzi dla
  innej aplikacji (luka w testach).

Bez zmian:
- **`credential/3` czyta sesję przy każdym wywołaniu** (oba) — jak `actor/2` wołane wprost. Przekazanie sesji
  z plugu to osobna zmiana.
- **Bez podglądu `aud`/`sub` credentialu innej aplikacji** (bezpieczeństwo) — S8 to odrzuca.
- **`invalid_target` tylko z 400** — EHOS i RFC 6749 dają 400.
- **`refused_until` z zegara aplikacji, nie bazy** — jak `expires_at`.
- **Dwie nazwy pod jednym adresem** dzielą wiersz. To ta sama aplikacja, więc nieszkodliwe.

Auth: 270 → 274 testów.

**Otwarte — użytkownika:** [#78](https://github.com/EmpoweredHouse/eh-os-contract/issues/78) zamknął opis PR-a
#86. Otworzyć ponownie i zamknąć PR-em EB3b, czy zostawić zamknięty z linkiem? Opis PR-a EB3b nie zawiera
„closes #78”.

## Dopisek 1 października — lista zmian do `eh-os` jako issues w `EmpoweredHouse/eh-os`

**Decyzja użytkownika (1 października):** potrzebę zapisujemy tutaj, a opis zadania i wymagania lądują w issue
w `EmpoweredHouse/eh-os`, gdzie da się je podjąć. *Odrzucone:* lista tylko w `PLAN.md`, jak dotąd. Punkty były
rozsiane po sekcjach „co wyszło”, szukało się ich grepem, a po stronie EHOS-a nikt ich nie widział. Uwagi do
D-51/D-52 nie trafiły do nich przed akceptacją rekordów. Issue zakładamy przez `gh` i nie piszemy nic do
repozytorium `eh-os`, więc reguła „tylko czytanie” stoi.

Pytanie, od którego to wyszło: czy aplikacja kliencka może logować użytkowników tożsamością EHOS-a. **Dziś nie
może.** EHOS loguje tylko do własnej konsoli (`phx.gen.auth`). Credential osoba kopiuje ze strony `/credentials`
i nie ma endpointu, który by go wydawał. D-24 wyklucza bycie dostawcą OIDC dla innych aplikacji, a logowanie
przeglądarkowe do aplikacji jest u nich „osobnym etapem”, na razie bez rekordu.

Każdy punkt listy sprawdzony 1 października na `eh-os` `main` = `c2ea39f`. Lokalna kopia `~/Projects/ai/eh-os`
stała na `e77f44e`, więc czytany był świeży klon w scratchpadzie.

| Punkt (gdzie w tym pliku) | Stan po stronie EHOS-a | Issue |
| --- | --- | --- |
| Logowanie frontendu aplikacji (E6) i użytkownicy końcowi, którzy nie są ludźmi konsoli | niezaprojektowane: D-24, G-3, „osobny etap” w `ROADMAP.md` | [eh-os#95](https://github.com/EmpoweredHouse/eh-os/issues/95) |
| `scp` w credentialu (D10, D-15 zawężone przez D-40) | D-40 dalej `proposed`, `Ehos.Credentials` nie wydaje `scp`, więc każde query ze `scope:` odpada z prawdziwym credentialem (`:unscoped_grant`) | [eh-os#94](https://github.com/EmpoweredHouse/eh-os/issues/94) |
| Fixture manifestu TaxVision (E10, „Rozjazd odbioru manifestu”) | fixture bez zmian: dwie komendy, stare etykiety | [eh-os#91](https://github.com/EmpoweredHouse/eh-os/issues/91) |
| Kto może publikować pod nazwą (E12c, „Do E12d i E12e, i otwarte”) | D-41 (`proposed`) sprawdza `publishes` tylko przy rejestracji (C-2), w transporcie nic nie zatrzymuje cudzej nazwy, a inbox ufa wiadomości | [eh-os#96](https://github.com/EmpoweredHouse/eh-os/issues/96) |
| D-51/D-52, uwaga 1: `contracts` w digeście uprawnień | D-52 przyjęty z `contracts` w digeście uprawnień | [eh-os#92](https://github.com/EmpoweredHouse/eh-os/issues/92) |
| D-51/D-52, uwaga 4: rozłączne ścieżki dewelopera i generatora | D-52 przyjęty bez tej reguły | [eh-os#93](https://github.com/EmpoweredHouse/eh-os/issues/93) |
| D-51/D-52, uwagi 2, 3, 5 | załatwione w przyjętych rekordach: przypięta kopia schematu w każdym wydaniu (D-51), YAML 1.2 core i odmowa duplikatów i aliasów (D-51, `docs/ehos-yaml.md`), `schema` jako jedyny podmieniany klucz (D-52) | — |
| D-51/D-52, uwagi 6, 7 | nieaktualne: manifest `ledger` generuje i publikuje CI `ehos-ledger` (D-52); kolejność rozstrzygnęliśmy 29 września | — |
| D10–D12: D-01, D-15, D-03 i „Outbox rows”, G-16 | wszystkie mają notkę z datą (D-40, D-41). Pytanie „co przenosi wiadomość między kontenerami” EHOS trzyma jako otwarte w G-16 | — |
| D14: D-34 „a call, not a gate”, „five tables”, test odmowy z D-40 | załatwione przez D-43 (`accepted`, 27 września) | — |
| D14: plan etapu 4, kroki 6–8 | nieaktualne: etap 4 zamknięty, trwa etap 5 | — |
| Port `4001.0` przechodzi sprawdzenia EHOS-a obok schematu `ehos.yaml` (EH2, „EH2 — co wyszło”) | `beside_the_schema/1` porównuje porty przez dopasowanie i klucz mapy, więc `4001.0` ≠ `4001` | [eh-os#111](https://github.com/EmpoweredHouse/eh-os/issues/111) |
| Refresh bez ID tokenu, którego `oidcc` nie przyjmuje (EB, „Dopisek 2 października”) | `Ehos.SignIn.Token` przy refreshu nie zwraca `id_token`, a `oidcc_token:refresh/3` daje wtedy `sub_invalid` po zrotowaniu tokenu | [eh-os#133](https://github.com/EmpoweredHouse/eh-os/issues/133) — **załatwione** 2 października ([eh-os#137](https://github.com/EmpoweredHouse/eh-os/pull/137), `801f758`, bez wydania); u nas [#80](https://github.com/EmpoweredHouse/eh-os-contract/issues/80) |
| Adresy innych aplikacji dla `resource` (EB) | `sign_in.applications` podaje nazwy, D-56 nie daje adresów | [eh-os#134](https://github.com/EmpoweredHouse/eh-os/issues/134) — odpowiedź w D-68 (przyjęte 2 października, eh-os#141): `EHOS_SIGN_IN_APPLICATIONS`; u nas [#81](https://github.com/EmpoweredHouse/eh-os-contract/issues/81) |
| Format `EHOS_CLIENT_KEY_FILE` i wyliczany `post_logout_redirect_uri` (EB) | nieustalone do kroku 2 etapu 9; klienty z konfiguracji, w testach `https://<host>/` | [eh-os#135](https://github.com/EmpoweredHouse/eh-os/issues/135) — odpowiedź w D-68 (przyjęte 2 października, eh-os#141): JWK z `kid` i `use`, bez PEM; `https://<host>/`; u nas [#81](https://github.com/EmpoweredHouse/eh-os-contract/issues/81) |
| Pytanie o CSP (EG3) | rozstrzygnięte bez pytania: konsola nie ma `report-uri`/`report-to` ani RUM, a EHOS nie ustawia CSP aplikacjom klienckim | — |

**Co zostaje po naszej stronie, gdy EHOS odpowie:** przy #94 — capability ze `scope` i wymiarem w
`mix eh_os_contract.manifest` z manifestem v2. Przy #93 — generator odmawia, gdy `ehos.yaml` ma już ścieżkę, którą
on pisze. Przy #95 — drugi Plug w `eh_os_contract_auth`: sesja przeglądarki i odnawianie credentiala. Przy #92 —
ewentualnie węższy digest kontraktu. Przy #96 — `<nazwa>.publish` wyprowadzany z `publish`, jeśli manifest ma go
nieść. Nowa potrzeba wobec `eh-os` od teraz: wiersz w tej tabeli i issue.

## Dopisek 28 września — dashboard na design systemie EmpoweredHouse

Poza kolejnością etapów v2, na gałęzi `claude/dashboard-design-system-migration-6df600`. To samo, co `eh-os`
zrobił dla konsoli w D-42 (PR EmpoweredHouse/eh-os#36), przełożone na montowalną bibliotekę ze zwykłym CSS.
Założenia w [`docs/adr/dashboard-design-system.md`](docs/adr/dashboard-design-system.md), **status
`proposed`** — czeka na akceptację.

**Co jest.** Kopia `colors_and_type.css` w `packages/eh_os_contract_web/assets/css/vendor/empoweredhouse/`
z `SOURCE.md` — bajt w bajt ta sama co w `eh-os` (SHA-256 `704bbd4e…`), `.gitattributes` z `-text`. Fonty
(Albert Sans, JetBrains Mono, 400/500, `latin` + `latin-ext`, OFL) w `priv/static/assets/fonts/`, obok
zbudowanego `app.css`, więc **host nie dodaje nic** — serwuje je ten sam `Plug.Static` co `app.css`, a
względne `url()` rozwiązują się względem arkusza. esbuild dostał `--external:*.woff2`, bo inaczej próbuje
rozwiązać `url()` i pada. Warstwa `app.css` importuje kopię, zmienne `--eh-os-contract-*` zostają jako API
hosta i wskazują na tokeny. Mermaid dostaje motyw z tokenów w runtime (`getComputedStyle`, przeliczone na
hex przez canvas, bo silnik motywów Mermaida czyta tylko hex), przerysowuje się przy zmianie motywu.
Skill odświeżania: `.claude/skills/sync-design-system/`. Testy: `test/design_system_test.exs`, 8.

**Decyzje użytkownika (28 września):**

- **Werdykt:** *breached* w kolorze błędu (coral) z kropką, *met* i *in progress* neutralnym tekstem —
  różnicę mówi zdanie. *Odrzucone:* kropka lime przy „Met in all N runs” (lime przekroczyłby ~5% ekranu
  przy wielu obietnicach, a spełniona obietnica to przypadek zwykły, nie sygnał); neutralne badge dla
  *in progress* (nowy element w szablonie zamiast samego CSS).
- **Kolory węzłów silnika w diagramach:** paleta Event Stormingu grafu v2 **zostaje na razie** — „w
  niedalekiej przyszłości będzie to zmieniane”, więc podmiana siedzi w jednej tabeli (`NODE_CLASSES` w
  `assets/js/app.js`), do której klasy Event Stormingu dołączą jedną zmianą. Kolory stanów v1 (`confirmed`,
  `in_flight`, `dead`, `terminal`, `external`) dashboard podmienia na tokeny, bo to kolory statusu, których
  design system nie ma. Silnik bez zmian — jego Mermaid idzie też do `mix eh_os_contract.graph`.
  *Odrzucone:* wszystko z tokenów (traci kolory, które ludzie znają z warsztatu); nie ruszać `classDef`
  (zielony „ok” na ciemnym tle łamie zasady).

**Znalezione przy weryfikacji, do zrobienia osobno.** **Ekran grafu nie działa pod ścisłym CSP i nie
działał nigdy.** Mermaid wstawia `<style>` do każdego SVG; pod `default-src 'self'` (tak ma EHOS) każdy
diagram to czarne prostokąty. Sprawdzone na sandboxie z polityką EHOS-a dodaną tylko na czas testu — z
arkuszem i skryptem sprzed tej zmiany wynik ten sam, więc to nie regresja. README pakietu mówi teraz
wprost, że ekran grafu wymaga `style-src 'unsafe-inline'`. Naprawa to rysowanie diagramów bez stylu
inline (np. SVG po stronie serwera albo przeniesienie reguł do arkusza) — osobna decyzja.

Drugie znalezisko, naprawione na miejscu: Mermaid 11 owija etykietę węzła w `<p>`, więc stronowa reguła
`p { color }` przebijała `color:#000` z `classDef` i etykiety na pastelowych węzłach Event Stormingu były
nieczytelne. Reset `pre.mermaid p` w warstwie.

Usunięte przy okazji martwe reguły z czasów panelu kont: `button[phx-click="revoke_role"]` i
`nav a:last-child { margin-left: auto }` — ta druga przy dwóch linkach spychała „Graph” na prawą krawędź.
Po przeglądzie także reguły `table`/`th`/`td`, `input` i `button`: żaden szablon ich nie renderuje.

**Przegląd (dwa równolegle, `pre-pr-review`).** Naprawione: kolory przez odczyt pikseli z canvasa
(przeglądarki antyfingerprintingowe blokują albo zaszumiają `getImageData`) — teraz przez ukryty element
i złożenie alfy w JS; brakujący albo nieczytelny token dawał po cichu zły kolor — teraz nazwany błąd,
diagramy spadają do wyglądu Mermaida, a LiveView łączy się mimo to (wcześniej wyjątek na górze `app.js`
zabijał cały dashboard); nakładające się rysowania jednego diagramu — teraz kolejka per element;
`document.fonts.ready` nie ładował podzbioru `latin-ext` przed pomiarem polskich etykiet — teraz
`document.fonts.load` z tekstem diagramu; focus niewidoczny w forced-colors; kolory `classDef` liczone
przy każdym rysowaniu zamiast raz na motyw. Testy: token czytany przez `app.css`/`app.js`, którego kopia
nie definiuje; `url(data:…)`; komunikat przy skrypcie inline, który ginął w `MatchError`.

**Poprawione założenie:** zmienne `--eh-os-contract-*` nie są i nie były powierzchnią nadpisywania dla
hosta — root layout zastępuje layout hosta i ładuje tylko arkusz pakietu, więc żaden arkusz hosta ani
`data-theme` tu nie dociera. README i ADR mówiły inaczej; poprawione (w ADR z datą). **Otwarte, do
decyzji:** czy dać hostowi wejście (np. opcję makra z własnym arkuszem albo motywem) — to nowy kształt
widoczny dla hosta, więc nie w tej zmianie.

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
- **Wartości w scenariuszach mówią, czym są** (decyzja użytkownika z 27 września, propozycja z 26 września):
  „account-anna”, „visit-anna”, „krakow”, nie „a-1”, „b-7”. Dotyczy nowych scenariuszy i testów od teraz;
  istniejące poprawia się przy okazji dotykania pliku, bez osobnego commita przepisującego. Szczegół asystenta,
  nie użytkownika: wartość to identyfikator danych testowych, nie tekst dla klienta, więc słowa po angielsku
  (reguła „kod po angielsku” z `CLAUDE.md`), a imiona i miasta bez diakrytyków. Pierwsza wersja tego akapitu
  miała „konto-Anny” i „wizyta-Anny” — poprawione 27 września, gdy test EA2 dostał przez nią polskie słowa.
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
— same deklaracje i ich reguły L2, bez runtime'u. Od D14 (v2 §16) model wyprowadza nazwy, na których stoi EHOS:
uprawnienie `<domena>.<komenda>` i `<domena>.<query>`, rola `<domena>.<aktor>`, gdzie `<domena>` to `name:`
domeny; `Model.capabilities/1` jest kluczowane nazwą uprawnienia. Nazwa komendy lub query jest więc unikalna w
całej aplikacji — reguła między kontraktami wchodzi z L3 w E5. Zmyślona fikstura `UniversalityGate` przepisana na nowy DSL; fikstury testów to moduły inline poza
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
**Zrobione 25 września** i zmergowane jako PR #9 (`db00403`): 12 commitów E4, pięć poprawek z przeglądu
przed PR i dwa commity `PLAN.md`. Oba warunki D13 przeszły, choć jedno założenie pod
nimi było błędne; kryteria odbioru spełnione — „E4 — co wyszło” niżej.

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
**Podzielony na dwa PR-y** (decyzja użytkownika z 25 września, żeby diff dało się przeczytać): **E5a** —
generowanie struktur i behaviours, wiązanie implementacji z L4, reguły S, `ScenarioCase`, decider fikstury,
kierunek zależności w xref; **E5b** — kompilator `compile.eh_os_contract` z regułami X i częściami L3 z
D10/D11/D14, para wydawca–subskrybent, literówka w `by:` psująca `mix compile`. **E5a zrobione 25 września**
na `claude/dsl-v2-e5-codegen-0c8df1`, 8 commitów od `b1d4a27` i 8 poprawek z przeglądu przed PR, wypchnięte
na `dsl-v2/e5-codegen` jako [PR #10](https://github.com/EmpoweredHouse/eh-os-contract/pull/10) — „E5a — co
wyszło” niżej. **E5b zrobione 25 września** na `dsl-v2/e5b-compiler`, sześć commitów (`686fcab`..`423164c`) na
`main` z E5a, i pięć poprawek z przeglądu przed PR; zmergowane jako
[PR #11](https://github.com/EmpoweredHouse/eh-os-contract/pull/11) (`6ef626b`) — „E5b — co wyszło” niżej.

**E6 — Dispatch synchroniczny i przejście VisitSettlement.** `Dispatcher`, `Codec`, `Capability`, idempotencja,
ponowienia, projekcje i polityki inline, `record/3` (D6), wiersze `_commands` (v2 §11–12); query przez tę samą
ścieżkę autoryzacji co komendy, ze `scope` i sprawdzeniem zwróconych wierszy (D10), i `EhOsContract.Plug`
wystawiający komendy i query modelu po HTTP. Autoryzacja przez behaviour `EhOsContract.Authorizer` (D14):
dispatch i query pytają go, czy `ctx.actor` ma uprawnienie deklaracji; domyślna implementacja porównuje z
uprawnieniami niesionymi przez aktora i niczego nie zapisuje, a aktorzy `:system` (polityki, process managery,
efekty) są sprawdzani tylko względem `by:`/`recorded_by:`. Credentiale, klucze i wiersz audytu to EA. Jeden commit
zastępuje stary kontrakt VisitSettlement, `Rehmed.Settlement.decide/1` i `rehmed_contract_examples_test`
nowym kontraktem, domeną, implementacją i testem scenariuszy (v2 §4.5). `@version "0.3.0-dev"` i linia w
CHANGELOG „Unreleased” (sekcja istnieje od `b58062b`) — od tego commita wersje kontraktów się ruszają. Na każdym skillu baner „opisuje v1”. Poprawki
ADR: „historia, nie sourcing” i wiersz o Commanded (design-rationale), §7–8.
*Odbiór:* cztery scenariusze przechodzą; decyzja zwracająca niezadeklarowane zdarzenie rzuca wyjątek, a magazyn
się nie zmienia — kontrola: zadeklarowane zostaje dopisane; wyjątek w projekcji inline wycofuje dopis; odmowa
uprawnień niczego nie zapisuje — ani do logu, ani do `_commands` (wiersz odmowy należy do implementacji
`Authorizer`, EA); query o wartość `scope` spoza grantu jest odrzucone, zanim ruszy implementacja;
uprawnienie ze `scope` bez żadnej wartości w grancie jest odrzucone (fail closed); implementacja zwracająca
cudzy wiersz jest zatrzymana — kontrola: wartość z grantu przechodzi; konflikt jest
ponawiany; ten sam klucz idempotencji zwraca te same pozycje;
delta `check` w sandboxie dotyczy tylko linii VisitSettlement.
**Zrobione 26 września** na `dsl-v2/e6-dispatch`, dziewiętnaście commitów (`bbad60c`..`7303de9`) z poprawkami z
przeglądu przed PR i zapis stanu, wystawione jako PR; odbiór spełniony — „E6 — co wyszło” niżej.

**EA — Pakiet `eh_os_contract_auth` (D14, v2 §16; `eh-os` D-33, D-34).** Trzeci pakiet w `packages/`, obok
`eh_os_contract_web`, z własnym `mix check`; rdzeń od niego nie zależy. Implementuje `EhOsContract.Authorizer`
z E6 dla credentiali EHOS-a:
- `verify/2`: JWT z nagłówkiem `alg: "Ed25519"` (tylko ten), `kid` = odcisk RFC 7638, `iss` z konfiguracji,
  `aud` dokładnie `<aplikacja>/<środowisko>`, `exp`; powody `:expired`, `:unknown_key`, `:bad_signature`,
  `:wrong_audience`, `:wrong_issuer`, `:no_keys`. Z `sub`, `cap` i `scp` (`eh-os` D-40) buduje `ctx.actor`.
  Joken do kryptografii, bez `joken_jwks` (powód w D-34);
- klucze z `/.well-known/jwks.json` w tabeli w bazie aplikacji (własna migracja, wzorzec
  `EhOsContract.Migrations`): przy starcie ostatni dobry zestaw z tabeli, potem pobranie; odświeżanie co 5 min;
  nieznany `kid` — wcześniejsze pobranie najwyżej raz na 30 s; nieudane pobranie niczego nie zmienia;
- wiersz audytu każdej decyzji — principal, uprawnienie, wersja kontraktu, wynik, powód, przy query ze `scope`
  także wartość — we własnej tabeli pakietu;
- Plug dla tokenu bearer przed `EhOsContract.Plug`;
- pomocnik testów: host mapuje każdą komendę i query modelu na funkcję wołającą swój punkt wejścia, pomocnik
  woła każdą credentialem bez uprawnienia i oczekuje odmowy z wierszem; deklaracja bez mapowania go wywraca.

Po E6 (behaviour i ścieżka dispatchu), niezależny od E7–E9; `verify/2` i klucze nie czytają kontraktu i mogą
ruszyć wcześniej. Poprawki: `CLAUDE.md` („Czego nie budujemy” — zrobione przy zapisie D14),
`docs/adr/identity-seam.md` (notka z datą — zrobione przy zapisie D14).
*Odbiór:* testy z D-34 — klucz usunięty z JWKS odrzucony po następnym odświeżeniu; nieudane pobranie zostawia
ostatni zestaw; nieznany `kid` pobiera najwyżej raz na interwał; pierwszy start bez EHOS-a odrzuca z
`:no_keys`; restart bez EHOS-a działa na kluczach z tabeli. Ponadto: `alg: "EdDSA"`, credential innego `aud` i
innego `iss` odrzucone; uprawnienie ze `scope` bez wpisu w `scp` odrzucone; odmowa ma wiersz w tabeli pakietu, a
log i `_commands` nie dostają niczego; pomocnik pada na komendzie bez mapowania — kontrola: credential z
uprawnieniem przechodzi i też ma wiersz.

Rozstrzygnięte przez użytkownika 27 września przed budową EA (EA przed E8):
- **Dwa PR-y**, drugi na gałęzi od pierwszego. **EA1 — weryfikacja** (`dsl-v2/ea-verify`): pakiet z własnym
  `mix check` w bramie sandboxa i w CI, `verify/1,2`, magazyn kluczy (tabela, pobieranie, odświeżanie, nieznany
  `kid`), migracja; nie czyta kontraktu; wszystkie testy D-34 i odrzucenia `alg`/`aud`/`iss`. **EA2 —
  autoryzacja** (od EA1): `Authorizer` z tabelą decyzji, Plug bearer, pomocnik testów, sandbox (VisitSettlement
  przez pomocnika), CHANGELOG, poprawki ADR.
- **Wpięcie wzorem silnika.** `EhOsContract.Auth` sam implementuje behaviour (`config :eh_os_contract,
  authorizer: EhOsContract.Auth`); `config :eh_os_contract_auth, issuer:, audience:, jwks_url:` (domyślnie
  `issuer <> "/.well-known/jwks.json"`), repo z `config :eh_os_contract, :repo`; dziecko `EhOsContract.Auth` w
  drzewie hosta po Repo; `EhOsContract.Auth.Migrations.up/down` w migracji hosta; tabele
  `eh_os_contract_auth_keys` i `eh_os_contract_auth_decisions`. `verify(token)` bierze `aud`/`iss` z
  konfiguracji, `verify(token, audience: …)` je nadpisuje; zwraca `{:ok, %EhOsContract.Actor{kind:
  :credential}}` albo jeden z sześciu powodów.
- **Plug**: brak nagłówka → 401 `{"error": "no_credential"}`, zły token → 401 z powodem i linia w logu. Wiersz
  audytu mają tylko decyzje `Authorizer`: przy złym tokenie nie ma zaufanego podmiotu, a zalew
  nieuwierzytelnionych żądań zapełniałby tabelę.
- **Pomocnik testów**: `assert_every_entry_refuses(contracts, %{"<uprawnienie>" => fn token -> … end})`, klucz to
  nazwa uprawnienia z modelu; pomocnik wybija token kluczem testowym, który sam wstawia do magazynu kluczy, woła
  każdą funkcję tokenem bez uprawnienia i sprawdza wiersz odmowy oraz pusty log i `_commands`; brak mapowania
  albo klucz spoza modelu → pad. `EhOsContract.Auth.Testing.credential(sub, cap, scp \\ %{})` do testów
  pozytywnych. Wariant z gotowym aktorem odrzucony: omijałby weryfikację, więc nie sprawdzałby całych drzwi.

Mechanika, rozstrzygnięta przez asystenta 27 września (wyjaśniona użytkownikowi przed budową):
- **Podwójny zapis przyjętej komendy (otwarte od D14) to dwa fakty.** Silnik pyta `Authorizer` przed
  transakcją dispatchu (`permit/3` w `dispatcher.ex`), więc wiersz pakietu zapisuje decyzję o uprawnieniu, a
  `_commands` wynik komendy — komenda może przejść autoryzację i paść na inwariancie. Oba zostają; notka w D14.
- **Wiersz audytu idzie połączeniem wywołania.** Host, który sam otwiera transakcję wokół `dispatch` i ją
  wycofuje, wycofuje też wiersz odmowy; na ścieżce przez Plug takiej transakcji nie ma. Osobne połączenie na
  audyt komplikuje sandbox testów bez zysku na drzwiach, więc ograniczenie idzie do dokumentacji.
- **Klucze w pamięci to ETS procesu kluczy, źródłem jest tabela**: restart procesu bez EHOS-a wczytuje tabelę
  (to, czego brakuje `joken_jwks`, D-34). Nie `:persistent_term` — podmiana co 5 min to globalne GC.
- **`exp` względem `EhOsContract.Clock.now()`**, nie zegara Jokena — test wygasłego credentiala ustawia zegar
  przez `Clock.at/2`. Interwały procesu kluczy (5 min, 30 s) liczone zegarem monotonicznym wstrzykiwanym w
  testach.
- **Pobieranie przez Req**, w testach `Req.Test`; kryptografia Joken/JOSE, bez `joken_jwks`.

**EA1 zrobione 27 września** na `dsl-v2/ea-verify` (`5d35927`..`8c28221`), zmergowane jako
[PR #19](https://github.com/EmpoweredHouse/eh-os-contract/pull/19) (`737428f`) — „EA1 — co wyszło” niżej.
**EA2 zrobione 27 września** na `dsl-v2/ea-authorize` (`a8dd701`..`a54369b`), zmergowane jako
[PR #20](https://github.com/EmpoweredHouse/eh-os-contract/pull/20) (`a2a056b`, do gałęzi EA1) — „EA2 — co wyszło”.
Odbiór EA spełniony w całości (mapa w „EA2 — co wyszło”).

**E7 — Runtime asynchroniczny, fikstury, zgodność.** Efekty (Oban, joby tylko z identyfikatorami),
uporządkowane subskrypcje, process managery i timery, przebudowa, `_event_runs` (D7), nowe źródła zgodności:
w toku, padające, pokrycie scenariuszy (v2 §12–13). Wersja okablowania liczona z kontraktu i implementacji —
zmienia werdykt, więc linia w CHANGELOG. Fikstury przebudowane według tabeli niżej. Poprawki ADR: §9–10, §15,
wyzwalacz „jedno zdarzenie w dwóch procesach”.
*Odbiór:* te same scenariusze dają te same liczby werdyktów (np. „50 przebiegów → jedna linia raportu” z
`report_test`); „jeszcze nie” przechodzi w „nigdy” dopiero po opróżnieniu kolejki; przebudowa daje identyczne
wiersze; trujące zdarzenie zatrzymuje konsumenta dokładnie na swojej pozycji; dwóch runnerów nie bierze tej
samej paczki (prawdziwe commity, osobny schemat); odpalony timer uruchomiony dwa razy daje jeden dispatch.
**E7a zrobione 26 września** i zmergowane jako PR #14 (`83befa9`); jego trzy punkty odbioru spełnione — „E7a — co
wyszło” niżej. **E7b zrobione 26 września** i zmergowane jako PR #15 (`3e612f0`) — „E7b — co wyszło” niżej. **E7c-1
zrobione 26 września**, wystawione jako [PR #16](https://github.com/EmpoweredHouse/eh-os-contract/pull/16) — „E7c-1 —
co wyszło” niżej. **E7c-2 zrobione 26 września** na `dsl-v2/e7c2-outputs`, niewypchnięte — „E7c-2 — co wyszło”. **Podzielony na trzy PR-y** (decyzja użytkownika z 26 września, jak E5a/E5b — żeby diff dało się przeczytać),
każdy na gałęzi od poprzedniego:
- **E7a — runtime asynchroniczny** (`dsl-v2/e7-async`): migracja V04; efekty na Obanie; uporządkowane
  subskrypcje dla read modeli i polityk `:at_least_once`; supervisor; przebudowa read modeli; testy trującego
  zdarzenia i dwóch runnerów na `CommitRepo`; znalezisko 5 z przeglądu E6. Odbiór: przebudowa daje identyczne
  wiersze; trujące zdarzenie zatrzymuje konsumenta dokładnie na swojej pozycji; dwóch runnerów nie bierze tej
  samej paczki.
- **E7b — process managery i timery**: krok jako jedna transakcja, `TimerJob` i `eh_os_contract.timer_elapsed`,
  replay bez reakcji, `correlate` z ustalenia 4 E5b. Odbiór: odpalony timer uruchomiony dwa razy daje jeden
  dispatch.
  Rozstrzygnięte przez użytkownika 26 września przed budową E7b: **test przesuwa czas zegarem** —
  `EhOsContract.Testing.drain/1` odpala tylko timery należne według `EhOsContract.Clock.now()`, a test ustawia
  zegar istniejącym `Clock.at/2`, więc widzi też „za wcześnie”. Na produkcji timer odpala Oban o swojej porze.
  Zgoda na commity bez pytania i zapis stanu obejmuje gałąź `dsl-v2/e7b-process-managers` (od `main` po PR #14).
- **E7c — zgodność na nowym logu i fikstury**: `_event_runs` z czytelnikami (`Trace`, `Run`), kontrakty v2 w
  raporcie, grafie i `check`, w toku i padające z nowych źródeł, pokrycie scenariuszy, wersja okablowania z
  linią w CHANGELOG, `conformance.v2`, fikstury według „Losów fikstur”, webowy `CaseHandling`, poprawki ADR.
  Odbiór: te same scenariusze dają te same liczby werdyktów; „jeszcze nie” przechodzi w „nigdy” dopiero po
  opróżnieniu kolejki.
  Rozstrzygnięte przez użytkownika 26 września przed budową E7c:
  - **Dwa PR-y**, drugi na gałęzi od pierwszego. **E7c-1 — werdykty** (`dsl-v2/e7c-conformance`): `_event_runs`,
    `Trace`, `Run`, `Conformance` i `Report` na kontraktach v2, w toku i padające z nowych źródeł,
    `conformance.v2`, fikstury `ProcessShapes` przebudowane (odbiór „te same liczby werdyktów” stoi na nich),
    start nowej polityki. **E7c-2 — wyjścia**: graf v2, `check` na v2, pokrycie scenariuszy, wersja okablowania,
    webowy `CaseHandling`, poprawki ADR, `min_position` przy query, pierwszy przebieg sandboxa w dev.
  - **`conformance.v2` tylko dla kontraktów v2**; kontrakt v1 zostaje przy `conformance.v1` z identycznymi
    bajtami do cięcia. Krok v2 to `from` / `via` / `to`, każde `{kind, name, label}` (komenda → zdarzenie albo
    zdarzenie → konsument → komenda), z `mode`, `runs` i `of_runs`. **W toku i padające rozbite na źródła**, bo
    każde idzie do innej osoby: `in_flight` = `{effects, timers, lag}`, `failing` = `{commands, subscription,
    effects}`. Nowe sekcje `scenarios` (zadeklarowane, zaobserwowane, nigdy niezaobserwowane, wyniki bez
    scenariusza) i `wiring` (wersja, od kiedy) — obie w E7c-2. Zdania raportu nazywają źródło: „in progress: 2
    timers scheduled”, „failing: 1 command failed in 1 run”, „failing: the subscription stopped at an event it
    cannot apply”; krok przez konsumenta mówi „(via: <etykieta konsumenta>)”.
  - **Graf v2 ma węzły wszystkich rodzajów** — komendy, zdarzenia, konsumenci (polityka, process manager,
    efekt), timery — w kolorach Event Stormingu, krawędzie `emits` / `issues` z licznikami przebiegów z
    nakładki (jak EventCatalog). Wariant „tylko zdarzenia, jak w v1” odrzucony: komenda od człowieka nie ma
    zdarzenia wejściowego, więc by zniknęła.
  - **Nowa polityka `:at_least_once` startuje jak nowy process manager**: bez reakcji na historię. Polityka nie
    ma stanu, więc replay bez reakcji to start od głowy logu w chwili rejestracji; przejście historii z
    reakcjami to świadome `--reset NAZWA`. Zamyka znalezisko 1 z przeglądu E7b. Linia w CHANGELOG.
  Zgoda na commity bez pytania i zapis stanu obejmuje `dsl-v2/e7c-conformance` i gałąź E7c-2.

Interfejs widoczny dla hosta, rozstrzygnięty przez użytkownika 26 września przed budową E7a:
- runnery wyłącza `config :eh_os_contract, subscriptions: :manual` (obok `:repo` i `:applications`), nie opcja
  dziecka;
- jeden pomocnik testów, `EhOsContract.Testing.drain/1`: dogania każdą subskrypcję do głowy logu i wykonuje
  joby efektów (w E7b także timerów), aż nic nie zostanie; `only:` zawęża do nazw konsumentów;
- jeden task, `mix eh_os_contract.subscriptions`: stan każdej subskrypcji, `--skip NAZWA` za trujące zdarzenie,
  `--reset NAZWA` przebudowa od zera — biblioteka sama nigdy nie pomija (v2 §12);
- read model czyści swoje wiersze opcjonalnym callbackiem `reset/0 :: :ok`; bez niego przebudowa odmawia, a
  subskrypcja zostaje `stale`, widoczna w tasku.

**E8 — Crypto-shredding.** `subject` w domenie, `personal:`/`subject:` na polach, tabele kluczy i usunięć,
`Vault`, szyfrowanie w `Codec`, `erase/3`, `forget/2`, bramki (v2 §14). Przed TaxVision, bo
`registry_discrepancy_detected.diff` ma dziś `retain: :hash`. Poprawka ADR: retencja w §7–8.
Od EA (27 września, przegląd bezpieczeństwa): **bramka „pole osobowe nie może być `scope` query”** — wartość
`scope` trafia do `eh_os_contract_auth_decisions` pakietu auth, poza crypto-shreddingiem; v2 §14 wymienia klucze,
tagi, korelację, `identity`, stan PM i pola publiczne, a `scope` nie.
*Odbiór:* w `payload` nie ma jawnego tekstu pól osobowych; po usunięciu odczyt daje `Erased`, snapshoty z tą
osobą znikają, `forget/2` się wykonało; `Conformance.as_data` identyczne przed i po (poza `generated_at`);
bramki odrzucają pola osobowe w kluczach; kontrola: osoba nieusunięta czyta się normalnie.

Rozstrzygnięte przez użytkownika 27 września przed budową E8. Przy każdej decyzji są też odrzucone opcje, żeby
dało się do nich wrócić bez odtwarzania rozmowy (prośba użytkownika):
- **Dwa PR-y, drugi na gałęzi od pierwszego.** **E8a — zapis i odczyt** (`dsl-v2/e8a-encryption`): migracja V05
  (tabele kluczy i usunięć), `Vault`, szyfrowanie w `Codec`, `Erased` przy odczycie, bramki. **E8b — usuwanie**:
  `erase/3`, odmowa dopisu dla usuniętej osoby, `eh_os_contract.subject_erased`, `forget/2`, test złoty zgodności,
  dokumenty, poprawka ADR (retencja §7–8). *Odrzucone:* jeden PR (mniej ceremonii, diff za duży na uważne
  czytanie); trzy PR-y (bramki i V05 / szyfrowanie / usuwanie — najmniejsze diffy, najwięcej scalania).
- **`erase/3`: uprawnienia pilnuje host, wywołanie jest idempotentne.**
  `EhOsContract.erase(:patient, "p-17", actor: actor)` zwraca `:ok`, także gdy osoba jest już usunięta, i wtedy
  nie dopisuje drugiego zdarzenia. Aktor trafia do `erasures.requested_by` i do zdarzenia. Silnik nie pyta
  `Authorizer`: kto może usuwać, rozstrzyga host, tak jak dostęp do dashboardu (`Web.Resolver`). *Odrzucone:*
  (a) **przez `Authorizer`**, uprawnienie `eh_os_contract.erase` w credentialu od EHOS-a — spójne z D14, ale to
  uprawnienie spoza kontraktu, więc musiałoby wejść do manifestu (E10) i do listy uprawnień w `Model.capabilities/1`;
  **naturalny moment na zmianę zdania to E10**, a zmiana dla hosta to tylko inny `actor:`. (b) **drugie usunięcie jako
  błąd** `{:error, :already_erased}` — mówi więcej, ale każdy host ponawiający żądanie RODO musiałby ten błąd
  połykać.
  *Zmienione 27 września po przeglądzie E8b (decyzja użytkownika):* wynik mówi, co `erase/3` zastał —
  `{:ok, :erased}`, `{:ok, :no_data}` (dla tego identyfikatora nie było danych osobowych; usunięcie i tak jest
  zapisane) albo `{:ok, :already_erased}`. Powód: przy samym `:ok` literówka w identyfikatorze („P-17” zamiast
  „p-17”) wyglądała jak usunięcie, a dane prawdziwej osoby zostawały czytelne. Dalej nigdy `{:error, _}`. *Odrzucone:*
  zostawić `:ok` (literówki nie da się wykryć); `{:error, :no_data}` bez zapisu (osoba, o której jeszcze nic nie
  zapisano, nie byłaby zablokowana na przyszłość).
- **`Vault`: lista KEK w konfiguracji, z rotacją.**
  `config :eh_os_contract, EhOsContract.Vault, keys: [{"2026-09", kek}, {"2026-03", stary}]`. Pierwszy klucz jest
  bieżący, pozostałe tylko rozpakowują. `mix eh_os_contract.rewrap` przepakowuje klucze osobowe bieżącym. Własny
  adapter (KMS) podpina się przez `config :eh_os_contract, vault: Modul`. Start pada, gdy zarejestrowany kontrakt
  ma pola osobowe, a KEK nie ma. *Odrzucone:* (a) **jeden KEK bez rotacji** — prostsza konfiguracja, ale wymiana
  klucza głównego oznaczałaby migrację, której nikt nie napisał; (b) **tylko behaviour**, bez domyślnego adaptera —
  nie ma czego źle skonfigurować, ale każdy host musi na start napisać własny, także w teście.
- **Snapshoty i rotacja klucza osoby poza E8.** Tabeli snapshotów w magazynie nie ma (v2 §10.3 ją opisuje, V03 i
  V04 jej nie tworzą), więc punkt odbioru „snapshoty z tą osobą znikają” **wypada** z E8. Kto zbuduje snapshoty,
  ten dokłada kolumnę `subjects` i kasowanie w `erase`. Kolumna `key_version` jest od V05, zawsze 1; rotacja klucza
  danych osoby (nowe zdarzenia pod nowym kluczem) czeka na użytkownika. *Odrzucone:* zbudować snapshoty w E8
  (spory dodatek, który nie jest crypto-shreddingiem); dodać rotację `key_version` w E8b.
- **Kształty wzięte przez asystenta domyślnie**, bo przesądza je v2 §14 (wymienione użytkownikowi przed budową):
  `personal:`/`subject:` bez zmian od E3–E4, dochodzą tylko bramki; w polu osobowym usuniętej osoby jest
  `%EhOsContract.Erased{subject: :patient, id: "p-17"}`, a typy generowane go dopuszczają;
  `forget(subject_type, subject_id) :: :ok` to opcjonalny callback read modelu, a read model konsumujący pole
  osobowe bez niego nie startuje; dispatch dotykający usuniętej osoby to odmowa `{:error, :subject_erased}`; klucza
  osoby nigdzie nie trzymamy w pamięci podręcznej.
Zgoda na commity bez pytania i zapis stanu obejmuje gałęzie `dsl-v2/e8…`.
**E8a zrobione 27 września** na `dsl-v2/e8a-encryption`, niewypchnięte, po przeglądzie przed PR — „E8a — co
wyszło” niżej. **E8b zrobione 27 września** na `dsl-v2/e8b-erasure` (od E8a) — „E8b — co wyszło”. Wystawione jako PR #21 (E8a) i
PR #22 (E8b, do gałęzi E8a).
Odbiór E8 spełniony (mapa w „E8b — co wyszło”), poza snapshotami, które wypadły decyzją użytkownika.

**E9 — Pozostałe kontrakty sandboxa.** *Nieaktualne w tym brzmieniu od 27 września* (port 1:1 zastąpiony
kontraktami od nowa z materiału — „Po E8 — kolejność zmieniona” i „Przed E9 — decyzje użytkownika”); obowiązuje
tylko odbiór na końcu akapitu. Kolejność i zakres, jak stały:
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

**E10 — Wyjścia. Zrobione lokalnie 28 września** („E10 — co wyszło”; manifest ujawnił zmianę potrzebną w
fixture `eh-os`). Ostrzeżenia L5 (v2 §6) przypięte testem na wyjściu sandboxa; graf systemu (domena →
konteksty → kontrakty, krawędzie `consumes`) w `mix eh_os_contract.graph` i na `/graph`; `Model.to_data/1` z
nazwanym schematem dla EHOS-a, z uprawnieniami, i endpoint w API pakietu web; AsyncAPI z deklaracji `publish` (D11)
i OpenAPI z komend i query modelu (D10). W pakiecie auth (D14) task manifestu dla EHOS-a: `ehos.manifest/v1`
(`eh-os` `docs/manifest.md`) jako projekcja modelu i domeny — tylko pola schematu EHOS-a, bo każde inne jest
odrzucane; aktor bez żadnego uprawnienia i aktorzy `:system` nie są rolami — potem v2 według `eh-os` D-40/D-41.
*Odbiór manifestu:* dla TaxVision po E9 równy fixture'owi `eh-os` `test/support/fixtures/manifests/taxvision.json`
(rola `taxvision.accountant`, „Księgowa”); jeśli task dopisuje `engine` i `contracts`, digest odchodzi od
przypiętego w EHOS i porównanie je pomija — rozstrzygnięte przy tym etapie.

*Korekta 29 września po pre-PR review:* publiczny model zachowuje strukturę scenariuszy i przykładów, ale
wartości pól `personal:` (także zagnieżdżonych w value) wystawia jako `null`; nie jest magazynem danych
fixture. Digest dokumentów E10 dostał osobne, długościowane kodowanie — historyczny hash wersji kontraktu nie
zmienia się. OpenAPI opisuje listy query jako powtórzone klucze `form`/`explode`, obiekty jako `deepObject`,
odpowiedź 400 i nullable po erasure; Plug zachowuje powtórzone klucze. Komponent wiadomości AsyncAPI nazywa
dokładne, wersjonowane `publish as:`, bez nieiniektywnej normalizacji. Task manifestu odmawia wyboru, gdy dwa
moduły domen mają tę samą publiczną nazwę.

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
**Publiczne wejście dla surowych danych — w E12** (decyzja użytkownika z 27 września; uwaga 4 z przeglądu EA2).
Jedno wejście silnika: autoryzacja → dekodowanie → dispatch albo query. Na nie przechodzi `EhOsContract.Plug`, a
`Dispatcher.permit_undecoded/5` (`@doc false`) znika. Powód terminu: dziś są jedne drzwi (Plug), a drugie powstają
dopiero tutaj — inbox zamienia przychodzące wiadomości w komendy, czyli też przyjmuje surowe dane. *Odrzucone:*
(a) **teraz**, małym PR-em przed E8 — nowe publiczne API, zanim pojawi się drugi użytkownik, więc kształt byłby
zgadywany z jednego przypadku; (b) **wcale** — każde przyszłe wejście (LiveView, job z credentialem) musiałoby samo
pamiętać o kolejności „najpierw uprawnienie, potem pola”. Jeśli drugie drzwi pojawią się przed E12, wejście wchodzi
razem z nimi.

**E13 — Graf jako API i osobny renderer, w miejsce Mermaida.** Pomysł użytkownika z 28 września, **bez miejsca w
kolejności**. To jest ponowne rozważenie, które EG odłożyło („interaktywny `/graph` z JSON-a (…) jak EventCatalog —
do ponownego rozważenia, gdy grafy będą miały treść po E9”, „Przed EG — decyzje użytkownika”); po E9a Rehmed ma
cztery kontrakty v2, więc widok systemu ma już krawędzie. Cel: cztery grafy EG (pełny graf kontraktu, jednostka,
mapa kontekstów, system) wyglądające jak w EventCatalogu (v2 §3, pkt 6), oglądane i lokalnie przy developmencie, i
w EHOS Console (LiveView), która uruchamia aplikacje klienckie. Użytkownikowi na Mermaidzie nie zależy.
Rozstrzygnięte przez użytkownika 28 września:
- **Silnik wystawia graf tak, jak wystawia AsyncAPI** (`EhOsContract.AsyncAPI.document/1` i `index/0`, endpoint z
  digestem w `ETag`, za tym samym `Resolver`): opublikowany format `eh_os_contract.graph.v1` z **JSON Schemą w
  pakiecie** (`priv/schema/graph.v1.json`) i testem walidującym każdy wygenerowany dokument. W webie `GET
  <mount>/graph` (indeks: domeny z mapą kontekstów i systemem) i `GET <mount>/graph/:contract` (pełny graf
  kontraktu z jego jednostkami); dokładne ścieżki — przy budowie. **Krawędzie wyprowadza silnik, nie renderer**:
  zgodność liczy przejścia niezadeklarowane na tym samym grafie statycznym, więc reguła „polityka konsumuje
  zdarzenie i wydaje komendę” żyje w jednym miejscu. Renderer zna słownik rodzajów węzłów i relacji, nie semantykę.
- **Dwa dokumenty**: statyczny opis (ten sam kontrakt → te same bajty, bez bazy, do wygenerowania w CI i
  przypięcia digestem) i nakładka z logu, `GET <mount>/graph/:contract/overlay?since=…` (oraz odpowiednik dla
  systemu domeny) — liczniki przebiegów, to, co czeka i pada, ścieżki nigdy nieprzejechane, kluczowane tymi samymi
  `id` węzłów i krawędzi; renderer nakłada jedno na drugie. *Odrzucone:* jeden dokument z `?overlay=true` —
  prostszy dla konsumenta, ale przestaje być opisem kontraktu, a jego digest przestaje cokolwiek znaczyć.
- **Renderer to nowy pakiet w tym repozytorium**, `packages/eh_os_contract_graph`: komponent funkcyjny Phoenixa i
  hook LiveView (kontener z `phx-update="ignore"`, jak bloki diagramów po EG3), bundle JS zbudowany esbuildem i
  commitowany w `priv/static` (wzorzec `assets.build` z `eh_os_contract_web`), więc host nie instaluje npm. **Nie
  zależy od `eh_os_contract`**, tylko od `phoenix_live_view` — przyjmuje dokument, niezależnie skąd przyszedł: w
  dashboardzie z wywołania funkcji, w Console z API aplikacji klienta. Tokeny design systemu EmpoweredHouse
  (dopisek z 28 września) i paleta rodzajów w jednej tabeli, bo paleta Event Stormingu „w niedalekiej przyszłości
  będzie zmieniana”. Brama wywołuje jego `mix check` jak pozostałych pakietów. *Odrzucone:* osobne repozytorium
  (użytkownik: pakiet tutaj); web component — obaj konsumenci są na LiveView, więc niepotrzebny; renderer
  wyprowadzający graf sam z `Model.to_data/1` — dwie implementacje reguł krawędzi w dwóch językach.
- **Mermaid wypada w całości**: `Graph.Mermaid` i `to_mermaid` w `Graph.Contract`, `Graph.Unit`,
  `Graph.ContextMap`, `Graph.System` i `Graph` (dane pod nimi — `build/*`, `Paths`, `overlay/1`, liczniki —
  zostają, bo z nich powstaje dokument); w webie zwendorowany `mermaid.min.js` (3,5MB), `NOTICE`, hook z kolejką
  rysowania, obejście CSP z EG3 (arkusze konstruowane, przenoszenie `style`), motyw Mermaida z tokenów, reset
  `pre.mermaid p` i zdanie w README o `style-src`; flagi Mermaida w `mix eh_os_contract.graph` — task wypisuje
  dokument JSON; asercje Mermaida w testach silnika, weba i sandboxa. Porównania bajtów na bazie dev robione dotąd
  na Mermaidzie przechodzą na dokument JSON. Grafy v1 EG zostawiło „bez zmiany bajtu do wycięcia v1”, więc albo
  E13 idzie po E11, albo ich Mermaid znika dopiero w E11 — do rozstrzygnięcia z kolejnością.
- **`Brief` przenosi się na ekran** z nowym rendererem i przestaje być wydawany jako plik:
  `mix eh_os_contract.brief` znika, a strona dashboardu pokazuje graf procesu obok listy (zdarzenia słowami
  klienta, obietnice zdaniami, co od każdego zdarzenia zależy) — obie połowy, bo moduledoc `Brief` zapisuje, że
  łapią różne błędy. Mieści się w decyzji po EG3: ekran jest miejscem, w którym ludzie oglądają model; na cztery
  pytania z `CLAUDE.md` odpowiadają nakładki, a opis stoi obok nich. *Odrzucone:* (a) mały serializer dokumentu do
  Mermaida tylko dla `Brief` — trzymałby Mermaida w silniku dla jednego czytelnika; (c) `Brief` bez rysunku — gubi
  połowę, która znalazła brakujące zależności kolejności.
- **Renderer — do rozstrzygnięcia prototypem**, nie z góry. Kandydat pierwszy: `@eventcatalog/visualiser` (npm,
  MIT, 4.1.4 z 7 września, React + `@xyflow/react` + dagre; `NodeGraph` przyjmuje ogólny `DslGraph`, rysuje karty
  EventCatalogu). Przeciw niemu: grafy EG mają 16 rodzajów węzłów, a `DslGraph` pokrywa kilka (komenda, zdarzenie,
  query, aktor, system zewnętrzny) — polityka, process manager, efekt, timer, read model, stan, niezmiennik,
  ograniczenie, kontekst, kontrakt i publikacja tylko przez surowe węzły React Flow typu `custom`; nakładka mieści
  się jedynie w `label` krawędzi; `NodeGraph` importuje statycznie `MermaidView` (Mermaid jest jego zależnością —
  3,5MB może wrócić do bundla); własny build Tailwinda może gryźć się z CSS hosta; format `DslGraph` jest ich
  wewnętrzny. Wyjście awaryjne: `@xyflow/react` z dagre albo ELK i własne karty. Mapowanie `graph.v1` → format
  renderera żyje w pakiecie renderera, więc zmiana renderera nie dotyka silnika ani EHOS-a. **Warunek dla obu:
  działa pod `default-src 'self'` EHOS-a** — sandbox serwuje tę politykę na dashboardzie na stałe (EG3), więc
  prototyp sprawdza ją sam. React ustawia style przez CSSOM, który polityka przepuszcza; do sprawdzenia, czy nic w
  bundlu nie wstawia `<style>`. Przy okazji znika ~400 zablokowanych stylów z pomiaru Mermaida, czyli pytanie do
  EHOS-a z EG3. *Odrzucone:* Mermaid (bez interakcji, stały wygląd, walka z CSP), Cytoscape.js (węzły na
  canvasie, karty tylko przez rozszerzenia do etykiet HTML), SVG liczony w Elixirze (bez interakcji), DOT (odrzucony
  już w EG).

**Co w silniku jest, a czego brakuje.** Grafy EG są „najpierw dane”: `Graph.Contract.build/2`, `Graph.Unit.build/2`,
`Graph.ContextMap.build/1` i `Graph.System.build/3` dają węzły, krawędzie i grupy. Do formatu publicznego brakuje
trzech rzeczy: typy siedzą w `Graph.Mermaid` (do neutralnego modułu); krawędź niesie wygląd (`line`, `head`) zamiast
rodzaju relacji (`emits`, `issues`, `records`, `reads`, `calls`, `backed_by`, `gives`, `consumes`, …) — wygląd
wybiera renderer; nakładka jest dziś wpisana w etykiety krawędzi i w `counts` węzłów tego samego grafu, a ma być
osobnym dokumentem liczb. Identyfikatory są dziś mermaidowe (`<rodzaj>_<nazwa>`, `unique_ids/2` z numerem
kolejnym) i muszą stać się stabilne między wersjami, bo po nich łączy się nakładkę i liczy digest.

Kolejność pracy i szacunek (zgrubny, sprzed prototypu): (0) prototyp renderera na pełnym grafie jednego kontraktu
Rehmedu w `sandbox/` — ½–1 dnia, rozstrzyga renderer, mierzy bundel i sprawdza CSP; (1) format: neutralne typy,
rodzaje relacji, stabilne identyfikatory, nakładka jako liczby, schema — 2–3 dni; (2) endpointy i task z JSON-em —
~1 dnia; (3) pakiet renderera: 16 rodzajów, grupy (jednostka, subdomena, kontekst), karta stanu — 3–4 dni z
visualiserem, 4–6 z własnymi kartami; (4) web: `/graph` na nowym komponencie, usunięcie Mermaida i obejścia CSP —
1–1½ dnia; (5) `Brief` na ekranie — 1–1½ dnia. Razem ~9–12 dni z visualiserem, ~10–14 z własnymi kartami.
Integracja w Console jest po stronie `eh-os`. Jeśli E13 wejdzie przed E10, zabiera z E10 graf systemu na `/graph`
(zbudowany już w EG2) i endpoint grafu.

Otwarte: **strony modelu** (`mix eh_os_contract.pages`, EL3) wstawiają Mermaida do `index.md` domeny (mapa
kontekstów) i na strony agregatów (jednostka). Decyzja o `Brief` ich nie obejmuje: albo strony idą na ekran jak
`Brief`, albo zostają plikami bez rysunku, albo zostaje dla nich Mermaid — decyzja użytkownika przed budową.
Przy E13 poprawka z datą w `docs/adr/technology-notes.md` §12 (renderer zbudowany) i v2 §3.
*Odbiór:* dokumenty i nakładki przechodzą walidację JSON Schemą dla każdego kontraktu i domeny sandboxa; ten sam
kontrakt daje ten sam digest przed i po restarcie; ta sama strona renderuje się w dashboardzie z dokumentu z
funkcji i z dokumentu pobranego przez HTTP z `/graph/:contract`; ścieżka zadeklarowana, nigdy nieprzejechana, jest
na grafie odróżnialna od przejechanej; ekran grafu pod polityką EHOS-a bez żadnego naruszenia CSP w konsoli;
`grep -ri mermaid packages sandbox` (poza `CHANGELOG.md`) nic nie znajduje; kontrola: kontrakt spoza rejestru daje
404, nie pusty graf.

### Po E8 — kolejność zmieniona: najpierw luki ESDM, kontrakty na końcu (27 września)

Przed budową E9 asystent zapytał o podział na PR-y i o kształt portów. Użytkownik odwrócił kolejność i rozstrzygnął
zakres. Decyzje razem z odrzuconymi opcjami:

- **Celem jest funkcjonalność ESDM, a kontrakty sandboxa są danymi testowymi.** „Nie zależy mi na tym, żeby naprawić
  kontrakty TaxVision/Rehmed, mogą być wygenerowane od nowa.” Zasada ze „Strategii” „porty tłumaczą, nie naprawiają”
  **przestaje obowiązywać dla kontraktów sandboxa**: powstają od nowa z materiału (konteksty, agregaty, polityki,
  read modele tak, jak nazywa je materiał), a v1 nie jest ani wzorcem, ani listą kontrolną. Zostają reguły z
  `CLAUDE.md`, w tym nazwy zdarzeń z warsztatu. Dziesięć usterek z dopisku 25 września przestaje być pytaniami,
  które port musi nieść; kontrakt od nowa rozstrzyga je materiałem albo sam. *Odrzucone:* (a) tłumaczenie 1:1,
  jeden kontrakt v1 → jeden v2 (mniej pracy, ale wychodzi v1 w nowej składni, bez kontekstów i z publikacją przez
  handlery); (b) model po ESDM-owemu z v1 jako listą kontrolną (propozycja asystenta; zbędna, skoro kontrakty są
  danymi testowymi).
- **Kolejność: analiza pokrycia ESDM → uzupełnienie luk → grafy → kontrakty.** „Lepiej się zastanowić, czy mamy
  pokrytą funkcjonalność ESDM na ten moment, przeanalizuj, czego nie ma, uzupełnijmy grafy, a na końcu zajmijmy się
  istniejącymi kontraktami.” Dawne E9 przesuwa się za nowe etapy EM i EG (niżej). *Odrzucone:* E9 teraz, a luki i
  grafy w E10 (tak stał plan: kontrakty sandboxa powstałyby na DSL-u, któremu brakuje rodzajów, i trzeba by je
  przepisywać drugi raz).
- **Luki modelu — wszystkie cztery grupy** (wybór użytkownika z listy): runtime DCB; `entity` i `domain_service`;
  `constraints` i inwarianty value objectu; drobne pola ESDM (tożsamość generowana, timery kalendarzowe, relacja do
  systemu zewnętrznego, tłumaczenie z definicją i `avoid`, nazwana subdomena). *Odrzucone:* nic z listy.
- **Grafy — wszystkie cztery** (wybór użytkownika z listy): mapa kontekstów (domena → subdomeny → konteksty,
  relacje, systemy zewnętrzne); widok systemu (kontrakty i krawędzie `consumes`, z nakładką z logu); pełny graf
  kontraktu (dzisiejszy graf kroków plus read modele, query, aktorzy i systemy zewnętrzne); widok jednostki (stan,
  komendy, zdarzenia, inwarianty, scenariusze). *Odrzucone:* nic z listy.
- **Uprawnienie do `record/3` z credentialem: `<domena>.<zdarzenie>`** (np. `rehmed.visit_completed`), rodzaj
  `:record` w `Model.capabilities/1`, ta sama reguła unikalności co komendy i query; manifest EHOS-a pozna ten rodzaj
  w E10. Zamyka otwarte pytanie z handoffu. *Odrzucone:* `<domena>.record.<zdarzenie>` (od razu widać nagranie, ale
  nowy wzorzec nazwy dla EHOS-a); obserwacje ludzi jako komendy (nazwy komend, których materiał nie ma).
- **Reguła „miesiąc otwiera księgowa tej firmy”** — użytkownik bez preferencji, więc domyślna propozycja asystenta:
  **`scope` dla komend**, jak dla query (D10); zamyka pytanie z v2 §19. Wchodzi razem z kontraktem TaxVision.
  *Odrzucone:* przypisanie jako fakt sprawdzany w DCB (dispatch musiałby podawać deciderowi aktora — nowy kształt
  API); reguła poza kontraktem, w kodzie hosta przed dispatchem (wypada z kontraktu i scenariuszy).

**Analiza pokrycia ESDM (27 września).** Źródło: `thenativeweb/esdm` na `cf17780` (22 września), wydanie 0.15.0 z
17 września; schematy `core`, `given-when-then` i `domain-storytelling` bez zmian od wydania. ESDM ma 18 rodzajów w
rdzeniu, dwa rozszerzenia (`feature`, `domain-story`) i 73 reguły (47 rdzeń, 17 scenariusze, 9 domain storytelling).

| ESDM | U nas | Luka |
| --- | --- | --- |
| `domain`, `bounded-context`, słownik | ✅ | tłumaczenie ma tylko słowo; w ESDM także definicję i `avoid` |
| `subdomain` | ⚠️ typ na kontekście | nazwana subdomena grupująca konteksty |
| `context-mapping` (8 typów) | ✅ `relation` | końcem relacji asymetrycznej może być system zewnętrzny; `terms` to pary słów z obu stron |
| `aggregate` | ✅ | tożsamość generowana (`source: generated`) i stała (`static`) |
| `dynamic-consistency-boundary` | ⚠️ DSL i reguły | runtime: `{:dcb, …}` w magazynie, `read_query`, dispatch |
| `command` | ✅ | `constraints` — nazwane reguły prozą |
| `event-handler` | ✅ `effect` | opis skutku ubocznego prozą |
| `policy`, `event` | ✅ | — |
| `process-manager` | ✅ | timery kalendarzowe (miesiące, lata); `endsWhen` w ESDM to warunek prozą |
| `read-model`, `query` | ✅ | reguła projekcji i `constraints` query prozą |
| `value-object` | ✅ `value` | inwarianty |
| `actor`, `external-system` | ✅ | pola opisowe (`responsibilities`, `category`, `capabilities`) |
| `entity` | ❌ odłożone w v2 §4.2 | cały rodzaj |
| `domain-service` | ❌ | cały rodzaj |
| `feature` + scenariusze | ✅ agregat, DCB, process manager, query | grupowanie w `feature` (kosmetyka, poza zakresem) |
| `domain-story` | ❌ | poza zakresem: format odkrywania, sprzed modelu |

Reguły strukturalne i scenariuszy ESDM mamy prawie wszystkie, i jako błędy kompilacji (tam, gdzie ESDM ostrzega, np.
`uncovered-invariant`, u nas jest błąd S8). Brakuje około jedenastu **ostrzeżeń kompletności** (L5 z v2 §6, planowane
na E10): `event-without-consumer`, `read-model-without-query`, `aggregate-without-commands` i `-events`,
`bounded-context-without-content`, `orphan-actor`, `orphan-external-system`, `orphan-context-mapping`,
`cross-bounded-context-reference-without-mapping`, `event-name-with-aggregate-prefix`,
`process-manager-without-event-reactions`. ESDM ma też stałe identyfikatory reguł, stronę dokumentacji na każdą i
wyjście JSON; u nas numery N1…X9 żyją tylko w ADR. Narzędzia ESDM poza `lint`: `view` (drzewo domena → kontekst →
jednostka), `glossary` (słownik per kontekst i język), `documentation` (strona na element, z linkami) — u nas żadnego.
Diagramów oficjalne narzędzie nie rysuje; zewnętrzny ESDM Visualizer rysuje tablicę węzłów. Czego ESDM nie ma, a my
mamy: wykonywanie scenariuszy, obietnice, przebiegi i zgodność, crypto-shredding, wersję schematu zdarzenia.

**Etapy po tej decyzji** (propozycja asystenta; podział na PR-y i kształty widoczne dla hosta — pytania do
użytkownika przed budową):
- **EM — luki modelu ESDM.** Każdy rodzaj razem ze swoim czytelnikiem (reguła ze „Strategii”).
- **EL — ostrzeżenia kompletności i narzędzia** (wyciągnięte z E10): reguły L5 ze stałymi identyfikatorami, `view`,
  `glossary`, strony dokumentacji.
- **EG — grafy**, cztery z listy wyżej, w tasku `mix eh_os_contract.graph` i na `/graph`.
- **E9 — kontrakty sandboxa od nowa**, pokrywające każdy rodzaj; odbiór E9 zostaje.
- Dalej reszta E10 (eksport modelu, AsyncAPI, OpenAPI, manifest), E11, E12.

Rozstrzygnięte przez użytkownika 27 września przed budową EM:
- **Trzy PR-y, każdy na gałęzi od poprzedniego:** **EM1** — runtime DCB (warunek w magazynie, `read_query`,
  dispatch, scenariusze DCB wykonywane); **EM2** — `entity` i `domain_service` z czytelnikami; **EM3** —
  `constraints`, inwarianty value objectu i drobne pola ESDM. **Po skończonej implementacji każdej części zawsze
  przegląd** (`pre-pr-review`), zanim ruszy następna. *Odrzucone:* dwa PR-y (drugi diff za duży); cztery PR-y
  (`entity` i `domain_service` osobno — więcej scalania bez zysku na czytelności).
- **`domain_service` w kontrakcie, z implementacją.** Kontrakt generuje behaviour z `@callback` i typami,
  implementacja `use C, domain_service: :nazwa`, L4 wymaga każdej funkcji; decyzje wołają ją jak zwykły moduł;
  reguły prozą czytają dokumentacja i grafy. *Odrzucone:* sama deklaracja w domenie, bez wiązania z kodem (nic by
  nie sprawdzało, że funkcja istnieje — wbrew regule „rodzaj wchodzi razem z czytelnikiem”).
- **`entity` w domenie, z kontekstem właścicielem** (`context:`), obok `value` — decyzja po wyjaśnieniu na przykładach
  (okres TaxVision, usługa z cennika Rehmedu). Każdy kontrakt aplikacji może nazwać pole encją, więc model i graf
  pokazują, że `period_id` Zadań, Miesiąca i Powiadomień to ten sam okres; własność opisuje `context:`, jak
  `scope: bounded-context` w ESDM. Wierszy encji biblioteka nie przechowuje — trzyma je aplikacja. *Odrzucone:*
  `entity` w kontrakcie (inne kontrakty zostają z gołym `:id` i powiązanie znika z modelu).
- **Tożsamość generowana nadawana przez bibliotekę.** Komenda oznaczona jako tworząca nie niesie identyfikatora;
  dispatch go nadaje i zwraca w odpowiedzi, a ponowienie z tym samym kluczem idempotencji zwraca ten sam. Przykład z
  materiału: „Umów wizytę” (C-09 → E-14). *Odrzucone:* (b) nadaje aplikacja, a kontrakt tylko to zapisuje (deklaracja,
  której nic nie wymusza; przy ponowieniu z nowym identyfikatorem powstają dwa obiekty); (c) pominąć, bo żaden
  planowany kontrakt sandboxa tego nie potrzebuje (użytkownik wybrał pełne pokrycie ESDM).

### EM1 — co wyszło (27 września)

Na `dsl-v2/e9-em1-dcb` (od `main` z handoffem), niewypchnięte. Trzy commity budowy i trzy z przeglądu:
magazyn (`4f45b2a` — `read_query/2` i warunek `{:dcb, zapytanie, głowa}` w behaviourze, w Postgresie i w suicie),
tagi (`c3456a2`), dispatch komendy DCB i `record/3` zdarzenia DCB (`c6bf91b`), potem `3efffa7`, `36409b9`,
`24f672f`. Silnik 972 → 995 testów; `check` silnika 15 → 18 ostrzeżeń (trzy procesy nowej fikstury bez
`accountable`, jak w `DispatchRig`), sandbox bez zmian (0 / 5 / 19, 54 testy).

Mechanika, rozstrzygnięta przez asystenta i wyjaśniona użytkownikowi przed budową:
- **Tagami są wszystkie wymagane, nieosobowe pola `:id` zdarzenia**, nie tylko klucz jednostki: granica
  PayerSettlement szuka zdarzeń wizyty po płatniku i okresie, a klucz wizyty to `visit_id`. Tagowanie tylko pól,
  po których dziś ktoś szuka, zostawiłoby bez tagów zdarzenia sprzed nowej granicy. Nowa część A4: `match:`
  wskazuje tylko takie pola (X6 wymagał tego już od zdarzeń kontraktu siostrzanego). Jeden predykat,
  `EhOsContract.Key.tag_field?/1`, czytają i reguła, i dopis.
- **Granica czyta swoje własne zdarzenia pod całą tożsamością** oraz każde zdarzenie z `consults`; `consults`
  samym `where:` czyta wszystkie zdarzenia typu. Zdarzenia granicy nie mają strumienia.
- **Konflikt granicy ponawia się jak konflikt strumienia** (trzy próby), a w transakcji wywołującego wraca jako
  `{:error, :conflict}`.

Odbiór z opisu E9, ta jego część, która dotyczy DCB, spełniony na wymyślonej fiksturze `BoundaryRig` (zapisy na
kurs z limitem miejsc): **w wyścigu niezmiennik nigdy nie pęka** — dziesięciu rejestratorów na trzy miejsca daje
3 przyjęte i 7 odmów na prawdziwych commitach, a po zamianie warunku na `:none` test zapisuje dziesięciu;
**sprawdzenie konfliktu czyta tylko pozycje po głowie** — test Postgresa wyjaśnia przechwycone zapytanie i
znajduje indeks ograniczony pozycją (`(type, position)`; przy wyłączonych skanach sekwencyjnych, bo mała tabela
testowa ich nie potrzebuje). Scenariusze granicy (cztery) przechodzą przez `ScenarioCase`.

**Przegląd przed kolejną częścią** (dwa przeglądy równolegle na `origin/main..HEAD`; prośba użytkownika — po
każdej skończonej implementacji):
- **Poprawione, z testem i próbą odwrotną:** `given_types` w `_commands` rosło z historią (jeden wpis na każde
  przeczytane zdarzenie; granica czyta całą historię typu) → każdy typ raz (`3efffa7`); dekoder wybierany po
  zapisanej w wierszu nazwie kontraktu psuł dispatch po przemianowaniu modułu, także zwykłych agregatów → po
  typie zdarzenia (`36409b9`).
- **Poprawione bez nowego testu** (`24f672f`): wspólny predykat tagu zamiast dwóch kopii; komunikat odmowy
  pozycji zapytania; ograniczone ponowienia w teście na commitach; notka w ADR, że identyfikatory podmiotów są
  teraz w indeksie tagów, którego usunięcie nie dotyka — więc naturalny identyfikator (PESEL) nie może być `:id`.
- **Pominięte, do pomiaru** (obie recenzje): odczyt granicy nie ma limitu i odszyfrowuje każdy podmiot w
  zbiorze przy każdej próbie; `consults` samym `where:` konfliktuje z każdym nowym zdarzeniem typu, a trzy próby
  z jitterem 1–10 ms nie rozkładają ponowień przy długim odczycie, więc przy dużym ruchu na jedną granicę
  większość wywołań dostanie `:conflict`; więcej wpisów GIN przy każdym dopisie pod globalną blokadą;
  `record/3` na granicy czyta cały jej wynik, choć potrzebuje tylko głowy; `Model.declaring` liczone przy każdym
  dispatchu. Wraca to przy pomiarze albo przy pierwszej granicy, która tego potrzebuje (snapshoty granicy,
  jitter skalowany czasem odczytu, `fastupdate` indeksu).
- **Bez zmiany:** plan zapytania pod blokadą (test już wyjaśnia faktycznie wykonane zapytanie; ogólny plan
  przygotowanego zapytania mógłby wybrać inny indeks, co wraca przy pomiarze); zdarzenia dopisane przed tą
  wersją mają węższe tagi i nigdy ich nie dostaną — dopuszczalne, bo zgodności wstecz nie ma, a kontrakty
  sandboxa powstają od nowa, **ale to warunek dla każdej przyszłej bazy z historią**.
- Weryfikacja poza testami: brak — żaden kontrakt sandboxa nie ma jeszcze granicy, więc nie ma czego oglądać w
  `MIX_ENV=dev`.

Rozstrzygnięte przez użytkownika 27 września przed budową EM2:
- **Pole wskazujące encję: `field :period_id, {:id, :period}`.** W logu to dalej identyfikator (tag jak każde
  `:id`), a model wie, że wskazuje okres. *Odrzucone:* nazwa encji jako typ, `field :period_id, :period` (krócej,
  ale `field :period, :period` czyta się, jakby zdarzenie niosło cały okres).
- **`domain_service` pilnowany także w działaniu.** Kontrakt generuje moduł, przez który się woła
  (`C.DomainServices.RegistryComparison.differences(ours, theirs)`); sprawdza on argumenty i wynik względem
  deklaracji i rzuca przy niezgodności, jak dispatch przy niezadeklarowanym zdarzeniu. *Odrzucone:* samo
  sprawdzenie przy kompilacji, a decyzje wołają implementację wprost (deklaracja typów byłaby tylko opisem).

### EM2 — co wyszło (27 września)

Na `dsl-v2/e9-em2-entities` (od EM1), niewypchnięte. Dwa commity budowy — `e1f41d7` (encje), `febdd61` (serwisy
domenowe) — i pięć z przeglądu (`e414c4f`..`aa415a1`). Silnik 995 → 1021 testów; `check` bez zmian (sandbox
0 / 5 / 19, silnik 0 / 18 / 17).

Mechanika, rozstrzygnięta przez asystenta:
- **`{:id, encja}` normalizowane w budowie modelu** do `type: :id` z `refers_to:` — klucz tylko takich pól, więc
  żaden digest się nie rusza, a Codec, tagi i typespeki widzą zwykłe `:id`. Reguły L2 czytają deklaracje przed
  budową, więc tam `{:id, _}` obsługuje jeden strażnik, `Domain.Rules.is_id/1`.
- **Nowy rodzaj nie rusza wersji tego, kto go nie deklaruje**: pusta kolekcja `entities` w domenie i
  `domain_services` w kontrakcie nie wchodzi do skrótu. Sprawdzone na prawdziwych danych — `VisitSettlement` liczy
  się dalej na `2ae1d0074cbc`, jak zapisała baza dev 26 września — i przypięte testem na `DispatchRig.Ledger`.
- **Moduł `C.DomainServices.<Nazwa>` jest naraz behaviourem implementacji i modułem wywołań**; rozwiązanie
  implementacji i wartości domeny trzymane w `:persistent_term` na serwis, jak indeks implementacji.
- Reguły: D6 (encja), X3 (odwołania do encji, typ wyniku), N1/N2 (nazwy funkcji; `behaviour_info/1`,
  `module_info/0,1`, `__info__/1` zajęte), F1/F2 (argumenty i wynik), I2 z podpowiedzią nazw argumentów, I7.

**Przegląd** (dwa równolegle na `dsl-v2/e9-em1-dcb..HEAD`):
- **Poprawione, z testem i próbą odwrotną:** X3 nie sprawdzał `returns {:id, …}`, a D6 aliasu
  `value :ref, {:id, :nope}` (`e414c4f`); F5 odrzucał identyfikator encji jako identyfikator podmiotu (`d0de5c2`);
  pola encji bez sprawdzenia powtórzeń, `subject:` i danych osobowych wewnątrz wartości (`4b354c7`); N2 odrzucał
  funkcję `evolve` z powodem jednostki i przepuszczał `behaviour_info/1` i spółkę (`5e78363`); `call/4` przy złej
  liczbie argumentów albo nieznanym serwisie padał mylącym błędem (`aa415a1`).
- **Poprawione bez testu zachowania** (`aa415a1`): koszt każdego wywołania (indeks implementacji pytał kontroler
  aplikacji i kopiował listy modułów), parowanie specyfikacji po nazwie zamiast po pozycji, eksport
  `EhOsContract.DomainService` w `boundary`.
- **Do użytkownika:** funkcja serwisu nie może zwrócić `nil` (np. wyszukiwanie, które nic nie znajduje) — to
  kształt DSL-a, np. `returns :integer, optional: true`.
- **Bez zmiany:** naturalny identyfikator jako identyfikator encji jest tak samo jawny jak zwykłe `:id` — ADR już
  mówi, że PESEL nigdy nie jest `:id`.
- **Luka spoza EM2:** słownik DSL-a domeny nie ma testu przypinającego, jaki ma kontrakt
  (`contract_vocabulary_test`), więc `entity` weszło bez zmiany żadnego przypięcia.

Rozstrzygnięte przez użytkownika 27 września po EM2, przed EM3:
- **Wynik serwisu może być pusty, jeśli deklaracja tak mówi:** `returns {:id, :clinic}, optional: true`; bez tego
  `nil` dalej jest błędem. *Odrzucone:* zostawić (funkcja zawsze coś zwraca, a „nic” trzeba wyrazić innym typem).
- **EM3 obejmuje tylko to, co się wykonuje:** identyfikator nadawany przez bibliotekę, timery kalendarzowe i pusty
  wynik serwisu. **Pola opisowe — `constraints`, inwarianty wartości, tłumaczenia z definicją, nazwana subdomena,
  relacja do systemu zewnętrznego — wchodzą w EL i EG** razem ze stroną albo grafem, który je pokazuje (zasada
  „rodzaj wchodzi razem ze swoim czytelnikiem”). *Odrzucone:* wszystko w EM3 (pełne pokrycie ESDM etap wcześniej,
  ale deklaracje bez czytelnika przez jeden etap).
- **Timer „za miesiąc” liczony kalendarzowo:** `wait: {1, :month}` to ta sama data w następnym miesiącu (31 stycznia
  → koniec lutego), jak w ESDM; tylko w timerach, obietnice i `deadline` zostają w stałych jednostkach, bo raport
  liczy z nich czas. *Odrzucone:* bez miesięcy (`{30, :day}` — rozjazd z ESDM).
- **Zapis identyfikatora nadawanego przez bibliotekę:** `identity :booking_id, generated: :uuid` na agregacie i
  `creates: true` na komendzie tworzącej — tylko ona przychodzi bez identyfikatora, a dispatch zwraca nadany w
  `receipt.identity`. *Odrzucone:* samo `generated:`, gdzie każda komenda bez identyfikatora tworzy obiekt
  (zapomniany identyfikator w zwykłej komendzie po cichu tworzyłby nowy obiekt zamiast błędu).

### EM3 — co wyszło (27 września)

Na `dsl-v2/e9-em3-runtime` (od EM2), niewypchnięte. Budowa: pusty wynik serwisu (`b922c27`), poprawka biblioteki
znaleziona po drodze (`8ef1897` — process manager, który niczego nie wydaje, generował moduł bez callbacków, więc
`@behaviour` w implementacji ostrzegał i pod `--warnings-as-errors` host nie mógł jej skompilować), timery
kalendarzowe (`c2ad6f9`), identyfikator nadawany przez bibliotekę (`4d6ad1f`); z przeglądu `6ac44c5`..`c17bb50`.
Silnik 1021 → 1040 testów; `check` silnika 18 → 19 ostrzeżeń (proces `waitlist` fikstury bez `accountable`),
sandbox bez zmian (0 / 5 / 19, 54 testy).

Mechanika, rozstrzygnięta przez asystenta:
- **`returns` jest własną deklaracją** (`returns :typ, optional: true`), bo opcja Sparka przyjmuje jeden argument;
  funkcja bez `returns` się nie kompiluje (F2).
- **`identity :x, generated: :uuid` to makro biblioteki obok opcji Sparka**, rozwijane do `identity` i `generated`;
  eksportowane do formattera ręcznie (`own_locals_without_parens`), bo `mix spark.formatter` go nie widzi.
- **Nowe klucze nie wchodzą do modelu, kto ich nie używa** (`creates` tylko przy `true`, `generated` tylko ustawione),
  więc żadna wersja kontraktu się nie rusza.
- **Kalendarz timerów jest w UTC**, jak log; firma, która potrzebuje miesiąca swojej strefy, ustawia timer `at:`.
- **UUIDv7**, nie v4: lepsza lokalność w indeksie `stream_id`; zdradza czas utworzenia — zapisane w ADR.

**Przegląd** (dwa równolegle na `dsl-v2/e9-em2-entities..HEAD`):
- **Poprawione, z testem i próbą odwrotną:** duplikat odpowiedzi komendy, która nie zdecydowała zdarzeń, zwracał
  świeżo wygenerowany identyfikator (`6ac44c5`); A6 radził na DCB coś, co się nie kompiluje, a literówka w
  `identity :x, generate: :uuid` dawała `KeyError` z wnętrza biblioteki (`808f018`).
- **Poprawione bez testu** (`3b93c63`): `:generated` w dokumentacji dispatchera i Pluga, nieaktualny komunikat
  `Duration`, jedna lista jednostek kalendarzowych zamiast trzech, UTC i UUIDv7 opisane, nawiasy w fiksturze.
- **Rozstrzygnięte przez użytkownika** (kształty widoczne dla hosta), każde z testem:
  - **odpowiedź HTTP niesie `identity`** przy każdej komendzie (`e1ac877`); *odrzucone:* tylko przy komendzie
    tworzącej (kształt odpowiedzi zależny od komendy);
  - **komenda tworząca wymaga klucza idempotencji**, `{:error, :idempotency_key_required}`, 422 przez HTTP
    (`93205d7`); klucze reakcji są wyliczane, więc ich to nie dotyczy; *odrzucone:* klucz opcjonalny i opis
    (ponowienie po timeoucie tworzyłoby drugi obiekt, o którym host się nie dowie);
  - **`record/3` na agregacie z nadawanym identyfikatorem tylko do istniejącego**, `{:error, :not_created}`
    (`c17bb50`); *odrzucone:* zostawić i opisać (host mógłby założyć obiekt z wymyślonym identyfikatorem).
- **Pominięte:** ta sama jednostka wyszukiwana trzy razy na dispatch (koszt pomijalny).

**EM zamknięte**: trzy gałęzie EM1 → EM2 → EM3, każda od poprzedniej, gotowe na trzy PR-y. Push i PR — na
polecenie użytkownika. Dalej EL (ostrzeżenia kompletności, `view`, słownik, strony dokumentacji i pola opisowe
odłożone z EM3), EG (cztery grafy), potem kontrakty sandboxa od nowa (E9). Zmergowane jako PR #24–#26.

### Przed EL — decyzje użytkownika (27 września)

Punkt odniesienia: ESDM na `cf17780` (0.15.0), sprawdzone w kodzie. Reguła ma tam identyfikator
`esdm/<kategoria>/<nazwa>` i poziom na stałe (`error` albo `warning`, bez wyciszania); każda ma wpis z kotwicą na
jednej stronie reguł, generowany z opisu reguły; `esdm lint --format json` wypisuje tablicę z `ruleId`, `severity`,
`message`, `location`, `documentationUrl`; kod wyjścia 1 tylko przy błędach, `--warnings-as-errors` zmienia sam kod
wyjścia. `view` rysuje drzewo w terminalu, `glossary` wypisuje Markdown (sekcja na kontekst, `--language`),
`documentation --output <dir>` pisze Markdown, stronę na element, z linkami.

- **Trzy PR-y, każdy na gałęzi od poprzedniego, z przeglądem po każdej części:** **EL1** (`dsl-v2/el-warnings`) —
  ostrzeżenia L5 z identyfikatorami, `check` powtarzający L3, przypięcie słownika DSL-a domeny; **EL2** — pola
  opisowe razem z `glossary` i `view`, które je czytają; **EL3** — strony dokumentacji. *Odrzucone:* dwa PR-y
  (drugi diff za duży); cztery (`view` osobno — więcej scalania bez zysku na czytelności).
- **Identyfikatory: krótkie nazwy, tylko dla ostrzeżeń `check`.** `orphan-actor: actor :manager of Rehmed.Domain
  …` z linkiem do `docs/rules.md#orphan-actor`; nazwa z ESDM tam, gdzie reguła jest z ESDM, i własna w tym samym
  stylu dla reguł z v1 (`process-without-accountable`). Błędy kompilacji zostają przy `X2:`, `N1:`, jak dziś.
  Wymagało wyjaśnienia na przykładzie — pierwsze pytanie nie mówiło, po co regule stały identyfikator (zdanie się
  zmienia, identyfikator nie: wyszukiwanie, link do opisu, filtr w JSON-ie, przypięcie w teście). *Odrzucone:*
  (b) nazwy we wszystkich warstwach (`unknown-actor` zamiast `X2`; około 60 kodów, ich testy i odwołania w ADR);
  (c) pełne identyfikatory ESDM, `esdm/modeling/orphan-actor` (cudzy prefiks bez integracji, a nasze reguły spoza
  ESDM potrzebowałyby drugiego stylu).
- **Wyciszanie i wyjście maszynowe jak w ESDM:** bez wyciszania; `mix eh_os_contract.check --format json` i
  `--warnings-as-errors`, które zmienia tylko kod wyjścia. Ostrzeżenie znika przez poprawę modelu, nie
  konfiguracji. *Odrzucone:* wyciszanie w konfiguracji (`check: [ignore: […]]` — wyciszona reguła przestaje mówić
  całej aplikacji); wyciszanie przy deklaracji (nowe słowo DSL-a i powód w modelu).
- **Nazwana subdomena, na którą wskazuje kontekst:** `subdomain :visits, "Wizyty", type: :core` i `context
  :scheduling, …, subdomain: :visits`; typ przechodzi na subdomenę. Wchodzi w EL2. *Odrzucone:* subdomena wymienia
  swoje konteksty, jak w ESDM (kontekst bez `subdomain:`, inaczej niż `entity …, context:`); obie formy (dwa
  sposoby na to samo).
- **Kształty DSL-a pozostałych pól opisowych** (`constraints`, inwarianty wartości, tłumaczenie z definicją i
  `avoid`, relacja z systemem zewnętrznym) — pytania do użytkownika przed EL2.

Rozstrzygnięte przez asystenta: narzędzia to taski Mixa, nie ekrany dashboardu (`CLAUDE.md`: ekran ma cztery
pytania; grafy na `/graph` to osobna decyzja EG). Proza `constraints` i inwariantów wartości to zdania dla
właściciela procesu, więc lista miejsc „po polsku” w `CLAUDE.md` rośnie o nie w EL2.

### EL1 — co wyszło (27 września)

Na `dsl-v2/el-warnings` (od `main` = `081877d`), niewypchnięte. Sześć commitów budowy po zapisie decyzji
(`916595f`): katalog reguł i format wyjścia (`01070bf`), reguły domeny (`fa7463b`), reguły kontraktu (`09a5c01`),
reguły z v1 i `emits-never-produced` (`619cd04`), powtórzenie L3 (`6078d92`), przypięcie słownika domeny
(`41d2c6b`). Silnik 1040 → 1070 testów. Delta `check`: sandbox 0 / 5 / 19 → **0 / 12 / 19**, silnik 0 / 19 / 17 →
**0 / 50 / 20**; każda nowa linia wyjaśniona w opisie commita, który ją wprowadził.

- **Sandbox, siedem nowych ostrzeżeń, wszystkie o jedynym kontrakcie v2 i jego domenie:** `orphan-actor`
  (`:manager` w `Rehmed.Domain`), `bounded-context-without-content` (`:scheduling` — `ClinicalVisit` jest v1 i nie
  zna domeny), `orphan-context-mapping` (relacja `scheduling → settlement`, z tego samego powodu), cztery
  `event-without-consumer` na `VisitSettlement` (rozliczenia nikt jeszcze nie czyta; dwa zdarzenia zamykające są
  `terminal` — pierwsza wersja tego zdania i opis `09a5c01` mówiły „trzy”, poprawione 27 września). Zostają do E9, gdzie kontrakty powstają od nowa.
- **Silnik, 31 ostrzeżeń i 3 notki na wymyślonych fiksturach**, pisanych pod mechanizm, nie pod kompletność:
  14 `event-name-with-aggregate-prefix`, 10 `event-without-consumer`, 3 `read-model-without-query`, po jednym
  `consults-without-match` (celowe w `BoundaryRig`), `process-manager-without-event-reactions`,
  `competing-in-transaction-consumers`, `emits-never-produced` (celowe `misbehave` w `DispatchRig`) i 3
  `free-text-not-personal`.

Mechanika, rozstrzygnięta przez asystenta:
- **Katalog w kodzie, strona z katalogu.** `EhOsContract.Check.Catalog` trzyma nazwę, poziom, co reguła czyta (v1,
  v2, obie), odpowiednik w ESDM i akapit; `docs/rules.md` generuje `mix eh_os_contract.rules` (task deweloperski,
  `--check` w bramie pakietu, strona w `extras`). `Finding.new/3` dla nazwy spoza katalogu rzuca, więc nic nie
  wychodzi bez opisu. Link w wyjściu to adres hexdocs (`rules.html#<nazwa>`) — zadziała po publikacji, którą
  decyduje użytkownik; plik jest w pakiecie od teraz.
- **Wyjście:** dwie linie na ustalenie (`POZIOM nazwa: zdanie`, potem `plik:linia · link`); kolejność jak
  dotąd (poziom, zdanie). JSON: `rule`, `level` (`error`/`warning`/`notice`), `message`, `file`, `line`,
  `documentation`. Ustalenia v1 dostały nazwy i nie mają lokalizacji (v1 znika w E11). `no-contracts` liczy też
  kontrakty v2 — wcześniej aplikacja z samymi v2 usłyszałaby, że nie ma kontraktów.
- **Reguły czytają to, co L3:** `Links.contract/1` (model, deklaracje z plikiem i linią) i deklaracje domeny ze
  Sparka, więc ustalenie wskazuje aktora, kontekst, relację, zdarzenie, pole albo `consumes`.
- **Gdzie ESDM a my różnimy się świadomie** (notka z datą w v2 §6): obietnica i `terminal: true` liczą się jako
  czytelnik zdarzenia (raport zgodności), bo bez wyciszania każde zdarzenie kończące przebieg ostrzegałoby na
  zawsze; `aggregate-without-commands` pominięte (D6); odwołaniem między kontekstami jest też pole wskazujące
  encję innego kontekstu (EM2); `ends_on` nie jest reakcją. Nazwa `process-manager-without-ends-on` — słowem
  naszego DSL-a, z odpowiednikiem ESDM w opisie.
- **Niezbudowane, z powodem:** reguła o zmianie schematu zdarzenia publicznego od wdrożonej wersji (jedyna, która
  potrzebuje bazy — wraca z E12); v1-owe „obietnica drobniejsza niż przebieg” (nie ma kontraktu v2, na którym by
  ją sprawdzić — E9).
- **Powtórzenie L3:** `Check.compiler_findings/2`, gdy w `compilers` projektu nie ma `:eh_os_contract`; ustalenie ma
  kod kompilatora (`X1`, `D14`) jako nazwę i nie ma linku (dokumentacją jest v2 §6).
- **`emits-never-produced`** czyta `emitted` z `__eh_os_implementation__/0`; `emit/1` w funkcji pomocniczej liczy
  się dla każdej komendy jednostki. Decyzja, która zwraca zdarzenie bez `emit/1`, dostaje ostrzeżenie — to też
  sygnał (niczego nie sprawdza aż do dispatchu).

**Przegląd przed kolejną częścią** (dwa równolegle na `main..7034708`):
- **Poprawione, z testem i próbą odwrotną:** `competing-in-transaction-consumers` wywracał cały `check`, gdy
  `consumes` wskazywał nieskompilowany moduł — dokładnie projekt bez kompilatora, dla którego EL1 powtarza L3
  (`9f7a41d`); `free-text-not-personal` nie widział `{:list, :string}`, wartości domeny będącej tekstem ani pól
  tekstowych wartości złożonej (`03a6cc4`); ta sama reguła wskazywała linię `use`, nie reakcję (`1a9112e`);
  pusta druga linia przy ustaleniu bez miejsca i linku (`471eee5`); skan `.beam` szedł zawsze i wywracał `check` w
  korzeniu umbrelli (`50ab457`, gałąź umbrelli bez testu — w repozytorium nie ma umbrelli).
- **Porządki i pokrycie** (`7d46602`): komentarz, `Catalog.known?/1`, `Catalog.level_word/1`; test konsumentów
  (samo `ends_on`, obietnica, `publish`, `consumes` rodzeństwa) i reakcji dwóch kontraktów naraz.
- **Bez zmiany:** `event-without-consumer` na zdarzeniach w etapach — raport zgodności czyta każde zdarzenie
  przebiegu, ale policzenie tego jako czytelnika wyłączyłoby regułę całkiem, bo każde zdarzenie jest w przebiegu
  swojego kontraktu (R2/R3); L3 powtarzane tylko na modułach projektu, jak w kompilatorze; ścieżka absolutna pliku
  spoza katalogu roboczego, jak w diagnostyce kompilatora.
- **Pominięte:** `Links.contract/1` budowany trzy razy na kontrakt (koszt pomijalny w tasku).
- Weryfikacja poza testami: `MIX_ENV=dev mix eh_os_contract.check --format json` w `sandbox/` po kompilacji —
  poprawny JSON, 31 ustaleń (12 ostrzeżeń, 19 notek), `orphan-actor` w `lib/rehmed/domain.ex:41`.

**Do E9:** `event-name-with-aggregate-prefix` zapali się na nazwach z warsztatu, jeśli jednostka nazywa się jak
początek zdarzenia (`accounting_month_opened` w jednostce `accounting_month`). Nazwy zdarzeń zostają z warsztatu
(`CLAUDE.md`), więc albo jednostka dostaje inną nazwę z materiału, albo ostrzeżenie zostaje i jest prawdziwe.

### Przed EL2 — decyzje użytkownika (27 września)

Pytania po przeglądzie EL1, każde z przykładem z materiału; wszystkie pola są opisowe — nic ich nie wykonuje, czytają
je `glossary`, `view`, strony dokumentacji (EL3) i grafy (EG).

- **Zmienione tego samego dnia, po pytaniu użytkownika „czy silnik może to sprawdzić?”** — wyjaśnione na
  `record_payment` i `value :money`, jak dziś działa inwariant agregatu (nazwa w kontrakcie, `reject` w
  implementacji, S8, test ze scenariusza):
  - **Ograniczenie komendy sprawdzane scenariuszem:** `constraint :positive_amount, "…"` w komendzie, komenda je
    `rejects:`, implementacja `reject(:positive_amount)`, każde ograniczenie ma scenariusz odmowy (jak S8), test
    generuje `ScenarioCase`. Query nie odmawia, więc tam ograniczenie zostaje prozą. *Odrzucone:* sama proza
    (nic nie dowodzi, że kod trzyma regułę); scenariusz zalecany ostrzeżeniem `check` zamiast błędu (łagodniej niż
    S8 dla inwariantów).
  - **Inwariant wartości z walidatorem od razu:** domena generuje behaviour, implementacja wartości definiuje
    funkcję na każdy inwariant, dispatch sprawdza pola tego typu, test z kontrprzykładu przy inwariancie.
    Rekomendacja asystenta była inna — proza teraz, walidator, gdy E9 go potrzebuje; *odrzucone* przez użytkownika.
    Kształty rozstrzygnięte zaraz potem:
    - **sprawdzane w komendzie i w zdarzeniach**, także w listach i polach wartości złożonych: pole komendy —
      odmowa przed decyzją, `{:error, {:invalid, [amount: {:invariant, :not_negative}]}}`, HTTP 422
      `{"invalid": {"amount": "not_negative"}}`, bez wiersza w logu; zdarzenie z decyzji — błąd kodu, rzuca jak
      niezadeklarowane zdarzenie; zdarzenie z `record/3` — odmowa jak przy komendzie. *Odrzucone:* tylko komenda
      (zła wartość z decyzji albo nagrania zostaje w logu na zawsze); tylko zdarzenia (komenda z -500 wywraca
      dispatch zamiast odmowy);
    - **kontrprzykład i przykład poprawny, oba wymagane:** `invariant :not_negative, "…", violated_by: [-1],
      satisfied_by: [0, 15_000]`; brak to błąd kompilacji; każdy daje wygenerowany test (walidator odrzuca
      `violated_by` i przepuszcza `satisfied_by`). Wybór użytkownika zamiast rekomendacji asystenta (samo
      `violated_by`, wymagane). *Odrzucone:* samo `violated_by`, wymagane (nie dowodzi, że walidator nie odrzuca
      wszystkiego); `violated_by` opcjonalne z ostrzeżeniem (inwariant bez dowodu);
    - **funkcja na inwariant:** `use Rehmed.Domain, value: :money`, `def not_negative(amount), do: amount >= 0`;
      behaviour z `@callback not_negative(money()) :: boolean()`, L4 wymaga każdej funkcji. *Odrzucone:* jedno
      `check/1` zwracające nazwę (kompilator nie sprawdzi, że każdy inwariant jest obsłużony);
    - **osobny PR po EL2, przed EL3** (EL2b), z przeglądem po skończeniu. *Odrzucone:* w EL2 (diff łączy narzędzia
      tekstowe z mechaniką dispatchu); po EL3 (dokumentacja EL3 nie pokazałaby kontrprzykładów).
- *Pierwsza wersja, zastąpiona akapitem wyżej:* **`constraints` i inwarianty wartości jako nazwane deklaracje:** `command :record_payment, … do constraint
  :positive_amount, "Kwota płatności jest dodatnia" end` (tak samo w query) i `value :money, :integer, unit: :grosze
  do invariant :not_negative, "Kwota nie jest ujemna" end` — kształt `invariant` agregatu, nazwa daje kotwicę na
  stronie. Proza po polsku, więc lista miejsc w `CLAUDE.md` rośnie. *Odrzucone:* lista zdań w opcji,
  `constraints: ["…"]` (bez nazw — nie ma do czego linkować ani czego przypiąć); inwarianty wykonywane przez MFA w
  Codecu (nowa mechanika runtime, nie pole opisowe).
- **Tłumaczenie jak w ESDM, definicja wymagana:** `translation :en, "Completed", definition: "…" do avoid "Done",
  reason: "…" end`; `avoid` przy terminie też dostaje opcjonalne `reason:`. *Odrzucone:* definicja opcjonalna
  (słownik w drugim języku bywa pusty); sama definicja bez `avoid` i `reason:` (luka względem ESDM w połowie).
- **Relacja z systemem zewnętrznym tymi samymi kluczami:** `relation :conformist, upstream: :ksef, downstream:
  :settlement`, gdzie `:ksef` to `external` domeny; tylko relacje kierunkowe, jak w ESDM; nowa reguła D pilnuje, że
  żadna nazwa nie jest naraz kontekstem i systemem; `orphan-external-system` liczy relację jako użycie.
  *Odrzucone:* jawny rodzaj końca, `upstream: {:external, :ksef}` (drugi zapis końca obok nazwy kontekstu); relacje
  tylko między kontekstami (mapa w EG nie pokaże, kto się komu podporządkowuje).
- **Identyfikator nadawany przez system zewnętrzny: `issued_by:`** (pytanie dopisane przez użytkownika):
  `field :p1_report_id, :id, issued_by: :medical_event_registry`; składa się z encją (`field :invoice_number, {:id,
  :invoice}, issued_by: :ksef`). Czytelnik: `view` i strona elementu w EL, krawędź w EG; `orphan-external-system`
  liczy wystawcę jako użycie. *Odrzucone:* (a) `{:id, :system}`, zapis encji z EM2 (jeden zapis dla dwóch rzeczy,
  pole naraz encją i numerem z systemu niewyrażalne); (c) proza w `source:` (ani `check`, ani grafy tego nie
  zobaczą).

### EL2 — co wyszło (27 września)

Na `dsl-v2/el-glossary` (od EL1), niewypchnięte. Dwa commity decyzji (`7d03eea`, `67c27e1`) i osiem budowy:
`mix eh_os_contract.glossary` (`367ece8`), `mix eh_os_contract.view` (`9cbbf50`), nazwana subdomena (`1fa7403`),
tłumaczenie z definicją i `avoid` z powodem (`0b46c5b`), sprawdzane ograniczenia komend (`458b8d9`), relacja z
systemem zewnętrznym (`030ecc4`), `issued_by:` (`d1362d2`), poprawka z weryfikacji (`efda115`). Silnik 1075 → 1096
testów; `check` bez zmian (sandbox 0 / 12 / 19, silnik 0 / 50 / 20).

Mechanika, rozstrzygnięta przez asystenta:
- **Każde pole razem z czytelnikiem:** subdomena — `view` i reguła `subdomain-without-bounded-context`;
  tłumaczenie — `glossary --language`; ograniczenie — `view --details`, scenariusz i test; relacja z systemem i
  `issued_by:` — `orphan-external-system` i `orphan-context-mapping` (mapę kontekstów rysuje EG).
- **Rejestr zna domeny** (`Registry.domains/0`); oba taski zaczynają od domeny aplikacji, `--domain`, gdy jest ich
  kilka. Słowa biblioteki w wyjściu po angielsku, słownik klienta dosłownie. Kolejność jak w deklaracji.
- **Nazwana subdomena w fiksturach i sandboxie:** materiał nie nazywa subdomen (jest tylko `CTX-01` jako jedyny
  `core`), więc każda domena dostała jedną subdomenę na rodzaj, który jej konteksty podawały — zapis kontekstów
  bez zmian, deklaracje na końcu modułu, żeby nie ruszyć żadnej przypiętej linii. §4.5 ADR kompiluje się z
  poprawką w `@amendments` testu przykładów, a nie z przepisanym ADR. Wersja każdej domeny się rusza.
- **Ograniczenie komendy:** A3 wpuszcza je do `rejects:`, nowa A7 (nazwa raz, nigdy jak inwariant jednostki, musi
  być w `rejects:`), S8 wymaga scenariusza odmowy tej komendy, I5 bez zmian (czyta `rejects:`). W odpowiedzi
  odmowy nazwa ograniczenia stoi tam, gdzie nazwa inwariantu (`Rejection.invariant`, `{"rejected": …}`).
- **Relacja z systemem:** tylko kierunkowa, drugi koniec kontekstem (D5); D1 odmawia nazwy naraz kontekstu i
  systemu. `cross-bounded-context-reference-without-mapping` zostaje o kontekstach, jak w ESDM.
- **`issued_by:`** bez ograniczenia typu (numer KSeF bywa napisem), sprawdzany w kontrakcie przez X4, w domenie
  przez nową D8; w modelu tylko tam, gdzie zadeklarowany. **Niezbudowane:** L5 „system wystawia identyfikator, a
  żaden efekt go nie woła” — numer bywa przepisywany przez człowieka, więc ostrzeżenie byłoby fałszywe bez
  sposobu na wyciszenie.
- **`CLAUDE.md` bez zmian**, choć „Przed EL” to zapowiadało: druga pozycja `constraint`, jak `invariant`, to
  `label`, a `label` już jest na liście miejsc po polsku.
- **Pułapka zapisana tutaj:** `mix format` w `sandbox/` i w pakiecie web pamięta eksport formattera zależności
  (`_build/*/lib/*/.mix/cached_dot_formatter`), więc nowe słowo DSL-a dostaje tam nawiasy, dopóki się tego pliku
  nie skasuje.

Weryfikacja poza testami (`MIX_ENV=dev` w `sandbox/`): `view` pokazuje domenę Rehmedu z subdomenami; `glossary
--language en` padało, bo atom `:en` nie istniał w maszynie, a sandbox nie ma angielskich tłumaczeń — poprawione
(`efda115`), teraz „_No translation into en._”.

**Przegląd EL2** (dwa równolegle na `dsl-v2/el-warnings..df06b36`):
- **Poprawione, z testem i próbą odwrotną:** kolejność ograniczeń ruszała digest komendy (`0a51f81`); relacja z
  systemem liczyła tylko część użyć, a `issuers/1` czytał dane scenariuszy (`1800fb3`); nazwy ograniczeń poza N1,
  duplikat ograniczenia query przepuszczany, A7 zgłaszało duplikat dwa razy (`21a223e`); `view` z nieznaną
  nazwą drukował puste drzewo, dwa argumenty dawały wyjątek, nazwa wiersza odczytywana z tekstu (`1c45152`).
- **Poprawione słownie** (`87f9a4e`): I5 i dokumentacja `reject/1` / `Rejection` mówią o ograniczeniach; D5 dla
  symetrycznej relacji z systemem; przykład w `DslWrappers`.
- **Bez zmiany:** `String.to_atom` dla `--language` (jeden argument w tasku deweloperskim); `reason: nil` i
  `avoid: []` w modelu domeny (wersja każdej domeny i tak ruszyła w EL2); etykieta ograniczenia w raporcie pokrycia
  (S8 wymaga scenariusza odmowy dla każdego ograniczenia, więc taka odmowa nie jest nigdy niezadeklarowana).
- Sprawdzone przez przegląd na prawdziwych danych: `VisitSettlement` ma na końcu EL2 tę samą wersję i te same 15
  digestów co przed nim.

### Po EL2 — proza, którą da się sprawdzać (27 września)

Na prośbę użytkownika asystent przejrzał oba DSL-e pole po polu: co jest dziś prozą albo deklaracją, której w v2
nikt nie czyta, a mogłoby być sprawdzane kompilatorem albo wygenerowanym testem. Wzorzec, który już działa:
inwariant agregatu i od EL2 ograniczenie komendy (nazwa, `reject`, scenariusz odmowy, test).

**Decyzja użytkownika: 1–4 do EL, 5 do EL2b, 6–9 odłożone.** 1–4 czytają pola z EL2 (`direction`, `avoid`,
relacje, reakcje), więc wchodzą na gałąź EL2 po rozstrzygnięciu jej przeglądu, z przeglądem nowych commitów
(rozstrzygnięcie asystenta — mechanika).

1. **Kierunek relacji kontra to, kto kogo konsumuje.** `separate_ways` a `consumes` między kontekstami — sprzeczność;
   `customer_supplier` i `conformist` — odwołanie tylko od downstream do upstream; `published_language` i
   `open_host_service` — downstream przez `publish` (D11), nie przez `consumes`. Przykład: Rehmed `customer_supplier
   scheduling → settlement`, a kontrakt `scheduling` konsumujący rozliczenia.
2. **Słowa do unikania w etykietach.** Etykieta kontraktu danego kontekstu zawierająca słowo z `avoid` tego
   kontekstu — ostrzeżenie (termin „Zrealizowana”, `avoid "Zakończona"`, zdarzenie „Wizyta zakończona”).
3. **`direction` systemu kontra użycie.** `calls:` do systemu `:inbound`, albo `issued_by:` / nagrania aktora
   `backed_by:` od systemu `:outbound` — sprzeczność; dziś `direction` jest wymagane i nikt go nie czyta.
4. **Pokrycie scenariuszami reakcji i query.** Polityka, process manager i query bez scenariusza — dziś S8 wymaga
   go tylko dla inwariantów i ograniczeń (ESDM: `feature-without-scenarios`). Poziom (ostrzeżenie czy błąd jak S8) —
   rozstrzygnięcie przy budowie, z wyjaśnieniem.
5. **Przykłady przy regule serwisu domenowego** — `rule :never_below_zero, "…", examples: [{[1, 3], 0}]`, każdy
   daje test funkcji; ten sam mechanizm co `violated_by` / `satisfied_by` walidatora wartości, więc w EL2b.

**1–4 zbudowane 27 września** na `dsl-v2/el-glossary`, po przeglądzie EL2: `relation-against-references`
(`f82e470`), `label-with-avoided-term` (`4343068`), `external-direction-contradicted` (`acda05e`),
`reaction-without-scenario` (`61579c7`). Rozstrzygnięcia asystenta:
- **Z 1 pominięta część o `open_host_service` / `published_language` przez `publish`:** w jednej aplikacji
  `consumes` rodzeństwa to właściwa droga, a `publish` (D11) jest między aplikacjami, więc reguła myliłaby się na
  każdej takiej relacji wewnątrz aplikacji. Kierunek sprawdzany tylko między kontekstami: to, w którą stronę idzie
  wywołanie systemu, nie mówi, kto od kogo zależy.
- **2** czyta etykiety wszystkich deklaracji kontraktu (także pól), całe słowa bez względu na wielkość liter; słowa
  z `avoid` tłumaczeń należą do innego języka i są pominięte.
- **3:** `calls:` wymaga systemu `:outbound` albo `:bidirectional`; `issued_by:` i `backed_by:` — `:inbound` albo
  `:bidirectional` (P1: wysłany raport, zwrócony numer).
- **4 jako ostrzeżenie, nie błąd jak S8:** scenariusz odmowy to jedyny dowód, że inwariant trzyma, a reakcję
  sprawdza też raport zgodności na logu; błąd wymusiłby scenariusze na fiksturach pisanych pod inny mechanizm.
  Delta silnika 50 → 63 ostrzeżeń (13 reakcji i query fikstur), sandbox bez zmian.

**Przegląd reguł 1–4** (dwa równolegle na `76d48ea..0513862`): poprawione `label-with-avoided-term` — puste `avoid`,
termin zawierający słowo do unikania, etykiety członków enum, jeden wzorzec na słowo, „bez względu na wielkość
liter”, odmian nie łapie (`7ad65b6`); `relation-against-references` stoi przy odwołaniu, nie przy relacji
(`875dff5`); **reguła 3 zawężona**: wywołanie systemu `:inbound` nie jest sprzecznością, bo efekt woła też po to,
żeby pobrać dane — zostały `issued_by:` i `backed_by:` przy systemie `:outbound` (`b2fb6c0`, zmiana względem opisu
wyżej); polskie „Po EL2” w komentarzach zastąpione angielskim odwołaniem. Pominięte: trzy sposoby zbierania pól z
`issued_by:` (ryzyko utrzymania, bez błędu dziś), `crossings/2` liczone kilka razy na domenę (koszt pomijalny).

*Odłożone do E9* (zobaczyć na prawdziwych kontraktach, czy są potrzebne): 6 — ograniczenie query sprawdzane
scenariuszem `answers` (przykład z testu okazał się `scope`, który już jest pilnowany); 7 — `expected_latency`
systemu mierzone na jobach efektów w raporcie zgodności (w v2 nikt go nie czyta); 8 — scenariusz efektu z
zaślepką systemu (najdroższe: dziś S6 wyklucza efekt jako cel scenariusza); 9 — `source:` i nazwy z warsztatu
(notka dla zdarzenia bez `source:`, albo indeks identyfikatorów materiału w konfiguracji — wymaga decyzji, gdzie
materiał żyje dla hosta).

*Zostaje prozą, bo ma być:* `label`, `definition`, opis scenariusza, `unavailable_looks_like`, proza `where:` w
`consults` (mechanika już jest konkretna: bez `match:` granica czyta wszystkie zdarzenia typu, co ma ostrzeżenie
`consults-without-match`; proza mówi tylko dlaczego).

### Przed EL2b — decyzja użytkownika (28 września)

Kształty walidatora wartości są z „Przed EL2 — decyzje użytkownika”, a zapis przykładu reguły — z pozycji 5 w „Po
EL2” (`examples: [{[1, 3], 0}]`: argumenty w kolejności wywołania, potem wynik). Otwarte zostało jedno pytanie,
zadane na fiksturze `BoundaryRig.Enrolment` (`function :free_seats`, `rule :never_below_zero`).

- **Przykłady przy regule serwisu domenowego są wymagane:** reguła bez `examples:` albo z pustą listą się nie
  kompiluje, tak jak inwariant wartości bez `violated_by:`. Funkcja serwisu jest czysta, więc każdą regułę da się
  pokazać na parze argumenty → wynik. Każdy przykład daje test, który woła funkcję przez moduł kontraktu
  (`C.DomainServices.Seating.free_seats(1, 3) == 0`), więc sprawdza też typy argumentów i wyniku. *Odrzucone:*
  opcjonalne z ostrzeżeniem `check` (ostrzeżenia nie da się wyciszyć, a reguła bez dowodu i tak przejdzie
  kompilację); opcjonalne bez ostrzeżenia (reguła zostaje prozą i nikt się o tym nie dowie).

### EL2b — co wyszło (28 września)

Na `dsl-v2/el-values` (od `dsl-v2/el-handoff`), niewypchnięte. Commit decyzji (`7beabe8`), dwa budowy —
inwarianty wartości (`5c4f8eb`) i przykłady reguł (`3e9b344`) — i siedem z przeglądu. Silnik 1106 → 1162
testów. Delta `check` silnika 0 / 63 / 20 → **0 / 65 / 21**, wszystko na nowej wymyślonej fiksturze `ValueRig` i
tych rodzajów, które mają inne fikstury: `process-without-accountable` (`:till`), `reaction-without-scenario`
(query `:payments_above`), notka `free-text-not-personal` (`note` płatności). Sandbox bez zmian (0 / 12 / 19);
`VisitSettlement` ma dalej `2ae1d0074cbc` i wiring `90e7d665ab04`, sprawdzone w `MIX_ENV=dev` i w tabeli
wdrożeń bazy dev.

Mechanika, rozstrzygnięta przez asystenta:
- **Inwariant wartości** siedzi w bloku `value` (nowa encja `invariant` DSL-a domeny); **D9** — nazwa jak nazwa
  funkcji (snake_case, raz w wartości, bez kolizji z Elixirem z listy N2, nie `:required`/`:type`/`:generated`,
  bo te słowa odmowa stawia tam, gdzie nazwę inwariantu), co najmniej po jednym przykładzie w każdej liście,
  przykłady jako dane proste typu wartości (jak dane scenariusza), żaden `nil`, żaden w obu listach ani dwa razy.
- **Behaviour** `D.Values.<Nazwa>` tylko dla wartości z inwariantami; `use D, value: :name` przez
  `EhOsContract.Implementation` (I1, I2, I7 jak dla kontraktu), callbacki z `Callbacks.of/3`. Wartość bez
  inwariantów nie ma czego implementować (I1 to mówi).
- **Gdzie sprawdzane:** wszędzie, gdzie dispatch sprawdza typ — komenda, `record/3`, parametry query (odmowa),
  zdarzenie z decyzji, argumenty i wynik serwisu domenowego (rzuca). Najpierw to, z czego wartość się składa
  (elementy listy, pola, wartość, na którą wskazuje alias), potem jej własne; pierwszy złamany to problem pola.
  Query i serwis domenowy są poza literą decyzji („w komendzie i w zdarzeniach”), ale wartość łamiąca inwariant nie
  jest wartością tego typu, więc jedna reguła dla wszystkich miejsc, w których typ jest sprawdzany. **Odczyt
  logu nigdy nie sprawdza.** Funkcja odpowiadająca czymś innym niż boolean rzuca, bez pokazania odpowiedzi.
- **Digest:** wartość bez inwariantów liczy się jak przed EL2b, więc wersja żadnej domeny się nie ruszyła.
- **Testy z przykładów:** `use EhOsContract.ScenarioCase, domain: D` — `violated_by` → funkcja inwariantu mówi
  `false`; `satisfied_by` → każdy inwariant wartości mówi `true`, a to, z czego się składa, przechodzi sprawdzenie
  dispatchu. Przykłady reguł wchodzą same do `use EhOsContract.ScenarioCase, contract: C`: wywołanie przez
  `C.DomainServices.<Nazwa>`, wynik porównany jako wartość (2.50 to 2.5).
- **Przykład reguły** zostaje w modelu jako `{[argumenty], wynik}`, tak jak zapisany; **S9** sprawdza kształt,
  arność, typy wbudowane i `nil` tylko przy `optional`; **X9** — wartości typów domeny.
- **`check`:** `value-without-implementation` (ostrzeżenie), tylko dla domeny, której jakiś kontrakt ma kod.

**Przegląd EL2b** (dwa równolegle na `8ab88ba..3e9b344`):
- **Poprawione, z testem i próbą odwrotną:** implementacja serwisu domenowego szukana w indeksie przy każdym
  wywołaniu (`43b430b`) i implementacja wartości przy każdej sprawdzanej wartości (`fb2abb1`) — skan
  załadowanych aplikacji, ~30 µs, lista 100 tys. kwot w jednym żądaniu; przykład podany dwa razy w jednej liście
  dawał zduplikowaną nazwę testu (`4727123`); przykład „zachowuje” jednego inwariantu, który inny inwariant
  wartości albo wartość, z której się składa, podaje jako „łamie” (`eaffa10`), a test `satisfied_by` nie pytał
  części wartości (`67ef206`); implementacje wartości poza `wiring_version`, więc zmiana tego, co dispatch
  przyjmuje, nie była widoczna jako wdrożenie (`419bf9a`); N2 i D9 z jednej funkcji, co domknęło lukę:
  zdarzenie `:module_info` przechodziło N2 (`c418908`).
- **Pominięte, z powodem:** implementacja wartości szukana wśród skonfigurowanych aplikacji i aplikacji domeny,
  jak implementacje kontraktu wśród aplikacji kontraktu (v2 §10.5; zapisane w ADR); `implementations:` w
  `ScenarioCase` nie sięga do wartości z inwariantami (tylko fikstury kompilowane ze stringów, żaden host);
  wyjątek z funkcji inwariantu albo brak implementacji rzuca przed transakcją, więc bez wiersza `failed` — jak
  wszystko, co dispatch robi przed transakcją, np. `Authorizer`; wyjątek z funkcji inwariantu niesie argument w
  stacktrace — tak samo jak decyzja i efekt, bez nowego rodzaju narażenia.
- **Rozstrzygnięte przez asystenta, potwierdzone przez użytkownika 28 września:** inwariant dodany później odmawia
  komendy, którą reakcja buduje ze starego zdarzenia, a odmowa komendy reakcji cofa komendę, która ją wywołała,
  albo zatrzymuje uporządkowanego konsumenta na tym zdarzeniu. Zostaje tak, zapisane w ADR (§6, notka z 28
  września): dodanie inwariantu to zmiana modelu jak zawężenie typu. *Odrzucone:* komendy reakcji bez sprawdzania
  inwariantów (zła wartość wraca do logu tą drogą); ostrzeżenie `check` o wartościach w logu (potrzebuje bazy, jak
  reguła o zmianie schematu odłożona do E12).

### Przed EL3 — decyzje użytkownika (28 września)

Pytanie zadane na Rehmedzie (domena `rehmed`, kontekst `:settlement`, `VisitSettlement` z `:record_payment`,
`:payment_recorded` i wartością `:money`), z podglądem układu plików przy każdej opcji.

- **Strona na element, jak w ESDM:** osobny plik dla domeny, kontekstu, kontraktu i każdej deklaracji w nim, dla
  wartości i encji domeny, z linkami między nimi (komenda → zdarzenie, pole → wartość). *Odrzucone:* strona na
  kontrakt z kotwicami (link trafia w długą stronę); strona na kontekst (kontekst z kilkoma kontraktami to jedna
  bardzo długa strona).
- **`--output <katalog>`, jak `esdm documentation --output`:** host decyduje, czy pliki commituje, czy wkłada do
  ExDoc (`extras`), czy tylko ogląda; `--check` mówi, czy katalog jest aktualny. *Odrzucone:* stały katalog z
  `--check` w bramie hosta (wymaganie, o które host nie prosił); tylko `extras` przy `mix docs` (bez plików w
  repozytorium nie ma ich w przeglądzie PR-a).

### EL3 — co wyszło (28 września)

Na `dsl-v2/el-docs` (od `dsl-v2/el-values`), niewypchnięte. Commit decyzji (`f2af33b`), jeden budowy
(`1eed5c2`) i dziesięć z przeglądu. Silnik 1162 → 1187 testów; `check` bez zmian (sandbox 0 / 12 / 19, silnik 0
/ 65 / 21). Na Rehmedzie w `MIX_ENV=dev`: 18 stron, `--check` → `current`, po ręcznej edycji → `differs`.

Mechanika, rozstrzygnięta przez asystenta:
- **`EhOsContract.Pages.render/2`** jest czysta: model domeny i kontraktów → `%{ścieżka => Markdown}`; task
  `mix eh_os_contract.pages --output <katalog> [--check] [--domain]` tylko pisze i porównuje.
- **Układ:** `index.md` domeny (z drzewem `view`), `values/`, `entities/`, `<kontekst>/index.md`,
  `<kontekst>/<kontrakt>/index.md` i **katalog na rodzaj** deklaracji (`commands/`, `events/`, `aggregates/`,
  …) — odejście od podglądu z pytania, gdzie komendy i zdarzenia leżały płasko, bo przestrzenie nazw kontraktu
  się nakładają (model odczytu może się nazywać jak jednostka). Kontrakt pod ostatnim członem modułu.
- **Treść:** słowa biblioteki po angielsku, etykiety i słownik klienta dosłownie; strona wartości z
  inwariantami i przykładami oraz „Used by”, encji z „Referred to by”, zdarzenia z „Emitted by” i „Read by”
  (także kontrakty rodzeństwa), serwisu domenowego z przykładami reguł jako wywołaniami. Linki względne.
- **Znacznik w pierwszej linii, z nazwą domeny:** task kasuje tylko swoje strony tej domeny, niczego nie
  nadpisuje ani nie pisze przez link, a wtedy nie pisze nic i wymienia, co stoi na drodze.
- **Deterministycznie:** przykłady wypisane z posortowanymi kluczami map, także w krotkach — `inspect/1` na OTP
  28 wypisuje klucze w kolejności tworzenia atomów.

**Przegląd EL3** (dwa równolegle na `9ae9198..1eed5c2`):
- **Poprawione, z testem i próbą odwrotną:** task nadpisywał pliki, których nie napisał, szedł za linkami
  przy zapisie i kasowaniu, czytał `--output` jako wzorzec globa (`o[u]t` kasowało w `out`), przyjmował puste
  `--output`, czytał całe pliki i zostawiał puste katalogi (`f13828c`); kasował strony innej domeny w tym samym
  drzewie (`19cac2e`); nazwa domeny spoza snake_case wychodziła poza katalog albo psuła linki, a dwa elementy
  jednej ścieżki gubiły stronę (`6654e53`); obietnica bez `or_else` (strona podawała surowszą obietnicę niż
  zadeklarowana), pominięte `include`, surowe termy czasu (`f6d411b`); timer w `on` jako zdarzenie
  „received”, scenariusz process managera bez `sets`/`cancels`/`ended`, opis sklejony z przebiegiem
  (`6a9c114`); mapa w krotce niedeterministyczna (`388d7db`); „Published” z nazwą publikacji zamiast źródła,
  „Consumed” bez linków i przemianowań (`3834eaf`); „Used by” bez encji i process managerów, encja bez
  „Referred to by”, lista referencji jako `{:list, :id}` (`d30eb45`); `|` i nowa linia w etykiecie, backtick w
  przykładzie (`067eb87`); `relative/2` zastąpione `Path.relative_to/3` (`cbee11a`).
- **Pominięte, z powodem:** surowy HTML w etykiecie przechodzi do ExDoc — etykiety pisze autor kodu, więc to
  nie granica zaufania, a escapowanie zmieniłoby etykiety zawierające `<` w każdym czytniku; pętle kwadratowe
  po deklaracjach (setki elementów, raz na uruchomienie); pola odbieranego zdarzenia publikowanego w „Used by”
  (nie mają własnej strony).

### Przed EG — decyzje użytkownika (28 września)

Przed budową asystent opisał cztery grafy na materiale Rehmedu (mapa kontekstów: dwie subdomeny, dwa konteksty,
jedna relacja `customer_supplier`; widok systemu: dziś jeden kontrakt, zero krawędzi `consumes`; pełny graf
`VisitSettlement`; widok agregatu `visit_settlement`) i zapytał o to, czego zapis „Grafy — wszystkie cztery” nie
rozstrzygał. Wszystkie cztery odpowiedzi to propozycje asystenta:

- **Dwa PR-y według poziomu.** **EG1 — poziom kontraktu:** pełny graf kontraktu i widok jednostki (rozszerza
  dzisiejszy graf kroków, sprawdzalny na `VisitSettlement`). **EG2 — poziom domeny:** mapa kontekstów i widok
  systemu z nakładką z logu (jedyna nowa część pytająca bazę). Każdy razem z taskiem i swoim miejscem na ekranie
  albo w stronach; przegląd po każdej części. *Odrzucone:* cztery PR-y, po jednym na graf (mapa i widok systemu
  dzielą ramę domeny, pełny graf i jednostka — rysowanie węzłów kontraktu, więc więcej scalania bez zysku na
  czytelności); najpierw silnik i task dla czterech, potem jeden PR z `/graph` (pierwszy diff za duży).
- **Mermaid wszędzie** — task, strony Markdown, `/graph`. Grafy powstają w silniku najpierw jako dane (węzły i
  krawędzie), potem są rysowane, więc inny renderer da się dołożyć później. *Odrzucone:* DOT obok Mermaida w
  tasku (lepszy układ dużych grafów, ale drugi renderer i program `dot` do obejrzenia); interaktywny `/graph` z
  JSON-a i biblioteką JS w rodzaju Cytoscape, jak EventCatalog (najbliżej kierunku z 25 września i działa pod CSP,
  ale najwięcej pracy i nowa zależność — do ponownego rozważenia, gdy grafy będą miały treść po E9).
- **Na `/graph` tylko grafy z nakładką z logu**: widok systemu i pełny graf kontraktu. **Mapa kontekstów idzie do
  `index.md` domeny, widok jednostki na stronę agregatu** (`mix eh_os_contract.pages`). Wszystkie cztery są w
  tasku `mix eh_os_contract.graph`. Powód: ekran odpowiada na cztery pytania z `CLAUDE.md`, a na nie odpowiadają
  tylko nakładki; mapa i jednostka opisują model, a model ma już strony z EL3. *Odrzucone:* wszystkie cztery na
  `/graph` (tak stał zapis w planie; ekran staje się przeglądarką modelu); wszystkie cztery wszędzie (te same
  obrazki w dwóch miejscach, dashboard poza swoimi pytaniami).
- **CSP w EG, jako ostatnia część (EG3):** ekran grafu ma działać pod `default-src 'self'` EHOS-a — style
  Mermaida przeniesione po narysowaniu przez CSSOM, sprawdzone w przeglądarce z polityką EHOS-a. Powód: bez tego
  nowe diagramy nie pokazują się w jedynym hoście, który istnieje. *Odrzucone:* osobno po EG (zakres zostaje przy
  grafach, ale ekran, na który EG dokłada, dalej wymaga `style-src 'unsafe-inline'`).

**Zmienione 28 września, po EG3, na polecenie użytkownika:** „dodaj mapę kontekstów i widok jednostki na
/graph”. Ekran pokazuje teraz wszystkie cztery: na górze każdej domeny jej mapę kontekstów i system, pod panelami
procesu — każdą jednostkę kontraktu wybranego procesu v2. Mapa i jednostka zostają też na stronach i w tasku.
Poprzednia decyzja („na `/graph` tylko nakładki”) przegrała z tym, że ekran jest miejscem, w którym ludzie oglądają
model; cztery pytania z `CLAUDE.md` dalej odpowiadają nakładki, a mapa i jednostka są opisem obok nich.
Zrobione w `e6b915a`; przegląd (dwa równolegle) znalazł, że bloki diagramów nie miały `phx-update="ignore"`, więc
każda łatka LiveView wyjmowała narysowane SVG ze wszystkich bloków — zmiana procesu opróżniała też mapę i system,
które się nie zmieniły (zmierzone w przeglądarce przed i po; `453cc0c`, test na atrybut). Poza tym `@units` zamiast
`assigns[:units] || []`, test domeny bez kontraktów v2, jedno grupowanie po domenie, moduledoc, README i notka z
datą w `technology-notes.md` przy „navigation is per-process” (`8e0a745`). Pominięte: dwie domeny o jednym `name:`
dałyby zdublowane identyfikatory bloków — nazwa domeny jest prefiksem uprawnień EHOS-a, więc to sprawa rejestru.
Web 43 → 45 testów.

Rozstrzygnięte przez asystenta (mechanika): nowe grafy są tylko dla v2, grafy v1 w tasku i na ekranie zostają bez
zmiany bajtu do wycięcia v1; kształt węzłów i kolory Event Stormingu jak w dzisiejszym grafie kroków.

### EG1 — co wyszło (28 września)

Na `dsl-v2/eg-graphs`, niewypchnięte: `0eca258` (EG1) i poprawki z przeglądu `8e194dc`, `1e3de9e`, `87a2beb`,
`92d5d28`, `db1d0c9`, `285a3ce`. Brama zielona na każdym commicie. Silnik 1187 → **1204** testy, `check` bez zmian
(sandbox 0 / 12 / 19, silnik 0 / 65 / 21), web 41, auth 51.

- **Pełny graf kontraktu** (`EhOsContract.Graph.contract_to_mermaid/2`, dawne `steps_to_mermaid/2`): kroki jak
  były, a wokół nich ramka każdej jednostki z jej komendami i zdarzeniami, aktorzy (`by:` → komenda i query,
  `recorded_by:` → zdarzenie z napisem `records`), read modele (zdarzenie → read model, przerywana przy dostawie
  po transakcji) i query (`reads`), systemy zewnętrzne domeny (`calls` efektu, `depends_on` zdarzenia bez grotu,
  `backed by` aktora systemowego, `gives <pole>` — pole nadawane przez system, wprost albo jako identyfikator
  encji). Nakładka tylko na krokach i zdarzeniach, liczniki bez zmian. Serwisy domenowe pominięte: model nie
  wiąże ich z komendami, więc nie ma czego narysować poza pudełkiem.
- **Widok jednostki** (`unit_to_mermaid/2`): karta stanu z polami (`identity`, `optional`), komendy → zdarzenia
  → stan; w DCB do stanu wchodzą zdarzenia konsultowane (`consulted by <pola>` albo „where stated in prose”),
  także cudze. Niezmiennik i ograniczenie komendy to romby przy komendzie, która może na nich odpaść. **Scenariusze
  liczone na krawędziach** (`2 scenarios`), nie rysowane: krawędź bez liczby to ścieżka, której nic nie przypina.
  Na stronie agregatu i DCB z `mix eh_os_contract.pages` jako blok ```` ```mermaid ````.
- **Dane najpierw**: `Graph.Contract.build/2` i `Graph.Unit.build/2` dają węzły, krawędzie i grupy;
  `Graph.Mermaid.render/2` rysuje. Wspólne `escape/1`, `runs/1` i identyfikatory węzłów używa też graf v1.
- **Task**: `--contract <Moduł> [--overlay] [--unit <nazwa>]`; `--process <p> --overlay` dla v2 rysuje pełny graf.
  Flaga, której obrazek by nie użył, jest odrzucana.
- **`/graph`**: drugi panel procesu v2 to pełny graf z nakładką. Sprawdzone na bazie dev: 13 węzłów
  `VisitSettlement` (5 komend, 6 zdarzeń, Specjalista, Recepcja), liczniki „4/6 runs” przy płatności; etykiety v1
  AccountingMonth z polskimi znakami. **`graph --overlay --mermaid` v1 bajt w bajt jak punkt odniesienia**
  `2026-09-27-po-zasiewie-visit-settlement`; graf `visit_settlement` różni się tylko dopisanymi węzłami i
  krawędziami (z odniesienia ubyły wyłącznie `classDef` rodzajów, których ten kontrakt nie ma).

**Przegląd (dwa równolegle, `pre-pr-review`).** Poprawione, każde z testem padającym na starym kodzie:
ograniczenie komendy w `rejects:` dawało krawędź do niezadeklarowanego węzła (`8e194dc`); kontrakt z nieistniejącą
domeną (v2 §8) wywracał pełny graf, który jako graf kroków się rysował (`1e3de9e`); złamanie linii w etykiecie
zamykało blok Mermaida na stronie (`87a2beb`); task po cichu gubił `--overlay`/`--since` przy `--unit` i
`--process` przy `--contract` (`92d5d28`); zdublowane pomocnicze funkcje, komentarz o ExDoc, README (`db1d0c9`).
**Znalezione przy weryfikacji na bazie dev, nie przez przegląd:** poprawka `87a2beb` zamieniała złamania linii
wyrażeniem `~r/\R/` bez flagi `u`, które łapie bajt `0x85` — drugi bajt „ą” w UTF-8 — więc psuła każdą polską
etykietę; żaden test nie miał „ą” (`285a3ce`, test z polską etykietą). Bez zmian: `include`, którego rodzeństwo
już nie deklaruje (R4 to wyklucza, stary kod miał to samo); aktorzy z `grants` zamiast z `by:`/`recorded_by:`
(`grants` powstaje z tych samych deklaracji). Przegląd bezpieczeństwa: bez regresji — zapytania na ekranie te
same co przy grafie kroków; ich koszt (N+1 w `Paths.lag/1`, podwójny mount, cały log bez `since:`) jest sprzed EG.

**Pułapka, od 28 września w `CLAUDE.md`:** wyrażenie regularne na tekście klienta zawsze z flagą `u` — bez niej `\R`, `\s`, `\w` czytają
bajty, a polszczyzna ma w UTF-8 bajty, które coś znaczą.

### EG2 — co wyszło (28 września)

Na `dsl-v2/eg-graphs`, niewypchnięte: `3e9b509` (reguła o flagę `u` w `CLAUDE.md`, na polecenie użytkownika),
`21fbb8e` (kolejka rysowania), `b1e861d` (EG2) i poprawki z przeglądu `31c149c`, `b031a1f`, `6f159a4`, `207b0ea`.
Brama zielona na każdym commicie. Silnik 1204 → **1217** testów, `check` bez zmian (0 / 12 / 19, 0 / 65 / 21), web
41, auth 51.

- **Mapa kontekstów** (`Graph.context_map_to_mermaid/1`): subdomena to ramka z kontekstami („Rdzeń · core”),
  systemy zewnętrzne domeny to walce, także te, do których nie dochodzi żadna relacja (znalezisko, nie szum).
  Relacja kierunkowa to strzałka od upstream do downstream z nazwą wzorca, a na jej końcu może być system
  zewnętrzny; symetryczna to linia bez grotu, `separate_ways` przerywana. Czyta tylko domenę. Na stronie
  `index.md` domeny jako blok Mermaid i w tasku `--map <domena>`.
- **Widok systemu** (`Graph.system_to_mermaid/3`): kontekst to ramka z kontraktami (etykieta: moduł · proces),
  `consumes` rodzeństwa to strzałka z nazwami zdarzeń, publikacja to jeden węzeł, na którym spotykają się
  `publish` i `consumes "<nazwa>"`. Nakładka: przebiegi procesu na kontrakcie; na krawędzi liczba konsumowanych
  zdarzeń w logu i to, co czeka albo pada na krokach konsumenta, które od nich startują. Na `/graph` nad
  panelami procesu, po jednym na domenę z kontraktami v2; w tasku `--system <domena> [--overlay]`.
  Na Rehmedzie: jeden kontrakt, „VisitSettlement · Rozliczenie wizyty (6 runs)”, zero krawędzi — treść przyjdzie z
  E9. Liczba „waiting/failing” na krawędzi nie ma testu z zasianą zaległością (fikstury nie mają konsumenta z
  wierszem subskrypcji na cudzym zdarzeniu); arytmetyka jest ta sama co w pełnym grafie.
- **Usterka ekranu znaleziona w przeglądarce, nie w testach** (`21fbb8e`): `mermaid.run` nadaje SVG identyfikator
  z `Date.now()` i licznika od zera przy każdym wywołaniu, więc dwa rysowania z tej samej milisekundy dostawały
  ten sam identyfikator i drugi diagram lądował w elemencie pierwszego. Przy trzech diagramach — przy każdym
  ładowaniu. Kolejka rysowania jest teraz jedna na stronę. Bez testu: to zachowanie przeglądarki; sprawdzone po
  przełączeniu procesu i zmianie motywu.

**Przegląd (dwa równolegle, `pre-pr-review`).** Poprawione, z testem padającym na starym kodzie: `--unit` przy
`--map`/`--system` był po cichu gubiony (`31c149c`); identyfikatory węzłów z samych nazw zderzały się
(`Clinic.VisitSettlement` i `Clinic.Visit.Settlement`, `clinic.visit.settled.v1` i `clinic.visit_settled.v1`) —
teraz `Mermaid.unique_ids/2` dopisuje kolejny numer (`b031a1f`); nakładka systemu czytała kroki każdego kontraktu,
liczyła przebiegi drugi raz i jedno zapytanie `count(e.id)` na krawędź — teraz tylko konsumenci, przebiegi z ich
kroków, jedno zapytanie pogrupowane po typie na `count(position)`, który obsłuży sam indeks `(type, position)`;
na domenie DispatchRig 28 → 12 zapytań, test z budżetem liczonym przez telemetrię (`6f159a4`); komentarz kolejki
w `app.js` i nieścisłe zdanie o `bounded/2` w CHANGELOG (`207b0ea`). **Pominięte, z powodem:** nakładka na ekranie
bez granicy czasu i podwójny mount (wzorce sprzed EG; EG2 mnoży ich koszt przez liczbę kontraktów domeny — do
pomiaru razem z runnerem read modelu); zawieszone rysowanie wstrzymuje kolejkę strony (świadomy koszt poprawki
identyfikatorów; alternatywa `mermaid.render` z własnym identyfikatorem to przepisanie hooka, można przy EG3);
wybrany kontrakt obserwowany dwa razy przy mount (jeden kontrakt); podwójny filtr domeny w `mount` (potrzebny, żeby
pominąć domeny bez kontraktów). Kontrakt bez procesu nie istnieje (R1), więc gałęzie `process: nil` w grafach to
tylko ostrożność.

### EG3 — co wyszło (28 września)

Na `dsl-v2/eg-graphs`, niewypchnięte: `7dd58ae` (EG3) i poprawki z przeglądu `35e74ed`, `2bd8316`. Brama zielona
na każdym commicie. Silnik 1217 → **1219**, web 41 → **43**, `check` bez zmian.

- **Ekran grafu działa pod `default-src 'self'` EHOS-a.** Wcześniej każdy diagram był czarnym prostokątem.
  Hook rysuje przez `mermaid.render` i przed wstawieniem przenosi `<style>` SVG do arkusza konstruowanego
  (`document.adoptedStyleSheets`), a każdy atrybut `style` do `element.style` — CSSOM nie jest stylem inline i
  polityka go nie blokuje (sprawdzone wprost: `style.cssText` przechodzi, `setAttribute("style")` nie).
- **Sandbox serwuje politykę EHOS-a na dashboardzie na stałe** (`router.ex`, potok `:browser`), więc każde
  oglądanie w dev jest też sprawdzeniem CSP. Ekran statusu: zero naruszeń.
- **Zostaje:** przebieg pomiarowy Mermaida ustawia style inline na roboczej kopii (d3, `innerHTML`, kod
  kształtów) i polityka blokuje każdy — około 400 wpisów w konsoli na załadowanie ekranu grafu w sandboxie, bez
  wpływu na rysunek. *Odrzucone:* przekierowanie `setAttribute("style")` na CSSOM na czas rysowania (394 → 303,
  globalna łatka na prototypie za mało dająca); etykiety SVG zamiast HTML (96 na diagram i inne łamanie
  etykiet); `securityLevel: "sandbox"` (iframe dziedziczy politykę, `render` zwraca wtedy inny kształt).
  Wyciszenie wszystkich wymagałoby łatania wywołań DOM Mermaida. **Pytanie do EHOS-a (użytkownika):** jeśli
  EHOS ma `report-uri`/`report-to` albo Datadog RUM zbiera `securitypolicyviolation`, każde wejście na ekran
  grafu wyśle kilkaset zgłoszeń. *1 października, sprawdzone w `eh-os` `c2ea39f`:* konsola nie ma `report-uri`,
  `report-to` ani RUM (`lib/ehos_web/router.ex`), a EHOS nie ustawia CSP aplikacjom klienckim. Zgłoszeń nie będzie,
  dopóki host sam ich nie włączy.
- **Sprawdzone w przeglądarce** (testy tego nie widzą): trzy diagramy z kolorami i układem jak bez polityki,
  żadna z 20 etykiet nie wystaje, przełączenie procesu i zmiana motywu bez pustego bloku w żadnej chwili, trzy
  arkusze przez cały czas, zepsuty diagram pokazuje zdanie w swoim bloku, a dwa pozostałe zostają.

**Przegląd (dwa równolegle, `pre-pr-review`).** Poprawione: Mermaid przed rysowaniem usuwa element o
identyfikatorze, który rysuje, więc rysowanie pod identyfikatorem bloku opróżniało diagram przy każdym
przerysowaniu, a po błędzie zostawiało pusty blok i obrazek błędu na dole strony — teraz nowy identyfikator na
rysowanie (bezpieczny dla selektora) i zdanie w bloku przy błędzie; pierwsze rysowanie mierzyło etykiety w foncie
strony (14 px), kolejne w foncie diagramu — teraz robocza kopia w ukrytym kontenerze w foncie diagramu; do
arkusza trafia tylko własny `<style>` Mermaida; `bindFunctions` jak w `run`; test źródła czyta też zbudowany
plik (`2bd8316`). Z przeglądu bezpieczeństwa **usterka sprzed EG3**: `<`, `>` i `#` w etykiecie Mermaid czytał jako
znacznik albo encję (`a<b`, `Faktura #12;`) — teraz encje Mermaida `#lt;`, `#gt;`, `#35;`, sprawdzone w
przeglądarce; karta stanu jednostki łamie linie po stronie renderera (`35e74ed`). Wstawianie SVG samemu nie
omija DOMPurify — `render` zwraca ten sam oczyszczony tekst, który `run` wstawiał. **Pominięte:** hałas w konsoli
(wyżej); nagłówek sandboxa nie chroni przed clickjackingiem (`frame-ancestors`) — celowo odwzorowuje politykę
EHOS-a, nie jest pełnym nagłówkiem utwardzającym.

### Przed E9 — decyzje użytkownika (28 września)

Przed budową asystent opisał na materiale, czego zapis „kontrakty od nowa z materiału” nie rozstrzygał, i zapytał o
cztery rzeczy. Wszystkie cztery odpowiedzi to propozycje asystenta:

- **Zakres: każdy rodzaj DSL-a raz, tam, gdzie materiał go niesie.** Cztery kontrakty z odbioru plus procesy, w
  których materiał naturalnie ma rodzaj, którego odbiór nie potrzebuje: deduplikacja P9 albo parowanie jako
  `domain_service`, R-07 („suma dnia według metody płatności”) jako read model i query, cron P1 TaxVision („kiedy
  zaczyna się miesiąc, sprawdź rejestry”) jako timer kalendarzowy, „Wszystko → Shugyo, event stream” jako
  `publish`, `visit_booked` (C-09 → E-14) z tożsamością generowaną. Kara za nieobecność, zaświadczenie, zamknięcie
  dnia, kadry i fakturowanie — poza zakresem. *Odrzucone:* cały materiał z sekwencją (osiem procesów Rehmedu i
  cały cykl TaxVision z szablonami i zastępstwami — kilka razy więcej kodu i przeglądu bez nowego sygnału dla
  DSL-a); tylko cztery z odbioru (rodzaje spoza odbioru sprawdzone wyłącznie na wymyślonych fiksturach).
- **Kontrakt na kontekst.** Jeden moduł na kontekst z materiału, nazwany jak kontekst: Rehmed według
  `30-contexts.md` (`Scheduling` CTX-01, `ClinicalDocumentation` CTX-03, `StatutoryReporting` CTX-04, `Settlement`
  CTX-05, `ExternalPayers` CTX-06), TaxVision według `03-ddd-architecture.md` §3–4 (Registry Watch, Accounting
  Month, Work Orchestration, Notifications). Proces przechodzący przez konteksty (wizyta: AGG-01 → AGG-02 → AGG-10)
  mieszka w kontrakcie, do którego należy jego obietnica, i włącza cudze zdarzenia przez `consumes`/`include`.
  Nazwy `ClinicalVisit` i `PayerSettlement` z odbioru zostają nazwami procesów, nie modułów. *Odrzucone:* kontrakt
  na jednostkę (`Visit`, `VisitDocumentation`, `MedicalEventReport`…: mniejsze pliki i rekompilacje, ale więcej
  modułów i `consumes` wewnątrz jednego kontekstu, a mapa kontekstów i graf systemu pokazywałyby moduły zamiast
  kontekstów z materiału).
- **Trzy PR-y, każdy od poprzedniego, przegląd po każdym:** **E9a — Rehmed, wizyta** (domena od nowa, rezerwacja,
  dokumentacja, zgłoszenie P1 z obietnicą spełnianą przez `or_else`, rozliczenie wizyty od nowa, test „zmiana pola
  konsumowanego psuje obie strony”); **E9b — Rehmed, płatnik** (DCB i wyścig); **E9c — TaxVision** (kontrakty,
  przepięcie kodu aplikacji — `Api.open_month` przez dispatch, `Tasks` i `Notifications` jako polityka i efekt,
  `identity_seam_test` i `periods_test` — i koniec kontraktów v1 w sandboxie). Rehmed pierwszy, bo jego domena już
  jest v2, a trzy z czterech punktów odbioru są o Rehmedzie. *Odrzucone:* dwa PR-y, Rehmed i TaxVision (PR
  Rehmedu z pięcioma kontraktami naraz nie daje się przeczytać z uwagą); TaxVision najpierw (kolejność starego
  akapitu E9).
- **`event-name-with-aggregate-prefix` na `accounting_month_opened` zostaje.** Nazwa zdarzenia i agregatu są z
  warsztatu (`AccountingMonthOpened`, agregat `AccountingMonth`); zmiana nazwy jednostki na `:month` tylko przenosi
  ostrzeżenie na `month_closed`. Ostrzeżenie jest prawdziwe i zostaje jako ustalenie o regule. *Odrzucone:* reguła
  pomija zdarzenie z `source:` wskazującym materiał (nowe zachowanie reguły, żeby wyciszyć jedno ostrzeżenie);
  nazwa po ESDM, `opened` (łamie „nazwy zdarzeń z warsztatu” z `CLAUDE.md`).

Rozstrzygane przez asystenta przy budowie, z zapisem w „co wyszło” każdej części: które pola są osobowe (z tabel
retencji destylacji), kształt `registry_discrepancy_detected` (E9c), pozycje 6–9 z „Po EL2 — proza, którą da się
sprawdzać” — każda wchodzi tylko, jeśli prawdziwy kontrakt jej potrzebuje.

### E9a — co wyszło (28 września)

Na `dsl-v2/e9-visit` (od `main` = `f2a54bd`, po rebase od `ff4f279` — na `main` doszedł `VISION.md`), niewypchnięte. Siedem commitów budowy po zapisie decyzji (`d34c10b`):
domena od nowa z `30-contexts.md` (`97396f2`), Scheduling (`05ec3b5`), ClinicalDocumentation (`2d5e76e`),
StatutoryReporting z procesem `clinical_visit` i usunięciem v1 `ClinicalVisit` (`b833982`), Settlement w miejsce
`VisitSettlement` (`250e739`), uprawnienie do nagrania w silniku (`799d586`), host i testy odbioru (`7058167`).
Brama zielona na każdym commicie. Sandbox 54 → **81** testów, silnik 1219 → **1221**; `check` sandboxa 0 / 12 / 19 →
**0 / 22 / 11** (każda linia wyjaśniona w opisie commita, który ją wprowadził), silnika bez zmian.

**Co jest.** Cztery kontrakty v2 Rehmedu, każdy na kontekst z mapy klienta, z implementacjami i scenariuszami:
- `Scheduling` (CTX-01, AGG-01) — tożsamość generowana (`book_visit`, C-09), obserwacje ludzi (`patient_arrived`,
  `visit_completed`);
- `ClinicalDocumentation` (CTX-03, AGG-02) — ograniczenie komendy (DEC-19) i process manager doby (decyzja klienta z
  13 sierpnia);
- `StatutoryReporting` (CTX-04, AGG-10) — `process :clinical_visit` przez trzy konteksty, obietnica dwóch dni od
  wyjścia pacjenta z `or_else`, polityka P-07, efekt wołający P1, odpowiedzi rejestru nagrywane przez aktora
  systemowego;
- `Settlement` (CTX-05, AGG-03) — przekazanie według K5-20, read model i query R-07.

Domena ma trzy subdomeny, pięć kontekstów, sześć relacji z mapy, słownik per kontekst z tłumaczeniami, podmiot
`patient`, encję `service` i system zewnętrzny `p1`. Pierwsze pola osobowe sandboxa (PESEL, kody ICD), więc sandbox
dostał klucz główny na środowisko w `config/dev.exs` i `config/test.exs`.

**Odbiór E9, części o wizycie:** obietnica `clinical_visit` spełniona przez `or_else` na przebiegu zasianym
dispatchem z credentialami (`rehmed_clinical_visit_test`, próba odwrotna: bez `or_else` czerwony), razem z
drogą przez efekt, naruszeniem po dwóch dniach i pogonią za dokumentacją; zmiana pola zdarzenia konsumowanego psuje
kontrakt subskrybenta (X9 przy obu scenariuszach, ze wskazaniem zdarzenia wydawcy) i jego politykę (nieznany klucz),
a pole nieużywane i pole zdarzenia, którego nikt nie konsumuje, nie dotykają żadnej strony
(`rehmed_consumed_field_change_test`, na kopiach prawdziwych plików; na prawdziwym drzewie najpierw pada polityka, po
jej poprawie L3 zgłasza te same cztery X9). Wyścig DCB — E9b.

**Uprawnienie do nagrania z credentialem, zbudowane w E9a** (decyzja z 27 września w „Po E8 — kolejność
zmieniona”; do E9 `record/3` odrzucał każdy credential): `Model.capabilities/1` daje każdemu zdarzeniu z
`recorded_by:` uprawnienie `<domena>.<zdarzenie>` rodzaju `:record` z rolami aktorów z `recorded_by:`, `record/3`
pyta `Authorizer` jak dispatch komendy, `EhOsContract.Plug` serwuje `POST /records/<uprawnienie>`, D14 obejmuje
nagrania. Mechanika asystenta w pierwszej wersji: role jak przy `by:` komend, także aktorzy systemowi —
**zmienione po przeglądzie** decyzją użytkownika (niżej): uprawnienie i role tylko z ludzi. Linia w CHANGELOG pakietu. Manifest EHOS-a pozna rodzaj w E10.

**Ustalenia o bibliotece:**
1. **F5 nie pozwala trzymać w stanie agregatu pola osobowego, którego podmiot poznaje się z pierwszym
   zdarzeniem.** Bramka DEC-19 najpierw siedziała w stanie dokumentacji (kody z `diagnosis_coded`); weszła jako
   ograniczenie zamknięcia, które niesie kody. Dla dokumentacji to naturalne, ale agregat, którego pacjent jest
   znany dopiero z pierwszego zdarzenia, nie ma drogi do stanu z danymi osobowymi.
2. **Inwariant o tym, kto wydaje komendę, jest niewyrażalny.** AGG-02 niezmiennik 3 („zamyka tylko specjalista,
   który wykonał wizytę”, egzekwowany dziś) wymaga, żeby decyzja widziała aktora; widzi komendę i stan, a
   uprawnienie mówi tylko „jakiś specjalista”. To samo pytanie co odrzucona opcja przy „miesiąc otwiera księgowa
   tej firmy” (27 września) — wraca z TaxVision w E9c.
3. **Odpowiedź query nie jest sprawdzana względem typów wiersza.** `sum()` w Postgresie dało `Decimal` w polu
   `:money` (`:integer`), a silnik to przepuścił; wyszło w scenariuszu `answers` tylko dlatego, że porównuje
   wartości. Do rozważenia: kontrola typów wiersza przy odpowiedzi, jak przy komendzie.
4. **Kolejność kompilatorów:** zmiana pola konsumowanego zdarzenia w prawdziwym drzewie pokazuje najpierw błąd
   implementacji (kompilator Elixira pada przed `compile.eh_os_contract`), a dopiero po jego poprawie błąd kontraktu
   (L3). Obie strony są wskazane, ale nie naraz.

**Ustalenia o materiale:**
- **Mapa kontekstów nie ma relacji scheduling → statutory reporting**, a termin ustawowy liczy się od faktu ze
  scheduling (`visit_completed`). Ostrzeżenie `cross-bounded-context-reference-without-mapping` zostaje prawdziwe;
  relacji, której klient nie narysował, nie dopisuję.
- **Pliki `10`/`20`/`30` modelu Rehmedu nie mają poprawek K5/K6.** Rozliczenie idzie za K5-20 (przekazanie tylko po
  zmianie zakresu, dwa niezmienniki) i odpowiedzią makiety na H177 (rozliczenie otwiera obecność pacjenta, cena
  zamarza przy zamknięciu, więc `total` jest w `close_settlement`); H177 jest otwarte do passu 2 i makieta sama mówi,
  że przeczy DEC-18. F1 z v2 §16 (skąd kwota) ma więc teraz odpowiedź z materiału, tymczasową.
- **`p1_reporting_not_required` jest nasze** — model nie ma faktu dla wizyty niezgłaszanej („absence by filter”), a
  obietnica jest per przebieg; bez niego każdy masaż naruszałby ustawę.
- Zostają poza zakresem, z powodem w moduledocach: potwierdzenia i telefony (U-10), reguły zasobów, PESEL płatnika
  (E9b), wizyta dwuosobowa (H35), ponowienia P1 (S-46), zamknięcie dnia.

**Pozycje 6–9 z „Po EL2”** — żadna nie była potrzebna w E9a: query R-07 nie ma ograniczenia prozą (6); P1 nie ma
podanego czasu odpowiedzi (7); efekt wysyłki jest sprawdzony testem hosta, bez scenariusza z zaślepką (8); każde
zdarzenie i komenda E9a ma `source:` z identyfikatorem materiału (9). Wracają przy E9b/E9c, jeśli tam będą potrzebne.

**Poza zakresem, zapisane:** dokumentacja pakietów używa `Rehmed.Contracts.VisitSettlement` jako przykładu z v2 §4.5,
nie jako odwołania do sandboxa — do E11, który przepisuje dokumentację; `CLAUDE.md` mówi, że Rehmed „nie ma tu kodu
i nie będzie miał” — nieprawda od E6 (moduledoc `Rehmed` poprawiony), poprawka `CLAUDE.md` należy do E11. Komendy
wydawane tylko przez reakcje (bez `by:`) mają uprawnienia bez ról i Plug je serwuje — jak dotąd; EHOS nie nada
uprawnienia bez roli.

Weryfikacja w przeglądarce (baza dev, CSP EHOS-a): pięć diagramów na `/graph`, mapa kontekstów z sześcioma
relacjami, system z czterema krawędziami `consumes`, `clinical_visit` z trzema torami, obietnicą i `or else`; żadna
etykieta nie wystaje; w konsoli tylko znane blokady stylu z pomiaru Mermaida.

**Przegląd E9a** (dwa równolegle na `origin/main..572cd6f`, po rebase).

*Decyzje użytkownika* (pytanie przed poprawką, bo host widzi kształt):
- **Uprawnienie tylko dla tego, co robi człowiek** (`9e22beb`). Po E9a każde zdarzenie z `recorded_by:` dostało
  uprawnienie, także `rehmed.p1_report_sent` z jedyną rolą systemową `rehmed.p1_integration`, a komenda reakcji
  (`queue_p1_report`, bez `by:`) miała uprawnienie bez ról, które router serwował. Credential z omyłkowym nadaniem
  mógłby nagrać „wysłano do P1” bez wysyłki — obietnica ustawowa zielona na ekranie, który ma pokazać naruszenie —
  albo zakolejkować zgłoszenie z dowolnym PESEL-em. Teraz `Model.capabilities/1` daje uprawnienie tylko deklaracji,
  której `by:`/`recorded_by:` nazywa aktora `:human`, role tylko z ludzi; reszta nie ma uprawnienia, credential
  dostaje `:missing_capability`, Plug 404. *Odrzucone:* poprawić tylko nagrania (komendy reakcji to ta sama luka,
  starsza niż E9a); zostawić i zapisać ryzyko (bezpieczeństwo oparte na tym, że EHOS nie nada).
- **`:not_created` przez HTTP to 404 `{"error": "not_created"}`** (`c12ece7`), nie 403: nagranie przyjścia na
  wizytę, której nikt nie umówił, to brak wizyty, nie brak uprawnienia. *Odrzucone:* 422 (treść żądania jest
  dobra); zostawić 403.

*Poprawione przez asystenta, z testem i próbą odwrotną:* drugie zamknięcie kliniczne wysyłało drugie zgłoszenie do
P1 — niezmiennik `closed_clinically_once` (`d59ab66`, AGG-02 stan końcowy); zamknięte rozliczenie przyjmowało
płatność i drugie zamknięcie, dzień korekty się przesuwał — niezmiennik 4 AGG-03,
`closed_settlement_changes_only_by_correction` (`89dc99a`). Słowem (`9b7306d`): notka z datą w v2 §11, opisy
pakietów, moduledoci `Rehmed` i `Rehmed.Contracts`, polszczyzna w moduledocach i komentarzach, słabsza asercja
testu pola.

*Bez zmiany:* `String.to_existing_atom` w query R-07 (tabelę pisze tylko projekcja z enumu); R-07 nie czyta korekt
(materiał: R-07 czyta E-55 i E-83, korekty należą do zamknięcia dnia, poza E9); query i nagranie o jednej nazwie w
jednym kontrakcie przepuszcza N1, ale odrzuca D14 w L3 (warunek `kind != first_kind`, dodany w E9a); numer prawa
wykonywania zawodu jawny — rejestr KIF jest publiczny, decyzja zapisana tutaj.

*Pominięte, jako ustalenia:*
- **`or_else` obietnicy P1 przychodzi dopiero z zamknięciem klinicznym**, więc masaż zamknięty po trzech dniach
  wygląda na naruszenie ustawy, choć niczego P1 nie jest winien. Flaga jest znana przy rezerwacji, ale nie leży na
  fakcie, od którego liczy się obietnica (`visit_completed`), a zwolnienie przed `from` nie wiadomo czy się liczy.
  Wraca przy E9b/E9c albo jako pytanie o kształt obietnicy („warunek na `from`”).
- **Dzień R-07 i dzień zamknięcia to dzień UTC**, nie Warszawy — sandbox nie ma bazy stref czasowych; prawdziwy
  host liczy dzień w strefie placówki.
- **Obserwacje nie mają decydenta** (D6): `visit_completed` da się nagrać po odwołaniu albo dwa razy, a pogoń za
  dokumentacją rusza po `visit_completed` nagranym już po zamknięciu klinicznym i zakłada zadanie dla
  udokumentowanej wizyty.
- **Specjalista podaje flagę P1 na zamknięciu** (`p1_reported`), więc przez HTTP może ją fałszować — to samo
  ustalenie co niewyrażalny niezmiennik „zamyka ten, kto wykonał”: decyzja regulacyjna na polu od wołającego.
- Dokumentacja pakietów z przykładem `VisitSettlement` — E11.

### Przed E9b — decyzja użytkownika (28 września)

Zapisy rozstrzygały prawie wszystko: niezmiennik i kształt DCB (v2 §4.6), menedżer przy fakturze (`C-49` → `A-05`,
14 sierpnia), `cadence {1, :month}`, relacja CTX-05 → CTX-06 (customer–supplier, *„which visits a payer owes for”*
w `30-contexts.md`). Nie rozstrzygały jednego: **skąd kontekst płatników wie, że wizyta jest wykonaną wizytą
płatnika w danym okresie** — płatnika nie niosło żadne zdarzenie sandboxa. Pytanie na przykładzie: pani Anna ma 12
września fizjoterapię w wariancie LuxMed (`H99`), recepcja zamyka wizytę bez płatności, a 1 października menedżerka
wystawia fakturę LuxMed za wrzesień — skąd `ExternalPayers` wie, że wizyta Anny należy do „LuxMed, wrzesień”?

- **Settlement mówi** (propozycja asystenta, wybrana): przy zamknięciu wizyty z płatnikiem Settlement emituje
  **nasze** zdarzenie z `payer_id`, `period_id` i `visit_id` (jak `p1_reporting_not_required` w E9a — model nie ma
  faktu na to, co płynie przez CTX-05 → CTX-06), a DCB konsultuje je przez `match:`, więc czyta tylko „LuxMed,
  wrzesień”. *Odrzucone:* **E-106 z warsztatu** („Podzielono rachunek między płatników”, `C-61`) — nazwa z
  warsztatu, ale znaczy wizytę mieszaną, a wizyta w całości na płatnika nie jest podziałem; **DCB czyta
  Scheduling** (`visit_booked` z płatnikiem i `visit_completed` przez `where:`) — same nazwy z warsztatu, ale
  boundary czyta każdą wizytę każdego płatnika, więc każde wyjście pacjenta w klinice jest konfliktem przy fakturze,
  a relacji Scheduling → płatnicy nie ma na mapie klienta.

### E9b — co wyszło (28 września)

Na `dsl-v2/e9-payer` (od `main` = `06c6e11` (po rebase od `451d068`)), niewypchnięte. Trzy commity budowy po zapisie decyzji (`b0770e7`):
domena i obciążenie płatnika w Settlement (`875cd00`), `ExternalPayers` w miejsce v1 `PayerSettlement` (`cb1e21e`),
testy odbioru na bazie z commitami (`31e8f15`). Brama zielona na każdym commicie. Sandbox 85 → **95** testów, silnik
bez zmian (1222); `check` sandboxa 0 / 22 / 11 → **0 / 24 / 8** (każda linia wyjaśniona w opisie commita), silnika bez
zmian.

**Co jest.**
- Domena: kontekst `external_payers` (CTX-06, generic), relacje z mapy — customer–supplier settlement → external
  payers i anticorruption layer od systemu płatnika (`X-02`–`X-04` jako jeden `external`, trzy konfiguracje).
- Settlement: `close_settlement` niesie opcjonalnie `payer_id` i `period_id` i przy wizycie z płatnikiem emituje obok
  zamknięcia `visit_charged_to_payer` (nasze, decyzja wyżej); płatnik bez okresu i odwrotnie — ograniczenie komendy.
- `Rehmed.Contracts.ExternalPayers` (AGG-11): `dcb :payer_period`, tożsamość `[:payer_id, :period_id]`, konsultuje
  `visit_charged_to_payer` po obu polach; komendy `C-48` (recepcja, `S-58`), wykluczenie z makiety (menedżer, z
  powodem) i `C-49` (menedżer); niezmienniki: faktura dopiero, gdy każda obciążona wizyta jest oznaczona u płatnika
  albo wykluczona, i zafakturowany okres się nie zmienia. Proces `payer_settlement` z `accountable: :manager` i
  `cadence {1, :month}`.

**Odbiór E9, część o DCB** (`rehmed_payer_period_race_test`, na `Taxvision.CommitRepo` — osobna baza z commitami,
tworzona od nowa przed każdym przebiegiem, jak `EhOsContract.CommitRepo` w silniku):
- **deterministycznie**: transakcja trzyma blokadę dopisu, faktura czyta boundary i czeka; pod blokadą recepcja
  zamyka wizytę Bena; faktura trafia na przesunięty boundary, decyduje od nowa i jest odrzucona;
- **pod obciążeniem**: dziesięć wizyt zamykanych i oznaczanych naraz, menedżer ponawia fakturę — jedyna faktura ma
  każdą wcześniej obciążoną wizytę oznaczoną;
- **plan sprawdzenia konfliktu** (złapane zapytanie magazynu, `EXPLAIN` z jego parametrami, po `ANALYZE`): `Index
  Scan using eh_os_contract_events_pkey`, `position > head`, żaden inny indeks.
- Próba odwrotna: z warunkiem DCB wyłączonym w magazynie faktura wychodzi z nieoznaczoną wizytą Bena, a test obciążenia
  znajduje dziesięć obciążonych i żadnej oznaczonej przed fakturą.

**Ustalenia o bibliotece:**
1. **Plan sprawdzenia konfliktu zależy od statystyk.** Na świeżej tabeli (bez `ANALYZE`) planner przyjmuje domyślną
   selektywność `position > head` i przy dwóch elementach zapytania (własne zdarzenia boundary i konsultowane)
   wybrał bitmapę po indeksach typu — konsultowany typ szedł po indeksie **samego `type`**, bez ograniczenia pozycją,
   czyli czytał całą historię tego typu. Po `ANALYZE` — zakres klucza głównego. Test silnika tego nie widział, bo jego
   zapytanie ma jeden element. Indeks `(type)` jest pozostałością v1 (v2 §10.3 ma tylko `(type, position)`). Do
   rozważenia przy pomiarze: skasować `(type)` albo wymusić zakres w kształcie zapytania; tabela pod autovacuum ma
   statystyki, więc w produkcji to raczej świeża baza po imporcie.
2. **Agregat nie widzi faktów innego kontekstu, więc płatnik i okres przychodzą z komendą.** Rozliczenie otwiera się
   przy obecności pacjenta i nie ma drogi do płatnika z rezerwacji bez własnego zdarzenia (polityka albo process
   manager — dwie deklaracje więcej). To trzecie pole decyzyjne od wołającego po fladze P1 i „zamyka ten, kto
   wykonał” (E9a): okres ustala host (miesiąc wizyty), a boundary mu ufa.
3. **Graf kontraktu nie rysuje `consults`.** W `--contract Rehmed.Contracts.ExternalPayers` konsultowane
   `visit_charged_to_payer` wisi jako węzeł bez krawędzi; w procesie jest dołączone i widać je w etapie `charging`.
   Krawędź „boundary czyta” — do EG, jeśli ma być widać, na czym boundary decyduje.
4. `event-without-consumer` ostrzega o własnych zdarzeniach boundary czytanych tylko przez jego decyzję — tak samo jak o
   zdarzeniach agregatu czytanych tylko przez `evolve`, więc spójnie; zostaje.

**Ustalenia o materiale:**
- **Makieta (K1, `51-mock.md` §4.8) zastąpiła „wystaw fakturę” eksportem i ręcznym „oznacz jako zafakturowane”**
  (`S-121`, fakturowanie poza zakresem, `H62`). `C-49`/`E-87` zostają nazwami z katalogu i znaczą to oznaczenie z
  numerem faktury zrobionej gdzie indziej.
- **Relacja do systemu płatnika jest przekraczana przez człowieka**, więc `orphan-context-mapping` na anticorruption
  layer zostaje prawdziwe (v1, ustalenie 4: bez `depends_on`, bo niedostępności nic nie zobaczy).
- Poza zakresem, z powodem w moduledocu: rejestracja u płatnika przed wizytą (`E-85`, `C-47`, PESEL — `H159`),
  przywrócenie wykluczonej wizyty, wizyta obciążona po fakturze okresu (fakt z Settlement nie da się tu odrzucić —
  trafia poza zafakturowany okres), `H47`, `H38`.

**Pozycje 6–9 z „Po EL2”** — żadna nie była potrzebna: boundary nie ma ograniczenia prozą (6), płatnik nie ma czasu
odpowiedzi (7), bez efektu (8), każda deklaracja ma `source:` (9).

W przeglądarce (baza dev, preview `eh_os_contract_host`): mapa kontekstów z płatnikami i systemem płatnika, proces
`payer_settlement` z trzema etapami, żadna etykieta nie wystaje.

**Przegląd E9b** (dwa równolegle na `origin/main..cdbecf2`, potem dwa na poprawkach `cdbecf2..f21512a`). Sandbox 95 → **99** testów, `check` bez zmian (0 / 24 / 8).

*Poprawione przez asystenta, z testem i próbą odwrotną:*
- **`ExternalPayers` nie był za drzwiami hosta** (`3f898de`): trzy uprawnienia bez wejścia, a test D-34 zielony, bo
  chodził tylko po czterech starszych kontraktach; teraz po pięciu i na starym routerze pada.
- **Oznaczenie i wykluczenie brały dowolną wizytę** (`edd4fa1`): literówka, wizyta innego płatnika albo zły miesiąc
  trafiały na fakturę, a jedna wizyta dawała się oznaczyć dwa razy albo oznaczyć i wykluczyć — niezmiennik
  `only_a_charged_visit_is_marked_or_excluded`.
- **Faktura za okres bez żadnej oznaczonej wizyty** (`6ffe85b`) zamykała miesiąc przed pierwszym zamknięciem wizyty i
  cały miesiąc zostawał niezafakturowany — niezmiennik `an_invoice_covers_a_marked_visit`; test obciążenia sprawdza
  teraz, że przed fakturą była obciążona wizyta, więc nie przejdzie na fakturze sprzed wyścigu.
- **`reset!` repo z commitami** (`c0f2c4d`) kończył się `MatchError`, gdy inny przebieg trzymał bazę; teraz mówi
  dlaczego. Pula 20 → 12: brama dostała `too_many_connections`, gdy inny worktree puszczał testy silnika (Postgres ma
  100 połączeń, repo z commitami silnika bierze 60).
- **Wizyta mieszana** (`ed32f39`, dopięte po drugim przeglądzie): scenariusz `P-31` z dodaną usługą, przekazaniem i
  płatnością pacjenta. **`total` znaczy dwie rzeczy** — przy płatnościach to ich suma (przy wizycie mieszanej część
  pacjenta), bez płatności cena, którą pokrywa ktoś inny; komentarz mówi teraz oba, a kształt jest z E9a
  (`visit_closed_without_payment` niesie pełną cenę). Kto czyta `total` jako wartość wizyty, zaniży każdą mieszaną.
- **Jedna nazwa bazy z commitami dla wszystkich worktree** (`01c225e`, drugi przegląd): dwa nakładające się przebiegi
  łamały się nawzajem (drop między create a migrate drugiego, te same płatnicy z `System.unique_integer` w dwóch VM);
  baza nazywa się teraz według checkoutu.

*Pominięte, jako ustalenia:*
- **Plan sprawdzenia konfliktu bez statystyk** (ustalenie 1 wyżej) — skasowanie indeksu `(type)` to migracja, którą
  wykonuje host, więc decyzja użytkownika; test planu sprawdza stan po `ANALYZE`.
- **Płatnik i okres od wołającego tworzą boundary, którego nikt nie zafakturuje**, gdy przyjdą w złym kształcie
  (`"2026-9"`, spacja w identyfikatorze): wizyta cicho wypada z „LuxMed, wrzesień”, a niezmiennik tam dalej trzyma.
  Format okresu to inwariant wartości — rodzaj zostawiony dla E9c; do tego ustalenie 2 wyżej.
- **Faktura przed końcem miesiąca** — kalendarza decyzja nie widzi (bez zegara w decyzji); ekran miesięczny jest
  po weryfikacji danych (`S-60`).
- **Pacjent płaci całość, a zamknięcie wskazuje też płatnika** — wizyta jest obciążona dwa razy; żadne zdarzenie nie
  niesie kwoty płatnika, więc nic tego nie zauważy.
- **`reason` wykluczenia nie jest osobowy** — zdarzenie nie zna pacjenta, więc nie ma podmiotu, pod którym dałoby się
  go zaszyfrować; uwaga `free-text-not-personal` zostaje.
- **Każda komenda boundary czyta i konfliktuje na całym okresie**: oznaczenie przy biurku trafia na konflikt z każdym
  równoległym zamknięciem wizyty tego płatnika w tym miesiącu, a dispatch ponawia trzy razy — test obciążenia
  potrzebuje własnego ponawiania. `consults` jest per boundary, nie per komenda; do rozważenia w bibliotece.
- Stan jako listy, nie zbiory — po niezmienniku bez duplikatów, rozmiar to liczba wizyt płatnika w miesiącu.
- **Oznaczenia nie da się cofnąć, a miesiąc z samymi wykluczeniami się nie kończy** (drugi przegląd): pomyłkowo
  oznaczona wizyta trafi na fakturę, a okres bez oznaczonej wizyty nie ma faktury ani innego zakończenia (v1 miał
  „zamknięto okres bez faktury”). Obie to następne komendy, nie nowy rodzaj — zapisane w moduledocu.

### Przed E9c — decyzje użytkownika (28 września)

Zapisy rozstrzygały konteksty (`03-ddd-architecture.md` §3–4: Registry Watch, Accounting Month, Work Orchestration,
Notifications), kolejność polityk (§5: cron → sprawdzenie rejestrów → otwarcie miesiąca → taski → powiadomienia; §5 i
§4.5 wygrywają z diagramem §3.1 z `02`, na którym taski stoją przed otwarciem) i nazwy zdarzeń (`02` §3.1, §10). Nie
rozstrzygały trzech rzeczy; asystent zapytał na przykładzie firmy c-1 i sierpnia:

- **Kto otwiera miesiąc: księgowa ręcznie** (`open_month` ze `scope: :company_id`, obok polityki z materiału, która
  otwiera miesiąc po zgodnej weryfikacji). Wybór użytkownika wbrew propozycji asystenta. *Odrzucone:* `scope` na
  „Ponów weryfikację” i otwarcie wyłącznie polityką, jak w materiale (propozycja asystenta). Skutek w mechanice
  (asystenta): ręczne otwarcie ma sprawdzić zgodność rejestrów, a agregat nie widzi faktów Registry Watch — więc
  miesiąc jest boundary `[company_id, period_id]` konsultującym wynik weryfikacji; v2 §2 wymienia „opening a month by
  hand” jako przypadek DCB.
- **Identyfikator okresu to nazwa „2026-07”**, pilnowana inwariantem wartości w domenie (propozycja asystenta,
  wybrana). Timer kalendarzowy P1 wylicza następny okres sam, bez bazy; tabela okresów zostaje źródłem dat; zamyka też
  ustalenie z E9b (zły format okresu tworzy boundary, którego nikt nie zafakturuje). *Odrzucone:* UUID jak dotąd
  (timer musiałby pytać bazę, więc comiesięczne sprawdzenie zlecałby harmonogram hosta, a timer kalendarzowy
  zostałby bez przykładu z materiału). Skutek w mechanice: wartość o bazie `:id` musi być tagiem, żeby boundary
  dopasował zdarzenia po okresie — zmiana w silniku.
- **Dwie części** (propozycja asystenta, wybrana): **E9c-1** — domena, Registry Watch, otwarcie miesiąca, `scope`
  komend, wejście HTTP, `identity_seam_test` i `periods_test` od nowa, koniec kontraktów v1; **E9c-2** — Work
  Orchestration, Notifications, parowanie jako `domain_service`, `publish` do Shugyo, numer KSeF z `issued_by`. Każda
  część osobnym PR-em z przeglądem. *Odrzucone:* jeden PR (diff około dwa razy większy niż E9a).

### E9c-1 — co wyszło (28 września)

Na `dsl-v2/e9-taxvision` (od E9b = `11084e0`), niewypchnięte. Trzy commity budowy po zapisie decyzji (`c7012a1`):
wartość o bazie `:id` jako identyfikator w silniku (`f2e385d`), `scope` komend w silniku (`1c6228f`), TaxVision od nowa
i koniec v1 w sandboxie (`a0e6faa`). Brama zielona na każdym commicie. Sandbox 99 → **111** testów, silnik 1222 →
**1239**; `check` sandboxa 0 / 24 / 8 → **0 / 25 / 9**, silnika 0 / 65 / 21 → **0 / 67 / 21** (dwie linie nowej
fikstury `DispatchRig.Transfer`).

**Co jest.**
- **Silnik, `scope` komend** (D10 dla komend, pytanie z v2 §19 zamknięte): `command …, by:, scope: :pole` — pole
  komendy (tożsamość jednostki albo zadeklarowane, wymagane), komenda ma `by:`, każdy aktor z `by:` niesie wymiar,
  pole nie jest osobowe (F7); dispatch i `EhOsContract.Plug` pytają `Authorizer` z wartością pola;
  `Model.capabilities/1` daje uprawnieniu `scope:`. Linia w CHANGELOG pod „a host has to act”.
- **Silnik, wartość o bazie `:id`**: pole typu `value :period, :id` jest tagiem i dla X6 tym samym typem co `:id`;
  `Key.tag_field?/2` bierze wartości domeny. Tożsamość jednostki zostaje zwykłym `:id`, więc inwariant pilnuje pól
  typowanych wartością (np. okresu w komendach Registry Watch), a nie tożsamości.
- **`Taxvision.Domain`**: Registry Watch (supporting) → miesiąc (core), księgowa ze `scope: [:company_id]`,
  integracja rejestrów, `value :period` z inwariantem RRRR-MM, `value :registry_difference`.
- **`Taxvision.Contracts.RegistryWatch`**: profil firmy, sprawdzenie (komplet danych), efekt pytający rejestry poza
  transakcją i nagrywający odpowiedź jako integracja, polityka porównania, process manager P1 z timerem
  kalendarzowym (miesiąc po zapisanym sprawdzeniu sprawdza następny okres, wyliczony z nazwy).
- **`Taxvision.Contracts.AccountingMonth`**: boundary `[company_id, period_id]` konsultujący werdykty Registry
  Watch; otwiera polityka (§5) albo księgowa tej firmy (`scope`), tylko po zgodnym ostatnim sprawdzeniu i raz;
  obietnica v1 (dwa dni albo rozjazd) jako `promise` z `or_else`.
- **Koniec v1 w sandboxie**: kontrakt v1, trzy handlery, `Taxvision.Api`, `Authorization`, `Identity` (token HMAC
  TaxVision), `RegistryCheck`, test przykładów v1. Wejście: `EhOsContract.Plug` pod `/api/taxvision` za credentialem
  EHOS-a. `identity_seam_test` od nowa (401, brak uprawnienia, poza firmą; D-34 dla obu kontraktów),
  `periods_test` od nowa (nazwa, następny okres, daty wiersza), test przebiegu (otwarcie sierpnia, blokada c-2 po
  wykreśleniu z VAT i odmowa ręcznego otwarcia, wrzesień sprawdzony przez timer miesiąc później, odmowa „2026-8”).

**Ustalenia o bibliotece:**
1. **Inwariant wartości nie sięga tożsamości.** Tożsamość jest wstrzykiwana jako `:id`, więc `open_month` dla
   „2026-7” przechodzi walidację i zostaje odrzucony dopiero niezmiennikiem miesiąca (brak zgodnego sprawdzenia).
   Bezpiecznie, ale format pilnuje tylko komend, które niosą okres jako pole. Do rozważenia: tożsamość typowana
   wartością.
2. **Agregat nie widzi faktów innego kontekstu — drugi raz** (po E9b): ręczne otwarcie miesiąca musiało być boundary.
   Ten sam kształt, co przy płatniku: kontekst, który decyduje na cudzym fakcie, to DCB albo pole od wołającego.
3. **Process manager bez `ends_on`** (`process-manager-without-ends-on`) jest tu prawdziwy: comiesięczne
   sprawdzenie trwa, póki firma jest klientem, a koniec współpracy nie jest w E9.

**Ustalenia o materiale:**
- **Kolejność §3.1 (`02`) i §5 (`03`) się różni** — taski przed otwarciem albo po nim; poszło za `03`.
- **Dane „w Abilii”, z którymi porównuje się rejestry, są w profilu firmy z onboardingu** (§4.1), którego E9 nie
  pisze; ukończenie profilu jest tu nagrane jako nasze.
- **Relacja Registry Watch → miesiąc jest na mapie bez typu** (strzałka z nazwami zdarzeń) — zapisana jako
  customer–supplier.
- `deadline {25, :day}` z v1 zdjęty: bez zdarzenia końcowego nie ma czego mierzyć, a 25. nikt z TaxVision nie podał.

W przeglądarce (baza dev, preview `eh_os_contract_host`): mapa kontekstów TaxVision, siedem diagramów na `/graph`,
proces `client` i boundary miesiąca, żadna etykieta nie wystaje.

**Przegląd E9c-1** (dwa równolegle na `11084e0..d44ff08`, potem po dwa na każdej rundzie poprawek). Sandbox 111 →
**120** testów, silnik 1239 → **1245**; `check` sandboxa 0 / 25 / 9 → **0 / 26 / 9** (`registry_check_logged` bez czytelnika, odkąd
pętla czyta potwierdzenie — czytelnikiem byłby read model „ostatnie sprawdzenie”, którego E9 nie pisze).

*Poprawione przez asystenta, z testem i próbą odwrotną:*
- **`scope` musi być jedną wartością i nie generowaną tożsamością** (`d4b369c`, aliasy w `e3f9c51`): lista
  `["b", "-7"]` przechodziła nadanie „b-7”, wartość złożona kończyła się 500, a `scope` na tożsamości generowanej przy
  `creates:` był `nil` dla każdego credentialu. Druga runda: alias wartości (`value :codes, {:list, :id}`, `value
  :home, :contact`) omijał obie reguły — L3 idzie teraz po aliasach.
- **X6 rozróżnia dwie różne wartości o bazie `:id`** (`042453a`): `:period` i numer faktury przechodziły jako ten sam
  typ; teraz równe są tylko te same typy albo wartość `:id` wobec zwykłego `:id`. Poprawiony też opis `Key`.
- **Źle wpisana wartość pola `scope` to brak wartości** (`297b1a9`): wyjątek w koderze zamiast odmowy, w komendach i —
  od E4 — w query. Skutek zamierzony: posiadacz nadania, który wyśle `company_id: 7`, dostaje 403 `outside_scope`, nie
  422 — kolejność „czy wolno, potem co jest nie tak” zostaje.
- **Pętla P1** (`644fd10`, potem `feb1953`): pięć minut awarii rejestrów 1. dnia zatrzymywało sprawdzanie na zawsze,
  ponowienie starszego miesiąca cofało pętlę, a ponowienie 5. dnia przesuwało wszystkie następne na 5. Pierwsza
  poprawka (najpóźniejszy okres, `at:` z nazwy) oddała sterowanie wpisowi księgowej: „2062-08” blokował pętlę do 2062,
  a pierwsze sprawdzenie marca we wrześniu odpalało miesiąc po miesiącu zaległe sprawdzenia. Teraz przebieg rusza na
  potwierdzeniu i ustawia następne na 1. dzień kolejnego miesiąca **od czasu potwierdzenia**, sprawdzając miesiąc,
  który się wtedy skończył; okres z komendy nie gra roli. Trzecia runda (`b022078`): liczenie „od teraz” gubiło
  miesiące — spóźniony timer (2 listopada) pomijał październik, ponowienie tuż po terminie, a przed zadaniem,
  przestawiało należny timer, a zegar innego węzła cofał termin. Teraz przebieg trzyma datę należnego sprawdzenia:
  pierwsze potwierdzenie ustawia 1. dzień następnego miesiąca, sprawdzenie miesiąca, którego ta data dotyczy,
  przesuwa ją o miesiąc **od niej samej**, a inne ponowienie jej nie rusza; spóźniony timer nadrabia tylko to, co
  przegapił. Do tego nowy niezmiennik: **sprawdza się tylko miesiąc zakończony do czasu komendy** (rozliczenie
  miesiąc w tył, WF 00:34:40) — „2062-08” jest odrzucany, zanim zapyta rejestry, więc nie otwiera miesiąca 2062-08.
  Czwarta runda (`7c67982`, jeden przegląd łączony): niezmiennik obejmował też sprawdzenie z timera, którego komendę
  stempluje zegar węzła, więc sekunda rozbieżności o północy odrzucała je i pętla stawała bez śladu; dotyczy teraz
  tylko ponowienia przez księgową. Pierwsze sprawdzenie nie nadrabia miesięcy sprzed siebie — celowo, po rundzie
  drugiej.
- **Resztki v1** (`bed5a87`, `533a9a3`): `Taxvision.Tasks` i `Notifications` bez handlerów, z UUID okresu; komentarz
  `setup` testu szwu; notka v1 w `Taxvision.Periods` na górze.

*Pominięte, jako ustalenia:*
- **Czy dane JDG w logu są osobowe** — forma prawna, status VAT i VIES oraz różnice dotyczą przy jednoosobowej
  działalności osoby fizycznej; v1 trzymał różnicę jako skrót (`retain: :hash`). Zostają jawne — decyzja niżej.
- **Brak limitu ponowień** — każde ponowienie pyta rejestry; limit jest sprawą hosta albo adaptera.
- **Aktor ze `scope` wydający komendę bez `scope`** — nic tego nie wyłapuje; kandydat na regułę L5 (E10).
- **Rejestry pytane `company_id`, nie NIP-em** — odziedziczone z v1; prawdziwy adapter potrzebuje NIP-u z profilu.
- **Jeden łańcuch timerów na firmę**: zadanie timera odrzucone po trzech porażkach albo zgubione przy `reconcile!`
  zatrzymuje pętlę do ponowienia przez księgową, a ponowienie późniejszego miesiąca przy zaległym timerze sprawdza ten
  miesiąc dwa razy — mechanika silnika (`TimerJob`), poza E9.
- **Ponowienie 1. dnia między 00:00 a 02:00 czasu polskiego jest odrzucane** (koniec miesiąca liczony w UTC) —
  odrzuca za dużo, nigdy za mało; ta sama granica co dzień R-07.
- **Północ w Warszawie to 22:00–23:00 UTC**: sprawdzenie tuż po niej ustawia termin za godzinę–dwie na ten sam
  miesiąc; sandbox nie ma bazy stref czasowych, jak przy dniu R-07.
- **Duplikacja** (`scope` komend i query w dispatchu i w D10; `one_value/2` obok `Key.base_type/2`) — do
  ujednolicenia przy E11. Scenariusze procesu managera zależą od epoki scenariuszy (styczeń 2026), co mówi komentarz.

### Po przeglądzie E9c-1 — decyzje użytkownika (28 września)

Asystent zapytał o dwie rzeczy, które przegląd zostawił użytkownikowi; odpowiedź: „zostaw jak jest”.
- **Dane JDG w logu zostają jawne** (forma prawna, status VAT i VIES, różnice). *Odrzucone:* pola osobowe szyfrowane
  pod firmą jako podmiotem (crypto-shredding po końcu współpracy); skrót różnicy jak `retain: :hash` w v1.
- **Indeks `(type)` zostaje** (ustalenie 1 z E9b: bez statystyk planner czytał nim historię typu). *Odrzucone:*
  skasowanie indeksu (migracja po stronie hosta); zakres wymuszony w kształcie zapytania sprawdzenia konfliktu.

### Przed E9c-2 — decyzje użytkownika (28 września)

Pytanie z refleksji użytkownika: kontrakty Rehmedu i TaxVision i tak wylecą z repozytorium biblioteki, więc jak
walidować implementację szybko i bez przepalania tokenów. Asystent pokazał na sandboksie, co jest tanie, a co
drogie: 48 scenariuszy to czyste funkcje (komenda wchodzi, zdarzenia wychodzą — bez bazy, HTTP i timerów), a
testy przebiegu (pętla P1, `identity_seam_test`, Plug) zjadły cztery rundy przeglądu, broniąc zachowania danych
testowych. Trzy propozycje asystenta, wszystkie przyjęte:

- **Po E11 kontrakty sandboxa przechodzą do testów pakietu jako fikstury akceptacyjne** (obok
  `UniversalityGate`): kontrakt ze scenariuszami i po jednym teście przebiegu na mechanizm silnika, nie na regułę
  domeny. Adaptery, HTTP i `Periods` nie muszą przeżyć. *Odrzucone:* osobne repozytorium przykładów (bez
  zgodności wstecz psułoby się przy każdej zmianie DSL-a, czyli drugie repozytorium do utrzymania); sandbox bez
  zmian.
- **E9c-2 węższe — tylko to, czego rodzaje DSL-a nie mają jeszcze na prawdziwym kontrakcie:** `domain_service`,
  `publish`, `issued_by` (w silniku są od EM/EL, sandbox nie używa żadnego) i polityka wydająca kilka komend
  naraz (silnik ją ma — klucz `…:<index>` — a każda polityka sandboxa wydaje jedną). *Odrzucone:* pełny zakres
  z „Przed E9c” — Work Orchestration i Notifications to agregat, polityka i efekt, które są już na prawdziwych
  kontraktach (5 / 3 / 2 razy), więc dodałyby modelowanie domeny bez sygnału dla biblioteki.
- **Przegląd kontraktów sandboxa jedną rundą**: pytanie, czy rodzaj trzyma się na materiale i czy silnik nie
  pęka; poprawność logiki domeny idzie do ustaleń, nie do kolejnych rund. Kod silnika, który E9c-2 zmieni, dalej
  dostaje pełny przegląd. *Odrzucone:* przegląd do skutku jak w E9c-1.
- **E9c-1 do `main` nowym PR-em** — #40 zmergował się do nieprzestawionej bazy `dsl-v2/e9-payer` (`dfc3451`), więc
  do `main` nie trafił; [#41](https://github.com/EmpoweredHouse/eh-os-contract/pull/41) to ta sama głowa `60324a5`.

**Gdzie wydaje kilka komend — wybór asystenta** (mechanika danych testowych). Nie taski z szablonu (Work
Orchestration): wymagałyby nowego kontekstu, agregatu szablonu i nazwy zdarzenia, której materiał nie ma (§4.5
publikuje `MonthlyTasksGenerated`, jedno zdarzenie, a dla `CreateTask` żadnego). Zamiast tego P6 (`02` §10): po
wgraniu wyciągu lista obrotów, a dla każdego obrotu dopasowywanie — na tym samym przepływie co `domain_service`
(parowanie, P7) i numer KSeF, z nazwami z `02` §3.3.

### E9c-2 — co wyszło (28 września)

Na `dsl-v2/e9-e9c2`, od E9c-1 (`60324a5`), niewypchnięte: zapis decyzji (`13c5d67`), budowa (`90925cc`), trzy
poprawki z przeglądu. Silnik bez zmian — wszystkie cztery rodzaje już tam były.
Sandbox 120 → **132** testy (scenariusze, przykłady usługi i wartości, test przebiegu); silnik 1245, web 45, auth 55;
`check` sandboxa 0 / 26 / 9 → **0 / 28 / 10**.

**Co jest.**
- **`Taxvision.Domain`**: kontekst Document Intake (supporting) i jego relacja customer–supplier do miesiąca
  (tabela `03` §3), system `:ksef` (`:inbound`) z aktorem integracji, `value :ksef_number, :id` z inwariantem
  formatu (NIP, RRRRMMDD, 12 cyfr szesnastkowych, suma kontrolna — format Ministerstwa Finansów, nie z
  warsztatu; samej sumy kontrolnej się nie liczy), `value :turnover`, `value :invoice`.
- **`Taxvision.Contracts.DocumentIntake`**: jedno zdarzenie, `invoice_pulled_from_ksef`, nagrywane przez
  integrację, z polem `ksef_number … issued_by: :ksef`. Bez implementacji: nikt tu nic nie decyduje.
- **`Taxvision.Contracts.AccountingMonth`**: boundary `:turnover_matching` `[company_id, period_id]` konsultujący
  faktury z KSeF; `ingest_bank_statement` (księgowa ze `scope`) daje `bank_turnover_list_created`; polityka
  `match_each_turnover` (P6) wydaje `run_matching` na każdy obrót; decyzja woła `domain_service :pairing`
  (`invoice_for/2`, dwie reguły z przykładami) i daje `turnover_matched_with_invoice` albo
  `turnover_without_invoice_flagged`; faktura paruje się raz. `publish :month_opened` jako
  `taxvision.accounting_month.opened.v1` dla Shugyo — relay to E12, więc na razie nic nie wychodzi.
- Test przebiegu (`taxvision_matching_test.exs`): faktura z KSeF, wyciąg z dwoma obrotami, jeden sparowany,
  drugi oznaczony; numer bez sumy kontrolnej nie zostaje nagrany. `identity_seam_test` dostał wejście
  `ingest_bank_statement` — D-34 (każde uprawnienie ma wejście, które go odmawia) złapał jego brak przy pierwszej
  bramie. Próby odwrotne: polityka wydająca jedną komendę,
  parowanie zwracające zawsze `nil` i faktura parująca się dwa razy — każda kładzie co najmniej jeden test.

**Ustalenia o bibliotece:**
1. **Kontrakt tylko z nagrywanymi zdarzeniami nie ma czego implementować**, a `contract-without-implementation`
   mówi o nim „nothing of it can be dispatched, and its report is of a process nobody runs” — choć integracja
   do niego nagrywa i proces biegnie. Kandydat na zawężenie reguły w E10 (nie zgłaszać, gdy każde zdarzenie
   ma `recorded_by:`).
2. **Pusty agregat i `@impl`**: implementacja agregatu bez stanu i komend nie ma callbacku `evolve`, więc moduł
   z samym `use` jest zbędny, a z `evolve` daje ostrzeżenie kompilatora. Zgodne z (1), do opisania w
   `docs/contract.md` przy E11.
3. **Nagranie z wartością łamiącą inwariant to `{:error, {:invalid, …}}`**, nie wyjątek — jak przy komendzie;
   test to przypina.
4. **Przykłady usługi domenowej z listą wartości są rozwlekłe** (mapa na każdą fakturę w każdym przykładzie), ale
   działają; typy i inwarianty wartości w przykładach są sprawdzane.
5. `publish` bez relaya jest dziś deklaracją sprawdzaną tylko przy kompilacji; czytelnik (relay i `Bus`) jest w E12.

**Ustalenia o materiale:** margines dni między fakturą a płatnością jest „kilku dni” bez liczby (BANK); pominięty
razem z parowaniem jednego obrotu z wieloma fakturami i fakturą, która przychodzi po obrocie (P7 „on-going”).

**Nowe linie `check`:** `event-without-consumer` dla obu wyników dopasowywania — czytelnikiem byłyby wyjaśnienia
(P8) i Shugyo, których E9 nie pisze — oraz `contract-without-implementation` dla Document Intake (ustalenie 1).

**Przegląd E9c-2** (jedna runda, decyzja użytkownika: dwa przeglądy równolegle na `60324a5..90925cc` —
`code-review high` i bezpieczeństwo z wydajnością). Sandbox 132 → **137** testów; `check` bez zmian, 0 / 28 / 10.

*Poprawione przez asystenta, z testem i próbą odwrotną:*
- **Numer KSeF w cyfrach spoza ASCII** (`3bb3a63`, oba przeglądy): z flagą `u` `\d` to każda cyfra Unicode, więc
  data w cyfrach arabsko-indyjskich przechodziła wyrażenie, a `String.to_integer/1` rzucał wyjątek — nagranie
  kończyło się wyjątkiem zamiast odmowy inwariantu — a NIP w takich cyfrach był drugą pisownią tego samego numeru.
  Teraz `[0-9]`; trzy nowe przykłady łamiące, w tym niemożliwa data, której wcześniej żaden nie sprawdzał.
- **Obrót rozstrzyga się raz, faktura paruje się raz niezależnie od kolejności w logu** (`bda39ca`, oba
  przeglądy): wyciąg wgrany drugi raz wydawał `run_matching` dla obrotów już rozstrzygniętych — sparowany obrót
  brał drugą fakturę na tę samą kwotę albo dostawał „bez faktury” i log miał oba fakty; faktura pobrana z KSeF
  ponownie po sparowaniu wracała do puli. Boundary trzyma osobno to, co dał KSeF, co się sparowało i które obroty
  są rozstrzygnięte; nowy inwariant `a_turnover_is_matched_once`, który polityka przyjmuje jako odpowiedź
  jednostki. Przy okazji dopisywanie na początek zamiast `++`.
- **Polskie cytaty w komentarzach i zbędne zależności granicy** (`46c7f9e`): pięć komentarzy i moduledoc cytowały
  warsztat po polsku; `Taxvision.DocumentIntake` zależał od `EhOsContract` i kontraktów, których nie używa.

*Pominięte, jako ustalenia o bibliotece:*
- **Polityka wydająca N komend w transakcji żądania trzyma globalną blokadę dopisywania przez N dispatchy**
  (bezpieczeństwo i wydajność, wysoka pewność): `:in_transaction` jest domyślne, blokada ma jeden klucz
  (`eh_os_contract_append_lock()`), więc wyciąg z tysiącami obrotów wstrzymuje każdy zapis w aplikacji, a `read_body`
  wpuszcza 8 MB. Mechanika silnika — do E10/E11: reguła `check` na politykę z fan-outem bez `delivery:
  :at_least_once` albo limit długości listy w polu komendy.
- **Boundary czyta wszystkie własne zdarzenia, także te, których `evolve` nie używa** (oba przeglądy): każde
  `run_matching` dekoduje każde `bank_turnover_list_created` miesiąca z całą listą obrotów — O(N²) na wyciąg. DSL
  nie pozwala boundary powiedzieć, które z własnych zdarzeń czyta; w sandboksie obeszłoby to przeniesienie wyciągu
  do osobnej jednostki. Do E11.
- **Usługa domenowa nie ma krawędzi na żadnym grafie** (weryfikacja w przeglądarce): graf kontraktu rysuje
  `issued_by` („gives ksef_number”) i `backed_by`, `publish` jest na grafie systemu, a `:pairing` nie ma nigdzie —
  ani w widoku boundary, który ją woła. Do E13 (graf jako API).
- **`\d` z flagą `u`** — nowy rodzaj pułapki obok reguły o `u` w `CLAUDE.md`: format ASCII piszemy `[0-9]`.
  Dopisane do `CLAUDE.md` (decyzja niżej).

*Pominięte, jako logika domeny (decyzja przed E9c-2):* dopasowywanie nie wymaga otwartego miesiąca (`stage
:opening` przed `:matching` nie jest wymuszany); parowanie nie patrzy na kierunek obrotu (wpływ czy wydatek) — pod
„tylko po kwocie”.

### Po przeglądzie E9c-2 — decyzje użytkownika (28 września)

Asystent zapytał o dwie rzeczy z przeglądu; odpowiedź: „tak” na obie.
- **NIP sprzedawcy w numerze KSeF i obroty JDG zostają w logu jawne.** Numer KSeF zaczyna się NIP-em sprzedawcy —
  przy jednoosobowej działalności identyfikatorem osoby trzeciej — a obroty z wyciągu to kwoty i daty z rachunku
  JDG; decyzja „Dane JDG w logu zostają jawne” obejmowała dotąd tylko dane klienta. *Odrzucone:* numer i obroty
  jako `personal:` (crypto-shredding pod sprzedawcą albo pod firmą klienta); numer KSeF jako skrót w logu.
- **Reguła o `\d` z flagą `u` w `CLAUDE.md`** — format ASCII piszemy `[0-9]`, obok reguły o `u`. *Odrzucone:*
  zostawienie jej tylko w ustaleniach przeglądu.

### Przed E10 — decyzje użytkownika (28 września)

- **E13 idzie po E12.** Graf systemu zbudowany w EG spełnia graficzną część odbioru E10; E10 przypina ją testem,
  bez rozpoczynania formatu `graph.v1` ani wymiany renderera. Optymalizacja boundary, które dekoduje nieużywane
  własne zdarzenia, zostaje w E11, a brak krawędzi usług domenowych — w E13.
- **Dwie reguły kompletności z E9 wchodzą do E10:** aktor z wymiarem `scope`, który może wydać komendę bez
  `scope`, oraz zawężenie `contract-without-implementation`, aby nie zgłaszało kontraktu złożonego wyłącznie ze
  zdarzeń nagrywanych przez `recorded_by:`.
- **Fan-out polityki `:in_transaction` dostaje ostrzeżenie L5**, gdy scenariusz pokazuje wydanie więcej niż jednej
  komendy. Nie ma arbitralnego limitu długości listy w runtime; ostrzeżenie mówi o globalnej blokadzie dopisywania
  i wskazuje `delivery: :at_least_once`. *Odrzucone:* limit danych wejściowych udający limit pracy oraz odłożenie
  znanego ryzyka bez żadnego sygnału dla autora kontraktu.
- **Reszta E10 idzie małymi commitami:** nazwany eksport `Model.to_data/1` i endpoint web, AsyncAPI z `publish`,
  OpenAPI z komend i query, a na końcu manifest `ehos.manifest/v1` w pakiecie auth, równy fixture'owi TaxVision
  po ograniczeniu do pól schematu EHOS-a.

### E10 — co wyszło (28 września)

Na `dsl-v2/e10-outputs`, od `e7709c2`, niewypchnięte: decyzje (`d4140bf`), kompletność (`7c1d551`), eksport modelu
(`ce0547b`), AsyncAPI (`da06ddc`), OpenAPI (`7dcf101`), manifest (`97047d5`) i poprawka z przeglądu (`dfa4455`).
Pełna brama po każdym commicie: `EXIT=0`. Sandboxowy test E10 przypina rzeczywiste wyjście `check`, graf systemu,
AsyncAPI i OpenAPI TaxVision oraz plik manifestu z taska.

**Zewnętrzna walidacja po researchu bibliotek (28 września).** Wygenerowane dokumenty wszystkich ośmiu
kontraktów v2 — pięciu Rehmedu i trzech TaxVision — przeszły Redocly CLI 2.55.0 dla OpenAPI (profil `spec`)
oraz AsyncAPI CLI 6.2.0 dla AsyncAPI. Wszystkie osiem dokumentów AsyncAPI ma 0 błędów i 0 ostrzeżeń;
każdy dostaje wyłącznie informację o dostępności AsyncAPI 3.1.0. Zgodnie z wcześniejszą decyzją walidatory
pozostają ręcznym, przypiętym wersją pomiarem poza repozytorium i bramą — projekt nie dostał zależności Node.

**Co jest.**

- **L5 z E9:** `scoped-actor-with-unscoped-command`; brak `contract-without-implementation` dla kontraktu
  złożonego wyłącznie ze zdarzeń `recorded_by:`; `in-transaction-policy-fan-out`, gdy scenariusz polityki pokazuje
  więcej niż jedną wydaną komendę. TaxVision daje ostatnie ostrzeżenie na `match_each_turnover`; nie ma limitu
  runtime, zgodnie z decyzją. Wynik sandboxa: **0 błędów, 29 ostrzeżeń, 9 uwag**.
- **Graf systemu:** istniejący wynik EG2 jest przypięty na TaxVision — konteksty, krawędź
  Document Intake → Accounting Month i publikacja miesiąca. E10 nie wprowadza formatu grafu jako danych.
- **Model jako dane:** `EhOsContract.Model.to_data/1` zwraca JSON-ready `eh_os_contract.model.v1` z kontraktem,
  domeną, wyprowadzonymi uprawnieniami i digestem projekcji. Chronione endpointy webowe: `/model` i
  `/model/:contract`, digest dokumentu jako `ETag`.
- **AsyncAPI 3.0:** tylko `publish` staje się kanałem, wiadomością i operacją `send`; zdarzenia wewnętrzne są
  nieobecne. Payload to zamknięty JSON Schema wybranych pól, z nazwą publikacji, zdarzeniem źródłowym,
  `schema_version` i `idempotent_on`. `/asyncapi` czyta wyłącznie kontrakty v2; bezpośrednia projekcja v1 zostaje
  tylko do cięcia E11.
- **OpenAPI 3.1.2:** osobny dokument na kontrakt, ścieżki względne wobec mountu `EhOsContract.Plug`:
  `POST /commands/<capability>` i `GET /queries/<capability>`. Widać role i `scope`; nie ma komend tylko dla kodu
  aplikacji. Komenda tworząca nie pokazuje generowanej tożsamości i wymaga `idempotency-key`; query opisuje pola
  read modelu. `/openapi` i `/openapi/:contract` są chronione jak reszta API i podają digest w `ETag`.
- **Jeden JSON Schema dla AsyncAPI i OpenAPI:** typy wbudowane, aliasy i wartości domeny, listy, enumy,
  identyfikatory, pola osobowe/`issued_by`, wymagane pola i `additionalProperties: false`. Przegląd znalazł, że
  `Codec` zapisuje opcjonalne pole jako `null`, nie tylko pomija klucz; oba dokumenty dopuszczają teraz oba
  kształty. `Receipt.position` też jest `integer | null`, bo komenda może nie dać zdarzenia.
- **Manifest EHOS-a:** `EhOsContract.Auth.Manifest.build/2` i
  `mix eh_os_contract.manifest --domain taxvision --output ehos.manifest.json` generują wyłącznie ścisłe pola
  `ehos.manifest/v1`. Capability to każda komenda dostępna człowiekowi; rolą jest każdy aktor `:human` z co
  najmniej jedną taką komendą. Aktor systemowy, aktor bez uprawnień, query, nagranie, scope i publikacja nie są
  prywatnymi rozszerzeniami, które EHOS odrzuciłby. `engine` i `contracts` są pominięte, więc metadane nie ruszają
  digestu autoryzacji.

**Rozjazd odbioru manifestu.** Wymaganie „równy fixture'owi TaxVision w `eh-os`” nie zachodzi po E9 i nie da się go
spełnić wierną projekcją obecnego modelu. Fixture z 25 września ma dwie komendy; model ma cztery. Do listy zmian po
stronie `eh-os` (*1 października:* [eh-os#91](https://github.com/EmpoweredHouse/eh-os/issues/91), z pełnym
manifestem wygenerowanym na `6e1658a`):

1. dodać `taxvision.complete_company_profile` (`Uzupełnij profil firmy`, proces `client`) i
   `taxvision.ingest_bank_statement` (`Wgraj wyciąg bankowy`, proces `accounting_month`);
2. etykietę `open_month` zmienić z „Otwarcie miesiąca księgowego” na „Otwórz miesiąc księgowy”;
3. etykietę `retrigger_verification` zmienić z „Ponowienie weryfikacji rejestrowej” na „Ponów weryfikację”, a
   proces z `accounting_month` na `client`;
4. rozszerzyć `taxvision.accountant` o wszystkie cztery capability i przeliczyć digest fixture'u oraz asercje,
   które go przypinają.

Generator nie dostał ręcznego filtra do dwóch historycznych komend: taki filtr przywróciłby drift, przed którym
manifest istnieje. Drugie repozytorium nie zostało zmienione. `ehos.manifest/v1` przyjmuje tylko komendy; query,
scope, `publish`/`consumes` czekają w EHOS D-40/D-41 na v2, a capability nagrywania potrzebuje tam pola, którego
proponowane v2 jeszcze nie opisuje.

### Przegląd PR-a E10 — przeciek i decyzja o grafach (29 września)

**Przeciek w `/model`.** Wygenerowane dokumenty wszystkich ośmiu kontraktów pokazały PESEL, ICD-10 i ICD-9
w `Rehmed.Contracts.StatutoryReporting`: dwa scenariusze polityki startują od `visit_closed_clinically`
rodzeństwa (ClinicalDocumentation), a redakcja szukała deklaracji zdarzenia tylko w zdarzeniach własnego
kontraktu — nie znalazła, więc zostawiła dane. Założenie z opisu PR-a („generated model contains no fixture
PESEL”) było sprawdzone ręcznie i nie na tym kontrakcie. Poprawka: zdarzenie w `given`, `on` i `expect` jest
rozwiązywane przez `Model.declaring/2` (własne albo rodzeństwa, z `as:`) i pola odebranej publikacji; dane
zdarzenia, którego deklaracji nie da się znaleźć, wychodzą jako `null` zamiast dosłownie. Zweryfikowane
odwrotnie: na `export.ex` z PR-a nowy test silnika pada na `refute encoded =~ "Ada Example"`. Sandbox dostał
test, że żaden model nie niesie wartości osobowych Rehmedu.

**Decyzja użytkownika: EHOS rysuje procesy z `/model`, AsyncAPI zostaje granicą `publish`.** Pytanie było, czy
AsyncAPI nie powinien pokazywać też zdarzeń wewnętrznych, skoro EHOS ma rysować procesy aplikacji. Pomiar:
AsyncAPI jest pusty w siedmiu z ośmiu kontraktów sandboxa — procesy płyną przez `consumes` wewnątrz aplikacji,
a jedynym `publish` jest `taxvision.accounting_month.opened.v1`. `/model` ma wszystko, czego graf potrzebuje:
zdarzenia, jednostki, polityki, process managery i krawędzie `consumes`; docelowy format grafu to `graph.v1` z E13.
*Odrzucone:* zdarzenia wewnętrzne w AsyncAPI oznaczone rozszerzeniem `x-eh-os-contract-internal` — zamazuje
granicę D11 (dokument udawałby kanały, których nie ma na brokerze i które zmieniają się bez wersji), a każda
wewnętrzna zmiana ruszałaby digest dokumentu, który istnieje po to, żeby porównywać interfejs zewnętrzny.
Konsekwencja: skoro EHOS czyta `/model`, redakcja modelu jest granicą danych osobowych — stąd poprawka wyżej przed
merge'em, nie po.

**Pre-PR review poprawki (29 września).** Oba przeglądy (poprawność; bezpieczeństwo i wydajność) znalazły cztery
ścieżki, którymi dane bez deklaracji wychodziły dosłownie albo rzucały wyjątkiem w kontrakcie, którego kompilator nie
sprawdził: rodzeństwo bez konsumowanego zdarzenia (`CaseClauseError`, 500 na `/model`), klucz danych bez pola,
odpowiedź query bez read modelu i przykład wartości strukturalnej, który nie jest mapą. Wszystkie dają teraz `null`
(`5790ca7`, zweryfikowane odwrotnie; 27 wygenerowanych dokumentów sandboxa identycznych bajt w bajt przed i po).
Pominięte: wspólny helper z `Links.Scenarios.event/6` (drobiazg, osobno) i obsługa `If-None-Match` na endpointach
dokumentów (7 ms na indeks — nie teraz).

**Decyzja użytkownika: ryzyko hashy przyjęte i zapisane.** `version` kontraktu i `digests["scenario:*"]` są
liczone ze scenariuszy **przed** redakcją (`build.ex`, `version/3` i `digests/3`), mają 48 bitów i wychodzą w
`/model`, OpenAPI i AsyncAPI. Kto widzi dokument, zna wszystkie pozostałe wejścia hasha, więc przy jednym polu
osobowym może offline zgadywać zredagowaną wartość — PESEL to około 2^28 możliwości; przy kilku polach osobowych
naraz przestrzeń przekracza 48 bitów i zgadywanie daje fałszywe trafienia, ale nie jest niemożliwe. Dostęp do
dokumentów jest za resolverem hosta. **Reguła, która z tego wynika: wartości pól `personal:` w scenariuszach,
przykładach reguł, niezmiennikach i wartościach domyślnych są zmyślone, nigdy prawdziwe** — kontrakt nie jest
miejscem na dane pacjenta, a hash z niego jest publiczny. *Odrzucone:* hash liczony z redakcji — zamyka lukę, ale
przesuwa jeden raz wersję każdego kontraktu z danymi osobowymi w scenariuszach, a zmiana samej wartości osobowej
w przykładzie przestaje ruszać wersję. *Odrzucone:* usunięcie tylko `digests` z eksportu — nie zamyka luki, bo
`version` jest hashem z tych samych scenariuszy i leży też w OpenAPI i AsyncAPI.

### Po E10 — decyzja użytkownika: deweloper pisze minimum, deskryptor aplikacji generujemy (29 września)

**Skąd pytanie.** Ta sama wiedza występuje w kilku dokumentach naraz. Przykład: komenda `open_month`, którą wydaje
Księgowa, jest w kontrakcie, w `capabilities` modelu, w rozszerzeniach operacji OpenAPI i w manifeście. `publish`
z kontraktu wraca w AsyncAPI i w ręcznie pisanym `publishes:` pliku `ehos.yaml` (`eh-os`, `ARCHITECTURE.md`
§5.1). Powtórzenie w dokumentach wygenerowanych nie jest problemem. Problemem jest fakt pisany ręcznie dwa razy
i dokumenty, które się rozjeżdżają, jak fixture manifestu TaxVision w `eh-os`. Manifest (co aplikacja oferuje)
i `ehos.yaml` (czego potrzebuje) okazały się dwiema stronami jednego grafu uprawnień: capability dla człowieka
przez rolę i capability innej aplikacji dla workloadu przez `needs.capabilities`. Rozdzielenie ich na dwa pliki
jest historyczne: manifest powstał osobno w D-32, bo `ehos.yaml` opisywał tylko potrzeby.

**Decyzja.** Deweloper podaje w `ehos.yaml` tylko minimum, czyli to, czego kontrakt wiedzieć nie może: bazę,
sekrety, `serves` i `health`. Przy deploymencie biblioteka generuje za niego kompletny deskryptor aplikacji i to
on trafia do EHOS-a. Deskryptor ma dwie sekcje:

- `offers` z kontraktu: capability, role, publikacje; do tego `serves` z `ehos.yaml`;
- `needs` z `ehos.yaml`: baza, sekrety; z kontraktu `consumes` i ta część `needs.capabilities`, którą da się
  wyprowadzić, a resztę z `ehos.yaml`.

Każdy fakt jest pisany ręcznie dokładnie raz: to, co wynika z procesu, w kontrakcie, a runtime w `ehos.yaml`.
Wygenerowanego pliku nikt nie edytuje.

**Co z dzisiejszego rozdziału zostaje, jako reguły wewnątrz deskryptora.**

- Uprawnienia mają osobny digest i osobną aktywację. Rola, która urosła, daje ludziom więcej i wymaga przeglądu w
  Console; zmiana portu albo wersji sekretu nie. EHOS liczy digest sam (D-38), więc może go liczyć z samej części
  uprawnień.
- Część ręczna i generowana nie mieszają się w jednym edytowanym pliku. Wejście (`ehos.yaml`) pisze deweloper,
  wyjście składa build.

OpenAPI, AsyncAPI i `/model` zostają obok jako widoki dla narzędzi i grafu.

*Odrzucone:* dwa osobne dokumenty, manifest i kompletny ręczny `ehos.yaml`, jak dziś. Ta sama capability żyje w
nich po dwóch stronach grafu, a `publishes` pisze się dwa razy. *Odrzucone:* Console sama wyprowadza manifest i
resztę z `/model`. Logika „kto ma jaką capability” (aktorzy, `by:`, `scope`) istniałaby wtedy w dwóch
repozytoriach i rozjechałaby się przy pierwszej zmianie reguł, więc wyprowadzanie zostaje w bibliotece.
*Odrzucone:* jeden plik, w którym deweloper edytuje połowę, a build nadpisuje drugą. To zły DX, bo nie wiadomo, co
przetrwa następny build.

**Czyje to jest.** Schemat deskryptora jest EHOS-a: `ehos.manifest/v1` (D-32, D-38) i `ehos.yaml` (§5.1) są ich.
Na liście zmian do `eh-os` jest propozycja (*1 października:* przyjęta jako D-51/D-52, ale digest uprawnień
obejmuje też `contracts`, [eh-os#92](https://github.com/EmpoweredHouse/eh-os/issues/92)): jeden deskryptor z
`offers`/`needs` i digestem uprawnień liczonym z `offers`, najlepiej razem z ich planowanym manifestem v2 (D-40/D-41), który i tak ma dołożyć query, scope i
`publish`/`consumes`. Dziś po naszej stronie nic się nie zmienia: `mix eh_os_contract.manifest` pisze v1, dopóki
EHOS przyjmuje v1. Etap w kolejności — do ustalenia po odpowiedzi EHOS-a.

**Otwarte, bez decyzji.** Czy AsyncAPI dostaje operacje `receive` z `consumes` publikacji innej aplikacji. Bez
nich Console przy deploymencie widzi, co Sales wysyła, ale nie widzi, na których polach polega Delivery. Czy
OpenAPI ma wskazywać capability tylko po nazwie, bez powtarzania ról i `scope`. Czy każdy wygenerowany dokument
niesie digest modelu, z którego powstał, żeby Console odrzuciła zestaw z dwóch buildów.

### D-51 i D-52 w `eh-os` — uwagi przed akceptacją (29 września)

EHOS zapisał kierunek z sekcji wyżej w dwóch rekordach, oba `proposed`, na gałęzi `stage-5/01-plan` w `eh-os`
(`c03d44e`): **D-51** — format `ehos.yaml` należy tylko do EHOS-a, jako JSON Schema `ehos.yaml/v1`; **D-52** —
`mix eh_os_contract.manifest` czyta `ehos.yaml` i pisze `ehos.manifest/v2`, czyli `ehos.yaml` rozszerzony o
`application`, `engine`, `contracts` i `offers`. Jedna różnica wobec naszej propozycji: `serves` zostaje na
najwyższym poziomie, a nie w `offers`, żeby klucze dewelopera miały te same ścieżki — przyjmujemy bez uwag.
**Nic nie implementujemy przed akceptacją rekordów.** Przeczytane w `eh-os` (tylko do czytania); nic tam nie
zapisano, komentarz do ich PR-a — na polecenie użytkownika.

*1 października:* oba rekordy są `accepted` (29 września), a uwagi nie zostały do nich wysłane. Uwagi 2, 3 i 5 są
załatwione w przyjętej treści, 6 i 7 są nieaktualne. Uwaga 1 to
[eh-os#92](https://github.com/EmpoweredHouse/eh-os/issues/92), uwaga 4 to
[eh-os#93](https://github.com/EmpoweredHouse/eh-os/issues/93). Szczegóły w „Dopisku 1 października”.

**Z modelem v2 nic nie jest sprzeczne.** `application` to `name:` domeny (task już bierze `--domain`),
`offers` to dzisiejsze capability i role, a `consumes` dojdzie jako własny klucz w `needs` po D-41. Uwagi, od
najważniejszej:

1. **Digest uprawnień obejmuje `contracts`, a `contracts[].version` zmienia się przy każdej edycji kontraktu.**
   `version` to hash całego kontraktu — deklaracji i scenariuszy (`next/contract/build.ex`, `version/3`).
   Przykład: nowy scenariusz w AccountingMonth TaxVision albo poprawiona etykieta zdarzenia zmienia `version`,
   capability i role zostają te same — a według D-52 powstaje nowa wersja aplikacji, która wymaga przeglądu w
   Console. To jest dokładnie ten szum, którego driver 3 D-52 chce uniknąć, i powód, dla którego task E10 pomija
   `engine` i `contracts` w v1. Propozycja: digest uprawnień z `application` i `offers`, a `contracts` tylko w
   digeście manifestu (zapisanym na wdrożeniu, więc weryfikacja D-16 w Stage 8 i tak ma z czym porównać).
2. **Adres schematu z `https://ehos.localhost/…` nie jest osiągalny z naszego CI**, a repozytorium `eh-os` jest
   prywatne. Test „fikstury spełniają opublikowany schemat” potrzebuje kopii. Propozycja: przypięta kopia
   `ehos.yaml/v1.json` w pakiecie auth z wersją i sha256, odświeżana świadomie; D-51 powinien powiedzieć, że
   przypięta kopia nie jest „powtórzeniem formatu”, tylko jego cytatem z wersją.
3. **„Ta sama wartość pod tą samą ścieżką” zależy od parsera YAML.** Generator potrzebuje parsera (nowa
   zależność pakietu auth), a strona sprawdzania w Console ma własny. YAML 1.1 czyta `public: yes` jako `true`,
   a `version: 16` jako liczbę; YAML 1.2 core — inaczej. Jeśli parsery się różnią, deweloper zobaczy na stronie
   sprawdzania co innego, niż generator zapisze w manifeście, a EHOS przy wdrożeniu widzi już tylko manifest. D-51
   powinien nazwać regułę parsowania (np. YAML 1.2 core schema) i to, że duplikaty kluczy i aliasy są odmawiane
   **przed** walidacją także przez generator — inaczej duplikat po cichu daje ostatnią wartość. Czy wybrany parser
   Elixira odmawia duplikatów — do sprawdzenia przy wyborze.
4. **Ścieżki dewelopera i generatora muszą być rozłączne na zawsze**, bo `needs` jest wspólne. Reguła do
   zapisania: żadna wersja `ehos.yaml` nie dostanie ścieżki, którą pisze generator (np. `needs.consumes` po
   D-41), a generator przy kolizji odmawia zamiast nadpisać.
5. **`schema` jest wyjątkiem od reguły „każdy klucz bez zmian”** — test property musi go pominąć; drobiazg w
   sformułowaniu D-52.
6. **Potwierdzenie „manifest `ledger` równy fixture'owi w `eh-os`” nie może żyć w tym repozytorium** — kod
   `ledger` jest w `EmpoweredHouse/ehos-ledger`, a tu nie budujemy aplikacji klienta. Propozycja: to porównanie
   w CI `ehos-ledger` (albo fixture `eh-os` brany z artefaktu jego CI); po naszej stronie test property i
   TaxVision.
7. **Kolejność.** #43 jest już w `main` (`91c6fbc`, CI `success`), więc warunek „najpierw merge E10” jest
   spełniony, a D-52 nazywa go jeszcze „in review”. U nas następne jest E11 (cięcie v1 i przemianowanie `Next`),
   które dotyka kodu, z którego task manifestu czyta model. Manifest v2 po akceptacji: po E11 na ostatecznych
   nazwach albo, jeśli Stage 5 czeka, mały etap przed E11 — decyzja użytkownika.

**Decyzja użytkownika (29 września): manifest v2 po E11**, po akceptacji D-51 i D-52 — pisany na ostatecznych
nazwach, bez `Next`. *Odrzucone:* mały etap przed E11 — skróciłby czekanie Stage 5, ale kod manifestu czyta model
przez moduły, które E11 przemianowuje, więc byłby ruszany dwa razy.

### EH — odpowiedź EHOS-a: D-51, D-52 i plan generatora `ehos.manifest/v2` (29 września)

*Odzyskane 1 października z niezacommitowanego `PLAN.md` w worktree `contract-linking-entity-definition-c94951`
(sesja z 29 września), na polecenie użytkownika, bez zmian treści. Od tamtej pory: tabele poza `public` (D-54, #51)
weszły w #53 i #54, a potrzeby wobec EHOS-a — w tym uwagi do D-51/D-52 — są w `eh-os` #91–#96 (#60); co z planu EH
jeszcze stoi, trzeba sprawdzić przed startem.*

**Skąd.** EHOS przejął propozycję z sekcji wyżej i zapisał ją w dwóch przyjętych rekordach, zmergowanych w `eh-os`
(PR #58, `9be1faf`): **D-51** — `ehos.yaml` definiuje wyłącznie EHOS, jako wersjonowany JSON Schema;
**D-52** — manifest `ehos.manifest/v2` to `ehos.yaml` rozszerzony o to, co oferują kontrakty. Kontekst przysłał
użytkownik; rekordy przeczytane z `origin/main` `eh-os` (`85fc336`), razem z D-54, D-56 i planem Stage 5. **Krok 1
Stage 5 jest już zmergowany (#59):** schemat leży w `eh-os` pod `priv/schemas/ehos.yaml/v1.json`, więc walidację
można podłączyć od razu, a nie „gdy krok 1 się zmerguje”. EHOS czyta plik przez yamerl (dwa przebiegi, schemat
`core`, `keep_duplicate_keys`) i waliduje JSV 0.25 (draft 2020-12). Po stronie EHOS krok 2 (przyjęcie v2, dwa
digesty, ręczny `ledger.v2.json`) jeszcze nie ruszył. `EmpoweredHouse/ehos-ledger` jest pustym repozytorium.

**Co się zmienia względem naszej propozycji.** `serves` jest na najwyższym poziomie, nie w `offers`, żeby klucze
dewelopera miały w manifeście te same ścieżki. Nazwa aplikacji dalej pochodzi z `name:` domeny, a przy kilku
domenach z pola `application` w `ehos.yaml`, które zastępuje flagę `--domain`. Digestów nie liczymy: liczy je EHOS.

**Przykład, jak to wygląda dla dewelopera.** Deweloper ledgera pisze `ehos.yaml` z przykładu D-51 (baza, `web` na
4000, health na 4001). CI uruchamia `mix eh_os_contract.manifest --output ehos.manifest.json`. Generator zamienia
`schema: ehos.yaml/v1` na `"schema": "ehos.manifest/v2"` i `"ehos_yaml": "ehos.yaml/v1"`, przepisuje `needs`,
`serves` i `health` bez zmian i dokłada `application: "ledger"` z domeny, `engine`, `contracts` oraz `offers` z
capability `ledger.record_entry` i rolami `ledger.clerk` i `ledger.auditor`. `public: false` się w nim nie pojawia,
jeśli deweloper go nie napisał.

**Audyt biblioteki pod D-54 i D-56 (29 września, tylko odczyt kodu).**

- **`public` jest zaszyty w dwóch modułach migracji i łamie migracje w innym schemacie.**
  `EhOsContract.Migrations` (`migrations.ex:114-120`, `:145`) i `EhOsContract.Auth.Migrations`
  (`auth/migrations.ex:63-69`, `:93`) czytają wersję z `pg_namespace.nspname = 'public'` i piszą
  `COMMENT ON TABLE "public".…`. Tabele przez `search_path` trafią do `ledger_production`, ale `COMMENT` padnie, bo
  `public.eh_os_contract_events` nie istnieje. A gdyby nie padł, odczyt wersji dawałby 0 i następne `up()`
  tworzyłoby wszystko od nowa. Reszta biblioteki (Ecto, surowe SQL w V03, funkcje i triggery, `insert_all` po
  nazwie tabeli) nie kwalifikuje nazw, więc działa przez `search_path`. Opcji `prefix` nie ma nigdzie i nie jest
  potrzebna, bo D-56 każe aplikacji ustawić `search_path` na `DATABASE_SCHEMA`.
- **Klucz advisory locka dopisywania jest globalny.** `v03.ex:39` ma stały klucz `pg_advisory_xact_lock`, bez
  schematu. Wszystkie aplikacje na jednej bazie `apps` serializowałyby sobie nawzajem dopisywanie do logu. Wynik
  byłby poprawny, ale jedna aplikacja spowalniałaby wszystkie. EHOS prosi wprost o klucz ze schematem.
- **LISTEN/NOTIFY idzie tylko przez notifier Obana**, z pustym payloadem (`subscription/runner.ex:42`). Kanał to
  `"<prefix Obana>.oban_eh_os_contract"`, więc zawiera schemat, gdy aplikacja da Obanowi prefix `DATABASE_SCHEMA`
  (D-56 tego wymaga). Cztery bezpośrednie zapytania biblioteki o `Oban.Job` (`graph.ex:244`, `paths.ex:395,410`,
  `process_manager.ex:265`) idą bez `prefix:` przez `search_path`. Przy D-56 to ten sam schemat, ale nigdzie tego
  nie przypinamy.
- **DDL w runtime: brak.** Każde `CREATE`, `ALTER`, `DROP` i `COMMENT` jest w migracjach. Rola runtime z samym
  DML wystarczy.
- **Zmienne D-56: biblioteka nie czyta żadnych zmiennych** (jedyna to `PORT` w `sandbox/config/dev.exs`).
  `eh_os_contract_auth` bierze `:issuer`/`:audience` z konfiguracji aplikacji, a CA z opcji `cacertfile:` child
  spec. Mapowanie `EHOS_ISSUER`, `EHOS_AUDIENCE` i `EHOS_CA_FILE` należy do `config/runtime.exs` aplikacji, czyli do
  szablonu w `ehos-tools`. U nas wystarczy przykład w README pakietu auth.

**Dwie sprzeczności z D-52 i jedna luka w D-51. Zgłoszone użytkownikowi; zmiana przyjętego rekordu to nowy rekord
w `eh-os`, nie nasza poprawka.**

1. **`contracts` w formie uprawnień.** D-52 liczy digest uprawnień z `application`, `contracts`, `capabilities` i
   `roles`, a `contracts` niesie `version` i `digest` każdego kontraktu. Nasza `version` to hash całego kontraktu,
   scenariuszy i zdarzeń wewnętrznych też. *Przykład:* poprawka opisu scenariusza w `Entries` zmienia `version`,
   więc zmienia digest uprawnień, a wtedy `ehos.platform_operator` (ma `deploy`, nie ma `register`) nie może tego
   wdrożyć, choć niczyje uprawnienia się nie zmieniły. To stoi w sprzeczności z własnym zdaniem D-52, że forma
   uprawnień obejmuje to, co dokument mówi o uprawnieniach. W E10 zrobiliśmy odwrotnie z tego samego powodu:
   manifest v1 pomija `engine` i `contracts`, „więc metadane nie ruszają digestu autoryzacji”. Stąd druga
   konsekwencja: nasz v1 (bez `contracts`) i nasz v2 (z `contracts`) oferujące to samo **nie** mają tego samego
   digestu uprawnień, a D-52 to obiecuje w potwierdzeniu.
2. **`contracts[].digest` jako `sha256:…`.** Taki digest kontraktu dziś u nas nie istnieje. Digest dokumentu
   `/model` (`Digest.document_hash/1`) i `version` mają po 12 znaków hex (48 bitów). Da się dodać pełny SHA-256
   dokumentu `/model` kontraktu. To wybór po naszej stronie, byle opisany. Porównanie z `/model` działającej
   instancji (D-16, Stage 8) wymaga wtedy tej samej wartości w eksporcie.
3. **Luka w D-51: ścisłe czytanie YAML-a.** D-51 mówi, że generator waliduje schematem i „nie pisze drugiej
   implementacji” reguł spoza schematu. Tylko że odmowa aliasów, anchorów, tagów i powtórzonych kluczy nie siedzi w
   schemacie: EHOS robi ją w czytniku, zanim schemat cokolwiek zobaczy. Generator z luźnym parserem (`yaml_elixir`
   domyślnie bierze ostatni z powtórzonych kluczy i rozwija aliasy) zapisałby poprawny JSON z pliku, który EHOS na
   stronie sprawdzania odrzuca. Wtedy „ta sama wartość pod tą samą ścieżką” traci sens. Generator musi więc czytać
   YAML tak ściśle jak EHOS, z tym samym rozwiązywaniem skalarów (YAML 1.2 `core`: `yes` to string). To jest druga
   implementacja czytnika, ale nie reguł. Reguł spoza schematu (unikalne nazwy i porty w `serves`, port health spoza
   `serves`) nie piszemy: łapie je EHOS przy sprawdzeniu wdrożenia (krok 2).

**Plan — etap EH, trzy części, każda z `pre-pr-review` przed następną.** Wszystko w pakietach, więc brama
`mix check` jest bez zmian.

- **EH1 — biblioteka w schemacie innym niż `public` (D-54, D-56).** Oba moduły migracji czytają i piszą wersję w
  `current_schema()` zamiast `'public'`. Klucz locka dopisywania bierze się ze schematu, w którym biegnie migracja:
  funkcja `eh_os_contract_append_lock()` liczy go z `current_schema()` albo migracja wpisuje go na stałe. Wybór
  zapada w EH1, a zmiana idzie nową wersją migracji, nie edycją V03. *Odbiór:* testy silnika i auth na drugim
  schemacie, np. `app_test` z `search_path` i prefiksem Obana: `up()` dwa razy jest idempotentne, `down()` sprząta,
  dispatch, subskrypcja i nagranie działają. Rola z samym DML (bez `CREATE`) przechodzi ścieżkę runtime. Dwa
  schematy w jednej bazie nie dzielą klucza locka. *Kontrola:* przed poprawką test na drugim schemacie pada na
  `COMMENT`. Przy okazji przykład w README auth: `EHOS_ISSUER` → `:issuer`, `EHOS_AUDIENCE` → `:audience`,
  `EHOS_CA_FILE` → `cacertfile:`.
- **EH2 — czytanie i walidacja `ehos.yaml` (D-51).** W `eh_os_contract_auth`, bo tam jest task manifestu:
  - ścisły czytnik na yamerl z opcjami EHOS-a (`detailed_constr`, `{:schema, :core}`, `keep_duplicate_keys`),
    który odmawia anchora, aliasu, tagu, dyrektywy, powtórzonego klucza, klucza niebędącego stringiem i drugiego
    dokumentu. Budżetów czasu i pamięci EHOS-a nie przenosimy: generator czyta plik dewelopera w jego własnym CI,
    nie dane z sieci;
  - walidacja JSV (draft 2020-12) względem kopii `ehos.yaml/v1.json` w `priv/` pakietu, bez zmian, z zapisanym
    źródłem (`eh-os` `85fc336`) i SHA-256 przypiętym testem. Kopia jest w bibliotece, a nie w `.ehos/` aplikacji,
    bo wersja manifestu i tak musi wiedzieć, które wersje `ehos.yaml` może nieść;
  - błędy ze ścieżką, jak na stronie sprawdzania EHOS-a.

  *Odbiór:* korpus odmów, jedna na plik: brak `schema`, brak `health`, `database` bez `engine`, nieznany klucz,
  powtórzony klucz, alias, port 80, `version: 16` jako liczba. Przykład z D-51 przechodzi. Każdy fixture
  `ehos.yaml` w repozytorium waliduje się tą kopią (potwierdzenie D-51 „w Waszym CI”).
- **EH3 — `ehos.manifest/v2` (D-52).** Task czyta `ehos.yaml` (domyślnie z katalogu projektu, `--ehos-yaml` do
  zmiany) i pisze v2:
  - każdy klucz poza `schema` bez zmian, `ehos_yaml` z `schema`;
  - `application` z domeny albo z pola: przy kilku domenach bez pola odmowa, a pole niebędące nazwą żadnej domeny też
    odmowa;
  - `offers.capabilities` i `offers.roles` jak w v1;
  - `engine` z `EhOsContract.version/0`, a `contracts` z `name`, `version` i digestem ustalonym w punkcie 2 wyżej.

  Flaga `--domain` znika. v1 zostaje za `--schema ehos.manifest/v1`, dopóki EHOS nie przyjmuje v2 (krok 2 Stage 5),
  potem wycinamy. *Odbiór:*
  - test property (StreamData, generator poprawnych `ehos.yaml` ze schematu v1): każdy klucz poza `schema` ma w
    manifeście tę samą wartość pod tą samą ścieżką, `ehos_yaml` = `schema`, a generator nie dopisuje wartości
    domyślnych;
  - odmowy: kilka domen bez `application`, `application` spoza domen, `ehos.yaml` niespełniający schematu;
  - manifest sandboxa: sandbox ma TaxVision i Rehmed, więc jego `ehos.yaml` musi nazwać `application`, i to jest
    test odmowy za darmo.

  *Kontrola:* zmiana w `ehos.yaml` samego `serves` nie rusza `offers`, `contracts` ani `application`.
- **EH4 — ledger, po stronie `ehos-ledger` i `eh-os`.** Manifest wygenerowany w CI `ehos-ledger` równy
  `ledger.v2.json` w `eh-os`. `contracts` i `engine` w ręcznym fixturze nie mogą zgadnąć naszych hashy, więc albo
  fixture powstaje z generatora, albo porównanie je pomija. To do ustalenia z `eh-os` przy ich kroku 2. TaxVision
  względem `taxvision.json`: bez zmian, znany rozjazd z „E10 — co wyszło”.

**Kolejność względem E11 — do decyzji użytkownika.** E11 zwija migracje (D2), a EH1 je poprawia. Zrobione przed
E11, poprawka `public` trafi do zwiniętej migracji przy cięciu, bez utraty pracy. Stage 5 `eh-os` (krok 3,
szablon i ledger) czeka na EH1 i EH3; E11 nie czeka na nic.

**Zostaje u nas, bez zmian:** operacje `receive` w AsyncAPI z `consumes`, capabilities w OpenAPI tylko po nazwie i
digest modelu na każdym wygenerowanym dokumencie (sekcja wyżej).

*Sprawdzone 1 października wobec `main` (`c9af0ef`) i `eh-os` `main` (`cfe3883`), na polecenie użytkownika.* Sekcja
wyżej zostaje jak była; co z niej dziś stoi:
- **Już nieprawda:** „krok 2 EHOS-a jeszcze nie ruszył” — v2 przyjęty w `eh-os` PR #62 (`27c4645`), fixture
  `ledger.v2.json` jest, **bez `engine` i `contracts`**, a digest autoryzacji v2 równa się v1; „`ehos-ledger` jest
  puste” — wygenerowane przez `ehosctl init`, CI puszcza `mix eh_os_contract.manifest` i publikuje **v1, którego
  wdrożenie odmawia**; krok 6c EHOS-a wdraża ręcznie pisany v2, **dopóki nasz generator nie pisze v2**; ledger przypina
  `eh-os-contract` na `50eb771` (merge #53, przed #54 — baza zmigrowana wtedy ma stary klucz blokady). Odwołania
  audytu do plików (`v03.ex`, `migrations.ex:114`, `graph.ex:244`…) wskazują kod naprawiony albo usunięty.
- **Zrobione:** EH1 (schemat inny niż `public`) w #53 i #54 — poza przykładem zmiennych D-56 w README auth; zapytania
  do Obana z `prefix:`; V01 zmieniany w miejscu zamiast nowej wersji. „Kolejność względem E11” — nieaktualne, E11
  jest w `main`.
- **Stoi:** D-51 i D-52 przyjęte (z dopiskami D-63/D-64: nazwa schematu `ehos_<app>_<env>`, nowe zmienne D-56, druga
  wersja `ehos.yaml` w przyszłości); schemat `priv/schemas/ehos.yaml/v1.json` w `eh-os` (zamarza z EHOS 0.3.0);
  sprzeczność 1 (`contracts` w digeście autoryzacji) — `eh-os#92`, bez odpowiedzi; EH2 i EH3 — nie zaczęte.
- **Zmienione:** sprzeczność 2 — EHOS nie wymaga formatu `sha256:` dla `contracts[].digest`, a pełny SHA-256 mamy
  (`Digest.document_digest/1`); EH3 — EHOS już przyjmuje v2 i odmawia v1 przy wdrożeniu, a `Manifest.V2` bierze tylko
  `needs.database` i odmawia nieznanych kluczy (więc bez `consumes`, `.subscribe`, zakresów i publikacji — #93, #94,
  #96 otwarte). **Nowa niezgodność:** wzorzec nazwy aplikacji EHOS-a nie dopuszcza `_`, a nasze D11 dopuszcza.
- **Decyzje użytkownika przed startem:** czy v2 niesie `contracts` przy otwartym #92 (każda zmiana etykiety rusza
  digest autoryzacji); jaki `contracts[].digest` (`document_digest/1` dokumentu modelu czy 12-znakowe `version`); v1
  skasować czy zostawić za flagą; gdzie kopia schematu `ehos.yaml` (`priv/` biblioteki czy `.ehos/` aplikacji, jak w
  D-51 i szablonie); odmowa `name:` domeny z `_` przy generowaniu; kolejność wobec fikstur i #49 — **EHOS 6c czeka na
  ten generator**.

### Przed EH2 i EH3 — decyzje użytkownika (1 października)

Stan przed decyzjami sprawdzony 1 października wobec `eh-os` `main` = `f7b2330` (merge #99, krok 6c: ledger
wdrożony z ręcznego `ledger.v2.json`) i `ehos-ledger` `main` = `341fc19`. Każda decyzja z przykładem w rozmowie;
tu z opcjami, które przegrały.

1. **v2 niesie `engine`, a `contracts` nie — dopóki [eh-os#92](https://github.com/EmpoweredHouse/eh-os/issues/92)
   nie odpowie.** `engine` jest tylko w digeście manifestu; digest autoryzacji zostaje równy v1 i ręcznemu
   `ledger.v2.json`, więc wdrożenie ledgera z generatora nie wymaga `register`. *Odrzucone:* bez obu — manifest
   równy fixture'owi co do danych, ale bez śladu generatora, a `engine` niczyich uprawnień nie rusza; z obydwoma,
   jak przykład D-52 — każda poprawka etykiety albo scenariusza (`version` to hash całego kontraktu) zmieniałaby
   digest autoryzacji i wymagała `register` przy wdrożeniu, choć niczyje uprawnienia się nie zmieniły. **Format
   `contracts[].digest`** (`sha256:` z `Digest.document_digest/1` dokumentu modelu czy 12-znakowe `version`) — do
   rozstrzygnięcia dopiero, gdy `contracts` wejdą.
2. **v1 kasujemy:** task pisze tylko v2, `Manifest.build` v1 i flaga `--domain` znikają. *Odrzucone:* v1 za
   `--schema ehos.manifest/v1` do samej rejestracji — wdrożenie i tak odmawia v1, zgodności wstecz nie trzymamy
   (kierunek z 25 września), a jedyni użytkownicy v1 to CI ledgera (ma `ehos.yaml`) i test sandboxa.
3. **Kopia schematu `ehos.yaml/v1.json` w `priv/` pakietu auth**, bez zmian, ze źródłem (commit `eh-os`) i SHA-256
   przypiętym testem. Biblioteka wie, które wersje `ehos.yaml` umie przenieść do manifestu, a kopii w aplikacji nikt
   nie pilnuje. *Odrzucone:* kopia z `.ehos/` aplikacji, jak w szablonie `ehos-tools` i u ledgera — generator
   walidowałby tym, co aplikacja ma, w tym wersją edytowaną albo inną niż ta, którą umie nieść. Schemat zamarza
   dopiero z EHOS 0.3.0, więc kopię odświeżamy świadomie.
4. **Generator odmawia, gdy `name:` domeny nie jest nazwą aplikacji EHOS-a** (`^[a-z]([-a-z0-9]*[a-z0-9])?$`, do 63
   znaków, nie `ehos` — w v1 i v2 tak samo), z komunikatem, co zmienić. Dotyczy nazwy wziętej z domeny; `application`
   z `ehos.yaml` ma ten wzorzec w schemacie. *Odrzucone:* zaostrzenie D11 w silniku — psuje fikstury
   (`:dispatch_rig`) i każdą domenę nazwaną po aplikacji OTP, a D11 mówi o przestrzeni nazw publikacji, nie o EHOS-ie;
   nic — odmówiłby dopiero EHOS, po buildzie i przy wdrożeniu.
5. **Kolejność: najpierw EH2 i EH3, fikstury akceptacyjne i #49 osobno, potem.** Testy generatora stoją na
   zmyślonych domenach w pakiecie auth. *Odrzucone:* najpierw fikstury — #49 nierozstrzygnięte, a ledger czeka na v2.
6. **Blok „Zgoda i stałe uprawnienia” potwierdzony na tę sesję.**

### EH2 i EH3 — plan (1 października)

Zastępuje EH2 i EH3 z sekcji „EH — odpowiedź EHOS-a” (EH1 zrobione w #53 i #54, EH4 jest poza tym
repozytorium). Wszystko w `eh_os_contract_auth`, poza `ehos.yaml` i testem sandboxa; brama bez zmian. Po każdej
części `pre-pr-review` przed następną. Gałęzie: `eh/eh2-ehos-yaml` (EH2a, EH2b — jeden PR) i `eh/eh3-manifest-v2`
(EH3a, EH3b — jeden PR). **Wybory mechaniki (asystenta):** nowe zależności pakietu auth — `yamerl` (ten sam czytnik
co EHOS) i `jsv` (ten sam walidator, draft 2020-12) w runtime, `stream_data` tylko w testach; schemat budowany przez
JSV w czasie kompilacji, z `@external_resource`; `priv/schemas` dochodzi do `files:` pakietu.

- **EH2a — ścisły czytnik `ehos.yaml`.** `EhOsContract.Auth.EhosYaml`: tekst → dane JSON-a albo lista błędów
  `%{path, line, message}` ze ścieżką w zapisie EHOS-a (`serves[0].port`, `""` dla całego pliku). yamerl dwa razy,
  jak EHOS: tokeny parsera (anchor, alias, tag, dyrektywa, drugi dokument) i drzewo `detailed_constr` ze schematem
  `core` i `keep_duplicate_keys` (powtórzony klucz, klucz niebędący stringiem, `.inf`/`.nan`, linia każdego klucza).
  Przed parserem: UTF-8 i brak NUL-a. Budżetów czasu i rozmiaru EHOS-a nie przenosimy — generator czyta plik
  dewelopera w jego CI, a listy ogranicza schemat. *Odbiór:* korpus odmów, jedna na plik — alias, anchor, tag,
  dyrektywa, dwa dokumenty, powtórzony klucz, klucz liczbowy, `.inf`, zły UTF-8; `public: yes` czytane jako string
  (YAML 1.2 `core`). *Kontrola:* bez `keep_duplicate_keys` test powtórzonego klucza robi się czerwony.
- **EH2b — schemat i walidacja.** `priv/schemas/ehos.yaml/v1.json` z `eh-os`, test na SHA-256 i źródło w
  moduledoku; `EhosYaml.read/1` waliduje JSV i zwraca błędy w tym samym kształcie, z linią z drzewa yamerla, gdy jest.
  *Odbiór:* odmowy — brak `schema`, brak `health`, `database` bez `engine`, nieznany klucz (na każdym poziomie), port
  80, `version: 16` jako liczba, `public: yes`; przechodzą przykład z `docs/ehos-yaml.md` i `ehos.yaml` ledgera.
  *Kontrola:* kopia schematu z jednym zmienionym bajtem — test SHA-256 czerwony.
- **EH3a — `Manifest.build/3` dla v2.** Z przeczytanego `ehos.yaml`, domen i kontraktów: każdy klucz poza `schema`
  bez zmian, `ehos_yaml` z `schema`, `application` z `ehos.yaml` albo z jedynej domeny, `offers` jak dziś w v1
  (`capabilities`, `roles`), `engine` z `EhOsContract.version/0`, bez `contracts` (decyzja 1). Odmowy: kilka domen bez
  `application`, `application` spoza domen, nazwa domeny spoza wzorca EHOS-a (decyzja 4), brak kapabilności albo ról.
  v1 znika (decyzja 2). *Odbiór:* test property (StreamData, generator poprawnych `ehos.yaml` według schematu v1) —
  każdy klucz poza `schema` pod tą samą ścieżką z tą samą wartością, `ehos_yaml` = `schema`, żadnej wartości
  domyślnej; zmyślona domena `ledger` o ofercie ledgera z `ehos.yaml` ledgera daje `ledger.v2.json` z `eh-os` (kopia
  w testach, ze źródłem) z dołożonym `engine`. *Kontrola:* zmiana samego `serves` nie rusza `offers` ani
  `application`.
- **EH3b — task, sandbox, dokumentacja.** `mix eh_os_contract.manifest --output <plik> [--ehos-yaml <plik>]`
  (domyślnie `ehos.yaml` w katalogu projektu); odmowa wypisuje każdy błąd ze ścieżką i linią; `--domain` odmawia z
  podpowiedzią, że nazwę daje teraz `application` w `ehos.yaml`. `sandbox/ehos.yaml` z `application: taxvision`
  (sandbox ma dwie domeny) i test: bez `application` odmowa z listą domen, z nim manifest v2. README pakietu auth:
  manifest v2 i przykład `config/runtime.exs` ze zmiennymi D-56 (`EHOS_ISSUER` → `:issuer`, `EHOS_AUDIENCE` →
  `:audience`, `EHOS_CA_FILE` → `cacertfile:`) oraz zdanie, że `EHOS_CLIENT_ID` i `EHOS_CLIENT_KEY_FILE` z D-64
  dotyczą logowania przeglądarkowego, którego pakiet nie robi ([eh-os#95](https://github.com/EmpoweredHouse/eh-os/issues/95)).
  CHANGELOG pakietu auth; odwołania do v1 w dokumentacji repozytorium.

**Poza EH, bez zmian:** zapytania, nagrania, zakresy, `consumes` i publikacje w `offers` (v2 ich nie unosi — #93,
#94, #96); `contracts` (#92); bump `ehos-ledger` i porównanie z `ledger.v2.json` w ich CI (EH4).

### EH2 — co wyszło (1 października)

Na `eh/eh2-ehos-yaml`, od `aadcbd1`, niewypchnięte: plan (`0e4e501`), EH2a — czytnik (`50e0551`), EH2b — schemat
(`6fc82fa`), poprawki po przeglądzie EH2a (`c72bb37`, `d29fbca`, `8694165`, `2b045f7`, `a3e1fac`) i po przeglądzie
EH2b (`53954b4`, `bdf7650`, `ee67995`). Pełna brama po każdym commicie: `EXIT=0`. Auth **71 → 115** testów; sandbox 144, silnik
1104, web 52 i liczby `check` (0 / 29 / 9, 0 / 68 / 6) bez zmian.

**Co jest.** `EhOsContract.Auth.EhosYaml.read/1`: tekst `ehos.yaml` → dane JSON-a albo lista powodów
`%{path, line, message}` (ścieżka w zapisie EHOS-a, `serves[0].port`), posortowana po linii; `versions/0` i
`format_error/1`. Czytnik (`EhosYaml.Reader`, prywatny) idzie za `lib/ehos/applications/ehos_yaml/yaml.ex` w `eh-os`
na `f7b2330`; schemat (`EhosYaml.Schema`, prywatny) — kopia `priv/schemas/ehos.yaml/v1.json` z `eh-os` `eeb732a`,
SHA-256 `5dd7ad34…515b` przypięty testem, ten sam co w `.ehos/` ledgera. Korpus odmów: 23 pliki, jedna odmowa na
plik, i dwa pliki przyjęte (przykład z `docs/ehos-yaml.md` i `ehos.yaml` ledgera).

**Co wyszło inaczej niż w planie, i dlaczego.**
- **`yamerl` (`~> 0.10.0`) i `jsv` (`~> 0.25.0`) są `runtime: false`**, nie zwykłymi zależnościami. Służą tylko
  taskowi manifestu w CI aplikacji, a jako zwykłe startowałyby supervisor yamerla w każdym hoście i jechały do jego
  release'u obok Pluga. Skutek: czytnik sam ładuje yamerla (`Application.load/1`), bo yamerl czyta opcje ze
  środowiska aplikacji, a poza Mixem `read/1` odmawia wyjątkiem z wyjaśnieniem. yamerl przypięty do 0.10.x, bo
  czytnik dopasowuje kształt jego tokenów i węzłów.
- **Schemat JSV budowany przy każdym odczycie**, nie w czasie kompilacji: zbudowany schemat trzyma skompilowane
  wzorce (referencje), których atrybut modułu nie przyjmie. Plik schematu jest czytany w czasie kompilacji, z
  `@external_resource`. Cache w `:persistent_term` był i wypadł po przeglądzie — trzymał stary schemat po
  odświeżeniu kopii.
- **Granice EHOS-a są, bez jego budżetów czasu i pamięci.** Plan mówił „nie przenosimy”, a przeglądy pokazały dwa
  powody, by je mieć: plik do 64 KiB i do 256 znaków `[`/`{` to reguły, które poprawny według schematu plik może złamać
  (EHOS na stronie sprawdzania go odmawia, a generator napisałby z niego manifest); głębokość do 16 i lista do 256
  pozycji ograniczają pracę samego czytnika, która rosła z kwadratem głębokości — `- - - … x` na 8000 poziomów (16
  KB) to 4,7 s, pełne 64 KiB ok. 100 s i 20 GB, zanim schemat cokolwiek odmówił.
- **Wartości czyta wyłącznie schemat `core`**: węzeł zbudowany przez moduł spoza niego (`config :yamerl, node_mods:`
  hosta albo innej zależności) jest odmawiany — z `yamerl_node_bool_ext` `public: yes` przechodziło jako `true`.

**Przeglądy.** EH2a: dwa (poprawność, bezpieczeństwo i wydajność), 10 ustaleń — 6 poprawionych (granice, `node_mods`,
`runtime: false` z ładowaniem yamerla, węższy `rescue`, linia pliku, który nie jest mapowaniem, źródło czytnika), 4
bez zmian (goły tag `!` — EHOS czyta tak samo, a schemat odmawia złego typu; ostrzeżenia yamerla obok błędu; cięcie
ścieżki do 64 znaków — tylko wyświetlanie; brak linii przy powtórzonym kluczu — yamerl zawsze ją daje). EH2b razem z
poprawkami: dwa przeglądy, 13 ustaleń — 8 poprawionych (głębokość i lista, przypięcie yamerla, cache, wyjątek poza
Mixem, komentarz `rescue`, CHANGELOG, ten zapis), 4 bez zmian (`allOf` filtrowany jak u EHOS-a i nieobecny w v1;
brak linii przy brakującym kluczu najwyższego poziomu; klucz z obcego modułu węzła z ogólnym komunikatem; anchor na
pustej wartości — yamerl nie daje tokenu, aliasy odmawiane), 1 pominięte — niżej. Trzecia runda, na samych
poprawkach (`a3e1fac..bdf7650`): bez defektu; dołożony test pliku płytkiego z wieloma kolekcjami (bez klauzuli
`collection_end` czerwony), lista granic w CHANGELOG. **Zostaje świadomie:** szeroka kolekcja flow w korzeniu pliku
(`[a: ,a: ,…]`) rośnie kwadratowo w parserze yamerla — 64 KiB to ok. 45 s; przed tym chroni EHOS-a budżet czasu,
którego nie przenosimy. Ma znaczenie tylko, gdyby task czytał `ehos.yaml`, którego deweloper nie napisał (np. PR z
forka w CI).

**Kandydat na issue w `eh-os` — założony 1 października jako [eh-os#111](https://github.com/EmpoweredHouse/eh-os/issues/111):** `port: 4001.0` przechodzi schemat (JSON Schema liczy
`4001.0` jako liczbę całkowitą), u nas i u EHOS-a tak samo, i trafia do manifestu jako float. Sprawdzenie EHOS-a obok
schematu (port health spoza `serves`, `v1.ex`) porównuje przez dopasowanie, więc `health.port: 4001.0` przy `serves`
na 4001 przechodzi. U nas nic nie zmieniamy (generator ma czytać jak EHOS); po stronie EHOS-a — odmowa albo
normalizacja liczby całkowitej zapisanej jako float.

### EH3 — co wyszło (1 października)

Na `eh/eh3-manifest-v2`, od `50cea3d` (głowa EH2), niewypchnięte: EH3a — generator i task (`1eea9a8`), poprawki po
przeglądzie (`6bbf5be`, `73c7183`), EH3b — dokumentacja i drobiazgi z przeglądu (`c807d61`), poprawki po dwóch
kolejnych rundach (`21f4aff`, `ac8d694`). Pełna brama po każdym commicie: `EXIT=0`. Auth **115 → 137** testów i jedno
property; sandbox **144 → 145**; silnik 1104, web 52, liczby
`check` bez zmian.

**Co jest.** `mix eh_os_contract.manifest --output <plik> [--ehos-yaml <plik>]` czyta `ehos.yaml` projektu (obok
jego `mix.exs`) przez `EhosYaml.read/1` i pisze `ehos.manifest/v2`: każdy klucz poza `schema` bez zmian, `schema`
jako `ehos_yaml`, bez wartości domyślnych, plus `application`, `offers` (kapabilności i role jak w v1) i `engine`;
bez `contracts` (decyzja 1). v1, `Manifest.build/2` i `--domain` zniknęły (decyzja 2); `--domain` odmawia z
podpowiedzią. `Manifest.build/3` (przeczytany `ehos.yaml`, domeny, kontrakty). **Odbiór:** zmyślona domena `ledger`
o ofercie ledgera z `ehos.yaml` ledgera daje `ledger.v2.json` EHOS-a (kopia z `eh-os` `f7b2330`, ostatnia zmiana
`ff1388e`) z dołożonym `engine`; property na StreamData — każdy `ehos.yaml`, który przyjmuje schemat v1, zapisany
jako JSON i przeczytany z powrotem, przechodzi do manifestu bez zmian; dwie mutacje (zgubione `serves`, dopisane
`health`) — czerwone. Sandbox ma `ehos.yaml` z `application: taxvision`; bez nazwy task odmawia wyboru między
TaxVision a Rehmedem. Na żywo: `MIX_ENV=dev mix eh_os_contract.manifest` w `sandbox/` pisze v2 TaxVision (cztery
kapabilności, rola `taxvision.accountant`, `engine` `0.3.0-dev`).

**Co wyszło inaczej niż w planie.** Task i test sandboxa weszły już do EH3a, nie do EH3b: bez `build/2` brama byłaby
czerwona. EH3b to sama dokumentacja. Poza planem, z przeglądów: generator odmawia tego, czego odmówiłby EHOS w
`offers` — komendy i aktora roli ponad 63 znaki (D-48) i pustej etykiety — zamiast 422 przy wdrożeniu; przy kilku
domenach liczy tylko te z kontraktami; `application:` w zapisie EHOS-a (`manifest-rig`) znajduje domenę nazwaną z
`_` i każe ją przemianować; podpowiedź nazwy tylko wtedy, gdy EHOS ją przyjmie. Task patrzy na plik (`File.stat`)
przed odczytem — FIFO bez pisarza zawieszało maszynę wirtualną — i odmawia `--output` równego plikowi wejściowemu.

**Przeglądy EH3a** (poprawność, bezpieczeństwo i wydajność): bez eskalacji uprawnień i bez ujawnienia danych; 14
ustaleń, wszystkie poprawione (lista w notatce przeglądu i w commitach `6bbf5be`, `73c7183`, `c807d61`). **Runda na
poprawkach:** bez defektu wysokiego ani średniego; poprawione — plik bez prawa odczytu (surowy `File.Error`),
`--output` przez dowiązanie albo inną wielkość liter na APFS nadpisujące `ehos.yaml` (porównanie urządzenia i
inode'a), puste `--ehos-yaml`, odczyt przez uchwyt najwyżej o bajt dalej niż EHOS, opis reguły wyboru domeny i
„musi nie mieć sekretów” w README (`21f4aff`). **Runda na `21f4aff`:** poprawione — Windows ma każdy inode równy 0
(porównujemy tylko niezerowe), ponowne sprawdzenie `--output` tuż przed zapisem, test `chmod 000` pomijany jako root
(`ac8d694`). **Zostaje świadomie:** ścieżka podmieniona na FIFO między `stat` a otwarciem może zawiesić task —
Erlang nie otwiera pliku bez blokowania.

### Przed E11 — podział i decyzje użytkownika (29 września)

**Inwentarz** (na `91c6fbc`): v1 żyje tylko w pakiecie silnika i dwóch miejscach dashboardu; sandbox ma same
komentarze. 14 plików lib/dev tylko v1 (~3 000 linii), ~2 400 linii v1 w 22 plikach mieszanych, 41 plików testów i
fikstur v1 (~8 150), 25 modułów `Next` i ~300 odwołań w 83 plikach, pięć wersji migracji i trzy katalogi `priv`.
Twardsze miejsca: szew `Model.fetch` z `Model.V1` (każda gałąź `_v1`), dwie listy rejestru (`contracts` i
`v2_contracts`, ~43 wywołania), nakładka grafu v1 zasilająca panel `/graph`, raport zgodności w dwóch kształtach i
`Dependency.unavailable!`, które waliduje przez deklarację v1 — do kontraktu v2 obserwacji nie da się zapisać, choć
v2 je czyta.

**Podział (wybór asystenta), przegląd po każdej części przed następną:**
- **E11a — usunięcie v1.** Najpierw testy wspólnej mechaniki (`Clock`, `Digest`, `Conformance.Wire`, krawędzie
  okien, `Deployment.diff`, `Report`) na fikstury v2, potem samo usuwanie; `Seed` przycięty do połowy v2; jedna
  lista kontraktów w rejestrze; `Dependency.unavailable!` sprawdza `external` domeny.
- **E11b — przemianowanie `Next`**, samo przemianowanie; testowe `Next.Implementations.*` dostają inny prefiks, bo
  bez `Next` wpadłyby pod prawdziwe `EhOsContract.Implementations`. Z nim usunięcie 16 przypadkowo scommitowanych
  plików (wyjście `pages` w pakiecie z `38132d8`, plik w `tmp/`).
- **E11c — migracje do jednego V01 (D2)** i trzy katalogi `priv`; w sandboxie odpadają tabele TaxVision z v1.
- **E11d — dokumentacja**: `docs/contract.md` z `Spark.CheatSheet`, `docs_test`, brama uniwersalności od nowa,
  `rules.md`, READMEs, `CLAUDE.md`, CHANGELOG 0.3.0, reszta v2 §18, zaległości „do E11” w dokumentacji.
- **E11e — skille**: pięć przepisanych, `write-handler` → `write-decider` i `write-reaction`.
- **E11f — zaległości silnika „do E11”**: duplikacja `scope` (dispatch i D10), boundary dekodujące nieużywane
  własne zdarzenia (O(N²) na wyciąg TaxVision). Nowe słowo DSL-a, jeśli okaże się potrzebne — do użytkownika z
  przykładem.
- Generator `gen.impl` na Igniterze (opcjonalny w opisie E11) — pominięty.

**Decyzje użytkownika:**
- **`Brief` i `mix eh_os_contract.brief` znikają w E11**; E13 buduje Brief na ekranie od nowa na v2. *Odrzucone:*
  przeniesienie na v2 jako plik teraz — ta sama praca dwa razy, a dziś Brief nie działa dla żadnego kontraktu
  sandboxa.
- **`mix eh_os_contract.trace` znika.** *Odrzucone:* przepisanie na obietnice — `report` już je pokazuje.
- **Panel „every contract” na `/graph` znika** (nakładka grafu handlerów v1, dla v2 pusta). *Odrzucone:* w jego
  miejscu graf systemu z nakładką — jest już osobnym widokiem, a E13 przerabia cały ekran.
- **Kontrakty sandboxa do testów pakietu — osobny etap po E11**, przed manifestem v2; E11 kończy się weryfikacją
  na sandboksie jak dziś. *Odrzucone:* ostatnia część E11 — mieszałaby cięcie z przenoszeniem danych testowych w
  jednym przeglądzie.

### E11a — co wyszło (29 września)

Na `dsl-v2/e11a-remove-v1`, od `68a6917`, niewypchnięte: przeniesienie (`2881504`, `e6af4ca`, `763cec0`,
`334502f`), usunięcie testów i fikstur v1 (`1693efb`, −8 633 linii), usunięcie v1 z bibliotek (`b4924f3`, 15 plików,
−6 228 linii). Pełna brama po każdym commicie: `EXIT=0`. Po cięciu: silnik 967 testów, `check` 0 / 66 / 5 (było
0 / 74 / 21 — zniknęły wyłącznie ustalenia o fiksturach v1); web 50; auth 62; sandbox 143, `check` 0 / 29 / 9 bez
zmian. W przeglądarce: `/dashboard/graph` i `/dashboard/contract` bez błędów poza znanym CSP Mermaida (EG3).
**Zostaje do dalszych części:** nazwy `Next`, `v2_contracts/0`, `report_v2` i pliki `*_v2_test.exs` (E11b); tabele
v1 w migracjach (E11c); `docs/contract.md` nieaktualny od `b4924f3`, bo generował go usunięty task `docs` (E11d).
`mix eh_os_contract.graph` bez flagi obrazu wypisuje teraz sposób użycia zamiast rysować graf v1. Katalog reguł nie
ma już żadnej reguły poziomu `error` — błędy są dziś wyłącznie bramami kompilacji. **Najpierw przeniesienie, potem usuwanie:** każdy test v1, który
przypina mechanikę współdzieloną z v2, dostał test v2 tej samej własności, zanim cokolwiek zniknie. Dwie analizy
pokrycia (9 plików „do przeniesienia” z inwentarza, potem pozostałe 23), ~115 testów v1 przeniesionych, reszta to
semantyka tylko v1 (handlery, `emit`, `retain`, klucze z `identity`, `Brief`, telemetria handlerów).

**Usterki v2, które przeniesienie wyciągnęło** (każda zweryfikowana odwrotnie):
1. **Obietnica v2 nie mogła zostać zawieszona.** `Dependency.unavailable!` przyjmowało tylko kontrakt v1, więc
   obserwacji niedostępności do kontraktu v2 nie dało się zapisać, choć `Trace.promised_outages` je czyta. Teraz
   przyjmuje kontrakt v2, którego zdarzenie `depends_on` tego systemu (`2881504`).
2. **`correlate []` się kompilowało**, a wtedy każde zdarzenie kontraktu dostawało za przebieg samą nazwę procesu
   (`Enum.all?([])` w `Dispatcher.run_key/2`) — raport liczył jeden przebieg na wszystko, `check` milczał. R2
   odmawia teraz pustej korelacji.
3. **Pusty `:id` przechodził** (`Codec.fits?` = `is_binary`), choć v1 go odmawiało: identyfikator, który nic nie
   identyfikuje, klucze strumienia, tagu i przebiegu z niczym po dwukropku. Odmawiany dla `:id` i `{:id, encja}`;
   odczyt historii (`decode_value`) dalej przyjmuje pusty, więc zapisana historia się czyta.

**Ścieżki v2, które nigdy nie biegły:** liczenie obietnicy per element (`evaluate_quantified`) — żadna fikstura v2
nie miała tożsamości jednostki węższej niż `correlate`; zawieszenie; krawędzie okien; klucz przebiegu z dwóch pól;
cykl polityki `:at_least_once`; strażnik `Consumer.issue!`. Wszystkie mają teraz testy na fiksturach v2 w samych
plikach testów (poza rejestrem, jak w v1).

**Zapisane, bez zmiany kodu:**
- **Termin `{1, :hour}` wychodzi w raporcie jako „Deadline: hour from the start.”** — `Duration.humanize` gubi
  jedynkę (słusznie w „every day”), a `Sentence.declaration(:deadline)` go używa. Tak samo w v1. Do poprawki
  osobno.
- **Plan zapytania przebiegów v2 zależy od statystyk planisty.** Test 50 000 przebiegów raz trwał 17 s i padł na
  anulowanym zapytaniu — pętla zagnieżdżona przy statystykach „prawie pusto”; po autovacuum zniknęło, nie dało
  się odtworzyć na żądanie. Test woła `ANALYZE` po wstawieniu; w produkcji statystyki prowadzi autovacuum. Do
  pomiaru razem z runnerem read modelu (otwarte pytania).
- **Cykl na ścieżce `:at_least_once` zapisuje w wierszu subskrypcji tylko moduł wyjątku** (v2 §17: żadnych
  wartości w rekordach awarii), więc ścieżka cyklu, którą niesie komunikat, ginie — v1 trzymało komunikat.
  Strażnik v2 zatrzymuje też każdy łańcuch dłuższy niż 32 (limit głębokości, którego v1 świadomie nie miało).
  `chain:` jest publiczną opcją `EhOsContract.dispatch/3`, więc aplikacja może go ustawić.
- **Strażnik tego, co wydaje polityka, jest podwójny**: bez `Consumer.issue!` komendę spoza `issues:` i tak
  odrzuca dispatch (`:not_declared`, aktor polityki nie ma uprawnienia).
- **Bramy v1 bez odpowiednika v2 i bez pojęcia w v2** (nie do przeniesienia): komenda w niezadeklarowanym
  procesie, reguła jako capture zamiast MFA, `identity` spoza payloadu, `events:` na procesie, `retain` na polu
  spoza payloadu. Częściowo pokryte: dwie komendy jednej nazwy w kontrakcie, `by: []`, jednostka kalendarzowa w
  `within` — do dopisania przy E11d, gdy tabela bram w `docs/contract.md` powstaje od nowa.

**Przegląd E11a (pre-pr-review, 29 września).** Dwa przeglądy równolegle na `origin/main..e03f534`: poprawność
(`code-review high`) i bezpieczeństwo z wydajnością. Dostęp, rozwiązywanie nazw kontraktów z URL-a (zawsze przez
rejestr, bez `String.to_atom`) i redakcja danych osobowych — bez zmian. Poprawione, każde osobnym commitem z testem
zweryfikowanym odwrotnie:
- **process manager z `correlate: []`** się kompilował (poprawka R2 objęła tylko proces) — wszystkie przebiegi
  dzieliłyby jeden rekord, stan i timery; P4 odmawia;
- **pusty `:id` w danych scenariusza** przechodził przy kompilacji (`Data.problems`), a padał dopiero w
  wygenerowanym teście — teraz odmawia jak `Codec`;
- **`Dependency.observe/3` rzucał w środku awarii** dla systemu, który kontrakt tylko wywołuje (`calls:` efektu),
  a moduł domeny dawał `MatchError`. **Decyzja użytkownika:** obserwacja jest zapisywana także dla systemu z
  `calls:` — obietnice i tak czytają tylko zdarzenia z `depends_on`, więc niczego nie zawiesza. *Odrzucone:*
  przepuszczanie bez zapisu (obserwacja by przepadła) i zostawienie wyjątku (autor dopisywałby `depends_on`, żeby
  adapter nie padał). Odmowa zostaje dla systemu, którego kontrakt nie używa, choćby domena go deklarowała;
- **dwa testy weba zniknęły z fiksturą v1** (dwa kontrakty o jednej nazwie procesu na `/graph`, 400 „several
  contracts” w API zgodności) — druga fikstura v2 w hoście testowym weba, z własną domeną (X7);
- **zależność `:telemetry`** bez użytkownika po usunięciu `EhOsContract.Telemetry` — usunięta (zostaje pośrednio z
  Ecto i Obana, `mix.lock` bez zmian).

Pominięte, z powodem: pusty `:string` jako pole korelacji daje przebieg `"proc:"` (odmowa w `run_key` to nowy
powód odmowy widoczny dla hosta; pola korelacji są dziś zawsze `:id`); **brak odpowiednika `promise-finer-than-run`
w v2** — gdy jednostka `eventually` nie ma pól tożsamości jednostki `from`, każdy element dostaje pusty klucz i
przebieg jest zawsze naruszony, a `check` milczy (sprzed E11a; kandydat na regułę L3 w E11f); koszt raportu rośnie z
całą historią (`Run` i `Trace` czytają wszystkie przebiegi procesu, sprzed E11a); powielone `bounded` w `trace.ex`
(uproszczenie, nie usterka); zadania Obana starego `EhOsContract.Job` w kolejce hosta — linijka do CHANGELOG-u w
E11d. Bez zmian: `:id` z samych spacji (tak samo jak v1 — `Codec` nie normalizuje tekstu). Pomiar przeglądu: na
2 mln zdarzeń zapytanie przebiegów to złączenie haszujące w 85–90 ms, także przy statystykach z pustych tabel —
17 s z testu skali mogło pochodzić z dopisywania w `Store`, nie z oceny; do złapania `auto_explain` przy pomiarze.

### E11b — co wyszło (29 września)

Na `dsl-v2/e11b-rename-next`, od `9dc47c6` (merge #44), niewypchnięte. Trzy commity, pełna brama po każdym `EXIT=0`,
liczby testów i ustaleń `check` co do jednego jak przed zmianą (sandbox 143, 0 / 29 / 9; silnik 971, 0 / 66 / 5; web
52; auth 62). Wyjścia `MIX_ENV=dev` obu domen — `check` (tekst i JSON), `report` z wersjami kontraktów, `view`,
`glossary`, `--map`, `--system` z nakładką i bez, `--contract` każdego z ośmiu kontraktów z nakładką i bez, manifesty,
strony — bajt w bajt te same przed i po. Wersje kontraktów się nie ruszyły (digest zdejmuje tagi struktur Sparka, więc
nazwa modułu DSL-a do niego nie wchodzi), wiersze wdrożeń też.

- **`b25aa40`** — 15 stron wyjścia `pages` w korzeniu pakietu, scommitowanych z `38132d8`. Szesnasty plik z
  inwentarza (w `tmp/`) zniknął już w E11a (`1693efb`). Po skasowaniu test `pages` ich nie odtwarza.
- **`1afaeb4`** — `EhOsContract.Next.*` → `EhOsContract.*`, pliki za modułami (`lib/eh_os_contract/next/` →
  `lib/eh_os_contract/`), `ProcessShapes.Next.*` → `ProcessShapes.*`, `UniversalityGate.Next.*` →
  `UniversalityGate.*`, `universality_gate_next_test.exs` → `universality_gate_test.exs`, `--extensions` w `mix.exs`
  i `.formatter.exs`, eksporty `boundary`. Poprawka przykładu ADR w `contract_examples_test.exs` (tożsamość) znika.
- **`b3f42bc`** — nazwy z `v2`, które odróżniały v2 od v1: `Registry.v2_contracts/0` → `contracts/0` (i klucz
  skanu w `persistent_term`), `Check.v2_findings/1` → `findings/1`, `Deployment.v2_edge_labels/1` →
  `edge_labels/1`, prywatne `report_v2`, `process_v2`, `drift_v2`, `duration_v2`, `declared_v2`, `v2_row`, `v2_body`
  (+ `v2_channels`/`v2_operations`/`v2_messages`), `Model.v2!` → `contract!`, zmienne `v2` w taskach `check` i
  `graph`; pliki `*_v2_test.exs` i ich moduły bez `V2`.

**Wybory asystenta (mechanika, bez pytania):**
- **Testowe implementacje → `EhOsContract.Fixtures.Implementations.*`**, obok `EhOsContract.Fixtures.*`, gdzie już
  są kontrakty, które implementują. *Odrzucone:* `EhOsContract.Implementations.*` — prawdziwy moduł indeksu
  implementacji, fikstura pod jego nazwą czytałaby się jak jego część; `EhOsContract.TestImplementations.*` — nowy
  prefiks obok istniejącego `Fixtures` bez powodu.
- **Dwa pliki testów z nazwą zajętą przez test mechaniki obok:** `clock_v2_test.exs` → `clock_contract_test.exs` (obok
  `clock_test.exs`, zegar poza kontraktem), `wire_v2_test.exs` → `wire_report_test.exs` (obok
  `conformance_wire_test.exs`, kodowanie poza raportem). *Odrzucone:* scalenie z plikiem obok — to już nie
  przemianowanie.
- **`eh_os_contract.conformance.v2` zostaje** — to nazwa kształtu na drucie, którą porównuje konsument, nie nazwa
  DSL-a. *Odrzucone:* `…conformance.v3` albo bez wersji — zmiana kształtu widocznego dla hosta bez zmiany kształtu.
- **Zostały ze starą nazwą, świadomie:** `CHANGELOG.md` i `docs/adr/` (zapis, nie opis stanu — jak `PNS.X` w ADR-ach);
  sześć skilli (`add-event`, `change-contract`, `contract-distillation`, `module-boundary-check`, `review-pr`,
  `write-handler`) — ich nagłówek mówi „v1 `EhOsContract.Contract` … v2 (`EhOsContract.Next.Contract`)”, podmiana dałaby
  zdanie z tą samą nazwą po obu stronach, a E11e je przepisuje.

**Przegląd E11b (pre-pr-review, 29 września).** Dwa przeglądy równolegle na `origin/main..b3f42bc`: poprawność
(`code-review high`) i bezpieczeństwo z wydajnością. Żadnej usterki w przemianowaniu: skan rejestru i `exclude` bez
zmian w logice, indeks implementacji nie widzi fikstur (moduły z `.exs`), rozwiązywanie kontraktu z URL-a dalej
przez rejestr, redakcja danych osobowych i wersje kontraktów bez zmian. Rozstrzygnięte:
- **CHANGELOG nie odnotowuje zmiany nazw publicznego API** — *pominięte do E11d* (CHANGELOG 0.3.0). Do wpisu:
  `use EhOsContract.Next.Contract` → `use EhOsContract.Contract`; `Registry.graph().v2_contracts` → `.contracts`;
  `Check.v2_findings/1` → `findings/1`; `Deployment.v2_edge_labels/1` → `edge_labels/1`. **Pułapka dla hosta:**
  `Registry.contracts/0` i `Check.findings/1` istniały w v1 i znaczyły kontrakty v1 — wywołanie sprzed E11a dalej się
  kompiluje i po cichu dostaje kontrakty v2 (`CHANGELOG.md:341` mówi jeszcze, że `contracts/0` „stays v1's”).
- **Proza „v2 contract” w komunikatach i dokach** (38 plików w `lib/`) — *pominięte do E11d*: E11b zmienia
  identyfikatory, a komunikat widziany przez hosta to jego kształt. Komunikaty: `eh_os_contract.graph.ex:204`,
  `dispatcher.ex:1108`, `consumer.ex:142`, `contract/links/siblings.ex:51` (X5), `auth/manifest.ex:48`; `@shortdoc`
  `compile.eh_os_contract` i `eh_os_contract.manifest`; `@doc` w `eh_os_contract.ex`, `open_api.ex`, `check.ex`,
  `deployment.ex`, `plug.ex`, `personal.ex`, `model.ex`; komentarz „The v2 DSLs” w `.formatter.exs`. Odwołania
  „v2 §N” do `docs/adr/contract-v2.md` zostają — to nazwa dokumentu.
- **Skille ze starą nazwą** — *pominięte do E11e*, jak wyżej.
- **`exclude:` bez granicy modułu i pomijany przez `Implementations.build/1`** — prawdziwe, sprzed E11b, oba przeglądy
  — *pominięte*, w otwartych pytaniach (zmiana znaczenia konfiguracji hosta idzie do użytkownika).
- **Stary kształt `%{v2_contracts: …}` w `persistent_term` po przeładowaniu kodu bez restartu** — *bez zmiany*:
  biblioteka nie wspiera gorącej podmiany, a moduł rejestru sam mówi, że nowy moduł widać po restarcie.

### E11c — co wyszło (29 września)

Na `dsl-v2/e11c-migrations`, od `563a251` (merge #45), niewypchnięte. Pełna brama po każdym commicie z kodem
`EXIT=0`, na bazach skasowanych i odtworzonych z nowych migracji.

- **`a1e4c98` — jeden V01 silnika (D2).** Kształt z v2 §10.3 w jednym kroku, `current_version/0` = 1, V02–V05
  skasowane, a z nimi migracje `upgrade_…_to_v2…v5` w trzech katalogach `priv` (silnik, web, sandbox). Zmiany
  kształtu, które §10.3 i notatki E2 zapowiadały na cięcie: `text` zamiast `varchar(255)`; bez
  `_event_handlings` i `_handler_failures` (od E11a nic ich nie pisze); bez indeksów v1 na `events` — `type`
  (pokrywa go `(type, position)`), `causation_id` (żadne zapytanie po nim nie filtruje), `instance_id` i
  `(process, instance_id)` (przebiegi czyta się przez `_event_runs`). Przegląd przeszedł każde zapytanie po
  `events` i nazwał indeks, na którym stoi. `pg_dump` schematu dev przed i po różni się tylko tym i komentarzem
  wersji. Test migracji od nowa: jedna wersja, dziewięć tabel i trzy funkcje, `down` bez resztek, żadnej kolumny
  `varchar` (sprawdzone odwrotnie).
- **`6ac26d7`** — cztery migracje `DispatchRig` w bazie testowej silnika jako jedna.
- **`f9edf9c`** — w sandboxie odpadają `taxvision_tasks`, `_accounting_months`, `_notifications` (tabele modułów v1
  TaxVision, od E9c nieczytane); `taxvision_periods` powstaje jedną migracją z unikalną nazwą i trzema `CHECK`-ami,
  bajt w bajt ta sama w `pg_dump`.
- **`c2544a8`** — poprawka z datą w v2 §10.3: czym V01 różni się od szkicu.
- **`418c966`** (po przeglądzie) — test przypina tożsamość `position` (`GENERATED ALWAYS`, sprawdzone odwrotnie
  mutacją na `BY DEFAULT`) i unikalność `id`; cztery komentarze wskazywały usunięte V03.

**Decyzja użytkownika (29 września): bez ścieżki z bazy sprzed cięcia.** Nie ma klienta, więc baza w wersji 2–5 jest
kasowana i tworzona od nowa. *Odrzucone:* (a) odmowa w `up/1` z komunikatem „odtwórz bazę” — nikt poza nami takiej
bazy nie ma; (b) most z wersji 5 przerabiający schemat w miejscu — historia, którą D2 każe zwinąć. Konsekwencja
zapisana w przeglądzie: baza z komentarzem „5” przy `up/1` milczy (jej schemat jest nadzbiorem nowego, więc nowy kod
na niej działa), a `down/1` na niej pada na nieistniejącym `V05`.

**Zmiana 29 września, po komentarzu CodeRabbita do #46 — na polecenie użytkownika („rozwiąż komentarze
coderabbit”).** `up/1` i `down/1` odmawiają (`ArgumentError`) bazie, której komentarz wersji jest wyższy niż
`current_version/0`, z komunikatem „odtwórz bazę”. To odwraca odrzuconą wyżej opcję (a) — powód: bez odmowy baza
zapisana jako „5” pominęłaby po cichu przyszłe V02, a to już nie sprawa bazy sprzed cięcia, tylko każdej wersji
naprzód. Ścieżki migracji z bazy sprzed cięcia dalej nie ma. Test na `CommitRepo`, sprawdzony odwrotnie. Po przeglądzie tej poprawki
(`code-review high`): komunikat rozróżnia bazę z nowszego wydania (użyj tamtego wydania) od bazy sprzed 0.3.0
(odtwórz albo zostań na 0.2), a `up/1` i `down/1` odmawiają też wersji docelowej spoza znanych — migracja hosta
wołająca `up(version: 2..5)` padała na nieistniejącym `V02`. Bez zmiany: baza z sierpnia zapisana jako „1” w starym
schemacie (żadna taka nie istnieje), `down/1` na bazie bez tabel (sprzed tej zmiany), ślad „5” po zabitym przebiegu
testu (naprawia `ecto.drop`).

**Wybory asystenta (mechanika):**
- **Czas zostaje `timestamp`** (Ecto `utc_datetime_usec`), nie `timestamptz` ze szkicu §10.3 — silnik pisze i czyta
  tylko UTC, zmiany typu nie zapowiadano. *Odrzucone:* `timestamptz` przy okazji — zmiana typu każdej kolumny czasu
  bez powodu z kodu.
- **Pakiet auth bez zmian** — jego dwie wersje to dwa `create` bez historii poprawek, a zakres E11c to trzy
  katalogi `priv` silnika. *Odrzucone:* zwinięcie auth razem — osobny pakiet z osobnym mechanizmem wersji.
- **Dane dev przywrócone do nowego schematu** zrzutem tylko danych, zamiast zasiewu od nowa — dzięki temu wyjścia
  narzędzi dało się porównać bajt w bajt z E11b (identyczne).

**Przegląd E11c (pre-pr-review, 29 września).** Dwa przeglądy równolegle na `origin/main..c2544a8`. Bezpieczeństwo
i wydajność: żadnej regresji — blokada dopisu, wyzwalacze tylko-do-dopisu, tożsamość i wszystkie `CHECK`-i jak w
starym V03, żaden usunięty indeks nie był używany, `text` nie zdjął ograniczenia, na którym coś polegało. Rozstrzygnięte:
- **cztery komentarze z V03** — *poprawione* (`418c966`);
- **test nie przypinał tożsamości ani unikalności `id`** — *poprawione* (`418c966`), odwrotnie sprawdzone;
- **brak zapisu E11c w `PLAN.md`** — *poprawione* (ten zapis);
- **`up/1` milczy, a `down/1` pada na bazie z wersją > 1** — *bez zmiany* w tym przeglądzie, decyzją użytkownika wyżej;
  *poprawione* 29 września po komentarzu CodeRabbita (zmiana decyzji opisana wyżej);
- **przykład `up(version: 2)` w moduledoku `Migrations`** — *bez zmiany*: jest opisany jako „gdy późniejsze wydanie
  podniesie `current_version/0`”;
- **`CHANGELOG.md` każe dopisać `up(version: 3|4|5)`** — *pominięte do E11d* (CHANGELOG 0.3.0);
- **stara baza dev z tabelami v1 TaxVision** — *bez zmiany*, bazy się odtwarza;
- **500 przy bardzo długim polu korelacji, pełne skany `_commands`** — sprzed E11c, w otwartych pytaniach.

### E11d-1 — co wyszło (29 września)

**Podział E11d (wybór asystenta):** E11d-1 — dokumentacja pakietu, generowana i ręczna, z testem, który ją trzyma
przy kodzie; E11d-2 — proza reszty repozytorium (`CLAUDE.md`, główne README, CHANGELOG, §18, „v2” w komunikatach).
*Odrzucone:* jedna część — diff na kilka tysięcy linii nie do przeczytania z uwagą.

Na `dsl-v2/e11d-docs`, od `a2973fb`:
- **`14dc852`** — `mix eh_os_contract.docs` wraca pod starą nazwą (tą z opisu bramy w `CLAUDE.md`): pisze
  `docs/dsl/domain.md` i `docs/dsl/contract.md` z rozszerzeń Sparka (`Spark.CheatSheet`), `--check` w `mix check`
  pakietu, obie strony w `extras` ExDoca. `docs/contract.md` od nowa: przewodnik po domenie i kontrakcie (najmniejsza
  para, która się kompiluje, implementacja, dispatch) i tabela każdej odmowy L2–L4 z kodem. README pakietu od nowa pod
  v2. `test/docs_test.exs`: przykłady definiujące moduł kompilują się stronami, razem z L3; kody w tabeli = kody w
  kodzie; każdy ma test w `test/dsl/`; każda deklaracja i klucz obu DSL-i ma opis; linki względne prowadzą do stron.
- **`7b3c293`** — brama uniwersalności przypięta od nowa: „zero nowych słów” liczy się od literału w
  `contract_vocabulary_test.exs` z 29 września, nie od kluczy v1 (v2 wymieniło słownik hurtem, przejmując ESDM).
- **`ccb1474`** — testy trzech bram v1, które v2 zachowało bez testu (zapis z E11a): dwie komendy jednej nazwy (N1),
  `by: []` (C1), jednostka kalendarzowa w `within` (R6).
- **`d969398`** (po przeglądzie) — tabela odmów napisana od nowa z każdej gałęzi kodu, która zgłasza kod (wiersze
  przygotował agent, sprawdzone wyrywkowo D14, X4, R6, F5); `docs_test` przypina kolumnę warstwy do miejsca, z którego
  kod pada (stary wiersz F5 go łamie); przykłady `dispatch` z pełną nazwą struktury; README: rotacja klucza głównego w
  trzech wdrożeniach i `Personal.rewrap!/2` dla wydania, koszt kopii zapasowych przy odtworzeniu, kopie danych
  osobowych w read modelach.

**Wybory asystenta:** referencja w osobnych plikach `docs/dsl/`, nie w bloku `docs/contract.md` — kontrakt to 2050
linii i zagrzebałby przewodnik (*odrzucone:* blok w przewodniku; jeden plik na oba DSL-e). Pliki commitowane z
`--check`, jak `rules.md` — zmiana DSL-a widać w diffie PR-a (*odrzucone:* generowanie przy `mix docs` i
`.gitignore`). Własny task zamiast `mix spark.cheat_sheets`, który wymaga Ignitera (opcjonalnej zależności Sparka).
Użytkownik zapytał o to w trakcie; wyjaśnione, bez zmiany decyzji.

**Przegląd E11d-1 (pre-pr-review, 29 września).** Dwa przeglądy równolegle na `a2973fb..7b3c293`. Rozstrzygnięte:
- **wiersz R6 nieprawdziwy, F5 i D11 bez L3, P4/A4/A6 i inne niepełne; kolumna warstwy niesprawdzana** —
  *poprawione* (`d969398`);
- **`codes_in_lib` liczył przykład z docstringu, tylko jednoliterowe prefiksy; komentarz w teście liczył się za
  test** — *poprawione* (`d969398`);
- **przykłady `dispatch` z krótką nazwą struktury** — *poprawione* (`d969398`);
- **README: rotacja w jednym wdrożeniu, `mix` w wydaniu, kopie zapasowe** — *poprawione* (`d969398`);
- **główne README i `CLAUDE.md` opisują stary task `docs`** — *pominięte do E11d-2*;
- **odwołania „v2 §N”, „plan EM3” w opisach DSL-a trafiają do HexDocs** — *pominięte do E11d-2* (proza w `lib/`);
- **szkielet `--check` powtórzony w dwóch taskach** — *bez zmiany*: dwa małe taski, wspólny helper to więcej kodu niż
  powtórzenie;
- **klucz idempotencji globalny, blokady `rewrap!` a `erase/3`, `mix rewrap` uruchamia hosta** — sprzed E11, w
  otwartych pytaniach, klucz idempotencji do użytkownika.

### E11d-2 — co wyszło (29 września)

Na `dsl-v2/e11d-docs`, po E11d-1:
- **`6bfea09`** — komunikaty, `@shortdoc`, jednolinijkowe `@doc`, opisy obu DSL-i i katalog reguł bez „v2 contract” i
  bez odwołań do ADR-a i planu (te trafiają do HexDocs przez `docs/dsl/` i `docs/rules.md`); moduledoki i komentarze
  zachowują „v2 §N” — czyta je ktoś z repozytorium.
- **`8069e58`** — CHANGELOG 0.3.0: „Removed — E11a”, zmiany nazw E11b z pułapką `Registry.contracts/0`, jedna migracja
  E11c w miejsce trzech nieaktualnych instrukcji, odmowy R2/P4/pusty `:id` i zawieszenie obietnicy z E11a; wpisy w
  CHANGELOG-ach weba i auth. Dwie zaległości planu: jednostka samych nagrań nie ma czego implementować, testy
  `async: true` piszące log czekają na siebie.
- **`fcede91`** — główne README od nowa (domena i kontrakt, dispatch, trzy sposoby dostarczania reakcji, obietnica w
  zdaniach raportu, taski, `docs/dsl/`, broker według E12).
- **`42442dd`** — `CLAUDE.md`: brama, tabela „Zanim cokolwiek zmienisz”, Rehmed z kodem, „czym biblioteka jest”,
  obietnice zamiast `trace`, „implementacje wskazują kontrakt, nigdy odwrotnie” zamiast „MFA, nigdy capture”, literały
  `emit/1` i `issue/1`, lista polskich stringów bez kluczy v1, dashboard bez stanu biznesu mimo read modeli.
- **`029ca1e`** — ostatnie wiersze v2 §18: dopiski z datą w `technology-notes` §1, §2, §12, §13.
- **`32d99a3`**, **`2d696a6`** (po przeglądzie) — niżej.

**Przegląd E11d-2 (pre-pr-review, 29 września).** Dwa przeglądy równolegle na `ad01460..029ca1e`. Rozstrzygnięte:
- **CHANGELOG: „odtwórz bazę” bez szczegółów** (utrata danych przy literalnym czytaniu, stare pliki migracji
  wywracają świeżą bazę) — *poprawione* (`2d696a6`): baza z danymi zostaje na 0.2.x, kroki dla deweloperskiej;
- **CHANGELOG: zadania `EhOsContract.Job`** (praca ginie, argumenty trzymają ładunek i aktora) — *poprawione*;
- **CHANGELOG: `graph` bez flagi wychodzi z błędem, reguła pliku mówi o `trace`** — *poprawione*;
- **README: aktor „sprawdzany względem `by:`”** — nieprawda dla aktora z credentiala (uprawnienia i zakresy z
  credentiala; `by:` bezpośrednio tylko dla `:system`) — *poprawione* w obu README;
- **README: blokada dopisu przy reakcjach `:in_transaction`, efekt w transakcji, „expect the wait” (timeout)** —
  *poprawione*;
- **README: wycinek raportu opisany jak całość, brak `--process`, brak `rewrap`** — *poprawione*;
- **przewodnik: jednostka samych nagrań ze stanem potrzebuje `evolve/2`** — *poprawione*;
- **`check` wypisywał „(D3)”, którego katalog już nie ma** — *poprawione* (`32d99a3`), razem z „v2 contract” w
  moduledokach dotkniętych plików (to, co wypisuje `mix help`);
- **format i miejsce dopisków w `technology-notes`** — *poprawione*;
- **brak odmowy w `up/1` dla bazy z wersją > 1** — *poprawione* po komentarzu CodeRabbita do #46, na polecenie
  użytkownika (`e36c30e`, `ef33f89`; opis w „E11c — co wyszło”);
- **„idempotency to tylko nazwa”** — *bez zmiany*: README mówi „names what makes a second delivery harmless”, co jest
  dokładnie tym, co P3 sprawdza;
- **„v2 §N” w moduledokach niedotkniętych plików** — *bez zmiany*: odwołania do dokumentu repozytorium, dla czytelnika
  repozytorium.

### Komentarze CodeRabbita do #46 (29–30 września)

Na polecenie użytkownika („rozwiąż komentarze coderabbit”, „sprawdź komentarz code rabbita”). #47 zmergował się do
gałęzi E11c, więc CodeRabbit ocenia E11d w #46.
- **Odmowa w `up/1` dla bazy z wersją > 1** (29 września) — *poprawione*, opis w „E11c — co wyszło”.
- **`docs/contract.md` i `docs/dsl/contract.md` dzielą w ExDocu nazwę strony** (30 września) — *poprawione*.
  CodeRabbit pisze, że referencja nadpisuje przewodnik; na ExDocu 0.40.4 nie nadpisuje, tylko numeruje strony
  (`contract-1.html`, `contract-2.html`) w kolejności `extras`, więc adres przewodnika zależałby od kolejności listy.
  Strony referencji to `docs/dsl/domain-dsl.md` i `docs/dsl/contract-dsl.md`, a `docs_test` pilnuje, że żadne dwie
  strony dokumentacji nie mają jednej nazwy bazowej (sprawdzone odwrotnie). Zapis E11d-1 wyżej wymienia stare nazwy.
- **Handoff z nieaktualnymi pozycjami** (30 września) — *poprawione*: pozycja „Z E11c do E11d” zrobiona, odmowa w
  `up/1` w zapisie przeglądu E11d-2 oznaczona jako poprawiona, stan gałęzi po merge'u #47 do bazy E11c.

### E11e — co wyszło (30 września)

Samą dokumentację w `.claude/skills/` i dopisek w `docs/adr/technology-notes.md` §8 zrobiono na gałęzi
`claude/e11e-skills-dsl-v2-ab38c4`, od `6df5bc7`, z wciągniętym handoffem `306ed55` z `dsl-v2/e11e-skills`
(polecenie użytkownika).
- **Pięć przepisanych:** `add-event`, `change-contract`, `contract-distillation` (z `output-template.md`),
  `module-boundary-check`, `review-pr`. **`write-handler` usunięty**, w jego miejsce `write-decider` (agregat i
  DCB: `emit/1`, `reject/1`, `evolve/2`, czysta decyzja) i `write-reaction` (policy, effect, process manager,
  read model z query: `delivery`, `idempotency`, gdzie startuje nowy konsument).
- **`pre-pr-review`:** `docs/contract.md` nie jest „samą dokumentacją”, bo `test/docs_test.exs` kompiluje jego
  przykłady i trzyma tabelę odmów przy kodzie, a `docs/dsl/` i `docs/rules.md` porównują `docs --check` i
  `rules --check`. Przy okazji „MFA rather than capture” zamienione na regułę z `CLAUDE.md` („implementacje
  wskazują kontrakt”).
- **Dopisek z datą w `technology-notes` §8:** co z tabeli planowanych skilli faktycznie istnieje.

**Decyzja użytkownika (30 września, w trakcie):** skille opisują jeden DSL jako fakty, bez „v1/v2” i bez
porównań ze starym — „nie mamy żadnej aplikacji w v1 ani w v2, nie potrzebujemy zgodności wstecz”. *Odrzucone:*
pierwsza wersja tej roboty, która pisała „written for the v2 DSL”, „v1 kept old rows…”, „the v1 question is
gone” — każde takie zdanie uczy czytelnika wersji, której nie ma. Zostają tylko nazwy plików
(`docs/adr/contract-v2.md`) i wersjonowane nazwy publikacji (`….v1` w `publish … as:`), bo to pojęcia DSL-a.

**Wybory asystenta:**
- Skille wskazują **kody odmów** z `docs/contract.md` i **nazwy reguł** z `docs/rules.md`, nie numery linii
  źródła, które skille v1 cytowały i które zgniły. *Odrzucone:* cytaty `plik:linia` — `technology-notes` §8
  mówi, że skille mają być krótkie i wskazywać kod i sprawdzenia, a kody i nazwy są stałe między wersjami.
- **Jeden `write-reaction` zamiast czterech** (po jednym na rodzaj). Wspólne pytanie — co zostawia w logu
  awaria po każdej stronie granicy transakcji — jest to samo dla wszystkich; tabela rodzajów jest na górze.
  *Odrzucone:* osobny `add-projection` z `technology-notes` §8 — powtórzyłby połowę `write-reaction`.
- **`change-contract` od nowa z kodu, nie z tabeli v1.** Tabela v1 była o logu, którego nikt nie czyta
  ponownie. Tutaj każdy stary wiersz jest dekodowany dzisiejszą deklaracją przy każdym złożeniu strumienia, więc
  wiersze tabeli są inne. Pięć z nich sprawdzone wprost na `Codec.decode/4` w `MIX_ENV=dev mix run --no-start`:
  dodane pole wymagane daje `:required`, usunięte pole jest pomijane, zmiana typu i usunięty element enuma dają
  `:type`, dodane opcjonalne daje `nil`.
- **Lista plików wyzwalających pytanie o CHANGELOG** (w `review-pr`, jedyne jej miejsce według CHANGELOG-a)
  rozszerzona o `paths.ex`, `coverage.ex`, `event_run.ex`, `dependency.ex`, `digest.ex`, `duration.ex`,
  `conformance/`, `report/`, `graph/`.

**Ustalenia z pisania (do E11f albo dalej, bez zmian w kodzie):**
- **Żaden test nie przypina, że strumień ze starym wierszem, który nie pasuje do deklaracji, odmawia głośno**
  („no longer fits” w `Consumer.decode!/5`). Na tym stoi cała tabela `change-contract`. Kandydat na E11f.
- **Upcasterów nie ma.** `schema_version` jest na każdym zdarzeniu, ale nic go nie czyta poza AsyncAPI.
  v2 §10.6 opisuje upcaster i regułę `check` („digest danych ruszył, a log ma wiersze tego typu”); jedno i
  drugie niezbudowane. Do tego czasu każda niekompatybilna zmiana zdarzenia z historią to nowe zdarzenie albo
  robota na danych.
- **Wiersz logu zapisuje nazwę modułu kontraktu**, a subskrypcje, process managery i zadania efektów rozwiązują
  przez nią deklarację (`Module.safe_concat([row.contract])`). v2 §5 mówi, że typ `"<process>.<event>"` chroni
  historię przed zmianą nazwy modułu — dla typu tak, dla tych trzech czytelników nie. Do sprawdzenia w E11f,
  potem poprawka z datą w v2 §5.
- **Przykład `rejestry` z `sandbox/lib/taxvision/registry_check.ex`**, na który wskazywał stary `review-pr`,
  już nie istnieje (plik zniknął w E9c-1, `a0e6faa`). Lekcja zostaje w `CLAUDE.md` i w `review-pr`, bez ścieżki.

**Weryfikacja:**
- Brama bazowa na `6df5bc7` przed zmianą: `EXIT=0`, liczby jak w handoffie (sandbox 143, `check` 0/29/9;
  silnik 986, 0/66/5; web 52; auth 62).
- Skrypt w scratchpadzie sprawdził każdy kod odmowy, nazwę reguły, ścieżkę i moduł cytowane w dziesięciu plikach
  skilli: wszystkie się rozwiązują (poza nazwami, które nie są regułami: `process-extraction`, `eh-os`,
  `code-review`).
- Stare słownictwo (`Handler`, `Next`, `Emitter`, `retain`, `trace`, `instance`, `payload`, `v1`, `v2`,
  `DRAFT`) szukane dwoma narzędziami, `grep -rE` i `git grep -w --untracked` (bez `--untracked` pomija nowe
  pliki). Zostały tylko angielskie słowa i nazwy plików.
- Brama po zmianie skilli: `EXIT=0`, liczby bez zmian (sandbox 143, `check` 0/29/9; silnik 986, 0/66/5; web 52;
  auth 62). Poprawki po przeglądzie niżej dotknęły już tylko `.claude/skills/`, których brama nie czyta.

**Przegląd E11e (30 września).** Zmiana jest samą dokumentacją, więc zamiast `/code-review` agent sprawdził
każde twierdzenie skilli z kodem silnika. Znalazł 3 błędy i 10 nieścisłości; wszystkie *poprawione*:
- **błędy:**
  - `change-contract` pisał `changed` przy przemianowaniu jednostki i komendy — digest jest kluczowany
    `"<kind>:<name>"`, więc przemianowanie to `removed` + `added`;
  - `pre-pr-review` liczył `docs/` jako czytane przez nikogo, a `contract_examples_test.exs` kompiluje przykłady
    z `docs/adr/contract-v2.md`, `docs_test` przykłady README pakietu i `authorization.md`, a linki sprawdza w
    CHANGELOG-u;
  - na liście plików do CHANGELOG-a brakowało `contract/build.ex`, z którego bierze się wersja i digesty
    deklaracji; dopisane, razem z `store/postgres.ex`, `key.ex` i `dispatcher.ex` przy zmianach runów, kluczy
    i etykiet awarii;
- **nieścisłości:**
  - jednostka bez `evolve/2` nie czyta historii, więc jej nie łamie;
  - jeden zły wiersz typu konsultowanego przez DCB łamie każdą decyzję tego DCB;
  - zadanie efektu po trzech próbach jest odrzucane, a nie `failing`;
  - niektóre zmiany typu dalej się dekodują (`:integer` → `:decimal`);
  - DCB czyta po typach i tagach, nie po `stream_id`;
  - process manager też bywa `stale`;
  - zdarzenie rejestrowane przez człowieka ma własne uprawnienie;
  - `publish` edytowany nie jest odmawiany (to reguła projektu, nie kod `D11`);
  - read model ma partie po 500;
  - zdarzenie bez pól `correlate` process managera przechodzi kompilację i nie trafia do żadnego runu;
  - wymyślony przykład prefiksu zastąpiony prawdziwym (`accounting_month_opened`), z decyzją z EL1: nazwa
    zostaje z warsztatu;
  - wycinek `VisitSettlement` oznaczony jako wycinek.

### E11f — co wyszło, część 1 (30 września)

Na `dsl-v2/e11f-engine`, od `406bb07`; przegląd (`pre-pr-review`, dwa przeglądy równolegle) na E11f-1 przed
kolejnymi częściami.
- **E11f-1, `510b1fb`** — klucz idempotencji w zakresie aktora (decyzja niżej): wyszukiwanie i unikalny indeks po
  `(issued_by, idempotency_key)`. V01 poprawione w miejscu — 0.3.0 nie jest wydane, więc nie ma bazy do
  aktualizowania (*odrzucone:* V02 — kolidowałby z odmową dla baz zapisanych jako „2”–„5” sprzed E11c). **Wspólne
  bazy lokalne dostały nowy indeks ręcznie** (`DROP INDEX` i `CREATE UNIQUE INDEX` w pięciu bazach z tabelami
  silnika; dane zostały). Sprawdzone odwrotnie: bez nowego wyszukiwania i przy starym indeksie padają te same dwa
  testy.
- **Przegląd E11f-1** — rozstrzygnięte:
  - pusty `sub` daje etykietę `actor:` wspólną dla wszystkich — *poprawione* (`291c27c`, sprawdzone odwrotnie);
  - zmiana `sub` między próbą a ponowieniem uruchamia komendę drugi raz; wspólny credential i wspólny aktor
    `:system` dzielą przestrzeń kluczy — *poprawione* w dokumentacji (`1272cf2`: `docs/authorization.md`,
    CHANGELOG);
  - moduledoc `Migrations` obiecywał, że V01 się nie przepisuje — *poprawione* (`1272cf2`);
  - nieaktualne komentarze w `v01.ex` i `dispatcher.ex`, słaba asercja drugiego testu — *poprawione*;
  - klucz z etykietą ponad ~2,7 KB wywraca zapis wiersza `accepted` (500) — *pominięte*, rozszerza otwarte pytanie
    z przeglądu E11c (limit długości to nowy powód odmowy, do użytkownika);
  - ten sam aktor z tym samym kluczem i komendą o innym zakresie albo treści dostaje stary paragon — *pominięte*:
    to opcja „skrót treści”, odrzucona w decyzji niżej; zostaje w otwartych pytaniach;
  - testy nie pokrywają `record/3` ani ścieżki pod blokadą — *bez zmiany*: wszystko idzie przez jedno
    `idempotent/2`.
- **E11f-2, `d718cee`** — testy, że strumień ze starym wierszem, który nie pasuje do deklaracji (brak wymaganego
  pola, typ już niezadeklarowany), odmawia głośno: `failed` w `evolve`, nic nie dopisane. Zachowanie było, testu
  nie było (ustalenie E11e). Sprawdzone odwrotnie mutacjami dekodera.
- **E11f-3, `0af122d`, wycofane w `28620e9`** — subskrypcja, process manager i zadanie efektu dekodują wiersz przez
  nazwę modułu zapisaną na nim, więc po zmianie nazwy modułu kontraktu subskrypcja ląduje w `failing` na pierwszym
  starym wierszu. Poprawka szukała deklaracji od kontraktu czytającego, jak dispatch. **Przegląd pokazał, że to
  pogarsza sprawę:** klucz konsumenta niesie nazwę modułu, więc przemianowany read model rejestruje się od nowa od
  pozycji 0, bez `reset/0`, i po poprawce **po cichu projektował log drugi raz**, zamiast odmówić głośno. Zmiana
  nazwy dalej psuje ponowienie idempotentne (`idempotency_key_reused`), zadania efektów w kolejce (anulowane) i
  timery process managerów (ignorowane). Pół-obsługa, która działa po cichu, jest gorsza od głośnej odmowy.
- **Przegląd E11f-2 i E11f-3** — rozstrzygnięte:
  - cicha podwójna projekcja i pozostałe skutki zmiany nazwy — *wycofane* (`28620e9`); poprawiona nota w
    `docs/adr/contract-v2.md` §5 i wiersz `change-contract` („nie przemianowuj modułu kontraktu z historią”);
  - strażnik podmiotu przepuszczał same białe znaki i nie był opisany — *poprawione* (odmowa pustego po `trim`,
    `@doc` `Actor.credential/3`, moduledoc `Auth`);
  - host składający `%Actor{}` literałem omija strażnika — *bez zmiany*: jedyną udokumentowaną drogą jest
    `credential/3`, a ścieżka przez pakiet auth jest zamknięta;
  - istniejąca baza ze starym indeksem idempotencji daje 500 zamiast dwóch komend — *bez zmiany*: 0.3.0 nie jest
    wydane, CHANGELOG mówi, jak przebudować indeks;
  - `sibling!` nie sprawdza, czy czytający konsumuje akurat to zdarzenie rodzeństwa — *pominięte*, sprzed E11f, w
    dispatchu; niskie (typy są unikalne w systemie, X7).
- **Decyzja użytkownika (30 września), z E11f-3: silnik dalej rozpoznaje kontrakt po nazwie modułu.**
  Dekodowanie w subskrypcjach, klucze konsumentów, ponowienia i raport zgodności zostają, jak są. Zmiany nazwy
  modułu kontraktu z historią się nie robi — mówi to `change-contract` i v2 §5. *Odrzucone:* rozpoznawanie po
  nazwie procesu (unikalnej w systemie, X7, i obecnej w typie każdego zdarzenia) — zmienia klucze konsumentów,
  zapytania raportu, idempotencję i odczyt w trzech czytelnikach, a nikt jeszcze nie przemianowuje kontraktów z
  historią.
- **Decyzja użytkownika (30 września), E11f-5: wariant B** (jednostka czyta tylko to, co składa `evolve/2`).
  *Odrzucone:* (A) słowo DSL-a z listą składanych zdarzeń — powtarza `evolve/2` i może się z nim rozjechać; (C)
  przebudowa sandboksa — pułapka zostaje dla następnego klienta; (D) zostawić do pomiaru.
- **E11f-4, `005bcad`** — jeden odczyt zakresu komendy i query w dispatchu (były dwie kopie) i jedna pętla D10
  po zakresowanych komendach i query; `one_value/2` oparte na `Key.base_type/2`. Zachowanie bez zmian: testy D10 i
  zakresu przechodzą, a padają przy zepsutej gałęzi listy (1) i kodowaniu zakresu (7).
- **E11f-5 — jednostka czyta tylko to, co składa jej `evolve/2`** (decyzja użytkownika niżej, wariant B).
  - **Problem.** `TurnoverMatching` (TaxVision) przy każdym `run_matching` czytał i dekodował wszystkie
    `bank_turnover_list_created` miesiąca, każdy z całą listą obrotów, choć jego `evolve/2` przepuszcza je bez
    zmiany (`def evolve(state, _event), do: state`). Wyciąg z N obrotami daje N komend, a każda czyta wszystkie
    dotychczasowe wyciągi: O(N²). Do tego każde wgranie wyciągu kolidowało z trwającym dopasowaniem, bo warunek
    konfliktu DCB obejmował typ, od którego decyzja nie zależy.
  - **Obserwacje.**
    - Stan jednostki jest funkcją tylko tych zdarzeń, które `evolve/2` zmienia. Informacja „które” już jest w
      kodzie — w głowach klauzul — i I3 już je skanuje.
    - Da się ją odczytać pewnie tylko w jednym kształcie: każda klauzula bez struktury zdarzenia to dosłownie
      `def evolve(state, _), do: state`. Każdy inny catch-all albo strażnik na zmiennej mogą składać cokolwiek.
    - Agregat i tak musi czytać cały strumień, bo wersja strumienia jest warunkiem dopisu — zysk jest tam tylko
      w dekodowaniu. W DCB zawęża się też zapytanie i warunek konfliktu.
    - `given_types` komendy boundary tracą pominięte typy, a pokrycie scenariuszy porównuje na nich `given`;
      bez zmiany w `Coverage` scenariusz z `given` pominiętego zdarzenia przestałby być obserwowany.
    - Typ, którego kontrakt już nie deklaruje, nie może być „pominięty”: to historia po zmienionym kontrakcie
      i ma dalej zatrzymywać strumień (pierwsza wersja go przepuszczała; wyłapał to test E11f-2).
  - **Zrobione.**
    - `Implementation` zapisuje `folds` (lista albo `:all`) w `__eh_os_implementation__/0`;
      `Implementations.folded_types/2` daje z tego typy logu.
    - Dispatch dekoduje tylko typy składane i niezadeklarowane, a zapytanie boundary zawęża do składanych;
      gdy nie zostaje nic, zostaje pełne zapytanie, bo magazyn odmawia pustego.
    - `Coverage` porównuje `given` na typach składanych.
    - `record/3` czyta jednostkę w całości, jak przedtem.
  - **Testy i próby odwrotne.**
    - `implementation_test`: cztery kształty `evolve/2`;
    - dispatch: niepasujący wiersz pominiętego `account_opened` nie blokuje wpłaty;
    - `coverage_test`: scenariusz z `given` pominiętego typu dalej jest obserwowany;
    - sandbox: `run_matching` nie ma w `given_types` wyciągów, a ma faktury.
    - Każdy z tych testów pada przy swojej mutacji: bez zawężenia zapytania pada test sandboksa, bez pomijania —
      test dispatchu, przy catch-allu uznawanym zawsze za „bez zmian” — dwa testy `folds`, bez filtra w
      `Coverage` — test pokrycia.
  - **Wnioski.**
    - Skoro „które zdarzenia” jest już w `evolve/2`, drugie miejsce na tę informację (słowo DSL-a) mogłoby się z
      nim rozjechać. Dlatego wybór B, a nie A.
    - Koszt B: zysk dostaje tylko kod pisany w jednym kształcie. `write-decider` mówi teraz, żeby catch-all był
      dokładnie `def evolve(state, _), do: state`, i dlaczego.
    - Warunek konfliktu DCB zawęża się poprawnie, bo od pominiętych zdarzeń decyzja nie zależy — ale to zmiana
      zachowania widoczna dla hosta (mniej `:conflict`), więc wpis w CHANGELOG-u.
    - Wiersz pominiętego typu, który przestał pasować do deklaracji, nie blokuje już strumienia. Tabela
      `change-contract` o tym mówi.
  - **Weryfikacja:** brama `EXIT=0` — sandbox **144** (+1), `check` 0/29/9; silnik **996** (+6), `check` 0/66/5;
    web 52; auth 62.
- **Przegląd E11f-4 i E11f-5** (dwa przeglądy równolegle; nic wysokiego, zawężenie warunku DCB uznane za poprawne:
  decyzja zależy tylko od stanu, a stan tylko od składanych zdarzeń) — rozstrzygnięte:
  - `folded_types` szukało implementacji w indeksie drugi raz na każdy dispatch, a pominięcie liczyło typy
    zadeklarowane dla każdego wiersza — *poprawione*: typy z modułu, który dispatch już ma, zbiór raz na dispatch;
  - boundary, które nie składa żadnego zdarzenia, wraca do pełnego zapytania (magazyn odmawia pustego), wbrew
    zdaniu w CHANGELOG-u — *poprawione* w CHANGELOG-u i ADR; w tym wypadku pomijane są też konsultowane typy
    rodzeństwa, nie tylko własne;
  - nieprawdziwy komentarz w `Coverage` (agregat zapisuje cały strumień) i opis testu pokrycia — *poprawione*;
  - `Coverage` bez implementacji w indeksie (zła konfiguracja `applications:` węzła) porównuje pełne `given`,
    a dispatch by odmówił — *bez zmiany*: zła konfiguracja wywraca już dispatch;
  - `folds/3` i I3 przechodzą po klauzulach osobno — *pominięte*, porządki; jedna wspólna analiza przy następnej
    zmianie kształtów klauzul;
  - agregat dalej pobiera z bazy całe wiersze strumienia, oszczędza tylko dekodowanie — *bez zmiany*, zapisane w
    „Obserwacjach” wyżej.
- **Weryfikacja:** brama po wycofaniu i poprawkach przeglądu `EXIT=0` — sandbox 143, `check` 0/29/9; silnik **990**
  (986 + 2 testy klucza + 2 testy historii), `check` 0/66/5; web 52; auth 62.

### Przed E11f — decyzja użytkownika (30 września)

**Klucz idempotencji w zakresie aktora.** Dziś `Dispatcher.idempotent/2` szuka przyjętej komendy po samym kluczu
(porównuje tylko kontrakt i typ), a unikalny indeks `eh_os_contract_commands_idempotency_index` jest na samym
`idempotency_key`. Dwie osoby z tym samym uprawnieniem i tym samym kluczem — przypadkiem (dwie instancje klienta
numerujące od `req-1`) albo celowo — dają dwa skutki. Komenda drugiej osoby po cichu się nie wykonuje
(`duplicate: true`). Druga osoba dostaje też paragon pierwszej: zdarzenia z odszyfrowanymi polami osobowymi, także
spoza jej zakresu, bo zakres sprawdzono na jej własnej komendzie. Decyzja: szukanie i unikalny indeks po parze
(kto wysłał, klucz), w E11f. Powtórzenie przez tego samego aktora dalej zwraca paragon, a ten sam klucz z inną
komendą dalej daje `idempotency_key_reused`. Komendy reakcji i timerów mają deterministyczne klucze i własnego
aktora, więc zmiana ich nie rusza. Zmiana jest widoczna dla hosta: dwie osoby z tym samym kluczem przestają się
blokować.
*Odrzucone:*
- **globalny klucz plus wymóg UUID w dokumentacji** — bezpieczeństwo zależałoby od każdego klienta, a błąd jest
  cichy;
- **zakres aktora plus skrót treści komendy** — `_commands` celowo nie trzyma treści, a skrót pól o małej
  zmienności (kwota, identyfikator pacjenta) da się odtworzyć zgadywaniem; wraca, gdy ktoś będzie potrzebował
  wykrywać ten sam klucz z inną treścią.

### #51 — tabele poza `public` — co wyszło (30 września)

**Zgłoszenie** (issue #51, z budowy pierwszej aplikacji klienta z szablonu ehos-tools): EHOS daje aplikacji
własny schemat `<aplikacja>_<środowisko>` z dwiema rolami (`eh-os` D-54, D-56) — właściciel migruje i nie ma
`CREATE` na `public`, rola aplikacji ma tylko `SELECT`/`INSERT`/`UPDATE`/`DELETE` (i `USAGE` na sekwencjach, z
domyślnych uprawnień). Aplikacja ustawia schemat jako `search_path` połączenia. Obie migracje tworzyły tabele
bez kwalifikacji (czyli w schemacie ze ścieżki), ale wersję czytały i zapisywały na `public` po nazwie
(`nspname = 'public'`, `COMMENT ON TABLE "public"....`).

**Gorzej, niż mówi zgłoszenie.** Zgłoszenie opisuje błąd `relation "public.eh_os_contract_events" does not
exist` — tak jest, gdy `public` jest pusty. Gdy `public` **ma** tabele (jak nasza baza testowa), `up/0` czytało
ich „1”, nie tworzyło w schemacie niczego i przechodziło; aplikacja padała dopiero na pierwszym zapisie przy
starcie (`Deployment.record!`). Sprawdzone odwróceniem poprawki.

**Wybór: przez `search_path`, nie opcja `prefix:`.** Wersję czyta w `current_schema()` (tam, gdzie `CREATE
TABLE` kładzie tabele), zapisuje niekwalifikowanym `COMMENT ON TABLE`, który po utworzeniu trafia w tę samą
tabelę, bo `current_schema()` jest pierwszy na ścieżce; tak samo rozwiązuje każde zapytanie w runtime (schematy Ecto nie mają `@schema_prefix`, `Store`, `Personal`, klucze auth — wszystko
niekwalifikowane; wyzwalacze wołają `eh_os_contract_append_lock()` też bez schematu). *Odrzucone:* **`prefix:`
dla tworzenia, odczytu i komentarza** — migracja z prefiksem przy zapytaniach runtime bez prefiksu to dwa źródła
prawdy o tym, gdzie są tabele; spójnie wymagałoby prefiksu w każdym zapytaniu silnika i auth, czyli dużego diffu
i opcji, którą host musi podać dwa razy (repo i migracja), a EHOS i tak ustawia `search_path`. Wraca, gdy ktoś
będzie potrzebował tabel silnika poza ścieżką połączenia. *Odrzucone też, po przeglądzie:* **`to_regclass`**
(pierwsza wersja poprawki) — znajduje pierwsze trafienie na całej ścieżce, więc przy `"ledger, public"` z tabelami
w `public` czytało ich „1” i nie tworzyło niczego, a `down/1` przy pustym schemacie zrzucał tabele `public`.

**Przegląd reszty obu pakietów** (zapytania runtime, DDL):
- **Znalezione i naprawione: `oban_jobs` bez prefiksu Obana.** `Paths` (liczniki zadań efektów i timerów w
  raporcie) i `ProcessManager.queued?/5` (czy timer ma zadanie w kolejce przy przebudowie) czytały
  niekwalifikowane `oban_jobs`, więc padały, gdy prefiks Obana nie jest na ścieżce. Teraz `prefix:
  ^Oban.config().prefix` na samym źródle `Oban.Job` (złączenie z `Event` zostaje na ścieżce). W układzie EHOS-a
  (Oban w tym samym schemacie, ehos-tools#3) działało i przedtem — werdykt się nie rusza.
- **DDL w runtime: żadnego.** `execute`/`CREATE`/`ALTER`/`DROP`/`TRUNCATE` są tylko w migracjach; przebudowa read
  modeli rigów robi `DELETE`. Test to przypina: rola aplikacji nie posiada żadnej relacji ani przed, ani po całym
  przebiegu (tabela tymczasowa też by się policzyła).
- **Znalezione, niezmienione — do decyzji: klucz blokady dopisu jest jeden na bazę, nie na log** (v2 §10.2,
  poprawka z datą w `docs/adr/contract-v2.md`). Blokada doradcza należy do całej bazy, a EHOS trzyma wszystkie
  aplikacje instancji w jednej bazie `apps` — D-54 mówi to wprost. Dopisy wszystkich aplikacji na silniku
  serializują się więc wzajemnie. Poprawność zostaje (każdy log widzi pozycje w kolejności commitów), cierpi
  przepustowość wspólna dla wszystkich: blokada trzyma się do commitu, przez reakcje w transakcji, więc wolna
  reakcja aplikacji A wstrzymuje dispatch aplikacji B. Możliwe: dwuargumentowe `pg_advisory_xact_lock(<stała
  int4>, hashtext('<schemat>'))` wypieczone przy migracji — osobna przestrzeń kluczy i przeżywa `pg_dump`
  schematu, którym D-54 odtwarza jedną aplikację; oid tabeli logu wypieczony w funkcji odtworzenia nie przeżywa.
  Przy tej zmianie przypiąć `SET search_path` funkcjom V01 (wyzwalacz woła `eh_os_contract_append_lock()` bez
  schematu, więc przez ścieżkę sesji — sesja operatora z inną ścieżką dostaje dziś „function does not exist”, a z
  kluczem per schemat mogłaby wziąć klucz cudzego schematu). Klucz per schemat usuwa tylko przypadkowe sprzężenie:
  blokady doradcze nie mają uprawnień, więc wrogi albo błędny sąsiad nadal może je wziąć — cena przyjęta w D-54.
  Wszystko to zmienia V01 — dziś „ostateczny kształt” bez wdrożonego konsumenta. Po pierwszym wdrożeniu zmiana to
  V02 podmieniająca funkcję pod ruchem, a przez okno podmiany dopisy pod starym i nowym kluczem mijają się i
  czytelnik gubi pozycje, więc bezpieczna V02 bierze oba klucze przez wydanie. **Do rozstrzygnięcia przed
  pierwszą aplikacją na współdzielonej instancji** (przegląd bezpieczeństwa). *Zrobione 30 września, po
  merge'u #53 — „Klucz blokady dopisu per schemat — co wyszło”.*

**Testy.** `packages/eh_os_contract/test/schema_test.exs` i `packages/eh_os_contract_auth/test/schema_test.exs`:
losowy schemat z właścicielem i rolą aplikacji jak u EHOS-a (warunki wstępne sprawdzane, nie zakładane — brak
`CREATE` na `public`, na bazie i w schemacie). Właściciel migruje w górę, drugi raz (bez zmian), w dół i znów w
górę, a `public` się nie zmienia. Rola aplikacji w silniku: zapis wdrożenia przy starcie, dispatch z read modelami
i polityką w transakcji, efekt przez Obana, kolejne read modele, process manager z timerami, query, erasure
(klucze podmiotów), raport, przebudowa read modeli i process managera z przeterminowanym timerem — dwa razy: z
Obanem w schemacie (jak szablon) i w osobnym schemacie spoza ścieżki (to przypina poprawkę `oban_jobs`). Rola
aplikacji w auth: magazyn kluczy (odczyt przy starcie, zapis po pobraniu, odświeżenie, restart bez EHOS-a z
tabeli) i tabela decyzji. Każda poprawka ma odwrotne sprawdzenie: bez niej odpowiedni test jest czerwony.
Testy podmieniają na czas testu globalną instancję `Oban` (silnik woła ją po nazwie) i stawiają ją z powrotem;
role i schematy sprzątają (sprawdzone: nic nie zostaje w klastrze). Pule ról testowych są po 2 połączenia:
Postgres ma tu 100, `CommitRepo` trzyma 60, a rola bez superusera nie wchodzi w trzy zarezerwowane — przy 4
brama łapała `too_many_connections` (testy przechodziły dopiero po ponownym połączeniu).

**Przegląd** (`code-review` i bezpieczeństwo/wydajność, równolegle). Naprawione, każde z testem czerwonym bez
poprawki: odczyt wersji przez `to_regclass` zamiast w `current_schema()` (oba przeglądy), `down/1` przy niczym
niezapisanym schodzący w tabele następnego schematu na ścieżce (poprawność), raport wymagający uruchomionego
`Oban` (oba — teraz bez niego szuka na ścieżce jak przedtem), wyciek ról testowych przy błędzie w połowie
(oba — `on_exit` przed utworzeniem, losowe hasło). Poprawione w dokumentacji: `EXECUTE` na funkcjach silnika w
uprawnieniach roli aplikacji (z `PUBLIC`, domyślnie), przykład `Oban.Migration.up()` w moduledoc, który pod
właścicielem EHOS-a pada (teraz z `prefix:` i `create_schema: false`), nieobsługiwany prefiks migracji Ecto.
Pominięte: klucz blokady i `SET search_path` funkcji (wyżej, do decyzji); `up(prefix: ...)` przyjmowane i
ignorowane po cichu — odmowa nieznanych opcji zmienia kształt widoczny dla hosta, więc do użytkownika;
wspólny pomocnik źródła `Oban.Job` dla `Paths` i `ProcessManager` — nie, bo `reconcile!/2` zawsze działa z
Obanem (zaraz potem go woła), a raport nie musi.

### Klucz blokady dopisu per schemat — co wyszło (30 września)

**Decyzja użytkownika** (30 września, po merge'u #53): „rób, osobny PR”. Problem opisany w „#51 — co wyszło”:
jeden stały klucz blokady na bazę, więc w bazie `apps` EHOS-a dopisy wszystkich aplikacji czekały na siebie.

**Co jest.** V01 bierze `pg_catalog.pg_advisory_xact_lock(class, log)`. `class` to pierwsze cztery bajty
sha256("eh_os_contract_events append"), wspólne dla silnika; `log` to pierwsze cztery bajty sha256 nazwy schematu,
w którym migracja tworzy log (`current_schema()`). Oba liczy Elixir przy migracji (`V01.lock_key/1`) i wpisuje jako
stałe w `eh_os_contract_append_lock()` oraz w funkcję wyzwalacza. Wyzwalacz nie woła już funkcji przez ścieżkę,
więc `SET search_path` na funkcjach okazał się niepotrzebny: żadne z ich ciał niczego nie rozwiązuje. Wywołanie
`eh_os_contract_append_lock()` w `Store` dalej idzie przez ścieżkę sesji — tak jak tabela, a V01 tworzy obie w
jednym schemacie. Migracja bez istniejącego schematu na ścieżce odmawia z opisem. V01 zmieniony w miejscu (przed pierwszym wydaniem 0.3.0, jak
indeks idempotencji w E11f); bazy zmigrowane wcześniej — wspólne bazy testowe i dev — mają stary klucz, dalej
poprawny, tylko wspólny, do `ecto.drop`.

*Odrzucone:*
- **`hashtext('<schemat>')` liczone w SQL** — `hashtext` to wewnętrzna funkcja Postgresa bez obietnicy stałości
  między wersjami; sha256 w Elixirze to ten sam sposób, którym powstał stary klucz;
- **oid tabeli logu** — wypieczony w funkcji nie przeżywa `pg_dump`/odtworzenia schematu, którym D-54 odtwarza
  jedną aplikację;
- **klucz liczony w runtime** (`TG_TABLE_SCHEMA` w wyzwalaczu, `current_schema()` w `Store`) — dynamiczny SQL
  przy każdym dopisie, a dwa miejsca wyliczałyby klucz z dwóch różnych nazw, gdy pierwszy schemat ścieżki
  aplikacji nie jest schematem logu;
- **wyzwalacz wołający funkcję z nazwą schematu** — klucz w jednym miejscu SQL, ale zmiana nazwy albo odtworzenie
  schematu pod inną nazwą wywraca każdy dopis; dwa ciała z jedną wartością z `lock_key/1` przeżywają obie;
- **blokada wymagająca uprawnień** (z przeglądu bezpieczeństwa: wiersz tabeli jednowierszowej albo `LOCK TABLE
  eh_os_contract_events IN EXCLUSIVE MODE`, których sąsiad bez `USAGE` nie weźmie) — czeka za autovacuum, ANALYZE
  i `CREATE INDEX CONCURRENTLY`, a siatka bezpieczeństwa w wyzwalaczu musiałaby podnosić blokadę, którą INSERT już
  trzyma, więc dwa dopisy z pominięciem `Store` mogłyby się zakleszczyć. Wraca, gdyby sąsiad blokujący log
  przestał być ceną przyjętą w D-54.

**Znalezione przy przeglądzie i naprawione:** klucz liczony zapytaniem wykonanym od razu, przed poleceniami, które
migracja hosta zakolejkowała wcześniej (Ecto wykonuje `execute` i `create` dopiero przy `flush`). `CREATE SCHEMA`
przed `EhOsContract.Migrations.up()` — choćby `Oban.Migration.up(prefix:)` bez `create_schema: false` — dawał
`current_schema()` pusty (odmowa) albo, przy `"ledger, public"`, klucz i wersję `public`. To samo dotyczyło
odczytu wersji z #53, także w auth. Teraz `up/1` i `down/1` obu pakietów robią `flush()` przed pierwszym
odczytem. Przy okazji wyszło, że Ecto zakłada własne `schema_migrations` przez ścieżkę **zanim** ruszy jakakolwiek
migracja, więc schemat tworzony w migracji zostawia tę tabelę w następnym na ścieżce — moduledoc mówi teraz, że
schemat ma istnieć przed migracjami, jak u EHOS-a.
*Bez zmian, z powodem:* literał `-2147483648` (przegląd poprawności twierdził, że Postgres czyta go jako `bigint`)
— sprawdzone w psql: jest `integer`, a proponowane `::int4` wiąże mocniej niż minus i właśnie ten przypadek by
wywróciło; „global” w katalogu reguł i skillu `write-reaction` — w obrębie jednej aplikacji to dalej prawda;
wspólny szkielet testów z `schema_test.exs` — role, uprawnienia i Oban tam, sam superuser tu, wspólne jest dziesięć
linii.

**Czego nie daje:** blokady doradcze nie mają uprawnień, więc sąsiad, który zna klucz, nadal może go wziąć — cena
przyjęta w D-54. Zderzenie 32-bitowego `log` dwóch schematów (ok. 10⁻⁴ przy tysiącu schematów w bazie) wraca dla
tej pary do dzisiejszego czekania, bez błędów. Tak samo schemat przemianowany (albo odtworzony pod inną nazwą obok
oryginału) zachowuje klucz starej nazwy, więc nowy schemat pod tą nazwą dzieli z nim blokadę.

**Test** `packages/eh_os_contract/test/append_lock_test.exs`: dwa schematy w bazie `CommitRepo`, każdy zmigrowany
jak u hosta. Gdy transakcja w pierwszym trzyma blokadę, dopis do drugiego przechodzi — przez funkcję `Store` i
przez wyzwalacz — a do pierwszego czeka (`lock_timeout`, któremu blokada doradcza podlega), także wstawiany z
sesji na ścieżce drugiego; obie funkcje każdego schematu mają jego klucz, różny od klucza drugiego; schemat
tworzony w migracji hosta dostaje swój klucz. W auth: schemat tworzony w migracji hosta dostaje tabele.
Odwrotnie: ze stałym `log` padają „własny klucz” i „inny schemat nie czeka”, a „ten sam log czeka” zostaje
zielony — szeregowanie w jednym logu było i jest; wyzwalacz wołający funkcję przez ścieżkę przepuszcza dopis z
cudzej sesji; bez `flush()` schemat tworzony przez hosta nie dostaje niczego, w obu pakietach.

### #50 — myślnik w przestrzeni nazw publikacji — co wyszło (30 września)

**Zgłoszenie** (issue #50, z budowy szablonu ehos-tools): EHOS nazywa aplikację etykietą DNS (`eh-os` D-43, D-51,
D-55), więc aplikacja OTP `my_shop` jest w EHOS-ie `my-shop`, a jej domena — `name: :"my-shop"`. Wtedy D11 nie
przepuszczał żadnej publikacji: wzorzec `@versioned` (L2) nie znał myślnika, a sprawdzenie przestrzeni nazw (L3)
odrzucało `"my_shop."`.

**Zrobione** (wybór użytkownika z 30 września: #50 przed pozostałymi kandydatami — *odrzucone na teraz:* brama na
#53 i decyzja o kluczu blokady, E12, rozstrzygnięcie #49 i fikstur):
- **Pierwszy segment nazwy może mieć myślnik, nie na końcach**; pozostałe segmenty snake_case jak były. Dotyczy
  `publish as:` i `consumes "<nazwa>"` (jedno sprawdzenie).
  *Odrzucone:* **wzorzec z issue** (`^[a-z]([-a-z0-9]*[a-z0-9])?…`) — wycina podkreślnik z pierwszego segmentu, a
  `dispatch_rig.transfer.completed.v1` jest dziś publikacją fikstury; każda domena OTP nazwana z podkreślnikiem
  przestałaby publikować. To, czy `name:` domeny jest nazwą, jaką EHOS może dać aplikacji, zostaje poza tą zmianą
  (otwarte pytanie w handoffie).
- **`$` → `\z`**: `$` pasuje też przed końcowym znakiem nowej linii, więc `"rehmed.visit.closed.v1\n"` przechodził
  — na brokerze łamie linię tematu. Osobny commit, wpis w CHANGELOG-u w „a host has to act”.
- Opisy `publish as:` i `consumes from:` w DSL-u (i `docs/dsl/`), moduledoc reguły, treść odmowy mówi, gdzie wolno
  myślnik. `docs/rules.md`, o które prosi issue, to katalog ostrzeżeń `mix eh_os_contract.check`, nie odmów
  kompilacji — D11 jest opisany w moduledocu, w `docs/dsl/` i w tabeli odmów `docs/contract.md` (bez zmiany).

**Testy i próby odwrotne.** L2 (`contract_boundaries_test`): kontrola `publish` i `consumes` pod `"my-shop."`;
odmowy myślnika na początku, na końcu i w dalszym segmencie; odmowa nazwy z `\n`. L3
(`contract_links_domain_test`): druga domena `:"my-shop"`, kontrola `"my-shop.payment.recorded.v1"` bez naruszeń i
`"my_shop.…"` poza przestrzenią. Stary wzorzec → padają trzy kontrole i nic więcej; wzorzec przepuszczający myślnik
na końcach → padają dwie odmowy; `$` zamiast `\z` → pada test nowej linii; stara treść odmowy → pada jej test.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle; błędu w zmianie żaden nie znalazł —
żaden czytelnik nazwy nie dzieli jej po kropkach ani nie robi z niej atomów, `-` jest legalny w temacie NATS-a, we
wskaźniku JSON i w kluczu komponentu AsyncAPI; wzorzec liniowy na wejściu do 1 MB):
- stan i decyzja tylko w commicie, nie w `PLAN.md` — *poprawione* (ten zapis);
- odmowa nie mówi, gdzie wolno myślnik — *poprawione*, z testem;
- moduledoc uzasadnia myślnik etykietą DNS, a wzorzec przepuszcza `_` — *poprawione*: moduledoc mówi, że `_`
  zostaje świadomie;
- `consumes from:` bez opisu gramatyki — *poprawione*;
- nowa odmowa nowej linii schowana w „Added” — *poprawione*: „Changed — a host has to act”;
- `name:` domeny bez sprawdzenia, z kropką wychodzi poza przestrzeń nazw (oba przeglądy) — *pominięte*: sprzed
  #50, nowy powód odmowy widoczny dla hosta, do użytkownika (otwarte pytania);
- brak flagi `u` na przepisanej linii — *bez zmiany*: nazwa to identyfikator ASCII, nie tekst klienta, a klasy są
  ASCII.

### `name:` domeny jako przestrzeń nazw — co wyszło (30 września)

**Decyzja użytkownika** (30 września, po merge'u #55): sprawdzenie `name:` przed E12, **z podkreślnikiem**.
*Odrzucone:* **bez `_`** — nazwa domeny byłaby dokładnie etykietą DNS aplikacji EHOS-a, ale odpadłoby 16 fikstur
(`:dispatch_rig`, `:universality_gate`, `:manifest_rig`, …) i podkreślnik z pierwszego segmentu `publish as:`,
który #55 świadomie zostawił; **E12 albo fikstury akceptacyjne najpierw** — E12 zrobiłby z nazw tematy na brokerze
z niesprawdzoną przestrzenią nazw, fikstury czekają na #49.

**Co jest.** Domena odmawia kompilacji, gdy `name:` nie jest jednym segmentem przestrzeni nazw: małe litery, cyfry,
`_` i `-`, na początku litera, bez myślnika na końcu — ta sama gramatyka co pierwszy segment `@versioned` w
`Contract.Rules.Boundaries`. `name: :"acme.billing"` (publikowało `"acme.billing.x.v1"` w przestrzeni `acme`),
`:"shop-"`, `:My_shop`, `:"my shop"`, `:"shop\n"`, `:""` — odmowa; `:"my-shop"`, `:dispatch_rig`, `:shop_` —
kompilują się. Odmowa wskazuje linię `use`: domena zapisuje ją w `persist` jak kontrakt (`:eh_os_contract_line`), a
`DslRules` przyjmuje adnotację źródła tam, gdzie żadna encja Sparka nie trzyma opcji. Wpis w CHANGELOG-u w „a host
has to act”: odmawia też domena, która niczego nie publikuje.

**Kod odmowy — wybór asystenta: `D11`, nie `D10` z kolejnej liczby reguł domeny.** Reguły domeny mają D1–D9, ale
`D10`, `D11` i `D14` są już kodami z decyzji (zakres zapytań, publikacje, capability) i leżą w tej samej tabeli
odmów; nazwa domeny jest przestrzenią nazw publikacji z decyzji D11, więc wiersz D11 w `docs/contract.md` dostał
jeszcze jeden przypadek. *Odrzucone:* **`D10`** — koliduje z istniejącym kodem zakresu zapytań; **nowa litera**
(np. `N` dla nazw) — kod bez decyzji, która go uzasadnia, a v2 §6 nie daje literze miejsca.
**Gdzie sprawdzenie — w regułach domeny (transformer), nie w `opt_schema`** (`{:custom, …}` Sparka): typ
niestandardowy odmawia `Spark.Options.ValidationError` bez kodu i poza jednym komunikatem z pozostałymi odmowami
domeny. *Odrzucone też:* porównanie pierwszego segmentu z nazwą w `namespaces/1` kontraktu (L3) — domena bez
publikacji dalej by przechodziła, a odmowa wskazywałaby publikację zamiast domeny.
**Bez limitu długości** (etykieta DNS ma do 63 znaków) — nikt go nie zgłosił, a to kolejny powód odmowy widoczny
dla hosta; wraca, gdyby EHOS odrzucał długie nazwy aplikacji.

**Testy i próby odwrotne** (`test/dsl/domain_rules_test.exs`, „D11: the domain's name…”): jedenaście złych nazw
(z `nil` i `true`) z treścią odmowy i linią `use`, siedem kontroli, odmowa razem z innymi naruszeniami domeny. Bez reguły → padają dwa
testy odmów; `$` zamiast `\z` → pada test złych nazw (`:"shop\n"`); myślnik dozwolony na końcu → ten sam; bez
myślnika → pada kontrola (`:"my-shop"`); `_` na początku dozwolone → pada test złych nazw.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle; regresji żaden nie znalazł — każda nazwa
domeny w repozytorium przechodzi, a z nazw, które mogły publikować, odpadają tylko te z kropką):
- `name: nil`, `true`, `false` się kompilowały — `Atom.to_string(nil)` to `"nil"`, a wymagana opcja przyjmuje `nil`;
  publikacje pod `nil.`, capability `nil.<komenda>`, aplikacja `"nil"` w manifeście — *poprawione* (`28fcaa0`), test
  czerwony bez poprawki;
- wzorzec segmentu przepisany ręcznie z `@versioned`, związany komentarzem — *poprawione* (`e21e81a`): jeden
  `DslRules.namespace?/1` dla domeny i publikacji; wzorzec bez myślnika wywraca kontrolki w obu DSL-ach naraz;
- linia `contract.md` poza szerokością zawijania — *poprawione* (`2cfbbfb`);
- `use_at/1` w regułach domeny obok `Links.use_at/1`, bez gałęzi `nil` — *bez zmiany*: inny kształt (adnotacja
  Erlanga dla `DslRules`, lista opcji dla `Links`), a linię zapisuje zawsze `handle_opts` tego samego modułu, `:file`
  — Spark;
- `DslRules` przyjmuje jako miejsce dowolny termin niebędący strukturą — *bez zmiany*: naruszenia tworzą tylko
  reguły biblioteki, typ to opisuje, a dialyzer go sprawdza;
- pomocnik `named/3` obok `domain/2` w teście — *bez zmiany*: `domain/2` ma nazwę `:clinic` i poddziedziny na
  sztywno;
- manifest z ręcznie złożonej mapy domeny omija sprawdzenie — *bez zmiany*: wejście to kod hosta, `Model.fetch/1`
  czyta skompilowane moduły;
- `_` i brak limitu 63 znaków, choć EHOS nazywa aplikację etykietą DNS — *bez zmiany*: decyzja użytkownika wyżej;
- `$` w N1, D9 i ścieżkach stron, nazwy aktorów bez sprawdzenia formy — *pominięte*: sprzed tej zmiany, nowe powody
  odmowy widoczne dla hosta, do użytkownika (otwarte pytania w handoffie).

**Brama** (30 września, na głowie gałęzi od `0e6e10f`): EXIT=0 — sandbox 144 (`check` 0/29/9), silnik **1015**
(1012 + 3), `check` 0/66/5, web 52, auth 66; `docs/dsl` i `docs/rules.md` aktualne.

### `$` w nazwach i nazwy aktorów — co wyszło (30 września)

**Polecenie użytkownika** (30 września): poprawić na tej samej gałęzi obie luki z przeglądu `name:` domeny.

**`$` → `\z`** (`58ce3da`): N1 (nazwy kontraktu — `command :"pay\n"` dawało capability `"<domena>.pay\n"` w
`Model.capabilities/1`, OpenAPI i manifeście), D9 (nazwa niezmiennika — funkcja z nową linią w nazwie), ścieżki stron
(`mix eh_os_contract.pages`) i dziesiętna w danych scenariusza (`"12.50\n"`; przy okazji `[0-9]` zamiast `\d`,
jak każe `CLAUDE.md`). W sandboksie to samo w nazwie okresu TaxVision (`a8a1826`) — bez zmiany zachowania, bo
`month_start/1` i tak odmawiał.

**Nazwa aktora snake_case, pod D4** (`1ebe67c`, `360bd47`): nazwa człowieka to rola `<domena>.<aktor>` w manifeście —
`actor :"*", :human` było rolą `"acme.*"`, `:"billing.clerk"` rolą dwusegmentową. Aktor systemowy roli nie ma
(`Model.capabilities/1` bierze tylko ludzi), ale ta sama forma go obowiązuje, bo `by:` wymienia go jak człowieka —
odmowa mówi to osobnym zdaniem. `nil`, `true`, `false` odmawiane jawnie, jak w D11. *Wybór asystenta:* kod **D4**
(reguła aktorów), nie nowy; *odrzucone:* osobny kod — D4 jest już „regułą aktora”, a tabela odmów nie potrzebuje
kolejnego wiersza dla jednej formy. N1, D4, D9 i ścieżki stron wołają jeden `DslRules.snake_case?/1`.

**Testy i próby odwrotne:** N1 z komendą `:"close\n"`; D9 z `:"small\n"`; strony z wartością `:"amount\n"`;
`test/contract_data_test.exs` (nowy) — `"12\n"`, `"12."`, `".5"`, `"1e3"`, cyfry arabsko-indyjskie; D4 — `:"*"`,
`:"billing.clerk"`, `:Reception`, `:"clerk\n"`, `true`, systemowy `:"Registry Bot"`, kontrola `:front_desk2`.
Każdy `$` przywrócony osobno → pada dokładnie jego test; bez reguły D4 → pada test D4; bez rozróżnienia rodzaju →
pada ten sam (komunikat systemowego); bez odmowy `true` → ten sam.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, na `90d93db..1ebe67c`):
- komunikat D4 twierdził, że aktor systemowy jest rolą — *poprawione* (`360bd47`), z testem;
- `actor true` przechodziło — *poprawione* (`360bd47`);
- wzorzec snake_case w czterech kopiach — *poprawione* (`360bd47`);
- wzorzec okresu w sandboksie z `\d` i `$` — *poprawione* (`a8a1826`);
- CHANGELOG mówił, że strona z nową linią się nie kompiluje, a odmawia task — *poprawione*;
- nagłówek D4 w kodzie i w teście nie mówił o nazwie — *poprawione*;
- komunikat D4 przy dziwnej nazwie domeny (`".*"` przy `name: nil`) — *bez zmiany*: D11 odmawia obok;
- dziesiętna w scenariuszu ostrzejsza niż `Decimal.cast` w runtime (`"1e3"`, `".5"`) — *bez zmiany*: tak było
  przed zmianą, zmiana dołożyła tylko `\z` i `[0-9]`;
- nazwy pozostałych elementów domeny, pole `scope:`, mapa capability bez L3, koszt mapy przy dispatchu —
  *pominięte*: sprzed tej zmiany, nowe powody odmowy albo pomiar, do użytkownika (otwarte pytania w handoffie).

### Nazwy elementów domeny — co wyszło (30 września)

**Polecenie użytkownika** (30 września): poprawić lukę z przeglądu `$` i aktorów, po sprawdzeniu, czy nie ma na nią
issue. *Nie ma* — na GitHubie trzy issues (#49 otwarte, #50 i #51 zamknięte), żadne o formie nazw; `PLAN.md` nie ma
decyzji przeciw — przegląd EL3 (`6654e53`) zablokował złe nazwy tylko przy generowaniu stron. Gałąź
**`dsl-v2/domain-names-snake-case`**, od głowy `dsl-v2/domain-name-check` (`c607b09`), bo korzysta z
`DslRules.snake_case?/1` — osobny PR, żeby tamten nie urósł; PR tej gałęzi idzie na tamtą albo po jej merge'u na
`main`.

**Co jest, pod D1** (reguła nazw domeny; aktorzy zostają pod D4):
- nazwa poddziedziny, kontekstu, podmiotu, wartości, encji i systemu zewnętrznego jest snake_case (`DslRules.name?/1`
  — atom, nie `nil`/`true`/`false`, wspólny z D4). `value :"a/b"` dawało moduł zagnieżdżony `Values.A.B`, `context
  :"front desk"` psuło węzeł mapy kontekstów, strony odmawiały dopiero przy generowaniu;
- dwie wartości, których nazwy po `Macro.camelize` są równe (`:money_amount`, `:money_amount_`, `:money__amount`,
  `:desk2`/`:desk_2`), są odmawiane jak dwie o jednej nazwie — moduł niezmienników `Values.MoneyAmount` byłby jeden;
  odmowa także bez niezmienników, bo niezmiennik można dopisać później;
- wartość nazwana jak typ, którego `@type` nie da się zdefiniować (`:map`, `:bool`) — pytanie do
  `:erl_internal.is_type/2` plus sześć nazw, które dokłada Elixir; dziś padała w `Build` z `TypespecError`
  wskazującym bibliotekę;
- wartość nazwana jak typ pola biblioteki (`:date`, `:id`, `:decimal`, `:timestamp`) — pole tego typu znaczyło
  wbudowany, więc wartość była nieużywalna, po cichu.

*Odrzucone:*
- **zakaz `__` w nazwie** (pierwsza wersja, `740d349`) — przegląd pokazał, że nie zamyka kolizji, którą miał
  zamknąć (`Macro.camelize` gubi też końcowe `_` i `_` przed cyfrą), a sam `__` niczego nie psuje; zastąpione
  porównaniem po `camelize` (`75a6e7b`);
- **ręczna lista typów Elixira** (`75a6e7b`) — pominęła `:bool`, `:var`, `:char_list`; `:erl_internal` odpowiada
  za OTP, który kompiluje, a odmowa `@type` i tak od niego zależy, więc reguła nie jest mniej deterministyczna niż
  błąd, który zastępuje (`f0614bf`);
- **kolizja tylko dla wartości z niezmiennikami** — dopisanie niezmiennika zmieniłoby werdykt D1 dla nazwy, której
  nikt nie ruszał;
- **odmowa kolizji dla każdego rodzaju** — tylko nazwa wartości staje się modułem; ścieżki stron i identyfikatory
  Mermaida odróżniają `front_desk` od `front_desk_`.

**Testy i próby odwrotne** (`domain_rules_test.exs`, D1): sześć rodzajów ze złą formą (z nową linią i `true`),
aktor tylko pod D4; kolizje z odmową raz na nazwę; typy Elixira i typy pól; kontrola. Bez reguły formy, bez
porównania po `camelize`, z D1 na aktorach, bez `:erl_internal`, bez typów pól, bez `uniq_by` — pada dokładnie
test swojej części. D9 odmawiał `true` już wcześniej jako słowa zarezerwowanego — test to przypina.

**Przegląd** (dwie rundy, `code-review high` i bezpieczeństwo/wydajność):
- runda 1 (`740d349`): `__` nie zamyka kolizji — *poprawione* (`75a6e7b`); komunikat przypisywał moduł, stronę i
  węzeł każdemu rodzajowi — *poprawione*; test kontrolny uznawał `:money_amount_` za bezpieczne — *poprawione*;
  wartość nazwana jak typ Elixira — *poprawione*; nieaktualny komentarz w `pages.ex` — *poprawione*; brak testu,
  że aktor dostaje tylko D4 — *poprawione*;
- runda 2 (`75a6e7b`): lista typów bez `:bool`/`:var`/`:char_list` — *poprawione* (`f0614bf`); wartość nazwana jak
  typ pola — *poprawione* (`0224222`); komunikat „is the module” dla wartości bez niezmienników — *poprawione*;
  podwójna odmowa powtórzonej nazwy — *poprawione* (`group_by`); przykład w komentarzu stron i „kolumna” podmiotu —
  *poprawione*; zależność od OTP — *bez zmiany* (wyżej);
- obie rundy: kolizja nazw kontraktu (sprawdzona — jest), nazwy pól, etykiety krawędzi Mermaida, kolizja
  `context :values`/`value :index` — *pominięte*: sprzed tej zmiany, nowe odmowy, do użytkownika (otwarte pytania).

**Brama** (30 września, na `0224222`): EXIT=0 — sandbox 144 (`check` 0/29/9), silnik **1021** (1018 + 3), `check`
0/66/5, web 52, auth 66; `docs/dsl` i `docs/rules.md` aktualne.

### Kolizja nazw kontraktu i nazwy pól — co wyszło (30 września)

**Polecenie użytkownika** (30 września, przy komentarzach do #56): poprawić też kolizję nazw kontraktu i nazwy pól.
Na tej samej gałęzi, w #56 — ta sama klasa („nazwa trzymana w formie”).

**Komentarz CodeRabbita do #56** (tłumaczyć polskie etykiety w fiksturach) — *bez zmiany*: `label` w domenie i
kontrakcie to miejsce, gdzie `CLAUDE.md` pozwala na polszczyznę; odpowiedź w wątku, wątek zamknięty, CodeRabbit
przyznał i zapisał to jako regułę.

**Co jest:**
- **N1: dwie nazwy, które `Macro.camelize` daje jednakowo** (`bfd6054`, `93c3b6b`) — tam, gdzie nazwa staje się
  modułem albo aliasem: komendy, zdarzenia i zdarzenia konsumowane (implementacja aliasuje struktury po nazwie) oraz
  agregaty, dcb, polityki, efekty, process managery, read modele, zapytania i serwisy domenowe, każdy w swojej
  przestrzeni modułów. `event :visit_closed` obok `:visit_closed_` kompilowało się z „redefining module
  …Events.VisitClosed”. N2 porównuje po `camelize` też `:state`/`:row` — `command :state_` był aliasem `State`.
  Wspólny `DslRules.camel_collisions/2` dla D1 i N1, w kolejności deklaracji.
- **F1, D3, D6: nazwa pola snake_case** (`f9a6278`), pole wartości raz (dziś nie sprawdzane — JSON Schema brała
  późniejszą definicję z `required` wcześniejszej); **`identity` jednostki jak pole** (`d769a98`) — `identity
  :"a|b"` trafiało przez `consults` do krawędzi grafu i tabeli strony; argument serwisu domenowego zostaje N1
  (`91b5fe7`, bez podwójnej odmowy).

*Odrzucone:*
- **kolizja jednostek łącznie** (pierwsza wersja) — agregat i dcb to moduły dwóch przestrzeni, `Aggregates` i
  `Dcbs`, więc `aggregate :visit` obok `dcb :visit_` nie jest kolizją; przestrzeń nazw zostaje wspólna;
- **kolizja timerów i publikacji** — nie generują modułu ani aliasu;
- **escapowanie `|` w etykietach krawędzi Mermaida** (obrona w głąb z przeglądu) — po tej zmianie każda etykieta
  to tekst biblioteki albo sprawdzona nazwa; wraca, gdyby etykieta niosła tekst klienta.

**Testy i próby odwrotne:** N1 — zdarzenie/zdarzenie, read model/read model, komenda/zdarzenie, zapytania
`:visits2`/`:visits_2`, kontrola z agregatem i dcb; N2 — `:state_`, `:row_`; F1 — pola komendy, `identity`
(forma, `__`, powtórzenie); D3/D6 — pola wartości i encji; argument serwisu raz. Bez każdej części pada dokładnie
jej test (kolizje w obu przestrzeniach N1, F1 forma, `identity`, D3, D6, jednostki łącznie, N2 dokładne, argument).

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, na `3eb24c8..f9a6278`):
- `identity` bez sprawdzenia — *poprawione* (`d769a98`);
- `:state_`/`:row_` zasłaniały aliasy `State`/`Row` — *poprawione* (`93c3b6b`);
- agregat i dcb jako jeden moduł — *poprawione* (`93c3b6b`);
- rodzaj w komunikacie szukany z timerami — *poprawione*; kolejność odmów alfabetyczna — *poprawione*;
- argument serwisu odmawiany dwa razy — *poprawione*; zmienna `twice` w D6 z odmowami formy — *poprawione*;
- testy bez kolizji między rodzajami i `:x2`/`:x_2` — *poprawione*;
- escapowanie etykiet Mermaida — *bez zmiany* (wyżej); pierwszy element kolizji w przestrzeni komend według
  kolejności rodzajów, nie źródła — *bez zmiany*: dotyczy tylko tego, która z dwóch nazw jest „pierwsza” w
  komunikacie.

**Brama** (30 września, na głowie): EXIT=0 — sandbox 144 (`check` 0/29/9), silnik **1028**, `check` 0/66/5, web
52, auth 66.

### Przed E12 — decyzje użytkownika (1 października)

**Następny etap: E12** (integracja między aplikacjami). *Odrzucone na teraz:* fikstury akceptacyjne i manifest v2 —
czekają na rozstrzygnięcie #49 i akceptację D-51/D-52 w `eh-os`; drobne reguły z „Otwartych pytań” — każda to
osobny powód odmowy z małym sygnałem. Zgody z bloku „Zgoda i stałe uprawnienia” potwierdzone w tej sesji.
**Test odbioru na zmyślonych domenach w pakiecie, nie w `sandbox/`** (wybór asystenta, zgodny z propozycją #49):
nie dokłada materiału klienta, który #49 chce wynieść.

**`Bus` nie obiecuje kolejności** (pytanie użytkownika, rekomendacja asystenta przyjęta). Wiadomości jednego wydawcy
wychodzą w kolejności logu, ale odbiorca może je dostać w dowolnej; między dwoma wydawcami kolejności nie ma nigdy.
*Odrzucone:* **kolejność od jednego wydawcy** — zawęża transport do szeregowego konsumenta (JetStream z jedną
niepotwierdzoną wiadomością naraz, HTTP wysyłane szeregowo do każdego odbiorcy), jedna wiadomość, której odbiorca
nie weźmie, zatrzymuje wszystko za nią, a drugi węzeł odbiorcy nic nie daje; **kolejność po kluczu**
(`publish … ordered_by:`) — nowe słowo DSL-a i konsumenci z partycjami, zanim jakikolwiek odbiorca o to poprosił.
Cena: odbiorca, któremu zależy na kolejności dwóch wiadomości, czeka na obie process managerem. **Odwracalne w
jedną stronę:** dołożenie kolejności później jest addytywne (odbiorca pisany bez niej dalej działa), odwrotnie
zepsułoby każdego, kto na niej polegał; `ordered_by:` wchodziłoby obok, a adapter, który go nie utrzyma, odmawia
publikacji zamiast po cichu zgubić kolejność. Dopisek z datą w `docs/adr/contract-v2.md` §16.

**Relay nie przez Obana** (pytanie użytkownika o transakcyjny outbox). Log jest outboxem (D11): stan jednostki to
ciąg jej zdarzeń, więc dispatch robi jeden dopis, nie dwa zapisy; relay czyta tylko zatwierdzone zdarzenia w
kolejności zatwierdzenia (§10.2) i przesuwa checkpoint po potwierdzeniu z `Bus`, więc wiadomość może przyjść dwa
razy, nigdy zero razy i nigdy bez swojego faktu. Oban zostaje outboxem efektów (zadanie w transakcji zdarzenia).
*Odrzucone:* zadanie Obana na każde publikowane zdarzenie — drugi outbox obok logu, zadania bez kolejności, stan
wyjścia rozproszony po zadaniach zamiast jednej pozycji. Ten sam dopisek w §16.

**Podział E12 na części** (wybór asystenta), każda z przeglądem przed następną:
- **E12a** — behaviour `EhOsContract.Bus`, adapter lokalny, suita adapterów (`EhOsContract.Bus.Suite`, jak
  `Store.Suite`);
- **E12b** — relay: uporządkowana subskrypcja nad logiem, wiadomość tylko z `fields`, id
  `<id zdarzenia>/<nazwa publish>` (zbudowane: `<id zdarzenia>/<nazwa wersjonowana>`, „E12b — co wyszło”),
  checkpoint po potwierdzeniu;
- **E12c** — inbox i runner subskrybenta, capability `<nazwa>.subscribe`, test dwóch aplikacji;
- **E12d** — publiczne wejście dla surowych danych, Plug na nim, bez `Dispatcher.permit_undecoded/5`;
- **E12e** — poprawka z datą `architecture.md` §9–10, `docs/contract.md`, CHANGELOG, skill `write-reaction`,
  handoff.

### E12a — co wyszło (1 października)

**Co jest** (gałąź `dsl-v2/e12-bus`, od `2d870ee`): `EhOsContract.Bus` z dwoma callbackami — `publish(opts,
messages)` (`:ok`, gdy transport trzyma całą partię; `{:error, _}` dla transportu niedostępnego, wyjątek dla
wiadomości, której żaden transport nie przeniesie) i `consumer(opts, consumer)` (dziecko trwałego konsumenta, którego
handler odpowiada `:ack` albo `:nack`); `EhOsContract.Bus.Message` z czterema polami (`id`, `name`,
`correlation_id`, `payload` jako JSON); `EhOsContract.Bus.Local` w pamięci jednego BEAM-a; `EhOsContract.Bus.Suite`
w `lib/`, jak `Store.Suite`. Konfiguracja `config :eh_os_contract, bus: {Adapter, opts}`, domyślnie żadna. Nic
jeszcze przez `Bus` nie publikuje.

**Wybory asystenta:**
- **Ack jako odpowiedź handlera, nie osobne wywołanie** — ADR wymienia trzy operacje (publikacja, subskrypcja,
  potwierdzenie); tu potwierdzenie to wartość, którą handler zwraca. Tak wygląda `Gnat.Jetstream.PullConsumer`
  (`handle_message/2` zwraca `:ack`/`:nack`), a runner inboxu (E12c) i tak potwierdza dopiero po commicie, w tym
  samym miejscu. *Odrzucone:* model pull z `fetch/2` i `ack/2` — cztery operacje zamiast dwóch i dzierżawa
  wiadomości w każdym adapterze; model push na pid — adapter musiałby sam pilnować, kto żyje.
- **Adapter lokalny w pamięci, nie na Postgresie** — ADR: „dla testów i jednej aplikacji”; wersja na bazie udawałaby
  broker między aplikacjami, czego D-41 nie chce (tabela u EHOS-a odrzucona).
- **Lokalny nie odrzuca duplikatów** — test inboxu w E12c potrzebuje drugiego doręczenia, a suita deduplikacji nie
  wymaga.
- **Payload przez JSON w lokalnym** — term, którego transport nie przeniesie (krotka, atom jako klucz), pada w
  teście, a nie na produkcji.
- **Domyślnie żaden adapter** — lokalny jako domyślny oznaczałby produkcję, która po cichu gubi wiadomości przy
  restarcie.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle, na `2d870ee..5ce8c90`; żaden nie znalazł
utraty wiadomości przy żywej subskrypcji):
- linkowany proces handlera, który pada, zabijał konsumenta z pełnym powodem w logu nadzorcy — *poprawione*
  (`9499087`): wyjścia łapane na czas handlera, jak w `EffectJob`; dekodowanie payloadu w tym samym miejscu
  (nieosiągalne w lokalnym, więc bez testu);
- wiadomość zabitego konsumenta wracała na początek kolejki od razu — jedna trująca wiadomość przekraczała limit
  restartów nadzorcy — *poprawione* (`9a95887`): wraca po `retry_after`;
- obcy `DOWN` albo komunikat z handlera zatrzymywał konsumenta — *poprawione* (`7e9952f`);
- `id` i nazwa wiadomości surowo w logu — *poprawione* (`07e6053`), `inspect`;
- `take` dla nieznanej nazwy wywracał brokera przez `Map.fetch!` (z mapą kolejek w komunikacie) — *poprawione*
  (`a7697c5`);
- `:sys.get_status/1` i raport padnięcia z payloadami — *poprawione* (`df67523`), `format_status/1`;
- powrót z węższą listą nazw zostawiał w kolejce wiadomości porzuconych nazw — *poprawione* (`cae1d5d`);
- identyfikator dziecka konsumenta bez nazwy brokera — *poprawione* (`0a028bb`);
- `:name` spoza atomów uruchamiał brokera, do którego żaden konsument się nie podłączy — *poprawione* (`cdf12d7`);
- `publish` wychodził exitem zamiast `{:error, _}`, z wiadomościami w powodzie — *poprawione* (`5f08f3c`);
  doc callbacku mówi, czego relay może się spodziewać;
- suita za ostra wobec „co najmniej raz” (dokładne liczby doręczeń; test potwierdzenia zatrzymywał konsumenta przed
  `:ack`) — *poprawione* (`921dc71`); lokalny zmutowany na podwójne doręczenie: stara suita pada na trzech testach,
  nowa przechodzi;
- `publish` przebudowywał mapę konsumentów na każdą wiadomość, zbędny zbiór monitorów — *poprawione* (`fc52afa`);
- test „konsument staje, gdy broker staje” zostawiał pętlę restartów — *poprawione* (`5adea29`);
- ADR „nigdy zero razy” bez zastrzeżenia o konsumencie późniejszym niż publikacja; moduledoc `Bus` przypisywał suicie
  więcej, niż widzi — *poprawione* (`fb6bf46`);
- brak terminu potwierdzenia, limitu prób i usuwania subskrypcji w lokalnym; trwali konsumenci suity na brokerze —
  *pominięte w kodzie, opisane* (`fb6bf46`): adapter deweloperski, a limit prób należy do transportu albo inboxu;
- `Bus.adapter/0` przyjmuje dowolny atom — *bez zmiany*: konfiguracja hosta, błąd przy pierwszym użyciu.

**Do E12b i E12c z przeglądu:**
- relay: wyjątek z `publish` to defekt wydawcy, `{:error, _}` — ponowienie bez przesunięcia checkpointu; loguje
  tylko rodzaj (`Protocol.UndefinedError` Jasona niesie w komunikacie wartość, której nie zakodował);
- **otwarte do E12c:** kiedy powstaje konsument subskrybenta względem relaya wydawcy — lokalny daje nowemu
  konsumentowi tylko to, co opublikowano po jego pierwszej subskrypcji, więc relay uruchomiony wcześniej publikuje
  w próżnię (dwie aplikacje w jednym BEAM-ie w developmencie).

### E12b — co wyszło (1 października)

**Co jest** (gałąź `dsl-v2/e12b-relay`, od `7e4e4cc`): `EhOsContract.Relay` — relay każdego `publish` jako
konsument rodzaju `:relay` w `Implementations` (klucz `"<kontrakt>:relay:<nazwa>"`), na wierszach i runnerze
subskrypcji, jak polityka. Krok czyta do 100 zdarzeń typu, który `publish` bierze, buduje wiadomości z samych
`fields` (id `<id zdarzenia>/<nazwa wersjonowana>`, korelacja zdarzenia) i przesuwa pozycję w tej samej transakcji,
gdy `Bus.publish/1` odda `:ok`. Fikstura `BusRig` (zmyślony sklep, test/support) — publikuje złożenie zamówienia
bez notatki sprzedawcy; anulowanie nie wychodzi.

**Wybory asystenta** (dopisek „as built” w v2 §16):
- **id kończy się nazwą wersjonowaną (`as:`), nie nazwą deklaracji** — deklaracja jest wewnętrzna dla wydawcy, jak
  zdarzenie źródłowe, którego D-41 nie wpuszcza do manifestu; dwie publikacje jednego zdarzenia (v1 obok v2) i tak
  mają dwa id;
- **`{:error, _}` z transportu nie jest porażką zdarzenia** — bez liczenia prób, pozycja stoi, ponowienie po 5 s.
  *Odrzucone:* liczenie jak u polityki — kilkusekundowa awaria brokera zostawiłaby relay `failing` do ręcznego
  zdjęcia, a `--skip` zgubiłby zdarzenie. Wyjątek to defekt i liczy się jak u polityki;
- **bez skonfigurowanego busa relay czeka** na swojej pozycji, start loguje ostrzeżenie. *Odrzucone:* odmowa startu
  (host bez brokera w developmencie by nie wstał); rejestracja relaya dopiero z busem (zacząłby od głowy, a to, co
  dopisano w międzyczasie, nigdy by nie wyszło);
- **relay startuje od głowy logu, jak polityka** — `publish` dodany do kontraktu z historią jej nie wysyła; reset
  wysyła log jeszcze raz, pod tymi samymi id.

**Decyzja użytkownika po przeglądzie (1 października): broker wołany w transakcji kroku, z limitem czasu na
adapterze.** Blokada wiersza (`FOR UPDATE SKIP LOCKED`) daje jednego wydawcę na relay w klastrze; kosztem jest
połączenie z puli trzymane podczas publikacji, więc `Bus.publish/2` ma wracać w kilka sekund, wyraźnie poniżej
timeoutu repo (inaczej Ecto zrywa połączenie po tym, jak broker wziął partię, pozycja nie rusza i partia wychodzi w
kółko). *Odrzucone:* publikacja poza transakcją i przesunięcie pozycji potem, tylko gdy nikt jej nie ruszył — bez
połączenia trzymanego przez sieć, ale każdy węzeł publikowałby każdą partię (mnożenie ruchu na brokerze), a zapis
porażek ścigałby się między węzłami.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle, na `797ae76..472102e`; żaden nie znalazł
zgubionej wiadomości poza zamierzonym `--skip` i zmianą nazwy `publish`):
- powiadomienie z każdego dispatchu omijało przerwę po awarii — przy awarii brokera próba i ostrzeżenie na każdy
  dispatch (oba przeglądy) — *poprawione* (`77e47e9`), test na `CommitRepo`;
- publikacja w transakcji bez limitu czasu (pula, pętla po timeoucie repo; oba przeglądy) — *decyzja użytkownika*
  wyżej, *poprawione w dokumentacji callbacku* (`25e51d5`);
- wyjątek partii przypisany pierwszemu zdarzeniu — cykl na każde zdarzenie przed winnym, a wyjątek zależny od
  wielkości partii nigdy nie dawał `failing` — *poprawione* (`8146016`): partia jeszcze raz, po jednym;
- `throw` z adaptera wywracał runner (z wartością w raporcie) — *poprawione* (`31c5f39`), także `catch` w runnerze;
- zła konfiguracja `bus:` w komunikacie w całości (np. token brokera) — *poprawione* (`a08e72d`), sam kształt;
- `--reset` relaya mówił „emptied, and replayed” — *poprawione* (`f5601b4`);
- relay bez busa otwierał transakcję i blokował wiersz co sekundę — *poprawione* (`4e5a654`), bez testu (wynik ten
  sam: `:idle`);
- trwała odmowa brokera jako `{:error, _}` blokowałaby relay na zawsze po cichu — *poprawione w dokumentacji*
  (`25e51d5`): `{:error, _}` tylko dla tego, co naprawia ponowienie, reszta to wyjątek; widoczność długiej awarii —
  *bez zmiany*: ostrzeżenie w logu, a błędy to Datadog (`CLAUDE.md`);
- zmiana nazwy `publish` porzuca wiersz (zaległe nie wychodzi), usunięcie i powrót wznawia od starej pozycji; pola
  zapieczętowane wcześniejszą wersją wychodzą zapieczętowane; tożsamości jawnie; relay tylko w skonfigurowanych
  aplikacjach — *opisane* w moduledocu `Relay` (`25e51d5`), do skilla `change-contract` w E12e;
- `read_all` z `type = ANY($1)` może nie użyć indeksu `(type, position)` dla rzadkiego typu — *pominięte*: sprzed
  E12b (to samo zapytanie karmi polityki), do pomiaru razem z runnerem read modelu (otwarte pytania);
- relay niewidoczny w `Paths` i na ekranie zgodności — *bez zmiany*: widać go w `mix eh_os_contract.subscriptions`;
  cztery pytania ekranu go nie obejmują;
- test „dopisane w trakcie” nie ćwiczy współbieżności — *poprawione* (nazwa i komentarz, `25e51d5`): współbieżność
  to obietnica `Store.Suite`.

**Do E12c i E12e:**
- E12c: inbox kluczuje `(nazwa, id wiadomości)`; `idempotent_on` (FM-08 w `eh-os`: ta sama treść pod nowym id) — do
  rozstrzygnięcia, czy wiadomość ma je nieść; kiedy powstaje konsument odbiorcy (z „E12a — co wyszło”);
- E12e: `change-contract` o zmianie nazwy i usunięciu `publish`; poprawka `architecture.md` §9–10.

### Przed E12c — decyzje użytkownika (1 października)

**D1 — wiadomość niesie klucz z wartości `idempotent_on`** (rekomendacja asystenta przyjęta). Relay liczy klucz:
SHA-256 nazwy wersjonowanej i wartości `idempotent_on`, piąte pole `Bus.Message`; inbox jest unikalny po
`(inbox, klucz)`, a bez `idempotent_on` (albo z wartością `nil`) klucz to id wiadomości. Przykład: sklep zapisuje
drugi `placed` dla `O-1` (błąd, log przeniesiony z nowymi id) — wiadomość `e2/…` ma klucz `e1/…`, magazyn
rezerwuje raz (FM-08 w `eh-os`). *Odrzucone:* **(B) nic, inbox po id** — FM-08 do jednostki odbiorcy, każdy
odbiorca pisze to samo sprawdzenie, a `idempotent_on` wydawcy nikomu nie służy; **(C) `idempotent_on` w
`consumes`** — druga kopia deklaracji wydawcy, która może się rozjechać. Cena: wydawca z za wąskim
`idempotent_on` po cichu traci drugi, prawdziwy fakt.

**D2 — konsument odbiorcy powstaje przed relayem przez kolejność w drzewie silnika** (rekomendacja asystenta
przyjęta). Supervisor startuje inboxy przed runnerami, a dziecko `Bus.consumer/2` jest zasubskrybowane, gdy jego
start wróci (obietnica dopisana w doc callbacku i w nazwie pierwszego testu suity). Przykład: relay sklepu wstaje
z zaległościami i publikuje od razu — w jednym BEAM-ie na `Bus.Local` konsument magazynu już słucha. Na produkcji
konsumenta zakłada EHOS przy grancie (D-41), a to, co opublikowano przed grantem, to historia z API właściciela
(D-03). *Odrzucone:* **(B) rejestracja przy pierwszym boocie** (trzeci callback `Bus`) — aplikacja sama
zakładałaby konsumenta, którego ma kontrolować grant; **(C) zostawić transportowi** (`Bus.Local` trzyma wszystko
dla nowego konsumenta) — subskrybent wdrożony później reagowałby na historię wydawcy.

### E12c — co wyszło (1 października)

**Co jest** (gałąź `dsl-v2/e12c-inbox`, od `66c3637`, trzy commity kodu i jeden zapisu):
- `1fa8f65` — `Bus.Message.key` (wymagany), liczony w `Relay.message/2`; pełny SHA-256, nie 12 znaków
  `Digest.hash/1` (kolizja = zgubiony fakt);
- `bb1f688` — `EhOsContract.Inbox` i `InboxRecord`, tabela `eh_os_contract_inbox` w V01 (w miejscu),
  `Implementations.inboxes/0` (jeden inbox na `consumes "<nazwa>"`, który obsługuje jakaś polityka; klucz
  `"<kontrakt>:inbox:<nazwa>"`), inboxy przed runnerami w `EhOsContract.Supervisor`, capability
  `<nazwa>.subscribe` w `Model.capabilities/1`; w `BusRig` zmyślony magazyn (`Warehouse`, `Stock`, decyzja
  `Reservation`, polityka `ReserveForOrder`), który rezerwuje towar dla zamówień sklepu;
- `0692740` — odmowa `D12` dla read modelu, efektu i process managera na zdarzeniu odebranym.

**Wybory asystenta** (dopisek „as built” w v2 §16):
- **przyczyną komendy jest wiersz inboxu, nie wiadomość** — ADR mówi „`causation_id` = id wiadomości”, ale
  przyczyna to UUID w obu tabelach (`causation_id`, `causation_event_id`), a id wiadomości to `<uuid>/<nazwa>`;
  wiersz ma własne `id` (UUID) i trzyma `message_id`. *Odrzucone:* kolumna przyczyny jako `text` (zmiana typu w
  dwóch tabelach V01 i we wspólnych bazach), id zdarzenia wydawcy wycięte z id wiadomości (wiązałoby inbox z
  formatem id, którego `Bus` nie obiecuje parsować);
- **tylko polityka bierze zdarzenie odebrane (`D12`)** — ADR nazywa tylko politykę; read model jest odbudowywany
  z logu, a efekt i process manager czytają swoje z logu, gdzie zdarzenia odebranego nigdy nie ma — do dziś się
  kompilowały i nigdy by go nie dostały. *Odrzucone:* zbudować inbox także dla nich (read model zgubiłby te
  wiersze przy odbudowie, zadanie efektu i process manager stoją na wierszu logu); zostawić (cicha luka).
  Fikstura `contract_generate_test` przeniosła zdarzenie odebrane z efektu i process managera do polityki;
- **czego inbox nie potwierdza**: payload niezgodny z polami `consumes` i polityka, która rzuca — rollback,
  `:nack`, log z nazwą, id i rodzajem błędu, bez wartości; **inbox nie liczy prób** — limit to `MaxDeliver`
  transportu. *Odrzucone:* licznik prób i stan `failing` w tabeli inboxu z taskiem do pomijania (jak
  subskrypcje) — większy diff, a `Bus.Local` to adapter deweloperski;
- **`<nazwa>.subscribe` bez wersji** — jak przykład w v2 §16 i w `eh-os` 0041 (`rehmed.visit.closed.subscribe`);
  rodzaj `:subscribe`, `roles: []`; Dispatcher, Plug, OpenAPI i manifest v1 filtrują po rodzaju, więc nic w
  silniku o nią nie pyta;
- **`__meta__` zdarzenia odebranego**: `id` wiersza i korelacja wiadomości; bez pozycji, aktora i czasu, których
  wiadomość nie niesie;
- **scenariusz polityki na zdarzeniu odebranym** (`on :order_placed` → `issues :reserve_stock`) działa bez zmian
  w `ScenarioCase`; `BusRig` dostał plik scenariuszy obu kontraktów (sklep też go nie miał).

**Próby odwrotne:** inboxy po runnerach → pada test kolejności startu; inbox kluczowany po id → padają test
FM-08 i test klucza w wierszu; polityka wydająca `total + 1` → pada scenariusz magazynu.

**Weryfikacja:** brama z `sandbox/` na drzewie `0692740` (przed commitami, to samo drzewo kodu) → **EXIT=0** —
sandbox 144, `check` 0 / 29 / 9; silnik **1088** (1073 + 15: inbox 10, relay 1, scenariusze `BusRig` 3, D12 1),
`check` **0 / 68 / 6** — o jedno ostrzeżenie więcej, zamierzone (`event-without-consumer` dla `:reserved`
magazynu, jak `:cancelled` sklepu); web 52; auth 66. Commity pośrednie w tymczasowym worktree: `bb1f688` —
silnik 1087, 0 padnięć, kompilacja z `--warnings-as-errors`, format; `1fa8f65` — silnik 1074, trzy padnięcia
`MigrationsTest`, wyłącznie dlatego, że wspólna baza `…_test_commits` ma już ręcznie dołożoną tabelę inboxu,
której V01 z `1fa8f65` nie zna (sprawdzone: różnicą jest tylko ta tabela).

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle, na `66c3637..5e15711`; oba znalazły
kolizję klucza):
- **klucz wiadomości kolidował** — `Digest.canonical/1` łączy napisy separatorami bez długości, więc przy
  `idempotent_on: [:a, :b]` pary `"x),(s:b,s:y"`/`"z"` i `"x"`/`"y),(s:b,s:z"` dawały ten sam klucz i inbox
  odrzucał drugi, prawdziwy fakt (oba przeglądy) — *poprawione* (`479aeeb`): `Digest.document_digest/1`, pełny
  SHA-256 kodowania z długościami, którego `document_hash/1` używa z tego samego powodu; z wycofaną poprawką pada
  jeden test z 14 w `relay_test.exs`;
- **broker niedostępny kładł silnik** — konsument `Bus.Local` bez brokera wychodzi w `init`, więc przy busie
  skonfigurowanym, a leżącym silnik nie wstawał (i host z nim), a broker, który padł później, przekraczał limit
  restartów i zatrzymywał wszystkie runnery i relaye (poprawność) — *poprawione* (`c82a97d`):
  `EhOsContract.Inbox.Keeper` startuje konsumenta w swoim `init` (D2 trzyma się, gdy bus działa), loguje rodzaj
  błędu i próbuje znowu po 5 s; z wycofaną poprawką padają dwa z 15 testów `inbox_test.exs` i `boot_test.exs`, oba
  w `inbox_test.exs`: nowy i test kolejności, który pyta teraz o identyfikator keepera;
- **`.subscribe` bez inboxu** — capability dla każdego `consumes`, a inbox tylko dla obsłużonego przez politykę;
  grant bez czytelnika zostawiłby na brokerze konsumenta, któremu rosną wiadomości (poprawność) — *poprawione*
  (`bab57b3`), ten sam warunek co inbox; z wycofaną poprawką pada jeden test (`contract_test.exs`, capability
  `Named`);
- **pomocnik testów auth żądał wejścia dla `.subscribe`** — `assert_every_entry_refuses/3` brał wszystkie
  capability, więc host z `consumes` dostałby „no entry for” (bezpieczeństwo, przy okazji) — *poprawione*
  (`0b14c73`); z wycofaną poprawką pada jeden test z 67 pakietu auth; wpis w CHANGELOG-u auth doszedł w commicie
  zapisu, nie w tym samym;
- nazwa trwałego konsumenta z kropkami (JetStream ich nie przyjmuje) — *opisane* w `Bus` (`c82a97d`): adapter ją
  mapuje; test przywracał `:manual` zamiast poprzedniej wartości i dwa sprawdzenia busa w supervisorze —
  *poprawione* (`c82a97d`);
- inbox nie sprawdza, kto opublikował (klucz, korelacja i nazwa z wiadomości) — *opisane* w `Inbox` i v2 §16: to
  grant transportu (D-41), jak przy subskrypcji; capability `<nazwa>.publish` — do użytkownika i EHOS-a (niżej);
- wiadomość, która nigdy nie przejdzie (zły payload, korelacja spoza UUID), wraca bez końca na `Bus.Local` —
  *bez zmiany*: wybór z E12c (nic nie ginie, `MaxDeliver` transportu); polityka bez modułu w inboxie — *bez
  zmiany*: to samo, co rzucająca polityka, a `check` ostrzega `declaration-without-implementation`;
- transakcja inboxu trzyma blokadę dopisu, gdy liczą się kolejne polityki — *bez zmiany*: tak samo polityka
  `:in_transaction`; kolizja nazw capability w `Map.merge` — *bez zmiany*: `.subscribe` ma co najmniej cztery
  segmenty, capability komendy dwa;
- runnery nie są budzone po commicie inboxu (do 1 s opóźnienia, `@poll`) i tabela inboxu rośnie bez końca —
  *pominięte*, niżej; zgodność nie widzi polityki inboxu — już otwarte.

**Druga runda przeglądu** (oba przeglądy na poprawkach, `5e15711..02345b3`; nic blokującego):
- keeper nie czekał na konsumenta przy zatrzymaniu (doręczenie w toku przeżywało repo hosta; dziecko-supervisor
  traciło `shutdown: :infinity`), restartował po 5 s także konsumenta, który działał (na `Bus.Local` relay
  publikujący w tej przerwie trafia w brokera bez konsumentów), a `{:ok, pid, info}` i `:ignore` brał za porażkę
  (oba przeglądy) — *poprawione* (`c253f1f`): `terminate/2` czeka tyle, ile mówi `shutdown` dziecka, restart od
  razu, a po 5 s tylko gdy dziecko padnie znowu w przerwie; z wycofaną poprawką padają cztery nowe testy
  `inbox_keeper_test.exs` (test restartu — strukturalnie, stary stan nie ma `started_at`);
- test z brokerem podniesionym w trakcie ścigał się z keeperem — *poprawione* (`4686811`);
- `document_hash/1` kopiował potok `document_digest/1` — *poprawione* (`2629a7b`), wynik ten sam;
- test pomocnika auth pokrywał tylko pustą mapę — *poprawione* (`5e66eb8`);
- obietnice ponad to, co keeper kontroluje — *opisane* (commit zapisu drugiej rundy): start adaptera, który czeka
  na sieć, wstrzymuje boot (boot czeka na każdego keepera po kolei), a logi OTP dziecka adaptera są adaptera —
  wymagania w doc `c:EhOsContract.Bus.consumer/2`; mapowanie nazwy konsumenta ma być różnowartościowe;
  restart brokera `Bus.Local` gubi to, co relay opublikuje, zanim keeper wróci — w `Inbox`;
- stała przerwa 5 s bez narastania i rozrzutu (ok. 720 ostrzeżeń na godzinę awarii na inbox) — *pominięte*: tak
  samo relay; `Enum.any?` w `capabilities/1` na każdy dispatch — *bez zmiany*, pomijalne.

**Do E12d i E12e, i otwarte:**
- **retencja `eh_os_contract_inbox`** — wiersz na fakt na inbox, na zawsze; czyszczenie po wieku skraca okno, w
  którym ten sam fakt pod nowym id (FM-08) jest rozpoznany — granica do decyzji użytkownika;
- **kto może publikować pod nazwą** — silnik wyprowadza `<nazwa>.subscribe`, a nie `<nazwa>.publish`; czy
  manifest ma nieść prawo publikacji, to sprawa EHOS-a (D-41) — do użytkownika, na liście zmian do `eh-os`
  (*1 października:* [eh-os#96](https://github.com/EmpoweredHouse/eh-os/issues/96));
- runnery po commicie inboxu nie dostają powiadomienia (dispatch w cudzej transakcji go nie wysyła) — czekają do
  sekundy; do pomiaru razem z runnerem read modelu; *naprawione 2 października* ([#72](https://github.com/EmpoweredHouse/eh-os-contract/issues/72)),
  razem z krokiem subskrypcji i timerem — „#72 — co wyszło”;
- **zgodność nie widzi polityki inboxu** — `Paths` bierze kroki tylko dla zdarzeń z typem w logu
  (`type_of/2` daje `nil` dla odebranego), więc ekran nie pokazuje tej ścieżki ani jako przejechanej, ani jako
  nieprzejechanej; da się ją liczyć z komend `policy:<nazwa>`, których przyczyna jest w `eh_os_contract_inbox` —
  do decyzji użytkownika (czwarte pytanie ekranu obejmuje ścieżki zadeklarowane);
- **przesłanka E12d nie potwierdziła się w zbudowanym kształcie** — decyzja z 27 września dawała wejściu termin
  „E12, bo inbox to drugie drzwi dla surowych danych”. Inbox nie autoryzuje (to konsument aplikacji, nie aktor z
  credentialem), sam dekoduje payload przez `Codec.decode/4` do struktury odebranej, a komendy wydaje polityka
  zwykłym `dispatch` ze strukturą — nie przechodzi przez „uprawnienie → dekodowanie → dispatch”. Drzwi dla
  surowych danych z credentialem są dalej jedne (Plug). Do decyzji użytkownika przed E12d: robić teraz (jedno
  wejście dla Pluga i przyszłych drzwi) czy odłożyć do drugich prawdziwych drzwi;
- E12e: `docs/contract.md` o inboxie i `consumes "<nazwa>"`, skill `write-reaction` (tylko polityka na zdarzeniu
  odebranym, `D12`), poprawka `architecture.md` §9–10.

### Przed E12d — decyzja użytkownika (1 października)

**E12d teraz, mimo że przesłanka odpadła** (wybór użytkownika; asystent rekomendował odłożenie). Inbox E12c nie
okazał się drugimi drzwiami dla surowych danych („E12c — co wyszło”), więc jedynymi drzwiami jest dalej Plug, a
wspólne wejście powstaje na zapas, z kształtem ustalonym na jednym użytkowniku. *Odrzucone:* **odłożyć do drugich
prawdziwych drzwi** (formularz LiveView, job z credentialem) — kształt z dwóch przypadków zamiast zgadywanego z
jednego, kosztem `permit_undecoded/5` i kolejności „najpierw uprawnienie” pilnowanej przez każde nowe drzwi samo.

**Kształt** (wybór użytkownika, rekomendacje asystenta przyjęte): **`EhOsContract.call/3`**, obok `dispatch/3`,
`record/3` i `query/3`, adresowane **nazwą capability** — `{:command, "rehmed.record_payment"}` — jak EHOS,
credential i Plug. *Odrzucone:* osobny moduł `EhOsContract.Entry.call/3`; adres kontraktem i nazwą deklaracji (jak
`dispatch/3`) — drzwi musiałyby znać moduł kontraktu.

### E12d — co wyszło (1 października)

**Co jest** (gałąź `dsl-v2/e12d-call`, od `27175a0`): `EhOsContract.call/3` → `Dispatcher.call/3` — routing po
capability (`Dispatcher.route/3`, publiczne: formularz potrzebuje deklaracji), aktor musi być credentialem,
dekodowanie (`Codec.decode/4`, dla query wartości tekstem), sprawdzenie `correlation_id`; przy każdym problemie
najpierw pytanie o uprawnienie (dawne `permit_undecoded/5`, teraz prywatne), potem `dispatch/3`, `record/3` albo
`query/3`. `EhOsContract.Plug` czyta już tylko HTTP (ciało, query string, nagłówki) i tłumaczy odpowiedź na status;
statusy i treści bez zmian — `plug_test.exs` (13) przechodzi bez zmiany linijki.

**Wybory asystenta:**
- **`:system` nie wchodzi przez `call/3`** (`{:error, :no_actor}`) — to kod aplikacji, który wydaje struktury
  przez `dispatch/3`; tak samo odmawiał Plug;
- **`contracts:` opcjonalne**, domyślnie wszystkie z rejestru — Plug podaje swoje, jak dotąd;
- **co jest nie tak z ciałem HTTP wie tylko Plug** — `call/3` mówi `:not_an_object`, a Plug odpowiada
  `unreadable_body` albo `body_is_not_a_json_object`, jak dotąd;
- zły `correlation_id` jest problemem tylko dla komendy i nagrania, jak dotąd (query go nie bierze).

**Próba odwrotna:** `call/3` bez pytania o uprawnienie przed problemem — padają 2 z 6 testów `call_test.exs` i 4
z 13 `plug_test.exs`.

**Do powrotu — kształt `call/3` jest zgadnięty z jednego użytkownika.** Problem, dla którego wejście miało czekać
(decyzja z 27 września), nie zniknął, tylko został świadomie przyjęty: jedyne drzwi, z których kształt wyprowadzono,
to Plug, a Plug ma swoje przyzwyczajenia — mapę z kluczami-napisami jak z JSON-a, wartości query jako tekst jak z
query stringa, błędy ciała opisywane przez siebie. **Kiedy wrócić:** przy pierwszych prawdziwych drugich drzwiach
dla surowych danych z credentialem — formularzu LiveView w aplikacji klienta albo w EHOS Console, jobie, który niesie
credential osoby, wejściu MCP — i **zanim** te drzwi pójdą na produkcję, bo po pierwszym hoście zmiana kształtu
publicznej funkcji jest zmianą łamiącą. **Co sprawdzić na nich:**
- czy wejście to dalej mapa z kluczami-napisami — formularz LiveView daje napisy wszędzie, także dla komend, więc
  opcja „wartości tekstem” może być potrzebna nie tylko dla query (dziś `strings: kind == :query`);
- czy wystarcza `{:error, :not_an_object}` i `{:invalid, problemy}` — formularz chce błąd przy polu, job może
  chcieć ponowić tylko część odmów;
- czy drzwi potrzebują deklaracji, zanim zawołają (`Dispatcher.route/3` jest publiczne z myślą o formularzu — jeśli
  nikt go nie użyje, może wrócić do środka);
- czy `contracts:` z domyślnym „wszystkie z rejestru” jest bezpieczne dla drzwi, które powinny widzieć tylko część;
- czy odmowa `:system` (`:no_actor`) pasuje do joba, który działa w imieniu aplikacji, a dane ma surowe;
- czy wartość zakresu „jak wysłana” wystarcza — dziś tylko napis pod kluczem-napisem; liczba (`"clinic_id": 7`)
  albo klucze-atomy z formularza dają przy błędzie w innym polu `:outside_scope` zamiast `{:invalid, …}` (sprzed
  E12d, z przeglądu E12d);
- czy domyślne `contracts:` ma zostać — bez `config :eh_os_contract, applications:` rejestr rzuca wyjątek, a drzwi,
  które zapomną `contracts:`, wystawiają każdą capability (ogranicza je tylko grant credentiala); alternatywa:
  `contracts:` wymagane, jak w `EhOsContract.Plug.init/1`;
- czy `min_position:` i `wait:` (dla query) mają sprawdzenie typu i górną granicę — dziś napis jako `min_position`
  po cichu pomija czekanie, napis jako `wait` rzuca wyjątek, a `wait` bez granicy trzyma proces (i połączenie, jeśli
  drzwi wołają w transakcji); doc mówi, że ustawia je kod drzwi, nie wywołujący — formularz LiveView będzie
  pierwszym, który zechce je przekazać (druga runda przeglądu E12d);
- czy sprawdzenie `correlation_id` (tekst UUID) przenieść z `call/3` do `dispatch/3` i `record/3`, które dalej
  biorą 16 surowych bajtów i wywracają zapis, i czy przekazywać dalej postać znormalizowaną przez `Ecto.UUID.cast/1`
  (wielkie litery dziś zostają w `__meta__` komendy, a z logu wracają małymi).
Jeśli coś z tego się nie zgadza — poprawka kształtu przed wydaniem 0.3.0 kosztuje jeden PR; po nim — wpis „host
musi działać” w CHANGELOG-u.

**Przegląd** (`code-review high` i bezpieczeństwo/wydajność, równolegle, na `27175a0..9540ab9`; gwarancja „najpierw
uprawnienie” trzyma — każda ścieżka to jedna decyzja `Authorizer`, nikt bez capability nie widzi problemu z polami):
- **Plug czytał i dekodował ciało przed sprawdzeniem aktora** (oba przeglądy) — anonimowe żądanie do ~8 MB
  (domyślne `read_body`) było czytane i parsowane, zanim dostało 401, a przed E12d dostawało je za darmo —
  *poprawione* (`8153fbc`); z wycofaną poprawką pada jeden test z 14 w `plug_test.exs`;
- **`x-correlation-id` z 16 dowolnych bajtów** przechodził `Ecto.UUID.cast/1` (surowy UUID) i wywracał zapis —
  500 zamiast 400 (sprzed E12d) — *poprawione* (`8506b2b`), tylko tekstowa postać UUID;
- **`call/3` gubił `min_position:` i `wait:`** dla query — drzwi czytające swój zapis przez `call/3` dostawały stare
  wiersze — *poprawione* (`8506b2b`); Plug nie ma na to nagłówka i nie miał go przed E12d, więc klient HTTP dalej
  nie czyta swojego zapisu z read modelu `:at_least_once` — bez zmiany, druga runda to wskazała; opcje jako mapa (jak w `dispatch/3`) i dokładny `@spec` `EhOsContract.call/3` — też
  `8506b2b`; z wycofanymi poprawkami padają trzy z dziewięciu testów `call_test.exs`;
- zakres „jak wysłany” tylko dla napisów i domyślne `contracts:` — *do powrotu* (wyżej);
- surowa wartość zakresu trafia do `scope_value` w decyzjach pakietu auth — znak `\u0000` albo zły UTF-8 z query
  stringa daje 500 przy zapisie decyzji (sprzed E12d) — *pominięte*, w „Otwartych pytaniach”;
- `idempotency_key:` bez sprawdzenia typu z drzwi spoza HTTP — *bez zmiany*: tak samo `dispatch/3`;
- Plug routuje dwa razy, a `Model.capabilities/1` i `Codec.values/1` liczą się 2–3 razy na żądanie — *pominięte*:
  mikrosekundy; indeks capability w `:persistent_term` przy pomiarze, razem z runnerem read modelu;
- `answer/7` w Plugu z siedmioma argumentami i prywatne `call/4` obok `Plug.call/2` — *bez zmiany*: czytelność,
  nie poprawność.

**Druga runda** (oba przeglądy na `9540ab9..20f38fd`, na samych poprawkach; nic blokującego): strażnik 401 w Plugu
zgadza się z `credential/1` dla każdego aktora, a 404 dalej przed 401; tekst UUID i opcje mapą — bez uwag. Opis
tej listy obiecywał „read your writes” także dla HTTP — *poprawione* w zapisie; tabela statusów Pluga bez wierszy
400 — *poprawione*; `wait:`/`min_position:`, sprawdzenie UUID poza `call/3` — *do powrotu* (wyżej); klauzula
`:no_actor` w Plugu nieosiągalna i dwie kopie typu błędów `call/3` — *bez zmiany*: zabezpieczenie i czytelność.

### E12e — co wyszło (1 października)

**Co jest** (gałąź `dsl-v2/e12e-docs`, od `7aa0496`; sama dokumentacja i skille):
- `docs/contract.md` — akapit o odbieraniu: `consumes "<nazwa>"` z polityką, inbox, `D12`, klucz z `idempotent_on`,
  capability `<nazwa>.subscribe` (przykład: `Loans` publikuje, kontrakt innej aplikacji odbiera);
- skill `write-reaction` — zdarzenie odebrane bierze tylko polityka (`D12`), `delivery:` nic dla niego nie zmienia;
  deduplikacja w inboxie po kluczu i cena za wąskiego `idempotent_on`; historia innej aplikacji nie przychodzi
  busem (D-03);
- skill `change-contract` — wiersze tabeli: zmienione `idempotent_on` (nowy klucz, fakt wzięty raz jeszcze),
  zmiana nazwy i usunięcie `publish` (wiersz relaya po nazwie deklaracji, C-4), usunięcie `consumes` albo jego
  polityki (inbox i `.subscribe` znikają, C-3);
- `docs/adr/architecture.md` §9–10 — poprawka z datą: „bez zewnętrznego brokera” trzyma się w jednej aplikacji;
  między aplikacjami `publish`, `Bus`, relay i inbox, idempotencja dalej deklaracją wydawcy.

CHANGELOG nie dostaje wpisu: nic z tego nie zmienia werdyktu ani zachowania, a E12a–E12d mają swoje.

**Przegląd** (dwa równolegle na `7aa0496..d17206e`: twierdzenia przeciw kodowi oraz język i konwencje; żadne
twierdzenie fałszywe): przykład w `contract.md` nazywał zdarzenie własnej aplikacji strony „innej aplikacji”, a
polityka wydawała komendę spoza strony — *poprawione* (`Loans` publikuje, kontrakt innej aplikacji odbiera);
„ten sam fakt pod nowym id” odrzucany tylko przy zadeklarowanym `idempotent_on` — *poprawione* w `contract.md`,
`write-reaction` i `architecture.md`; zmienione `idempotent_on` daje nowy klucz tylko wiadomościom zbudowanym po
wdrożeniu — *poprawione* w `change-contract`; brakujący wiersz: nowe `as:` przy `consumes` to nowy trwały konsument
(zaległe nieprzeczytane, deduplikacja od zera) — *dodane*; `.subscribe` zostaje, gdy polityka obsługuje inną wersję
nazwy — *poprawione*; „nic, na czym kontrakt polega, nie jedzie transportem, który gubi” — *zawężone* do logu;
„Co przeczytać najpierw” sprzed E12c i retencja inboxu poza „Otwartymi pytaniami” — *poprawione*.
**`CLAUDE.md`** („Czym biblioteka jest”) mówi dalej, że broker „jeszcze niezbudowane”, a §9–10 „mówi dziś «bez
zewnętrznego brokera»” — po E12 nieprawda; *poprawione* na polecenie użytkownika, w tym samym PR-ze.

### #71 — proces kluczy w `eh_os_contract_auth`: tabela, interwały, `refresh/1` — co wyszło (2 października)

**Problem** ([#71](https://github.com/EmpoweredHouse/eh-os-contract/issues/71)): cztery rzeczy, które termin
pobrania kluczy (#69) zostawił otwarte w `EhOsContract.Auth.Keys` — „Poprawka 28 września (2) — jeden termin”
niżej i jej odzyskanie z 1 października. Żadnej dziś nic nie wyzwala; to utwardzenie, nie błąd, który ktoś widział.

**Analiza przed zmianą** — skutek (1) węższy, niż mówiło issue: przy zaplanowanym odświeżeniu nikt nie czeka, bo
`fetch_now` zamyka okno wcześniejszego pobrania na 30 s, zanim pobierze, więc wołający z nieznanym `kid` nie wołają
procesu. Czeka jeden — ten, którego `kid` wywołał pobranie (i każde żądanie przy starcie, gdy `load/1` wisi). Klucze
szły do pamięci dopiero po tabeli, więc przy zablokowanej tabeli dostawał `:unknown_key` dla klucza, który EHOS
właśnie przysłał. Zasada „najpierw tabela, żeby pamięć nie miała zestawu, którego następny start nie wczyta” nie
trzymała się i tak: przy nieudanym zapisie klucze szły do pamięci. (2) dotyczy też `refresh_every`, którego issue
nie wymieniało. Żadnej z dwóch opcji nie ustawia ani README, ani sandbox, ani testy.

**Decyzje użytkownika** (rekomendacje asystenta przyjęte):
- (2) **odmowa przy starcie** interwału poniżej 5 s (termin pobrania) albo nie w całych milisekundach, dla obu opcji.
  Przegrały: usunięcie obu opcji (host nie mógłby pobierać rzadziej — nikt dziś nie chce, ale to uprawniony powód)
  i ciche podniesienie do granicy (konfiguracja hosta ignorowana bez słowa);
- (4) **pominięte**: task pobrania zostaje zlinkowany. Sygnał wyjścia z zewnątrz wysłany do taska zabiłby proces
  kluczy i jego tabelę, ale nic w pobraniu się z taskiem nie linkuje (Finch i NimblePool monitorują, Mint nic nie
  linkuje). `Task.Supervisor.async_nolink` zmieniałby `EhOsContract.Auth` z jednego workera w supervisor — kształt
  widoczny dla hosta — dla zagrożenia, którego nic nie wywołuje. Komentarz w `get/1` mówi to przy kodzie.

**Co jest** (gałąź `auth/issue-71-keys-hardening`, od `65d7caf`):
- (1) odczyt i zapis tabeli w transakcji z `SET LOCAL statement_timeout = '1s'` (Postgres kończy każdą instrukcję,
  czekanie na blokadę też, a połączenie zostaje w puli) i `timeout: 2_000` klienta na każdym wywołaniu, `BEGIN` i
  `COMMIT` też — zapasowo, bo ten zamyka połączenie (w testach razem z transakcją sandboxa). Zapis na zablokowanej
  tabeli trwa sekundę, więc wcześniejsze pobranie (5 s) mieści się w 10 s wywołania; czekanie na połączenie z puli
  zostaje sprawą repo hosta. Klucze do pamięci przed tabelą. Testy: drugie połączenie spoza sandboxa trzyma `ACCESS EXCLUSIVE` na tabeli —
  start i wcześniejsze pobranie po rotacji kończą się poniżej 4 s, klucz z rotacji przechodzi; repo, które wstrzymuje
  zapis na słowo testu — w czasie zapisu nowy klucz już jest w pamięci. Na kodzie z `main` padają oba, i tylko one
  (start: `:sys.get_state` po 10 s nie dostaje odpowiedzi);
- (3) `refresh/1` łapie wyjście: `{:error, :timeout}` albo `{:error, :not_running}`, w `@spec`, który był. Test
  na procesie, który nie działa; gałąź timeoutu bez testu — kosztowałby 10 s czekania na tę samą klauzulę `catch`;
- (2) `check!/1` (więc i `child_spec/1`) odmawia `refresh_every:` i `refetch_at_most_every:` poniżej 5 000 albo nie
  całkowitych; testy na 0, 4 999 i 5 000.0 dla obu, kontrola na 5 000 i minucie; na starym kodzie pada sześć. Okno
  wcześniejszego pobrania liczy się od **końca** pobrania z zapisem, nie od startu — inaczej przy granicy 5 s
  następne pobranie wolno by zacząć w chwili, gdy poprzednie się skończyło (oba przeglądy).
- Wpisy w `CHANGELOG.md` pakietu w commitach zmian, zdanie w README („How the key store behaves”).

**Przegląd** (dwa równolegle na `65d7caf..d343aa9`; nic w bezpieczeństwie):
- granica 5 s nie wykluczała pobrań jedno po drugim, bo okno liczyło się od startu pobrania (oba) — *poprawione*:
  od końca; test z pobraniem, które zabiera 20 s zegara, pada na starym liczeniu;
- `timeout: 2_000` to timeout klienta, nie Postgresa — zamyka połączenie, a `SET`, `BEGIN` i `COMMIT` miały 15 s
  repo, więc zdanie o mieszczeniu się w 10 s nie było prawdą (oba) — *poprawione*: `statement_timeout` po stronie
  Postgresa, zapasowy timeout klienta na transakcji, opis budżetu uczciwy;
- `lock_table!` rejestrował zwolnienie blokady po `assert_receive` (spóźniona blokada zostałaby na zawsze), a
  połączenie Postgrex nie było zamykane — *poprawione*; komentarz wskazywał nieistniejące `hold_writes/0`, doc
  `start_link/1` mówił, że oba interwały mierzy `:clock` — *poprawione*; `refresh/1` każde wyjście poza timeoutem
  nazywa `:not_running`, także padnięcie w trakcie — *opisane* w docu, crash loguje supervisor;
- `SET LOCAL` w sandboxie trwa po `RELEASE SAVEPOINT` do końca testu — *bez zmiany*: w produkcji transakcja jest
  najbardziej zewnętrzna, w testach sekunda na instrukcję nikomu nie przeszkadza;
- pamięć przed tabelą i sekunda na zablokowanej tabeli poszerzają znane okno: klucz cofnięty przez EHOS, którego
  zapis nie przeszedł, wraca po restarcie przy niedostępnym EHOS-ie — *pominięte*: luka była (każdy nieudany zapis),
  komentarz w `store/2` ją nazywa, a stary kod czekał do 15 s, trzymając wołającego.

Brama z `sandbox/` → **EXIT=0** — sandbox 145, `check` 0 / 29 / 9; silnik 1114, `check` 0 / 68 / 6; web 52; auth
**149** (+11) + 1 property.

### #72 — runnery budzone po commicie, którego dispatch nie zamyka — co wyszło (2 października)

**Problem** ([#72](https://github.com/EmpoweredHouse/eh-os-contract/issues/72), z przeglądu E12c): dispatch budzi
runnery (`Subscription.Runner.notify/0`) tylko po transakcji, którą sam otworzył; w cudzej nie wie, czy ta się
zacommituje. Inbox otwiera własną transakcję, jego polityki dispatchują w niej — i po commicie nikt nie budził
runnerów, więc read model, process manager albo relay do trzeciej aplikacji czekał na poll (`@poll`, do 1 s,
średnio 0,5 s na przeskok). **Ta sama luka była w dwóch starszych miejscach**, których issue nie wymieniało: krok
subskrypcji (`Subscription.stepped/2` — polityka `:at_least_once` i process manager dispatchują w transakcji
runnera) i `TimerJob` (dopisuje `timer_elapsed`, który czyta tylko runner process managera).

**Decyzja użytkownika: naprawić teraz** (asystent rekomendował). Przegrała opcja z issue „zostawić i zmierzyć
razem z pozostałymi kosztami pollingu” — pomiar nie ma terminu, a poprawka jest mała.

**Co jest:** jeden mechanizm zamiast trzech łatek. Dispatch po każdym dopisie, który ktoś czyta po kolei, stawia
znacznik w procesie (`Runner.notify_on_commit/0`), w swojej transakcji i w cudzej tak samo; właściciel transakcji
silnika otwiera ją przez `Runner.transaction/2`, które po commicie budzi runnery raz, jeśli znacznik stoi, a
wewnątrz innej transakcji tylko wykonuje funkcję i znacznik zostawia temu, kto commituje. Używają go dispatch,
inbox, krok subskrypcji i `TimerJob` (dispatch we własnej transakcji budzi jak przedtem — polityka wydaje tylko
komendy swojego kontraktu, P1, więc znacznik zagnieżdżonego dispatchu niczego nie dokłada). Transakcja kodu hosta nadal nie budzi — runnery pollują, jak dotąd.
Przegrały: samo `notify/0` po commicie inboxu (zostawia krok i timer, a następne miejsce z własną transakcją
znowu by zapomniało); bezwarunkowe powiadomienie po każdym kroku (budzi wszystkie runnery na wszystkich węzłach,
przy notifierze Postgresa każde to zapytanie — lawina); `notify/0` wewnątrz transakcji, licząc na to, że `NOTIFY`
Postgresa dochodzi dopiero po commicie (prawda tylko dla notifiera Postgresa; notifier PG2 wysyła od razu, runner
budzi się przed commitem i nic nie widzi).

**Testy** (`watch_wakes/0` w `DataCase`: telemetria notifiera Obana, tylko z procesu testu): inbox budzi po
przyjęciu wiadomości, a po wiadomości wziętej wcześniej nie; timer budzi po odpaleniu, a odpalony po raz drugi
(bez dopisu) nie; krok process managera, który dispatchuje, budzi. Kontrola odwrotna: z `repo.transaction` w
miejsce `Runner.transaction` w inboxie, kroku i timerze padają dokładnie trzy nowe testy „budzi”. CHANGELOG bez
wpisu — żaden werdykt się nie rusza, zmienia się tylko opóźnienie.

**Przegląd** (oba równolegle na `01ac970..2f23318`, poprawności także na `5abb6b9`; nic w bezpieczeństwie):
- runner nie łączył powiadomień czekających w skrzynce, a od tej zmiany sam je sobie wysyła — po jednym na każde
  zdarzenie, na którym polityka albo process manager dispatchuje; po nadrobieniu zaległości robił krok na każde
  (10 tys. zdarzeń — 10 tys. pustych transakcji na każdym runnerze, polityki w kolejce do blokady dopisu) —
  *poprawione* (`5abb6b9`): powiadomienie zabiera te, które czekają za nim; bez tego test liczy 5 kroków zamiast 1;
- `Personal.erase/3` budził sam, po swojej transakcji — także zagnieżdżonej w transakcji hosta, czyli przed jej
  commitem (wzorzec, który ta zmiana odrzuciła) — *poprawione* (`810c549`): ten sam mechanizm;
- testy nie odróżniały budzenia po commicie od budzenia w transakcji, nie mówiły „raz” i nie sprawdzały transakcji
  hosta — *poprawione* (`844a44e`): `watch_wakes/0` zgłasza budzenie w transakcji osobno; z `notify/0` w miejsce
  `notify_on_commit/0` w `TimerJob` pada test timera; `dispatch_effects_test.exs` traci własną kopię handlera;
- handler telemetrii dopasowywał `%{channel: _}` (zmiana metadanych Obana odłączyłaby go po cichu, a `refute`
  przechodziłyby na pusto) — *poprawione* razem z poprzednim; nieaktualny doc `notify/0`, za długie linie
  moduledoków, `Process.sleep(50)` w teście runnera — *poprawione*; `Process.read_timer/1` czyta 0 dla timera
  startowego, który jeszcze nie odpalił, więc pierwsza wersja oczekiwania przepuszczała — test padał 7 razy na 10,
  po poprawce 20 na 20 zielonych;
- jedno powiadomienie na każdy krok, który coś dopisał, przy nadrabianiu zaległości polityki — *pominięte*: tyle
  samo kosztuje ta sama liczba dispatchów z kodu hosta, a odbiorców łączy już `5abb6b9`; budzenie raz na końcu
  `catch_up/2` opóźniałoby następnych konsumentów do końca zaległości;
- `CHANGELOG.md` (E7a) mówi, że runnery budzi dispatch — *bez zmiany*: to wpis etapu i dalej prawdziwy.

Brama z `sandbox/` na gałęzi `claude/issue-72-assessment-923997` → **EXIT=0** — sandbox 145; silnik **1114**
(+10); web 52; auth 138 + 1 property.

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

*1 października:* wszystkie punkty są już w `eh-os`, z notkami z datą przy D-01, D-15, D-03 i ARCHITECTURE (D-40,
D-41) i z G-16 zaprojektowanym przez D-41. Pytanie o transport EHOS trzyma jako otwarte w G-16. Wyjątek to „grant
musi umieć nieść wartości zakresu”: [eh-os#94](https://github.com/EmpoweredHouse/eh-os/issues/94).

### D14 — autoryzacja: kontrakt deklaruje, osobny pakiet weryfikuje (25 września)

Z przeglądu zgodności z etapem 4 EHOS-a (`eh-os` `docs/plans/stage-4-identity-and-console.md`, krok 7, oraz
D-32, D-33, D-34, D-40, D-41). Wyszło, że v2 powołuje się na `eh_os_contract_auth` (v2 §16, D10), a nie buduje
go żaden etap, i że v2 §11 sprawdza role aktora, choć credential EHOS-a niesie tylko uprawnienia (`cap`), bez
ról. Użytkownik: kontrakt zostaje wąski, w obrębie DDD; auth jest osobny i wpina się w kontrakt; na razie
jako pakiet w tym repozytorium. Zapisane w v2 §16 jako D14; zmienione wyżej: E4, E6, E10; dodany EA.

Podział: EHOS wydaje credential i uruchamia aplikację kliencką; kontrakt mówi, kto może wydać komendę lub
query (`by:`, aktorzy są rolami — v2 §18), wyprowadza nazwy uprawnień i ról i pyta `EhOsContract.Authorizer`
przy dispatchu; pakiet auth weryfikuje credential, trzyma klucze, implementuje `Authorizer` i zapisuje wiersz
każdej decyzji. Rdzeń przy odmowie nie zapisuje nic.

**Otwarte:** przyjęta komenda ma wiersz w tabeli pakietu auth i wiersz `accepted` w `_commands` — dwa zapisy
jednego faktu. Rozstrzyga EA.

**Do przeniesienia do `eh-os` — przez użytkownika albo sesję w tamtym repozytorium; stąd tam nie piszemy:**
- D-34 „the seam is a call, not a gate” — w v2 dispatch pyta `Authorizer`, więc sprawdzenie jest bramką w
  kontrakcie, a pakiet auth tylko dostarcza tożsamość, uprawnienia i wiersz. Powód D-34 (joby i backfille
  z credentialem) v2 rozwiązuje aktorami `:system`. Także: „the other five tables” — od V03 jest sześć.
- D-40 mówi o „generated denial test” w E6; D-34 i EA mają zamiast tego pomocnika testów.
- Plan etapu 4, krok 7: weryfikator to EA (po E6), task manifestu to E10, a odbiór „manifest wygenerowany dla
  sandboxa równy fixture'owi” jest możliwy dopiero po E9. Krok 8: sandbox dostanie aktorów v2 dopiero w E9, więc
  wcześniej krok 8 potrzebuje minimalnej aplikacji z jednym kontraktem v2 i pakietem auth.
- Handoff planu etapu 4 opisuje krok 6 jako otwarty PR, a jest zmergowany (#35, `5fe898b`).

*1 października:* trzy pierwsze punkty załatwił D-43 (`accepted`, 27 września), a punkty o planie etapu 4 są
nieaktualne, bo etap 4 jest zamknięty. Issue niepotrzebne.

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
  `MIX_ENV=dev mix run`; te wiersze zostają w bazie dev na stałe — *i mają zostać: decyzja użytkownika z
  25 września po E3; to punkt odniesienia porównań bajtów raportu i grafu w kolejnych etapach*. Ścieżki asynchronicznej celowo nie
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
   *Naprawione 25 września po E3, na decyzję użytkownika: `189cad7`, stała kolejność wypisywania.*
5. **Model nie jest cache'owany.** Każdy akcesor buduje mapę od nowa z literałów modułu, więc `emit` buduje ją
   cztery razy. Suita silnika: 2,7 s przed E1, 2,6 s po. Cache po module musiałby zauważać rekompilację, którą
   testy robią celowo; wróci do tematu E4, gdy model v2 będzie większy.
6. **Pakiet web zależy teraz od `EhOsContract.Model`.** W repozytorium i przez gita oba pakiety biorą ten
   sam commit, więc rozjazd jest niemożliwy. Przy publikacji na Hex wymaganie wersji silnika w webie musi
   wskazywać wydanie z `Model`. `CHANGELOG.md` nie ma jeszcze wpisu o nowym publicznym module; plan otwiera
   „Unreleased” w E6. Otwarte pytanie: czy wpis ma wejść wcześniej. *Rozstrzygnięte 25 września po E3:
   „Unreleased” otwarte od razu (`b58062b`), wersja zostaje do E6.*
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
   dokłada się do pytania z E1, kiedy otworzyć „Unreleased”. *Wpisane w `b58062b`.*

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

### E4 — co wyszło (25 września)

Stan: `EhOsContract.Next.Contract` z rozszerzeniem `Next.Contract.Dsl` (wszystkie rodzaje z v2 §4.2 z
poprawkami D10–D11: `aggregate`, `dcb`, `policy`, `effect`, `process_manager`, `read_model`, `query`,
`consumes` w obu formach, `publish`, `process`, `scenario`), transformer `Next.Contract.Rules` z siedmioma
grupami reguł (`Names`, `Fields`, `Units`, `Process`, `Consumes`, `Consumers`, `Boundaries`) i `Build`
(model `__eh_os_contract_model__/0`, digesty, capabilities). Obok: `EhOsContract.DslWrappers` (nakładki D13,
także w DSL-u domeny), `EhOsContract.DslRules` (raport naruszeń, wyjęty z `Domain.Rules`),
`Next.Contract.vocabulary/0`, `Model.capabilities/1`, `scope:` na aktorze domeny. Fikstura
`UniversalityGate.Next.TreatmentEpisode` z `UniversalityGate.Domain`. `Rehmed.Domain` w zapisie z §4.5, bez
nawiasów. Brama zielona na każdym z 12 commitów (z zastrzeżeniem w ustaleniu 10); sandbox 44 → 45, silnik
493 → 593 (z przeglądem), web 31; `eh_os_contract.check` bez żadnej zmienionej linii w obu projektach.

**Warunki D13, jak sprawdzone** (plan: porażka któregokolwiek — stop i pytanie; żaden nie padł):
1. *Błąd wskazuje plik:linię deklaracji, nie nakładki* — `test/dsl/dsl_wrappers_test.exs`: nieznana opcja obok
   bloku `context`, zagnieżdżonego `term` i `value`, oraz reguła D przy owiniętych deklaracjach; w kontrakcie
   to samo dla `command` (`contract_test`). Wyłączenie nakładek wywala 6 z 9 testów tego pliku.
2. *Formatter zostawia zapis czteroargumentowy bez nawiasów* — w silniku i u konsumenta
   (`sandbox/test/rehmed_domain_test.exs`, przez `Mix.Tasks.Format.formatter_for_file/1`, czyli przez
   `import_deps`). **Założenie pod tym warunkiem było błędne:** formatter nigdy nie dodaje nawiasów wywołaniu z
   blokiem `do`, niezależnie od `locals_without_parens`. Eksport arności nakładek jest więc zbędny i go nie ma;
   kontrola w teście pokazuje, że bez żadnego eksportu nawiasy dostają tylko wywołania bez bloku. Poprawka z
   datą pod D13 w v2 §16.

**Odbiór, jak sprawdzony.**
- *Test na każdą regułę L2 i kontrola* — `test/dsl/contract_{names,fields,units,process,consumers,boundaries}_test.exs`:
  odmowa z plikiem:linią i obok kontrola, która się kompiluje. Wstecz, grupa po grupie: bez `Names`+`Fields`
  pada dokładnie 13 odmów, bez `Units` 7, bez `Process`+`Consumes` 9, bez `Consumers` 5, bez `Boundaries` 4;
  kontrole za każdym razem przechodzą.
- *Złoty test modelu* — `test/dsl/contract_test.exs`: cały model małego kontraktu literałem; wersja i digesty
  nie widzą kolejności deklaracji (także zagnieżdżonych i wartości zbiorowych jak `by:`), zmiana jednego pola
  rusza wersję i wyłącznie digest `event:payment_recorded`; kolejność pól `identity` zmienia wersję, bo nazywa
  inny strumień.
- *Słownik przypięty, wyprowadzany z rozszerzenia* — `Next.Contract.vocabulary/0` chodzi po definicjach encji
  Sparka; `test/dsl/contract_vocabulary_test.exs` przypina 55 ścieżek literałem.
- *Przykłady z §4.5–4.6 w zapisie, w którym są* — `test/dsl/contract_examples_test.exs` czyta je **z
  `docs/adr/contract-v2.md`**, nie z kopii, więc zmiana przykładu w ADR jest sprawdzana od razu. Trzy jawne
  poprawki, każda z powodem i z testem, że wciąż trafia w tekst: nazwa `Next` do cięcia, `public: true` (D11),
  `param` zamiast `field` w query (D10). Fragmenty §4.6 kompilują się wewnątrz najmniejszego kontraktu, który
  daje im zdarzenia i proces; sam fragment zostaje dosłowny. Pominięte z nazwy: moduły implementacji i test
  scenariuszy (E5), `Capability.check` i dispatch (E6). Poza repozytorium, bez ADR, testy tego pliku są
  pomijane z powodem.

**Ustalenia.**
1. **`value :x, label: "L" do … end` trafia do Sparkowego `value/3`**, bo `type` jest opcjonalnym argumentem
   pozycyjnym: lista opcji ląduje w `type`, a blok w opcjach. Nakładka tej arności kolidowałaby ze Sparkiem.
   `DslWrappers` daje takiej encji `transform`, który przenosi listę z powrotem do opcji i sprawdza ją schematem
   — tę samą regułę Spark stosuje sam, gdy bloku nie ma. Później tego dnia `consumes "<nazwa>", as: :x do …`
   pokazało drugą połowę: Spark sprawdza typ argumentu przed `transform`, więc typ opcjonalnego argumentu jest
   poszerzany o `:keyword_list`. Warunek dla przyszłych encji: opcjonalny argument encji z blokiem nigdy nie
   przyjmuje listy słów kluczowych jako prawowitej wartości. Oba zdania w notce pod D13.
2. **Reguły P1–P5 weszły w E4**, choć opis etapu wymienia N, F, A, C, R i K: rodzaje, które P sprawdza, wchodzą
   w E4, a bez P polityka mogłaby wydawać nieistniejącą komendę. **P3 nie dotyczy process managerów:** §4.6
   pisze jednego bez `idempotency`, a jego komendy i timery dostają klucze z przebiegu (§17). Poprawka z datą
   w v2 §6.
3. **Reguły D10 i D11 nie mają litery w §6**, więc komunikaty niosą numer decyzji („D10: query …”). Dwie
   części tych decyzji wymagają domeny i są w L3 (E5): że każdy aktor z `by:` query deklaruje jej `scope`, i że
   nazwa publikacji leży w przestrzeni nazw aplikacji. L2 sprawdza tylko kształt nazwy (kropkowane małe segmenty zakończone `.v<n>`).
4. **R6: `cadence` przyjmuje `:week`, `:month`, `:year`** ponad jednostki stałe `EhOsContract.Duration`, bo
   nic nie liczy z niej terminu; `within`, `deadline` i `wait` — tylko stałe. v1 nie sprawdzał jednostek
   `cadence` wcale. `Duration` bez zmian.
5. **Fikstura `UniversalityGate` ma wersję v2 obok v1**, nie zamiast: kontrakt v1 czyta osiem plików testów
   (report, trace, brief, asyncapi, payload, model, registry_exclude, universality_gate), których zachowania
   nie mają następcy v2 przed E7, a test v1 znika tylko z testem v2, który je przejmuje. Tabela „Losy fikstur”
   poprawiona. Moduledoc wersji v2 wylicza, co tłumaczenie zmieniło: kto zapisuje fakty bez komendy (D6, z
   aktorami zmyślonymi razem z domeną), zniknięcie tożsamości faktu, brak odpowiednika `retain: :hash` do E8
   (dwa pola `reason` zostają zwykłym `:string` — luka, nie decyzja), reguła jako inwariant, przykłady jako
   scenariusze, `external` i rola odpowiedzialna w domenie.
6. **Scenariusze fikstury podają w `given` tylko część wymaganych pól** — `received_at` brak. S3 w E5 to
   odrzuci, a reprezentacja czasu w danych scenariusza jest pytaniem E5: literał `~U[…]` włożyłby do modelu
   strukturę `DateTime`, a model ma być czystymi danymi.
7. **Model v2 jest skompilowany do modułu**, więc pytanie o cache z E1 (ustalenie 5) dotyczy tylko adaptera v1.
   Z akcesorów v2 §9 wszedł `Model.capabilities/1`, bo §4.6 go woła (kształt — ustalenie 14); `unit_of/2`, `run/1` i `module_for/3`
   wejdą ze swoimi czytelnikami (E5–E6). Akcesory v1 odmawiają kontraktu v2 z nazwy modułu, więc żaden
   czytelnik v1 nie przeczyta go po cichu źle, a rejestr v1 go nie widzi (`universality_gate_next_test`).
8. **Kształt modelu, poza §9:** listy w kolejności deklaracji; komendy i zdarzenia wyjęte z jednostek na
   górny poziom z kluczem `unit`, zdarzenie z kluczem `stage`; `include` płasko w `process.includes` z kluczem
   `stage`; `consumes` z `kind: :contract | :published`; digest per zużyte zdarzenie pod nazwą lokalną
   (`consumes:<as>`); jeden digest dla wszystkich scenariuszy (`scenario:*`, jak w §9); `grants` po aktorze z
   trzema listami, `commands`, `queries` i `records` (to ostatnie z `recorded_by:`).
9. **Błąd budowania encji zagnieżdżonej zostawia stan Sparka w słowniku procesu**, więc kolejny moduł
   kompilowany w tym samym procesie pada na „nested entity without a `recursive_as`”. U konsumenta bez
   znaczenia (kompilacja i tak staje na pierwszym błędzie); w testach jedna taka odmowa na test.
10. **Po drodze: jeden commit poszedł na czerwonej bramie.** Pierwsza wersja commita N/F (`e595571`) miała
    `git commit` przywiązany przez `&&` do porównania linii `check`, a nie do kodu wyjścia bramy, który był 1
    (konflikt nazw pomocników testowych z lokalnymi funkcjami testów domeny). Zauważone od razu, poprawione i
    commit nadpisany (`--amend`) przed jakimkolwiek pushem — w historii jest już zielony `15d980f`. Od tego
    miejsca commit idzie tylko po skrypcie, który kończy się kodem wyjścia bramy. To ta sama klasa błędu co
    `| tail` z `CLAUDE.md`: commit wiązany z niewłaściwym kodem wyjścia.
11. **`Rehmed.Domain` w zapisie z §4.5**, bez nawiasów, z jednym terminem, który materiał definiuje ze
    źródłem: „Zrealizowana — pacjent wyszedł z gabinetu” (`AGG-01`, `E-51`), w kontekście scheduling, gdzie
    §4.6 kładzie `visit_completed`. Plan chciał tam zapisu `context …, subdomain: … do term … end`; innego
    terminu z definicją w repozytorium nie ma, więc żaden nie jest zmyślony. Wersja domeny ruszyła (aktorzy
    mają teraz `scope: []`); nikt jej nie czyta.
12. **Gałąź.** Sesja pracowała w nowym worktree `.claude/worktrees/dsl-v2-e4-contract-core-68fd81`, na gałęzi
    `claude/dsl-v2-e4-contract-core-68fd81`, odgałęzionej od `38df8bd` i przed PR przebazowanej na `950f83f`. Lokalna `dsl-v2/e4-contract-core`
    została na `38df8bd`, bo jest wymeldowana w worktree z E1 i git nie przesuwa gałęzi wymeldowanej gdzie
    indziej. `origin/dsl-v2/e4-contract-core` stoi na `a4a7009`, więc push E4 na nią to fast-forward:
    `git push origin claude/dsl-v2-e4-contract-core-68fd81:dsl-v2/e4-contract-core` — na polecenie użytkownika.
13. **Przed E4:** CI na `main` po merge'u #7 zielone (przebieg `36137135279` na `c882946`, job `check`
    `success`, żaden krok pominięty ani nieudany). CodeRabbit na PR #7: plan Free, samo podsumowanie, zero
    komentarzy i recenzji — nie było czego rozstrzygać.
14. **D14 przyszło w trakcie E4.** PR #8 (zmergowany, gdy E4 był już lokalnie gotowy) dopisał do opisu E4
    nazwy, na których stoi EHOS. Po przebazowaniu na nowy `main` E4 je dostał, jednym commitem przed
    przeglądem. Mapa po aktorze nazywa się w modelu `grants`. `Model.capabilities/1` jest kluczowane nazwą
    uprawnienia (`<domena>.<komenda>`, `<domena>.<query>`) i podaje role `<domena>.<aktor>` oraz `scope`
    query. Nazwę domeny czyta w chwili wywołania ze skompilowanego modułu domeny, bo kontrakt nie kompiluje
    się względem domeny (§8). Nieskompilowana domena jest odmawiana z nazwy. N1 odmawia query o nazwie
    komendy; unikalność w całej aplikacji to L3 (E5), jak mówi opis. Przykład wyniku z §4.6, pisany po
    aktorze, dostał notkę z datą: to jest `grants`.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`, po przebazowaniu na `950f83f`).**
Sześć znalezisk:
1. `include` w procesie i `consults` w dcb przyjmowały zdarzenie z `consumes "<nazwa>"`, choć D12 kładzie je
   w inboksie, nie w logu — **poprawione** w `1a376e1` (R4, A4).
2. `consumes Kontrakt, :zdarzenie do field … end` kompilowało się, a `Build` gubił pola bez słowa —
   **poprawione** w `597ace8`: K1 odmawia pól dla zdarzenia z kontraktu-rodzeństwa (v2 §7).
3. Scenariusz z dwoma wyzwalaczami kompiluje się, a model trzyma tylko pierwszy — **pominięte**: jeden
   wyzwalacz na scenariusz to reguły S1/S6, które wchodzą w E5; do dopisania tam.
4. `DslWrappers.attach/2` odmawiał każdej encji z własnym `transform`, także takiej, której nakładki nie
   dotykają — **poprawione** w `98185d8`.
5. `Model.capabilities/1` przy `domain:` wskazującym moduł niebędący domeną padało na błędzie adaptera v1 —
   **poprawione** w `cd10e5a`.
6. N2 czytało eksporty `Kernel` na każdą nazwę i arność — **poprawione** w `edf109d` (jedna mapa przy
   kompilacji modułu; bez zmiany zachowania).
Testy z 1, 2, 4 i 5 zweryfikowane wstecz: na kodzie sprzed poprawki pada dokładnie nowy test. Silnik 589 →
593. Na przebazowanych commitach sprzed przeglądu bramy od nowa nie puszczano — #8 zmienił tylko Markdown;
zielona jest na każdym commicie od przebazowania.

### E5a — co wyszło (25 września)

Stan: kontrakt v2 generuje struktury (`Next.Contract.Generate`: `C.Commands.*`, `C.Events.*`, `C.Received.*`,
stany, `Row`, parametry query) i behaviours z jednej listy `Next.Contract.Callbacks`; `use C, aggregate: :x`
(i sześć innych rodzajów) wiąże implementację przez `EhOsContract.Implementation` z makrami `emit`/`reject`/
`issue` i `@before_compile` (L4, I1–I7); reguły S1–S8 są ósmą grupą L2 (`Rules.Scenarios`);
`EhOsContract.ScenarioCase` uruchamia scenariusze na implementacji; decider fikstury to
`UniversalityGate.Next.Episode`. Nowe w eksportach `boundary`: `Implementation`, `Meta`, `Rejection`,
`ScenarioCase`. `Model.module_for/3` wszedł ze swoim czytelnikiem (generator). Brama zielona na każdym z 8
commitów; silnik 593 → 646, sandbox 45, web 31; linie `eh_os_contract.check` identyczne co do bajtu z `5cb888d`
w obu projektach na każdym commicie.

**Odbiór E5, część E5a, jak sprawdzony.**
- *Implementacja fikstury kompiluje się pod `--warnings-as-errors`* — `UniversalityGate.Next.Episode` w
  `test/support/`, kompilowany przez bramę pakietu; kontrole w `implementation_test` sprawdzają zero diagnostyk.
- *Test `CompileError` z plikiem:linią na każdą regułę L4* — `test/dsl/implementation_test.exs`, I1–I7, każda
  odmowa przez `DslCase.assert_refused/4`, który sprawdza plik i linię użytkownika. Wstecz: gdy `refuse!/2`
  niczego nie odrzuca, pada 8 testów odmów, 4 kontrole przechodzą.
- *Usunięcie scenariusza z odmową psuje kompilację i nazywa inwariant* — `contract_scenarios_test`, S8, z
  kontrolą. Wstecz: bez grupy `Rules.Scenarios` pada 11 odmów, 5 kontroli przechodzi.
- *`mix xref graph --label compile-connected` bez krawędzi kontrakt → implementacja* — przypięte testem
  (`implementation_dependency_test`), który uruchamia prawdziwy `mix xref` na manifeście tej kompilacji: od
  kontraktu fikstury tylko pliki biblioteki, ani implementacja, ani domena; implementacja ma krawędź
  kompilacji do kontraktu.
- *Pomocnik testów bram zastępuje `refute_compiles/2`* — `DslCase.refusal/2` i `assert_refused/4` przyjmują
  `DslError`, `CompileError` z makra i diagnostykę błędu kompilatora. `compile_gates_test` (v1) przeszedł na
  niego bez zmiany jednej asercji; wszystkie 27 odmów v1 wskazuje plik użytkownika.
- *Poprawka ADR §18* — notki z datą w `architecture.md` i `design-rationale.md`.

**Ustalenia.**
1. **Czas w danych scenariusza to napis ISO 8601** (`"2026-09-01T09:00:00Z"`, data `"2026-09-01"`). S3
   odmawia literału `~U` z powodem: włożyłby `DateTime` do modelu, który ma być czystymi danymi.
   `ScenarioCase` rzutuje napisy na typy pól. Wartości typów wbudowanych sprawdza S3 (L2); X9 zostają tylko
   typy domeny i dane zdarzeń z kontraktu-rodzeństwa. Notka w v2 §6.
2. **Tożsamość jednostki w danych scenariusza jest opcjonalna**: scenariusz to jeden strumień, a scenariusze
   §4.5 nie podają `visit_id`. `ScenarioCase` wstawia wartość podaną gdziekolwiek w scenariuszu albo
   `"scenario"`.
3. **S1 zamyka znalezisko 3 z przeglądu E4** (dwa wyzwalacze) i dostał jeszcze jedno: dwa scenariusze o tym
   samym opisie są odrzucane, bo opis nazywa test, który `ScenarioCase` generuje.
4. **S6 przyjmuje dwa cele:** komendę do agregatu lub DCB (`expect` albo `rejected`, nie oba) i zdarzenie
   dostarczone polityce albo process managerowi, także timer PM przez `on :timer`. Efekt, read model i query
   są odrzucane z powodem: nic jeszcze nie mówi, czym jest wynik read modelu ani odpowiedź query. **`query` w
   scenariuszu czeka na E6**, który uruchamia projekcje — wtedy trzeba mu dać słowo wyniku.
5. **Kształty callbacków, których §5 nie rozstrzygał** (notka z datą w v2 §5): `evolve/2` tylko przy
   zadeklarowanym stanie; PM ma callback tylko na reakcję lub timer, które coś wydają; callback read modelu
   `(event) :: :ok` do E6; callback query w `C.Queries.*` obok parametrów. **`reject/1` bez `reject/2`**:
   `EhOsContract.Rejection` nazywa tylko inwariant, bo odmowa idzie do logów i wywołujących (§17).
6. **Stan process managera zaczyna się od pól `correlate`**, tak jak stan jednostki od tożsamości. Wyszło przy
   pisaniu `ScenarioCase`: callback timera dostaje sam stan, a bez korelacji nie miałby z czego zbudować
   komendy. Notka w v2 §4.2.
7. **Cena I4 (literały w `emit/1`), zmierzona na deciderze:** dwa wyniki `qualify_referral` mają wspólne dwa
   pierwsze zdarzenia, które trzeba zapisać w każdym z dwóch `emit`. Zostawione — reguła kupuje sprawdzenie w
   czasie kompilacji — ale to pierwszy pomiar i warto go powtórzyć na VisitSettlement w E6.
8. **Wygenerowane moduły powstają `Module.create/3` na pliku i linii deklaracji**, co widać w chunku
   `debug_info` (`anno`); w testach `Code.compile_string` nie pisze chunka `Docs`. Typ mapy w `@type t` wraca z
   `Code.Typespec` z polami posortowanymi — tak przechowuje je Erlang, więc test porównuje posortowane.
9. **`Row` read modelu i parametry query nie wymuszają kluczy** (`@enforce_keys`), komendy i zdarzenia tak.
   Czy `Row` stanie się schematem Ecto, rozstrzyga E6.
10. **`ContractExample` zostaje** dla testów v1 (`sandbox/test/contract_examples_test`,
    `rehmed_contract_examples_test`, `universality_gate_test`); znika z ostatnim z nich — VisitSettlement w E6,
    reszta w E9 i E11. `ScenarioCase` zachowuje jego semantykę podciągu i dodaje dopasowanie pól oraz
    zabezpieczenie, że wynik decyzji mieści się w deklaracji.
11. **Nazwy `:state` i `:row`** dla komendy, zdarzenia albo query dawały alias kolidujący z `State`/`Row` w
    implementacji — zapisane tu jako otwarte na E5b, zamknięte w przeglądzie (znalezisko 5, N2). Przy
    okazji: pole zdarzenia `consumes "<nazwa>"`, którego deklaracja nie wymienia, jest odrzucane przez
    samego Elixira (klucz spoza struktury `C.Received.*` we wzorcu) — tę część D11 daje generowana struktura.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`).** Dziesięć znalezisk:
1. I3 brało zmienną ze strażnikiem (`when is_struct(e, A)`) za catch-all i wyłączało sprawdzenie pokrycia —
   **poprawione** w `dc52aa8`; moduledoc mówi teraz, że I3 czyta wzorce, nie strażniki.
2. Pola `correlate` wstrzykiwane do stanu PM zawsze jako `:id` — **poprawione** w `c62601b`: typ z lokalnego
   zdarzenia, `:id` tylko dla pola, które niosą wyłącznie zdarzenia konsumowane.
3. Drugie `use C, …` w tym samym module po cichu zastępowało pierwsze — **poprawione** w `1bf1d13` (I1). Przy
   tym wyszło, że atrybut ustawiony w cytowanym kodzie `use` nie jest widoczny dla następnego `use`, bo ciało
   modułu jest rozwijane, zanim ruszy; ustawiany jest teraz w czasie rozwijania.
4. I4 odmawiało `for … uniq: true, do: %E{}` — **poprawione** w `8534629`; `into:` i `reduce:` dalej odmawiane.
5. Nazwy `:state`/`:row` — **poprawione** w `c1dc59a` (N2).
6. Niepasujące dane typu domeny kończyły scenariusz `MatchError` — **poprawione** w `7270465`: scenariusz
   pada z nazwą pola. Tamże zmiana nazwy fikstury `ManagerRight`, która kolidowała z testem E4.
7. Decyzja zwracająca mapę zamiast struktury kończyła scenariusz `KeyError` — **poprawione** w `284ff24`.
8. DCB konsultujący własne zdarzenie miał je dwa razy w `evolve` — **poprawione** w `45904b9`.
9. Odnajdywanie zdarzenia konsumowanego po nazwie lokalnej jest w trzech miejscach — **pominięte**: X5–X6 w
   E5b czytają zdarzenia konsumowane między kontraktami i tam powinien powstać jeden akcesor.
10. Makra liczą `Callbacks.of/3` przy każdym wywołaniu — **pominięte**: koszt tylko w czasie kompilacji,
    liniowy w liczbie wywołań.

Każda poprawka zweryfikowana wstecz: na kodzie sprzed niej pada dokładnie nowy test. Silnik 646 → 654. Diff
E5a nie dotyka czytelników v1 (`trace`, `graph`, `conformance`, `report`, `run`, …), tasków, sandboxa ani
pakietu web, więc porównanie bajtów raportu i grafu na bazie dev nie ma czego mierzyć i nie było puszczane.

### E5b — co wyszło (25 września)

Stan: `EhOsContract.Next.Contract.Links` (reguły między modułami, L3) z czterema grupami — `Links.Domain`
(X1–X4, D10, D11), `Links.Siblings` (X5–X6), `Links.System` (X7, X8, D14), `Links.Scenarios` (X9) — i kompilator
Mixa `Mix.Tasks.Compile.EhOsContract`, zarejestrowany w `mix.exs` pakietu (sprawdza fikstury) i sandboxa. Obok:
`Model.consumed/2` (znalezisko 9 z przeglądu E5a), `Data.problems/3` (wartości typów domeny),
`DslRules.closest/2` (podpowiedź nazwy wspólna dla L3 i L4), `file:`/`line:` w `__eh_os_implementation__/0`.
Brama zielona na każdym z sześciu commitów; silnik 654 → 685, sandbox 45, web 31; linie `eh_os_contract.check`
identyczne co do bajtu w obu projektach na każdym commicie.

**Rozstrzygnięcia z początku etapu.** Użytkownik potwierdził zgodę na commity i zapis dokumentów oraz wybrał
test „czysta funkcja i jeden prawdziwy `mix compile`”. O skanie i lokalizacjach powiedział, że nie widzi
konsekwencji; asystent je wyłożył i wybrał rekomendowane, bo oba są szczegółem do zmiany później:
- *Moduły* — pliki `.beam` ze ścieżki kompilacji projektu, eksporty czytane przez `:beam_lib` przed
  załadowaniem, bez konfiguracji; domena i rodzeństwo nazwane w kontrakcie szukane po nazwie. Rejestr v1 odpadł:
  wymaga konfiguracji w każdym projekcie, a plik `.app`, który czyta, Mix pisze dopiero po kompilatorach.
- *Lokalizacje* — to, co Spark sam trzyma w skompilowanym module (`spark_dsl_config/0`: deklaracje z
  `anno`), poza modelem i digestami (v2 §9). L3 czyta te same deklaracje co L2 (`Rules.declarations/1`), więc
  błędy obu warstw powstają tym samym kodem. Doszły tylko linia `use` kontraktu (persist Sparka) i miejsce
  `use` implementacji.
- *Numeracja* — reguły z decyzji mają prefiks decyzji („D10: …”, „D11: …”, „D14: …”), jak w E4.
- *`check` powtarzający L3* — nie w E5b: oba projekty rejestrują kompilator; wchodzi z L5 w E10.

**Odbiór E5, część E5b, jak sprawdzony.**
- *Literówka w `by:` psuje zwykłe `mix compile`* — `compiler_test`: projekt w katalogu tymczasowym, prawdziwy
  `mix compile`, błąd `X2: command :close_visit: by: :recepion is not an actor of Fx.Domain; did you mean
  :reception?` na `lib/visit.ex:7`, wypisany raz, w formacie błędu Elixira (z fragmentem źródła). Obok: usunięcie
  aktora **z samej domeny** przekompilowuje jeden plik i też psuje kompilację, bo L3 biegnie co raz (v2 §8).
- *Para wydawca–subskrybent: usunięcie pola konsumowanego zdarzenia albo zmiana jego typu psuje `mix compile` z
  błędem wskazującym obie strony* — `compiler_test` na kompilacji przyrostowej, w której przekompilowuje się
  tylko wydawca: błąd stoi na `include` subskrybenta (`lib/billing.ex:14`) i nazywa zdarzenie wydawcy z
  `lib/booking.ex:9`. *Kontrole*: pole opcjonalne dodane i pole, którego subskrybent nie używa, przetypowane —
  kompiluje się. To samo jako czyste funkcje w `contract_links_siblings_test`, także dla `correlate` process
  managera i `match:` boundary.
- *Każda reguła L3 z kontrolą* — `contract_links_{domain,siblings,system,scenarios}_test`. Wstecz, grupa po
  grupie: bez `Domain` pada 8 odmów, bez `Siblings` 6, bez `System` 3, bez `Scenarios` 2; kontrole za każdym
  razem przechodzą. Bez zarejestrowanego kompilatora ta sama zmiana w projekcie-fiksturze się kompiluje.

**Ustalenia.**
1. **Prawdziwy `mix compile` w teście kosztuje około sekundy**, jeśli projekt nie ma zależności, a biblioteki
   dostaje z `_build` pakietu przez `ERL_LIBS`. Potrzebne jest `--no-prune-code-paths`: bez niego Mix wycina ze
   ścieżki kodu wszystko, czego nie ma w `deps` projektu, i `use EhOsContract.Domain` pada na „module is not
   loaded”. Trzy testy `compiler_test` biegną razem około 3,5 s.
2. **Mix nie wypisuje diagnostyk zwróconych przez kompilator**; kompilator wypisuje je sam przez
   `Code.print_diagnostic/2`, więc wyglądają jak błędy Elixira. Test pilnuje, że wychodzą raz.
3. **X5 odrzuca rodzeństwo z innej domeny** — to kontrakt innej aplikacji, a te rozmawiają tylko przez
   `publish` (D11). §6 tego nie mówił; notka z datą. **X6 dla `projects`** sprowadza się do X5, bo deklaracja nie
   nazywa pól; pola projekcji pilnuje dopasowanie struktury w implementacji (mechanizm 3 z §7).
4. **Pole `correlate` process managera, które niosą tylko zdarzenia konsumowane, jest w stanie PM typu `:id`**
   (`Build`, z E5a). X6 porównuje z tym typem, więc wydawca z takim polem jako `:integer` jest odrzucany, dopóki
   stan PM nie zadeklaruje pola wprost. Zgodne z wygenerowaną strukturą stanu, ale warto wrócić, gdy E7
   uruchomi process managery.
5. **X2 dla aktora scenariusza jest dziś wtórny wobec S7**: S7 trzyma aktora w `by:` komendy, więc literówka w
   nim idzie w parze z literówką w `by:` i wychodzą dwa błędy. Zostawione, bo §6 wymienia aktora scenariusza
   wprost.
6. **Fikstury pakietu przechodzą L3** (`UniversalityGate.Next` z domeną, wartościami enum w scenariuszach i
   implementacją); sandbox nie ma jeszcze kontraktu v2, ale `Rehmed.Domain` jest skanowany. Pierwszy kontrakt v2
   sandboxa (VisitSettlement, E6) będzie sprawdzany od pierwszej kompilacji.
7. **Katalog `tmp/`.** `@tag :tmp_dir` pisze do `packages/eh_os_contract/tmp/`; dopisane do
   `.gitignore` pakietu.

**Przegląd przed PR (25 września, `/code-review high origin/main..HEAD`).** Osiem znalezisk:
1. S3 nie sprawdzał danych `given` process managera ani `given` zdarzenia konsultowanego przez boundary, a X9
   zakładał, że sprawdził — nieznany klucz albo brak pola przechodził przez obie warstwy. **Poprawione** w
   `1693da3`, w S3 (L2), bo tam są pola lokalnych zdarzeń: oba idą tym samym sprawdzeniem co zdarzenie z `on`.
2. X8 czytał `file:`/`line:` z opisu implementacji, więc `.beam` sprzed tej zmiany kończył `mix compile`
   `KeyError`em w kompilatorze — **poprawione** w `6793974`: taka implementacja jest odrzucana bez miejsca.
3. `Links.Siblings` rozwiązywał przemianowania `as:` sam, czwarta kopia tego, co `Model.consumed/2` miał
   zastąpić — **poprawione** w `bfbd341`.
4. `Links.Domain` trzymał własną listę struktur kontraktu obok tej w `Rules.Fields` — **poprawione** w `6b79f40`:
   `Rules.Fields.structs/1` jest jedną listą.
5. Kontrakt-rodzeństwo był budowany od nowa przy każdym `consumes` i każdym wpisie scenariusza —
   **poprawione** w `f2d9746`: `Links.contract/2` bierze ten z `system`.
6. Brak testu L3 dla zdarzenia przemianowanego przez `as:` — **poprawione** w `bfbd341` (test przechodzi przed i
   po refaktorze 3, który przypina).
7. Kompilator czyta eksporty każdego `.beam` przy każdej kompilacji — **pominięte**: zmierzone 759 plików w
   109 ms razem ze startem VM (około 0,14 ms na plik), a alternatywa, manifest kompilatora Elixira, jest
   prywatnym API Mixa.
8. `Links.System.human/1` powtarza prywatne `human/1` z `Implementation` — **pominięte**: jedna linia w dwóch
   modułach.
Poprawki 1 i 2 zweryfikowane wstecz: na kodzie sprzed nich pada dokładnie nowy test. 3, 4 i 5 nie zmieniają
zachowania; testy L3 przechodzą bez zmian. Silnik 685 → 688. Sprawdzone poza testami: prawdziwe `mix compile`
projektu-fikstury w scratchpadzie — z błędem X2 w formacie Elixira, a bez zarejestrowanego kompilatora ta sama
kompilacja przechodzi. Diff nie dotyka czytelników v1, tasków ani pakietu web, więc porównanie bajtów raportu i
grafu na bazie dev nie ma czego mierzyć i nie było puszczane.

### E6 — co wyszło (26 września)

**Rozstrzygnięcie z początku etapu: kształt `EhOsContract.Authorizer`.** Użytkownik go potwierdził po
rozpisaniu przebiegu od manifestu po kliknięcie (manifest z rolami → przypięcie roli w EHOS-ie → token z
`sub`, `cap`, `scp` → lokalne sprawdzenie w aplikacji, bez pytania EHOS-a). Trzy decyzje, zapisane w v2 §11
notką z datą:
1. **Sprawdzenie stoi na drzwiach aplikacji.** `Authorizer` jest pytany o wywołanie z credentialem (dziś
   człowiek, później także system z własnym credentialem — `eh-os` D-23, G-2). Kod samej aplikacji pilnuje
   kontrakt: reakcję jej `issues:`, aktora `:system` domeny `by:`/`recorded_by:` deklaracji. Kryterium to
   pochodzenie wywołania, nie rodzaj aktora — pierwsza propozycja mówiła „tylko człowiek” i była myląca.
2. **`Authorizer` może zawęzić, nie może poszerzyć.** `authorize/2 :: :ok | {:error, powód}`; czysta decyzja
   to `Authorizer.check/2` (`:missing_capability`, `:unscoped_grant`, `:outside_scope`), domyślna
   implementacja to samo `check/2`, a po `:ok` silnik liczy `check/2` jeszcze raz z aktora i rzuca, gdy ten
   odmawia. Uprawnienia muszą więc przyjść w credentialu. `scope` porównywany w postaci stringa z `scp`.
3. **`record/3` z credentialem jest odrzucany do E9**, bo EHOS nadaje tylko komendy i query, więc nie ma nazwy
   uprawnienia do nagrania zdarzenia. Aktor `:system` nagrywa normalnie.

Przy okazji użytkownik zapytał o poziom zabezpieczenia. Odpowiedź: standard (JWT Ed25519 sprawdzany lokalnie z
JWKS, krótki czas życia, `aud` na aplikację i środowisko, RBAC spłaszczony do uprawnień, fail closed, audyt),
z egzekwowaniem mocniejszym niż w typowej aplikacji, bo w jednym miejscu w dispatchu, i z drugim sprawdzeniem
wierszy query. Słabsze strony, świadomie przyjęte: do 10 minut po odebraniu roli, bearer bez wiązania z
urządzeniem (DPoP/mTLS), do 5 minut po usunięciu klucza, `scope` jako jedno pole, audyt bez ochrony przed
podmianą, własna pamięć JWKS. **Do `eh-os`, przez użytkownika:** logowanie frontendu zwykłej aplikacji nie
jest tam zaprojektowane (najbliżej G-3), a od niego zależy reszta. *1 października:*
[eh-os#95](https://github.com/EmpoweredHouse/eh-os/issues/95).

**Stan.** Dziewiętnaście commitów, brama zielona na każdym: zapis ustaleń (`bbad60c`); `Actor` i `Authorizer`
(`04952ec`); `Codec` i `Key` (`4290aca`); `dispatch/3` z `Implementations`, `CommandRecord` i `Receipt`
(`c724c83`); read modele i polityki w transakcji (`6e8cbfe`); `record/3` i `query/3` (`e2988bb`);
`EhOsContract.Plug` (`77d7a4d`); przejście VisitSettlement i `0.3.0-dev` (`38eb854`); banery na skillach i
poprawki ADR (`115c15f`); zapis stanu (`d51b99e`); scenariusz query, `answers` (`7903265`); zapis stanu (`97208b2`); siedem poprawek z
przeglądu przed PR (`bd85190`..`7303de9`). Silnik 688 → 756 testów, sandbox 45 → 47, web 31. `check` silnika 0/8/16 bez zmian;
sandboxa 0/5/23 → 0/4/19.

**Odbiór E6, jak sprawdzony** (testy w `test/runtime/` pakietu i w `sandbox/test/`):
- *Cztery scenariusze przechodzą* — `rehmed_visit_settlement_scenarios_test`. Wstecz: decider, który zamyka
  niedopłatę, wywraca scenariusz odmowy.
- *Decyzja zwracająca niezadeklarowane zdarzenie rzuca, magazyn bez zmian; kontrola: zadeklarowane dopisane* —
  `dispatch_command_test`, `misbehave` na `DispatchRig`. Wiersz `failed` z `failed_in: "decider"` jest.
- *Wyjątek w projekcji inline wycofuje dopis* — `dispatch_inline_test`: projekcja ruchów pada na 13, a log, druga
  projekcja i saldo zostają jak przed; kontrola: 12 przechodzi.
- *Odmowa uprawnień niczego nie zapisuje — ani logu, ani `_commands`* — `dispatch_command_test`.
- *Query o wartość `scope` spoza grantu odrzucone, zanim ruszy implementacja* — `dispatch_record_query_test`;
  implementacja wysyła wiadomość procesowi, więc widać, że nie ruszyła; kontrola: w grancie rusza.
- *Uprawnienie ze `scope` bez wartości odrzucone (fail closed)* — ten sam plik, pusta lista i brak wpisu.
- *Implementacja zwracająca cudzy wiersz zatrzymana; kontrola: wartość z grantu przechodzi* — ten sam plik,
  `OutsideScopeError`; ta sama „cieknąca” implementacja przechodzi, gdy grant obejmuje wszystkie oddziały.
- *Konflikt ponawiany* — `dispatch_command_test`: decider dopisuje do strumienia za plecami decyzji. Wstecz: z
  jedną próbą zamiast trzech test pada. W transakcji wołającego wynik to `{:error, :conflict}`.
- *Ten sam klucz idempotencji zwraca te same pozycje* — `dispatch_command_test`, także przez HTTP w `plug_test`.
- *Delta `check` w sandboxie dotyczy tylko linii VisitSettlement* — ubyło jedno ostrzeżenie („no `accountable`”)
  i cztery informacje („no handler”) VisitSettlement v1; żadna inna linia się nie ruszyła (diff wyjść).

**Ustalenia.**
1. **Konflikt w zagnieżdżonym dispatchu polityki nie może wystąpić**, bo blokada dopisu jest trzymana od
   pierwszego dopisu transakcji do jej końca; dispatcher traktuje go jak błąd. Odmowa komendy polityki na
   inwariancie zostawia pierwszą komendę w mocy, a wiersz `rejected` się zapisuje: to odpowiedź jednostki, nie
   awaria.
2. **Wiersz `failed` trzyma moduł wyjątku, nie komunikat.** Komunikat może cytować wartość (np. `MatchError`),
   a v2 §17 każe trzymać dane osobowe z dala od błędów; wyjątek i tak idzie dalej do wołającego i jego loggera.
3. **Implementacje są znajdowane skanem aplikacji hosta**, trzymanym w `:persistent_term`
   (`EhOsContract.Implementations`), a nie rejestrem z bootu (§10.5). Moduł dodany do działającego węzła jest
   widoczny po restarcie. Deklaracja `:in_transaction` bez implementacji zatrzymuje dispatch zamiast być
   pominięta.
4. **`Row` zostaje zwykłą strukturą, nie schematem Ecto** (rozstrzygnięcie z E5a, mechanika). Read model pisze
   własne tabele hosta (v2 §12), a query mapuje wiersze na `Row`; schemat Ecto potrzebowałby nazwy tabeli w
   kontrakcie, a kontrakt nie wie, gdzie host trzyma dane.
5. **Cena literałów w `emit/1`, zmierzona drugi raz — na VisitSettlement jest zerowa.** `close_settlement` ma
   trzy gałęzie, każda z jednym, innym zdarzeniem; nic się nie powtarza. Pierwszy pomiar (`qualify_referral`,
   dwa wspólne zdarzenia w dwóch `emit`) był kosztowny. Dwa pomiary, dwa wyniki: koszt zależy od tego, czy wyniki
   decyzji mają wspólny prefiks. Reguła zostaje.
6. **Aktor w logu to `"actor:<subject>"`, `"system:<nazwa>"` albo `"policy:<nazwa>"`** (v2 §10.3, `issued_by`),
   także w kolumnie `actor` zdarzeń v2. v1 pisał tam goły podmiot albo `"system"`.
7. **Scenariusz query: `answers`, według wariantu read modelu z ESDM** (`7903265`). Użytkownik zapytał, jak to
   robi ESDM: rozszerzenie Given-When-Then ma wariant read modelu — given zdarzenia, when query z parametrami,
   then `result` albo zmaterializowany read model; porównania ESDM nie ustala. Użytkownik zgodził się na
   implementację w E6. Słowo `answers` (lista wierszy; przy `returns: :one` wiersz albo `nil`); S2 — `given` to
   zdarzenia, które read model projektuje; S3 — pola wiersza i parametry; S6 — jedno `answers`, tylko po query;
   X9 — wartości typów domeny. **Porównanie: dokładnie tyle wierszy, ile wymienionych, każdy pasuje do innego
   zwróconego na wymienionych polach, kolejność bez znaczenia** — inaczej niż w pierwszej propozycji
   („oczekiwane są wśród zwróconych”), bo ta nie pozwoliłaby powiedzieć, że wiersza innej przychodni w
   odpowiedzi nie ma; zmiana wyjaśniona użytkownikowi przed implementacją. Wariant „cały read model” pominięty.
   `ScenarioCase` projektuje `given` przez implementację read modelu i pyta query w transakcji wycofywanej na
   końcu, więc moduł testu z takim scenariuszem pobiera połączenie sandboxa Ecto. Klucz `answers` jest w modelu
   tylko przy scenariuszu query, więc słowo nie ruszyło wersji żadnego kontraktu. Wstecz na `DispatchRig`: złe
   saldo, pusta odpowiedź i nadmiarowy wiersz wywracają scenariusz.
8. **F2 ma konsekwencję w kodzie**: korekta przed przekazaniem wizyty nie ma dnia (`handed_over_on` jest `nil`),
   więc zdarzenie nie pasuje do pola `business_date` i dispatch rzuca. Port tłumaczy, więc zostało; opisane w
   moduledocu kontraktu jako pytanie do właściciela, obok F1.
9. **`CLAUDE.md` mówi, że Rehmed nie ma tu kodu** — nieprawdziwe już przed E6 (`Rehmed.Settlement.decide/1`), a
   od E6 kodem jest `Rehmed.Settlement.VisitSettlement`. Poprawka w `CLAUDE.md` należy do E11, który przepisuje
   ten plik; do tego czasu zapisane tu.
10. **Query string w `EhOsContract.Plug`** niesie każdą wartość jako tekst, więc `Codec.decode/4` dostał
    `strings: true` (liczba całkowita i wartość logiczna z tekstu, tylko na najwyższym poziomie). Nagłówek
    `x-correlation-id`, który nie jest UUID, jest odrzucany z 400, zanim cokolwiek ruszy.
11. **Nowe migracje testowe pakietu wypisują raz ostrzeżenie „redefining module”**, gdy `TestRepo` i `CommitRepo`
    ładują ten sam plik w jednym przebiegu. To ostrzeżenie czasu wykonania, nie kompilacji; brama przechodzi.
12. **`Model.capabilities/1` jest liczone przy każdym dispatchu** (nazwa uprawnienia do żądania). Tanie przy
    VisitSettlement; pamięć podręczna, gdy pomiar pokaże potrzebę.

**Przegląd przed PR (26 września, `/code-review high origin/main..HEAD`).** Dziesięć znalezisk:
1. Decyzja mogła zwrócić zdarzenie z tożsamością innej jednostki, a dispatch dopisywał je do strumienia komendy
   (zdarzenie konta a-2 w strumieniu a-1, wliczane do salda a-1) — **poprawione** w `bd85190`: tożsamość zdarzenia
   musi być tożsamością komendy, inaczej wyjątek i nic nie jest dopisane.
2. Query z `returns: :one` przepuszczało listę (`List.wrap`), także w `ScenarioCase` — **poprawione** w
   `f393da7`; `DispatchRig` dostał query zwracające jeden wiersz, ze scenariuszem.
3. Porażka komendy wydanej przez politykę zapisywała w wierszu pierwotnej komendy `failed_in` z wnętrza
   (`"decider"`) — **poprawione** w `7100331`: cała reakcja idzie pod `"policy:<nazwa>"`.
4. Klucz idempotencji komendy polityki nie zawierał kontraktu, a indeks przyjętych kluczy obejmuje całą
   aplikację — **poprawione** w `25cf70c`: `"policy:<kontrakt>:<nazwa>:<id zdarzenia>:<n>"`, notka w v2 §11.
5. Zapis wiersza `failed` w `rescue` może zasłonić pierwotny wyjątek, gdy pada sama baza — **pominięte**: dotyczy
   tylko sytuacji, w której baza pada w trakcie dispatchu, test wymaga repo psującego się na żądanie; wraca w E7
   z obsługą padających konsumentów.
6. Zdarzenia z `given` w scenariuszu query nie miały `id` ani `position` w `__meta__`, a dispatch je daje —
   **poprawione** w `c4f5272`; projekcja sald `DispatchRig` zapisuje pozycję w kolumnie `NOT NULL`.
7. Uprawnienia, wartości domeny i aktorzy liczeni przy każdym wywołaniu, w Plugu dla każdego kontraktu —
   **pominięte**: to ustalenie 12; pamięć podręczna, gdy pomiar pokaże potrzebę.
8. To samo sprawdzenie aktora `:system` w trzech klauzulach — **poprawione** w `c478c9d`.
9. Polskie cytaty w moduledocu i komentarzu VisitSettlement i w moduledocu decidera, przeniesione z v1 —
   **poprawione** w `7303de9`.
10. `EhOsContract.Plug.init/1`, `call/2` i `Authorizer.Default.authorize/2` bez `@doc` i `@spec` — **poprawione** w
    `c478c9d`.
Poprawki 1, 2, 3 i 6 zweryfikowane wstecz: na kodzie sprzed każdej pada dokładnie nowy test (przy 6 — trzy
testy scenariuszy query, żaden test dispatchu). Poprawka 4 ma test formatu klucza, który pada na starym kodzie.
Silnik 751 → 756, sandbox 47, web 31; `check` bez zmian (0/4/19, 0/8/16). Poza testami nic nie było puszczane:
baza dev jest punktem odniesienia porównań bajtów raportu, a v2 czytelnicy logu przychodzą w E7; ścieżkę HTTP
sprawdza `plug_test` przez `Plug.Test`.

### E7a — co wyszło (26 września)

**Stan.** Na `dsl-v2/e7-async`, zmergowane jako PR #14: zapis podziału (`a0828e8`), V04 (`213b0b4`), efekty
(`fbce133`), subskrypcje z przebudową i `drain/1` (`1e85f09`), supervisor (`279494c`), testy na prawdziwych
commitach (`b238ff2`), task `subscriptions` (`b9db321`), znalezisko 5 z przeglądu E6 (`c0cdf28`) i ten zapis.
Brama zielona na każdym commicie z kodem. `a0828e8` to sam `PLAN.md`, zacommitowany bez przebiegu bramy na
drzewie, które przed chwilą przeszło ją jako `09ced0e`. Od następnego commita szło to już skryptem, który
commituje dopiero po `exit $rc`. Silnik 756 → 790 testów, sandbox 47, web 31; `check` bez zmian (0/8/16, 0/4/19).
Notka z datą w v2 §12 opisuje, co zbudowano.

**Odbiór E7a, jak sprawdzony:**
- *Przebudowa daje identyczne wiersze* — `subscription_test`, „rebuilding”: read model asynchroniczny (linie
  księgi) po `rebuild` i `drain` ma te same wiersze; read model w transakcji (salda) jest w trakcie pomijany
  przez dispatch, dogania go runner, wraca do dispatchu. Wstecz: dispatch projektujący przebudowywany read
  model wywraca test — ale dopiero po dołożeniu otwarcia konta w trakcie przebudowy. Pierwsza wersja testu
  przechodziła pusto, bo wpłata na wyczyszczonej tabeli to `update_all` na zera wierszy.
- *Trujące zdarzenie zatrzymuje konsumenta dokładnie na swojej pozycji* — `subscription_test` („a poison
  event”) i `subscription_commits_test` (każda próba to osobny commit): `failed_position` = pozycja trującego,
  `position` = poprzednie zastosowane, trzy próby, `failing`; dalsze `drain` go nie ruszają, `skip` pomija tylko
  jego. Wstecz: bez płotu po porażce padają oba testy trującego zdarzenia.
- *Dwóch runnerów nie bierze tej samej paczki (prawdziwe commity)* — `subscription_commits_test` na
  `CommitRepo`: drugi dostaje `:idle`, gdy pierwszy trzyma paczkę; czterech naraz stosuje 39 zdarzeń dokładnie
  raz. Wstecz: bez `FOR UPDATE SKIP LOCKED` padają oba testy.

**Ustalenia.**
1. **Nowy konsument uporządkowany zaczyna od pozycji 0**, więc nowa polityka reaguje na historię — z kluczami
   z każdego zdarzenia, więc drugi raz niczego nie dopisze. Tak startują handlery Commanded. Nowy read model w
   transakcji zaczyna od głowy logu, bo dispatch projektował go od początku. Read model dodany do logu, który
   ma już jego zdarzenia, przebudowuje się ręcznie (`--reset`). Mechanika, rozstrzygnięta przeze mnie. Opcja
   „zacznij od głowy” dla polityki wejdzie, gdy pierwszy host jej potrzebuje.
2. **Dispatch przesuwa wiersz każdego read modelu w transakcji**: jedno zapytanie i jedna aktualizacja na read
   model na dispatch, pod blokadą dopisu. Bez pomiaru; to ta sama kategoria co ustalenie 12 z E6.
3. **Wersja konsumenta to digest deklaracji i zdarzeń, które bierze.** Read model, którego zdarzenie zyskało
   pole, jest `stale`. Zmiana samego kodu implementacji wersji nie rusza, więc przebudowę po poprawce
   projekcji robi człowiek. `stale` dalej bierze zdarzenia.
4. **`drain(only:)` a efekty**: joby są Obana i idą całą kolejką `:events`, więc z `only:` joby ruszają tylko
   wtedy, gdy `only:` wymienia efekt. To węższe od „`only:` zawęża do nazw konsumentów” w decyzji.
5. **Oban musi chodzić na repo dispatchu**, inaczej job nie commituje się ze zdarzeniem; dispatch odmawia
   wstawienia. Klucz konsumenta to `"<kontrakt>:<rodzaj>:<nazwa>"` — nazwa wiersza subskrypcji i argument jobu.
6. **Powiadomienie po commicie nie jest widziane przez żaden test**: sandbox nigdy nie commituje. Runner w
   `boot_test` dogania przez poll co sekundę.
7. **Pytanie z E2 („jak uruchomić dispatcher na drugim repo”)**: test `async: false` przestawia
   `config :eh_os_contract, :repo` na `CommitRepo` i przywraca w `on_exit`. Do zasymulowania padającej bazy
   jest `EhOsContract.BrokenRepo` — `TestRepo` z jednym zepsutym `insert!`.
8. **`EhOsContract.boot/0` zniknął**, dziecko jest supervisorem — linia w CHANGELOG. Sandbox w dev **nie był**
   uruchamiany: boot zapisałby wiersze wdrożenia i subskrypcji do bazy dev, która jest punktem odniesienia
   porównań bajtów raportu. Pierwszy przebieg w dev należy do E7c, razem z czytelnikami v2.

**Przegląd przed PR (26 września, `/code-review high origin/main..HEAD`).** Dziesięć znalezisk; dziewięć
poprawionych, każde osobnym commitem z testem, który na kodzie sprzed poprawki pada jako jedyny:
1. Konsumenci w transakcji szli zdarzenie po zdarzeniu, więc zagnieżdżony dispatch polityki na pierwszym
   zdarzeniu projektował swoje zdarzenie przed drugim zdarzeniem komendy — read model widział e1, e3, e2
   (regresja względem E6). **Poprawione** w `ad0f91c`: najpierw wszystkie read modele, potem polityki, potem
   efekty. Fikstura dostała `split_deposit` (dwa zdarzenia), a salda projektują też `account_flagged`.
2. Polityka uporządkowana dispatchuje w transakcji kroku, gdzie konflikt nie jest ponawiany; inny piszący do tego
   samego strumienia liczył się jako porażka zdarzenia, trzy — `failing`. **Poprawione** w `b8f36aa`: krok
   polityki bierze blokadę dopisu przed decyzją. Test na `CommitRepo` z nową polityką fikstury
   `return_small_change` (jej komenda nie uruchamia efektu, więc obywa się bez Obana).
3. `Implementations.consumer/1` szukał tylko w skonfigurowanych aplikacjach, dispatch także w aplikacji
   kontraktu — job efektu kontraktu spoza `applications:` był anulowany. **Poprawione** w `973467e`. Zostaje:
   konsument uporządkowany spoza skonfigurowanych aplikacji nie dostaje wiersza ani runnera, bo boot nie wie,
   który kontrakt będzie dispatchowany; zapisane w `subscribed/0`.
4. Powrót przebudowanego read modelu do dispatchu brał blokadę dopisu, trzymając już wiersz, odwrotnie niż
   `rebuild/2` — zakleszczenie z `--reset`. **Poprawione** w `31fd7b4`: osobna transakcja, najpierw blokada
   dopisu. Pierwsza wersja testu zależała od kolejności testów (dochodzenie do głowy pętlą kroków zużywało
   powrót, gdy log nie miał zdarzeń sald) i padła w bramie; pozycja jest teraz ustawiana wprost.
5. Powiadomienie po każdym dispatchu, także po odmowie i bez konsumentów uporządkowanych — przy notifierze
   Postgresa to zapytanie. **Poprawione** w `5c33fb1`, test przez telemetrię Obana.
6. Runner dla każdego read modelu w transakcji odpytuje co sekundę, choć pracuje tylko przy przebudowie —
   **pominięte**: jedno lekkie zapytanie na sekundę na read model, a przebudowa bez runnera musiałaby mieć
   osobną ścieżkę startu; wraca, gdy pomiar pokaże koszt, jak ustalenie 12 z E6.
7. Wiersz read modelu w transakcji przesuwany po każdym zdarzeniu — **poprawione** w `e0cdac8`: raz na dispatch.
   Ustalenie 2 wyżej jest od tego commita prawdziwe co do liczby aktualizacji.
8. Job efektu, który przestał brać typ zdarzenia, padał `KeyError` i szedł do `discarded` — **poprawione** w
   `75b2c8c`: anulowany, jak job usuniętego efektu.
9. Publiczne `EffectJob.perform/1`, `Runner.init/1`, `handle_info/2` bez `@doc` i `@spec` — **poprawione** w
   `75b2c8c` i `5c065f3`.
10. Dispatcher pytał o tabelę subskrypcji po nazwie zamiast przez `SubscriptionRecord` — **poprawione** w
    `e68d2b0`, bez zmiany zachowania.

Silnik 790 → 798 testów, sandbox 47, web 31; `check` bez zmian (0/8/16, 0/4/19).

### E7b — co wyszło (26 września)

**Stan.** Na `dsl-v2/e7b-process-managers` od `main` po PR #14, zmergowane jako PR #15: zapis decyzji
(`3f35299`), P4 odrzuca process managera `:in_transaction` (`ff65927`), runtime process managerów i timerów
(`d2dfbae`), poprawki ADR i ten zapis. Brama zielona na każdym commicie, także na tym z samym `PLAN.md`. Silnik
798 → 810 testów, sandbox 47, web 31; `check` bez zmian (0/8/16, 0/4/19).

**Odbiór E7b, jak sprawdzony:** *odpalony timer uruchomiony dwa razy daje jeden dispatch* —
`process_manager_test`, „a timer fired twice”: ten sam job wykonany dwa razy, zanim process manager weźmie
którekolwiek odpalenie, daje dwa zdarzenia `timer_elapsed` i jedno oflagowanie; wykonany po nim nie dopisuje
niczego. Wstecz: bez sprawdzenia tokenu test pada. Obok: „nie przed czasem” — job wykonany godzinę za wcześnie
drzemie 3600 s; bez sprawdzenia terminu pada siedem testów, w tym ten.

**Ustalenia.**
1. **Semantyka wzięta ze `ScenarioCase`**, żeby scenariusz i runtime mówiły to samo: callback reakcji dostaje
   zdarzenie i stan *sprzed* niego, potem `evolve/2`. Zdarzenie `starts_on` dla działającego przebiegu nie
   jest reakcją (reaguje tylko `on`), zdarzenie przebiegu, który nie wystartował albo się skończył, niczego nie
   zmienia.
2. **Token timera to id zdarzenia, które go nastawiło, a `wait:` liczy się od jego `occurred_at`**, nie od zegara
   kroku — dzięki temu replay odtwarza te same timery, a job zaplanowany przed przebudową dalej pasuje.
3. **Replay jest chroniony trzy razy**: reakcje wyłączone, klucze z id zdarzeń, `TimerJob` unikalny po
   argumentach. Żadne pojedyncze usunięcie nie wywraca testu replayu, więc test przypina wynik, nie mechanizm.
4. **Ustalenie 4 z E5b (`correlate` typowane jako `:id`) nie wymagało zmiany**: korelacja w runtime to
   `Key.join` wartości pól zdarzenia, a `Key` zamienia każdą wartość na tekst, więc typ pola w stanie nie
   zmienia przebiegu.
5. **`at:` timera jest zbudowane, ale bez testu** — fikstura ma tylko `wait:`. Timer `at:` pola stanu, które w
   chwili nastawienia jest `nil`, rzuca, więc subskrypcja staje na tym zdarzeniu jako `failing`.
6. **Linia CHANGELOG o P4** weszła commitem runtime'u, nie tym, który zmienił regułę — wbrew zasadzie „tym samym
   commitem”.
7. **Poprawki ADR**: notka z datą w architecture §15 („wersja druga steruje, obietnice patrzą”) i przy jej
   wyzwalaczu („druga implementacja”), w design-rationale §15, i notka „as built” w v2 §12.

**Przegląd przed PR (26 września, `/code-review high origin/main..HEAD`).** Siedem znalezisk; pięć poprawionych
z testem, który na kodzie sprzed poprawki pada, jedno poprawione bez zmiany zachowania, jedno błędne:
1. **Nowy process manager na logu z historią** startował od pozycji 0 z reakcjami — wdrożony na rok historii
   wydałby komendy za każdy stary przebieg i odpalił naraz wszystkie zaległe timery. **Poprawione** w `a6aad4a`:
   nowy process manager zaczyna od replayu z wyłączonymi reakcjami; na głowie timer zaległy bez czekającego
   joba jest porzucany (przyszedł, gdy nikt nie sterował), a zaległy z czekającym jobem — po przebudowie
   działającego — odpala się. Boot i `drain/1` rejestrują tak samo. **Uwaga dla użytkownika:** to inna reguła
   niż dla nowej polityki z E7a (ta dalej zaczyna od 0 i reaguje na historię, z kluczami z zdarzeń); do
   rozważenia, czy polityce nie dać tej samej.
2. Job timera usuniętego process managera padał `MatchError` — **poprawione** w `47a01ca`: anulowany.
3. Stan przebiegu czytany `binary_to_term/1` bez `:safe` — **poprawione** w `3aaa30b`.
4. Replay brał jedno zdarzenie na krok pod blokadą dopisu — **poprawione** w `1acd77e`: paczki po 500, bez blokady.
5. Komentarz powrotu read modelu nad klauzulą process managera — **poprawione** w `b2713b6`.
6. „Martwa” klauzula `order(:process_manager)` — **błędne**: `order/1` sortuje też indeks; usunięcie wywróciło
   89 testów w bramie; doc poprawiony w `b2713b6`.
7. Timer `at:` bez testu — **poprawione** w `3d6c0a8`: przegląd tydzień po wpłacie w fiksturze. Ustalenie 5 wyżej
   jest od tego commita nieaktualne.

Silnik 810 → 816 testów, sandbox 47, web 31; `check` bez zmian.

### E7c-1 — co wyszło (26 września)

**Stan.** Na `dsl-v2/e7c-conformance` od `main` po PR #15, niewypchnięte: handoff (`9285de2`), zapis decyzji
(`632a5cf`), start nowej polityki (`706bee3`), `_event_runs` (`815801e`), `Trace` i `Run` na v2 (`e1894dd`),
`Paths` (`2cdaf76`), raport v2 i `conformance.v2` (`9cf8b13`) i ten zapis. Brama zielona na każdym commicie,
także na tych z samym `PLAN.md`. Silnik 816 → 879 testów, sandbox 47, web 31; `check` bez zmian (0/4/19,
0/8/16) — fikstury v2 są dla `check` niewidoczne, dopóki `check` nie czyta v2 (E7c-2).

**Odbiór E7c-1, jak sprawdzony:**
- *Te same scenariusze dają te same liczby werdyktów* — `test/conformance/promise_test.exs` (scenariusze
  `trace_test`), `deadline_test.exs` (scenariusze `run_test`) i pierwszy blok `report_v2_test.exs` (przebiegi,
  werdykty obietnicy, potwierdzony termin, deklaracje, zdania reguły) idą raz na kształt v1 i raz na port v2,
  z tymi samymi asercjami. Testy v1 są nietknięte.
- *„Jeszcze nie” przechodzi w „nigdy” dopiero po opróżnieniu kolejki* — `report_v2_test`, „not yet is not
  never”: krok odmowy przez politykę `:at_least_once` jest w `in_flight` (lag 1), nie w `untraversed`; po
  `drain` znika z obu.
- *D7* — `event_runs_test` (zdarzenie w przebiegu domowym i w przebiegu oddziału) i `deadline_test`
  („measures a run made of another contract's events”). Wstecz: bez typów z `include` pada ten drugi i tylko on.

**Ustalenia.**
1. **Fikstury przetłumaczone obok, nie zastąpione** — jak `UniversalityGate.Next` w E4: `ProcessShapes.Next.
   Promised`, `Timed`, `Bare` w wymyślonej `ProcessShapes.Domain`, a `ProcessShapes.Seed` pisze ten sam
   scenariusz w oba kształty. Zastąpienie przepisałoby siedem plików testów v1 i zostawiło czytelników v1 bez
   testu, choć TaxVision w sandboxie dalej ich używa. v1 i `Seed` znikają w E11. Mechanika, rozstrzygnięta
   przeze mnie.
2. **Gałąź odmowy to w v2 trzy kroki, nie jedna ścieżka.** Komenda jest węzłem, więc „50 przebiegów → jedna
   linia raportu” z `conformance_test` ma w v2 postać „50 przebiegów → te same trzy kroki, każdy raz”: kroki
   nikomu niezrobione są raportowane raz, niezależnie od liczby przebiegów. To mój odczyt kryterium; liczby
   werdyktów (obietnice, termin, przebiegi) są równe dosłownie.
3. **W testach hosta pierwsze `drain/1` to wdrożenie** — konsekwencja decyzji o starcie polityki: polityka
   zarejestrowana po zdarzeniu nie reaguje na nie. Dwa testy polityki w `subscription_test` robią `drain` przed
   dispatchem; linia w CHANGELOG i akapit w `Testing`.
4. **Magazyn pisze przebiegi razem ze zdarzeniem**, nie dispatcher po dopisie: żadna ścieżka dopisu (dispatch,
   `record/3`, timer, pomocnik testów, emiter v1) nie może zapomnieć wiersza. Zdarzenie v1 też dostaje przebieg
   domowy; czytelnicy v1 tabeli nie czytają. Wspólna nazwa procesu v1 i v2 (`handling`) niczego nie miesza, bo
   czytelnik v2 filtruje typami `"<proces>.<zdarzenie>"` — test kontrolny w `promise_test`.
5. **Niezbudowane: uzupełnienie `_event_runs` dla starych zdarzeń**, gdy kontrakt zaczyna włączać ich typ
   (v2 §13 mówi „rebuildable”). Wraca przy ClinicalVisit (E9), pierwszym kontrakcie, który włącza cudze
   zdarzenia z historią.
6. **Efekt nie zostawia śladu w logu, kiedy działa**, więc jego krok ma `runs: nil`: nigdy „niezrobiony”, tylko
   w toku (job czeka) albo padający (job `discarded`).
7. **Padająca komenda trafia do kroku przez `failed_in`**: etap konsumenta — do kroków tego konsumenta; decyzja,
   fold albo read model — do każdego kroku, który komenda emituje (której z nich by dokonała, nie wiadomo).
   Polityka z dwoma zdarzeniami wejściowymi dostaje porażkę na obu krokach.
8. **Lag liczony tylko dla konsumenta z wierszem subskrypcji**: bez wiersza konsument nie jest wdrożony i nic
   na niego nie czeka.
9. **Dryf v2** to zdarzenie wdrożonej wersji, którego żadna zadeklarowana komenda nie emituje, także zapisane
   obok dispatchu (`from: nil`, „written outside dispatch”). Historia pod starszą wersją nie jest dryfem.
10. **Do E7c-2, bo stoi na wdrożeniach v2**: boot nie zapisuje wdrożeń kontraktów v2, więc raport mówi „nothing
    has happened under this version yet”, a granica deklaracji obietnicy (`promise:<nazwa>`) jest zawsze `nil`.
    Tam też `Registry` i `check`, które kontraktów v2 nie widzą.

**Przegląd przed PR (26 września, `/code-review high origin/main..HEAD`).** Dziesięć znalezisk; sześć poprawionych
z testem, który na kodzie sprzed poprawki pada jako jedyny, jedno poprawione bez zmiany zachowania, jedno
porządkowe bez testu, dwa pominięte, jedno błędne:
1. **Krok za czekającym krokiem był „niezrobiony”** — przy odmowie w lagu polityki raport wypisywał „Notify a
   refusal → Refusal notified” jako „never carried out”, wbrew odbiorowi E7c. **Poprawione** w `71610d0`: krok,
   do którego początku prowadzi krok czekający (także dalej w łańcuchu), nie jest niezrobiony.
2. Lag kroku timera liczył odpalenia wszystkich timerów wszystkich process managerów — **poprawione** w `6bb69ff`.
3. Padające komendy ograniczane okresem po `recorded_at` (zegar bazy), reszta po `occurred_at` (`Clock`) —
   **pominięte**: `_commands` nie ma innej chwili; na produkcji zegar dispatchu to zegar ścienny, a różnica
   dotyczy tylko wstrzykniętego zegara. Wraca, jeśli wiersz komendy dostanie `occurred_at`.
4. Grupowanie reakcji po polu `timer` z payloadu każdego zdarzenia zlewało grupy — **poprawione** w `aad9f81`.
5. Lag to jedno zapytanie na konsumenta i typ — **pominięte**, ta sama kategoria co ustalenie 12 E6: wraca przy
   pomiarze.
6. `LIKE` na nazwie kontraktu z `_` jako wieloznacznikiem — **poprawione** w `73d7fb7` (dokładne klucze), bez testu,
   bo żaden moduł w repozytorium nie ma `_` w nazwie.
7. `Implementations.stored/2` powielał `Model.declaring/2` — **poprawione** w `3bb7eae`, bez zmiany zachowania.
8. Raport liczy przebiegi osobno od `of_runs` kroków — **błędne**: proces bez kroków (`DispatchRig.Branch`) ma
   przebiegi, których żaden krok nie niesie.
9. `Paths.declared/1` oddawał klucze wewnętrzne wbrew dokumentacji — **poprawione** w `c4bc294`.
10. Kroki w toku drukowane pod „never carried out”, a przy pustej liście po „All agreed steps were carried
    out” — **poprawione** w `ce7c002` dla procesu v2 (własny nagłówek „Agreed steps in progress:”); układ v1 bez
    zmian, więc bajty raportu v1 się nie ruszają.

Silnik 879 → 881 testów, sandbox 47, web 31; `check` bez zmian (0/4/19, 0/8/16).

### E7c-2 — co wyszło (26 września)

**Stan.** Na `dsl-v2/e7c2-outputs` od `dsl-v2/e7c-conformance` (PR #16), niewypchnięte: wdrożenia v2 z wersją
okablowania (`f92e528`), task raportu (`39febdc`), graf v2 (`42d283c`), `check` na v2 (`200a1fa`), pokrycie
scenariuszy i `wiring` w raporcie (`33bac1e`), webowy `CaseHandling` v2 i ekrany (`3fbdfa2`), `min_position`
(`d3463ae`), poprawki ADR (`1120c8d`) i ten zapis. Brama zielona na każdym commicie. Silnik 881 → 904 testy,
sandbox 47, web 31 → 32; `check` sandboxa 0/4/19 → **0/5/19**, silnika 0/8/16 → **0/14/17** (niżej).

**Delta `check`, każda linia wyjaśniona.** Sandbox: +1 ostrzeżenie — `Rehmed.Contracts.VisitSettlement` nie ma
`accountable`; to linia, która wypadła z wyjścia przy porcie w E6. Silnik: +6 ostrzeżeń i +1 informacja —
`ProcessShapes.Next.Promised` i `Next.Bare` bez `accountable` oraz niepotwierdzone terminy `Next.Promised` i
`UniversalityGate.Next.TreatmentEpisode`, dokładnie jak ich oryginały v1; `DispatchRig.Ledger` i `Branch` bez
`accountable`; termin `Branch` bez zdarzenia kończącego (informacja). Linie v2 niosą nazwę kontraktu, bo port i
oryginał dawałyby inaczej tę samą linię.

**Pierwszy przebieg sandboxa w dev.** Zrobił go **nie ten skrypt, tylko `mix phx.server`** uruchomiony w tym
worktree przez aplikację Claude o 23:15 (PID 81432, nadal działa): boot zapisał wiersz wdrożenia v2
`VisitSettlement` (`2ae1d0074cbc` / okablowanie `90e7d665ab04`); wierszy subskrypcji i przebiegów nie ma, bo
`VisitSettlement` nie ma konsumentów uporządkowanych, a baza dev nie ma zdarzeń v2. Potem raport i graf
nakładki na tej samej bazie z kodem `main` (worktree `dsl-v2-e7-async-runtime-00f4d5`, `9285de2`) i z E7c-2:
**`graph --overlay --mermaid` bajt w bajt identyczny**, a raport różni się wyłącznie dopisaną sekcją kontraktu
v2 (wersja, okablowanie, zmiana względem wiersza v1, zero przebiegów, cztery scenariusze niezaobserwowane).
Części v1 bez zmiany bajtu. Przed: 12 zdarzeń, 5 wdrożeń; po: tak samo — wiersz v2 zapisał już ten boot.

**Ustalenia.**
1. **`Registry.v2_contracts/0` obok `contracts/0`**, nie w nim: kilkunastu czytelników v1 pyta kontrakt o to, na
   co odpowiada tylko v1. Każde wyjście czyta v2 jawnie; przy cięciu listy się sklejają.
2. **Okablowanie v2 = kroki z `Paths.declared` + moduły implementujące deklaracje.** Kroki już ruszają wersję
   kontraktu, więc tylko wiązanie z modułami mówi coś o kodzie. Obietnica dostaje własny digest przy zapisie
   wdrożenia (`promise:<nazwa>`), bo model digestuje cały proces — granica deklaracji obietnicy działa.
3. **Graf v2**: liczniki na krawędzi, która jest krokiem (emisja albo komenda konsumenta), bo zdarzenie
   docierające do konsumenta, który wydaje dwie komendy, rysowane jest raz; timer rysowany jako process manager →
   timer → komenda, żeby jego licznik nie dzielił krawędzi z reakcjami. Process manager bez `issues:` na
   `starts_on` nie ma krawędzi od zdarzenia — kroki są tylko tam, gdzie coś jest wydawane.
4. **`check` na v2 nie powtarza reguł L2/L3**: tylko to, co kontrakt może legalnie powiedzieć, a czytelnik
   powinien usłyszeć. Kontrakt częściowo zaimplementowany to ostrzeżenie (dispatch resztę odrzuci), wcale —
   informacja (D3). Częściowej implementacji nie da się zbudować w teście (moduł spoza aplikacji nie jest
   skanowany), więc ta gałąź nie ma testu.
5. **Pokrycie scenariuszy** liczy tylko scenariusze wyzwalane komendą: query nie zostawia wiersza. „Wynik bez
   scenariusza” to rozstrzygnięcie komendy (emisje albo niezmiennik), którego żaden jej scenariusz by nie
   dopasował — bez względu na `given`. Okres po `recorded_at`, jak padające komendy (znalezisko 3 z przeglądu
   E7c-1).
6. **Webowy `CaseHandling` zastąpiony portem v2** z dwiema politykami inline; **oryginał v1 zostaje jako
   `Fixtures.V1.CaseHandling` wyłącznie dla AsyncAPI**, które czyta v1 do E10. Oba nazywają proces `:handling`
   (przemianowanie na `:v1_handling` z pierwszej wersji cofnięte po przeglądzie, znalezisko 2). Testy API
   zgodności nazywają kontrakt, bo zarejestrowane są dwa.
7. **`min_position`**: polling wiersza subskrypcji co 25 ms, najdłużej `wait:` (5000 ms), potem
   `{:error, :not_caught_up}`. Read model inline bez wiersza uchodzi za dogoniony. Fikstura `Ledger` dostała
   query `:lines_of` na asynchronicznym `ledger_lines`.
8. **Poprawki ADR z v2 §18 dla E7** są w architecture §9–10 i wyzwalaczu „jedno zdarzenie w dwóch procesach”,
   design-rationale §9–10, technology-notes §4. „Bez zewnętrznego brokera” zostaje prawdą do E12.

**Po merge'u PR #16 i #17 (27 września): nowy punkt odniesienia bazy dev i zasiew v2.** Na polecenie
użytkownika. **Punkt odniesienia porównań bajtów jest teraz poza repozytorium**, w
`~/Projects/ai/eh-os-contract-dev-reference/`: `2026-09-27-przed-zasiewem/` (raport, graf nakładki, `pg_dump` bazy
dev na `main` = `191e47c`, identyczne z przebiegiem E7c-2) i `2026-09-27-po-zasiewie-visit-settlement/` (to samo po
zasiewie, plus graf procesu `visit_settlement`). Zasiew przez dispatch w `MIX_ENV=dev`: sześć wizyt
`VisitSettlement` od 21 do 26 września — pełna płatność, split karta+gotówka, odmowa na niezmienniku (150 z
200 zł), zamknięcie bez płatności, korekta po zamknięciu, wizyta w toku; 17 zdarzeń, 18 wierszy komend, 17
przebiegów. **Sekcje v1 raportu i graf nakładki v1 po zasiewie są bajt w bajt takie jak przed nim.** Sekcja v2:
6 przebiegów, w mocy od 21 września, wszystkie kroki zrobione, 4 z 4 scenariuszy zaobserwowane, cztery wyniki
bez scenariusza (dodanie usługi, korekta, wydanie wizyty, płatność).

**Port sandboxa w dev: 4010, i taski nie zajmują portu.** Port 4000 na tej maszynie trzyma inna aplikacja
Phoenix (`/private/tmp/eh-os-test`, od 14 września), więc `autoPort` z `launch.json` losował przy każdym starcie
inny port, a pod `localhost:4000` odpowiadał tamten projekt. Poza tym `server: true` w `config/dev.exs` sprawiał,
że każdy task startujący aplikację stawiał serwer: `mix eh_os_contract.report` przy działającym dashboardzie na tym
samym porcie padał z `:eaddrinuse` (sprawdzone). `server: true` usunięty — `mix phx.server` serwuje i bez niego
(sprawdzone na 4011) — a domyślny port sandboxa to 4010 w `dev.exs`, `launch.json` i README.

**Kształt deklarowany procesu v2** (luka, którą użytkownik zobaczył na dashboardzie 27 września). Po E7c ekran
grafu rysował dla procesu v2 w obu panelach graf kroków, a obrazka dla właściciela procesu — etapy jako pasy,
zakończenia, obietnice z oknem — v2 nie miał; ekran otwierał się przy tym na procesie v1 (kolejność etykiet), więc
wyglądał jak sprzed E7. `Graph.declared_to_mermaid/2` rysuje teraz proces v2 tymi samymi funkcjami co v1 (wyjście
v1 bajt w bajt identyczne dla trzech procesów sandboxa), task `graph --process` rysuje go bez `--overlay`, a ekran
otwiera się na pierwszym procesie v2.

**Przegląd przed PR (26 września, `/code-review high dsl-v2/e7c-conformance..HEAD`).** Osiem znalezisk; sześć
poprawionych, jedno pominięte, jedno błędne:
1. i 7. **`check` nie liczył query** wśród tego, co wymaga implementacji, a gałąź „zaimplementowany w części”
   nie miała testu — **poprawione** w `051ad57` z fiksturą `DispatchRig.Unfinished` (zaimplementowany unit, bez
   read modelu i query); `check` silnika 0/14/17 → 0/15/17, ta jedna linia to cel fikstury.
2. **Wybór procesu na ekranie grafu po samej nazwie** — v2 i jego oryginał v1 o tej samej nazwie procesu
   zasłaniały się nawzajem; przemianowanie na `:v1_handling` to ukrywało. **Poprawione** w `c0f7de5`: klucz to
   kontrakt i nazwa.
3. **Digest obietnicy z całej mapy**, także `unverified` i `source` — potwierdzenie obietnicy rysowałoby
   granicę deklaracji i wyjmowało wcześniejsze przebiegi z werdyktu. **Poprawione** w `b820acd`: digest z
   `from`, `eventually`, `within`, `or_else`.
4. Skan wszystkich jobów Obana na kontrakt — **poprawione** w `986f00c` (klucze konsumentów kontraktu), bez
   zmiany zachowania.
5. `Coverage` padałby na scenariuszu z `given` spoza magazynu — **pominięte**: osiągalne dopiero przez DCB
   konsultujący zdarzenie odebrane z innej aplikacji (E9); tam do obsłużenia.
6. Krawędź process manager → timer rysowana jako dostawa „async” — **poprawione** w `116f7c0` („sets”, bez
   grotu).
8. `wiring` powtarza dane z `deployment` — **błędne**: sekcja jest kształtem, który użytkownik zatwierdził przed
   E7c.

Silnik 904 → 906, web 32; `check` sandboxa 0/5/19, silnika 0/15/17.

### EA1 — co wyszło (27 września)

**Stan.** Na `dsl-v2/ea-verify`: zapis rozstrzygnięć (`d538ec3`) i pakiet jednym commitem (`5d35927`) — nowy
katalog, trzy linie bramy (`sandbox/mix.exs`, `ci.yml`) i tabele katalogów w `CLAUDE.md` i `README.md`, więc
dodawanie bez przemianowań. Brama zielona na każdym commicie. Silnik, web i sandbox bez zmian (908 / 32 / 47,
`check` bez delty); pakiet auth 29 testów. `mix.exs` pakietu: `0.1.0-dev`, zależności `joken ~> 2.7` (2.7.0,
JOSE 1.11.12), `req ~> 0.7` (0.7.4), `ecto_sql`/`postgrex` w wersjach silnika, `plug` tylko w testach.

**Co jest:** `EhOsContract.Auth.verify/1,2`, dziecko `EhOsContract.Auth` (`child_spec/1` pada przy starcie bez
`audience` albo bez `issuer`/`jwks_url`), `EhOsContract.Auth.Keys`, `EhOsContract.Auth.Migrations` (V01: tabela
`eh_os_contract_auth_keys`, wersja w komentarzu tej tabeli). Odbiór D-34 — klucz usunięty z JWKS odrzucony po
odświeżeniu, nieudane pobranie (EHOS leży, 503, zestaw bez klucza Ed25519) nie zmienia niczego, nieznany `kid`
pobiera najwyżej raz na 30 s z kontrolą po upływie interwału, pierwszy start bez EHOS-a to `:no_keys` z kontrolą
po powrocie, restart bez EHOS-a działa z tabeli — oraz `EdDSA`, obce `aud` (także poprawne w liście), obcy `iss`,
brak `exp`, zegar `Clock.at/2`, zmieniony claim, obcy klucz pod znanym `kid`, rotacja z dwoma kluczami.

**Ustalenia:**
1. **Test `EdDSA` nie pilnuje sprawdzenia nagłówka.** Mutacja usuwająca warunek `alg` w `verify` zostawia go
   zielonym, bo Joken sam nie weryfikuje tokenu `EdDSA` signerem `Ed25519`. Dwie warstwy odmawiają; test przypina
   wynik i mówi to w komentarzu. Pozostałe siedem mutacji (bez `exp`, `aud` w liście, bez limitu 30 s, bez
   wczytania tabeli, pusty zestaw jako sukces, klucz prywatny w tabeli, bez usuwania z pamięci) — każda wywraca
   dokładnie swój test.
2. **Kształt tokenu spoza formy EHOS-a to `:bad_signature`**, nie siódmy powód: nie-JWT, brak `kid`, `sub` nie
   string, `cap` nie lista stringów. Sześć powodów z D-34 zostaje zbiorem zamkniętym.
3. **Klucz jest znany po odcisku liczonym u siebie**, nigdy po `kid` wpisanym w JWKS obok klucza; z JWKS trafiają
   do tabeli tylko `kty`, `crv`, `x` — wpis z częścią prywatną jej nie zapisze (test).
4. **Zawieszony EHOS nie wywraca wołającego.** Pobieranie ma domyślnie 2 s na połączenie i 3 s na odpowiedź, bez
   ponowień; wywołanie przy nieznanym `kid` czeka do 10 s i przy przekroczeniu odmawia z tym, co jest w pamięci.
   Znalezione przeglądem własnym przed commitem (domyślny timeout Req 15 s > 5 s `GenServer.call`). **Bez testu**
   — wymagałby 10 s czekania albo konfigurowalnego timeoutu wywołania; do decyzji przy przeglądzie przed PR.
5. **Skąd klucze i co skonfigurować przy integracji** — na prośbę użytkownika w `README.md` pakietu (sekcja
   „Where the keys come from, and what to configure at integration”): para kluczy w Secrecie z charta EHOS-a,
   JWKS pod `/.well-known/jwks.json`, `kid` jako odcisk, **certyfikat TLS adresu EHOS-a jako kotwica zaufania**
   (wewnętrzne CA przez `req_options` dziecka), rotacja ręczna po stronie EHOS-a. `docs/adr/identity-seam.md`
   odsyła tam notką z datą.
6. **Test migracji w dół nie powstał**: zestaw migruje się `up/0` jak konsument, `down/1` jest nieprzetestowane.
   Silnik testuje migracje na `CommitRepo`; pakiet auth nie ma drugiego repo i przy jednej tabeli nie było warto.
7. Health check dla `:no_keys` (D-34: „says so in its log and its health check”) — **`EhOsContract.Auth.ready?/0`,
   na prośbę użytkownika** (`56d6910`): `false`, gdy nie ma żadnego klucza albo proces kluczy nie działa; nigdy nie
   pobiera i nie rzuca.

**`/code-review` (high) na `main...dsl-v2/ea-verify`, na polecenie użytkownika — siedem uwag, wszystkie
poprawione:**
1. **Jeden zepsuty wpis JWKS zabijał proces kluczy w pętli** — `x`, które nie jest kluczem Ed25519, rzucało w
   `JOSE.JWK.from_map/1` w procesie; restart pobierał to samo i nadzorca w końcu kładł hosta. Teraz `x` musi mieć
   32 bajty, zły wpis kosztuje tylko siebie, a każdy wyjątek przy pobieraniu to nieudane pobranie, nie crash.
2. **`child_spec` przyjmował sam `jwks_url`, a `verify` i tak wymagał `issuer`** — każde żądanie rzucało
   `KeyError`. `issuer` jest teraz wymagany przy starcie.
3. **Proces kluczy w restarcie wywracał wołającego** (brak tabeli → `ArgumentError`, `:noproc` z wywołania).
   Teraz to odmowa `:no_keys`, jak w `ready?/0`; zniknął komunikat „dodaj do drzewa nadzoru” — tę rolę przejmuje
   `ready?/0` i log przy starcie.
4. `refresh/1` miał 5 s na wywołanie przy pobieraniu do 5 s i zapisie — teraz 10 s, jak przy nieznanym `kid`.
5. **Klucz parsowany przy każdym credentialu** — w pamięci jest teraz gotowy `Joken.Signer`, liczony raz na
   pobranie.
6. **Nieznany `kid` zawsze szedł przez proces**, także w oknie 30 s, więc zalew podrobionych `kid` kolejkował się
   za trwającym pobraniem. Chwila następnego dozwolonego pobrania jest w tabeli ETS i wołający bez niej nie woła
   procesu; proces sprawdza jeszcze raz u siebie.
7. **`actor/1` łapał każdy wyjątek jako `:bad_signature`** — teraz kształty `sub`/`cap` w strażniku i tylko
   `ArgumentError` z `Actor.credential/3`. Własne sprawdzenie `scp` wyleciało po mutacji: `Actor.credential/3`
   odrzuca je sam.
Nowe testy sprawdzone wstecz (cofnięcie każdej z poprawek 1, 2, 3 i 6 wywraca dokładnie swój test); 4, 5 i 7 bez
osobnego testu — 5 i 7 nie zmieniają zachowania, 4 wymagałby wolnego EHOS-a. Pakiet 30 → 32 testy.

### EA2 — co wyszło (27 września)

**Stan.** Na `dsl-v2/ea-authorize` od `c42896d`: pakiet (`a8dd701`) i sandbox z dokumentami (`61ae0ef`). Brama zielona
na obu. Silnik i web bez zmian (908 / 32), `check` bez delty (0/5/19, 0/15/17). Sandbox 47 → 53, pakiet auth 32 → 41.

**Co jest:** `EhOsContract.Auth.authorize/2` (behaviour `EhOsContract.Authorizer`: samo `check/2` i wiersz w
`eh_os_contract_auth_decisions`, migracja pakietu V02), `EhOsContract.Auth.Plug`, `EhOsContract.Auth.Testing`
(`credential/3,4`, `assert_every_entry_refuses/2,3`), `EhOsContract.Auth.Keys.pin/2`. Sandbox: `authorizer:
EhOsContract.Auth`, `issuer: "https://ehos.invalid"` (RFC 6761 — nigdy się nie rozwiąże, więc prawdziwe credentiale
dostają `:no_keys`), `audience: "rehmed/sandbox"`, dziecko po `EhOsContract`, migracja, komendy `VisitSettlement` pod
`/api/rehmed` za Plugiem bearer. `plug` przeszedł z zależności testowej do zwykłej.

**Odbiór EA, jak sprawdzony:**
- testy D-34 i odrzucenia `alg`/`aud`/`iss` — EA1;
- uprawnienie ze `scope` bez wpisu w `scp` odrzucone — `authorize_test` (`:unscoped_grant` z wierszem, wartość i
  wymiar w wierszu); w sandboxie nie ma query ze `scope`, więc przez HTTP niesprawdzone;
- odmowa ma wiersz, a log i `_commands` nie dostają niczego — `assert_every_entry_refuses` dla pięciu komend
  `VisitSettlement` przez HTTP;
- pomocnik pada na komendzie bez mapowania (i na kluczu spoza kontraktu, i na wejściu, które nie pyta) —
  kontrola: credential z uprawnieniem przechodzi (200, zdarzenie z `actor:u-specjalistka`) i ma wiersz `allowed`.
Wstecz: bez Pluga bearer w routerze i z domyślnym `Authorizer` padają pomocnik i kontrola pozytywna; w pakiecie
padają swoje testy po wyrzuceniu przypiętych kluczy przy odświeżeniu, wartości `scope`, samego wiersza i
niewrażliwości schematu `Bearer` na wielkość liter.

**Ustalenia:**
1. **Klucz testowy przez `Keys.pin/2`, nie przez tabelę ani konfigurację.** Pomocnik wstawia połówkę publiczną do
   pamięci działającego procesu kluczy hosta; przeżywa odświeżenia, do tabeli nie trafia, znika z restartem. To
   funkcja publiczna, więc każdy kod w tej samej VM może dodać ufany klucz — tak samo, jak może zbudować
   `Actor.credential/3` z pominięciem weryfikacji; opisane w dokumentacji `pin/2`.
2. **Pomocnik liczy na tabelach silnika w całości** (`eh_os_contract_events`, `eh_os_contract_commands` przed i po),
   więc działa tylko w teście z własnym połączeniem sandboxa — jak każdy test hosta, który dispatchuje.
3. **`EhOsContract.Plug` dekodował treść przed autoryzacją** — wywołujący bez uprawnienia, który wysłał złe pola,
   dostawał 422 z nazwami pól, a nie 403, i nie było wiersza decyzji. **Poprawione na polecenie użytkownika**, w
   silniku: gdy żądanie pada przed dispatchem albo query (treść nie jest obiektem, pola się nie dekodują,
   `x-correlation-id` nie jest UUID), Plug pyta `Authorizer` tym samym zapytaniem przez
   `Dispatcher.permit_undecoded/5` (`@doc false`), z wartością `scope` taką, jak przyszła. Odmowa → 403, zgoda →
   dotychczasowy 400/422; każde żądanie to dalej dokładnie jedno pytanie (test w `plug_test` silnika z
   `Authorizer`, który liczy pytania; w sandboxie wiersz `refused` i, jako kontrola, 422 z jednym `allowed`).
   Skutek widoczny: query ze `scope` bez parametru to 403 `outside_scope`, jak w `query/3`, nie 422 — linia w
   `CHANGELOG.md` silnika. Wstecz: stary `plug.ex` wywraca trzy nowe testy silnika.
4. **Sandbox w dev loguje przy starcie brak kluczy** (`ehos.invalid`) i co 5 minut nieudane pobranie, na poziomie
   `warning`/`error`. Zamierzone: tak wygląda aplikacja bez EHOS-a.
5. Nazwa kontraktu w wierszu to `inspect(module)`, jak w `_commands`.

**`/code-review` (high) na `dsl-v2/ea-verify...dsl-v2/ea-authorize`, na polecenie użytkownika — osiem uwag:**
1. **`pin` ze złym kluczem rzucał w procesie kluczy** i zabierał z nim tabelę ze wszystkimi kluczami — poprawione:
   sprawdzenie w wołającym (test; mutacja przenosząca je z powrotem do procesu go wywraca).
2. **`Keys.pin/2` jest publiczne i działa w każdym środowisku** — każdy kod w VM może dodać ufany klucz.
   **Do użytkownika**: bramka w konfiguracji (np. `config :eh_os_contract_auth, pin_keys: true` tylko w teście) to
   kształt widoczny dla hosta.
3. `credential/3` bez procesu kluczy kończył się gołym `:noproc` — teraz `ArgumentError` mówiący, co uruchomić (test).
4. **Plug sięga do `Dispatcher.permit_undecoded/5` (`@doc false`)**, bo dekodowanie jest w Plugu, a autoryzacja w
   dispatchu; drugie drzwi, które same dekodują, musiałyby o tym wiedzieć. **Do użytkownika**: wejście silnika
   przyjmujące surowe dane (autoryzacja → dekodowanie → dispatch w jednym miejscu) to nowe publiczne API.
5. Kształt zapytania o `scope` był budowany w dwóch miejscach — teraz jedno, `scope_request/2` w dispatcherze.
6. `Codec.values/1` liczone dwa razy na żądanie — teraz raz.
7. `EhOsContract.Auth.Plug.init/1` po cichu gubił nieznane opcje (literówka w `audience`) — teraz rzuca (test).
8. Dev bez migracji pada przy dispatchu z credentialem — **bez zmian**, opisane wyżej w „Stanie repozytorium”.
Poprawki 1, 3 i 7 sprawdzone wstecz. Pakiet auth 41 → 44.

**`engineering:code-review` (bezpieczeństwo i wydajność) na `main...dsl-v2/ea-authorize`, na polecenie
użytkownika — dziesięć uwag, wszystkie poprawione** („popraw wszystko”; przy 3 i 4 asystent wziął domyślne):
1. **`http://` jako `issuer`/`jwks_url` był przyjmowany** — klucze otwartym tekstem, podmienialne po drodze. Start
   pada, jeśli adres nie jest `https` (`http` tylko dla `localhost`).
2. **Req domyślnie idzie za 10 przekierowaniami** (sprawdzone w `req/lib/req/steps.ex`) — odpowiedź 302 na inny host
   przenosiła źródło zaufania. `redirect: false`; przekierowanie to nieudane pobranie.
3. **`Keys.pin/2` działał wszędzie** — teraz tylko przy `config :eh_os_contract_auth, pin_keys: true` (pakiet i
   `sandbox/config/test.exs`); gdzie indziej rzuca. Domyślne asystenta, kształt dla hosta — do potwierdzenia.
4. **Brak górnej granicy życia credentiala** — `exp` dalej niż 15 min (10 z D-33 i 5 na rozjazd zegarów) to
   `:bad_signature`. Domyślne asystenta — do potwierdzenia.
5. **Odpowiedź JWKS czytana w całości** — powyżej 64 KB (czytanie przerwane w `into:`) albo 16 kluczy to nieudane
   pobranie.
6. **`scope_value` może kiedyś być daną osobową** poza crypto-shreddingiem — bramka dopisana do opisu E8.
7. **Synchroniczny INSERT audytu na każde żądanie**, także query — wymóg D-34, koszt opisany w `README.md` pakietu.
8. **Tabela decyzji rośnie bez końca** — sekcja o retencji w `README.md` (decyzja hosta, przykład `DELETE`).
9. **Nagłówek `crit` ignorowany** (RFC 7515 każe odrzucić) — `:bad_signature`.
10. `verify/2` czytał całą konfigurację aplikacji na każdy credential — dwa `fetch_env`.
**Potwierdzone przez użytkownika 27 września, przed E8** — obie domyślne asystenta zostają:
- **`pin_keys: true` zostaje warunkiem `Keys.pin/2`.** Konfiguracja zamiast `Mix.env()`, bo w release'ie `Mix` nie
  istnieje. *Odrzucone:* (a) bez bramki, tylko ostrzeżenie w dokumentacji (stan sprzed przeglądu) — każdy kod w VM
  może dopisać ufany klucz; (b) przypinanie tylko w `EhOsContract.Auth.Testing` kompilowanym w `:test` —
  mocniejsze, ale zależność kompilowałaby się u hosta inaczej w teście niż na produkcji.
- **Limit życia credentiala zostaje stały: 15 minut** (10 z D-33 i 5 na rozjazd zegarów), dalej `:bad_signature`.
  Jeśli EHOS zmieni czas życia, zmienia się pakiet. *Odrzucone:* (a) konfigurowalny `max_lifetime` z domyślnymi
  15 min — elastyczniej, ale host może też limit poluzować; (b) bez limitu, pełne zaufanie do `exp` z EHOS-a.

Poprawki 1, 2, 4, 5, 9 na `dsl-v2/ea-verify` (`8c28221`), bo to kod EA1, scalone do EA2 (`f286f3a`); 3, 6, 7, 8 na
EA2. Każda z 1–5 i 9 sprawdzona wstecz; przy 5 pierwsza wersja testu przeżyła mutację (za duża odpowiedź nie miała
klucza, więc i tak była nieudana) — poprawiona, żeby niosła klucz. Pakiet auth 44 → 51.

**Poprawka 28 września — `:connect_options` hosta scalane, nie podmieniane.** Znalezione przy przeglądzie
testu zamykającego Stage 4 w `eh-os` (`test/apps/ledger/lib/ledger/application.ex` powtarzał `timeout: 2_000`, żeby
to obejść): `Keys` scalał `:req_options` hosta płytkim `Keyword.merge`, więc przykład z README i moduledocu
`EhOsContract.Auth` (`connect_options: [transport_opts: [cacertfile: …]]`) gubił domyślne `connect_options:
[timeout: 2_000]` i łączenie spadało do 30 s Minta — dłużej niż `@call_timeout` (10 s) procesu kluczy, gdy adres
EHOS-a gubi pakiety, a pobranie wyzwala każdy z nieznanym `kid`. Teraz `:connect_options` scalane klucz po kluczu
(`timeout:` hosta dalej wygrywa), reszta opcji jak dotąd. *Odrzucone:* sam przykład w dokumentacji powtarzający
`timeout: 2_000` z wyjaśnieniem — każdy host musiałby o tym pamiętać, a pułapka zostaje. Test w `keys_test` (adapter
Req zamiast sieci, łapie opcje transportu, które Req oddałby Mintowi); ze starym scalaniem pada. Linia w
`CHANGELOG.md` pakietu.
*Przegląd* (dwa równolegle na `origin/main..HEAD`): poprawione — `connect_options: nil` wywracał każde pobranie
po cichu (`:no_keys`), teraz czytane jak brak opcji (test, sprawdzony wstecz); dokumentacja nazywa drugą drogę
nadpisania timeoutu, `transport_opts: [timeout: …]`, którą Req przepuszcza (test); pomocnik nazwany
`merge_option/3`. Bez zmian — scalanie tylko jeden poziom w głąb: pakiet nie ma domyślnych `transport_opts`.
**Pominięte, sprzed tej zmiany, do użytkownika:** (1) `receive_timeout` ogranicza pojedynczy odczyt, nie całe
pobranie (`request_timeout` Req to `:infinity`), więc EHOS sączący bajt co 2,9 s trzyma proces kluczy bez końca —
komentarz przy `refetch/1` („a fetch is bounded by the request timeouts below”) nie jest prawdziwy; (2) host
może nadpisać `redirect`, `into`, `retry` i `url` — obietnice README („follows no redirect”, limit 64 KB, tylko
`https`) trzymają się, dopóki host ich nie ruszy. Oba zmieniają kształt widoczny dla hosta albo wymagają decyzji.
(1) — osobne zadanie; (2) — „Poprawka 28 września (2)” niżej.

**Poprawka 28 września (2) — `req_options` zastąpione jawną opcją na CA.** Punkt (2) wyżej: host mógł podać
dowolne opcje Req, więc `redirect: true` czy `verify: :verify_none` po cichu zdejmowały gwarancje z README, a
`url:` w opcjach dziecka podmieniało adres po sprawdzeniu `https`. **Decyzja użytkownika 28 września:** pakiet
bierze tylko `cacertfile:`/`cacerts:`; opcje pobrania są jego; `plug:` do testów tylko przy `pin_keys: true`;
nieznana opcja (także stare `req_options:`) wywraca start; `url:` w opcjach dziecka odrzucany, a `https`
sprawdzany też w `Keys.start_link/1`. `eh-os` (`ledger/application.ex`) przechodzi na `cacertfile:`.
*Odrzucone:* (a) biała lista opcji Req z odmową przy starcie — zrobione i zamknięte jako
[PR #37](https://github.com/EmpoweredHouse/eh-os-contract/pull/37): dziesięć rund przeglądów, każda znajdowała
kolejną drogę przez powierzchnię Req/Finch/Mint/`ssl` (stare nazwy opcji, opcje TLS, globalne `config :req` z
wtyczkami, sekrety i różnice parserów w adresie), +666 linii. Błąd leżał w podejściu, nie w liście: bronił przed
hostem, którego konfiguracja jest zaufanym kodem, zamiast zawęzić interfejs, który wystawiał całe Req.
(b) Cicho nakładać opcje pakietu po opcjach hosta — konfiguracja kłamie. (c) Tylko dokumentacja — pułapka zostaje.
Pominięte świadomie: `config :req, default_options` hosta dalej działa pod tym pobraniem — to globalna decyzja
hosta, tym samym kodem, co on sam (zdanie w README). Zła *wartość* CA (`nil` z pustej zmiennej, zła ścieżka) przechodzi
start i wywraca każde pobranie. Przy pierwszym starcie zamyka szczelnie (`ready?/0` false); gdy tabela ma już
klucze, **zostają w mocy bez końca, a sygnałem jest tylko ostrzeżenie w logu** — klucz usunięty z JWKS dalej
weryfikuje (uwaga z przeglądu ostatniego commita). Do zadania z limitem pobrania: brak całkowitego limitu czasu
(`request_timeout` Req to `:infinity`), `refresh/1` bez `catch` i sygnał starego zestawu kluczy. **Znane ograniczenie:** proxy ani certyfikatu klienta (mTLS) nie da się podać; host, który ich
potrzebuje, prosi, i dochodzi jedna nazwana opcja.

**Poprawka 28 września (2) — jeden termin na całe pobranie klucza, 5 s.** Punkt (1) z pominiętych wyżej. Timeouty Req
ograniczają pojedyncze kroki: `receive_timeout` liczy się od nowa przy każdym odczycie, `:ssl.connect` wydaje
timeout połączenia dwa razy (TCP, potem uzgadnianie TLS), a `request_timeout` Finch sprawdza dopiero, gdy odczyt
wróci, i nie obejmuje ani łączenia, ani pobrania połączenia z puli. Teraz `Keys` puszcza żądanie w osobnym
`Task`, czeka `Task.yield/2` 5 s, potem `Task.shutdown(:brutal_kill)`: pobranie, które nie skończyło się w 5 s, jest
nieudanym pobraniem (`{:error, :timeout}`), klucze w mocy zostają. 5 s to połowa `@call_timeout` (10 s), więc
wołający na nieznanym `kid` dostaje odpowiedź, a `connect_options: [timeout: 30_000]` hosta nie wydłuża już
niczego ponad termin. Przy okazji `exit` z wnętrza Req (np. timeout puli Finch) jest nieudanym pobraniem, a nie
wywrotką procesu: wcześniej `rescue` go nie łapał. *Odrzucone:* `request_timeout:` jako domyślna opcja Req —
najgorszy przypadek to termin plus `receive_timeout`, bez łączenia i puli, i działa tylko z adapterem Finch.
**Decyzja użytkownika: termin stały, host go nie zmienia.** Przegrały: opcja `:fetch_timeout` z górną granicą
(start pada `ArgumentError` przy wartości za bliskiej 10 s) i opcja bez granicy — jedyny powód, żeby ją
podnieść, to podejście pod `@call_timeout`, czyli przywrócenie błędu; klucz to kilkaset bajtów. Koszt: test
czeka pełne 5 s. Test w `keys_test` na prawdziwym gniazdzie `127.0.0.1` (nie plug — chodzi o zachowanie Finch):
nagłówki, potem bajt co sekundę, poniżej 3 s `receive_timeout`; start procesu kończy się w 5–6 s, klucz z tabeli
zostaje. Sprawdzony wstecz: bez terminu proces po 10 s dalej wisi. Komentarz przy `refetch/1` poprawiony, linia
w `CHANGELOG.md`, zdanie w README i w `@doc` `start_link/1`. Gałąź na PR #35 (te same linie `keys.ex`).
*Przegląd* (dwa równolegle na `fix/auth-connect-timeout-merge..HEAD`): poprawione — `throw` z pluga albo adaptera
hosta dalej wywracał proces kluczy przez link z taskiem (łapany był tylko `exit`), teraz każdy rodzaj (test na
`exit` i na `throw`, plugiem zamiast przestarzałego adaptera-funkcji; sprawdzony wstecz: przy `catch :exit` pada
tylko test `throw`); `case` na wyniku taska dostał klauzulę `{:exit, _}` (dziś nieosiągalna, bo proces nie łapie
exitów); komentarz przy `catch` mówił odwrotnie, po co jest link; dokumentacja obiecywała, że termin obejmuje całe
pobranie, a `store/2` idzie po nim, poza terminem — sformułowania zawężone do żądania; moduledoc `KeyCase` („no
port is opened”) nieaktualny; górna granica testu 6 s → 8 s (zmierzone 5,003 s, ale wlicza start i odczyt tabeli).
Bez zmian — suma timeoutów kroków (2 s TCP + 2 s TLS + 3 s odczytu) przekracza 5 s: tak ma być, termin jest
granicą; log odróżnia go (`(:timeout)`) od timeoutu kroku (`%Req.TransportError{reason: :timeout}`). Zwolnienie
gniazda i połączenia z puli po zabiciu taska sprawdzone w źródłach Finch/NimblePool (HTTP/1: gniazdo należy do
taska; HTTP/2: pula anuluje strumienie na DOWN). **Pominięte, sprzed tej zmiany, do użytkownika:** (1) `store/2`
i `load/1` idą z domyślnym timeoutem repo (15 s), poza terminem — zablokowana tabela (migracja, `VACUUM FULL`)
trzyma proces dłużej niż `@call_timeout`, a przy starcie każde żądanie z pierwszych sekund czeka i dostaje
`:no_keys`; krótki `timeout:` na wywołaniach repo to osobna decyzja. (2) `refetch_at_most_every` nie ma dolnej
granicy, a `fetched_at` jest stemplowane na starcie pobrania: host z wartością poniżej 5 s dostaje pobrania
jedno za drugim i rosnącą skrzynkę przy atakującym z nieznanymi `kid`. Walidacja przy starcie zmienia kształt
widoczny dla hosta. (3) Cztery testy PR #35 z adapterem-funkcją wypisują ostrzeżenie o przestarzałości Req.

*Odzyskane 1 października.* Ta poprawka nigdy nie trafiła do `main`: PR #36 miał za bazę gałąź PR-a #35
(`fix/auth-connect-timeout-merge`), a zmergowany został o 12:44, dziewięć minut po tym, jak #35 wszedł do `main` —
więc do gałęzi, której nikt już nie mergował (pułapka z `pre-pr-review`: commit na gałęzi zmergowanego PR-a nie
dociera do `main`). Znalezione przy sprzątaniu gałęzi; cztery commity nałożone na `main` od nowa, dopasowane do
opcji z #38 (`plug:` i `url:` w miejsce zniesionego `req_options:`, także w `KeyCase`), na polecenie użytkownika.
Zapis wyżej jest sprzed #38 i zostaje jak był: jego „(2)” powtarza numer poprawki o `req_options` (to trzecia z 28
września), `connect_options` hosta już nie istnieje, „gałąź na PR #35” to stara baza, a pominięte (3) — testy z
adapterem-funkcją — zniknęło razem z `req_options`. Otwarte zostają (*2 października: zamknięte w #71 — „#71 — co
wyszło”*): (1) i (2) wyżej, `refresh/1` bez `catch` i
sygnał starego zestawu kluczy z notki nad nim. *Przegląd odzyskania* (dwa równolegle): gwarancje #38 nietknięte,
wycieku po zabiciu taska brak; poprawione dwa komentarze `keys.ex` (o `:req_options` i o zwalnianym połączeniu, które
dotyczy HTTP/1); pominięte — task jest linkowany, więc sygnał wyjścia z zewnątrz (padający proces pomocniczy pluga
albo adaptera) dalej zabija proces kluczy, a klauzula `{:exit, _}` jest nieosiągalna; `Task.Supervisor.async_nolink`
by to zamknął, dziś nic takiego sygnału nie wysyła.

**Skill `pre-pr-review` odpala od teraz oba przeglądy równolegle** (prośba użytkownika): dwa subagenty w jednej
wiadomości, `code-review high` i `engineering:code-review` z naciskiem na bezpieczeństwo i wydajność, wspólna pula
uwag; plus dwa nowe rodzaje problemów i ostrzeżenie o mutacjach, które stosują się w połowie.

### E8a — co wyszło (27 września)

**Stan.** Na `dsl-v2/e8a-encryption` od `main` (`6aacc53`): decyzje (`39061ee`), F7 (`ba32639`), V05 (`0f81137`),
szyfrowanie (`c8dbf4b`). Brama zielona na każdym. Silnik 911 → 937, sandbox 54, web 32, auth 51; `check` bez delty
(0/5/19, 0/15/17). Niewypchnięte.

**Co jest:** F7 (L2: pole osobowe w stanie process managera; L3: wartość domenowa z polem osobowym w stanie PM albo
jako parametr `scope` query). V05: `eh_os_contract_subject_keys` i `eh_os_contract_erasures` (druga pusta do E8b).
`EhOsContract.Personal` (klucze osób, pieczętowanie i otwieranie), `EhOsContract.Vault` + `Vault.Local`,
`EhOsContract.Erased`, `mix eh_os_contract.rewrap`, sprawdzenie `Vault` przy starcie. `Codec` dostał `encode/4` z
funkcją pieczętującą, `decode/4` z `open:`, `personal?/2`, `subjects/4`. Fikstura `ShreddingRig` (zmyślona):
członek z imieniem, e-mailem i kontaktami, jedno zdarzenie z danymi dwóch osób.

**Odbiór E8 w części E8a, jak sprawdzony:**
- w `payload` nie ma jawnego tekstu pól osobowych — `personal_test` (JSON payloadu bez imienia, e-maila i
  telefonów; `member_id` i pola nieosobowe jawne);
- bez klucza odczyt daje `Erased`, reszta pól bez zmian; kontrola: osoba z kluczem czyta się normalnie — klucze
  usuwane w teście wprost (`erase/3` to E8b);
- bramki odrzucają pole osobowe w stanie PM i w `scope` (klucze, tagi, korelacja i `identity` były od E4).
Wstecz: bez pieczętowania, z brakiem klucza jako błędem, z kluczami czytanymi per zdarzenie, bez sprawdzenia przy
starcie i bez `Erased` w typach pada po teście; bez obu reguł F7 padają oba testy F7.

**Ustalenia:**
1. **Parametr query w ogóle nie przyjmuje `personal:` ani `subject:`**, więc bramka „pole osobowe nie może być
   `scope`” z opisu E8 jest na L2 prawdziwa z konstrukcji. Zostaje przypadek wartości domenowej z polem osobowym —
   to L3. Notka z datą pod v2 §6.
2. **`Vault` dostał kontekst** w `wrap`/`unwrap` (wiersz klucza, `typ|id|wersja`) — zapakowany klucz przeniesiony do
   wiersza innej osoby się nie rozpakuje; KMS przyjmuje to jako encryption context. Do tego `current/0` (dla
   `rewrap`) i `check/0` (dla startu). Notka z datą pod v2 §14.
3. **Które klucze czytać, wynika z deklaracji**: podmiot pola osobowego to wartość pola-rodzeństwa, więc koperta nie
   niesie podmiotu (v2 §14 jej go nie daje). Fold strumienia to jedno zapytanie o klucze niezależnie od długości
   (test liczy zapytania telemetrią); zdarzenie bez pól osobowych nie czyta i nie pisze kluczy.
4. **Konsumenci po transakcji (subskrypcje, efekty, PM) czytają klucze per wiersz**, i to tylko dla wiersza z
   zapieczętowanym polem. v2 §14 mówi „jedno zapytanie na partię”; w runnerze wiersz jest dekodowany w swoim
   `rescue`, więc pobranie kluczy dla całej partii przed pętlą zmienia izolację błędu. Zostawione do pomiaru.
5. **Pole osobowe z `nil` jest zapisywane jako `nil`**, nie pieczętowane: brak wartości nie jest daną osobową.
6. **Zapis `Erased` jest odmawiany** (`ArgumentError` z nazwą pola). Decyzja, która przepisze `Erased` ze stanu do
   nowego zdarzenia, padnie więc w E8a na zapisie; E8b odmówi wcześniej, `:subject_erased`, zanim cokolwiek się
   zakoduje.
7. Pierwszy przebieg bramki dał w `check` silnika 16 ostrzeżeń zamiast 15: fikstura miała proces bez
   `accountable`. Poprawiona fikstura, nie wyjaśniana delta.

**Przegląd przed PR (27 września, na prośbę użytkownika przed E8b)** — skill `pre-pr-review`, dwa przeglądy
równolegle na `main...dsl-v2/e8a-encryption`: `code-review high` (9 uwag) i `engineering:code-review`,
bezpieczeństwo i wydajność (9 uwag). Po połączeniu duplikatów 15. **Dziesięć poprawionych**, każda osobnym
commitem z testem sprawdzonym wstecz (`e783879`..`599ebb4`):
1. `Erased` w wierszu query wywracał odpowiedź HTTP (500) — teraz poza logiem to `null` (**decyzja użytkownika**;
   odrzucone: obiekt `{"$erased": "member"}` — pole raz tekst, raz obiekt; błąd jak dotąd — sprzeczny z typami).
2. Brak klucza czytał się po cichu jako `Erased` — teraz `Erased` tylko dla osoby w `eh_os_contract_erasures`,
   inaczej odczyt pada (częściowe odtworzenie bazy nie zamieni dobrych danych w „usunięte”).
3. Praca z `Vault` (KMS) szła pod globalną blokadą dopisu — `prepare/2` czyta, rozpakowuje i pakuje przed nią,
   pod nią zostaje `INSERT … ON CONFLICT DO NOTHING` (oba przeglądy).
4. `Map.fetch!` w pieczętowaniu wkleiłby do wyjątku wszystkie klucze dispatchu, `Jason.encode!` — wartość
   osobową; teraz komunikat nazywa pole.
5. Jawny tekst w polu osobowym przy `open:` czytał się normalnie, a koperta bez `open:` przy wartości o polach
   opcjonalnych dekodowała się pusto — oba „nie pasuje” (oba przeglądy).
6. Fold po przejściu na partię wypadł spod `stage("evolve")` — `failed_in` wróciło do „evolve”.
7. `rewrap` z `SKIP LOCKED` mógł zgłosić sukces, gdy równoległy przebieg trzymał klucze — liczy pozostałe i pada.
8. `publish` wartości domenowej z polem osobowym w środku i pole `personal:` typu, który sam niesie dane osobowe
   (zapieczętowane cudzym kluczem) — reguły L3 (D11, F5) i reguła domeny (F5), jeden predykat
   `Codec.personal_type?/2` zamiast kopii w F7.
9. Zapakowane klucze w logu zapytań Ecto (`:debug`) — `log: false` na `INSERT` i `UPDATE` kluczy.
10. `@spec` w `Vault.Local`.

**Do E8b** (prawdziwe, zamyka je odmowa `:subject_erased`): po ręcznym usunięciu kluczy następny zapis tworzy
nowy klucz w wersji 1, a stare szyfrogramy przestają się otwierać; `problems/3` przyjmuje `Erased`, a zapis go
odmawia. **E8b musi sprawdzać usunięcie pod blokadą, zanim cokolwiek się zapieczętuje** — patch E8b z
rozgrzebanej pracy woła jeszcze stare `for_writing/2` i trzeba go dopasować do `prepare/2`.
**Pominięte:** kopie klucza w kopiach zapasowych, WAL i replikach — decyzja właściciela produktu (v2 §14); w
README silnika zdanie o retencji klucza głównego wobec retencji kopii. Klucze per wiersz w runnerach — ustalenie
4 wyżej, do pomiaru. **Bez zmiany:** AAD bez identyfikatora zdarzenia — podmiana szyfrogramów między zdarzeniami
wymaga UPDATE na logu, który odrzuca trigger.
Po przeglądzie: silnik 937 → 947, `check` bez delty.

### E8b — co wyszło (27 września)

**Stan.** Na `dsl-v2/e8b-erasure`, gałęzi od E8a po przeglądzie (`9455bc2`): usuwanie (`d014010`). Brama zielona.
Silnik 947 → 959, sandbox 54, web 32, auth 51; `check` bez delty (0/5/19, 0/15/17). Niewypchnięte. Praca przerwana
na przegląd E8a (prośba użytkownika) poszła jako patch w scratchpadzie, bez wspólnego stasha; nałożona na nową
głowę E8a z trzema konfliktami, rozwiązanymi na rzecz poprawek z przeglądu.

**Co jest:** `EhOsContract.erase/3` (`Personal.erase/3`): w jednej transakcji pod blokadą dopisu kasuje klucze osoby,
zapisuje usunięcie, dopisuje `eh_os_contract.subject_erased` (typ i id osoby, nic osobowego; `contract:
"EhOsContract"`, bez strumienia i przebiegu) i woła `forget/2` read modeli w transakcji. Read model po transakcji
dostaje zdarzenie w kolejności, przebudowa je odtwarza. Drugie wywołanie to `:ok` bez zdarzenia. Odmowa
`{:error, :subject_erased}` w dispatchu (bez wiersza `_commands`; `410` w `Plug`). Opcjonalny `forget/2` w
generowanym behaviour read modelu i sprawdzenie przy starcie (`check_forgetting!/1`). `Codec.personal_subjects/2`.
Fikstura `ShreddingRig` dostała dwa read modele (w transakcji i po niej) i tabele w migracji testowej.

**Odbiór E8, jak sprawdzony (E8a i E8b razem):**
- w `payload` nie ma jawnego tekstu pól osobowych — E8a;
- po usunięciu odczyt daje `Erased` (także w liście kontaktów i w polu `previous`), `forget/2` się wykonał w
  transakcji i po niej — `erasure_test`; snapshotów nie ma (decyzja użytkownika, punkt wypada);
- `Conformance.as_data` identyczne przed i po, poza `generated_at` — test złoty w `erasure_test`;
- bramki odrzucają pola osobowe w kluczach — E4 i F7, po przeglądzie E8a także wartość domenowa w środku;
- kontrola: osoba nieusunięta czyta się normalnie, jej komenda przechodzi.
Wstecz: bez odmowy, bez `forget` w transakcji, bez routingu `forget` do runnera, bez filtra typu podmiotu i bez
idempotencji `erase/3` pada po teście.

**Ustalenia:**
1. **Odmowa jest węższa niż „dopis dla osoby”**: dispatch odmawia zdarzenia, które niesie dane osobowe usuniętej
   osoby — tylko wtedy powstałby jej klucz od nowa. Zdarzenie z samym jej identyfikatorem przechodzi, bo proces
   biznesowy może iść dalej (np. anulowanie wizyty). Notka z datą pod v2 §14.
2. **`forget/2` idzie tylko do read modeli z danymi danego typu podmiotu.** Pierwszy przebieg testów wywołał
   `forget(:patient, …)` w read modelu członków — `:patient` deklaruje zmyślona domena `UniversalityGate`, a
   routing znał tylko typ zdarzenia. Konsument niesie teraz `forgets` (typy podmiotów), test regresji jest.
3. **`subject_erased` nie należy do żadnego kontraktu**, więc `Consumer.decode!/1` rozpoznaje go po typie i daje
   `%Erased{}`; czytelnicy zgodności go nie widzą (kontrakt `"EhOsContract"`, bez przebiegu).
4. **Wpięcie `check_forgetting!/1` w `Supervisor` nie ma testu** — sama funkcja ma; test bootu potrzebowałby
   fikstury bez `forget/2`, która wywróciłaby start każdego innego testu bootu.
5. Po przeglądzie E8a sprawdzenie usunięcia siedzi w `Personal.for_writing/2` pod blokadą, po `prepare/2`: klucze
   rozpakowuje się przed blokadą, ale żaden nie zostanie zapisany ani użyty dla osoby usuniętej w międzyczasie.
6. Pomocniki `join/3` w teście kolidowały z importowanym `Ecto.Query.join/3` (błąd kompilacji testu) — nazwy
   `join_member/3`, `rename_member/3`.

**Przegląd przed PR E8b (27 września)** — dwa przeglądy równolegle na `dsl-v2/e8a-encryption...dsl-v2/e8b-erasure`:
`code-review high` (9 uwag) i `engineering:code-review` (8 uwag); po połączeniu 13. **Poprawione** (`6abb069`..`92f2d88`,
testy sprawdzone wstecz, poza refaktorem): polityka albo process manager z odmową `:subject_erased` wywracał
dispatch albo zatrzymywał subskrypcję dla wszystkich — teraz to odpowiedź, jak odrzucenie (oba przeglądy);
`prepare/2` pakował przez `Vault` klucz dla usuniętej osoby (oba); stare `subject_erased` typu, którego żadna domena
już nie deklaruje, wywracało przebudowę (oba); nieimplementowany read model w transakcji blokował każde `erase/3`;
`erase/3` z dwoma odczytami zegara, dekodowaniem własnego wiersza, zapytaniami bez konsumentów i opcją
`correlation_id:` rysującą fałszywą krawędź w grafie (opcja usunięta); podwójne przejście po polach osobowych w
`Codec`. **Dokumentacja**: `forget/2` biegnie pod blokadą dopisu (indeks na identyfikatorze podmiotu); `erase/3`
sięga read modeli skonfigurowanych aplikacji (uwaga obu przeglądów — kontrakt spoza `applications:` jest też poza
rejestrem, raportem i subskrypcjami, więc `erase/3` nie ma jak go znaleźć); `--skip` na usunięciu zostawia kopię,
`--reset` ją zabiera. **Pominięte:** `oban_jobs.errors` może trzymać zdekodowane zdarzenie z wyjątku efektu, do
czasu przycięcia przez Obana — kod sprzed E8, poza zakresem, do osobnej pracy. **Do użytkownika:** `erase/3` zwracał
`:ok` także dla identyfikatora, którego nie było — użytkownik zdecydował, że wynik ma mówić, co zastał (pod opisem
E8 w „Etapach”).
Po przeglądzie: silnik 959 → 963, `check` bez delty.

### Po E8 — poprawki (27 września)

Po wystawieniu #21 i #22 użytkownik zapytał o dwie pozycje z przeglądu E8b i zdecydował; #21 i #22 zmergował w
trakcie, więc poprawki poszły na nową gałąź `dsl-v2/e8c-followups` od `main` (commit z wynikiem `erase/3`
przeniesiony z gałęzi E8b cherry-pickiem, to samo drzewo, na którym brama przeszła).
- **`erase/3` mówi, co zastał** — `{:ok, :erased | :no_data | :already_erased}` (decyzja pod opisem E8).
- **Oban nie trzyma wartości z porażki efektu** (decyzja użytkownika: oczyścić u źródła). `EffectJob` podaje Obanowi
  `EffectJob.Failure` (efekt, pozycja zdarzenia, moduł albo rodzaj porażki, stos bez argumentów) zamiast wyjątku,
  wyjścia albo rzutu, a `{:error, reason}` tylko rodzajem. Wyjścia są łapane na czas efektu (`trap_exit`), więc
  awaria podlinkowanego procesu wraca jako wyjście; po powrocie efektu strażnik czyta sygnały: awaria
  podlinkowanego procesu to porażka joba, `:shutdown` jest honorowany. `TimerJob` nie potrzebuje niczego — tylko
  dopisuje `timer_elapsed`; reakcja process managera pada w subskrypcji, która zapisuje moduł.
- **Test wpięcia `check_forgetting!/1` w `Supervisor`** — podmieniony indeks implementacji w `:persistent_term`.

**Przegląd przed PR** (dwa przeglądy równolegle na `origin/main..HEAD`). Bezpieczeństwo: `exit`/`throw` i awaria
podlinkowanego procesu omijały strażnika (**poprawione**, `9cb510c`), ramki stosu funu z argumentami (**poprawione**
tamże), v1 `EhOsContract.Job` trzyma payload w `oban_jobs.args` z założenia (**pominięte**: v1, znika w E11).
Poprawność: to samo `exit`/`throw`; `trap_exit` zamieniało awarię niedoczekanego podlinkowanego procesu w `:ok`
bez ponowienia (**poprawione**, `862f246`); „nigdy błąd” przy `erase/3`, który rzuca dla niezadeklarowanego
podmiotu, i zbyt mocne „nic nie było” przy `:no_data` (**poprawione w dokumentacji**); wiersze `oban_jobs.errors`
sprzed tej wersji (**notka w CHANGELOG**: usunąć albo zostawić pruningowi); test bootu odtwarza klucz indeksu
(**wzmocniony**: sprawdza, że podmieniony indeks jest czytany). **Bez zmiany:** błędy samego silnika też dochodzą
do Obana tylko jako moduł — komunikaty silnika potrafią zawierać `inspect` zwróconej wartości, więc przepuszczanie
ich wprost przywróciłoby wyciek; efekt z imionami „Crash/Bounce/Exit/Throw/Link/Spawn” w wspólnej fiksturze
(zmyślonej, wymaga `Testing.drain/1` przed raportem złotym — dopisane); atom w `{:error, atom}` przechodzi, bo atomy
z danych zewnętrznych byłyby własnym błędem hosta.

### Losy fikstur

| Fikstura | Los |
| --- | --- |
| `ProcessShapes.Promised` (or_else, asynchroniczny koniec, niepotwierdzony deadline; używana przez 7 plików testów) | przetłumaczona w E7c-1 **obok**, jako `ProcessShapes.Next.Promised` (ustalenie 1 w „E7c-1 — co wyszło”); v1 znika w E11 |
| `ProcessShapes.Timed`, `ProcessShapes.Bare` | przetłumaczone w E7c-1 obok, jako `ProcessShapes.Next.Timed` i `Next.Bare`; v1 znika w E11 |
| `UniversalityGate.TreatmentEpisode` z `Eligibility` i fake'iem `PayerRegistry` | przetłumaczona w E4 **obok**, jako `UniversalityGate.Next.TreatmentEpisode` z `UniversalityGate.Domain` (ustalenie 5 w „E4 — co wyszło”); v1 znika, gdy jej osiem plików testów ma następców (E7, najpóźniej E11); `Eligibility.decide/1` jest od E5 deciderem `UniversalityGate.Next.Episode`, a scenariusze fikstury przechodzą na nim (`universality_gate_scenarios_test`); samo `Eligibility` zostaje dla kontraktu v1 do E11; fake zostaje; kontrakt bez implementacji poza tym (D3) |
| `ProcessShapes.Rig` (19 zdarzeń, 14 handlerów) | **rozbity, nie portowany:** krawędź wsteczna i jej trzy kontrole → E7; celowo zepsute handlery → testy wyjścia decydera i polityki w E6; pary cyklu → E6/E7; konkurujące handlery synchroniczne → dwie projekcje inline w E6; `item_noted` → E8; usunięty przy cięciu |
| `CaseHandling` (web) | zastąpiony w E7c-2 portem v2 z dwiema politykami; oryginał v1 jako `Fixtures.V1.CaseHandling` tylko dla AsyncAPI, do E10 |

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
