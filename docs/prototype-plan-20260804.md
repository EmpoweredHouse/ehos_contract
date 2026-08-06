---
type: Output
title: Środowisko testowe PNS — bootstrap projektu
owner: operator
status: done
last_updated: 2026-08-04
source_of_truth: decyzja 008 w stanie z 2026-08-04, przegląd 2026-08-03, szew tożsamości 2026-08-04
load_policy: task
related:
  - /decisions/008-pns-runtime-architecture.md
  - ~/Projects/ai/pns_prototype/docs/adr/technology-notes.md
  - ~/Projects/ai/empowered-house-context/output/20260803-adr-008-review.md
  - /output/20260804-pns-identity-service.md
  - /wiki/pns/modular-design.md
  - /wiki/pns/event-driven-doctrine.md
---

> **Przeniesione z repozytorium kontekstu 6 sierpnia 2026, bez zmian w treści. Dokument historyczny.**
>
> Plan pierwszego prototypu, wykonany 4 sierpnia. Trzymany dla porównania „co planowaliśmy" z „co wyszło" —
> dwie rzeczy rozstrzygnęły się inaczej i to jest zapisane w nagłówku planu.
>
> **Bieżąca robota jest w [`../PLAN.md`](../PLAN.md), nie tutaj.** Wyniki i wnioski w
> [`../README.md`](../README.md).

# Środowisko testowe PNS — bootstrap projektu

Napisane od nowa 4 sierpnia. Poprzednia wersja powstała 2 sierpnia wieczorem i nie została wykonana;
między nią a dziś rekord przeszedł czternaście commitów, w tym cały przegląd zespołu i ustalenie szwu
tożsamości. Wersja z 2 sierpnia jest **zastąpiona, nie poprawiona** — zmienił się DSL kontraktu, doszła
brama kompilacyjna §18, ekrany przestały być pytaniem otwartym, a tożsamość weszła do zakresu.

> **Wykonane 4 sierpnia.** Kod: `~/Projects/ai/pns_prototype`, 42 testy, `mix check` przechodzi. Dwie
> rzeczy w tym planie rozstrzygnęły się inaczej: providera OIDC **nie stawialiśmy** (szew jest prawdziwy,
> implementacją jest lokalny HMAC — Zitadel to koszt bez sygnału na tym etapie), a warstwa web jest
> minimalna i ręczna. Ustalenia wróciły do decyzji 008 i notatek technologicznych. Pełny raport w
> `README.md` prototypu.

Cel: **projekt, który stoi jedną komendą i w którym da się uruchomić testy sprawdzające twierdzenia
decyzji 008.** Nie prezentacja, nie szkielet do pokazania — środowisko, w którym twierdzenie albo przechodzi
test, albo nie.

## Rozstrzygnięcia, które nie są pytaniami

Trzy rzeczy, które w poprzedniej wersji były rozwidleniem albo przemilczeniem. Rozstrzygnięte tutaj, żeby
nie wracały w trakcie pracy.

**1. Kod zostaje i ma kształt kroku 1 z §15.** Jedno repo `~/Projects/ai/pns-prototype`, jeden projekt
mix, `lib/pns/` (to, co będzie pakietem) obok `lib/taxvision/` (aplikacja klienta), granica pilnowana przez
`boundary` od pierwszego commita. Struktura jest dokładnie ta, którą §15 przewiduje dla pierwszego klienta,
więc przeniesienie tego obok repozytorium klienta jest `git mv`, a nie przepisaniem.

Przegląd ostrzegł przed jednym trybem awarii — *„otherwise it becomes the template §16–17 refuses to
build"*. Zabezpieczenie jest mechaniczne, nie deklaratywne: **nie budujemy `mix pns.new`** (§15 stawia to
przy drugim kliencie), nie wyciągamy generycznego template'u, a drzewo klienckie nazywa się `taxvision`, nie
`my_app`. Nazwa katalogu jest częścią zabezpieczenia — nic z tego nie wygląda na coś do skopiowania.

