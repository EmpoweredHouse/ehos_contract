defmodule GraphLab.Contracts.Till do
  @moduledoc """
  **Added to the test set to test the graph on; not client material** (`GraphLab`).

  Reception's till: the day it is open, from the opening to the close after the cash is
  counted (`E-83`, `AGG-07`, which Rehmed leaves out of E9), and the cash a patient is
  refunded when a settlement is corrected downwards. It is the second contract of
  settlement's context, the one contract with two units, each with a lifecycle, and its
  own process, `GraphLab.Processes.TillDay`.
  """

  use EhOsContract.Contract, domain: GraphLab.Domain, context: :settlement, id: "graph-lab.till"

  consumes GraphLab.Contracts.Settlement, :settlement_corrected

  aggregate :till_day, "Dzień kasowy" do
    identity :day_id

    state do
      field :counted, :money, optional: true
    end

    invariant :a_closed_day_does_not_change, "Zamkniętego dnia kasowego się nie zmienia",
      source: "AGG-07; dodane do testów grafu"

    invariant :cash_counted_before_close,
              "Dzień kasowy zamyka się dopiero po przeliczeniu gotówki",
              source: "E-83; dodane do testów grafu"

    lifecycle do
      status :open, "Otwarty"
      status :closed, "Zamknięty", final: true

      initial :open, on: :day_opened
      transition :open, :day_closed, :closed
    end

    command :open_till_day, "Otwórz dzień kasowy",
      by: :reception,
      emits: :day_opened,
      source: "dodane do testów grafu"

    command :count_cash, "Przelicz gotówkę w kasie",
      by: :reception,
      emits: :cash_counted,
      from: :open,
      or_rejects: :a_closed_day_does_not_change,
      rejects: :a_closed_day_does_not_change,
      source: "dodane do testów grafu" do
      field :counted, :money
    end

    command :close_till_day, "Zamknij dzień kasowy",
      by: :manager,
      emits: :day_closed,
      from: :open,
      or_rejects: :a_closed_day_does_not_change,
      rejects: [:a_closed_day_does_not_change, :cash_counted_before_close],
      source: "E-83"

    event :day_opened, "Otwarto dzień kasowy", source: "dodane do testów grafu"

    event :cash_counted, "Przeliczono gotówkę w kasie", source: "dodane do testów grafu" do
      field :counted, :money
    end

    event :day_closed, "Zamknięto dzień kasowy", source: "E-83" do
      field :counted, :money
    end
  end

  aggregate :cash_refund, "Zwrot gotówki pacjentowi" do
    identity visit_id: {:id, :visit}

    invariant :a_refund_is_paid_out_once, "Zwrot wypłaca się raz",
      source: "dodane do testów grafu"

    lifecycle do
      status :owed, "Do wypłaty"
      status :paid_out, "Wypłacony", final: true

      initial :owed, on: :refund_owed
      transition :owed, :refund_paid_out, :paid_out
    end

    # Issued by the policy on a correction downwards, never by a person.
    command :owe_refund, "Zapisz zwrot do wypłaty",
      emits: :refund_owed,
      source: "E-84; dodane do testów grafu" do
      field :amount, :money
    end

    command :pay_out_refund, "Wypłać zwrot z kasy",
      by: :reception,
      emits: :refund_paid_out,
      from: :owed,
      or_rejects: :a_refund_is_paid_out_once,
      rejects: :a_refund_is_paid_out_once,
      source: "dodane do testów grafu"

    event :refund_owed, "Zwrot czeka na wypłatę z kasy", source: "dodane do testów grafu" do
      field :amount, :money
    end

    event :refund_paid_out, "Wypłacono zwrot z kasy", source: "dodane do testów grafu"
  end

  policy :refund_on_correction, "Korekta w dół — zwrot do wypłaty z kasy",
    handles: :settlement_corrected,
    issues: :owe_refund,
    source: "E-84; dodane do testów grafu" do
    constraint :only_corrections_downwards,
               "Zwrot zapisuje się tylko przy korekcie w dół; korekta w górę to dopłata pacjenta",
               source: "dodane do testów grafu"
  end

  scenario "recepcja otwiera dzień kasowy" do
    command :open_till_day
    expect :day_opened
  end

  scenario "gotówka przeliczona — dzień kasowy się zamyka" do
    given :day_opened
    given :cash_counted, %{counted: 120_000}
    command :close_till_day
    expect :day_closed, %{counted: 120_000}
  end

  scenario "gotówka nieprzeliczona — zamknięcie dnia odrzucone" do
    given :day_opened
    command :close_till_day
    rejected :cash_counted_before_close
  end

  scenario "dzień zamknięty — ponowne przeliczenie odrzucone" do
    given :day_opened
    given :cash_counted, %{counted: 120_000}
    given :day_closed, %{counted: 120_000}
    command :count_cash, %{counted: 125_000}
    rejected :a_closed_day_does_not_change
  end

  scenario "korekta o 10 zł w dół — zwrot do wypłaty",
    illustrates: :only_corrections_downwards do
    target :refund_on_correction

    on :settlement_corrected, %{
      visit_id: "visit-anna",
      delta: -1_000,
      business_date: "2026-10-05"
    }

    issues :owe_refund, %{visit_id: "visit-anna", amount: 1_000}
  end

  scenario "zwrot zapisany — recepcja wypłaca go z kasy" do
    given :refund_owed, %{amount: 1_000}
    command :pay_out_refund
    expect :refund_paid_out
  end

  scenario "zwrot już wypłacony — druga wypłata odrzucona" do
    given :refund_owed, %{amount: 1_000}
    given :refund_paid_out
    command :pay_out_refund
    rejected :a_refund_is_paid_out_once
  end
end
