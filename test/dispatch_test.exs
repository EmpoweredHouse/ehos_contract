defmodule PNS.DispatchTest do
  @moduledoc """
  Podział dispatchu po granicy transakcji (ADR §9-10, notatki §4).

  To jest twierdzenie, którego proza nie rozstrzyga: albo semantyka awarii jest
  taka, jak zapisano, albo nie jest.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth

  @company "c-1"
  @period "2026-07"

  test "emit zapisuje zdarzenie, uruchamia handler synchroniczny i kolejkuje async — jedna transakcja" do
    {:ok, _} =
      PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: @company, period: @period})

    # Handler synchroniczny dopisał swoje w tej samej transakcji, a jego
    # publikacja pociągnęła kolejny handler synchroniczny.
    assert [_] = events_of(:registry_data_consistent)
    assert [tasks_event] = events_of(:monthly_tasks_generated)
    assert [_] = events_of(:accounting_month_opened)

    assert tasks_event.payload["task_count"] == 4
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 4
    assert Repo.aggregate(Taxvision.AccountingMonth.Month, :count) == 1
  end

  test "łańcuch przyczynowy i korelacja idą przez wszystkie zdarzenia" do
    {:ok, root} =
      PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: @company, period: @period})

    [tasks] = events_of(:monthly_tasks_generated)
    [opened] = events_of(:accounting_month_opened)

    assert tasks.correlation_id == root.correlation_id
    assert opened.correlation_id == root.correlation_id
    assert tasks.causation_id == root.id
    # Przyczyną otwarcia miesiąca jest wygenerowanie tasków, nie zgodność
    # rejestrów. Bez tego graf zaobserwowany byłby płaski.
    assert opened.causation_id == tasks.id
  end

  test "handler synchroniczny, który rzuci, cofa wszystko — brak zdarzenia, brak joba" do
    # Zdarzenie zadeklarowane, którego handler celowo wysadzam podmieniając
    # szablon na coś, co wywali insert.
    assert_raise Postgrex.Error, fn ->
      PNS.emit(AccountingMonth, :registry_data_consistent, %{
        company_id: @company,
        # `period` dłuższy niż kolumna łamie ograniczenie w tabeli tasków, czyli
        # handler synchroniczny rzuca w środku transakcji.
        #
        # Wcześniej to samo robiło `period: nil`, ale odkąd `period` jest polem
        # instancji, null jest odrzucany **przed** wejściem do handlera — i to
        # jest poprawna kolejność: zdarzenie bez tożsamości przebiegu nie ma
        # prawa trafić do logu. Sprawdzana jest tu awaria handlera, więc awaria
        # musi pochodzić z handlera.
        period: String.duplicate("x", 300)
      })
    end

    assert events_of(:registry_data_consistent) == []
    assert events_of(:monthly_tasks_generated) == []
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 0
    assert all_enqueued() == []
  end

  test "handler asynchroniczny dostaje joba wstawionego w tej samej transakcji" do
    {:ok, event} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: "vat_status: Abilia=czynny, rejestry=wykreślony"
      })

    assert [job] = all_enqueued(worker: PNS.Job)
    assert job.args["handler"] == "Taxvision.Notifications.OnRegistryDiscrepancyDetected"
    # Korelacja zserializowana do argumentów — bez tego łańcuch urywa się na
    # granicy procesu BEAM-a (notatki §3).
    assert job.args["correlation_id"] == event.correlation_id
    assert job.args["causation_id"] == event.id

    # Handler synchroniczny nie odpalił: to nie jego zdarzenie.
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 0
  end

  test "polityka retain obowiązuje też w argumentach joba, nie tylko w logu" do
    diff = "vat_status: Abilia=czynny, rejestry=wykreślony"

    {:ok, event} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: diff
      })

    assert [job] = all_enqueued(worker: PNS.Job)

    assert String.starts_with?(event.payload["diff"], "sha256:")
    # To jest ta rzecz, która wyszła dopiero w kodzie: gdyby handler dostawał
    # pełną wartość, wyciekłaby przez `oban_jobs` — tabelę, której `retain` nie
    # obejmuje. Polityka obchodzona przez kolejkę wygląda na spełnioną.
    assert String.starts_with?(job.args["payload"]["diff"], "sha256:")
    refute job.args["payload"]["diff"] == diff
  end

  test "handler asynchroniczny uruchomiony dwa razy nie robi nic drugi raz" do
    {:ok, _} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: "rozjazd"
      })

    [job] = all_enqueued(worker: PNS.Job)

    assert :ok = perform_job(PNS.Job, job.args)
    after_first = Repo.aggregate(Taxvision.Notifications.Notification, :count)
    assert after_first == 2

    assert :ok = perform_job(PNS.Job, job.args)
    assert Repo.aggregate(Taxvision.Notifications.Notification, :count) == after_first

    # Zdarzenie o wysłanym powiadomieniu poszło raz, nie dwa.
    assert [_] = events_of(:discrepancy_notification_sent)
  end

  test "publikacja zdarzenia spoza kontraktu jest odrzucana w runtime" do
    assert_raise ArgumentError, ~r/nie deklaruje zdarzenia/, fn ->
      PNS.emit(AccountingMonth, :zdarzenie_ktorego_nie_ma, %{})
    end
  end
end
