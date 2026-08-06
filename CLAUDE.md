# PNS — repozytorium kodu

Silnik weryfikacji zgodności wdrożonego kodu z zadeklarowanym procesem, plus jedna aplikacja klienta jako
przypadek testowy. `lib/pns/` to przyszły pakiet, `lib/taxvision/` to kod klienta. Granica jest wymuszona
przez `boundary` od pierwszego commita.

## Zanim cokolwiek zmienisz

| Co | Gdzie |
| --- | --- |
| Plan pracy, etapy, kryteria odbioru | [`PLAN.md`](PLAN.md) |
| Stan faktyczny, luki, co wyszło z prototypu | [`README.md`](README.md) |
| **Jak napisać kontrakt** — klucze, wymagane/opcjonalne, co się nie skompiluje | [`docs/contract.md`](docs/contract.md) |
| **Pełny rekord projektowy, 18 decyzji, `§N` z komentarzy w kodzie** | [`docs/adr/008-pns-runtime-architecture.md`](docs/adr/008-pns-runtime-architecture.md) |
| Co każda decyzja pobiła, odrzucone alternatywy | [`docs/adr/design-rationale.md`](docs/adr/design-rationale.md) |
| Kształty kodu, schematy, pułapki, wybory bibliotek | [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) |
| Przegląd zespołu z 3 sierpnia | `~/Projects/ai/empowered-house-context/output/20260803-adr-008-review.md` — **został w repo kontekstu**, bo mówi o luce mocy i ekonomii wdrożeń |
| Propozycja sprzedażowa i warunki oceny, dwie strony | `~/Projects/ai/empowered-house-context/decisions/008-pns-runtime-architecture.md` |
| Zakres produktu i uzasadnienie | `~/Projects/ai/empowered-house-context/output/20260804-pns-product-plan.md` |

**Pakiet projektowy przeniesiono tutaj 6 sierpnia** z repozytorium kontekstu, bez zmian w treści. Tam został
dwustronicowy rekord: idea, zakres, warunki oceny, stan recenzji. Podział jest po przeznaczeniu — tam się
sprzedaje pomysł i zapada decyzja, tutaj leży dowód.

Z tego wynika, gdzie co poprawiać:

- **Szczegół implementacyjny** — `docs/adr/technology-notes.md`, na miejscu, jednym commitem.
- **Decyzja albo warunek oceny** — nie tutaj. Ustalenie ląduje w `PLAN.md` jako wniosek, a do rekordu w repo
  kontekstu wraca **przy zamknięciu etapu**, nie przy każdej zmianie.
- Rekord jest **świadomie z tyłu**. Gdy rekord i `PLAN.md` się różnią, nowszy jest `PLAN.md`.

Rekord mylił się już dwa razy i oba razy wyszło to przy pisaniu kodu. Jeśli myli się znowu, poprawka idzie do
rekordu — nie do komentarza obchodzącego problem.

## Jedno pytanie, na które ten produkt odpowiada

> Czy wdrożony kod robi to, co mówi zdefiniowany proces?

Ekran ma **cztery pytania i ani jednego więcej**: które zadeklarowane ścieżki nigdy nie zostały przejechane,
które przejścia nie są zadeklarowane, które assercje `trace` są naruszane, która wersja kontraktu jest
wdrożona i od kiedy.

Wszystko inne ma właściciela: wydajność to GCP, błędy to Datadog, **stan biznesu to aplikacja klienta**.
Kiedy PNS zacznie odpowiadać „która firma nie ma otwartego lipca", staje się drugim, gorszym ekranem
aplikacji klienta.

## Brama

```bash
docker compose up -d && mix ecto.setup && mix check
```

`mix check` to `compile --force --warnings-as-errors`, `pns.check`, `pns.docs --check` i `test`.
**Musi przechodzić.** `pns.docs --check` pilnuje, że referencja kluczy w `docs/contract.md` jest
wygenerowana z `PNS.Contract.schema/0`, a nie pisana ręcznie.
`--warnings-as-errors` jest konieczne: `boundary` raportuje naruszenia jako ostrzeżenia, więc bez tego
przełącznika granice są dokumentacją. Postgres słucha na **5433**.

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
  komunikaty błędów kompilacji i stringi wypisywane na wyjście. **Zakres to nie tylko `lib/pns/`** —
  także `lib/taxvision/`, `test/` z fikstrami, `config/`, `priv/repo/migrations/`, `docs/` i `mix.exs`.
  Trzy ostatnie zostały przy pierwszym sprzątaniu pominięte, bo nikt o nich nie pomyślał.
- **Po polsku jest wyłącznie to, co klient czyta zdaniami, i tylko w stringu** — nigdy w komentarzu,
  moduledoku ani nazwie. Konkretnie: `label`, opisy `example`, `source` i `unavailable_looks_like` w
  kontrakcie, raport w `Taxvision.Report`, nazwy tasków, temat powiadomienia. Poza tymi miejscami polski
  string też jest błędem.
- **Grep po `[ąćęłńóśźż]` nie wystarcza do sprawdzenia** i to jest zapisane, bo kosztowało jeden fałszywy
  „gotowe". Spora część polszczyzny nie ma diakrytyków — `rejestry` w `registry_check.ex` przeżyło pełne
  przepisanie pliku po pliku właśnie dlatego. Przy sprawdzaniu trzeba przejść też po słowach.
- **Dokumentacja repo — `README.md`, `PLAN.md`, ten plik — zostaje po polsku.** To nie jest kod i nie
  jedzie z pakietem.
- **Publiczne funkcje w `lib/pns/` mają `@doc` i `@spec`.** Bez tego pakiet nie ma dokumentacji ani
  kontraktu typów, a `dialyzer` nie ma czego sprawdzać.
- Wcześniejsza wersja tej reguły mówiła „identyfikatory po angielsku, moduledoki i komentarze po polsku"
  i to był błąd, który zdążył się rozlać po `lib/pns/`. **Poprawianie wstecz jest osobnym zadaniem** —
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

`mix pns.new` (dopiero przy drugim kliencie). Prawdziwych parserów i integracji — koszt domenowy klienta,
zero sygnału dla biblioteki. Providera OIDC — szew działa, podmiana to jedna linia konfiguracji. Grafu w
interfejsie — sprawdzone, przy tej skali dekoracja. Alertów i widoków operacyjnych. **Czegokolwiek, co
odpowiada na pytanie o konkretną firmę.**
