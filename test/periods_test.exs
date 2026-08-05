defmodule Taxvision.PeriodsTest do
  @moduledoc """
  Etap 1.3b: **dwa moduły potrzebujące tych samych danych.**

  Ostatni z pięciu kształtów i jedyny, którego nie dało się sprawdzić na
  stanowisku badawczym: na fikstórze zduplikowałbym dane ze „nazwanym źródłem
  prawdy” i ogłosił sukces, nie dowiadując się niczego. Potrzebne było realne
  ciśnienie — `period` żyje w zdarzeniach pięciu modułów TaxVision, a joiny
  międzymodułowe są zabronione.

  Tu rozstrzyga się też wątpliwość z planu produktowego: **czy zakaz joinów
  międzymodułowych jest znośny.**
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.AccountingMonth.Month
  alias Taxvision.Tasks.Task

  @okres "2026-07"

  defp otworz(firma) do
    {:ok, _} = Taxvision.Api.open_month(accountant(firma), %{company_id: firma, period: @okres})
  end

  describe "kanonizacja" do
    test "okres jest wierszem, więc nie da się zaksięgować w okresie, który nie istnieje" do
      # To jest cały zysk z zamiany stringu na wiersz. `\"2026-7\"` obok
      # `\"2026-07\"` przestaje być możliwe, a nie tylko niezalecane.
      assert_raise ArgumentError, ~r/no period named "2026-13"/, fn ->
        Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-13"})
      end
    end

    test "zakres dat wychodzi z nazwy raz, w jednym miejscu" do
      okres = Taxvision.Periods.fetch!(@okres)

      assert okres.starts_on == ~D[2026-07-01]
      assert okres.ends_on == ~D[2026-07-31]
    end

    test "założenie tego samego okresu dwa razy daje jeden wiersz" do
      przed = Taxvision.Periods.fetch!(@okres)
      assert Taxvision.Periods.ensure!(@okres) == przed
    end
  end

  describe "dwa moduły, ta sama odpowiedź, jedno źródło" do
    test "taski i miesiąc dostają tę samą datę, każdy do własnej tabeli" do
      otworz("c-1")

      okres = Taxvision.Periods.fetch!(@okres)
      [miesiac] = Repo.all(Month)
      taski = Repo.all(Task)

      assert miesiac.closes_on == okres.ends_on
      assert taski != []
      assert Enum.all?(taski, &(&1.due_on == okres.ends_on))

      # Dwie kopie tej samej prawdy, w dwóch prywatnych tabelach. To jest
      # **duplikacja strategiczna**, nie wspólna tabela: źródło prawdy jest
      # jedno i jest nazwane.
      assert miesiac.closes_on == List.first(taski).due_on
    end
  end

  describe "cena zakazu joinów, zmierzona" do
    test "każdy moduł płaci własnym zapytaniem — i tyle wynosi N+1" do
      # Notatki §14 nazywają N+1 ryzykiem, nie niespodzianką. Tu jest zmierzone,
      # a nie opowiedziane: dwa moduły potrzebują tej samej odpowiedzi i żaden
      # nie może skorzystać z zapytania drugiego, bo nie wolno im się widzieć.
      me = self()

      :telemetry.attach(
        "periods-counter",
        [:taxvision, :repo, :query],
        fn _event, _measure, meta, _config ->
          if meta[:source] == "taxvision_periods", do: send(me, :period_query)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("periods-counter") end)

      otworz("c-1")

      assert policz_zapytania() == 2,
             "jedno zapytanie na moduł: Taxvision.Tasks i Taxvision.AccountingMonth. " <>
               "Gdyby było jedno, ktoś przekazuje sobie dane bokiem; gdyby więcej, " <>
               "N+1 rośnie szybciej, niż notatki §14 przewidują"
    end

    defp policz_zapytania(licznik \\ 0) do
      receive do
        :period_query -> policz_zapytania(licznik + 1)
      after
        50 -> licznik
      end
    end
  end
end