**2. Warstwa web wchodzi, w minimalnej postaci.** Poprzednia wersja pomijała Phoenixa uzasadnieniem, które
się przewróciło: ekrany zostały rozstrzygnięte 3 sierpnia (silnik headless za API, frontendy osobno). Bez
warstwy web nie ma gdzie zwalidować tokenu, więc tożsamość byłaby nietestowalna. Wchodzi więc **API pisane
ręcznie, dwa wejścia: jedna komenda i jedno zapytanie.**

Jawne ograniczenie: to API **nie jest generowane z kontraktu** i **nie jest dowodem w sprawie REST vs
GraphQL**, która pozostaje otwarta. Jest najcieńszą rzeczą, przez którą przechodzi token i komenda. Gdyby
zaczęło rosnąć, znaczy, że robimy nie ten spike.

**3. Tożsamość jest w zakresie i jest jednym z twierdzeń.** Wcześniej wypisana poza zakres, co było błędem:
szew z 4 sierpnia to jedyna decyzja architektoniczna z tego tygodnia, którą można sprawdzić w całości bez
klienta, a jej trybów awarii nie widać w prozie. Provider stoi w `docker-compose` obok silnika i jest
prawdziwy — nie stub, nie fake.

## Twierdzenia do sprawdzenia kodem

Sześć. Każde ma test albo artefakt, nie akapit.

| | Twierdzenie | Źródło | Jak upada |
| --- | --- | --- | --- |
| 1 | Kontrakt jako moduł Elixira jest wykonalny i czytelny — akumulacja deklaracji, `@before_compile` generujący zapytania, `version/0` jako hash | §1–2, notatki §1 | DSL wymaga więcej ceremonii niż to, co opisuje; albo `version/0` nie da się policzyć w czasie kompilacji |
| 2 | Podział dispatchu po granicy transakcji jest **mechanicznie rozstrzygalny** — nie deklaracją programisty, a lintem po tym, co handler faktycznie robi | §9–10, notatki §4 | Lint nie umie odróżnić I/O poza repo od operacji na własnych tabelach, i decyzja wraca do człowieka |
| 3 | Wynik warsztatu jest discovery-grade, nie generation-grade | §1 | Okazuje się, że wystarcza — wtedy odrzucona alternatywa „generowanie wprost z grafu" była tańsza i decyzja 1 jest zła |
| 4 | Reguła przez przykład działa jako brama kompilacyjna: *reguła bez przykładu się nie kompiluje*, a przykład **jest** testem | §18, notatki §6 | Brama jest łatwa, ale „przykład jest testem" wymaga, żeby kontrakt znał funkcję w czasie kompilacji — czego §1 zabrania (MFA, nie capture). Jeśli wychodzi z tego generator testów, §18 twierdzi coś mocniejszego, niż dowozi |
| 5 | **Tożsamość za szwem protokolarnym trzyma się, a trzy poziomy IAM są rozdzielone w kodzie** | [szew tożsamości](adr/identity-seam.md) | Rozdzielenie okazuje się nieostre: albo reguła domenowa wypływa do konfiguracji providera, albo entitlement wraca jako zapytanie per request |
| 6 | Ecto daje hook na repo widzący dotknięte tabele | trigger §5–6, przegląd | Nie daje — i wtedy odroczenie runtime'owego confinementu przestaje być bezpieczne, a to jest decyzja strukturalna do podjęcia teraz, nie później |

Twierdzenie 6 miało termin — sesja zespołu 5 sierpnia — i **jest już rozstrzygnięte**, patrz niżej. Reszta
idzie w bootstrapie.

### Wynik sondy Ecto — rozstrzygnięte 4 sierpnia

**Hook istnieje i odroczenie jest bezpieczne.** `Ecto.Repo.prepare_query/3` to nadpisywalny callback
użytkownika, wołany **przed** wykonaniem, dostający cały `%Ecto.Query{}` — więc wszystkie dotknięte tabele
wychodzą **strukturalnie**, z `query.from` i `query.joins`, bez parsowania SQL-a. Retrofit to nadpisanie
jednego callbacku w module repo: **nie wymaga zmiany tego, jak moduły sięgają do repo**, co było dokładnym
warunkiem postawionym w przeglądzie.

Sprawdzone uruchomieniem na Ecto 3.14.1 / ecto_sql 3.14.0, nie z dokumentacji:

