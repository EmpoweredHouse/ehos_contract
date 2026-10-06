defmodule AppuniteEquipment.Contracts.Computers do
  @moduledoc """
  One employee computer, from the order to its end: what the person who manages the
  equipment decides about it and observes, and what must stay true.

  Written on 3 October 2026 from process 1 of
  `docs/appunite-equipment-2026-10-03-distillation.md`. The spreadsheet's two
  columns — where the computer is (`A:F`) and what is to be done with it in the
  office (`A:G`) — are not fields here. Where it is is the lifecycle's, which the
  engine follows from the events (#99); what is to be done follows from it and the
  setup, and is the Inventory read model's.

  ## One aggregate, and a run per assignment

  Every rule in the material is about one computer — whether it is set up, where it
  is, whether it is for sale — so every decision is this aggregate's, over one
  stream. The process owner chose to verify the run **per assignment**, from the
  issue to the return (distillation, "Zanim przeczytasz", shape B). A contract holds
  one process and every local event must carry its correlation, so that run is a
  sibling contract, `AppuniteEquipment.Contracts.Assignments`, which consumes the
  events of an assignment. What is left here is the computer's own run, from
  the invoice to one of its four ends, in four stages: intake, use, sale, ending.
  The computer goes round the same loop for years, and a contract's stages claim an
  order only forwards, so the whole loop is one stage, `:use`, inside which no order
  is claimed. Its beginning and its end go only forwards — nothing is registered
  after it was in use, and nothing takes a computer off sale — and that is what the
  stages claim. A first version had no stages at all, and its diagram was one row
  of seventeen boxes that said nothing (3 October 2026). The order inside the loop is
  the aggregate's lifecycle, not the process's (#99, 4 October 2026).

  ## What is left out, and why

  - **The order, and the person it is for** (`T l.58`, cf.pdf). A computer enters
    this contract when it is registered from the reseller's invoice, with no one
    yet (E, 4 October 2026: the computer is registered first, the person comes later).
    Who needs a computer, and whether one was bought for them, is a demand's
    (`AppuniteEquipment.Contracts.Demands`), and every issue answers one.
  - **The handover documents** (`T l.100–102`). The second person reads the serial
    number and the shipping date to write them, and nothing waits on the document.
  - **The sale invoice** is accounting's; the sale is recorded when it is issued.
  - **The order of the shelf before a new computer** (`T l.66`) is a preference the
    process owner was not sure of (`E`), not a rule.
  - **A replacement the employee keeps** needs no fact: it is an assignment that is
    never returned.
  - **A stolen computer** ends here; it carries its assignment, which it ends too
    (`Assignments`), and its employee, who needs another computer (`Demands`).
  """

  use EhOsContract.Contract,
    domain: AppuniteEquipment.Domain,
    context: :equipment,
    id: "appunite_equipment.computers"

  aggregate :computer, "Komputer" do
    # Generated, not the serial number: an identity is an `:id`, and the serial
    # number's own format is a value of the domain (`:serial_number`), checked on the
    # field the invoice gives.
    identity :computer_id, generated: :uuid

    state do
      field :chip, :chip, optional: true
      field :assignment_id, :id, optional: true
      field :set_up, :boolean, default: false
      field :reserved, :boolean, default: false
      field :listed_externally, :boolean, default: false
    end

    # The process owner said Innergo cleans the disk; that a repair erases it too is
    # not stated. Every return from Innergo asks for the setup again, which costs a
    # check of the MDM profile when the disk was kept.
    invariant :set_up_before_issue,
              "Komputera bez standardowych ustawień nie wydaje się pracownikowi; po zwrocie od pracownika, formatowaniu i powrocie z Innergo ustawia się go od nowa",
              source: "E"

    invariant :only_from_the_office,
              "Wydać, ustawić, sformatować, wysłać do Innergo, wystawić na sprzedaż, oddać albo zutylizować można tylko komputer, który jest w biurze",
              source: "A:F, A:G"

    invariant :withdrawn_generation_not_issued,
              "Komputera wycofanej generacji (dziś M1) nie wydaje się pracownikowi — idzie na sprzedaż",
              source: "T l.66, E"

    invariant :for_sale_not_issued,
              "Komputera wystawionego na sprzedaż nie wydaje się pracownikowi",
              source: "A:G"

    invariant :only_an_issued_computer_returns, "Zwraca się tylko komputer wydany pracownikowi",
      source: "A:F"

    invariant :only_a_listed_computer_is_sold,
              "Zarezerwować, wystawić na Allegro i sprzedać można tylko komputer wystawiony na sprzedaż",
              source: "T l.94–96, E"

    invariant :first_reservation_wins, "Na ryneczku komputer rezerwuje pierwszy, kto się zgłosi",
      source: "E"

    invariant :no_reservation_after_external_listing,
              "Po wystawieniu na Allegro ryneczek jest zamknięty",
              source: "E"

    invariant :allegro_only_without_reservation,
              "Na Allegro idzie komputer, którego nikt nie zarezerwował na ryneczku",
              source: "E: „chyba że nikt się nie zgłasza, to wtedy Allegro”"

    invariant :only_a_reservation_is_dropped, "Zwolnić można tylko istniejącą rezerwację",
      source: "E"

    # Where the computer is, in the spreadsheet's own words (A:F), and the moves the
    # team makes between them (plan LC4a, #99). The engine follows it from the events;
    # nothing sets it. Only what a decision depends on: "Zastępczy" is the assignment's,
    # and the setup is a flag beside it, since in the office a computer is either.
    lifecycle do
      status :in_office, "Office"
      status :issued, "W użytku"
      status :returning, "W trakcie zwrotu"
      status :in_service, "Innergo spa"
      status :for_sale, "For sale"
      status :sold, "Sold", final: true
      status :donated, "Charity", final: true
      status :disposed, "Utylizacja", final: true
      status :lost, "Lost", final: true

      initial :in_office, on: :received
      transition :in_office, :issued, :issued
      transition :issued, :return_started, :returning
      transition :returning, :returned, :in_office
      transition :in_office, :sent_for_service, :in_service
      transition :in_service, :service_returned, :in_office
      transition :in_office, :listed_for_sale, :for_sale
      transition :for_sale, :sold, :sold
      transition [:in_office, :for_sale], :donated, :donated
      transition [:in_office, :for_sale], :disposed, :disposed

      # The material knows one loss: a computer with an employee, stolen (E, "ostatnio
      # jeden został ukradziony"). A loss recorded anywhere else is still appended, and
      # the report shows it as a move the lifecycle does not allow.
      transition :issued, :lost, :lost
    end

    # The computer is born here, with what the invoice says it is (cf.pdf: "rejestracja
    # komputera (inventory)" after the purchase).
    command :receive_computer, "Spisz komputer z faktury",
      by: :equipment_manager,
      emits: :received,
      creates: true,
      source: "T l.88–90, E, cf.pdf" do
      field :profile, :hardware_profile
      field :serial_number, :serial_number
      field :chip, :chip
      field :price, :money
      field :purchased_on, :date
      field :invoice_number, :id
    end

    command :set_up_computer, "Ustaw komputer",
      by: :equipment_manager,
      emits: :set_up,
      from: :in_office,
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:G „Do ustawienia”, E"

    command :issue_computer, "Wydaj komputer pracownikowi",
      by: :equipment_manager,
      emits: :issued,
      from: [:in_office, :for_sale],
      or_rejects: :only_from_the_office,
      rejects: [
        :only_from_the_office,
        :set_up_before_issue,
        :withdrawn_generation_not_issued,
        :for_sale_not_issued
      ],
      source: "T l.100–102, E" do
      field :demand_id, :id
      field :assignment_id, :id
      field :employee_id, :id, subject: :employee
      field :shipped_on, :date
      field :tracking_number, :id, optional: true
      field :as_replacement, :boolean
    end

    command :start_return, "Rozpocznij zwrot",
      by: :equipment_manager,
      emits: :return_started,
      from: :issued,
      or_rejects: :only_an_issued_computer_returns,
      rejects: :only_an_issued_computer_returns,
      source: "A:F „W trakcie zwrotu”, T l.100" do
      field :reason, :return_reason
      field :returned_on, :date
    end

    command :wipe_computer, "Sformatuj komputer",
      by: :equipment_manager,
      emits: :wiped,
      from: :in_office,
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:G „Do wyczyszczenia”, E"

    command :send_for_service, "Wyślij do Innergo",
      by: :equipment_manager,
      emits: :sent_for_service,
      from: :in_office,
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:G „Wysłać do Innergo”, T l.106" do
      field :reason, :service_reason
    end

    command :put_up_for_sale, "Wystaw na sprzedaż",
      by: :equipment_manager,
      emits: :listed_for_sale,
      from: :in_office,
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:G „For sale”, E" do
      field :asking_price, :money
    end

    command :reserve_computer, "Zarezerwuj komputer z ryneczku",
      by: :equipment_manager,
      emits: :reserved,
      from: :for_sale,
      or_rejects: :only_a_listed_computer_is_sold,
      rejects: [
        :only_a_listed_computer_is_sold,
        :first_reservation_wins,
        :no_reservation_after_external_listing
      ],
      source: "T l.96, E" do
      field :buyer_id, :id, subject: :employee
    end

    command :drop_reservation, "Zwolnij rezerwację",
      by: :equipment_manager,
      emits: :reservation_dropped,
      from: :for_sale,
      or_rejects: :only_a_reservation_is_dropped,
      rejects: :only_a_reservation_is_dropped,
      source: "E"

    command :list_externally, "Wystaw na Allegro",
      by: :equipment_manager,
      emits: :listed_externally,
      from: :for_sale,
      or_rejects: :only_a_listed_computer_is_sold,
      rejects: [:only_a_listed_computer_is_sold, :allegro_only_without_reservation],
      source: "E"

    command :sell_computer, "Odnotuj sprzedaż",
      by: :equipment_manager,
      emits: :sold,
      from: :for_sale,
      or_rejects: :only_a_listed_computer_is_sold,
      rejects: :only_a_listed_computer_is_sold,
      source: "T l.110–112, E" do
      field :price, :money
      field :invoice_number, :id
    end

    command :donate_computer, "Oddaj komputer",
      by: :equipment_manager,
      emits: :donated,
      from: [:in_office, :for_sale],
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:F „Charity”, E"

    command :dispose_computer, "Zutylizuj komputer",
      by: :equipment_manager,
      emits: :disposed,
      from: [:in_office, :for_sale],
      or_rejects: :only_from_the_office,
      rejects: :only_from_the_office,
      source: "A:F „Utylizacja”, E"

    stage :intake do
      # The invoice gives the price, the purchase date — the warranty runs from it,
      # though the reseller keeps that register — and the serial number.
      event :received, "Komputer przyszedł i został spisany z faktury",
        depends_on: :apple_reseller,
        source: "T l.88–90, E, cf.pdf" do
        field :profile, :hardware_profile
        field :serial_number, :serial_number
        field :chip, :chip
        field :price, :money
        field :purchased_on, :date
        field :invoice_number, :id
      end
    end

    # The loop: issued, returned, cleaned, set up, issued again — for years. The run
    # claims no order inside: the computer's lifecycle does, and the assignment's own
    # run (`Assignments`) claims the order of one issue and its return.
    stage :use do
      event :set_up, "Komputer ustawiony (MDM, szyfrowanie dysku)", source: "E"

      # The handover document is written from the serial number and this date, which is
      # the shipping date (E). Picked up in person, it has no tracking number.
      # Assigning the person, setting up their account, packing and calling the
      # courier are one move (E, 4 October 2026), and it answers one demand.
      event :issued, "Wydano komputer pracownikowi", source: "T l.100–102, E" do
        field :demand_id, :id
        field :assignment_id, :id
        field :employee_id, :id, subject: :employee
        field :shipped_on, :date
        field :tracking_number, :id, optional: true
        field :as_replacement, :boolean
      end

      event :return_started, "Pracownik zwraca komputer",
        source: "A:F „W trakcie zwrotu”, T l.100" do
        field :assignment_id, :id
        field :reason, :return_reason
        field :returned_on, :date
      end

      # Seen arriving, not decided: nothing can refuse a parcel that came back.
      event :returned, "Zwrócony komputer dotarł do biura",
        recorded_by: :equipment_manager,
        source: "A:F" do
        field :assignment_id, :id
      end

      event :wiped, "Komputer sformatowany przed odłożeniem na półkę",
        source: "A:G „Do wyczyszczenia”, E"

      event :sent_for_service, "Komputer wysłany do Innergo",
        source: "A:F „Innergo spa”, T l.106" do
        field :reason, :service_reason
      end

      # What Innergo answered, retyped from its panel: the report used to go into a
      # comment on the computer's row (T l.106), the cost into the spreadsheet (E).
      # The diagnosis is about the computer, never a person, so it stays free text.
      event :service_returned, "Komputer wrócił z Innergo z diagnozą",
        recorded_by: :equipment_manager,
        depends_on: :apple_reseller,
        source: "T l.106–108, E" do
        field :diagnosis, :string
        field :cost, :money, optional: true
      end
    end

    # The sale goes only forwards: no command takes a computer off sale and back
    # into use.
    stage :sale do
      # The asking price comes from similar computers on Allegro (E).
      event :listed_for_sale, "Komputer wystawiony na sprzedaż", source: "A:G „For sale”, E" do
        field :asking_price, :money
      end

      event :reserved, "Komputer zarezerwowany na ryneczku", source: "T l.96, E" do
        field :buyer_id, :id, subject: :employee
      end

      event :reservation_dropped, "Rezerwacja przepadła", source: "E"

      event :listed_externally, "Komputer wystawiony na Allegro", source: "E"
    end

    # Every way a computer ends. A loss comes from any stage, and a computer given
    # away or disposed of from the office skips the sale: both only skip forwards.
    stage :ending do
      # Sold when accounting issues the invoice, and recorded by the person who
      # manages the equipment (E). A buyer from outside is accounting's data, never
      # this contract's.
      event :sold, "Komputer sprzedany", terminal: true, source: "T l.110–112, E" do
        field :price, :money
        field :invoice_number, :id
        field :channel, :sale_channel
      end

      event :donated, "Komputer oddany na cele charytatywne",
        terminal: true,
        source: "A:F „Charity”"

      event :disposed, "Komputer zutylizowany", terminal: true, source: "A:F „Utylizacja”"

      # One was stolen recently (E). Found again is "a small chance", and not modelled.
      # Only from an employee (#126), so it names the assignment it ends and the person
      # who now needs another computer (cf.pdf: a theft leads back to a purchase or the
      # shelf).
      event :lost, "Komputer zgubiony albo skradziony",
        recorded_by: :equipment_manager,
        terminal: true,
        source: "A:F „Lost”, E, cf.pdf" do
        field :assignment_id, :id
        field :employee_id, :id, subject: :employee
      end
    end
  end

  # The spreadsheet's Inventory tab: every computer AppUnite ever had, where it is,
  # and who has it (T l.94). Current is its rows in use, For Sale its rows for sale,
  # and the column of what is to be done in the office follows from the status and
  # the setup — none of them is a table of its own.
  read_model :inventory, "Inventory — wszystkie komputery i ich status",
    projects: [
      :received,
      :set_up,
      :issued,
      :return_started,
      :returned,
      :wiped,
      :sent_for_service,
      :service_returned,
      :listed_for_sale,
      :reserved,
      :reservation_dropped,
      :listed_externally,
      :sold,
      :donated,
      :disposed,
      :lost
    ] do
    field :computer_id, :id
    field :profile, :hardware_profile
    field :serial_number, :serial_number, optional: true
    field :chip, :chip, optional: true

    field :status,
          {:enum,
           [
             in_office: "Office",
             issued: "W użytku",
             replacement: "Zastępczy",
             returning: "W trakcie zwrotu",
             in_service: "Innergo spa",
             for_sale: "For sale",
             sold: "Sold",
             donated: "Charity",
             disposed: "Utylizacja",
             lost: "Lost"
           ]}

    field :set_up, :boolean
    field :employee_id, :id, subject: :employee, optional: true
    field :asking_price, :money, optional: true
    field :reserved, :boolean
  end

  query :inventory_list, "Lista komputerów", reads: :inventory, by: :equipment_manager

  process :computer, "Komputer: od faktury do sprzedaży, oddania, utylizacji albo utraty",
    accountable: :equipment_manager do
    correlate :computer_id
    stage :intake
    stage :use
    stage :sale
    stage :ending
  end

  scenario "komputer z faktury Innergo — spisany do inventory" do
    command :receive_computer, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    expect :received, %{serial_number: "K7HQ2F9X4M", chip: :m5}
  end

  scenario "nowy komputer ustawiony — wydany nowej osobie, wysłany pocztą" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    command :issue_computer, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      tracking_number: "00759007731234567890",
      as_replacement: false
    }

    expect :issued, %{assignment_id: "assignment-ola-1", shipped_on: "2026-10-01"}
  end

  scenario "nowy komputer bez MDM i szyfrowania — nie wychodzi z biura" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    command :issue_computer, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    rejected :set_up_before_issue
  end

  scenario "komputer wrócił z Innergo po czyszczeniu — bez ponownego ustawienia nie jest wydawany" do
    given :received, %{
      profile: :operations,
      serial_number: "C02XG2JHJGH5",
      chip: :m2,
      price: 549_900,
      purchased_on: "2023-03-14",
      invoice_number: "FV/2023/03/41"
    }

    given :set_up
    given :sent_for_service, %{reason: :cleaning}
    given :service_returned, %{diagnosis: "Wyczyszczony, bateria 91%"}

    command :issue_computer, %{
      assignment_id: "assignment-bartek-2",
      demand_id: "demand-bartek-2",
      employee_id: "employee-bartek",
      shipped_on: "2026-10-02",
      as_replacement: false
    }

    rejected :set_up_before_issue
  end

  scenario "komputer w Innergo — nie można go wydać jako zastępczego" do
    given :received, %{
      profile: :developer,
      serial_number: "C02XG2JHJGH5",
      chip: :m3,
      price: 1_049_900,
      purchased_on: "2024-01-10",
      invoice_number: "FV/2024/01/7"
    }

    given :set_up
    given :sent_for_service, %{reason: :repair}

    command :issue_computer, %{
      assignment_id: "assignment-maja-3",
      demand_id: "demand-maja-3",
      employee_id: "employee-maja",
      shipped_on: "2026-10-02",
      as_replacement: true
    }

    rejected :only_from_the_office
  end

  scenario "M1 w biurze, ustawiony — nie jest wydawany nowej osobie" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :set_up

    command :issue_computer, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    rejected :withdrawn_generation_not_issued
  end

  scenario "komputer wystawiony na sprzedaż — nie jest wydawany" do
    given :received, %{
      profile: :operations,
      serial_number: "C02XG2JHJGH5",
      chip: :m2,
      price: 549_900,
      purchased_on: "2023-03-14",
      invoice_number: "FV/2023/03/41"
    }

    given :set_up
    given :listed_for_sale, %{asking_price: 250_000}

    command :issue_computer, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    rejected :for_sale_not_issued
  end

  scenario "pracownik odchodzi — zwrot rozpoczęty" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    command :start_return, %{reason: :offboarding, returned_on: "2027-03-31"}
    expect :return_started, %{assignment_id: "assignment-ola-1", reason: :offboarding}
  end

  scenario "komputer leży w biurze — nie ma czego zwracać" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    command :start_return, %{reason: :offboarding, returned_on: "2027-03-31"}
    rejected :only_an_issued_computer_returns
  end

  scenario "zwrot w dobrym stanie — sformatowany przed odłożeniem na półkę" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :return_started, %{
      assignment_id: "assignment-ola-1",
      reason: :exchange,
      returned_on: "2027-03-31"
    }

    given :returned, %{assignment_id: "assignment-ola-1"}
    command :wipe_computer
    expect :wiped
  end

  scenario "komputer w drodze od pracownika — jeszcze nie do sformatowania" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :return_started, %{
      assignment_id: "assignment-ola-1",
      reason: :failure,
      returned_on: "2027-03-31"
    }

    command :wipe_computer
    rejected :only_from_the_office
  end

  scenario "M1 w biurze — wystawiony na ryneczek" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    command :put_up_for_sale, %{asking_price: 210_000}
    expect :listed_for_sale, %{asking_price: 210_000}
  end

  scenario "Paweł zgłasza się pierwszy — komputer zarezerwowany" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    command :reserve_computer, %{buyer_id: "employee-pawel"}
    expect :reserved, %{buyer_id: "employee-pawel"}
  end

  scenario "Paweł zarezerwował, zgłasza się Tadeusz — odmowa" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :reserved, %{buyer_id: "employee-pawel"}
    command :reserve_computer, %{buyer_id: "employee-tadeusz"}
    rejected :first_reservation_wins
  end

  scenario "komputer już na Allegro — pracownik go nie rezerwuje" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :listed_externally
    command :reserve_computer, %{buyer_id: "employee-tadeusz"}
    rejected :no_reservation_after_external_listing
  end

  scenario "komputer w biurze, niewystawiony — nie da się go zarezerwować" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    command :reserve_computer, %{buyer_id: "employee-pawel"}
    rejected :only_a_listed_computer_is_sold
  end

  scenario "Paweł się rozmyślił — rezerwacja przepada" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :reserved, %{buyer_id: "employee-pawel"}
    command :drop_reservation
    expect :reservation_dropped
  end

  scenario "nikt nie rezerwował — nie ma czego zwalniać" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    command :drop_reservation
    rejected :only_a_reservation_is_dropped
  end

  scenario "Paweł kupuje zarezerwowany komputer — księgowość wystawiła fakturę" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :reserved, %{buyer_id: "employee-pawel"}
    command :sell_computer, %{price: 210_000, invoice_number: "FS/2026/10/2"}
    expect :sold, %{price: 210_000, channel: :marketplace}
  end

  scenario "nikt się nie zgłosił — sprzedany na Allegro" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :listed_externally
    command :sell_computer, %{price: 195_000, invoice_number: "FS/2026/10/3"}
    expect :sold, %{channel: :allegro}
  end

  scenario "komputer w biurze, niewystawiony — sprzedaży się nie odnotowuje" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    command :sell_computer, %{price: 210_000, invoice_number: "FS/2026/10/2"}
    rejected :only_a_listed_computer_is_sold
  end

  scenario "Inventory: jeden komputer u Oli, jeden M1 na ryneczku" do
    given :received, %{
      profile: :developer,
      computer_id: "computer-1",
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up, %{computer_id: "computer-1"}

    given :issued, %{
      computer_id: "computer-1",
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :received, %{
      profile: :developer,
      computer_id: "computer-2",
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{computer_id: "computer-2", asking_price: 210_000}
    query :inventory_list

    answers [
      %{
        computer_id: "computer-1",
        serial_number: "K7HQ2F9X4M",
        status: :issued,
        set_up: true,
        employee_id: "employee-ola"
      },
      %{
        computer_id: "computer-2",
        serial_number: "C02DX1ABQ6LR",
        status: :for_sale,
        set_up: false,
        asking_price: 210_000,
        reserved: false
      }
    ]
  end

  scenario "sprzedany komputer, potem omyłkowo odnotowany zwrot — nie wraca do użytku" do
    given :received, %{
      profile: :operations,
      serial_number: "C02XG2JHJGH5",
      chip: :m2,
      price: 549_900,
      purchased_on: "2023-03-14",
      invoice_number: "FV/2023/03/41"
    }

    given :listed_for_sale, %{asking_price: 250_000}
    given :sold, %{price: 250_000, invoice_number: "FS/2026/10/2", channel: :marketplace}
    given :returned, %{assignment_id: "assignment-ola-1"}
    given :set_up

    command :issue_computer, %{
      assignment_id: "assignment-bartek-2",
      demand_id: "demand-bartek-2",
      employee_id: "employee-bartek",
      shipped_on: "2026-10-02",
      as_replacement: false
    }

    rejected :only_from_the_office
  end

  scenario "dotarł zwrot innego przydziału — komputer i tak jest w biurze" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :return_started, %{
      assignment_id: "assignment-ola-1",
      reason: :exchange,
      returned_on: "2027-03-31"
    }

    given :returned, %{assignment_id: "assignment-bartek-2"}
    command :wipe_computer
    expect :wiped
  end

  scenario "komputer u pracownika, odnotowany powrót z Innergo — nie trafia do drugiej osoby" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :set_up

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :service_returned, %{diagnosis: "Wyczyszczony"}
    given :set_up

    command :issue_computer, %{
      assignment_id: "assignment-bartek-2",
      demand_id: "demand-bartek-2",
      employee_id: "employee-bartek",
      shipped_on: "2026-10-02",
      as_replacement: false
    }

    rejected :only_from_the_office
  end

  scenario "komputer sprzedany Pawłowi — jego rezerwacji już się nie zwalnia" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :reserved, %{buyer_id: "employee-pawel"}
    given :sold, %{price: 210_000, invoice_number: "FS/2026/10/2", channel: :marketplace}
    command :drop_reservation
    rejected :only_a_reservation_is_dropped
  end

  scenario "Paweł zarezerwował — komputer nie idzie na Allegro" do
    given :received, %{
      profile: :developer,
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{asking_price: 210_000}
    given :reserved, %{buyer_id: "employee-pawel"}
    command :list_externally
    rejected :allegro_only_without_reservation
  end

  scenario "Inventory: oddany komputer bez rezerwacji, sprzedany zostaje sprzedanym" do
    given :received, %{
      profile: :developer,
      computer_id: "computer-2",
      serial_number: "C02DX1ABQ6LR",
      chip: :m1,
      price: 899_900,
      purchased_on: "2021-02-02",
      invoice_number: "FV/2021/02/3"
    }

    given :listed_for_sale, %{computer_id: "computer-2", asking_price: 210_000}
    given :reserved, %{computer_id: "computer-2", buyer_id: "employee-pawel"}
    given :donated, %{computer_id: "computer-2"}

    given :received, %{
      profile: :developer,
      computer_id: "computer-3",
      serial_number: "C02XG2JHJGH5",
      chip: :m2,
      price: 549_900,
      purchased_on: "2023-03-14",
      invoice_number: "FV/2023/03/41"
    }

    given :listed_for_sale, %{computer_id: "computer-3", asking_price: 250_000}

    given :sold, %{
      computer_id: "computer-3",
      price: 250_000,
      invoice_number: "FS/2026/10/2",
      channel: :marketplace
    }

    given :lost, %{
      computer_id: "computer-3",
      assignment_id: "assignment-ola-1",
      employee_id: "employee-ola"
    }

    given :returned, %{computer_id: "computer-3", assignment_id: "assignment-ola-1"}
    query :inventory_list

    answers [
      %{computer_id: "computer-2", status: :donated, reserved: false},
      %{computer_id: "computer-3", status: :sold}
    ]
  end

  scenario "zgubienie odnotowane dla komputera w biurze — komputer zostaje w biurze" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :lost, %{assignment_id: "assignment-ola-1", employee_id: "employee-ola"}
    query :inventory_list

    answers [%{status: :in_office}]
  end

  scenario "w Inventory zwrot innego przydziału też jest w biurze" do
    given :received, %{
      profile: :developer,
      serial_number: "K7HQ2F9X4M",
      chip: :m5,
      price: 1_199_900,
      purchased_on: "2026-09-29",
      invoice_number: "FV/2026/09/118"
    }

    given :issued, %{
      assignment_id: "assignment-ola-1",
      demand_id: "demand-ola-1",
      employee_id: "employee-ola",
      shipped_on: "2026-10-01",
      as_replacement: false
    }

    given :return_started, %{
      assignment_id: "assignment-ola-1",
      reason: :exchange,
      returned_on: "2027-03-31"
    }

    given :returned, %{assignment_id: "assignment-bartek-2"}
    query :inventory_list

    answers [%{status: :in_office, employee_id: nil}]
  end
end
