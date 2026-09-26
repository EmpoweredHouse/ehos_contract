defmodule ProcessShapes.Next.Promised do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes.Rig`.

  `ProcessShapes.Promised` in the v2 DSL (v2 plan, E7c), kept beside it so that the
  same runs are judged on both and give the same verdicts. The shape is the same:
  a request arrives and is logged, is approved or refused, and then completes or has
  its refusal notified — the notice through the log after the transaction, so that
  "not yet" has somewhere to wait. The promise is the same: after it arrives, within
  two days it completes, or else the refusal has gone out.

  Where v1 put two facts in one emission, v2 has two commands: the request is
  submitted, then decided. v1's three synchronous and asynchronous handlers are
  three policies, and each of their paths is two steps here, since a command is a
  node of the graph: the event, the policy's command, the command's event.
  """

  use EhOsContract.Next.Contract, domain: ProcessShapes.Domain, context: :handling

  aggregate :request, "Request" do
    identity :request_id

    command :submit_request, "Submit a request", by: :requester, emits: :request_received

    command :decide_request, "Decide a request",
      by: :reviewer,
      emits: [:request_approved, :request_refused] do
      field :approve, :boolean
    end

    command :log_request, "Log a request", emits: :request_logged
    command :complete_request, "Complete a request", emits: :request_completed
    command :notify_refusal, "Notify a refusal", emits: :refusal_notified

    stage :intake do
      event :request_received, "Request received"
      event :request_logged, "Request logged"
    end

    stage :decision do
      event :request_approved, "Request approved"
      event :request_refused, "Request refused"
    end

    stage :closing do
      event :request_completed, "Request completed", terminal: true
      event :refusal_notified, "Refusal notified", terminal: true
    end
  end

  policy :log_arrival, "Log a request on its arrival",
    handles: :request_received,
    issues: :log_request

  policy :complete_approved, "Complete an approved request",
    handles: :request_approved,
    issues: :complete_request

  # Through the log, after the transaction, as v1's asynchronous handler was: while
  # it waits, the promise has been neither kept nor broken.
  policy :notify_on_refusal, "Notify a refused request",
    handles: :request_refused,
    issues: :notify_refusal,
    delivery: :at_least_once,
    idempotency: :event_id

  process :handling, "Request handling" do
    correlate :request_id

    stage :intake
    stage :decision
    stage :closing

    # Confirmed, in the fiction of this fixture. The deadline is not, and is three
    # days where the promise is two, for the reasons v1's moduledoc gives.
    cadence {1, :day}
    deadline {3, :day}, unverified: true

    promise :completed_or_refusal_notified do
      from :request_received
      eventually :request_completed
      within {2, :day}
      or_else :refusal_notified
    end
  end
end

defmodule ProcessShapes.Next.Request do
  @moduledoc "The decider of `ProcessShapes.Next.Promised`'s request."

  use ProcessShapes.Next.Promised, aggregate: :request

  @impl true
  def submit_request(%SubmitRequest{request_id: id}, _state),
    do: emit(%RequestReceived{request_id: id})

  @impl true
  def decide_request(%DecideRequest{request_id: id, approve: true}, _state),
    do: emit(%RequestApproved{request_id: id})

  def decide_request(%DecideRequest{request_id: id, approve: false}, _state),
    do: emit(%RequestRefused{request_id: id})

  @impl true
  def log_request(%LogRequest{request_id: id}, _state), do: emit(%RequestLogged{request_id: id})

  @impl true
  def complete_request(%CompleteRequest{request_id: id}, _state),
    do: emit(%RequestCompleted{request_id: id})

  @impl true
  def notify_refusal(%NotifyRefusal{request_id: id}, _state),
    do: emit(%RefusalNotified{request_id: id})
end

defmodule ProcessShapes.Next.LogArrival do
  @moduledoc "Logs the arrival. One path, taken by every run."

  use ProcessShapes.Next.Promised, policy: :log_arrival

  @impl true
  def request_received(%RequestReceived{request_id: id}), do: issue(%LogRequest{request_id: id})
end

defmodule ProcessShapes.Next.CompleteApproved do
  @moduledoc "The ordinary ending, reached inside the transaction that approved."

  use ProcessShapes.Next.Promised, policy: :complete_approved

  @impl true
  def request_approved(%RequestApproved{request_id: id}),
    do: issue(%CompleteRequest{request_id: id})
end

defmodule ProcessShapes.Next.NotifyOnRefusal do
  @moduledoc "The other ending, through the log after the transaction."

  use ProcessShapes.Next.Promised, policy: :notify_on_refusal

  @impl true
  def request_refused(%RequestRefused{request_id: id}), do: issue(%NotifyRefusal{request_id: id})
end