| Operacja | Hook | Co widzi |
| --- | --- | --- |
| `all` z joinem przez granicę modułu | tak | `["invoices", "jobs"]` — obie tabele |
| `update_all`, `delete_all` | tak | tabela docelowa |
| `insert_all` **ze źródłem-zapytaniem** | tak | tabela |
| `insert_all` z listą map | **nie** | — |
| `insert/2`, `update/2`, `delete/2` na changesecie | **nie** | — |
| surowy SQL przez `Ecto.Adapters.SQL.query/4` | **nie** | — |

Nazwa tabeli w joinie siedzi w module schematu, nie w `source` — trzeba dołożyć
`mod.__schema__(:source)`. Drobiazg, ale bez niego join wygląda na `nil` i check milczy tam, gdzie ma krzyczeć.

**Dlaczego luka nie jest dziurą.** Zapis do tabeli innego modułu changesetem wymaga nazwania jego schematu
Ecto, czyli zdalnej referencji do modułu — a to widzi tracer kompilacji i `boundary`, więc ta ścieżka jest
już pokryta na poziomie, na którym decyzja 008 ją stawia. Jedyne prawdziwie niewidoczne wejście to surowy
SQL z literalną nazwą tabeli — ten sam przypadek, który przegląd odłożył argumentem, że modele generują
idiomatyczny Ecto, nie SQL w stringach. Jeśli kiedyś okaże się potrzebny, jest na to telemetria
`[…, :repo, :query]`: leci przy **każdym** zapytaniu, w metadanych ma `source` i tekst SQL-a — ale po
wykonaniu, więc nadaje się do detekcji, nie do blokowania, i `source` to jedna tabela.

**Do zaniesienia na sesję 5 sierpnia:** hook jest, odroczenie stoi, właściciel z przeglądu (Kamil) ma o
dwadzieścia minut mniej pracy. Propozycja zmiany w triggerze §5–6 decyzji 008 czeka na akceptację —
to canonical context, więc nie tknąłem go bez zgody.

## Wycinek domenowy

Z sekcji 3.1 warsztatu TaxVision, **Otwarcie miesiąca**. Źródło:
`~/Projects/ai/taxvision-process-native/workshop_output/02-event-storming.md` (53 KB, skonsolidowany
EventStorming). Przegląd zalecił dokładnie to — *„make the spike one bounded TaxVision process"* — bo
generyczny projekt testuje maszynerię i nie testuje produktu.

Najmniejszy fragment mający wszystko, co architektura ma pokazać: rozgałęzienie, zewnętrzną zależność, oba
tryby dispatchu, politykę mapującą się 1:1 na assercję i **regułę autoryzacyjną, która jest regułą
biznesową, a nie ustawieniem providera**.

Zdarzenia zaimplementowane, nazwy z warsztatu, nie wymyślone:
`data_completeness_confirmed`, `registry_status_checked`, `registry_check_logged`,
`registry_data_consistent`, `registry_discrepancy_detected`, `monthly_tasks_generated`,
`accounting_month_opened`, `discrepancy_notification_sent`

Zdarzenia **zadeklarowane i celowo niezaimplementowane**, z faz 3.2–3.4: `bank_statement_received`,
`turnover_matched_with_invoice`, `month_closed`. To nie jest niedokończona robota, a demo stanu *declared,
never observed* (notatki §5, §9) — `mix pns.check` ma je wypisać jako martwe ścieżki.

