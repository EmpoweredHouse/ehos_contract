defmodule ProcessShapes.Handling do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  **The shape of a promise with two endings, one of which crosses the queue** (v2
  plan, E7c), over `ProcessShapes.Promised`'s requests: after a request arrives,
  within two days it completes, or else the refusal has gone out. It names no
  `accountable` and its deadline is unconfirmed, so that the check has both to say.
  Until plan DD, P2g (#228) it was `:handling` inside the contract. Its scenarios show
  the promise judged, one per verdict it can get here (plan DD, S2, #251).
  """

  use EhOsContract.Process,
    id: "process_shapes.handling",
    domain: ProcessShapes.Domain,
    label: "Request handling"

  correlate :request_id

  stage :intake, include: [{ProcessShapes.Promised, [:request_received, :request_logged]}]
  stage :decision, include: [{ProcessShapes.Promised, [:request_approved, :request_refused]}]
  stage :closing, include: [{ProcessShapes.Promised, [:request_completed, :refusal_notified]}]

  ends_on [:request_completed, :refusal_notified]

  # Not confirmed, in the fiction of this fixture, and three days where the promise
  # is two. Two numbers, so that a test can tell whether a value in the report came
  # from the promise or from the deadline; unconfirmed, so that the evidence report
  # has a declaration to leave out.
  deadline {3, :day}, unverified: true

  promise :completed_or_refusal_notified do
    from :request_received
    eventually :request_completed
    within {2, :day}
    or_else :refusal_notified
  end

  scenario "completed the next day — kept", verdict: :satisfied, via: :eventually do
    given :request_received, %{request_id: "r-1"}, at: "2026-09-07T09:00:00Z"
    given :request_approved, %{request_id: "r-1"}, at: "2026-09-07T12:00:00Z"
    given :request_completed, %{request_id: "r-1"}, at: "2026-09-08T09:00:00Z"
    promise :completed_or_refusal_notified, at: "2026-09-10T09:00:00Z"
  end

  scenario "refused and notified — kept the other way", verdict: :satisfied, via: :or_else do
    given :request_received, %{request_id: "r-1"}, at: "2026-09-07T09:00:00Z"
    given :request_refused, %{request_id: "r-1"}
    given :refusal_notified, %{request_id: "r-1"}
    promise :completed_or_refusal_notified, at: "2026-09-07T10:00:00Z"
  end

  scenario "completed on the third day — broken", verdict: :violated do
    given :request_received, %{request_id: "r-1"}, at: "2026-09-07T09:00:00Z"
    given :request_completed, %{request_id: "r-1"}, at: "2026-09-09T09:00:01Z"
    promise :completed_or_refusal_notified, at: "2026-09-10T09:00:00Z"
  end

  scenario "nothing yet, a day in — still open", verdict: :pending do
    given :request_received, %{request_id: "r-1"}, at: "2026-09-07T09:00:00Z"
    promise :completed_or_refusal_notified, at: "2026-09-08T09:00:00Z"
  end
end
