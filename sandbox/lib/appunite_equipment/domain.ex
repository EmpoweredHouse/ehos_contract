defmodule AppuniteEquipment.Domain do
  @moduledoc """
  The vocabulary of AppUnite's employee computers: one context, the person who
  manages them, the employee whose data the contracts carry, the reseller that both
  sells and services the computers, and the values.

  Written on 3 October 2026 from `docs/appunite-equipment-2026-10-03-distillation.md`.
  Only the equipment context is declared. Onboarding, the handover documents and
  accounting are upstream or downstream of it in the material, and none of them has
  a contract: each is a person reading the equipment's facts, not a process this
  domain models.
  """

  use EhOsContract.Domain, name: :appunite_equipment, language: :pl
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  subdomain :supporting, "Wsparcie", type: :supporting, source: "distillation, Domain"

  context :equipment, "Sprzęt pracowniczy", subdomain: :supporting, source: "T l.58" do
    term "Office",
      definition: "Komputer jest w biurze; co dalej, mówi kolumna „Dalsze działania”",
      source: "A:F, T l.90"

    term "Z półki",
      definition: "Komputer używany, dostępny w biurze, brany przed zamówieniem nowego",
      source: "T l.66, l.76–78" do
      avoid "Spółki", reason: "Błąd rozpoznania mowy w notatce z rozmowy"
    end

    term "New",
      definition:
        "Nowa osoba ma zamówiony komputer i czekamy na dostawę — stan zapotrzebowania, nie komputera",
      source: "A:F, E (2026-10-03, 2026-10-04)"

    # Our word, not the team's: the process owner's sketch of 4 October (cf.pdf) draws
    # it as the two ways a person gets a computer — a purchase or the shelf — opened by
    # a new person and by a theft, and the answers of that day add failure and exchange.
    term "Zapotrzebowanie",
      definition:
        "Osoba potrzebuje komputera: nowa osoba, kradzież, awaria albo wymiana; kończy się wydaniem komputera z półki albo kupionego",
      source: "cf.pdf (szkic właściciela procesu, 2026-10-04), E (2026-10-04)"

    term "Ustawienie",
      definition:
        "Standardowe ustawienia komputera, np. MDM i szyfrowanie dysku; bez nich komputera się nie wydaje",
      source: "E"

    term "Zastępczy",
      definition:
        "Komputer wydany pracownikowi, którego komputer ma awarię; pracownik może z nim zostać",
      source: "A:F, T l.94, E"

    term "Innergo spa",
      definition: "Komputer jest w Innergo, na czyszczeniu albo naprawie",
      source: "A:F, T l.106"

    term "Do wyczyszczenia",
      definition:
        "Komputer w dobrym stanie, który przed odłożeniem na półkę osoba zarządzająca sprzętem formatuje sama",
      source: "A:G, E"

    term "Ryneczek",
      definition:
        "Sprzedaż komputerów pracownikom: kto pierwszy, ten lepszy; gdy nikt się nie zgłasza, Allegro",
      source: "T l.96, E"
  end

  actor :equipment_manager, :human, "Osoba zarządzająca sprzętem", context: :equipment

  # The employee never acts in these contracts: the person who manages the equipment
  # records what was issued to whom, and who reserved what. Their identifier is
  # still personal data, and the contracts say whose.
  subject :employee, "Pracownik"

  # Innergo sells the computers (the invoice) and services them (cleaning, repair,
  # the warranty register). Nothing calls it: the person who manages the equipment
  # orders in its panel and retypes its statuses, so no event depends on it.
  external :apple_reseller, "Sprzedawca i serwis Apple (Innergo)", direction: :bidirectional

  relation :anticorruption_layer, upstream: :apple_reseller, downstream: :equipment

  # An Apple serial number. Older Macs carry twelve characters that encode the
  # factory, the week and the configuration; since 2021, starting with the first M1
  # Macs, it is random, ten characters, and Apple announced eight to fourteen.
  value :serial_number, :id, label: "Numer seryjny" do
    invariant :apple_format, "Numer seryjny Apple to od 8 do 14 wielkich liter i cyfr",
      violated_by: ["c02xg2jhjgh5", "C02 XG2JJGH5", "C02XG2J", "C02XG2JHJGH5ABC", "FV/7/2026"],
      satisfied_by: ["C02XG2JHJGH5", "K7HQ2F9X4M"],
      source: "E: format komputerów Apple"
  end

  value :chip, {:enum, [m1: "M1", m2: "M2", m3: "M3", m4: "M4", m5: "M5"]},
    label: "Generacja procesora"

  # T l.74: the rules are written down, and the employee does not choose.
  value :hardware_profile,
        {:enum, [developer: "Programista — MacBook Pro", operations: "Operacje — MacBook Air"]},
        label: "Profil sprzętu"

  value :money, :integer, unit: :grosze, label: "Kwota"

  value :demand_reason,
        {:enum,
         [new_hire: "Nowa osoba", theft: "Kradzież", failure: "Awaria", exchange: "Wymiana"]},
        label: "Powód zapotrzebowania"

  value :return_reason,
        {:enum, [offboarding: "Odejście pracownika", exchange: "Wymiana", failure: "Awaria"]},
        label: "Powód zwrotu"

  value :service_reason, {:enum, [cleaning: "Czyszczenie", repair: "Naprawa"]},
    label: "Powód wysyłki do Innergo"

  value :sale_channel, {:enum, [marketplace: "Ryneczek", allegro: "Allegro"]},
    label: "Kanał sprzedaży"
end
