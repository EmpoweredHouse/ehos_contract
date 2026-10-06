# eh_os_contract — repozytorium biblioteki

To jest repozytorium biblioteki `eh_os_contract`: kontrakt procesu biznesowego i dwie rzeczy na nim
zbudowane — dispatch zdarzeń dla aplikacji sterowanej zdarzeniami i sprawdzanie, czy to, co się stało,
zgadza się z tym, co kontrakt mówi. Inne repozytoria instalują pakiety stąd — z gita, przez `sparse:`,
docelowo z Hexa.

| Katalog | Co |
| --- | --- |
| `packages/eh_os_contract/` | **biblioteka** — DSL kontraktu, dispatch, log, zgodność, `docs/contract.md` |
| `packages/eh_os_contract_web/` | montowalny dashboard |
| `packages/eh_os_contract_auth/` | weryfikacja credentiali EHOS-a, klucze z JWKS (etap EA; skąd klucze i co skonfigurować przy integracji — jego `README.md`) |
| `sandbox/` | host deweloperski `:eh_os_contract_host` i dane testowe: TaxVision, Rehmed, endpoint Phoenixa |
| `docs/` | założenia (`docs/adr/`) i materiał warsztatowy |

Każdy z czterech to osobny projekt Mix. Pakiety budują się i testują same, bez `sandbox/` — i to jest
własność, której pilnujemy: `sandbox/` jest pierwszym konsumentem biblioteki, nie jej częścią.

**Do 23 września pakiet nazywał się `pns` (moduły `PNS.*`, host `:pns_prototype`, tabele `pns_*`).**
Wszystko w kodzie nosi już nową nazwę — `eh_os_contract`, `EhOsContract`, `:eh_os_contract_host`. Stara
zostaje tylko w `docs/adr/` i w historii `PLAN.md`, bo to zapis, nie opis stanu: `PNS.X` tam to dzisiejsze
`EhOsContract.X`.

**`sandbox/` nie jest produktem i nie budujemy w nim aplikacji dla nikogo.** Produktem jest biblioteka;
TaxVision i Rehmed są **danymi testowymi** — materiałem, na którym sprawdzamy, czy DSL się trzyma. Dlatego wnioski z pisania kontraktu idą do `PLAN.md` jako praca nad biblioteką, a nie do
notatek o kliencie, i dlatego kontrakt, którego nie da się napisać, jest **lepszym** wynikiem niż
kontrakt napisany obok materiału.

Od 18 sierpnia dane testowe są z dwóch domen, TaxVision (`sandbox/lib/taxvision/`) i Rehmed
(`sandbox/lib/rehmed/`): każda ma domenę, kontrakty v2 i implementacje, które decydują i reagują. Rehmed miał
być wyłącznie kontraktami — od E6 ma kod, bo bez niego dispatch i raport nie miałyby czego sprawdzać
(poprawka z 29 września, E11d). Trzecia domena medyczna, `UniversalityGate.TreatmentEpisode`,
jest w `packages/eh_os_contract/test/support/`, bo jest **zmyślona** — i sama to o sobie mówi w pierwszej
linii.

## Zanim cokolwiek zmienisz

| Co | Gdzie |
| --- | --- |
| Plan pracy, etapy, kryteria odbioru, **stan** | [`PLAN.md`](PLAN.md) |
| **Etap programu** (dziś DD): zakres, decyzje, przegląd, PR-y — w issue na GitHubie, po angielsku; `PLAN.md` trzyma status i link | skill [`stage-issue`](.claude/skills/stage-issue/SKILL.md) |
| Czym jest to repozytorium, brama, struktura | [`README.md`](README.md) |
| **Jak napisać domenę i kontrakt** — co się nie skompiluje, każda odmowa z kodem | [`packages/eh_os_contract/docs/contract.md`](packages/eh_os_contract/docs/contract.md) |
| Każdy klucz obu DSL-i — typ, wymagany/opcjonalny, domyślna wartość (generowane) | [`packages/eh_os_contract/docs/dsl/`](packages/eh_os_contract/docs/dsl) |
| **Założenia początkowe, 18 decyzji, `§N` z komentarzy w kodzie** | [`docs/adr/architecture.md`](docs/adr/architecture.md) |
| Kształty kodu, schematy, pułapki, biblioteki — `notes §N` z komentarzy | [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) |
| Co każda decyzja pobiła, odrzucone alternatywy | [`docs/adr/design-rationale.md`](docs/adr/design-rationale.md) |
| Kto zaakceptował, zakres komercyjny, stan recenzji | repo kontekstu — **nie tutaj** |

