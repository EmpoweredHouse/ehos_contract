defmodule ProcessShapes.Promised do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  **The shape of a promise with two endings, one of which crosses the queue**
  (v2 plan, E7c). A request arrives and is logged, is approved or refused, and then
  completes or has its refusal notified — the notice through the log after the
  transaction, so that "not yet" has somewhere to wait. The promise, which
  `ProcessShapes.Handling` keeps since plan DD, P2g (#228): after it arrives, within
  two days it completes, or else the refusal has gone out.

  The request is submitted, then decided: two commands. Three policies follow, and
  each of their paths is two steps, since a command is a node of the graph: the
  event, the policy's command, the command's event.
  """

  use EhosContract.Contract,
    domain: ProcessShapes.Domain,
    context: :handling,
    id: "process_shapes.promised"

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

    event :request_received, "Request received"
    event :request_logged, "Request logged"
    event :request_approved, "Request approved"
    event :request_refused, "Request refused"
    event :request_completed, "Request completed"
    event :refusal_notified, "Refusal notified"
  end

  policy :log_arrival, "Log a request on its arrival",
    handles: :request_received,
    issues: :log_request

  policy :complete_approved, "Complete an approved request",
    handles: :request_approved,
    issues: :complete_request

  # Through the log, after the transaction: while it waits, the promise has been
  # neither kept nor broken.
  policy :notify_on_refusal, "Notify a refused request",
    handles: :request_refused,
    issues: :notify_refusal,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure]
end

defmodule ProcessShapes.Request do
  @moduledoc "The decider of `ProcessShapes.Promised`'s request."

  use ProcessShapes.Promised, aggregate: :request

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

defmodule ProcessShapes.LogArrival do
  @moduledoc "Logs the arrival. One path, taken by every run."

  use ProcessShapes.Promised, policy: :log_arrival

  @impl true
  def request_received(%RequestReceived{request_id: id}), do: issue(%LogRequest{request_id: id})
end

defmodule ProcessShapes.CompleteApproved do
  @moduledoc "The ordinary ending, reached inside the transaction that approved."

  use ProcessShapes.Promised, policy: :complete_approved

  @impl true
  def request_approved(%RequestApproved{request_id: id}),
    do: issue(%CompleteRequest{request_id: id})
end

defmodule ProcessShapes.NotifyOnRefusal do
  @moduledoc "The other ending, through the log after the transaction."

  use ProcessShapes.Promised, policy: :notify_on_refusal

  @impl true
  def request_refused(%RequestRefused{request_id: id}), do: issue(%NotifyRefusal{request_id: id})
end
