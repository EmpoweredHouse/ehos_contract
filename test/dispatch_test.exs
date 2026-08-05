defmodule PNS.DispatchTest do
  @moduledoc """
  Dispatch split along the transaction boundary (ADR §9-10, notes §4).

  This is a claim prose cannot settle: either the failure semantics are as
  recorded, or they are not.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth

  @company "c-1"
  @period "2026-07"

  test "emit writes the event, runs the sync handler and queues the async one — one transaction" do
    {:ok, _} =
      PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: @company, period: @period})

    # The synchronous handler added its own rows in the same transaction, and its
    # publication pulled in a further synchronous handler.
    assert [_] = events_of(:registry_data_consistent)
    assert [tasks_event] = events_of(:monthly_tasks_generated)
    assert [_] = events_of(:accounting_month_opened)

    assert tasks_event.payload["task_count"] == 4
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 4
    assert Repo.aggregate(Taxvision.AccountingMonth.Month, :count) == 1
  end

  test "the causation chain and the correlation run through every event" do
    {:ok, root} =
      PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: @company, period: @period})

    [tasks] = events_of(:monthly_tasks_generated)
    [opened] = events_of(:accounting_month_opened)

    assert tasks.correlation_id == root.correlation_id
    assert opened.correlation_id == root.correlation_id
    assert tasks.causation_id == root.id
    # The cause of the month opening is the tasks being generated, not the
    # registries agreeing. Without this the observed graph would be flat.
    assert opened.causation_id == tasks.id
  end

  test "a synchronous handler that raises rolls everything back — no event, no job" do
    # A declared event whose handler is blown up on purpose by feeding it
    # something that breaks the insert.
    assert_raise Postgrex.Error, fn ->
      PNS.emit(AccountingMonth, :registry_data_consistent, %{
        company_id: @company,
        # A `period` longer than the column breaks a constraint in the tasks
        # table, so the synchronous handler raises inside the transaction.
        #
        # `period: nil` used to do the same, but since `period` is an instance
        # field a null is rejected **before** the handler is reached — and that is
        # the correct order: an event with no run identity has no business
        # reaching the log. What is under test here is a handler failure, so the
        # failure has to come from the handler.
        period: String.duplicate("x", 300)
      })
    end

    assert events_of(:registry_data_consistent) == []
    assert events_of(:monthly_tasks_generated) == []
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 0
    assert all_enqueued() == []
  end

  test "the asynchronous handler gets a job inserted in the same transaction" do
    {:ok, event} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: "vat_status: Abilia=czynny, rejestry=wykreślony"
      })

    assert [job] = all_enqueued(worker: PNS.Job)
    assert job.args["handler"] == "Taxvision.Notifications.OnRegistryDiscrepancyDetected"
    # Correlation serialised into the arguments — without it the chain breaks at
    # the BEAM process boundary (notes §3).
    assert job.args["correlation_id"] == event.correlation_id
    assert job.args["causation_id"] == event.id

    # The synchronous handler did not fire: this is not its event.
    assert Repo.aggregate(Taxvision.Tasks.Task, :count) == 0
  end

  test "the retain policy applies to the job arguments too, not only to the log" do
    diff = "vat_status: Abilia=czynny, rejestry=wykreślony"

    {:ok, event} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: diff
      })

    assert [job] = all_enqueued(worker: PNS.Job)

    assert String.starts_with?(event.payload["diff"], "sha256:")
    # This is the thing that only came out in code: if the handler received the
    # full value, it would leak through `oban_jobs` — a table `retain` does not
    # cover. A policy the queue walks around looks satisfied.
    assert String.starts_with?(job.args["payload"]["diff"], "sha256:")
    refute job.args["payload"]["diff"] == diff
  end

  test "an asynchronous handler run twice does nothing the second time" do
    {:ok, _} =
      PNS.emit(AccountingMonth, :registry_discrepancy_detected, %{
        company_id: @company,
        period: @period,
        diff: "a divergence"
      })

    [job] = all_enqueued(worker: PNS.Job)

    assert :ok = perform_job(PNS.Job, job.args)
    after_first = Repo.aggregate(Taxvision.Notifications.Notification, :count)
    assert after_first == 2

    assert :ok = perform_job(PNS.Job, job.args)
    assert Repo.aggregate(Taxvision.Notifications.Notification, :count) == after_first

    # The notification-sent event went out once, not twice.
    assert [_] = events_of(:discrepancy_notification_sent)
  end

  test "publishing an event outside the contract is rejected at run time" do
    assert_raise ArgumentError, ~r/does not declare event/, fn ->
      PNS.emit(AccountingMonth, :no_such_event, %{})
    end
  end
end
