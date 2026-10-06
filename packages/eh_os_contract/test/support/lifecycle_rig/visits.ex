defmodule LifecycleRig.Visits do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A visit's lifecycle. Admitting, cancelling and closing name the statuses they are
  issued in, so their implementation does not check the status at all: the engine
  refuses them elsewhere. Reopening names none, and its implementation emits an
  arrival whatever the status — the defect the graph exists to catch.
  """

  use EhOsContract.Contract,
    domain: LifecycleRig.Domain,
    context: :visits,
    id: "lifecycle_rig.visits"

  aggregate :visit, "Visit" do
    identity :visit_id

    state do
      field :notes_before_arrival, :integer, default: 0
    end

    invariant :only_a_booked_visit, "Only a booked visit is admitted or cancelled"
    invariant :only_an_open_visit, "Only a visit in progress is closed"

    lifecycle do
      status :booked, "Booked"
      status :in_progress, "In progress"
      status :closed, "Closed", final: true
      status :cancelled, "Cancelled", final: true

      initial :booked, on: :booked
      transition :booked, :patient_arrived, :in_progress
      transition :booked, :cancelled, :cancelled
      transition :in_progress, :closed, :closed
    end

    command :book_visit, "Book a visit", by: :reception, emits: :booked

    command :admit_patient, "Admit the patient",
      by: :reception,
      emits: :patient_arrived,
      from: :booked,
      or_rejects: :only_a_booked_visit,
      rejects: :only_a_booked_visit

    command :cancel_visit, "Cancel the visit",
      by: :reception,
      emits: :cancelled,
      from: :booked,
      or_rejects: :only_a_booked_visit,
      rejects: :only_a_booked_visit

    command :close_visit, "Close the visit",
      by: :reception,
      emits: :closed,
      from: :in_progress,
      or_rejects: :only_an_open_visit,
      rejects: :only_an_open_visit

    command :add_note, "Add a note", by: :reception, emits: :note_added
    command :reopen_visit, "Reopen the visit", by: :reception, emits: :patient_arrived

    event :booked, "Visit booked"
    event :patient_arrived, "Patient arrived", recorded_by: :front_desk
    # Plan W1: a second version of its fields, so the log shows the version it was
    # written with.
    event :note_added, "Note added", schema_version: 2
    event :cancelled, "Visit cancelled", terminal: true

    event :closed, "Visit closed", terminal: true do
      field :notes_before_arrival, :integer
    end
  end

  process :visit, "A visit, from booking to its close", accountable: :reception do
    correlate :visit_id
  end

  scenario "a booked visit admits its patient" do
    given :booked
    command :admit_patient
    expect :patient_arrived
  end

  scenario "a visit the patient came to is not admitted again" do
    given :booked
    given :patient_arrived
    command :admit_patient
    rejected :only_a_booked_visit
  end

  scenario "a visit the patient has not come to is not closed" do
    given :booked
    command :close_visit
    rejected :only_an_open_visit
  end

  scenario "a closed visit counts the notes taken before the patient arrived" do
    given :booked
    given :note_added
    given :patient_arrived
    given :note_added
    command :close_visit
    expect :closed, %{notes_before_arrival: 1}
  end
end