`docs/adr/` to **założenia, nie rekord decyzji.** Nikt ich tutaj nie akceptuje i nie ma po co: decyzja, żeby
tę ideę sprawdzić, już padła, a zadaniem tego repozytorium jest ją zwalidować. Aparat, który do niego
należał — kto recenzował, kto zaakceptował, zakres komercyjny — **został w repo kontekstu** i tam ma zostać.
Trzymany w dwóch miejscach zestarzeje się w jednym z nich.

**Do `~/Projects/ai/empowered-house-context` nie piszemy. Nigdy.** Ani commita, ani gałęzi, ani poprawki w
pliku. Wszystko, co potrzebne, jest tutaj — założenia w `docs/adr/`, stan w `PLAN.md`. Reguła jest z 6
sierpnia i ma powód: pakiet projektowy żył w obu repozytoriach naraz, poprawki jechały na gałąź w tamtym,
podczas gdy autorytatywne pliki były już tutaj, i **przez pół dnia istniały dwie kopie tej samej treści**.
Czytać stamtąd wolno, jeśli o to poprosisz. Pisać — nie.

Z tego wynika, gdzie co poprawiać:

- **Szczegół implementacyjny** — `docs/adr/technology-notes.md`, na miejscu, jednym commitem.
- **Ustalenie z pisania kodu** — do `PLAN.md`, i tylko tam aktualizuje się stan.
- **Założenie, które okazało się nieprawdziwe** — poprawka **z datą** w `docs/adr/`, nie ciche przepisanie.
  Sens tych plików polega na tym, że da się je porównać z tym, co faktycznie wyszło; przepisane pod aktualny
  kod przestają cokolwiek mierzyć.
- Założenia są **świadomie z tyłu**. Gdy `docs/adr/` i `PLAN.md` się różnią, nowszy jest `PLAN.md`.

Założenia myliły się już dwa razy i oba razy wyszło to przy pisaniu kodu. Jeśli mylą się znowu, poprawka
idzie do `docs/adr/` — nie do komentarza obchodzącego problem.

## Czym biblioteka jest, a czym nie

Dwie połowy na jednym modelu — domenie i kontraktach (DSL v2, na wzór ESDM). **Zdarzenia**: `dispatch` pyta,
czy aktor może wydać komendę, sprawdza pola, czyta historię jednostki z logu, pozwala implementacji
zdecydować i dopisuje tylko to, co kontrakt deklaruje; log jest własny silnika (event sourcing). Reakcje —
read modele, polityki, process managery, efekty — jadą w transakcji dispatchu (`:in_transaction`) albo po
niej (`:at_least_once`: subskrypcja z logu, efekt przez Obana wstawionego w tę samą transakcję). **Między
aplikacjami** (E12, od 1 października): zdarzenie wychodzi tylko przez `publish` — relay czyta log i oddaje je
behaviourowi `EhOsContract.Bus` — a przychodzi do inboxu, który bierze tylko polityka (`D12`), nigdy do logu
odbiorcy. Adaptery transportu (JetStream przez `gnat`, relay EHOS-a) są po stronie EHOS-a; biblioteka ma tylko
`Bus.Local` do testów i jednego węzła i od żadnego brokera nie zależy (`docs/adr/architecture.md` §9–10, poprawka
z 1 października). Dane spoza kodu aplikacji — surowe, z credentialem — wchodzą przez `EhOsContract.call/3`, na
którym stoi Plug. **Zgodność** odpowiada na jedno pytanie:

> Czy wdrożony kod robi to, co mówi zdefiniowany proces?

Ekran ma **cztery pytania i ani jednego więcej**: które zadeklarowane ścieżki nigdy nie zostały przejechane,
które przejścia nie są zadeklarowane, które obietnice (`promise`) są łamane, która wersja kontraktu jest
wdrożona i od kiedy.

Wszystko inne ma właściciela: wydajność to GCP, błędy to Datadog, **stan biznesu to aplikacja klienta**.
Kiedy EhOsContract zacznie odpowiadać „która firma nie ma otwartego lipca", staje się drugim, gorszym ekranem
aplikacji klienta. Od v2 biblioteka prowadzi read modele i query klienta — to jego stan, deklarowany w
kontrakcie — ale dashboard go nie pokazuje: pokazuje zgodność.

## Brama

```bash
docker compose up -d && cd sandbox && mix ecto.setup && mix check
```

