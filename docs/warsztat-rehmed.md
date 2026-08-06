# Warsztat Rehmed — pytania, których zabrakło przy TaxVision

Po polsku, bo to materiał, który czyta się klientowi na głos. Nie jedzie z pakietem i nie
jest dokumentacją silnika — dlatego nazwa pliku też jest polska.

## Do czego to jest

Warsztat ma wyjść z **kontraktem, który się kompiluje**, a nie z mapą procesu. Przy
TaxVision wyszedł z mapą i to jest zmierzone: **z warsztatu przyszło jakieś 40% kontraktu,
i to ta łatwiejsza połowa.**

| Warsztat dał | Trzeba było wymyślić |
| --- | --- |
| nazwy zdarzeń + polskie opisy | kształty payloadów — zero pól |
| aktorów | typy pól |
| polityki „kiedy X, to Y" | ścieżki błędów przy niedostępnej zależności |
| bramki i kolejność faz | klucze idempotencji |
| hotspoty i pytania otwarte | stany terminalne |
| kandydatów na agregaty | termin 25 dni — **jedyna liczba w kontrakcie bez źródła** |

Prawa kolumna to nie zaniedbanie facylitatora. To rzeczy, których **nie da się wymyślić za
klienta**, a które kompilator wymusza — i dlatego są warte drugiej sesji, nie domysłu.

## Jak prowadzić, żeby przetestować zakład, na którym stoi produkt

Rekord nazywa wprost zakład decydujący, czy z tego w ogóle jest produkt: **prawdziwy
właściciel procesu przeczyta przykłady i je poprawi.** I podaje miarę: *trzydzieści
przykładów i zero poprawek znaczy, że nikt nie czytał.*

Z tego wynika sposób prowadzenia, i jest odwrotny do intuicji:

> **Nie zadawaj pytań otwartych. Stawiaj twierdzenia z liczbami i proś o poprawienie.**

