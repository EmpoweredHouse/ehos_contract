defmodule Rehmed.ClinicalVisitTest do
  @moduledoc """
  The clinical visit across three contracts, dispatched in the host (v2 plan, E9a):
  booked in scheduling, closed in documentation, reported in statutory reporting,
  and judged by `:clinical_visit`'s promise — P1 within two days of the patient
  leaving (Dz.U. 2025 poz. 866).

  E9's acceptance asks for the promise kept through `or_else` on a seeded run; the
  run here is seeded the way a clinic would make it, by people with credentials and
  the registry's integration, not by inserting rows.
  """

  use Taxvision.DataCase, async: false

  alias EhOsContract.{Actor, Clock, Event, Testing, Trace}
  alias Rehmed.Contracts.{ClinicalDocumentation, Scheduling, StatutoryReporting}
  alias Rehmed.Contracts.ClinicalDocumentation.Commands.CloseVisitClinically
  alias Rehmed.Contracts.Scheduling.Commands.BookVisit
  alias Rehmed.Contracts.Scheduling.Events.{PatientArrived, VisitCompleted}

  @promise :medical_event_reported_within_statutory_window
  @left ~U[2026-09-01 10:00:00Z]

  @reception Actor.credential("reception-ola", ["rehmed.book_visit", "rehmed.patient_arrived"])
  @specialist Actor.credential("specialist-ewa", [
                "rehmed.visit_completed",
                "rehmed.close_visit_clinically"
              ])

  # The first drain is the deploy: the policy, the chase and the effect subscribe
  # before the visit happens (`EhOsContract.Testing`).
  setup do
    Testing.drain()
    :ok
  end

  # A visit booked, the patient arrived, and left the room at `@left`.
  defp visit(patient) do
    {:ok, booked} =
      EhOsContract.dispatch(
        Scheduling,
        %BookVisit{
          patient_id: patient,
          service_id: "service-physiotherapy",
          specialist_id: "specialist-ewa",
          scheduled_at: ~U[2026-09-01 09:00:00Z]
        },
        actor: @reception,
        idempotency_key: "booking:#{patient}"
      )

    %{visit_id: id} = booked.identity

    {:ok, _} = EhOsContract.record(Scheduling, %PatientArrived{visit_id: id}, actor: @reception)

    {:ok, _} =
      Clock.at(@left, fn ->
        EhOsContract.record(Scheduling, %VisitCompleted{visit_id: id}, actor: @specialist)
      end)

    id
  end

  defp close(id, reported?, at) do
    codes = if reported?, do: %{icd10: "M54.5", icd9: "93.39"}, else: %{}

    Clock.at(at, fn ->
      EhOsContract.dispatch(
        ClinicalDocumentation,
        struct!(
          CloseVisitClinically,
          Map.merge(codes, %{
            visit_id: id,
            patient_id: "patient-anna",
            pesel: "85010112345",
            practitioner_number: "practitioner-ewa",
            p1_reported: reported?
          })
        ),
        actor: @specialist
      )
    end)
  end

  defp verdicts(opts \\ []), do: Trace.evaluate(StatutoryReporting, @promise, opts)

  # An event's type is its home process's name and its own (D1): statutory
  # reporting's events are the clinical visit's.
  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  test "a massage closed clinically keeps the promise the other way: nothing is owed to P1" do
    id = visit("patient-anna")
    {:ok, _} = close(id, false, DateTime.add(@left, 3600))

    assert [%{verdict: :satisfied, via: :or_else, instance_id: instance}] = verdicts()
    assert instance =~ id
    assert "clinical_visit.p1_reporting_not_required" in types()
  end

  test "physiotherapy is queued on the close, sent by the effect, and keeps the promise" do
    id = visit("patient-anna")
    {:ok, _} = close(id, true, DateTime.add(@left, 3600))

    # Queued in the close's transaction, sent after it.
    assert [%{verdict: :pending}] = verdicts(now: DateTime.add(@left, 3600))
    Clock.at(DateTime.add(@left, 7200), fn -> Testing.drain() end)

    assert [%{verdict: :satisfied, via: :eventually}] = verdicts()

    # The integration recorded the registry's answer, as the integration.
    sent = Repo.one!(from(e in Event, where: e.type == "clinical_visit.p1_report_sent"))
    assert sent.actor == "system:p1_integration"
  end

  test "a visit nobody closes is pending inside two days and breaks the statute after them" do
    visit("patient-anna")

    assert [%{verdict: :pending}] = verdicts(now: DateTime.add(@left, 47 * 3600))
    assert [%{verdict: :violated}] = verdicts(now: DateTime.add(@left, 49 * 3600))
  end

  test "a day after the patient leaves with no clinical close, the chase creates the task" do
    visit("patient-anna")

    Clock.at(DateTime.add(@left, 23 * 3600), fn -> Testing.drain() end)
    refute "visit_documentation.documentation_overdue_task_created" in types()

    Clock.at(DateTime.add(@left, 25 * 3600), fn -> Testing.drain() end)
    assert "visit_documentation.documentation_overdue_task_created" in types()
  end

  test "the chase ends with the clinical close, and creates no task" do
    id = visit("patient-anna")
    {:ok, _} = close(id, false, DateTime.add(@left, 3600))

    Clock.at(DateTime.add(@left, 25 * 3600), fn -> Testing.drain() end)
    refute "visit_documentation.documentation_overdue_task_created" in types()
  end
end
