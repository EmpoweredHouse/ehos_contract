defmodule GraphLab.Contracts.Till do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  Reception's till: the day it is open, from the opening to the close after the cash is
  counted (`E-83`, `AGG-07`), and the cash a patient is
  refunded when a settlement is corrected downwards. It is the second contract of
  settlement's context, a contract with two units, each with a lifecycle, and its
  own process, `GraphLab.Processes.TillDay`.
  """

  use EhOsContract.Contract, domain: GraphLab.Domain, context: :settlement, id: "graph-lab.till"

  consumes GraphLab.Contracts.Settlement, :settlement_corrected

  aggregate :till_day, "Dzień kasowy" do
    identity :day_id

    state do
      field :counted, :money, optional: true
    end

    invariant :a_day_is_opened_once, "Dzień kasowy otwiera się raz",
      source: "AGG-07; dodane do testów grafu"

    invariant :only_an_open_day_changes, "Przelicza się i zamyka tylko otwarty dzień kasowy",
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
      rejects: :a_day_is_opened_once,
      source: "dodane do testów grafu"

    command :count_cash, "Przelicz gotówkę w kasie",
      by: :reception,
      emits: :cash_counted,
      from: :open,
      or_rejects: :only_an_open_day_changes,
      rejects: :only_an_open_day_changes,
      source: "dodane do testów grafu" do
      field :counted, :money
    end

    # The day closes with the last count.
    command :close_till_day, "Zamknij dzień kasowy",
      by: :reception,
      emits: :day_closed,
      from: :open,
      or_rejects: :only_an_open_day_changes,
      rejects: [:only_an_open_day_changes, :cash_counted_before_close],
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

    # A second correction downwards of the same visit is refused here, and the
    # correction stands: the refusal is the refund's answer to the policy.
    invariant :a_refund_is_owed_once, "Zwrot z kasy zapisuje się raz na wizytę",
      source: "dodane do testów grafu"

    invariant :only_an_owed_refund_is_paid_out,
              "Wypłaca się tylko zapisany i jeszcze niewypłacony zwrot",
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
      rejects: :a_refund_is_owed_once,
      source: "E-84; dodane do testów grafu" do
      field :amount, :money
    end

    command :pay_out_refund, "Wypłać zwrot z kasy",
      by: :reception,
      emits: :refund_paid_out,
      from: :owed,
      or_rejects: :only_an_owed_refund_is_paid_out,
      rejects: :only_an_owed_refund_is_paid_out,
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

  scenario "dzień kasowy już otwarty — drugie otwarcie odrzucone" do
    given :day_opened
    command :open_till_day
    rejected :a_day_is_opened_once
  end

  scenario "gotówka przeliczona — dzień kasowy się zamyka" do
    given :day_opened
    given :cash_counted, %{counted: 120_000}
    command :close_till_day
    expect :day_closed, %{counted: 120_000}
  end

  scenario "gotówka przeliczona dwa razy — dzień zamyka się z ostatnim przeliczeniem" do
    given :day_opened
    given :cash_counted, %{counted: 120_000}
    given :cash_counted, %{counted: 118_500}
    command :close_till_day
    expect :day_closed, %{counted: 118_500}
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
    rejected :only_an_open_day_changes
  end

  scenario "dzień zamknięty — drugie zamknięcie odrzucone" do
    given :day_opened
    given :cash_counted, %{counted: 120_000}
    given :day_closed, %{counted: 120_000}
    command :close_till_day
    rejected :only_an_open_day_changes
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

  scenario "zwrot zapisany do wypłaty" do
    command :owe_refund, %{amount: 1_000}
    expect :refund_owed, %{amount: 1_000}
  end

  scenario "zwrot już zapisany — drugi zwrot dla tej wizyty odrzucony" do
    given :refund_owed, %{amount: 1_000}
    command :owe_refund, %{amount: 500}
    rejected :a_refund_is_owed_once
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
    rejected :only_an_owed_refund_is_paid_out
  end
end
