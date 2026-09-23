# EhOsContract — repozytorium silnika

Silnik weryfikacji zgodności wdrożonego kodu z zadeklarowanym procesem. `lib/eh_os_contract/` to silnik i przyszły
pakiet; `lib/taxvision/` to **aplikacja klienta, która jest tu tymczasowo** — jako przypadek testowy,
na którym sprawdzamy, czy założenia silnika się trzymają. Granica jest wymuszona przez `boundary` od
pierwszego commita, żeby ta tymczasowość była faktem, a nie obietnicą.

**Do 23 września pakiet nazywał się `pns` (moduły `PNS.*`, host `:pns_prototype`, tabele `pns_*`).**
Wszystko w kodzie nosi już nową nazwę — `eh_os_contract`, `EhOsContract`, `:eh_os_contract_host`. Stara
zostaje tylko w `docs/adr/` i w historii `PLAN.md`, bo to zapis, nie opis stanu: `PNS.X` tam to dzisiejsze
`EhOsContract.X`.

**To repozytorium jest przejściowe i nie budujemy w nim aplikacji dla nikogo.** Produktem są fundamenty
biblioteki i wnioski; TaxVision i Rehmed są **danymi testowymi** — materiałem, na którym sprawdzamy, czy
DSL się trzyma. Dlatego wnioski z pisania kontraktu idą do `PLAN.md` jako praca nad biblioteką, a nie do
notatek o kliencie, i dlatego kontrakt, którego nie da się napisać, jest **lepszym** wynikiem niż
kontrakt napisany obok materiału.

Od 18 sierpnia dane testowe są z dwóch domen. `lib/taxvision/` to pełna aplikacja — schematy, handlery,
repo. `lib/rehmed/` to **wyłącznie kontrakty**: Rehmed nie ma tu kodu i nie będzie miał, bo do
sprawdzenia DSL kod nie jest potrzebny. Trzecia domena medyczna, `UniversalityGate.TreatmentEpisode`,
zostaje w `test/support/`, bo jest **zmyślona** — i sama to o sobie mówi w pierwszej linii.

## Zanim cokolwiek zmienisz

| Co | Gdzie |
| --- | --- |
| Plan pracy, etapy, kryteria odbioru, **stan** | [`PLAN.md`](PLAN.md) |
| Czym jest to repozytorium, brama, struktura | [`README.md`](README.md) |
| **Jak napisać kontrakt** — klucze, wymagane/opcjonalne, co się nie skompiluje | [`docs/contract.md`](docs/contract.md) |
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

## Jedno pytanie, na które ten produkt odpowiada

> Czy wdrożony kod robi to, co mówi zdefiniowany proces?

Ekran ma **cztery pytania i ani jednego więcej**: które zadeklarowane ścieżki nigdy nie zostały przejechane,
które przejścia nie są zadeklarowane, które assercje `trace` są naruszane, która wersja kontraktu jest
wdrożona i od kiedy.

Wszystko inne ma właściciela: wydajność to GCP, błędy to Datadog, **stan biznesu to aplikacja klienta**.
Kiedy EhOsContract zacznie odpowiadać „która firma nie ma otwartego lipca", staje się drugim, gorszym ekranem
aplikacji klienta.

## Brama

```bash
docker compose up -d && mix ecto.setup && mix check
```

`mix check` to `compile --force --warnings-as-errors`, `eh_os_contract.check`, `eh_os_contract.docs --check`, `test` i — od
21 sierpnia — `mix test` w `packages/eh_os_contract` osobnym wywołaniem. **Musi przechodzić.** Suita silnika
przeniosła się do pakietu i `mix test` w tym projekcie już jej nie widzi; brama, która przestałaby
pokrywać silnik w dniu, w którym silnik dostał własną suitę, byłaby najgorszym możliwym wynikiem tej
przeprowadzki. Osobne wywołanie, nie umbrella — pakiet ma stać sam, i to jest własność, której pilnujemy. `eh_os_contract.docs --check` pilnuje, że referencja kluczy w `docs/contract.md` jest
wygenerowana z `EhOsContract.Contract.schema/0`, a nie pisana ręcznie.
`--warnings-as-errors` jest konieczne: `boundary` raportuje naruszenia jako ostrzeżenia, więc bez tego
przełącznika granice są dokumentacją. Postgres słucha na **5433**.

**Nie rurkuj bramy do `tail` przed commitem.** `mix check | tail -4 && git commit` sprawdza kod wyjścia
**`tail`**, który jest zawsze zerowy — więc commit idzie na czerwonym, a Ty widzisz cztery ostatnie linie i
nie widzisz liczby padnięć. Zdarzyło się 6 sierpnia: scommitowane 24 padnięcia. Jeśli musisz skrócić wyjście:

```bash
out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"
```

**`mix run` w `MIX_ENV=test` pisze poza sandboxem.** Sandbox obejmuje testy, nie zadania mixa — więc jedno
`MIX_ENV=test mix run -e '...'` zostawia wiersze **na stałe** w bazie testowej i wywala potem wszystko, co
liczy rekordy. Ta sama pułapka, którą `EhOsContract.Deployment.record!` zastawia przy boocie. Do oglądania czegokolwiek
używaj `MIX_ENV=dev`; jeśli już wpadniesz, ratuje `MIX_ENV=test mix ecto.drop && mix ecto.create &&
mix ecto.migrate`.