Pytanie otwarte („jakie pola ma to zdarzenie?") daje prozę od facylitatora. Twierdzenie
nieprawdziwe („zakładam, że wizyta odwołana mniej niż 24 h przed terminem liczy się jako
odbyta") daje **poprawkę od właściciela** — a poprawka jest jedyną rzeczą, która dowodzi,
że ktoś przeczytał.

Praktycznie: przed każdą sekcją poniżej powiedz „przygotowaliśmy założenie, powiedz, gdzie
jest błędne". Licz poprawki. Ta liczba jest wynikiem warsztatu na równi z kontraktem.

## Czego nie wolno przywieźć na warsztat

**Nie pokazuj `UniversalityGate.TreatmentEpisode` i nie używaj jego słownictwa.** W repo
leży wymyślony kontrakt medyczny — `referral_received`, `payer_eligibility_checked`,
`session_completed` i tak dalej. Powstał, żeby sprawdzić, czy DSL opisze inną domenę, i
**ani jedna z tych nazw nie pochodzi od nikogo z Rehmed**. Postawiony na stole zakotwiczy
klienta na naszej wyobraźni, a wtedy warsztat potwierdzi nasze zmyślenie zamiast dostarczyć
ich proces. Plik ma to napisane w pierwszej linii i tam ma zostać.

**Nazwy zdarzeń pochodzą od klienta, w jego słowach, w czasie przeszłym.** Notujcie polski
oryginał obok nazwy technicznej — przy TaxVision to się opłaciło, bo pozwala wrócić do
tego, co ktoś faktycznie powiedział.

**Zapisuj źródło przy każdej liczbie.** Timestamp nagrania wystarczy. Liczba bez źródła
wchodzi do kontraktu jako `unverified` i **nie liczy się do raportu dowodowego** — patrz
ostatnia sekcja.

---

# Pytania, ułożone po tym, co zasilają

## 1. Kształt faktu → `payload`

Dla **każdego** zdarzenia, po nazwie:

- **Co trzeba wiedzieć, żeby to zdarzenie miało sens za rok, bez patrzenia w system?**
  Nie „co jest w bazie", a „co jest treścią tego faktu".
- **Które z tych pól identyfikują coś, a które są treścią?** Silnik ma pięć typów i tylko
  tyle: identyfikator, tekst wpisany przez człowieka, liczba całkowita, punkt w czasie,
  jedna z ustalonego zbioru. Jeśli coś nie wchodzi w żaden — to sygnał, nie problem.
- **Czy któreś pole może być puste?** Odpowiedź „czasem tak" znaczy, że to są **dwa różne
  zdarzenia**, nie jedno z dziurą. Pole zadeklarowane i puste jest dziś błędem emisji.

*Bez tego:* generator wymyśla pola przy każdym uruchomieniu inaczej, a raport dowodowy
mówi o faktach, których treści nikt nie ustalił.

## 2. Kiedy dwa razy to jeden raz → `identity`

- **Ta sama rzecz zgłoszona dwa razy — to jeden fakt czy dwa?** Przy TaxVision okazało się,
  że dwa różne rozjazdy w jednym miesiącu to dwa powiadomienia, a ten sam rozjazd
  powtórzony — jedno. Bez tego rozróżnienia system albo spamuje, albo połyka drugi problem.
- **Po czym rozpoznasz, że to ta sama rzecz?** To jest lista pól, nie zdanie.

*Bez tego:* przy ponowieniu handler wykona pracę drugi raz. Kolejka gwarantuje
at-least-once, więc **to nie jest dobra praktyka, a warunek poprawności**.

## 3. Co jest jednym przebiegiem → `instance`

- **Co jest „jedną sprawą" od początku do końca?** Przy TaxVision: jedna firma w jednym
  miesiącu. Tu prawdopodobnie jeden pacjent w jednym czymś — ale **czym**, nie zgaduję.
- **Czy dwie takie sprawy mogą lecieć równolegle dla tej samej osoby?** Jeśli tak, to co je
  rozdziela.

*Bez tego:* assercja „po X następuje Y" zalicza Y z **cudzego** przebiegu, a licznik
pokazujący „49 przejechań" nie odróżnia jednego pacjenta powtarzającego czynność
czterdzieści dziewięć razy od czterdziestu dziewięciu pacjentów.

## 4. To samo zdarzenie wiele razy → `identity` kontra `instance`

- **Czy w jednej sprawie to samo zdarzenie zdarza się wielokrotnie?** Wizyty, próby
  kontaktu, kolejne badania.
- Jeśli tak: **czym różni się druga od pierwszej?** Numerem, datą, czymś innym.

*Bez tego:* dziesięć wizyt w jednym epizodzie zostanie policzone jako dziesięć epizodów
albo jako jedna wizyta powtórzona — oba są fałszem, w przeciwnych kierunkach.

## 5. Gdzie się to kończy → `terminal`

- **Wymień wszystkie sposoby, w jakie ta sprawa się kończy** — także te złe.
- **Czy porzucenie / odmowa / rezygnacja pacjenta to zakończenie, czy zawieszenie?**

*Bez tego:* raport nigdy nie powie „ten krok nie został wykonany ani razu", bo nie wie,
kiedy przestać czekać. Przy TaxVision zablokowanie miesiąca **jest** zakończeniem, i to
było nasze założenie, nie ich słowo.

## 6. Kolejność, ale tylko tam, gdzie jest → `stages`

- **Co bez czego nie może się stać?** Pytaj o bramki, nie o kolejność.
- **Co dzieje się równolegle albo w dowolnej kolejności?**

*Bez tego:* wpiszemy w kontrakt liniową kolejność jako model klienta — a na tej kolejności
stoi wykrywanie kroków wstecznych, więc check zacznie egzekwować **nasz wymysł**. Przy
TaxVision klient powiedział wprost: *„fazy nie są w pełni sekwencyjne, sekwencyjne są
bramki"*, i pierwsza wersja kontraktu i tak to zignorowała.

## 7. Czego proces obiecuje dopilnować → `trace`

Tu stawiaj twierdzenia, nie pytania. Forma jest zawsze ta sama:

> **Po** `zdarzenie A` **w ciągu** `N` **następuje** `zdarzenie B`, **albo** `zdarzenie C`.

- **Czy to jest obietnica, którą składacie pacjentowi albo płatnikowi?**
- **Ile czasu?** Liczba i jednostka. Nie „szybko".
- **Czy to `N` obowiązuje także drogę awaryjną?** Czyli: jeśli sprawa się nie udaje,
  powiadomienie musi wyjść w tym samym terminie, czy „kiedy zauważymy"? **To jest jedyne
  pytanie z tej listy, na które my mamy dziś odpowiedź, i jest nasza, nie ich** — silnik
  zakłada, że termin wiąże obie drogi. Jeśli u nich jest inaczej, raport będzie pokazywał
  naruszenia, których nie ma.

*Bez tego:* nie ma czego weryfikować. Cały produkt to porównanie tej obietnicy z logiem.

## 8. Jak często to jest należne → `cadence`

- **Czy ta sprawa jest kiedykolwiek „należna"?** Miesiąc księgowy jest — co miesiąc. Ale
  epizod leczenia **nigdy nie jest należny**: zaczyna się, kiedy wpłynie skierowanie.
- Jeśli nie jest należna: **po jakim czasie milczenia uznajecie, że coś stanęło?**

*Bez tego:* mechanizm „nigdy nie zaobserwowano" nie ma skąd wziąć długości okna. Dla
procesów zdarzeniowych to **stan normalny, nie przypadek brzegowy** — i to jedyna rzecz,
której wymyślony kontrakt medyczny nauczył nas o prawdziwym.

---

# Cztery pytania, których nikt nie zadaje na event stormingu

Te są specyficzne dla PNS i przy TaxVision wypadły w całości. Trzy z nich są w domenie
medycznej **dużo ważniejsze** niż w księgowej.

## 9. Co nie ma prawa wylądować w logu na zawsze → `retain`

Log jest append-only i to jest cały jego sens. Więc:

- **Które z tych pól to dane o zdrowiu?** Nie „dane osobowe" — dane o zdrowiu, bo to inna
  kategoria i inny reżim.
- **Które z nich muszą zostać na stałe, a które wystarczy, że *były*?** Silnik umie trzy
  polityki: zostaw, zostaw hash, wyrzuć. Hash daje dowód, że coś się stało i **które to
  było**, bez trzymania treści.
- **Czy handler potrzebuje surowej wartości?** Jeśli tak, to pole nie może być hashowane —
  i to jest konsekwencja dla kontraktu, nie dla kodu.

*Bez tego:* diagnoza pacjenta trafia do logu dosłownie, na zawsze, i żaden późniejszy
`retain` tego nie cofnie. **Retencja jest jedyną rzeczą z tej listy, której nie da się
dołożyć potem.**

## 10. Co znaczy, że system zewnętrzny nie odpowiada → `external`, `unavailable_looks_like`

- **Od jakich systemów zewnętrznych zależy ten proces?** Nazwijcie je faktem biznesowym,
  nie dostawcą — „rejestr płatnika", nie nazwa oprogramowania.
- **Jak wygląda ich niedostępność?** Timeout, pusta odpowiedź, odpowiedź bez treści — **w
  waszych słowach, całym zdaniem.** To zdanie idzie do kontraktu i czyta je człowiek.
- **Czy „nie odpowiada" znaczy to samo co „odpowiedział nie"?** Prawie nigdy nie znaczy, a
  systemy zwykle to zlewają.

*Bez tego:* awaria czyjegoś serwera w okresie obietnicy liczy się jako **wasze**
niedotrzymanie. Silnik umie już tego nie robić, ale tylko jeśli wie, od czego zależy które
zdarzenie i jak wygląda awaria.

## 11. Która reguła ma przykład, który zadziałał, i przykład, który poszedł źle → `example`

Dla każdej reguły „kiedy X, to Y":

- **Podaj jeden przypadek, w którym to zadziałało — z prawdziwymi liczbami.**
- **Podaj jeden, w którym poszło źle.**

Prawdziwe liczby, nie „jakiś pacjent". Ten przykład **staje się testem** — i to jest
mechanizm, przez który właściciel procesu ma nad kodem kontrolę bez czytania kodu.

*Bez tego:* reguła bez przykładu **się nie kompiluje** i to jest jedyna brama, którą można
pokazać osobie nietechnicznej.

## 12. Które liczby są wasze, a które nasze → `unverified`

Na koniec, przez cały kontrakt:

- **Przeczytaj każdą liczbę na głos i powiedz, czy ona od was pochodzi.**

Wszystko, czego nie potwierdzą, wchodzi jako `unverified` i **nie liczy się do raportu
dowodowego** — bo liczba, której klient nie uzgodnił, wypisana obok liczb uzgodnionych,
czyta się jako zmierzona. Przy TaxVision jest jedna taka: termin 25 dni, wzięty z przykładu
w naszych notatkach.

---

# Co ma wyjść z sali

Kontrakt kompiluje się, kiedy dla każdego procesu jest:

- [ ] nazwy zdarzeń w czasie przeszłym, słowami klienta, z polskim oryginałem
- [ ] pola każdego payloadu, z typem z pięciu dostępnych
- [ ] `identity` — co czyni dwa wystąpienia tym samym faktem
- [ ] `instance` — co czyni dwa zdarzenia jedną sprawą
- [ ] co najmniej jedno zdarzenie terminalne, wliczając złe zakończenia
- [ ] bramki, czyli „co bez czego"; kolejność wewnątrz fazy **zostaw pustą**
- [ ] co najmniej jedna assercja `trace` z terminem i liczbą
- [ ] `retain` dla każdego pola, które jest danymi o zdrowiu
- [ ] zależności zewnętrzne + zdanie, jak wygląda ich niedostępność
- [ ] dwa przykłady na regułę: jeden udany, jeden nieudany, z liczbami
- [ ] źródło przy każdej liczbie, albo świadome `unverified`

## Miara warsztatu

Dwie liczby, obie zapisać:

1. **Ile procent kontraktu przyszło z sali** — przy TaxVision 40%. Jeśli wyjdzie tyle samo,
   to nie warsztat jest zły, a nasze przygotowanie.
2. **Ile przykładów właściciel procesu poprawił.** To jest test zakładu, na którym stoi
   produkt. **Zero poprawek przy trzydziestu przykładach znaczy, że nikt nie czytał** — i
   wtedy trzeba to powiedzieć wprost, a nie zapisać jako sukces.