`mix check` w `sandbox/` to `format --check-formatted`, `compile --force --warnings-as-errors`,
`eh_os_contract.check`, testy sandboxa, a potem `mix check` każdego pakietu osobnym wywołaniem —
`packages/eh_os_contract` (z `eh_os_contract.docs --check` i `eh_os_contract.rules --check`, które pilnują,
że referencja obu DSL-i w jego `docs/dsl/` i katalog reguł w `docs/rules.md` są wygenerowane z kodu, a nie
pisane ręcznie; a `test/docs_test.exs` trzyma przy kodzie przykłady i tabelę odmów w `docs/contract.md`),
`packages/eh_os_contract_web` i `packages/eh_os_contract_auth`. **Musi przechodzić.** Osobne wywołania, nie umbrella — pakiet ma stać sam,
i to jest własność, której pilnujemy. Brama mieszka w `sandbox/`, bo tylko on widzi wszystkie projekty;
każdy pakiet ma też własne `mix check`, które przechodzi bez niego.
`--warnings-as-errors` jest konieczne: `boundary` raportuje naruszenia jako ostrzeżenia, więc bez tego
przełącznika granice są dokumentacją. Postgres słucha na **5433**.

**Nie rurkuj bramy do `tail` przed commitem.** `mix check | tail -4 && git commit` sprawdza kod wyjścia
**`tail`**, który jest zawsze zerowy — więc commit idzie na czerwonym, a Ty widzisz cztery ostatnie linie i
nie widzisz liczby padnięć. Zdarzyło się 6 sierpnia: scommitowane 24 padnięcia. Jeśli musisz skrócić wyjście:

```bash
out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"
```

**`mix run` w `MIX_ENV=test` pisze poza Ecto Sandboxem** (tym od transakcji w testach, nie katalogiem
`sandbox/`). Ecto Sandbox obejmuje testy, nie zadania mixa — więc jedno
`MIX_ENV=test mix run -e '...'` zostawia wiersze **na stałe** w bazie testowej i wywala potem wszystko, co
liczy rekordy. Ta sama pułapka, którą `EhOsContract.Deployment.record!` zastawia przy boocie. Do oglądania czegokolwiek
używaj `MIX_ENV=dev`; jeśli już wpadniesz, ratuje `MIX_ENV=test mix ecto.drop && mix ecto.create &&
mix ecto.migrate`.

**Bazy Postgresa są wspólne dla wszystkich worktree** — nazwy są stałe (`eh_os_contract_host_test`, `…_dev`,
`eh_os_contract_test` …). Z tego dwie pułapki, obie z 4 października:

- **`too_many_connections`.** Brama obok cudzego `phx.server` albo cudzych testów pada na połączeniach, nie na
  kodzie (`AppendLockTest`, `SchemaTest`). Nie ponawiaj w pętli: zatrzymaj własny serwer dev, poczekaj, aż
  `lsof -nP -iTCP:5433 | awk 'NR>1 && $1 ~ /beam/' | wc -l` spadnie poniżej ~10, i puść bramę raz.
- **Migracja z niezmergowanej gałęzi zmienia bazę testową wszystkim.** Brama LC4a usunęła kolumnę, której
  `main` jeszcze używał, i testy na innych gałęziach padły. Po bramie na gałęzi z migracją, której nie ma w
  `main`, przywróć schemat (`psql` w kontenerze: cofnij zmianę i usuń wiersz z `schema_migrations`) albo powiedz
  o tym użytkownikowi.

## Konwencje, które łatwo złamać

- **`boundary`: moduły procesowe są rodzeństwem, nie hierarchią.** Dostęp do cudzych tabel wymaga jawnego
  `deps`. Pierwsza wersja miała `Taxvision` zależny od własnych dzieci i `boundary` słusznie ją odrzucił.
- **Implementacje wskazują kontrakt, nigdy odwrotnie** (`use Kontrakt, aggregate: :x`). Kontrakt, który
  nazywałby swój kod, byłby od niego zależny kompilacyjnie, a kod zależy od kontraktu — każda zmiana kodu
  rekompilowałaby kontrakt i wszystko po nim. Z tego samego powodu kontrakt wskazuje domenę przez `domain:`
  bez zależności kompilacyjnej, a związki między nimi sprawdza kompilator Mixa (L3). Do E11 ta reguła
  brzmiała „reguła wskazuje MFA, nigdy capture” — to był jej kształt w v1.
- **Sprawdzenia w ciele makra, nie w `quote`.** To tworzy zależność kompilacyjną i sprawia, że błąd wskazuje
  implementację, nie bibliotekę.
