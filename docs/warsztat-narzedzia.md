# Narzędzia warsztatowe — co, kiedy, w jakiej kolejności

Po polsku, bo to dokumentacja repo dla zespołu, nie kod i nie coś, co czyta klient. Nie jedzie z
pakietem.

## Dwa repozytoria, jeden łańcuch pracy

**`appunite/process-native-software` powstało pierwsze.** To jest właściciel metodologii Process
Mapping — jak prowadzić warsztat, jaki zespół, jak nagrywać, jakie są fazy 1-4, i ma tam już
**zwalidowany** (jedyny tak oznaczony w tamtym repo) skill `process-extraction`, który zamienia
surowe transkrypty Dnia 1 w mapę procesu biznesowego.

**`eh-os-contract` powstało później**, jako test jednej konkretnej idei: czy da się zbudować silnik
weryfikujący zgodność wdrożonego kodu z zadeklarowanym procesem. To repo jest dziś tymczasowe —
`README.md` mówi to wprost. Jeśli idea się sprawdzi, `process-native-software` prawdopodobnie
kiedyś trafi **tutaj**, jako podkatalog metodologii, którą ten silnik obsługuje — nie odwrotnie.
Do tego czasu repozytoria zostają osobne, i **do `process-native-software` nic nie piszemy bez
pytania** — to nie jest nasz playbook, ma własne zasady zarządzania (`AGENTS.md` tamtego repo).

## Skille, w kolejności użycia

| Kiedy | Skill | Gdzie mieszka | Co robi | Co NIE robi |
| --- | --- | --- | --- | --- |
| Po Dniu 1 warsztatu | `process-extraction` | `process-native-software` (zewnętrzny, zwalidowany) | Surowy transkrypt → mapa procesu biznesowego (`output/01-processes.md`): aktorzy, kroki, narzędzia, wyjątki, punkty bólu | Nie wie nic o DSL-u EhOsContract; nie generuje kontraktu |
| Po Dniu 2, albo dużo później — kiedykolwiek jest materiał i czas | `contract-distillation` | `eh-os-contract` (ten skill) | To samo źródło (najlepiej już przetworzone przez `process-extraction`) → destylacja pod kategorie, których wymaga kontrakt: kandydaci na zdarzenia, `identity`, `instance`, `terminal`, `stages`, kandydaci na `trace`, `cadence`, `retain`, `external`, przykłady, źródła/`unverified` | Nie generuje kodu Elixira; nie jest mapą procesu biznesowego (to już zrobił `process-extraction`) |
| Podczas pisania kodu aplikacji (backend, API, frontend) | `module-boundary-check` | `eh-os-contract` (ten skill) | Dla konkretnej akcji: (1) czy w ogóle iść przez event/handler EhOsContract, (2) osobno, czy ten event potrzebuje `trace`/`instance`/`process` | Nie decyduje za Ciebie w niejasnych przypadkach — każe zapytać |

**`docs/warsztat-rehmed.md` to coś czwartego, nie z tej tabeli** — to nie skill uruchamiany na
materiale, tylko przygotowane pytania **na żywo, w trakcie sesji z klientem**, budowane na
podstawie luk znalezionych przy TaxVision. Zabiera się je na warsztat, nie odpala się ich po
fakcie.

## Dlaczego `contract-distillation` nie duplikuje `process-extraction`

Oba czytają ten sam rodzaj materiału, ale pytają o co innego:

- `process-extraction` pyta o **zrozumienie biznesowe** — po to, żeby zbudować wireframe'y i mapę
  AS-IS/TO-BE. Odbiorcą jest projektant i sam klient (mapa idzie do potwierdzenia).
- `contract-distillation` pyta o **gotowość kontraktu** — kategorie z `packages/eh_os_contract/docs/contract.md`, które
  prędzej czy później trzeba wypełnić, żeby `EhOsContract.Contract` się skompilował. Odbiorcą jest ten, kto
  usiądzie pisać plik `.ex` — czasem tego samego dnia, czasem za miesiąc.

Stąd kolejność preferencji wejścia w `contract-distillation`: **najpierw sprawdź, czy istnieje już
wynik `process-extraction`** (jest przejrzany przez człowieka, więc tańszy i pewniejszy punkt
startu) — a surowy transkrypt tylko wtedy, gdy tamtego jeszcze nie ma.

## Co jest wciąż tylko szkicem

Wszystkie trzy skille natywne dla `eh-os-contract` (`contract-distillation`, `module-boundary-check`)
są oznaczone `DRAFT` w swoich plikach `SKILL.md` — nieprzetestowane na prawdziwym zaangażowaniu.
Warsztat z Rehmed (10-11 sierpnia) jest pierwszą okazją, żeby to sprawdzić na żywym materiale.
Aktualizować tę tabelę i pliki skilli po każdym realnym użyciu — zgodnie z tym, jak
`process-native-software` prowadzi swój log poprawek warsztatowych w
`Service Delivery/Process-Mapping-Playbook.md`.