## Konwencje, które łatwo złamać

- **`boundary`: moduły procesowe są rodzeństwem, nie hierarchią.** Dostęp do cudzych tabel wymaga jawnego
  `deps`. Pierwsza wersja miała `Taxvision` zależny od własnych dzieci i `boundary` słusznie ją odrzucił.
- **Reguła wskazuje MFA, nigdy capture.** Capture zrobiłby z kontraktu zależność kompilacyjną od domeny, a
  handlery zależą od kontraktu — więc każda zmiana domeny rekompilowałaby wszystko.
- **Sprawdzenia w ciele makra, nie w `quote`.** To tworzy zależność kompilacyjną i sprawia, że błąd wskazuje
  handler, nie bibliotekę.
- **Nazwy zdarzeń to literały.** Publikacja dynamiczna jest nielegalna, bo od tego zależy, czy graf statyczny
  jest faktem, czy heurystyką.
- **Kod jest po angielsku. Bez wyjątków.** Identyfikatory, moduledoki, `@doc`, komentarze, nazwy testów,
  komunikaty błędów kompilacji i stringi wypisywane na wyjście. **Zakres to nie tylko `lib/eh_os_contract/`** —
  także `lib/taxvision/`, `lib/rehmed/`, `test/` i `packages/eh_os_contract/test/` z fikstrami, `config/`,
  `priv/repo/migrations/`,
  `docs/` i `mix.exs`.
  Trzy ostatnie zostały przy pierwszym sprzątaniu pominięte, bo nikt o nich nie pomyślał.
- **Po polsku jest wyłącznie to, co klient czyta zdaniami, i tylko w stringu** — nigdy w komentarzu,
  moduledoku ani nazwie. Konkretnie: `label`, opisy `example`, `source` i `unavailable_looks_like` w
  kontrakcie, nazwy tasków, temat powiadomienia. Poza tymi miejscami polski string też jest błędem.
  Raport zgodności był tu wcześniej piątym wyjątkiem i **przestał być, 6 sierpnia**: renderer przeniósł się
  do silnika (`EhOsContract.Report`, dawniej `Taxvision.Report` w drzewie klienta) i wypisuje po angielsku — decyzja
  zapisana w `PLAN.md`. Etykiety kontraktu (`label`, `from_label`, `to_label`) nadal wychodzą w raporcie
  dosłownie, w języku, w którym je zadeklarował klient — regułą jest teraz "silnik pisze swoje zdania po
  angielsku", nie "kto czyta cały artefakt".
- **Grep po `[ąćęłńóśźż]` nie wystarcza do sprawdzenia** i to jest zapisane, bo kosztowało jeden fałszywy
  „gotowe". Spora część polszczyzny nie ma diakrytyków — `rejestry` w `registry_check.ex` przeżyło pełne
  przepisanie pliku po pliku właśnie dlatego. Przy sprawdzaniu trzeba przejść też po słowach.
- **Dokumentacja repo robocza — `PLAN.md`, ten plik — zostaje po polsku.** To nie jest kod i nie
  jedzie z pakietem. **`README.md` jest wyjątkiem od 21 sierpnia** — biblioteka ma zostać
  upubliczniona, więc `README.md` jest teraz po angielsku, po tej samej stronie granicy co
  `docs/contract.md` i `docs/adr/`: dokument, który czyta ktoś spoza tego zespołu. `PLAN.md`
  i ten plik zostają po polsku, bo ich czytelnikiem wciąż jest tylko zespół pracujący w tym
  repozytorium.
- **Publiczne funkcje w `lib/eh_os_contract/` mają `@doc` i `@spec`.** Bez tego pakiet nie ma dokumentacji ani
  kontraktu typów, a `dialyzer` nie ma czego sprawdzać.
- Wcześniejsza wersja tej reguły mówiła „identyfikatory po angielsku, moduledoki i komentarze po polsku"
  i to był błąd, który zdążył się rozlać po `lib/eh_os_contract/`. **Poprawianie wstecz jest osobnym zadaniem** —
  patrz `PLAN.md`, bo jest sprzężone z assercjami testów bram kompilacyjnych.
- **Komunikaty commitów po angielsku**, z tej samej reguły: `git log` czyta recenzent, nigdy klient.
  Dwanaście pierwszych commitów jest po polsku i **zostaje** — historia sprzed reguły nie jest przepisywana,
  bo te wiadomości niosą uzasadnienia decyzji i tłumaczenie ich hurtem gubi więcej, niż porządkuje.
- **Polski cudzysłów zamykający to `”` (U+201D), nie `"`.** Wpisanie ASCII-owego `"` w środku
  stringu kończy string i wywala kompilację z komunikatem o nieoczekiwanym tokenie w miejscu
  **otwierającego** `„`, czyli kilka znaków przed prawdziwą przyczyną. Zdarzyło się trzy razy w jeden dzień.
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
rozstrzyga host przez `EhOsContract.Web.Resolver` (od 23 września; wcześniej `EhOsContract.Auth` z logowaniem i kontami, z
czasów, gdy silnik miał być właścicielem EHOS). Grafu w
interfejsie — sprawdzone, przy tej skali dekoracja. Alertów i widoków operacyjnych. **Czegokolwiek, co
odpowiada na pytanie o konkretną firmę.**
