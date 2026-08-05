# PNS — repozytorium kodu

Silnik weryfikacji zgodności wdrożonego kodu z zadeklarowanym procesem, plus jedna aplikacja klienta jako
przypadek testowy. `lib/pns/` to przyszły pakiet, `lib/taxvision/` to kod klienta. Granica jest wymuszona
przez `boundary` od pierwszego commita.

## Zanim cokolwiek zmienisz

| Co | Gdzie |
| --- | --- |
| Plan pracy, etapy, kryteria odbioru | [`PLAN.md`](PLAN.md) |
| Stan faktyczny, luki, co wyszło z prototypu | [`README.md`](README.md) |
| Decyzja architektoniczna | `~/Projects/ai/empowered-house-context/decisions/008-pns-runtime-architecture.md` |
| Kształty kodu, schematy, pułapki | `~/Projects/ai/empowered-house-context/output/20260801-pns-architecture-adr/technology-notes.md` |
| Zakres produktu i uzasadnienie | `~/Projects/ai/empowered-house-context/output/20260804-pns-product-plan.md` |

Repo kontekstu jest **źródłem prawdy dla decyzji**. Jeśli kod pokaże, że rekord się myli — a to się już
zdarzyło dwa razy — poprawka idzie do rekordu, nie do komentarza w kodzie.

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

`mix check` to `compile --force --warnings-as-errors`, `pns.check` i `test`. **Musi przechodzić.**
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
- **Etykiety po polsku**, bo to język klienta. Przy pisaniu do pliku pamiętaj o `encoding: :unicode` —
  Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, i psuje każdy polski znak.
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