**Polityka P1** z sekcji 10 („kiedy zaczyna się miesiąc, sprawdź rejestry; kiedy dane zgodne, wygeneruj
taski; kiedy niezgodne, zablokuj i powiadom") daje dwie rzeczy:

- assercję `trace` z gałęzią `or_else` — prawdziwe rozgałęzienie biznesowe,
- `rule` z dwoma przykładami wskazującą jedną czystą funkcję przez MFA: dane zgodne → taski wygenerowane,
  rozjazd → komenda odrzucona z powodem.

Podział dispatchu wychodzi z domeny sam, co jest właśnie testem twierdzenia 2:

- **w transakcji** — `Taxvision.Tasks.OnRegistryDataConsistent` generuje taski w swoich tabelach, ta sama
  baza, zero I/O na zewnątrz,
- **async przez Obana** — `Taxvision.Notifications.OnRegistryDiscrepancyDetected` wysyła powiadomienie,
  czyli I/O poza repo, więc **musi** być `:async` i lint ma to powiedzieć, jeśli ktoś zadeklaruje inaczej.

### Reguła autoryzacyjna jako reguła domenowa

To jest wycinek, który testuje twierdzenie 5, i wybrany tak, żeby wszystkie trzy poziomy IAM były na jednej
ścieżce żądania:

| Poziom | Pytanie | Kto właścicielem | W tym wycinku |
| --- | --- | --- | --- |
| Uwierzytelnienie | kto to jest | kupione | token podpisany przez providera, walidowany przeciw JWKS |
| Entitlement | czy ta osoba w ogóle dosięga API księgowego | kupione — grant roli jako claim | claim `accounting` czytany z tokenu przez plug, przed jakimkolwiek kodem domenowym |
| Reguła domenowa | czy **ta** osoba może otworzyć miesiąc, w którym są nierozliczone rozjazdy rejestrowe | **nasze** | `rule` w kontrakcie z przykładami, sprawdzana w czystej funkcji decyzyjnej |

Trzeci wiersz jest tam, gdzie jest wartość, i dlatego jest wyrażony tym samym mechanizmem co każda inna
reguła biznesowa — przez `rule` i `example`. Jeśli ta reguła da się zapisać jako polityka w Zitadelu, szew
jest źle postawiony i twierdzenie 5 upada. Jeśli entitlement wymaga zapytania do providera przy każdym
żądaniu, upada tak samo.

## Do zbudowania

### Infrastruktura — to jest „środowisko testowe"

`docker-compose.yml`: Postgres plus **provider OIDC**. Wybór na start: **Zitadel** — deklaratywny bootstrap
i lekkość w bundlowaniu to jego dwie przewagi z rozpoznania, a deklaratywny bootstrap jest tu wprost
wymagany, bo środowisko musi wstać na czystej maszynie bez klikania w panel. Zasiew: organizacja, projekt,
dwie role, użytkownik maszynowy do testów, dwóch ludzi z różnymi grantami.

Kryterium akceptacji dla całej tej sekcji: **`docker compose up -d && mix ecto.setup && mix test` przechodzi
na czystej maszynie**, bez ręcznego kroku w interfejsie providera. Jeśli tego nie da się osiągnąć w
Zitadelu, fallback jest znany i przetarty — Keycloak z importem realmu z JSON-a. **Który z dwóch wyszedł,
jest samo w sobie ustaleniem** i wraca do rozpoznania providerów w dokumencie o tożsamości, gdzie
deklaratywny bootstrap Zitadela jest wpisany jako rzecz do sprawdzenia w PoC, a nie do wzięcia z
dokumentacji.

Do tego: migracje, `config/test.exs` z Obanem w `testing: :manual`, `boundary` w `mix.exs` z jawnymi
`deps`/`exports` dla `PNS` jako „pakietu" wewnątrz aplikacji.

### Strona pakietu — `lib/pns/`

| Plik | Zawartość |
| --- | --- |
| `contract.ex` | `use PNS.Contract`: akumulacja `event`, `process`, `trace`, `external`, `rule`, `example` w atrybutach modułu; `@before_compile` generujący `event?/1`, `event/1`, `events/0`, `process/1`, `traces/0`, `external/1`, `rules/0`, `examples_for/1`, `version/0` (hash wszystkich deklaracji), `__pns_contract__/0` jako marker do skanu. **Brama §18: `rule` bez `example` przerywa kompilację.** `rule` trzyma MFA, nie capture — capture zrobiłby z kontraktu zależność kompilacyjną od domeny, a handlery zależą od kontraktu, więc każda zmiana domeny rekompilowałaby wszystko. Bez modułu agregującego: każdy kontrakt rejestruje się sam, referencje międzykontraktowe rozwiązywane po nazwie przy boocie |
| `handler.ex` | `use PNS.Handler, event:, publishes:, async:`: `@behaviour`, sprawdzenie istnienia zdarzenia i zgodności `publishes:` **w ciele makra, nie w `quote`** — to tworzy zależność kompilacyjną wymuszającą kolejność, a `__CALLER__` daje file/line wskazujące na handler, nie na bibliotekę. `__pns_handler__/0` wstrzyknięty do każdego handlera. Nazwy zdarzeń muszą być literałami; publikacja dynamiczna jest nielegalna, bo od tego zależy, czy graf statyczny jest faktem, czy heurystyką |
| `registry.ex` | Skan przy boocie: `:application.get_key/2` → `Code.ensure_loaded?` + `function_exported?/3` → `:persistent_term`. Zapytania `sync_handlers_for/1`, `async_handlers_for/1`, krawędzie grafu. Nie generowany moduł z całym grafem — makro per-moduł nie umie tego zaaranżować |
| `emitter.ex` | `emit/4` — jedna funkcja, w której widać cały §9: insert zdarzenia, handlery synchroniczne w tej samej transakcji, joby async wstawione w tej samej transakcji. Jeśli to nie mieści się w kilkunastu linijkach, argument za własną warstwą emisji jest słabszy niż zapisany |
| `event.ex`, `event_handling.ex` | Schematy wg notatek §3: `type, version, contract_version, correlation_id, causation_id, payload, actor, occurred_at` oraz `event_id, handler, attempt, status, duration_us, error`. `contract_version` od pierwszej migracji — niebackfillowalne |
| `job.ex` | Worker Obana uruchamiający jeden handler; korelacja serializowana do args przy enqueue, bo job leci w innym procesie BEAM-a i tu łańcuch się urywa najczęściej |
| `auth/verifier.ex` | Szew: `oidcc` — discovery URL, client id, client secret z konfiguracji, walidacja podpisu przeciw JWKS. **Zero credentiali, zero wystawiania tokenów.** Plug do pipeline'u API |
| `auth/entitlement.ex` | Plug czytający **jeden claim** i odcinający żądanie przed kodem domenowym. Bez sieci, świeżość w granicach czasu życia tokenu. Alternatywa — własna replika aktualizowana eventem przy zmianie grantu — zapisana jako druga ścieżka i nieimplementowana; ścieżka trzecia, pytanie do wspólnego serwisu per request, jest jawnie odrzucona, bo robi z kilku API rozproszony monolit |
| `auth/directory.ex` | `@behaviour` na garść wywołań user-management, których potrzebuje ekran admina: lista pracowników, grant roli, zaproszenie. Cienki celowo — grubość tutaj znaczy drugie źródło prawdy o tym, kto pracuje w firmie. Implementacja przeciw providerowi plus fake do testów |
| `mix/tasks/pns.check.ex` | Sprawdzenia całoprogramowe, bo makro widzi jeden plik: każde zdarzenie ma handler albo jest terminalne; brak sierot; `publishes:` zgodne z tym, co widział tracer; **krawędzie wsteczne** (trigger §15 mówi „od pierwszego commita"); rozstrzygalność `trace` po nazwach; funkcja z `rule` istnieje; referencje międzykontraktowe się rozwiązują; **raport** pól z wolnym tekstem bez `retain` — raport, nie błąd, bo brama kompilacyjna na dane osobowe była rekomendowana i odrzucona; **brak nazwy vendora w schemacie konfiguracji silnika** |
| `mix/tasks/pns.graph.ex` | Graf statyczny plus nałożone liczniki z logu; wyjście tekstowe i mermaid |

### Strona aplikacji — `lib/taxvision/`

`repo.ex`. `contracts/month_end_closing.ex` — kontrakt z procesem, `cadence`, `deadline`, assercją `trace`,
regułą P1 i regułą autoryzacyjną, każda z dwoma przykładami. Moduł `registry_check/` z **czystą funkcją
decyzyjną** `command -> {:error, reason} | [events]`; to ona jest wskazywana przez `rule` i ona sprawdza
regułę domenową o uprawnieniach. Moduł `tasks/`, moduł `notifications/`,
`adapters/registry_lookup.ex` — behaviour plus fake (CEIDG/KRS/VAT/VIES), bo prawdziwe rejestry są poza
zakresem.

Granice zgodnie z `wiki/pns/modular-design.md`: prywatne tabele, zero joinów międzymodułowych, duplikacja
tylko tam, gdzie jedna kopia jest nazwanym źródłem prawdy.

### Warstwa web — `lib/taxvision_web/`

Pipeline: `PNS.Auth.Verifier` → `PNS.Auth.Entitlement` → kontroler. Dwa wejścia: `POST` otwierające miesiąc
(komenda) i `GET` czytający stan procesu (zapytanie). Ręcznie pisane, nie generowane, i to jest zapisane w
`README` prototypu, żeby nikt nie policzył tego jako dowodu w sprawie REST vs GraphQL.

## Weryfikacja

Testy są deliverable'em, nie dodatkiem — to one są treścią twierdzeń.

**Kontrakt i kompilacja**

1. Handler zadeklarowany na nieistniejące zdarzenie **nie kompiluje się** — przez `Code.compile_string/1`
   z asercją na wyjątek i na to, że komunikat wskazuje handler, nie bibliotekę.
2. **Reguła bez przykładu nie kompiluje się** (§18). Drugi artefakt kompilacyjny i jedyny, który da się
   pokazać osobie nietechnicznej.
3. `version/0` zmienia się po zmianie dowolnej deklaracji, w tym `retain:`.
4. Przykłady **są** testami: oba przypadki P1 przechodzą przeciw czystej funkcji decyzyjnej, bez pisania
   osobnych testów.

**Dispatch**

5. `emit` zapisuje zdarzenie, uruchamia handler synchroniczny i kolejkuje job async — wszystko w jednej
   transakcji.
6. Handler synchroniczny rzuca → brak wiersza zdarzenia, brak joba, błąd u wołającego.
7. Handler async dostarczony dwa razy → drugi raz bez dodatkowego efektu.
8. `correlation_id` przechodzi przez granicę joba Obana.
9. Handler robiący I/O poza repo, zadeklarowany jako synchroniczny, **jest wyłapany** — to jest test
   twierdzenia 2 i jeśli nie przechodzi, decyzja o „enforced, not chosen" jest życzeniem.

**Tożsamość — trzy poziomy, trzy różne odpowiedzi**

10. Żądanie bez tokenu → 401. Żądanie z tokenem podpisanym niewłaściwym kluczem → 401. Walidacja przeciw
    JWKS jest prawdziwa, nie zaślepiona.
11. Token bez claimu `accounting` → **403 przed jakimkolwiek kodem domenowym**. Weryfikowane brakiem
    wiersza w logu zdarzeń, nie treścią odpowiedzi.
12. Token z rolą, ale osoba nieuprawniona do tej operacji domenowej → **komenda odrzucona przez regułę z
    kontraktu**, z powodem, i odrzucenie jest zapisanym przypadkiem, a nie 403. Ten test jest całym
    twierdzeniem 5: gdyby dało się go przejść konfiguracją providera, poziomy nie są rozdzielone.
13. **Test strukturalny szwu**: brak tabeli z credentialami osiągalnej z kodu domenowego, brak wystawiania
    tokenów, brak nazwy vendora w schemacie konfiguracji. Jako test, nie jako konwencja — bo to są trzy
    rzeczy, które szew wymienia jako łamiące go.

**Conformance**

14. `mix pns.check` wypisuje zdarzenia z faz 3.2–3.4 jako zadeklarowane i nieobserwowane.
15. Assercja `trace`: ścieżka zgodna spełnia ją w oknie, ścieżka rozjazdu spełnia `or_else`, brak obu daje
    naruszenie.

**Sonda Ecto — zrobiona**

Odpowiedź i jej granice są wyżej. Do bootstrapu wchodzi jako **test, nie jako notatka**: repo prototypu
nadpisuje `prepare_query/3`, wyciąga tabele z `from` i `joins` (z `__schema__(:source)` dla joinów), a test
sprawdza, że zapytanie z joinem przez granicę modułu jest widziane. To jest jednocześnie szkielet checka,
który §5–6 odkłada — leży gotowy, wyłączony, i włącza się w dniu, w którym trigger zadziała.

Ręcznie, do oglądania: `docker compose up -d`, `mix deps.get`, `mix ecto.setup`, `mix test`,
`mix pns.check`, `mix pns.graph`, plus celowe zepsucie `publishes:` żeby zobaczyć komunikat.

## Ryzyka, uczciwie

- **Deklaratywny bootstrap providera jest najbardziej niepewnym elementem infrastruktury.** Rozpoznanie
  wpisuje pokrycie i ergonomię Zitadela jako rzeczy do sprawdzenia w PoC, nie do wzięcia z dokumentacji. Jeśli
  zasiew nie da się zrobić bez klikania, środowisko przestaje stawać jedną komendą, co jest tu głównym
  kryterium. Fallback: Keycloak z importem realmu.
- **Tracer kompilacji dla `publishes:`.** Notatki §2 mówią wprost, że makro nie czyta ciała funkcji, więc to
  wymaga tracera w `elixirc_options`. Fallback: analiza po kompilacji w `mix pns.check` na tym, co tracer
  zebrał w osobnym przebiegu — ta sama reguła, słabsza granulacja, późniejszy moment wymuszenia.
- **„Przykład jest testem" może wyjść słabsze, niż §18 twierdzi.** Brama „reguła bez przykładu" jest
  prostym warunkiem. Ale wykonanie przykładu przeciw funkcji, której kontrakt celowo nie zna w czasie
  kompilacji, wymaga rozwiązania w runtime'ie testów. Jeśli wychodzi z tego generator, trzeba to zapisać.
- **Warstwa web to jedyne miejsce, gdzie ten spike dotyka otwartej decyzji.** Mitygacja jest w rozmiarze:
  dwa wejścia, ręcznie, i zapis w `README`, że to nie jest dowód w sprawie REST vs GraphQL.
- **Elixir 1.18.4 raportuje kompilację pod OTP 25, a działa na OTP 28.** Zwykle bez znaczenia; rozjazd
  wersji Obana, Ecto i `oidcc` sprawdzam na `mix deps.get`, nie zakładam.
- **`boundary` na jednym projekcie z dwoma drzewami modułów** jest jego przypadkiem użycia, ale `PNS` jako
  „pakiet" wewnątrz aplikacji wymaga jawnych `deps` i `exports`.

## Środowisko, sprawdzone 4 sierpnia

Elixir 1.18.4 / OTP 28, Docker 28.0.4, port 5432 wolny, `phx_new` 1.8.0, hex 2.2.2. Materiał warsztatowy na
miejscu: `~/Projects/ai/taxvision-process-native/workshop_output/02-event-storming.md`.

## Na koniec

`README.md` prototypu: instrukcja uruchomienia, zapis trzech rozstrzygnięć z góry tego dokumentu i sekcja
**Findings** — co trzeba było dołożyć do wyniku warsztatu, żeby dał się skompilować w kontrakt: typy
payloadów, ścieżki błędów, niezmienniki, klucze idempotencji, przykłady do reguł. To bezpośredni test
twierdzenia 3 i materiał do decyzji o pilocie.

Cztery rzeczy wracają do repo kontekstu jako zmiany, nie jako raport:

| Ustalenie | Gdzie wraca |
| --- | --- |
| Odpowiedź o hook Ecto | trigger §5–6 w decyzji 008 — decyduje, czy odroczenie jest bezpieczne |
| Zitadel czy Keycloak na deklaratywnym bootstrapie | rozpoznanie providerów w dokumencie o tożsamości |
| Tracer czy analiza po kompilacji | notatki §2 |
| Findings z kompilacji warsztatu | notatki §1, i wprost do wyceny pilota |

Notatki §13 nadal mówią `Users and sessions — phx.gen.auth, generated`, a ADR §16–17 nadal mówi
`WorkOS wrapped`. Oba są sprzeczne ze szwem i dokument o tożsamości sam to odnotowuje jako niepoprawione.
**W tym prototypie obowiązuje szew** — i przejście tego bootstrapu jest najlepszym momentem, żeby tamte dwa
zdania poprawić, bo wtedy poprawka będzie opisem czegoś, co stoi.
