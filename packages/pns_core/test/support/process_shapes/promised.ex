defmodule ProcessShapes.Promised do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes.Rig`.

  **The shape of a promise with two endings, one of which crosses the queue.**

  A run arrives, is logged, and then either completes or is refused; a refusal has
  to be notified, and the notification is asynchronous. The assertion says: after
  it arrives, within two days it completes — or else the refusal has gone out.

  Three declared paths, of which an ordinary run traverses two. That ratio is the
  point: it is what lets the acceptance criterion of stage 1.4 be stated as "fifty
  runs, one line of report" instead of "fifty runs, some lines of report".

  ## Why a fourth contract rather than two more events on the rig

  Until 2026-08-21 both of these shapes came from the TaxVision contract, and every
  test of `PNS.Trace` and `PNS.Conformance` therefore ran on a client tree. The rig
  could not take them over: its one assertion has no `or_else` and none of its
  handlers is asynchronous on a path an assertion watches, and adding those would
  move the edge counts a dozen tests assert against for reasons unrelated to what
  those tests check.

  The asynchronous ending is not decoration. "Not yet" and "never" look identical
  in the log, and the only fixture that can tell the difference is one where an
  ending really is still sitting in a queue.
  """

  use PNS.Contract

  event :request_received,
    label: "Request received",
    owner: ProcessShapes.Promised,
    # Arrives from outside, so it carries the run identity on its own.
    payload: %{request_id: :id},
    process: :handling,
    stage: :intake

  event :request_logged,
    label: "Request logged",
    owner: ProcessShapes.Promised,
    payload: %{request_id: :id},
    process: :handling,
    stage: :intake

  event :request_approved,
    label: "Request approved",
    owner: ProcessShapes.Promised,
    payload: %{request_id: :id},
    process: :handling,
    stage: :decision

  event :request_completed,
    label: "Request completed",
    owner: ProcessShapes.Promised,
    payload: %{request_id: :id},
    process: :handling,
    stage: :closing,
    terminal: true

  event :request_refused,
    label: "Request refused",
    owner: ProcessShapes.Promised,
    payload: %{request_id: :id},
    # Keyed by the run and nothing finer: the asynchronous handler needs an
    # idempotency key, and one that did not contain the run would merge two runs
    # into one notification.
    identity: [:request_id],
    process: :handling,
    stage: :decision

  event :refusal_notified,
    label: "Refusal notified",
    owner: ProcessShapes.Promised,
    payload: %{request_id: :id},
    process: :handling,
    stage: :closing,
    terminal: true

  process :handling,
    label: "Request handling",
    stages: [:intake, :decision, :closing],
    instance: [:request_id],
    # Confirmed, in the fiction of this fixture: requests arrive daily.
    cadence: {1, :day},
    # Three days, deliberately **not** the assertion's two. They are different
    # promises — how long the whole run may take, against how long one step has to
    # follow another — and while they shared a number, a test could not tell
    # whether a value in the report came from the confirmed assertion or from the
    # unconfirmed deadline. Stage 5.4 needed to tell.
    deadline: {3, :day},
    # And this one is **not** confirmed, which is the whole reason it is here. The
    # evidence report has to be able to leave a declaration out, and a fixture with
    # nothing to leave out cannot show that it does — the filter would pass just as
    # well while being broken.
    unverified: [:deadline]

  trace :completed_or_refusal_notified do
    from :request_received
    eventually :request_completed, within: {2, :day}
    or_else :refusal_notified
  end
end

defmodule ProcessShapes.Promised.OnRequestReceived do
  @moduledoc "Logs the arrival. One path, taken by every run."

  use PNS.Handler,
    contract: ProcessShapes.Promised,
    event: :request_received,
    publishes: [:request_logged]

  @impl PNS.Handler
  def handle(%{request_id: id}, _ctx), do: {:ok, [PNS.event(:request_logged, %{request_id: id})]}
end

defmodule ProcessShapes.Promised.OnRequestApproved do
  @moduledoc "The ordinary ending, reached inside the emitting transaction."

  use PNS.Handler,
    contract: ProcessShapes.Promised,
    event: :request_approved,
    publishes: [:request_completed]

  @impl PNS.Handler
  def handle(%{request_id: id}, _ctx), do: {:ok, [PNS.event(:request_completed, %{request_id: id})]}
end

defmodule ProcessShapes.Promised.OnRequestRefused do
  @moduledoc """
  The other ending, and it goes through the queue.

  Asynchronous on purpose. While the job is waiting, the assertion has not been
  kept and has not been broken either — and a fixture where every ending is
  immediate cannot tell those two apart, which is the state `:pending` exists for.

  **Idempotent, because Oban gives at-least-once.** A client deduplicates against
  its own table using `ctx.idempotency_key`, which is what the key is for and what
  `job_idempotency_test` checks. This fixture owns no table, so it deduplicates
  against the log instead: it asks whether this run has already been notified. The
  strategy is different and the property is the same — run the job twice, and the
  consequence happens once.
  """

  import Ecto.Query

  use PNS.Handler,
    contract: ProcessShapes.Promised,
    event: :request_refused,
    publishes: [:refusal_notified],
    async: true

  @impl PNS.Handler
  def handle(%{request_id: id}, _ctx) do
    if notified?(id) do
      :ok
    else
      {:ok, [PNS.event(:refusal_notified, %{request_id: id})]}
    end
  end

  # Through a variable rather than an attribute in call position, for the reason
  # `PNS.Emitter` has the same indirection: an attribute there expands to a module
  # literal and `boundary` rightly rejects the reference.
  defp notified?(request_id) do
    instance_id = "handling|#{request_id}"
    repo = Application.fetch_env!(:pns, :repo)

    repo.exists?(
      from e in PNS.Event,
        where: e.instance_id == ^instance_id and e.type == "refusal_notified"
    )
  end
end
