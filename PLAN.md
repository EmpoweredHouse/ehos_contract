# Plan pracy

Zakres produktu, warunki oceny i stan recenzji żyją w rekordzie:
`~/Projects/ai/empowered-house-context/decisions/009-pns-runtime-architecture.md`; założenia, które ten
prototyp waliduje, są w [`docs/adr/architecture.md`](docs/adr/architecture.md). **Ten plik to lista roboty** i tylko tu jest
aktualizowany stan.

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
   nieszkodliwe (autoryzacja idzie nagłówkiem/cookie, nie parametrem), ale dla **każdego** przyszłego
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
(`nav`, `table`, `form`, `button`), zero frameworku — bezpieczne, bo `root_layout` zastępuje **całą**
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
bundle (`priv/static/assets/app.js`, zminifikowany, 144KB) jest **commitowany**, nie budowany przy
`mix compile` konsumenta — pakiet ścieżkowy nie ma jak uruchomić kroku budowania za kogoś, więc
`esbuild` jest `runtime: false` i potrzebny tylko temu, kto edytuje JS (`mix assets.build`).

**Ślepy zaułek, zanim wyszło na jaw dlaczego**: pierwsza wersja serwowała bundle przez
`forward "/assets", Plug.Static, ...` zagnieżdżone w tym samym `scope` co ekrany — więc dziedziczyło
`pipe_through :browser` hosta, `protect_from_forgery` włącznie. `Plug.CSRFProtection` ma wbudowaną
ochronę przed cross-origin `<script>` i **odmawia serwowania JavaScriptu przez trasę objętą CSRF**,
z zasady, niezależnie od tego, czy request faktycznie jest złośliwy
(`Plug.CSRFProtection.InvalidCrossOriginRequestError`). Objawiało się jako 403, zamaskowane w dodatku
przez brak skonfigurowanego `render_errors` w hoście demo — dopiero jawny error view ujawnił prawdziwy
wyjątek. **Poprawka zgodna z tym, jak robi to każda wygenerowana aplikacja Phoenix**: statyczne assety
serwuje się na poziomie Endpointu, przed routerem, nie przez trasę. `pns_dashboard/2` już tego nie robi
— zamiast tego jego moduledoc **wymaga jednej linijki w Endpointzie hosta** (`plug Plug.Static, at:
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
— w tym ostatnim **tylko klucz konfiguracyjny**, bez startowania procesu `Agent`, bo `pns_prototype` nie
montuje jeszcze żadnej trasy `pns_web` (`runtime: false`, zero drzewa nadzoru Phoenixa) i uruchomienie
procesu, którego nikt nie woła, byłoby zgadywaniem topologii, nie fundamentem.

**`:read_only` przestał być martwym rozróżnieniem.** Od fundamentu istniały dwa poziomy dostępu, ale
ekran 1 renderuje to samo dla obu. Ekran 2 jest pierwszym miejscem, gdzie różnica robi coś: `:all` widzi
formularze grant/revoke/invite, `:read_only` widzi tylko listę. **Sprawdzane dwa razy, nie raz** — ukryte
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
skopiowana ręcznie w dwóch miejscach) — więc **`Duration` dołączony do `exports:` w `pns.ex`**, żeby
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
testowym haczykiem. Zamiast tego: **jeden test integracyjny przez prawdziwy DB** (jeden przebieg,
zatwierdzony od razu przez handler — `:satisfied`, plus naturalnie nieużyta ścieżka `case_rejected` →
untraversed, bez żadnej sztuczki), i **osobne testy `render/1` wprost**, przez
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
reconnect, więc **zero osobnego Pluga do przechowywania tokenu w sesji**. `on_mount`
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
  odpala krok `test` w `dev`, nie w `test`, i pada. **`packages/pns_core` ma tę samą lukę** — dziś działa
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
bramy kompilacyjnej sprawdzała legalność zbioru enum w **tej samej** funkcji, która sprawdza „czy to
w ogóle jest typ payloadu" — więc każdy nielegalny zbiór (pusty, z duplikatem, ze złym typem elementu)
wywalał się z ogólnym komunikatem „nie jest typem payloadu", zanim druga, bardziej szczegółowa pętla
w ogóle dostała szansę się odezwać. Druga pętla była martwym kodem od pierwszego commita. Naprawione
rozdzieleniem: pierwsza sprawdza wyłącznie **kształt** (`{:enum, lista}`), druga **legalność
zawartości** tej listy — złapane mutacyjnie, nie przeglądem: cofnięcie rozdzielenia wywaliło dokładnie
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
przebieg (wyklucza naruszenie), bo **którakolwiek** awaitowana zależność padła — mimo że trasa chciana
była osiągalna przez cały czas i po prostu się nie zdarzyła.

Zapytany o rozstrzygnięcie w rozmowie, nie w kodzie: **zostawić dzisiejsze zachowanie.** Kontrakt mówi
„X albo Y", a Y było niemożliwe — to wystarcza jako powód wstrzymania werdyktu, nawet gdy X nie
zależało od niczego; węższe odczytanie (zawieszać tylko, gdy KAŻDA wciąż-możliwa trasa była
zablokowana) było na stole i odrzucone. `@tag :known_defect` zdjęty z testu asertującego węższe
odczytanie — usunięty, nie zostawiony czerwony na przyszłość, której teraz nikt nie planuje; test
pinujący dzisiejsze zachowanie jako **potwierdzone** dostał datę i uzasadnienie w komentarzu.
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
(ten sam warunek co check), `PNS.Trace.evaluate/3` liczy **jeden element na wartość `identity`
zdarzenia `from`** w przebiegu, każdy z własnym oknem od własnego najwcześniejszego `from`. Trafienie
`eventually`/`or_else` łączy się z elementem po **tych samych wartościach pól `identity` w jego własnym
payloadzie** — trafienie bez tych pól nie rozwiązuje żadnego elementu. To jest kierunek asekuracyjny:
fakt, którego nie da się odróżnić od elementu, który miał rozwiązać, nie rozwiązuje go przez
przypadek. Jeden werdykt przebiegu to teraz **najgorszy z werdyktów jego elementów** — `:violated`
jeśli którykolwiek element ma zamknięte puste okno, inaczej `:pending` jeśli którykolwiek wciąż otwarte,
inaczej `:suspended` jeśli którykolwiek wykluczony, inaczej `:satisfied` — kwantyfikator generalny, bo
obiecane było *każdy*, nie *któryś*. Zwykły przypadek (`identity` = `instance`) jest nietknięty: to samo
zapytanie, ta sama funkcja, ten sam koszt.

**Jedna świadoma strata informacji: `via: nil`, gdy elementy zamknęły się różnymi trasami.** Przebieg
spełniony częściowo przez `eventually`, częściowo przez `or_else` nie zgaduje, którą trasę wypisać —
to jest pytanie warsztatowe, nie inżynierskie, i moduledoc mówi to wprost.

**Nie zamyka Rehmedowego przypadku, który to znalazł.** Rozliczenie płatnika ma **drugą**, osobną lukę
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

Eskejp separatora był tagowany, nie poprawiony: `PNS.Instance` zamienia `|` na `%7C` i **zostawia `%`
w spokoju**, więc wartość zawierająca dosłowny tekst `%7C` daje ten sam klucz przebiegu co wartość
zawierająca `|`. `PNS.Job` odziedziczył ten sam kształt na `:`/`%3A`. Powodem tagu, nie poprawki, była
cena migracji: poprawka zmienia format każdego `instance_id` i każdego klucza idempotencji, jaki
kiedykolwiek zapisano, a stare wiersze zostają w starym kodowaniu.

**Sprawdzone `psql` przed poprawką, nie założone: migracji nie było z czego robić.** `pns_events` i
`oban_jobs` mają `0` wierszy w `dev` i w `test`, a żadne wdrożenie poza tym repozytorium tego
obwodowania nie czyta — TaxVision i Rehmed są danymi testowymi, nie produkcją, więc „przeformatowane
klucze leżą w tabelach idempotencji klientów" było ryzykiem przyszłym, nie faktem o dzisiejszym stanie.
Cena, którą tag nazywał, wynosi dziś zero, i to jest właściwy moment na zamknięcie — każdy dzień
dłużej z prawdziwym ruchem podnosi tę cenę, nigdy jej nie zmniejsza.

Poprawka: `%` eskejpuje się jako `%25` **przed** eskejpowaniem separatora, w obu miejscach
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
kod: `test/trace_edges_test.exs` ma cały blok `describe "a window of length zero"`, który **celowo**
wykorzystuje dzisiejszą tolerancję zera, żeby przypiąć zachowanie ewaluatora w chwili, gdy deadline
pokrywa się z otwarciem okna — a sam moduledoc pliku mówi wprost „read every test below as a
description of what happens, never as an argument that it should".

Rozstrzygnięcie: **zero zostaje legalne, ujemna liczba nie.** Zero ma sensowne odczytanie — „musi się
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
uruchamia teraz **dwie** suity: 44 testy tutaj i 285 w `packages/pns_core`.

### `PNS.Migrations` — i znacznik wersji powstał, zanim był potrzebny

Pięć tabel silnika leżało w `priv/repo/migrations/` gospodarza, wymieszanych z migracjami TaxVision,
a Oban stał **jedną linijkę wyżej w tym samym katalogu** i robił dokładnie odwrotnie. Schematy i
wszystkie zapytania są w pakiecie, więc aplikacja utrzymywała kopię kształtu, którego nie posiada.

Wersjonowanie w kształcie Obana, z wersją zapisaną w komentarzu na `pns_events`. Na wersji 1 nie ma
z czego migrować i **właśnie dlatego mechanizm wchodzi teraz**: pierwsza zmiana schematu jest momentem,
w którym jest już za późno, bo wtedy każdy konsument siedzi na nieoznaczonym `create` i nie ma stanu,
od którego można by ruszyć.

`V01` tworzy **kształt docelowy**, nie historię. `process` i `instance_id` są kolumnami `pns_events` od
pierwszego `create`; to, że doszły dzień później, jest faktem o tym repozytorium, nie o czyjejś bazie.

**Sprawdzone `pg_dump` przed i po, w `dev` i w `test`, oraz przeciwko bazie pakietu:** pięć tabel, ich
kolumny, kolejność kolumn, wartości domyślne, ograniczenia i trzynaście indeksów są identyczne co do
bajtu. Jedyna różnica to `COMMENT ON TABLE public.pns_events IS '1'` — czyli sam mechanizm.

Tabele Obana zostają Obana. `up/1` **nie opakowuje** `Oban.Migration.up/1`: opakowanie związałoby naszą
wersję z jego, ukryłoby aktualizację, o której konsument musi zdecydować sam, i pękłoby u konsumenta,
który już używa Obana do własnej roboty.

### Suita silnika stoi bez klienta — i to jest 87% suity

Nie wiedzieliśmy dotąd, ile z testów bada silnik, a ile TaxVision. Teraz wiadomo, bo szew jest
fizyczny: **289 testów w pakiecie, 44 tutaj** (z tego 4 `:known_defect`, wszystkie w pakiecie i wszystkie
nadal czerwone). Sześć plików zostaje przy kliencie i każdy z powodu, który da się nazwać:

| Plik | Dlaczego zostaje |
| --- | --- |
| `periods_test.exs` | okresy to domena TaxVision, nie mechanizm |
| `identity_seam_test.exs` | trzy poziomy IAM na **krawędzi żądania klienta**; skanuje też moduły `:pns_prototype` i konfigurację gospodarza |
| `contract_examples_test.exs`, `rehmed_contract_examples_test.exs` | przykłady z kontraktów klienta |
| `declared_shape_test.exs` | **nowy, wydzielony z `graph_test.exs`** — jego assercje są o modelowaniu `Rehmed.Contracts.ClinicalVisit`, nie o rendererze: że notatka nie jest zdarzeniem, że wejście do gabinetu to inny fakt niż przyjście do przychodni, że dwa okna zagnieżdżają się na jednym celu. Przepięte na wymyśloną fiksturę **nadal by przechodziły i nie sprawdzałyby już niczego** |
| `docs_test.exs` | pilnuje `docs/contract.md`, patrz dług niżej |

### Trzy rzeczy, które wyszły dopiero przy przenoszeniu

1. **`docs/contract.md` jest artefaktem pakietu trzymanym jako artefakt gospodarza.** Test bram
   kompilacyjnych pojechał do pakietu, dokument został — bo wskazują na niego po tej ścieżce `CLAUDE.md`,
   `README.md`, dwa skille i dwie destylacje, a `mix pns.docs` rozwiązuje ją względem katalogu roboczego.
   Skutek: `docs_test.exs` czyta teraz **przez szew**, po ścieżce `packages/pns_core/test/…`. Działa
   i jest brzydkie. Do zrobienia razem z przeniesieniem dokumentu i `--path` w tasku.
2. **Fikstury nie miały trzech kształtów, które miał kontrakt klienta**, i dopiero przenoszenie to
   pokazało: procesu bez `trace`, procesu bez `external`, przebiegu z **dwóch** pól z `cadence`, oraz
   obietnicy z `or_else`, której drugie zakończenie jedzie przez kolejkę. Bez tego ostatniego nie da się
   odróżnić „jeszcze nie" od „nigdy" — a to jest jedyny powód, dla którego werdykt `:pending` istnieje.
   Stąd `ProcessShapes.Bare` i `ProcessShapes.Promised`. **Fikstury urosły, testy nie zmalały.**
3. **`ContractExamples` mieszkał w `test/support/` gospodarza**, więc własne fikstury silnika nie mogły
   sprawdzić swoich `example` bez pożyczenia modułu z drzewa klienta. Wjechał do `lib/` jako
   `PNS.ContractExample`, tak jak `Oban.Testing` siedzi w `lib/`: suita konsumenta musi go zawołać, a
   moduł kompilowany tylko pod `MIX_ENV=test` w tym pakiecie u nikogo innego nie istnieje.

Do tego jedna rzecz o konfiguracji, znów: **path dependency nie wciąga konfiguracji ani `test/support/`
zależności** — pakiet w drzewie gospodarza kompiluje się bez swoich fikstur, więc `mix pns.check`
w tym projekcie przestał raportować rig i bramę uniwersalności. To jest poprawne (`pns.check` gospodarza
ma mówić o kontraktach klienta) i było niewidoczne, dopóki fikstury leżały tutaj.

## Dopisek 21 sierpnia — brzegi silnika: trzy usterki, cztery ciche zielenie i jedno znalezisko spoza listy

TaxVision i Rehmed przejeżdżały wyłącznie **wygodnym środkiem** każdego okna i każdego typu. Ten dopisek
jest o brzegach. 324 testy, `mix check` zielony, ostrzeżenia nadal cztery plus jedno z 19 sierpnia.

### Naprawione — trzy usterki, każda z testem, który przed poprawką jest czerwony

1. **Klucz idempotencji sklejał wartości `identity` dwukropkiem i nie eskejpował niczego.** Przy
   `identity: [:a, :b]` wartości `("x:y", "z")` i `("x", "y:z")` dawały **jeden** klucz. Skutek jest
   cichy w najgorszy możliwy sposób: drugi fakt czyta się w tabeli idempotencji klienta jako powtórzenie
   pierwszego, jego handler **nigdy nie rusza**, żaden wiersz tego nie odnotowuje, a oba zdarzenia leżą
   w logu jak obsłużone. `PNS.Instance` eskejpował swój `"|"` od pierwszego dnia — dwa mechanizmy
   robiły to samo i tylko jeden miał rację.
2. **`PNS.Check.finer?/2` porównywał klucze jako listy**, więc `[:b, :a]` wobec `[:a, :b]` wychodziło
   „drobniejsze”. Fałszywy pozytyw akurat na sprawdzeniu, którego cała wartość polega na byciu
   wiarygodnym co do **kierunku** pomyłki — a jedyna poprawka, po którą sięgnie czytelnik, czyli
   przestawienie pól w keywordzie, nie zmienia nic. Teraz zbiory.
3. **Klucz rozłączny z `instance` nie był łapany przez nic**, i jest groźniejszy od drobniejszego:
   klucz idempotencji bierze się z `identity` i **z niczego więcej**, więc fakt, którego klucz nie
   zawiera przebiegu, skleja dwa przebiegi w jeden. Osobne sprawdzenie
   (`PNS.Check.facts_not_keyed_by_their_run/1`), nie gałąź sąsiada: inna populacja — **każde** zdarzenie,
   nie tylko kotwica assercji; inna konsekwencja — pominięty skutek, nie za łagodny werdykt; inna
   poprawka — na zdarzeniu, nie na procesie.

Oba sprawdzenia biorą teraz jawną listę kontraktów. Fikstura zbudowana po to, żeby być błędem
modelowania, weszłaby inaczej do rejestru i wisiała ostrzeżeniem na **każdym** `mix pns.check` w tym
repozytorium — a to jest sposób, w jaki sprawdzenie się wyłącza.

### Cztery ciche zielenie, każda z linią w `pns.check`

4. **Dwa kontrakty deklarujące tę samą nazwę zdarzenia.** Pytanie brzmiało o `declared_events/0`
   i `process_of/1` — **żadne z nich nie jest dwuznaczne**: pierwsze tagguje każde zdarzenie jego
   kontraktem, drugie jest generowane per kontrakt i widzi tylko własne. Dwuznaczne jest **każde
   wyszukanie po samej nazwie**, a dispatch jest jednym z nich: `handlers_for/1` filtruje po `event`
   i nie patrzy na `contract`. Pokazane testem, nie argumentem — `test/check_ambiguity_test.exs`
   emituje `item_measured` z kontraktu, którego **nie ma w rejestrze** i który nie dzieli z rigiem nic
   poza stringiem, a **oba handlery riga się wykonują**, w tej transakcji, na payloadzie, którego rig
   nigdy nie zadeklarował. Cicho scalają się jeszcze dwaj czytelnicy: `PNS.Graph.overlay/1`
   i `PNS.Check.stage_index/0` indeksują węzły po nazwie zdarzenia. `:error`.
5. **Dwa kontrakty deklarujące tę samą nazwę procesu.** `"<process>|<values>"` nie niesie kontraktu,
   więc to nie jest zbieżność, tylko **jeden string**. `overlay/1` liczy przebiegi po nazwie procesu,
   czyli obcy emitujący cokolwiek **poprawia twoje pokrycie**. `PNS.Trace` jako jedyny filtruje po
   kontrakcie — więc assercje zostają uczciwe obok liczb, które nie są, a to jest gorsza mieszanka niż
   jedno albo drugie osobno. `:error`.
6. **Zero kontraktów** dawało `0 errors, 0 warnings, 0 notices`, czyli dokładnie tę samą linię co czyste
   repozytorium. `:warn`, i wypisuje skonfigurowane aplikacje, bo błąd jest tam, a nie w kontraktach.
7. **`trace` bez `within` nie ma przypadku porażki**: cokolwiek po `from` ją spełnia, a przebieg bez
   niczego zostaje `:pending` **na zawsze**, bo okno, które musi minąć, nigdy się nie zamyka. Przypięte
   oceną rok po fakcie. `:info`, zgodnie z notatką zapisaną w `PNS.Trace` przy pisaniu ewaluatora.

Żadne z czterech nie odzywa się na materiale tego repozytorium i **każde ma test kontrolny, który to
mówi** — inaczej jedynym dowodem na sprawdzenie byłaby jego własna cisza.

### Przypięte, nie zmienione

`test/trace_edges_test.exs`, `test/payload_edges_test.exs`, `test/scale_edges_test.exs`.

**Jedna asymetria i jest świadoma:** trafienie **dokładnie** w termin jest w oknie (`in_window?`
porównuje `!= :gt`), zegar **dokładnie** na terminie jest już po (`pending?` porównuje `== :lt`). Obie
połowy przypięte osobno, bo czytając którąkolwiek samą chce się dopasować ją do drugiej. Cena jest
nazwana: zostaje jednoinstantowy wyścig, w którym zdarzenie zapisane mikrosekundy za późno jest sądzone
przeciw oknu, które właśnie się zamknęło.

Reszta, skrótem: trafienie w tej samej mikrosekundzie co `from` spełnia, a mikrosekundę wcześniej nie;
dwa `from` w jednym momencie to nadal **jeden** werdykt; `from` z przyszłości czeka, a nie jest sądzone;
awaria jest domknięta na **obu** końcach okna; pusty `:string` jest legalny tam, gdzie pusty `:id` nie
jest, i to nie jest niespójność; 28-cyfrowy integer przeżywa log; offset normalizuje się do UTC i **nie
da się go potem odzyskać**; `:enum` przyjmuje dowolny atom i dowolny string; **atom wraca z logu jako
string**, więc `case` po atomach przestaje pasować w dniu, w którym handler staje się asynchroniczny;
obie granice okresu raportu są domknięte, więc dwa sąsiadujące okresy liczą zdarzenie na styku **dwa
razy**.

Skala: 10 000 zdarzeń w jednym przebiegu → jeden werdykt, zakotwiczony na **najwcześniejszym**;
50 000 przebiegów → 50 000 w mianowniku. Cztery testy, 1,1 sekundy.

### Zostawione, z powodem

| Co | Dlaczego nie ruszone |
| --- | --- |
| **~~`within: {0, :day}` się kompiluje~~ — ✅ zamknięte 21 sierpnia** | Rozstrzygnięcie po drodze: zero zostaje legalne (czyta się jako „w tej samej chwili”, przetestowane), tylko ujemna liczba jest odrzucana. `PNS.Duration.t` poprawione na `non_neg_integer()`. Patrz „Dopisek 21 sierpnia (3)” wyżej |
| **~~Awaria zależności zadeklarowanej wyłącznie przez `or_else` zawiesza przebieg~~ — ✅ rozstrzygnięte 21 sierpnia, bez zmiany kodu** | Zapytany, kto ma decydować o tym osądzie — nie ma tu prawdziwego process ownera, fikstura jest wymyślona — zdecydowałem zostać przy dzisiejszym zachowaniu: kontrakt mówi „X albo Y", a Y było niemożliwe, i to wystarcza jako powód wstrzymania werdyktu, nawet gdy X nie zależało od niczego. `@tag :known_defect` zdjęty, bo asercja przeciwna nie ma już czekać na nic — patrz „Dopisek 21 sierpnia (6)" niżej |
| **Trzy assercje samozwrotne** | `from == eventually` i `from == or_else` **nie mogą zawieść** i kompilują się; `eventually == or_else` zawieść może, ale trwale zeruje połowę rozbicia „przez eventually / przez or_else”, czyli dokładnie tę informację, dla której werdykt niesie `via:`. Przypięte, nie zabronione — brama kompilacyjna to decyzja słownikowa |
| **~~Eskejpowanie separatora nie jest odwracalne~~ — ✅ zamknięte 21 sierpnia** | Migracja, przez którą nie było jak przejść, okazała się nie istnieć: `pns_events` i `oban_jobs` są puste w `dev` i w `test`, i nigdzie indziej nie ma wdrożenia, które by to obwodowanie czytało — TaxVision i Rehmed są danymi testowymi, nie produkcją. Sprawdzone `psql` przed poprawką, nie z pamięci. Patrz „Dopisek 21 sierpnia (4)” niżej |

### Znalezisko spoza listy: eskejp, który nie jest eskejpem — ✅ zamknięte 21 sierpnia, patrz dopisek (4)

Wyszło przy pisaniu testów payloadu, nie z listy, przeciw której były pisane. `PNS.Instance` zamienia
`|` na `%7C` i **zostawia `%` w spokoju**, więc odwzorowanie nie jest różnowartościowe: wartość
zawierająca dosłowny tekst `%7C` daje ten sam klucz przebiegu co wartość zawierająca `|`. To jest ta
sama usterka, którą naprawia pierwszy commit tej serii, tylko węższa — i **`PNS.Job` ją odziedziczył**,
bo dostał to samo eskejpowanie celowo, żeby oba mechanizmy się zgadzały.

`@tag :known_defect`, nie poprawka wtedy: eskejpowanie `%` jako `%25` zmienia format **każdego
`instance_id`, jaki kiedykolwiek zapisano**. Stare wiersze zostają w starym kodowaniu, więc przebiegi
rozjeżdżają się na wdrożeniu, a po stronie joba przeformatowane klucze leżą w tabelach idempotencji
**klientów**. To była decyzja migracyjna, nie poprawka błędu — dopóki nie było wiadomo, czy migracja
jest z czego robiona.

**Zamknięte 21 sierpnia, patrz dopisek (4) niżej: sprawdzone `psql`, nie z pamięci — migracji nie ma z
czego robić.** `pns_events` i `oban_jobs` są puste w `dev` i w `test`, a żadne wdrożenie poza tym
repozytorium nie czyta tego obwodowania — TaxVision i Rehmed są danymi testowymi. Koszt migracyjny, który
uzasadniał tag, dziś wynosi zero.

### Drobiazg do rozstrzygnięcia przez człowieka

Przykład w moduledoku `mix pns.report` mówi `--until 2026-07-31T23:59:59Z`. Granice są domknięte, więc
ten przykład **gubi wszystko, co wydarzyło się w ostatniej sekundzie miesiąca**. Nie ruszone, bo nie
wiem, czy przykład ma być poprawny, czy poglądowy — a jeśli poprawny, to poprawną wartością jest
`23:59:59.999999Z`, co widać dopiero, gdy się wie, że kolumna jest `utc_datetime_usec`.

## Dopisek 20 sierpnia — silnik wyjęty do `packages/pns_core`, i ile to naprawdę kosztowało

`README.md` twierdził, że przeniesienie drzewa klienta to `git mv`, a `CLAUDE.md`, że tymczasowość jest
faktem, nie obietnicą. **Nikt tego nie sprawdził, więc wyciągnięcie było jednocześnie eksperymentem.**

**Dla `lib/` twierdzenie się obroniło**: `git mv lib/pns packages/pns_core/lib/pns`, własny `mix.exs`,
zależność `path`, i ani jedna linia w `lib/taxvision/` ani `lib/rehmed/` się nie zmieniła. `boundary`
pilnował tego szwu od pierwszego commita i szew okazał się prawdziwy.

**Ale trzy rzeczy wyszły dopiero przy próbie, i wszystkie są o konfiguracji, nie o kodzie:**

| # | Co pękło | Dlaczego to własność biblioteki, nie usterka |
| --- | --- | --- |
| 1 | `@repo Application.compile_env!(:pns_prototype, :repo)` w siedmiu modułach | **pakiet kompiluje się przed aplikacją, która go konfiguruje.** Każde wywołanie ostrzegało, że `Taxvision.Repo` nie istnieje — u prawdziwego konsumenta ostrzegałoby o jego repo. Biblioteka nie może trzymać referencji kompilacyjnej do modułu, którego użytkownik jeszcze nie napisał. Zamienione na `Application.fetch_env!/2` w runtime; **traci się sprawdzenie `compile_env!`, że konfiguracja nie zmieniła się od buildu** |
| 2 | `PNS.Registry.load!(app \\ :pns_prototype)` | domyślną była **jedyna aplikacja, jaka wtedy była**, więc pytanie nigdy nie padło. Po wyciągnięciu biblioteka z domyślną własną nazwą **skanuje samą siebie, nie znajduje kontraktów i raportuje zdrowy pusty graf** — `0 errors, 0 warnings, 0 notices`. Cicha porażka w stronę zieleni, ta sama rodzina co granulacja i jednostka liczby. Teraz `config :pns, applications: [...]`, a brak wpisu jest błędem, nie ciszą |
| 3 | fikstury w `test/support/` czytały nazwę aplikacji gospodarza | te same dwa wzorce co wyżej |

**Wniosek dla pakietu, nie dla tego repo:** granica modułowa была prawdziwa, a granica **konfiguracyjna**
nie istniała — nikt jej nie pilnował, bo w jednej aplikacji nie ma jej jak złamać. To jest dokładnie ta
klasa rzeczy, których nie da się sprawdzić inaczej niż wyciągnięciem.

Zostaje do zrobienia: `PNS.Migrations` (dziś pięć tabel silnika leży wymieszanych z migracjami TaxVision
w `priv/repo/migrations/`) i przeniesienie testów silnika do pakietu — **22 z 27 plików testowych
odwołuje się do `Taxvision`**, bo `boundary` nigdy nie objął `test/`. *(Oba zrobione 21 sierpnia —
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
   nie przekracza procesu. To jest zdrowe ograniczenie, ale trzeba je znać **przed** modelowaniem, nie po.
2. **~~`unverified` nie obejmuje `trace`.~~ ✅ zamknięte 21 sierpnia**, patrz „Dopisek 21 sierpnia (8)".
   `PNS.Conformance.verified_declarations/1` filtrowało wyłącznie `:cadence` i `:deadline`, więc **spornej
   assercji nie dało się wyłączyć z raportu dowodowego**. Tutaj obie liczby były mocne (ustawa i decyzja
   klienta z datą), więc nic złego się wtedy nie działo — ale mechanizm nie powstrzymałby gorszej pary.
3. **Assercja mierzy od momentu, w którym nam powiedziano, nie w którym się wydarzyło.** Okno biegnie od
   wpisu w logu. Przy procesie, którego istotą jest odraczanie zapisu, to jest przekłamanie w stronę
   optymistyczną. Kotwica została wybrana tak, żeby zapis był współczesny zdarzeniu — ale to jest wybór
   modelujący, a nie własność silnika, i następny klient może go nie mieć.

Rehmed nie ma tu kodu i nie będzie miał: to drzewo jest **wyłącznie kontraktami**, bo do sprawdzenia DSL
kod nie jest potrzebny. Wszystkie zdarzenia są `declared, never observed`, czyli dokładnie ten stan, który
`pns.check` raportuje jako `info` i który notes §5 opisuje jako normalny w trakcie wdrożenia.

### Drugi kontrakt Rehmed — rozliczenie płatnika. Cztery luki, jedna groźna

`lib/rehmed/contracts/payer_settlement.ex`, ten sam dzień. **Wart więcej niż pierwszy, bo jest miejscem,
w którym DSL się skończył** — a przy danych testowych to jest lepszy wynik niż kontrakt napisany gładko.

| # | Luka | Waga |
| --- | --- | --- |
| 1 | ~~Assercja drobniejsza niż przebieg nie jest łapana i myli się w stronę dobrych wieści.~~ **✅ zamknięte 21 sierpnia** — `PNS.Trace` liczy teraz per element, patrz „Dopisek 21 sierpnia (5)". Nie zamyka tego kontraktu: luka 2 wciąż blokuje napisanie tej assercji tutaj | było **to jest produkt**, teraz zamknięte jako mechanizm silnika |
| 2 | **Zdarzenie należy do jednego procesu, a obietnica potrzebuje dwóch.** Naturalną kotwicą jest *wizyta wykonana*, która należy do przebiegu wizyty. Scalenie procesów nie pomaga: jeden z dwóch liczników przestaje mieć sens | duże — to jest ta sama granica, o którą rozbił się pierwszy kontrakt, widziana z drugiej strony |
| 3 | **`instance` to nie „pola grupujące przebieg", tylko „pola znane w chwili zdarzenia"** — i DSL nigdzie tego nie mówi. `E-85` rejestracja u płatnika dzieje się przed wykonaniem, a okres rozliczeniowy nie jest wtedy znany. TaxVision tego nie ujawnił, bo miesiąc księgowy jest znany przed jakąkolwiek pracą w nim | średnie — kandydat na zdanie w `docs/contract.md` |
| 4 | ~~`unverified` nie obejmuje `trace`~~ — **✅ mechanizm zamknięty 21 sierpnia**, patrz „Dopisek 21 sierpnia (8)". `H38` (przyjęcie płatnika w 7 dni) wciąż nie jest napisane w `payer_settlement.ex` — blokuje ją luka 2 (kotwica w innym procesie), osobna od tej | było **z obserwacji staje się pozycją backlogu** |

Dwie rzeczy, które przy okazji wyszły na plus i warto je znać jako precedens:

- **Zależność obsługiwana ręcznie nie ma obserwowalnej awarii.** `external` jest zadeklarowany i **żadne
  zdarzenie nie ma `depends_on`** — bo awaria to człowiek, który czegoś nie przepisał, a `:suspended` bierze
  się z **zaobserwowanej** niedostępności. Deklaracja bez `depends_on` jest tu poprawną odpowiedzią, nie
  niedbalstwem.
- **`retain: :persist` na polu `:string` bywa decyzją, nie zaniechaniem.** Powód wykluczenia wizyty
  z faktury musi być czytelny, więc `:hash` spełniłby kontrolę retencji i zniszczył deklarację. Kontrast
  z kontraktem klinicznym, który nie ma ani jednego `:string`, jest tu celowy i pokazuje, że kontrola
  retencji potrzebuje **czytelnika, nie reguły**.

### Trzeci kontrakt Rehmed — rozliczenie wizyty. Pieniądze, i czym one naprawdę są

`lib/rehmed/contracts/visit_settlement.ex` plus jedyny kawałek kodu domenowego w tym drzewie,
`lib/rehmed/settlement.ex`. Napisany po to, żeby zmierzyć się z pieniędzmi zamiast je omijać — pierwsze
dwa kontrakty Rehmed omijały, a **TaxVision omija też**: `turnover_matched_with_invoice` paruje obrót
z fakturą po identyfikatorach i nie niesie ani jednej kwoty, w produkcie **księgowym**. Trzy kontrakty,
zero kwot, i nikomu to nie wyglądało na lukę.

**Wniosek nie brzmi „brakuje typu pieniężnego".** Grosze w `:integer` to poprawna reprezentacja pieniędzy
— sumy i porównania są dokładne, a alternatywa, która wygląda przyjaźniej (dziesiętna liczba jako tekst),
traci arytmetykę i ląduje w `:string`, czyli w typie, który znaczy *tekst wpisany przez człowieka* i jako
jedyny odpala kontrolę retencji.

> **Brakuje sposobu na powiedzenie, co dana liczba liczy.** `task_count` liczy taski, `recipients`
> liczy adresatów, `amount_minor` liczy grosze — i wszystkie trzy są `:integer`, nierozróżnialne.
> Drugi kontrakt wpisujący **złote** w pole, w które pierwszy wpisuje grosze, kompiluje się, emituje
> i jest źle zsumowany w raporcie. **Żadna brama tego nie widzi** — ta sama klasa cichej,
> prawdopodobnie wyglądającej porażki co granulacja assercji wyżej.

Obejście zastosowane w kontrakcie to konwencja nazewnicza: każda kwota kończy się na `_minor`.
**Konwencja nie jest gwarancją** i nazwanie jej gwarancją byłoby tym rodzajem twierdzenia, które to
repozytorium ma wykrywać u innych.

**Jeśli kiedyś dokładamy typ, to `:decimal`, nigdy `:money`.** `:decimal` jest kształtem — dokładna
liczba dziesiętna, która nie może być floatem — i potrzebuje jej fizyka, stawki podatkowe i wagi tak samo
jak ceny. `:money` nazywa rzecz, którą rozpoznaje księgowy, czyli powtarza błąd `:period`. Próg dowodowy
niech będzie ten sam, który zabił `:period` — **liczenie**: przez cztery kontrakty pola, które użyłyby
`:decimal`, to **trzy, wszystkie w tym jednym pliku**. Za mało. I powodem, gdy przyjdzie, będzie
**dokładność, nie pieniądze**.

Trzy rzeczy przy okazji:

- **Silnik nigdy nie czyta wartości payloadu.** `identity` i `instance` biorą pola jako klucze,
  `PNS.Emitter` sprawdza kształt — liczbę czyta wyłącznie `rule` przez `example`, a `given:` jest
  **nietypowane**. Więc pieniądze w przykładach są całkowicie poza zamkniętym zbiorem. To osłabia całą
  panikę o typ pieniężny i warto to wiedzieć, zanim ktoś zacznie go dokładać.
- **Atrybut, który istnieje tylko czasem, nie może być polem** — drugi raz. Pole zadeklarowane musi być
  na każdej emisji, więc opcjonalność wyraża się **osobnym zdarzeniem**. Tu boli mocniej niż przy dopisku
  ICD-9: `DEC-05` chce, żeby każda linia płatności nazywała swojego płatnika, a linia opłacona prywatnie
  nie ma płatnika do nazwania. **Przypadek mieszany jest w tym kontrakcie niewyrażalny** i jest to
  zapisane jako luka, nie zaklejone polem nullowalnym, którego DSL i tak by nie przyjął.
- **`rule`/`example` w drugiej domenie działa i jest wykonywane.** `test/rehmed_contract_examples_test.exs`
  używa tego samego generatora co TaxVision, cztery przykłady z **prawdziwymi liczbami klienta**
  (150 + 50 = 200, VLW 00:19:58). Sprawdzone mutacją: odwrócenie warunku w `decide/1` wywala trzy z pięciu
  testów. „Przykład jest testem" jest własnością DSL, nie oprzyrządowania jednego kontraktu — i teraz jest
  na to drugi dowód.

### 19 sierpnia — luka granulacji przypięta testem, i obrazek dla właściciela procesu — ✅ zamknięte 21 sierpnia, patrz „Dopisek 21 sierpnia (5)" wyżej

**Test, który pada na żądanie.** `test/trace_granularity_test.exs`. Cztery testy opisują dzisiejsze
zachowanie (trzy elementy obiecane, jeden dostarczony, raport mówi `satisfied`), plus kontrola pinująca
`violated`, żeby tamte nie przechodziły z nudniejszego powodu. Piąty, otagowany `:known_defect`
i wykluczony w `test_helper.exs`, twierdzi to, co być powinno — `mix check` zostaje zielony, a
`mix test --include known_defect` jest naprawdę czerwony. **Nowa fikstura nie była potrzebna:**
`ProcessShapes.Rig` już miał ten kształt (`submission_reaches_inspection` biegnie między dwoma
zdarzeniami per element w procesie kluczowanym po sprawie) i nikt tego nie zauważył.

Ostrzejsza połowa znaleziska wyszła dopiero przy pisaniu testu: **trafienie nie musi dotyczyć tego samego
elementu, co otwarł okno.** Ewaluator szuka pierwszego wystąpienia celu po pierwszym wystąpieniu źródła
i **nigdy nie porównuje payloadów**.

**`PNS.Graph.declared_to_mermaid/2`** — kształt zadeklarowany jednego procesu: etapy jako tory, zdarzenia
w nich, zakończenia oznaczone, każda assercja jako strzałka z liczbą, zależność zewnętrzna na linii bez
grotu. `mix pns.graph --mermaid --process <nazwa>`.

**To nie jest graf odrzucony w etapie 4** i różnica jest rozstrzygająca, nie kosmetyczna: tamten rysował
krawędzie z rejestru handlerów, dla zespołu. **Kontrakt bez implementacji ma zero krawędzi**, więc tamten
obrazek dla `ClinicalVisit` to jedenaście nierozłączonych pudełek. Sekwencja kontraktu siedzi w `stages`,
`terminal` i `trace` — i żadne z tych trzech nie pojawia się na grafie handlerowym.

Zastrzeżenie zapisane przy funkcji: **obrazek łatwiej pokiwać głową niż poprawić.** Ma stać nad zdaniami
assercji, nie zamiast nich; miarą sesji jest liczba poprawek.

**Obrazek znalazł w kontrakcie trzy niedomiary w dwóch rundach, i to jest dowód o narzędziu, nie
o Rehmedzie.** Runda pierwsza: jedenaście pudełek, jedna strzałka — brakowało twierdzenia, że zamknięcie
kliniczne następuje po pracy, którą zamyka. Runda druga, po obejrzeniu PDF-a przez człowieka: brakowało
twierdzenia, że wywiad i zabieg poprzedzają wyjście pacjenta — **i brakowało samego początku wizyty**.
`E-40 Pacjent wszedł do gabinetu` nie był zadeklarowany, choć `E-51` (wyjście) był, a `AGG-01` wymienia
`E-27`, `E-40` i `E-51` jako **jedną rodzinę** przejść wywoływanych przez pacjenta. Wziąłem koniec
świadczenia bez jego początku.

Runda trzecia, ten sam czytelnik nad tym samym PDF-em: **kolejność wewnątrz gabinetu była zła, a jednej
notatki w ogóle nie było.** `E-49 Zapisano notatkę widoczną w recepcji` nie istniało w kontrakcie, a
`E-42 Powielono notatkę z poprzedniej wizyty` wisiało obok zabiegu, jakby było krokiem po nim — podczas
gdy `AGG-02` rysuje `C-19` i `C-20` jako **dwie krawędzie do tego samego stanu**: to jest wariant
wywiadu, nie trzeci krok. Etapy: `[:start, :interview, :treatment, :departure, :documentation, :closing,
:reporting]`.

Wzorzec we wszystkich trzech rundach ten sam i wart nazwania, bo się powtórzy: **strach przed jednym fałszywym
twierdzeniem o kolejności dał zero twierdzeń**, a te dwie rzeczy są trudne do odróżnienia na liście
deklaracji i trywialne do odróżnienia na rysunku. Etapy: `[:start, :delivery, :departure, :documentation,
:closing, :reporting]`. Trzy z sześciu mają jedno zdarzenie — to nie przypadek, tylko cena porządku
totalnego: „te w dowolnej kolejności, potem to jedno" kosztuje osobny tor na każdy moment.

**Jedna granica została jawnie sporna i tak ma zostać:** `:departure → :documentation` twierdzi, że
kodowanie ICD dzieje się po wyjściu pacjenta. Tablica sekwencjonuje `E-44` **przed** `E-51`, więc jako
opis intencji jest to nieprawda; transkrypty opisują odraczanie pod obciążeniem, więc jako opis praktyki
jest to prawda. To jest pytanie do klienta, nie rozstrzygnięcie dla nas.

**A `E-27 Klient pojawił się na wizycie` świadomie nie wszedł.** To jest poczekalnia — recepcyjne
*czeka na kanapie*, read model `R-03` — a `20-aggregates.md` ostrzega wprost, że mieszanie stanu
obecności fizycznej ze stanem przepływu pracy jest błędem, który popełniła paleta kolorów z tablicy.
`E-27` należy do procesu rezerwacji, którego nikt jeszcze nie napisał.


**Przeglądanie modułu nie wyłapało żadnego z trzech; rysunek wyłapał wszystkie.**

**Czwarta luka DSL, i jedyna z tych czterech bez obejścia: `stages` wyraża wyłącznie porządek liniowy.**
Prawdziwy kształt tej domeny to porządek **częściowy** — zamknięcie po wszystkim, reszta wzajemnie
nieuporządkowana. Lista faz jest porządkiem totalnym, więc wszystko nieuporządkowane musi dzielić tor,
a przez to **uporządkowania, które wewnątrz toru zachodzą, są niewyrażalne**. Granulacja, jednostka
liczby i porządek częściowy mają ten sam kształt: DSL przyjmuje deklarację mówiącą co innego, niż autor
sądzi, i nic tego nie sygnalizuje.

Renderer mówi o tym wprost — tor z więcej niż jednym zdarzeniem nosi w tytule `no order claimed inside`.
Bez tego pudełka bez strzałek czytają się jako *niedokończone*, a nie jako *świadomie nieuporządkowane*,
i te dwa odczyty zbierają zupełnie inne poprawki.

**Przy okazji naprawiony `within 24 hour`.** Liczba mnoga była wypisana ręcznie dla `:month` i `:day`,
reszta jednostek wpadała w gałąź ogólną. Przeniesione do `PNS.Duration.humanize/1`, czyli do modułu,
który i tak jest jedynym źródłem prawdy o jednostkach — `PNS.Report` deleguje. **Przeżyło cztery
kontrakty, bo żaden nie użył godzin aż do czwartego.**

## Stan na 6 sierpnia

221 testów, `mix check` przechodzi. Ostrzeżenia są **cztery i wszystkie celowe** (piąte doszło
19 sierpnia — patrz dopisek na górze):

1. `deadline` TaxVision bez potwierdzenia process ownera,
2. `deadline` z wymyślonej fikstury bramy uniwersalności,
3. **krawędź wsteczna** w stanowisku badawczym kształtów — kryterium odbioru 1.3,
4. **dwa handlery synchroniczne na jednym zdarzeniu** — kryterium odbioru 2.4.

Brak trzeciego albo czwartego byłby regresem, nie poprawą. Samo `mix pns.check` w środowisku dev pokazuje
jedno, bo fikstury żyją w `test/support/`.

Działa: kontrakt jako moduł Elixira z bramami kompilacyjnymi, dispatch po granicy transakcji, log zdarzeń,
`boundary`, szew tożsamości, nakładka declared vs observed z czterema stanami, **tożsamość instancji procesu
i liczniki w dwóch wymiarach (wystąpienia i przebiegi)**, **drugi kontrakt z obcej domeny bez ani jednego
nowego słowa w DSL**, **ocena assercji `trace` per przebieg — cztery werdykty z czterech**, **raport
nieprzejechanych ścieżek per przebieg**, **`publishes:` wiąże handler w runtime, nie tylko opisuje**,
**obie tożsamości wdrożenia haszują się kanonicznie, z jednego źródła**, **awaria handlera synchronicznego
zostawia ślad, a raport odróżnia „próbowane i nie udaje się" od „nigdy nie próbowano"**, **cykl w runtime
jest zatrzymany na obu ścieżkach dispatchu**, **kolejność handlerów synchronicznych jest odtwarzalna, a job
po znikniętym handlerze jest anulowany i zapisany**, **payload jest walidowany przeciw zadeklarowanym typom,
a `:timestamp` jest punktem w czasie po obu stronach kolejki**, **telemetria emituje to, czego nie widzi
nikt inny — handlera i naruszenie kontraktu**.

**Nie działa, bo nie zostało zbudowane — i to jest produkt:**

| Luka | Waga |
| --- | --- |
| `deadline` procesu jest zadeklarowany i **nie czyta go nikt** — jedyni czytelnicy to filtr, który go wyrzuca, i renderer, który by go wypisał; `deadline_at` w `PNS.Trace` pochodzi z `within`, czyli z innej deklaracji | to jest produkt — **zwężone 6 sierpnia**, patrz „Rozstrzygnięte 6 sierpnia" niżej |
| `cadence`'s „never observed" — **odrzucone 6 sierpnia**, patrz „Rozstrzygnięte 6 sierpnia" niżej. Sama deklaracja `cadence` zostaje: kosztuje zero kodu i raport już ją wypisuje. | zamknięte |
| ~~Zbiór wartości `:enum` nie jest deklarowalny~~ — **✅ zamknięte 21 sierpnia**, `{:enum, [...]}`, patrz „Dopisek 21 sierpnia (7)” | było drobne |

## Etap 1 — rdzeń weryfikacji

**1.1 Instancja procesu. ✅ zrobione 5 sierpnia.** `instance: [...]` w DSL, brama kompilacyjna: każde
zdarzenie procesu musi nieść pola instancji. Powód jest techniczny, nie sprawozdawczy — bez tego
„eventually Y" dopasuje Y z innego przebiegu.
*Odbiór:* assercja policzona dla dwóch równoległych przebiegów nie myli ich zdarzeń. **Spełnione** —
`test/instance_test.exs`, przebieg c-1 otwiera miesiąc, c-2 nie, i licznik per typ zdarzenia zaliczyłby oba.

Wyszło przy okazji, w kolejności ważności:

- `instance:` jest **wymagane na każdym procesie**, nie opcjonalne. Obie rzeczy, które czynią z tego produkt
  — ocena `trace` i nakładka — liczą się w obrębie przebiegu, więc brama opcjonalna byłaby dokumentacją.
- **Zdarzenie w dwóch procesach nie kompiluje się.** To warunek stopu z ADR §15 zrobiony mechanicznie: dwa
  procesy to dwie tożsamości przebiegu, a w logu jest na to jedna kolumna.
- **`trace` rozciągnięty na dwa procesy nie kompiluje się** z tego samego powodu.
- Brama znalazła jedno zdarzenie: `turnover_matched_with_invoice` nie miało `period`, więc meczowanie z lipca
  liczyłoby się jako postęp w sierpniu. Dopisane.
- Liczniki mają **dwa wymiary**: wystąpienia i przebiegi, plus mianownik „ile przebiegów w ogóle było".
  Krawędź przejechana 49 razy przez jedną firmę i raz przez 49 firm miały wcześniej identyczny licznik.
  Świadomie **liczba, nie lista** — które przebiegi milczą, to pytanie o konkretną firmę.
- Zdarzenia zapisane przed tym etapem nie mają tożsamości przebiegu i już jej nie dostaną; raport pisze
  „bez tożsamości przebiegu", nie „0 przebiegów". To ten sam problem, który przy wersjach kontraktu
  rozwiązuje stan `:historical`.

**1.2 Brama uniwersalności. ✅ zrobione 5 sierpnia — PRZESZŁA.** Drugi kontrakt z innej domeny, wyłącznie
kontrakt plus fake'i, bez implementacji.

Domena medyczna jest naturalnym wyborem, bo Rehmed startuje 10.08 — ale **materiału warsztatowego z Rehmed
jeszcze nie ma**, więc ten kontrakt jest świadomie wymyślony i jest tak oznaczony w pliku. Testuje
**słownik DSL, nie wiedzę o domenie**.
**Poprawka do samej bramy, 5 sierpnia:** kryterium „zero nowych słów" dowodzi, że DSL **opisze** inną
domenę — nie że silnik na niej **zadziała**. `PNS.Trace` i `PNS.Conformance`, zbudowane po przejściu bramy,
dostawały z kontraktu medycznego puste listy, więc ich uniwersalność była nieprzetestowana. **Brama obejmuje
od teraz mechanizmy, nie tylko słownik** — inaczej ten sam dryf wróci przy 1.6 i 1.7.

*Odbiór:* **zero nowych słów w DSL.** **Spełnione** — `UniversalityGate.TreatmentEpisode`
(`test/support/`, nie drzewo klienta, nie trafia do repo kontekstu) opisuje epizod leczenia od skierowania
do zamknięcia bez ani jednego nowego słowa. Kryterium jest teraz **pinowane testem**, nie deklarowane:
`PNS.Contract.vocabulary/0` wystawia słownik maszynowo, a `test/universality_gate_test.exs` porównuje go z
literałem. Dopisanie `population:` wywala ten test tego samego dnia.

Co brama pokazała, w kolejności ważności:

- **`cadence` nie ma zastosowania do procesu zdarzeniowego.** Epizod leczenia nie jest należny nigdy —
  zaczyna się, kiedy wpłynie skierowanie. Słowa nie brakuje, bo `cadence` jest opcjonalna. Ale mechanizm,
  który na niej stoi — okno „never observed" — nie ma dla takiego procesu skąd wziąć długości i spada na
  fallback z zaobserwowanych odstępów. Notatki §9 traktują ten fallback jako przypadek brzegowy; dla
  procesów zdarzeniowych jest **stanem normalnym**. Do poprawki w rekordzie.
- **„Kontrakt plus fake'i, bez implementacji" nie jest osiągalne, jeśli kontrakt ma regułę.** Brama §18
  wymaga przykładu, przykład wskazuje MFA, a `pns.check` sprawdza, że funkcja istnieje. Albo kontrakt bramy
  nie deklaruje reguł i zostawia §18 nieprzetestowane na drugiej domenie, albo dochodzi jedna czysta funkcja
  decyzyjna. Wybrane drugie. Do poprawki w opisie zakresu 1.2 w rekordzie.
- **`owner:` może wskazywać moduł, którego nie ma, i nikt tego nie sprawdza.** Widoczne już wcześniej
  (`Taxvision.Matching`), potwierdzone na drugim kontrakcie. ✅ **zrobione 5 sierpnia** — `info` w
  `pns.check`, zgrupowane po module, nie po zdarzeniu.
- **`:period` jest jedynym typem w słowniku, który nie jest uniwersalny.** Brama tego nie złapała, bo
  sprawdza, czy trzeba **dopisać** słowo, a nie czy któreś jest zbędne. Dowód: kontrakt medyczny ma
  czternaście pól w payloadach i nie używa `:period` ani razu. To „miesiąc księgowy" przebrany za typ
  ogólny. ✅ **wypadł 6 sierpnia** — szczegóły przy 2.2a, w tym wniosek o samej bramie.
- **`PNS.Graph` nie ma zawężenia do procesu ani kontraktu.** Drugi kontrakt ujawnił ukryte założenie „jest
  tylko jeden" — `graph_test` liczył węzły globalnie. Notatki §9 mówią wprost „navigation is per-process,
  never global", więc to jest luka, nie preferencja. Należy do 1.7/etapu 4, nie tutaj.
- **`identity` i `instance` razem uniosły kształt, którego TaxVision nie ma.** Dziesięć wizyt w jednym
  epizodzie to dziesięć faktów w jednym przebiegu — `identity: [:episode_id, :session_no]` przy
  `instance: [:episode_id]`. Gdyby to było jedno pojęcie, jedno z dwóch byłoby nie do wyrażenia.
- **`mix check` pokazuje teraz dwa ostrzeżenia, nie jedno.** Drugie pochodzi z wymyślonego `deadline` w
  fiksturze. Rejestr skanuje całą binarkę, a w środowisku testowym fikstura w niej jest — to ta sama
  własność, dzięki której „graf pochodzi z binarki, która działa". Samo `mix pns.check` (środowisko dev)
  fikstury nie widzi i pokazuje jedno ostrzeżenie. **Do rozstrzygnięcia:** czy raport dowodowy ma umieć
  wykluczyć przestrzeń nazw z konfiguracji silnika. Nie z DSL — to byłoby nowe słowo.

### Dokumentacja kontraktu — zrobione 5 sierpnia

`docs/contract.md`, po angielsku, bo to dokumentacja pakietu. Trzy mechanizmy anty-driftowe, bo bez nich
ręcznie pisany opis DSL-a jest **drugim źródłem prawdy** — a dziś znaleźliśmy cztery takie rozjazdy między
rekordem a kodem, w tym przykład DSL w notatkach §1 z typami, których w słowniku nie ma:

1. **Referencja kluczy jest generowana** z `PNS.Contract.schema/0` przez `mix pns.docs`. `--check` w
   `mix check` wywala build, gdy blok jest nieaktualny. Sprawdzone: podmiana jednej wartości domyślnej w
   dokumencie zatrzymuje bramę.
2. **Przykład jest fikstórą, nie ilustracją** — test kompiluje każdy blok kodu z kontraktem z tego pliku.
   Ta sama zasada, którą kontrakt stosuje do reguł, zastosowana do własnej dokumentacji.
3. **Każdy klucz DSL-a musi być w dokumencie wymieniony**, a tabela „co się nie skompiluje" nie może
   obiecywać więcej bram, niż jest testów bram.

Przy okazji `schema/0` zastąpiła sześć osobnych list kluczy jednym źródłem, z którego wyprowadza się
`vocabulary/0` **i** walidacja nieznanych kluczy. Wcześniej były to dwie rzeczy do rozjechania się.

I wyszła z tego jedna brama: **`trace` bez `from` albo bez `eventually` się nie kompiluje.** Wcześniej
kompilował się i produkował bezsens — nic nie mogło go spełnić, więc każdy przebieg wychodził jako
naruszony po upływie okna. Schema wymusiła nazwanie, co jest wymagane, i wtedy stało się widać, że
wymaganie nie było egzekwowane.

## Język kodu — ✅ spłacone 5 sierpnia

**Cały kod jest po angielsku.** 54 pliki, jeden commit, bo inaczej się nie dało: bramy kompilacyjne są
przypięte testami asertującymi na fragmenty własnych komunikatów, więc zmiana komunikatu bez testu wywala
bramę, a zmiana testu bez komunikatu nie pinuje niczego.

Granicę wyznacza **kto czyta string**, nie katalog:

- Po angielsku wszystko, co czyta programista albo kompilator — `lib/pns/`, drzewo klienta, zadania mixa,
  fikstury i testy. Fikstury, bo jadą z pakietem; testy, bo biblioteka z komunikatami bram w jednym języku
  jest biblioteką dla jednego kraju.
- Po polsku zostają cztery rzeczy, wszystkie **treść, nie kod**: `label`, `source`, opisy `example` i
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

Pytanie brzmiało: czy kontrakt nie dryfuje w stronę kontraktu pod TaxVision. **Słownik nie dryfuje.
Dryfowały mechanizmy i krawędzie silnika** — trzy znaleziska, wszystkie naprawione:

- **`PNS.Auth.Actor` miał `company_id`** jako pole struktury, czyli silnik wiedział, że aktorzy należą do
  **firm**. Przychodnia ma placówki, spedycja terminale. Umknęło, bo brama to kontrakt plus fake'i, a szew
  tożsamości nie jest częścią kontraktu. Teraz `claims: %{}` i najemcę czyta kod domenowy.
- **`within: {1, :month}` kompilowało się i wywalało w runtime.** DSL przyjmował jednostkę, której ocena nie
  umiała policzyć. Niewidoczne, bo **oba** kontrakty liczą w dniach — pisząc fikstórę medyczną
  bezrefleksyjnie skopiowałem nawyk TaxVision, choć dla epizodu leczenia `{3, :month}` jest naturalniejsze
  niż `{90, :day}`. Jednostki mają teraz jedno źródło prawdy (`PNS.Duration`) dla bramy i dla arytmetyki.
- **Raport ścieżek pomijał proces bez handlerów w całości**, czyli cały kontrakt bramy uniwersalności był
  nieobecny — a nieobecność czyta się jako „nie ma o czym mówić". Teraz `basis: :no_paths`.

Znalezione tutaj i **naprawione tego samego dnia**: runtime pakietu mówił po polsku (`to_text`, etykiety
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
jego wartość polega na tym, że jest kontraktem **bez** implementacji; jest też jedyną fikstórą, na której da
się sprawdzić raport dla procesu bez ani jednej ścieżki. Dopięcie handlerów zabrałoby oba pokrycia.

*Odbiór spełniony, i ważniejsza jest druga połowa:* check zgłasza **jedną** krawędź wsteczną
(`OnClarificationAnswered`: subskrybuje w `resolution`, publikuje do `matching`) i **milczy na trzech
kontrolach**, które publikują do przodu. Sam fakt, że check znajduje przypadek zbudowany pod niego, nie
dowodzi niczego — dowodem jest milczenie na kontrolach.

Kształty pokryte: **krok, który się cofa** (w checku i w runtime — para domyka się po wyjaśnieniu),
**to samo zdarzenie wiele razy w jednym przebiegu** (trzy pozycje = trzy fakty, jeden przebieg),
**zdarzenie wchodzące bez komendy** (bez aktora, bez przyczyny, a z tożsamością przebiegu).

Wyszło przy okazji:

- **Wykrywanie krawędzi wstecznych było logiką bez testu** — funkcją prywatną zadania mixa. Przeniesione do
  `PNS.Check`, bo sprawdzenie, którego nikt nie sprawdza, cicho przestaje działać, a na tym stoi trigger
  przeglądu ADR §15. **Reszta `mix pns.check` to nadal ~180 linii logiki całoprogramowej bez ani jednego
  testu** — do przeniesienia tą samą drogą.
- **Indirekcja `defp repo, do: @repo` w `PNS.Emitter` jest nośna, nie stylistyczna.** `@repo.aggregate(...)`
  rozwija atrybut do **literału modułu** w pozycji wywołania, więc `boundary` widzi referencję i odrzuca ją.
  Przez zmienną — nie widzi. To jest jedyny powód, dla którego `PNS` ma `deps: []`.
- **`clarification_requested` nie ma handlera i nie jest terminalne**, bo jego kontynuacja przychodzi z
  zewnątrz. Daje linię `info` i to jest uczciwe: nie ma w DSL słowa „czeka na świat zewnętrzny" i **nie
  wolno go dopisać** — to byłoby nowe słowo pod jeden przypadek.
- **~~Aktor jako `nil` nie odróżnia „import" od „nie wiemy kto".~~ ✅ zamknięte 21 sierpnia.** Sensowna
  wersja postulatu „każde zdarzenie ma aktora" to nie „wymagany", a **„nigdy cisza"** — jawny aktor
  systemowy, `PNS.Auth.system_actor/0`. Patrz „Dopisek 21 sierpnia (7)".

**1.3b Dwa moduły potrzebujące tych samych danych. ✅ zrobione 5 sierpnia.** Nośnikiem jest tabela
`taxvision_periods`: okres przestaje być stringiem i staje się wierszem z zakresem dat.

**Zakaz joinów międzymodułowych jest znośny, i jego cena jest zmierzona, nie opowiedziana.** `Taxvision.Tasks`
ustawia `due_on`, `Taxvision.AccountingMonth` ustawia `closes_on`, oba z tego samego okresu — i **każdy płaci
własnym zapytaniem**. Test liczy je telemetrią Ecto: dokładnie dwa trafienia w `taxvision_periods` na jedno
otwarcie miesiąca. Notatki §14 nazywają N+1 ryzykiem, nie niespodzianką; teraz jest liczbą.

Mechanizm, który to trzyma, jest mocniejszy niż zakaz: **`Taxvision.Periods` ma `exports: []`**, więc schemat
`Period` jest nieosiągalny z zewnątrz i join do niego jest **niewyrażalny**, a nie zabroniony. Ten sam ruch,
który zamienił „zdarzenie w dwóch procesach" ze sprawdzenia w niemożliwość. Rodzeństwo dostaje `fetch!/1` —
wywołanie funkcji, nie join.

Kanonizacja zadziałała natychmiast i widać to w testach: **nie da się zaksięgować w okresie, który nie
istnieje.** 23 testy padły przy pierwszym uruchomieniu, bo otwierały miesiąc bez kanonicznego okresu. To nie
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
sam wiersz nie gwarantuje, że dwa zdarzenia wskażą ten sam. Prawdziwy zysk to **kanonizacja**: przy kluczu
obcym `"2026-7"` obok `"2026-07"` przestaje być możliwe, a nie tylko niezalecane. Zamyka też dziurę, którą
miałby okres jako data — `2026-07-15` jest poprawną datą i cichym drugim przebiegiem tego samego miesiąca.

To jest **dobre miejsce na kształt „dwa moduły potrzebujące tych samych danych"** i lepsze niż przykład
wymyślony: `period` występuje w zdarzeniach należących do `RegistryCheck`, `Tasks`, `AccountingMonth`,
`Notifications` i docelowo `Matching`, więc każdy z nich musi ten okres rozwiązać. ADR §5–6 zabrania joinów
międzymodułowych, a `wiki/pns/modular-design.md` daje odpowiedź: strategiczna duplikacja z nazwanym źródłem
prawdy, nie wspólna tabela. Czyli budowanie tego nie jest objazdem, tylko realizacją punktu z listy.

**Kolejność wobec etapu 1: 1.5 i 1.4 idą przed 1.3** (ustalone 5 sierpnia). Powód: `trace`, `deadline` i
`cadence` są zadeklarowane i **nie czyta ich żaden mechanizm w runtime** — sprawdzone, nie z pamięci. To
jest produkt, a 1.1 i 1.2 były jego warunkiem wstępnym. 1.3 wymaga decyzji domenowych i materiału
klienckiego; 1.4 i 1.5 nie wymagają ani jednej linijki TaxVision, bo oba kontrakty już deklarują assercje.

**1.4 Behawioralna weryfikacja ścieżek, per instancja. ✅ zrobione 5 sierpnia.**
*Odbiór:* **spełnione.** `PNS.Conformance.untraversed_paths/1`, `test/conformance_test.exs`: 50 przebiegów
zgodnych → dokładnie **jedna** nieprzejechana ścieżka. 49 zgodnych plus jeden rozjazd → **zero**.

To jest jednocześnie odpowiedź na warunek falsyfikacji z ADR-a: **różnica declared vs observed jest
sygnałem, nie szumem.** Pięćdziesiąt przebiegów daje jedną linię raportu. Gdyby dawało pięćdziesiąt albo
trzy, odpowiedź brzmiałaby odwrotnie.

`PNS.Conformance` jest miejscem, w którym zbiegną się cztery pytania ekranu — dziś odpowiada na pierwsze.
Dzięki temu 1.7 nie powstanie jako czwarte zadanie mixa obok trzech innych.

Dwie sytuacje, w których raport łatwo skłamie, obie przypięte testem:

- **Zero przebiegów to brak podstawy, nie trzy znaleziska.** Proces, który nigdy nie ruszył, ma wszystkie
  ścieżki nieprzejechane; wypisanie ich zamienia „nie ma danych" w „mamy trzy problemy". Raport mówi
  `basis: :no_runs` i pustą listę — ta sama zasada, na której stoi ocena assercji.
- **Job w kolejce to „jeszcze nie", nie „nigdy".** Wypisywany osobno, nie jako nieprzejechany. Bez tego
  raport kłamie przy każdym normalnym opóźnieniu.

Liczy **przebiegi, nie wystąpienia** — bo tylko ta liczba przy wielu klientach odróżnia ciszę od braku
ruchu. Wolumen w teście jest symulowany, ale **proces nie**: przebiegi idą przez kontrakt z warsztatu, a nie
przez fazy dopisane pod kryterium odbioru.

**Symulować wolumen, nie proces.** Plan produktowy chce falsyfikacji na 50 zasymulowanych przebiegach i ma
rację co do taniości, ale nie nazywa wady: proces, który sam zaprojektuję, wyprodukuje dokładnie ten sygnał,
który w niego wpiszę. Te 50 przebiegów idzie więc przez **istniejący kontrakt z warsztatu**, nie przez fazy,
które sam dopiszę. Kształt pochodzi wtedy z sesji z klientem, a losowe są tylko dane.

**1.5 Ocena assercji `trace`. ✅ zrobione 5 sierpnia — trzy werdykty z czterech.** Per instancja.
*Odbiór:* **spełnione.** `PNS.Trace`, `test/trace_test.exs`, i widać to na prawdziwych danych:
`mix pns.trace` na pięciu przebiegach mówi „spełniona 5/5, 3 przez eventually, 2 przez or_else". Dwie
zablokowane firmy są **spełnione**, nie naruszone.

To jest pierwszy moment, w którym cokolwiek w runtime **czyta** `trace`. Do teraz assercja była prozą w
składni Elixira.

Trzy decyzje semantyczne, każda przypięta testem, bo każdą da się zepsuć w drugą stronę bez łamania
niczego innego:

- **Okno liczy się od pierwszego wystąpienia `from`, nie od ostatniego.** Inaczej proces uciekałby przed
  terminem w nieskończoność, emitując `from` ponownie — a przy ponownym sprawdzeniu rejestrów to nie jest
  przypadek teoretyczny.
- **`within` obowiązuje także `or_else`.** Inaczej termin jest bezużyteczny: proces zakończony poprawnie
  trzy miesiące po terminie byłby „spełniony". **Do potwierdzenia przez process ownera** — to jedyna
  decyzja w tym etapie, która należy do niego, nie do nas.
- **Przebieg bez `from` nie jest oceniany wcale.** Ani spełniony, ani naruszony — nie ma o czym orzekać.
  Liczenie go jako naruszenia zrobiłoby alarm z każdej niezaczętej sprawy. Symetrycznie: zero przebiegów
  to brak podstawy do orzekania, nie zielony raport.

Wyszło przy okazji: **`or_else` produkowane handlerem asynchronicznym jest `pending`, dopóki job stoi w
kolejce** — ta sama lekcja, co czwarty stan nakładki. Koszt jest nazwany: job zaklinowany dłużej niż okno
policzy się jako naruszenie, i to jest poprawne, bo powiadomienie faktycznie nie poszło.

**1.5b Czwarty werdykt: `:suspended`. ✅ zrobione 6 sierpnia.** `PNS.Dependency`,
`test/dependency_test.exs`. 221 testów.

`external` i `unavailable_looks_like` były w kontrakcie od pierwszego dnia i **nikt ich nie czytał**. Dziś
mają czytelnika: awaria zależności w oknie assercji nie jest już naruszeniem.

**Dlaczego to najdroższy fałszywy pozytyw, jaki ten produkt umie wyprodukować.** Bez tego raport mówi
klientowi, że złamał własne ustalenie, kiedy leżał **czyjś serwer**. Jedyny majątek tego artefaktu to bycie
wiarygodnym — jedno takie znalezisko przed księgową i raport przestaje być czytany.

**Reguła doboru zależności jest wąska i to jest istotne: liczą się te, które deklarują zdarzenia, jakie
nie przyszły.** `from` już się stało, więc to, od czego ono zależy, działało. Suma wszystkich zależności
kontraktu byłaby gorsza — przebieg dostawałby rozgrzeszenie, bo padło coś, czego nigdy nie dotknął.

**Zawieszenie zastępuje wyłącznie naruszenie.** Nigdy nie rusza `:satisfied` — przebieg zakończony poprawnie
jest zakończony poprawnie, cokolwiek wtedy leżało — ani `:pending`, bo jest jeszcze czas. Oba kierunki
przypięte testem, bo drugi jest z tych, których nikt nie pomyśli sprawdzić.

**Nadmierne zapisywanie jest groźniejsze niż niedostateczne, i to zdecydowało o API.** Zawieszenie **zabiera**
znalezisko z raportu, więc mechanizm zapisujący niedostępność hojnie po cichu przestałby raportować prawdziwe
problemy — awaria w kierunku, którego nikt nie zauważa, czyli odwrotnie niż cała reszta tego silnika. Dlatego
`PNS.Dependency.observe/3` zapisuje **wyłącznie** to, co adapter stwierdza wprost (`{:error, :unavailable}`);
`{:error, :timeout}` przechodzi bez zapisu, dopóki ktoś nie zdecyduje inaczej **w adapterze**.

Zapis jest **owinięty, nie do zapamiętania** — ten sam kształt co `PNS.Telemetry.handler_span/2`, z tego
samego powodu: reguła, do której nikt nie jest zmuszony, wygasa.

**Obserwacje, nie przedziały.** Adapter wie, że jedno wywołanie padło. Nigdy nie wie, kiedy usługa wróciła,
bo nikt mu tego nie mówi — dowiedzenie się wymaga dopytywania, czyli health-checkera, czyli innego produktu.
Nic nie jest kluczowane przebiegiem: **rejestr nie leży jednej firmie**, leży wszystkim naraz, i test tego
pilnuje (jedna awaria zawiesza oba przebiegi).

**TaxVision nie umie wyprodukować zawieszenia, i to jest znalezisko, nie brak fikstury.** Jego jedyna
zadeklarowana zależność — rejestry publiczne — jest konsultowana przez krawędź żądania **przed pierwszą
emisją**, więc okno nigdy nie otwiera się, gdy zależność jest w grze. Ten werdykt ma znaczenie dla procesów,
których **następnik** sięga na zewnątrz, nie tych, których poprzednik. Demonstracja jest więc na rigu, który
jest jawnie nie-domeną — i **nie dopisałem `external :mail` do kontraktu klienta**, choć powiadomienie
faktycznie zależy od poczty: `unavailable_looks_like` jest polskim zdaniem, które **czyta klient**, a
wymyślanie go za niego to dokładnie ta zmyślona wiedza o domenie, którą PNS ma wykrywać u innych.

**1.6 Wersja kontraktu jako pierwszoklasowa odpowiedź. ✅ zrobione 5 sierpnia.**
*Odbiór:* **spełnione.** `PNS.Deployment`, `test/deployment_test.exs`. Raport mówi, co wdrożone, od kiedy,
jakie wersje są w logu, ile zdarzeń pochodzi z innych wersji, oraz co się zmieniło — osobno zdarzenia,
osobno ścieżki.

**Najważniejsze wyszło z ostatniej części kryterium („bez ani jednego fałszywego driftu") i było prawdziwą
dziurą, nie hipotetyczną.**

`version/0` haszuje **deklaracje kontraktu**. Ścieżki pochodzą z `publishes:` **handlerów**, których w tym
haszu nie ma. Skutek: usunięcie handlera zmienia graf, nie zmieniając ani jednej wersji stemplowanej
gdziekolwiek — więc nakładka widziała krawędź zaobserwowaną i już niezadeklarowaną, sprawdzała, że wersja
kontraktu jest wciąż aktualna, i orzekała **drift** dla ścieżki, która była legalnie zadeklarowana, kiedy
przejechała.

Notatki §9 mówią, że skew wersji „handled by `contract_version` on the event", i podają przykład z
**usuniętym zdarzeniem** — ten działa, bo usunięcie zdarzenia bumpuje wersję. Przypadku z usuniętym
**handlerem** rekord nie rozważa. **Do poprawki w rekordzie.**

Rozwiązanie: **wdrożenie ma dwie tożsamości.** `contract_version` to umowa, `wiring_version` to kod. Refaktor
rusza jedną i nie rusza drugiej, a to jest dokładnie rozróżnienie, na którym klientowi zależy.

Kształt zapisu: jeden wiersz na odrębne obwodowanie, przy boocie. **Nic per zdarzenie** — koszt to jeden
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
*Odbiór:* **spełnione.** `PNS.Conformance.report/2` (dane) plus `Taxvision.Report.render/1` (zdania),
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
  a `month_opens_or_is_blocked` w raporcie dla księgowej oblewa kryterium. Raport składa **zdanie z etykiet
  zdarzeń**, czyli ze słów, które klient już zatwierdził.

  **Rozstrzygnięte 5 sierpnia: `label` do `trace` nie wchodzi.** `trace` ma już nazwę
  (`trace :month_opens_or_is_blocked do`), brakuje mu etykiety klienckiej — i to jest różnica, która decyduje.
  Etykieta zdarzenia **dodaje fakt**, którego nie ma nigdzie indziej: żaden silnik nie wyprowadzi „Otwarto
  miesiąc księgowy” z `accounting_month_opened`, więc nie ma z czego dryfować. Etykieta assercji
  **powtarzałaby fakt już w pełni wyrażony** przez `from`/`eventually`/`within`/`or_else` — czyli drugą
  edytowalną reprezentację jednej rzeczy. Zmień `within: {2, :day}` na `{5, :day}` i proza dalej mówi „w ciągu
  dwóch dni”, a **nic tego nie łapie**. To jest argument, którym ADR §2 odrzuca zewnętrzny format dokumentacji
  jako źródło, obrócony na nasz własny DSL. Zdanie składane jest wyprowadzone, więc **nie może skłamać**.

  Czego assercja faktycznie nie umie powiedzieć, to **dlaczego ją ustalono** — „bo urząd liczy termin od
  otwarcia" `[WF 00:34:40]`. Tego w mechanice nie ma, nie da się wyprowadzić i nie ma z czego dryfować. Słowo
  na to **już istnieje**: `source:`, dziś tylko na `rule`. Rozszerzenie kosztuje zero nowych słów, `label`
  kosztowałoby jedno. **Nie dopisane** — obie nasze assercje pochodzą z warsztatu i żadna nie ma zapisanego
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
obwodowaniu nie ma — i raport nazywał to driftem, **poprawnie w formie i z fałszywego powodu.**

**Jedna reguła, dwie konsekwencje — po granicy transakcji, nie po preferencji.** Synchronicznie: rzuca,
transakcja się cofa, w logu nie ma ani emisji, ani zdarzenia, które ją wywołało. W kolejce: łapie się tam,
gdzie każda inna awaria handlera, ląduje w `event_handlings` z komunikatem, a **zdarzenie wywołujące zostaje**
— bo job leci poza transakcją, świadomie, i fakt, który go wywołał, pozostaje faktem. Sprawdzenie idzie
**przed** emisją, nie po: gdyby po, graf byłby już sprzeczny z logiem, kiedy ktokolwiek się dowie.

Naruszenie **nie może być stanem danych, tylko defektem kodu** — i deklaracja, i emitowana nazwa są w
handlerze statyczne. Dlatego wywala się na pierwszym teście, który handler przejedzie, i to jest cała
wartość: przenosi wykrycie z produkcji do CI.

Fikstury (`OnItemReviewed`, `OnItemEscalated`) są w rigu, bo **złamany kod na potrzeby testu nie ma prawa
stać w drzewie klienta** — żadna domena nie powinna nosić przykładu buga. Oba deklarują `publishes: []`, więc
nie wnoszą **ani jednej krawędzi**: graf, `wiring_version` i raporty ścieżek zostają nietknięte. Dwie
fikstury, nie jedna, bo jedna reguła wołana z dwóch miejsc to dokładnie to, co się rozjeżdża — i nie mogą
dzielić zdarzenia, skoro synchroniczna cofa transakcję, w której stałby job.

Naruszenie zależy od payloadu, a nie jest bezwarunkowe, i to nie jest wygoda: **ten sam handler emitujący nic
nie może rzucać.** Bez tej kontroli sprawdzenie reagujące na dowolny return handlera przeszłoby test
pozytywny. Zweryfikowane odwrotnie — po zneutralizowaniu reguły pada **cztery z ośmiu** testów, czyli
dokładnie te, które o naruszeniu cokolwiek twierdzą.

Zostaje na później: tracer kompilacji (notatki §2) przesunąłby wykrycie jeszcze wcześniej, ale to
optymalizacja momentu, nie warunek poprawności.

**2.2a Wyrzucenie `:period` ze słownika typów. ✅ zrobione 6 sierpnia.** `PNS.Contract.payload_types/0`,
`test/compile_gates_test.exs`, `test/universality_gate_test.exs`. 166 testów.

**Najpierw trzeba było słownik stworzyć, a nie tylko z niego usunąć.** Sprawdzone, nie założone: **żadna
walidacja typów nie istniała** — dowolny atom kompilował się jako typ payloadu. Samo przepisanie
`period: :period` na `period: :id` w jedenastu miejscach byłoby więc kosmetyką **odwracalną przez przypadek**,
bo nic nie stałoby na drodze następnej osobie, której `:period` będzie wygodne. Słownik jest teraz **zbiorem
zamkniętym**, a wyjście z niego jest błędem kompilacji: `[:id, :string, :integer, :timestamp, :enum]`.

**Czego brama uniwersalności nie umie zobaczyć — i to jest wniosek o samej bramie.** Kryterium „zero nowych
słów" pyta, czy opisanie drugiej domeny wymusiło **dodanie** słowa. Jest **konstrukcyjnie niewidoma** na
słowo, które już jest, a być nie powinno. `:period` przechodził ten test dwa dni. Znalazło go **liczenie**:
kontrakt medyczny ma czternaście pól payloadu i nie użył go ani razu. Brama ma teraz drugą połowę — literał
z typami, przypięty tym samym mechanizmem, co słownik kluczy.

**Cena, której `PLAN.md` się bał, nie dotyczy tej połowy.** Wcześniejsza wersja tego punktu wiązała usunięcie
`:period` z walidacją typów, bo klucz przebiegu miał zmienić się z `accounting_month|c-1|2026-07` na
`|<uuid>|<uuid>`, a „odtwarzalny z samego logu" było jawną własnością projektową. To jednak dwie różne
zmiany, i pomyliłem je: **wyrzucenie typu ze słownika nie rusza wartości.** Sprawdzone po zmianie — klucz
nadal brzmi `accounting_month|c-1|2026-07`. Przejście na `period_id` jako uuid to osobna decyzja klienta i
ona nadal ma czekać na 2.2b.

Komunikat błędu mówi, **co napisać zamiast** — „jeśli nazywa rzecz, a nie kształt, to jest `:id`" — i to jest
przypięte osobnym testem. Brama, która mówi tylko „twoje słowo jest złe", jest bramą, którą się obchodzi.

Domknięte przy okazji: `:integer` był używany piętnaście razy i **nie było go w udokumentowanym słowniku**;
notatki §1 pokazywały w przykładzie DSL-a `:uuid` i `:decimal`, **których nigdy nie było**. Referencja typów
jest teraz generowana przez `mix pns.docs` z tego samego źródła, co brama — bo ręcznie pisana kopia zbioru
zamkniętego jest pierwszym miejscem, w którym pojawia się szósty typ bez dokumentacji.

**2.2b Walidacja payloadu przeciw zadeklarowanym typom. ✅ zrobione 6 sierpnia.** `PNS.Payload.validate!/4`,
`test/payload_test.exs`. 196 testów.

**Wyszło, że to nie jest jedna rzecz, a dwie — i pierwsza była fałszywą obietnicą w moduledoku.**
`PNS.Payload` twierdził, że handler synchroniczny i asynchroniczny widzą **ten sam kształt**. Dla kluczy tak,
dla **wartości nie**: `:timestamp` był `DateTime` w jednym i tekstem ISO 8601 w drugim. Dowód, że to bolało:
kod klienta serializował ręcznie w miejscu emisji (`DateTime.utc_now() |> DateTime.to_iso8601()`) — pole
zadeklarowane jako punkt w czasie **celowo trzymało tekst**, bo dwa kształty były gorsze niż jeden zdegradowany.
`cast/2` odtwarza teraz wartości, obejście wypadło z `api.ex`, a deklaracja znaczy to, co mówi.

Reguła zamiast listy: **cast naprawia dokładnie to, co niszczy JSON.** Liczby, tekst i identyfikatory
przeżywają round trip; punkt w czasie nie. **Odtwarzanie to nie koercja** — `:integer` przychodzący jako `"5"`
nie jest stratą, bo JSON liczby niesie, więc to wołający podaje nie to; koercja ukryłaby defekt, który
walidacja ma ujawniać.

**Kolejność była zła przy pierwszym podejściu i to jest najważniejsze znalezisko tego punktu.** Walidowałem
**po** `retain`, z uzasadnieniem „sprawdzamy to, co faktycznie wyląduje w logu". Jest odwrotnie:

- `:hash` zamienia cokolwiek w hex string, więc pole `:string` **nigdy nie mogło paść**, a `:integer` **nigdy
  przejść** — czyli sprawdzenie przestawało obowiązywać dokładnie tam, gdzie pola niosą treść wrażliwą.
- `:drop` **usuwa pole**, więc zadeklarowane pole byłoby trwale brakujące i każda taka emisja odrzucona.

Drugie było **utajone: `:drop` nie było używane nigdzie**, więc nikt nie mógł na to wpaść. Doszła fikstura
(`item_noted`, `retain: %{note: :drop}`), która jest dziś jedynym `:drop` w repo — bo pułapka nieosiągalna to
nie to samo co nieistniejąca. Typ opisuje **fakt**, `retain` opisuje **co log z niego zachowuje**, a
zrzucenie pola nie zwalnia wołającego z deklaracji.

**Surowo na wejściu, defensywnie na wyjściu.** Nic nie waliduje przy czytaniu i to jest decyzja, nie
przeoczenie: log trzyma zdarzenia zapisane pod kontraktami, które się od tego czasu zmieniły, a raport, który
nie umie przeczytać historii, jest gorszy od takiego, który czyta ją luźno. ADR §7–8 nazywa to *read
defensively*. Przypięte testem: wiersz z payloadem bez dzisiejszego pola daje się odczytać bez wyjątku.

**Jedno sprawdzenie stało się nieosiągalne z emisji** — ten sam wzorzec, co „zdarzenie w dwóch procesach".
`PNS.Instance` rzucał, gdy pola instancji zabrakło w payloadzie; brama kompilacyjna gwarantuje deklarację,
walidacja gwarantuje obecność, a walidacja leci **przed** liczeniem klucza. Raise **zostaje**, bo funkcja jest
publiczna i wołający bezpośrednio nie ma przed sobą niczego — **nieosiągalne z jednej ścieżki to nie martwe**,
i to jest przypięte osobnym testem, nie komentarzem.

**Trzy pola nie są odrzucane, choć mogłyby być:** nadmiarowy klucz nieopisany w kontrakcie **zostaje**. Jest
odrzucany tam, gdzie to ma znaczenie — handler emitujący niezadeklarowane *zdarzenie* nie dojdzie tak daleko —
a jeden zbędny klucz jest w logu **widoczny**, podczas gdy brakujący jest ciszą. Ten sam argument, który
zrobił z checka retencji raport, a nie bramę.

Zweryfikowane odwrotnie: po zneutralizowaniu walidacji pada **siedem z piętnastu** testów tego pliku.

**2.2c `period_id` jako identyfikator. ✅ zrobione 6 sierpnia — decyzja klienta podjęta.**
Migracja `20260806130000`, `Taxvision.Periods.fetch_by_id!/1`. 207 testów.

**Przeszacowałem koszt, kiedy o to pytałem, i to jest sprostowanie do mojego własnego zdania.** Mówiłem, że
„odtwarzalny z samego logu" jest własnością, którą się traci. Nie jest: własność silnika mówi, że klucz jest
**odtwarzalny** z payloadu w logu, nie że jest **czytelny**. Odtwarzalność jest nietknięta. Traci się
interpretowalność gołym okiem — i to w dwóch miejscach, oba drobne: `mix pns.trace --instances` (widok
debugowy) i ktokolwiek czytający log bez joina. **Raport dowodowy nie wypisuje kluczy przebiegu w ogóle** —
sprawdzone renderem po zmianie, zero uuidów — bo „które przebiegi milczą" to pytanie o konkretną firmę.

**Nazwy na krawędziach, identyfikatory w środku**, i krawędzi jest dwie. Wejściowa: `Taxvision.Api` rozwiązuje
nazwę raz, i za tą linią nic w domenie nie widzi już stringa. **Wyjściowa, której nie przewidziałem:** temat
powiadomienia zawiera nazwę miesiąca, więc bez odwrotnego rozwiązania księgowa dostałaby maila „miesiąc
3f2a8c…-… zablokowany". Symetria wyszła z kodu, nie z planu.

**`boundary` natychmiast złapał dwie nowe zależności międzymodułowe** — `Notifications` i `Api` sięgające po
`Periods`. Zadeklarowane jawnie. To zakaz joinów robiący dokładnie to, po co jest: nowa zależność jest
**widoczna od razu**, a nie przychodzi jako join, który ktoś zauważy później.

**Moja pierwsza migracja była zła i pękła na dev-bazie.** Dodawała kolumnę `null: false` i przechodziła na
pustej bazie testowej. Stary string **jest** nazwą okresu, więc join odzyskujący identyfikator istnieje —
migracja robi teraz backfill, potem dokłada `NOT NULL`, i **nic nie usuwa**: wiersz, którego nie da się
zmigrować, zatrzymuje migrację. Migracja cicho kasująca dane biznesowe, żeby sobie przejść, jest gorsza od
takiej, która staje. Przy okazji jest to próba generalna dla klienta, którego tabele nie są puste.

**Najciekawsze znalezisko: przykład i funkcja decyzyjna przestały być tym samym kształtem.** `example`
opisuje **komendę, jak ją wydaje człowiek** — więc `period: "2026-07"`. Funkcja decyzyjna dostaje wejście
**po rozwiązaniu na krawędzi** — więc `period_id`. `given:` jest dokładnie tym, co zastępuje tę maszynerię, i
zawsze było. Identyfikator w przykładzie jest **czytelny celowo** (`"period-2026-07"`): `:id` znaczy
*identyfikator*, nie *uuid*, a wstawienie prawdziwego uuida do kontraktu wymieniłoby całą własność §18 —
że przykład da się przeczytać process ownerowi na głos — na spójność, której nic nie potrzebuje.

**Zmierzona cena wzrosła z dwóch zapytań na trzy** i trzecie jest tą kanonizacją. Jedno na krawędzi
(nazwa → identyfikator), po jednym na każdy moduł potrzebujący dat. Przypięte **osobnym** testem, że
zapytanie po nazwie jest **dokładnie jedno** — bo gdyby ktoś przeniósł rozwiązywanie do handlera, liczba
zostałaby trzy, a powód by się zmienił.

Drobiazg, który pokazuje utraconą czytelność w najmniejszym możliwym miejscu: **posortowana lista kluczy
przebiegu przestała być chronologiczna**, bo sortuje się po uuidzie. Test sortuje teraz obie strony.

**2.3 Ślad po awarii handlera synchronicznego. ✅ zrobione 6 sierpnia.** `PNS.HandlerFailure`,
`PNS.SyncHandlerError`, `test/handler_failure_test.exs`. 162 testy.

Plan mówił „zapis poza transakcją **albo** telemetria". Weszły **oba i z różnych powodów**: telemetria, bo
zbieranie błędów należy do narzędzi klienta (`[:pns, :handler, :exception]` z handlerem, przebiegiem i
stacktrace'em), a trwały wiersz, bo **telemetria istnieje tylko tam, gdzie ktoś skonfigurował kolektor**, a
luka z ADR §13 jest o **artefakcie**, nie o observability.

**Kryterium ma dwie połowy, które się przeciągają, i obie są przypięte.** Awaria jest zapisana **i cofnięcie
zostaje w mocy** — zapisanie okupione osłabieniem rollbacku wymieniłoby lukę diagnostyczną na log, który
kłamie, że fakt zaszedł, choć praca się nie wykonała.

**Osobna tabela, nie status na `pns_event_handlings`, i nie z wygody.** Każdy inny wiersz w logu mówi o czymś,
co zaszło; ten mówi o czymś **próbowanym, co nie zaszło** — więc nie ma na co wskazać, bo zdarzenie zostało
cofnięte i nigdy nie istniało. Klucza obcego nie ma i to jest decyzja, nie przeoczenie. Tym, co przeżywa
rollback, jest `correlation_id`, generowany przed otwarciem transakcji, i to on jest uchwytem.

**Gdzie zapis, bo to była cała trudność.** Nie tam, gdzie awaria jest zauważona — ten kod siedzi w skazanej
transakcji, więc jego insert cofnąłby się razem z nią. Zapis idzie w **najbardziej zewnętrznej ramce
emittera**, tej, która transakcję otwarła, **po** rollbacku, kiedy połączenie jest znowu wolne. Żadnego
drugiego połączenia, żadnego `Task`, żadnego pisania obok sandboxa w testach — a to ostatnie miało już
kiedyś cenę przy `PNS.Deployment.record!`.

**Wrapper jest transportem i nie wychodzi do wołającego.** Ramka, która wie *który handler padł na którym
przebiegu*, jest głęboko w transakcji, która zaraz zniknie; ramka, która umie trwale zapisać, nie wie nic —
kontekst musi odbyć podróż. Ale pierwsza wersja przepuszczała `PNS.SyncHandlerError` na zewnątrz i **jeden
test to złapał**: wołający zamiast `ArgumentError` handlera dostawał wyjątek silnika. To byłaby zmiana
łamiąca obsługę błędów u każdego klienta, wprowadzona jako efekt uboczny mechanizmu diagnostycznego. Teraz
emitter odwija i rzuca **oryginał z oryginalnym stacktrace'em** — samo `reraise original, __STACKTRACE__`
wskazywałoby bibliotekę, co jest gorsze niż brak wrappera, więc stacktrace jedzie w polu.

**Podwójne zawinięcie.** Emisja handlera odpala następny handler, więc `rescue` ramki wyżej zawinęłoby już
zawinięty błąd i przypisało awarię **nie temu handlerowi**, plus jedno zdarzenie telemetrii na ramkę. Osobna
klauzula na `PNS.SyncHandlerError` przepuszcza go bez zmian.

**Tabela ma czytelnika od pierwszego commita**, bo inaczej jest kolejną deklaracją, której nikt nie czyta — a
etap 2 istnieje po to, żeby takie usuwać. `PNS.Conformance` odróżnia **„nigdy nie próbowano" od „próbowane i
nie udaje się"**: „zadeklarowane, nigdy nie zaobserwowane" czyta się jako martwy albo nieprzetestowany krok, a
dla handlera, który leci i pada w każdym przebiegu, **oba odczyty są fałszywe** i idą do złej osoby. Ścieżka z
padającym handlerem wypada z listy nieprzejechanych i wchodzi na własną. To trzeci wariant jednego błędu:
raport nie ma prawa zamieniać *braku odpowiedzi* na *odpowiedź „nie"*.

Liczy **przebiegi, nie awarie** — handler ponowiony czterdzieści razy dla jednego klienta to jeden padający
przebieg. `coalesce` wymagało jawnego rzutowania, bo `instance_id` jest tekstem, a `id` uuidem, i Postgres
słusznie odmawia zamiast wybrać po cichu.

**Limit nazwany, nie obejściony:** kiedy transakcję otwarł wołający, silnik nie dostaje swojej kolejki —
wyjątek wchodzi w ich transakcję i ślad jest ich do zapisania. Trwały zapis z wnętrza czyjejś skazanej
transakcji nie jest na jednym połączeniu możliwy. Przypięte testem, żeby limit był własnością, a nie
niespodzianką.

Fikstura `OnItemFlagged` jest w `intake`, **nie w `resolution`**, choć tam byłaby naturalniejsza: publikuje do
`matching`, więc z `resolution` byłaby **drugą krawędzią wsteczną** i po cichu zepsułaby kryterium odbioru
1.3, zmieniając liczbę z jednej na dwie. Sprawdzone: `pns.check` nadal zgłasza jedną.

Zweryfikowane odwrotnie: po wyłączeniu zapisu padają **trzy z dwudziestu trzech** testów w tych dwóch
plikach — dokładnie te, które o śladzie cokolwiek twierdzą.

**2.4 Cztery rzeczy odpornościowe. ✅ ZAMKNIĘTE 6 sierpnia.** 180 testów.

**Kolejność dwóch handlerów synchronicznych — zrobione.** Plan mówił „zdefiniowana **albo** zabroniona".
Wyszło **jedno i drugie, i to nie jest kompromis**: zdefiniowana w rejestrze, żeby zachowanie się
odtwarzało, i zgłaszana jako ostrzeżenie w `pns.check`, bo sam determinizm nie czyni tego kształtu dobrym.

Zakaz byłby za mocny: dwa handlery piszące rozłączny stan pochodny w jednej transakcji są legalne i
niezależne od kolejności. Ale „niezależne od kolejności" **było twierdzeniem, którego nikt nie sprawdził** —
a kolejność brała się z tego, w jakiej kolejności moduły znalazły się w liście aplikacji, więc identyczny kod
mógł zachowywać się różnie po dwóch deployach. Teraz jest sortowana po nazwie modułu: **odtwarzalna i nadal
arbitralna**. Ostrzeżenie mówi wprost, że jeśli kolejność ma znaczenie, to kontrakt wyraża sekwencję przez
pisownię nazwy modułu, a poprawka należy do kontraktu — jeden handler publikuje zdarzenie, na które
subskrybuje drugi, i wtedy sekwencja jest **ścieżką, którą widzi nakładka**.

Nie jest to brama kompilacyjna, bo oba handlery są w innych modułach i żaden nie wie o drugim w czasie
kompilacji. To własność całoprogramowa i leży tam, gdzie reszta takich — ale **w `PNS.Check`, nie w zadaniu
mixa**, tą samą drogą co `backward_edges/0`.

Żadne zdarzenie nie miało takiego kształtu, więc check byłby niemy, a **check, którego jedynym dowodem jest
własna cisza, nie jest przetestowany.** Do rigu weszła jedna para (`OnItemMeasuredFirst`/`Second`, oba
`publishes: []`, więc zero krawędzi), nazwana tak, że **kolejność alfabetyczna i deklaracyjna się nie
zgadzają** — czyli dokładnie pułapka, o której mówi ostrzeżenie. `mix check` pokazuje od teraz **cztery**
ostrzeżenia, a czwarte jest kryterium odbioru tego punktu, tak samo jak krawędź wsteczna jest kryterium 1.3.

**Łagodne odrzucenie joba po znikniętym handlerze — zrobione.** Było: `to_existing_atom` rzuca, job pada,
Oban ponawia **dwa razy identycznie** co trzy sekundy i kończy jako `discarded` z komunikatem, który nie mówi
dlaczego. Deterministyczna awaria ponawiana to szum, a szum w kolejce jest miejscem, w którym chowają się
awarie prawdziwe.

Teraz `{:cancel, reason}` — bez ponawiania — plus wiersz w `pns_event_handlings` ze statusem `cancelled`.
**Zapis nie jest księgowością, a odpowiedzią na pytanie z 1.6:** job zakolejkowany dla handlera, którego nie
ma, jest **ścieżką zadeklarowaną przez obwodowanie, które nie jest już wdrożone** — dokładnie tym faktem,
który `wiring_version` istnieje, żeby odróżnić od driftu. Cicho porzucony, log twierdziłby, że pracy nigdy nie
zakolejkowano, co jest innym i fałszywym zdaniem.

Trzy drogi do „handlera nie ma" i wszystkie znaczą dla joba to samo: atomu nigdy nie było (zmiana nazwy przy
jobach w kolejce), moduł jest, ale nie da się go wczytać, albo **moduł jest i przestał być handlerem** — to
ostatnie robi się, usuwając `use PNS.Handler` i zostawiając plik. Rozwiązywanie po samej nazwie wywaliłoby się
linijkę później, na wywołaniu funkcji, której nie ma.

Kontrola w tym teście padła przy pierwszym uruchomieniu, bo wybrałem jako „działający handler" fiksturę z 2.1,
która **celowo emituje coś niezadeklarowanego**. To jest koszt trzymania złamanego kodu w rigu i wart
zapisania: fikstury z różnych etapów potrafią się na siebie nałożyć.

**Ochrona przed cyklem — ✅ zrobione 6 sierpnia.** `test/cycle_test.exs`, 173 testy.

**Reguła jest węższa, niż się wydaje, i trzy tańsze były błędne.** Cyklem jest **to samo zdarzenie dwa razy
na jednej ścieżce** od emisji korzeniowej — nic więcej.

- **Limit głębokości** wymaga liczby, której nikt nie uzasadni, a ta liczba decyduje, czy prawdziwy kontrakt
  działa. Zadeklarowany graf daje ograniczenie darmo: ścieżka bez powtórzenia nie może być dłuższa niż liczba
  zdarzeń.
- **„To samo zdarzenie już było w tej transakcji"** daje fałszywy alarm na rombie: komenda emituje A, handlery
  A emitują B i C, oba publikują D. Dwa D, żadnego cyklu, bo żadne nie jest przodkiem drugiego. **Przypięte
  testem** — dwie pozycje w jednej komendzie dają dwa `item_paired` i dwa `case_closed`.
- **Statyczne sprawdzenie na grafie nie umie tego zrobić**, bo **krawędź wsteczna nie jest cyklem**. Rig ma
  jedną celowo i jest ona kryterium odbioru 1.3, więc zakaz krawędzi wstecznych zakazałby kształtu, który
  opisał warsztat.

**Łańcuch jedzie przez kolejkę i to nie jest kompletność na wyrost.** Pętla przez joby nie wyczerpuje stosu —
leci wiecznie, wolniej, a każdy skok wygląda jak zwykła praca, co czyni ją groźniejszą z dwóch. Złapanie
cyklu tylko na ścieżce synchronicznej przenosi awarię, nie usuwa jej. Łańcuch jest listą **stringów**, nie
atomów, bo przechodzi do argumentów joba jako JSON, a konwersja z powrotem kazałaby tabeli atomów ręczyć za
nazwę, która mogła zostać usunięta od czasu zakolejkowania.

**Mój komunikat błędu radził coś nieprawdziwego** i złapał to test asynchroniczny: pierwsza wersja
proponowała „zrób handler asynchronicznym, żeby powtórzenie stało się nowym przebiegiem". Nie pomaga —
łańcuch jedzie z jobem, więc pętla tylko zwalnia. Komunikat mówi teraz o tym wprost.

**Wyszło przy okazji, i było prawdziwym defektem 2.3:** wiersz obsługi w jobie zapisywał `"ok"`, a emisja
padała **pod nim**. Handlowanie i emitowanie siedzą teraz w jednej klauzuli `try`, bo wszystko, co może paść
przy działaniu na wyniku handlera — niezadeklarowana emisja, cykl, cofnięta transakcja — należy po tej samej
stronie zapisu.

**Drugi defekt, ta sama klasa co przy 1.2:** `graph_test` porównywał **globalną** listę krawędzi
asynchronicznych z oczekiwaniem jednego kontraktu, dwie linie pod komentarzem o ukrytym założeniu „jest tylko
jeden". Pękł, kiedy fikstura w innym kontrakcie zadeklarowała pierwszy handler asynchroniczny. Zawężone.

Zweryfikowane odwrotnie: po wyłączeniu bramy pada **cztery z siedmiu** testów, a suite trwa **32 sekundy
zamiast 0,1** — czyli widać dokładnie ten tryb awarii, o który tu chodzi.

**Kanoniczny hash — ✅ zrobione 6 sierpnia, wyciągnięte przed 2.2.** `PNS.Digest`, `test/digest_test.exs`.
Powód wyciągnięcia: 1.6 i 1.7 właśnie oparły klasyfikację historii na `contract_version`, więc luka
przestała być hipotetyczna — zaczęła podpierać raport dowodowy.

**Groźniejszy z dwóch defektów nie był tym, który miał w planie nazwę.** Aktualizacja OTP to zdarzenie, które
ktoś zauważa. **Przestawienie dwóch bloków `event` w pliku to zwykła edycja** — a `term_to_binary` liczył z
listy w kolejności deklaracji, więc wersja się ruszała, mimo że ustalenia nie. Kolejność deklaracji jest teraz
nieistotna, bo kontrakt jest **zbiorem** deklaracji, nie ciągiem.

Rozróżnienie, na którym stoi cały moduł: **kolekcje deklaracji sortujemy, wartości wewnątrz deklaracji nie.**
`instance: [:company_id, :period]` i odwrotność to dwa różne ustalenia, bo klucz przebiegu to te wartości
złączone w kolejności — posortowanie zrównałoby dwa różne klucze. To samo `stages:`, bo kolejność faz
decyduje, czy krawędź jest wsteczna.

Sortowanie idzie po kanonicznej postaci **całej** deklaracji, nie po kluczu `name`. Dzięki temu moduł nie
musi wiedzieć, który klucz nazywa deklarację, i nie ma grupy, której trzeba go nauczyć — `example` nie ma
`name` i to przestało być przypadkiem szczególnym.

`PNS.Deployment` liczy teraz z tego samego źródła, więc **obie tożsamości wdrożenia mają jedną kanoniczną
postać**, a nie jedną dobrą i jedną utwardzoną. Krawędzie są tam sortowane przed haszowaniem — to jedyne
miejsce, gdzie `PNS.Digest` potrzebuje pomocy wołającego, bo kolejność listy zachowuje świadomie.

**Cena zapłacona raz, jawnie: wersja skoczyła `7c229c333c21` → `0343089e9d75`.** Czyli poprawka wykonała
dokładnie to przeklasyfikowanie, któremu zapobiega — jednorazowo i celowo. Raport powie „zdarzeń z
wcześniejszych wersji ustaleń: N, to legalna historia", co jest uczciwe. **Konsekwencja dla harmonogramu:
to musiało wejść, zanim log klienta ma historię wartą zachowania**, i dlatego nie czekało na 2.2.

Fikstury (`Ordered`, `Reordered`, `Changed`) stoją **w pliku `.exs`**, bo rejestr skanuje listę modułów
aplikacji, a moduły z `.exs` w niej nie są — więc są niewidoczne dla grafu, tabeli wdrożeń i każdego raportu
ścieżek. Sprawdzone: `pns.check` pokazuje nadal 18 informacji i trzy kontrakty w rejestrze. Kontrakt, który
istnieje tylko po to, żeby go zahaszować, nie ma prawa wyjść w raporcie klienta jako proces bez przebiegów.

**2.5 Telemetria. ✅ zrobione 6 sierpnia — ETAP 2 ZAMKNIĘTY.** `PNS.Telemetry`, `test/telemetry_test.exs`.
206 testów.

**Dwie rodziny zdarzeń, i to, że tylko dwie, jest treścią tego punktu.** Kryterium doboru: emitujemy
wyłącznie to, czego **żadne inne narzędzie w stosie nie widzi**.

| Zdarzenie | Dlaczego my, a nie ktoś inny |
| --- | --- |
| `[:pns, :handler, :start/:stop/:exception]` | handlera synchronicznego nie widzi nikt — Oban zna *job*, nie handlera w środku |
| `[:pns, :contract, :violation]` | nikt inny nie wie, co klient uzgodnił; to jedyny sygnał „kod przestał zgadzać się z ustaleniami" **na żywo** |

Świadomie **nie** emitujemy: czasów zapytań (to Ecto), cyklu życia joba (to Oban), ani niczego, na co
odpowiada raport — bo to byłaby druga, przybliżona kopia własnego produktu.

**Licznik wyemitowanych zdarzeń napisałem i wyrzuciłem, i to jest uczciwsze niż go nie rozważyć.** Log ma tę
liczbę dokładnie, a metrykę dałoby się emitować tylko **z wnętrza transakcji** — czyli awaria handlera
synchronicznego cofałaby fakt, a licznik by go zachował. **Liczba fałszywa dokładnie wtedy, gdy coś jest
zepsute, jest gorsza niż brak liczby.** Do tego łamała regułę, którą sam zapisałem dwa akapity wyżej.

**Poprawiłem swój własny szew z 2.3.** Tamto zdarzenie wymyśliło własny kształt (`duration_us`, ręczne
`kind`/`reason`), bo rozwiązywałem problem diagnostyczny i nie zapytałem, co będzie musiał obejść integrator.
Teraz to `:telemetry.span/3` — `start`/`stop`/`exception`, `duration` w jednostkach natywnych, czyli kształt,
który Ecto, Phoenix i Oban już emitują. **Pakiet emitujący telemetrię *prawie* konwencjonalną kosztuje każdego
integratora osobny przypadek.**

**Reguła o metadanych jest regułą retencji.** Telemetria to **trzecia droga na zewnątrz**, po logu i
argumentach joba. Te dwie `retain` zamknął; metryka niosąca wartość payloadu otworzyłaby dokładnie tę dziurę
z powrotem. Metadane niosą **nazwy i klucz przebiegu** — nazwy są deklaracjami, a klucz jest w logu z założenia
i odtwarzalny z niego samego, więc oba są już tak publiczne jak log. Wartości payloadu nie są i nie pojawiają
się tam nigdy.

**`telemetry` weszło jako zależność bezpośrednia.** Było spełnione przechodnio przez Ecto i Obana — a pakiet,
którego zależność jest zaspokojona tylko dlatego, że sąsiad jej potrzebuje, **pęka, kiedy sąsiad wychodzi**.

**Katalog zdarzeń jest przypięty literałem** (`PNS.Telemetry.events/0`), bo nazwa zdarzenia telemetrii jest
tak samo publiczna jak nazwa funkcji: po cichej zmianie ten, kto się podłączył, przestaje cokolwiek dostawać i
dowiaduje się, gdy wykres pada na zero.

**Mój test retencji był pozorny i złapałem to przed commitem.** `item_noted` — jedyne pole na `retain: :drop`
w repo — nie miało handlera, więc nie było span-a i `refute_received` przechodziło, **nie dostając niczego**.
Doszedł handler, a test najpierw **stwierdza, że span był**, i dopiero potem czego w nim nie ma.

## Dług po stronie TaxVision

Jedna rzecz, która nie należy do silnika i nie miała dotąd swojego miejsca — **komenda
`RetriggerVerification` z warsztatu została w kontrakcie pominięta.** Do dołożenia razem z pętlą ponowienia,
przy prawdziwym materiale, nie przy moich założeniach o KSeF. Zapisane tutaj, bo README przestało być
dziennikiem i to był jedyny punkt roboczy, który mieszkał wyłącznie tam.

## Etap 3 — pakiet jako pakiet

Wydzielenie do `packages/pns_core` z path dep, żeby granicę wymuszał system budowania, nie tylko `boundary`.
✅ zrobione, razem z migracjami w stylu Obana i osobną suitą — patrz dopiski 20–21 sierpnia wyżej.

Trzy skille: dodaj zdarzenie, napisz handler, zmień kontrakt — ten trzeci jest najważniejszy, bo jako
jedyny wymaga zrobienia czegoś **przed** napisaniem kodu. **✅ `zmień kontrakt` zrobiony 21 sierpnia**
(`.claude/skills/change-contract/`) — tabela klasyfikacji delty sprawdzona przeciw źródłu: co refuduje
kompilator, co widzi `PNS.Deployment.diff/2` (tylko `events_added/removed`, `paths_added/removed` —
i nic więcej), i co jest cichą zmianą kontraktu bez żadnego wsparcia diff-owego (`retain`, `identity`,
`instance`, typ pola, parametry `trace`). Znalezisko warte zapisania osobno, nie tylko w skillu:
**`PNS.Trace.evaluate/3` nie ma wersjonowanej historii assercji** — zmiana `within`/`from`/`eventually`/
`or_else` na już zadeklarowanym `trace` reinterpretuje **wszystkie** historyczne przebiegi w chwili
wdrożenia, bez żadnego znaku w logu czy w tabeli wdrożeń, że werdykt liczył się pod inną obietnicą.
Nic tego dziś nie chroni; raport rozciągnięty na taką zmianę trzeba ręcznie ograniczyć `since:`.
**✅ `dodaj zdarzenie` i `napisz handler` zrobione 21 sierpnia**, równolegle, każdy w osobnym
subagencie (`.claude/skills/add-event/`, `.claude/skills/write-handler/`) — `module-boundary-check`
nie odsyła już do nieistniejących skilli, patrz jego krok 5. Znalezisko z `napisz handler`, warte
zapisania osobno: **handler odczytuje `meta.event` na żywo ze skompilowanych metadanych modułu w
chwili wykonania joba, nie w chwili zakolejkowania** — job zakolejkowany przed zmianą nazwy
zdarzenia, wykonany po tym, jak handler już wskazuje na nowe zdarzenie, castuje stary payload pod
nowy schemat po cichu (`lib/pns/job.ex:63`). Ten sam wzorzec co znalezisko z `zmień kontrakt` o
zmianie nazwy — teraz opisany z drugiej strony, od handlera.

**✅ CI zrobione 21 sierpnia** (`.github/workflows/ci.yml`) — jedno wywołanie `docker compose up -d
--wait` (ten sam plik co lokalnie, nie druga definicja Postgresa do rozjechania się z pierwszą), dwa
`mix deps.get` (host i `packages/pns_core` osobno — silnik jest zależnością `path`, ale
`package_test/1` woła `mix test` w nim jako **osobny proces Mixa**, z własnym `deps/`,
git-ignorowanym), potem `mix check`. **Sprawdzone, nie założone: `mix ecto.setup` z dokumentowanej
komendy lokalnej nie jest potrzebne do przejścia bramy** — usunięta lokalna baza `dev`, `mix check`
przeszedł mimo to (brama chodzi pod `MIX_ENV=test`, a bazy testowe stawia własny alias `test:`, i
hosta, i silnika). Cały workflow przejechany lokalnie od czystego stanu — usunięte `deps/`,
`_build/` obu projektów, świeże `mix deps.get` w obu, `mix check` zielony — bo `act` nie jest
zainstalowany i nie instalowałem go bez pytania.

**Czwarty skill, pierwszy dla człowieka. ✅ zrobiony 21 sierpnia** (`.claude/skills/review-pr/`) —
jak recenzować wygenerowany PR i **czego nie sprawdzać**, bo już pilnuje to check: kompletna lista
refuzacji kompilatora i błędów `mix pns.check` (część 1), obok listy, gdzie uwaga recenzenta
faktycznie się opłaca — ostrzeżenia/informacje `mix pns.check` wymagające osądu, `rule`/`example`
wyglądające na wymyślone, cicha edycja `identity`/`instance`/`retain`/`trace` na już zadeklarowanym
kontrakcie (odsyła do tabeli `zmień kontrakt`, nie duplikuje jej), brak twierdzenia „zweryfikowane
odwrotnie" przy poprawce błędu, polski tekst poza wąską dozwoloną powierzchnią, rozmiar diffu
niezgodny z zadeklarowanym zakresem. Notatki §8 wymieniają osiem skilli i wszystkie są dla agenta,
który pisze — a bramą jest recenzent, i dopiero teraz ma coś napisanego dla siebie.

**Etap 3 zamknięty w całości: 4/4 skille, migracje, osobna suita, CI.**

## Etap 4 — jeden ekran

Cztery pytania jako lista, nie graf. Sprawdzone: 11 zdarzeń dało 3 krawędzie i diagram nie powiedział nic,
czego nie mówiła posortowana lista. Bez alertów, bez stanu na żywo, bez czegokolwiek o konkretnej firmie.

**Zablokowane do rozstrzygnięcia:** notatki §9 mówią *„live, not a report … monitors eventually want alerts"*,
co jest w napięciu z zawężeniem zakresu. Etapy 1–3 są od tego niezależne.

## Rekord: gdzie jest i czego nie wolno z nim robić

**Pakiet projektowy jest tutaj, w [`docs/adr/`](docs/adr/).** Przeniesiony 6 sierpnia z repo
kontekstu i przerobiony z rekordu decyzji na **założenia początkowe**: nikt ich tutaj nie akceptuje, bo
decyzja, żeby tę ideę sprawdzić, już padła. Aparat, który do rekordu należał — kto recenzował, kto
zaakceptował, zakres komercyjny — został tam.

**Do `~/Projects/ai/empowered-house-context` nie piszemy. Nigdy.** Ani commita, ani gałęzi, ani poprawki w
pliku. Reguła jest z 6 sierpnia i ma powód: pakiet żył w obu repozytoriach naraz, poprawki jechały na gałąź
tam, podczas gdy autorytatywne pliki były już tutaj, i **przez pół dnia istniały dwie kopie tej samej
treści** — dokładnie ten dryf, który ten produkt wykrywa zawodowo. Czytać stamtąd wolno, jeśli ktoś o to
poprosi. Pisać — nie. Zapisane też w `CLAUDE.md`.

**Poprawki z etapów 1.1–1.7 są rozliczone i są w `docs/adr/`.** Dziewięć rzeczy, w tym trzy, w których kod
obalił rekord: bullet falsyfikacyjny mówiący, że `trace` i `deadline` nie mają czytelnika (dziś `trace` ma,
`deadline` nadal nie); zakład declared-vs-observed, którego oba wymienione zabezpieczenia okazały się
niewystarczające; i skew wersji, który nie obejmował usuniętego handlera. Historia jest w `git log`, nie tutaj
— **`PLAN.md` trzyma stan, nie archiwum**.

Została jedna rzecz, którą rekord mówi, a kod jeszcze nie — i jedna, którą rekord mówi, a kod **już nie
będzie**, rozstrzygnięte, nie zaniedbane:

- **§9 „navigation is per-process, never global”** wobec braku zawężenia w `PNS.Graph`. Luka, nie
  preferencja — należy do etapu 4, bo to jego wymaganie.
- **§9 okno „never observed" — odrzucone 6 sierpnia**, patrz „Rozstrzygnięte 6 sierpnia" wyżej i poprawka z
  datą w `docs/adr/technology-notes.md` §9. Rekord pytał, kiedy to zbudować; odpowiedź jest „nie budujemy",
  nie „jeszcze nie".

Gałąź `backup-polskie-opisy` usunięta 5 sierpnia po sprawdzeniu, że wszystkie siedem drzew jest w `main`.

## Kolejność

**Etap 1 zamknięty w całości.** 1.1–1.7 plus 1.5b. Brama uniwersalności przeszła, `trace` przestał być
dekoracją i ma dziś **cztery werdykty z czterech**, a różnica declared vs observed okazała się sygnałem —
50 przebiegów daje jedną linię raportu, i wszystkie pięć kształtów procesu jest obsłużonych.

**Etap 2 zamknięty w całości, 6 sierpnia.** 2.1–2.5. Obietnice kontraktu przestały być dekoracją: `publishes:`
wiąże handler, słownik typów jest zamknięty, wartości są walidowane, awaria synchroniczna zostawia ślad, cykl
jest zatrzymany na obu ścieżkach, a telemetria emituje to, czego nie widzi nikt inny. **Etap 1 startował na
42 testach, kończył na 133; etap 2 kończy na 221.**

### Co dalej: warsztat, nie kod

**Rehmed startuje 10 sierpnia, a największy zakład rekordu jest nietknięty** — czy prawdziwy process owner
przeczyta przykłady i je poprawi. Nic z etapu 2 tego nie ruszyło ani o milimetr; rusza to tylko warsztat.

Pytania przygotowane: [`docs/warsztat-rehmed.md`](docs/warsztat-rehmed.md). Zbudowane wokół zakładu, nie wokół
luk — **twierdzenia z liczbami do poprawienia, nie pytania otwarte**, bo pytanie otwarte daje prozę od
facylitatora, a poprawka jest jedyną rzeczą, która dowodzi, że ktoś przeczytał. Miary do zapisania dwie: ile
procent kontraktu przyszło z sali (przy TaxVision 40%) i **ile przykładów właściciel poprawił**.

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
  tego w PNS wymagałoby wiedzieć, **które konkretne instancje powinny istnieć**, żeby wykryć, których nie ma —
  a to jest wiedza o firmach, której silnik świadomie nie ma (§1, `claims: %{}`, żadnego `company_id` w żadnej
  strukturze `PNS`). Notatki §9 same mówią „count, not a list", ale nawet licznik wymaga mianownika, którego
  log zdarzeń, z zasady, nie widzi — encja, która nie wyemitowała nic, jest niewidzialna dla systemu opartego
  wyłącznie na logu. To nie jest to samo pytanie co „ekran na żywo" (kwestia interfejsu), tylko **strukturalny
  brak informacji, którego dokładanie oznaczałoby złamanie własnej reguły o firmach**. Poprawka z datą w
  [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) §9, nie ciche wykreślenie — ten mechanizm był
  tam opisany jako „open, do zdecydowania przed budową raportu z §9", więc to jest odpowiedź na tamto pytanie,
  a nie jego ignorowanie. Deklaracja `cadence` w kontrakcie zostaje — nie kosztuje nic i raport ją już wypisuje
  jako fakt („Należny: co miesiąc"), tylko monitor okna nie wchodzi.
- **`deadline` procesu — zwężone, nie odrzucone.** W przeciwieństwie do `cadence`'s „never observed", to jest
  policzalne wyłącznie z logu, bez żadnej wiedzy o firmach: pyta „z przebiegów, które **już się zaczęły**
  (mają zdarzenie `from`), ile przekroczyło uzgodniony czas trwania" — ten sam kształt, co dziś liczy
  `PNS.Trace` dla `violated`/`satisfied`, tylko licząc od pierwszego zdarzenia instancji, nie od konkretnego
  zdarzenia źródłowego jednej assercji. **Do zbudowania, jeszcze nie wykonane:** dodać do
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
- **~~`info` dla assercji bez `within`~~** — **już było zrobione**, ta pozycja była nieaktualna: sprawdzone
  w `pns.check.ex` (`check_unfalsifiable_assertions/1`) i w `test/check_ambiguity_test.exs`, oba istniały
  przed tą sesją. Zdjęte z listy, nie zaimplementowane drugi raz.
- **~~Wykluczenie przestrzeni nazw z raportu, z konfiguracji silnika~~** — zrobione: `config :pns, exclude:
  [...]` w `PNS.Registry.load!/1`.
- **~~Zbiór wartości `:enum`~~** — zrobione: `{:enum, [...]}` obok gołego `:enum`, opt-in, zero zmian w
  istniejących kontraktach.

**Do etapu 4, bo to jego wymaganie, nie dług:** zawężenie `PNS.Graph` do procesu i kontraktu.

Zamknięte 6 sierpnia bez zmiany w DSL: **`label` dla `trace` nie wchodzi** — powód przy 1.7.

Kod zostaje w tym repo i przenosi się do repozytorium pilota, gdy ono powstanie; struktura jest już taka, że
to `git mv`.