- **Zdarzenia i komendy to literały.** `emit/1` i `issue/1` biorą literały struktur (I4), bo od tego
  zależy, czy graf statyczny jest faktem, czy heurystyką.
- **Kod jest po angielsku. Bez wyjątków.** Identyfikatory, moduledoki, `@doc`, komentarze, nazwy testów,
  komunikaty błędów kompilacji i stringi wypisywane na wyjście. **Zakres to wszystko w `packages/` i
  `sandbox/`** — `lib/`, `test/` z fikstrami, `config/`, `priv/repo/migrations/`, `mix.exs` — oraz `docs/`.
  `config/`, migracje i `mix.exs` zostały przy pierwszym sprzątaniu pominięte, bo nikt o nich nie pomyślał.
- **Po polsku jest wyłącznie to, co klient czyta zdaniami, i tylko w stringu** — nigdy w komentarzu,
  moduledoku ani nazwie. Konkretnie: `label` i `source` w domenie i kontrakcie, nazwy tasków, temat
  powiadomienia (klucze v1 — opisy `example`, `unavailable_looks_like` — zniknęły w E11). **Od v2 (etap E3,
  25 września) także:** w domenie
  tekst `term`, jego `definition`, `avoid` i tekst tłumaczenia (`translation`), a w kontrakcie v2 prozę
  `where` przy `consults` i opisy scenariuszy — to słownik i przypadki, które właściciel procesu czyta
  zdaniami. Poza tymi miejscami polski string też jest błędem.
  Raport zgodności był tu wcześniej piątym wyjątkiem i **przestał być, 6 sierpnia**: renderer przeniósł się
  do silnika (`EhOsContract.Report`, dawniej `Taxvision.Report` w drzewie klienta) i wypisuje po angielsku — decyzja
  zapisana w `PLAN.md`. Etykiety kontraktu (`label`, `from_label`, `to_label`) nadal wychodzą w raporcie
  dosłownie, w języku, w którym je zadeklarował klient — regułą jest teraz "silnik pisze swoje zdania po
  angielsku", nie "kto czyta cały artefakt".
- **Grep po `[ąćęłńóśźż]` nie wystarcza do sprawdzenia** i to jest zapisane, bo kosztowało jeden fałszywy
  „gotowe". Spora część polszczyzny nie ma diakrytyków — `rejestry` w `registry_check.ex` przeżyło pełne
  przepisanie pliku po pliku właśnie dlatego. Przy sprawdzaniu trzeba przejść też po słowach.
- **Dokumentacja repo robocza — ten plik i historia `PLAN.md` — zostaje po polsku.** To nie jest kod i nie
  jedzie z pakietem; nowe wpisy w `PLAN.md` są od 6 października po angielsku (niżej). **`README.md` jest wyjątkiem od 21 sierpnia** — biblioteka ma zostać
  upubliczniona, więc `README.md` jest teraz po angielsku, po tej samej stronie granicy co
  `packages/eh_os_contract/docs/contract.md` i `docs/adr/`: dokument, który czyta ktoś spoza tego zespołu. Ten plik i
  dotychczasowy `PLAN.md` zostają po polsku, bo ich czytelnikiem był tylko zespół pracujący w tym
  repozytorium.
- **Od 6 października nowe wpisy w `PLAN.md` są po angielsku** (decyzja użytkownika: projekt będzie
  międzynarodowy, więc ślady w repozytorium i na GitHubie zostawiamy po angielsku; rozmawiamy po polsku).
  Historia zostaje po polsku i nie jest tłumaczona; poprawka w istniejącym polskim akapicie (status, link)
  idzie w jego języku. Issue i PR-y — zawsze po angielsku (skill `stage-issue`). *Odrzucone:* przetłumaczenie
  całego `PLAN.md` (ponad 11 000 linii, tłumaczenie hurtem gubi uzasadnienia, jak przy pierwszych commitach);
  zostawienie polskiego dla nowych wpisów.
- **Publiczne funkcje w `packages/eh_os_contract/lib/` mają `@doc` i `@spec`.** Bez tego pakiet nie ma dokumentacji ani
  kontraktu typów, a `dialyzer` nie ma czego sprawdzać.
- Wcześniejsza wersja tej reguły mówiła „identyfikatory po angielsku, moduledoki i komentarze po polsku"
  i to był błąd, który zdążył się rozlać po bibliotece. **Poprawianie wstecz jest osobnym zadaniem** —
  patrz `PLAN.md`, bo jest sprzężone z assercjami testów bram kompilacyjnych.
- **Komunikaty commitów po angielsku**, z tej samej reguły: `git log` czyta recenzent, nigdy klient.
  Dwanaście pierwszych commitów jest po polsku i **zostaje** — historia sprzed reguły nie jest przepisywana,
  bo te wiadomości niosą uzasadnienia decyzji i tłumaczenie ich hurtem gubi więcej, niż porządkuje.
- **Polski cudzysłów zamykający to `”` (U+201D), nie `"`.** Wpisanie ASCII-owego `"` w środku
  stringu kończy string i wywala kompilację z komunikatem o nieoczekiwanym tokenie w miejscu
  **otwierającego** `„`, czyli kilka znaków przed prawdziwą przyczyną. Zdarzyło się trzy razy w jeden dzień.
- **Wyrażenie regularne na tekście klienta zawsze z flagą `u`.** Bez niej `\R`, `\s` i `\w` czytają bajty, a
  polszczyzna ma w UTF-8 bajty, które coś znaczą: `~r/\R/` łapie `0x85`, drugi bajt „ą”. Zdarzyło się 28 września
  w grafach EG1 — każda polska etykieta traciła „ą”, a testy przechodziły, bo żaden nie miał „ą”. Test tekstu
  klienta pisz z polską etykietą.
- **Z flagą `u` `\d` to każda cyfra Unicode, nie `[0-9]`.** Format ASCII — numer KSeF, NIP, data — pisz
  `[0-9]`. Zdarzyło się 28 września w E9c-2: data zapisana cyframi arabsko-indyjskimi przechodziła wyrażenie,
  `String.to_integer/1` rzucał wyjątek i nagranie faktury kończyło się wyjątkiem zamiast odmowy inwariantu.
- Przy pisaniu do pliku pamiętaj o `encoding: :unicode` — Erlang trzyma stdout w latin1, kiedy wyjście
  nie jest terminalem, i psuje każdy polski znak.
- **W skryptach powłoki nie licz na dzielenie na słowa.** Shell to zsh, a zsh **nie dzieli** nierozdzielonych
  rozwinięć — `for x in $LISTA` daje jedną iterację z całą listą w jednym argumencie, nie N iteracji. Raz
  wystarczyło, żeby `git cherry-pick` dostał siedem SHA-ów jako jeden argument, padł, a stojące po nim
  `git commit --amend` przepisało nie ten commit, co miało. Pętle po SHA-ach pisz jawnie albo przez tablice.
- **Nazwy zdarzeń pochodzą z warsztatu**, nie z wyobraźni. Źródło:
  `~/Projects/ai/taxvision-process-native/workshop_output/02-event-storming.md`.

## Człowiek jest bramą, więc czytelność jest wymaganiem

Kod idzie jako PR i weryfikuje go człowiek. Z tego wynikają dwie rzeczy przy generowaniu:

1. **Uwaga recenzenta idzie tam, gdzie jest losowość** — czyli na funkcje decyzyjne. Szkielet, migracje i
   granice są deterministyczne i recenzuje się je raz na wzorzec, nie raz na wystąpienie.
2. **Mały diff.** PR, którego nie da się przeczytać z uwagą, nie jest recenzowany, tylko przybijany. To jest
   ograniczenie funkcjonalne, nie stylistyczne.

## Czego nie budujemy

`mix eh_os_contract.new` (dopiero przy drugim kliencie). Prawdziwych parserów i integracji — koszt domenowy klienta,
zero sygnału dla biblioteki. **Tożsamości** — logowania, kont, ról, providera OIDC: silnik zna aktora
wyłącznie jako nieprzezroczysty `subject`, uwierzytelnia aplikacja klienta, dostęp do dashboardu
rozstrzyga host przez `EhOsContract.Web.Resolver` (od 23 września; wcześniej `PNS.Auth` z logowaniem i kontami, z
czasów, gdy silnik miał być właścicielem EHOS). **Od 25 września (D14 w v2 §16)** credential wydaje EHOS, a
weryfikuje go osobny pakiet `eh_os_contract_auth` (etap EA w `PLAN.md`), który implementuje
`EhOsContract.Authorizer` kontraktu; rdzeń od niego nie zależy i dalej niczego nie weryfikuje. Role to aktorzy
kontraktu (v2 §18), nie osobna deklaracja. Alertów i widoków operacyjnych. **Czegokolwiek, co
odpowiada na pytanie o konkretną firmę.**
