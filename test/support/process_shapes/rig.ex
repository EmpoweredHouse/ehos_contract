defmodule ProcessShapes.Rig do
  @moduledoc """
  # THIS IS NOT A DOMAIN AND DOES NOT PRETEND TO BE ONE.

  A test rig for the **process shapes** of stage 1.3. The names are deliberately
  colourless — `item`, `case`, `pairing` — because if they sounded like accounting
  or like medicine, somebody would read them as knowledge about a domain. There is
  not a single claim about anybody's process here.

  Why a separate file rather than handlers attached to the universality gate's
  contract: that one is an artifact of stage 1.2 and its value lies in being a
  **contract with no implementation**. It is also the only fixture on which the
  report for a process with no declared path at all can be exercised. Attaching
  handlers would take away both of those coverages.

  ## What it is for

  The product plan lists shapes the library has to handle regardless of domain.
  Three of them require **handlers**, so no implementation-free contract can
  exercise them:

  | Shape | Where here |
  | --- | --- |
  | A step that goes backwards | `OnClarificationAnswered` — subscribes in `resolution`, publishes into `matching` |
  | The same event many times in one run | `item_paired`, once per item |
  | An event arriving without a command | `item_received` — arrives from outside, with no actor |

  The "step that goes backwards" shape is the acceptance criterion of 1.3 and is
  **built here on purpose**, together with three controls that are **not** backward
  edges. The mere fact that the check finds a case constructed for it proves
  nothing — the proof is that it does not find one in the other three.

  ## Also used for engine mechanisms that need a handler

  Shapes were the first use rather than the only one. Stage 2.1 needs a handler that
  emits something it did not declare, and that cannot live in a client tree: it is
  broken code on purpose, and no domain should be asked to carry an example of a bug.
  `OnItemReviewed` and `OnItemEscalated` do that, one per dispatch path, and both
  declare `publishes: []` so they contribute **no edges** — the graph, the wiring
  version and every path report stay exactly as they were.
  """

  use PNS.Contract

  event :item_received,
    label: "Item received for pairing",
    owner: ProcessShapes.Intake,
    # **An event arriving without a command.** Nobody here invoked it, so its
    # payload has to carry the run identity on its own and there is no actor.
    payload: %{case_id: :id, item_no: :integer, amount: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_paired,
    label: "Item paired",
    owner: ProcessShapes.Matching,
    # **The same event many times in one run.** A fact's identity includes the
    # item number, a run's identity does not.
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :matching

  event :pairing_unresolved,
    label: "Item left unpaired",
    owner: ProcessShapes.Matching,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :matching

  event :clarification_requested,
    label: "Clarification requested",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  event :clarification_answered,
    label: "Clarification answered",
    owner: ProcessShapes.Resolution,
    # Also arrives without a command — the answer comes from outside.
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  event :case_closed,
    label: "Case closed",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, paired: :integer},
    process: :pairing,
    stage: :resolution,
    terminal: true

  # The two below exist for stage 2.1 rather than for a shape. Nothing in the rig
  # emits them; the tests that need an undeclared emission drive them directly.
  event :item_reviewed,
    label: "Item reviewed",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  event :item_escalated,
    label: "Item escalated",
    owner: ProcessShapes.Resolution,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :resolution

  # For stage 2.4: two pairs that cause each other. All four sit in `intake` and
  # publish within `intake`, so none of them is a backward edge and the count of
  # those stays at one, which is the acceptance criterion of 1.3.
  #
  # Two pairs rather than one because a cycle caught on the synchronous path only
  # moves to the queue. The first pair closes inside one transaction, the second
  # closes across a job.
  event :item_disputed,
    label: "Item disputed",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_rechecked,
    label: "Item rechecked",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_appealed,
    label: "Item appealed",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_reopened,
    label: "Item reopened",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  # For stage 2.2b: the only field anywhere on `retain: :drop`, and the reason it exists
  # is that nothing used `:drop` at all — so the interaction between dropping a field
  # and validating declared fields was a trap nobody could have tripped. Validation
  # runs on the payload **as supplied**, before `retain`, which is why a dropped field
  # is legal here rather than "a declared field that is missing".
  event :item_noted,
    label: "Item noted",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer, note: :string},
    retain: %{note: :drop},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  # For stage 2.4: the one event with two synchronous handlers, so the check that
  # reports that shape has something to find. Nothing else in either contract has it,
  # and a check whose only evidence is its own silence is not tested.
  event :item_measured,
    label: "Item measured",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  # For stage 2.3. In `intake` rather than `resolution` deliberately: its handler
  # publishes into `matching`, and from `resolution` that would be a second backward
  # edge — which would quietly break the acceptance criterion of 1.3 by making the
  # count two.
  event :item_flagged,
    label: "Item flagged for review",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  # For stage 1.5b: an assertion whose consequent depends on the outside world.
  #
  # It is here rather than on the TaxVision contract because **that contract cannot produce
  # a suspension**: its one declared dependency, the public registries, is consulted by the
  # request edge *before* the first event is emitted, so the window never opens while the
  # dependency is in play. That is a finding about where this verdict matters — processes
  # whose **consequent** reaches outside, not whose precondition does — and not a gap in
  # the fixture.
  event :item_submitted,
    label: "Item submitted for inspection",
    owner: ProcessShapes.Intake,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :intake

  event :item_inspected,
    label: "Item inspected",
    owner: ProcessShapes.Matching,
    depends_on: :inspection_service,
    payload: %{case_id: :id, item_no: :integer},
    identity: [:case_id, :item_no],
    process: :pairing,
    stage: :matching

  external :inspection_service,
    label: "Inspection service",
    unavailable_looks_like: "a timeout, or a reply with no verdict in it"

  trace :submission_reaches_inspection do
    from :item_submitted
    eventually :item_inspected, within: {1, :day}
  end

  process :pairing,
    label: "Item pairing",
    stages: [:intake, :matching, :resolution],
    instance: [:case_id]
end

defmodule ProcessShapes.Intake do
  @moduledoc "The owner of the `intake` stage. A pure decision, no I/O."

  def decide(%{amount: amount}) when amount > 0, do: :pair
  def decide(_), do: :unresolved
end

defmodule ProcessShapes.Matching do
  @moduledoc """
  The owner of the `matching` stage.

  **The repo comes from configuration, not from a reference to a client module** —
  exactly as in `PNS.Emitter`. Naming `Taxvision.Repo` directly produced a boundary
  violation ("not a sibling, a parent, or a dep of some ancestor"), and rightly so:
  an engine test rig has no business reaching into the client tree.
  """

  import Ecto.Query

  @doc """
  How many items in **this run** are in a given state.

  Counted by `instance_id`, not by event type — because the same event occurs many
  times in one run, and a per-type counter would count somebody else's items. That
  is the same mistake stage 1.1 fixed in the overlay, only committed inside a
  handler.
  """
  @spec count(String.t(), String.t()) :: non_neg_integer()
  def count(case_id, type) do
    instance_id = "pairing|#{case_id}"
    # Through a variable rather than `@repo.aggregate(...)` directly — and that
    # is the reason `PNS.Emitter` has the same, seemingly redundant indirection.
    # An attribute in call position expands to a **module literal**, so `boundary`
    # sees a reference and rightly rejects it.
    repo = repo()

    repo.aggregate(
      from(e in PNS.Event, where: e.instance_id == ^instance_id and e.type == ^type),
      :count
    )
  end

  # Runtime rather than compile time, following `PNS.Emitter` — the extraction of
  # 2026-08-20 forced it there and the reason is in that module.
  defp repo, do: Application.fetch_env!(:pns, :repo)

  @doc "A case can close once every unresolved item has had a clarification."
  @spec closable?(String.t()) :: boolean()
  def closable?(case_id) do
    count(case_id, "pairing_unresolved") <= count(case_id, "clarification_answered")
  end
end

defmodule ProcessShapes.Resolution do
  @moduledoc "The owner of the `resolution` stage. The backward step lives here."
end

defmodule ProcessShapes.Intake.OnItemReceived do
  @moduledoc false

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_received,
    publishes: [:item_paired, :pairing_unresolved]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no} = payload, _ctx) do
    base = %{case_id: case_id, item_no: item_no}

    case ProcessShapes.Intake.decide(payload) do
      :pair -> {:ok, [PNS.event(:item_paired, base)]}
      :unresolved -> {:ok, [PNS.event(:pairing_unresolved, base)]}
    end
  end
end

defmodule ProcessShapes.Matching.OnPairingUnresolved do
  @moduledoc "A control: `matching` → `resolution`, that is, forwards."

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :pairing_unresolved,
    publishes: [:clarification_requested]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:clarification_requested, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Resolution.OnClarificationAnswered do
  @moduledoc """
  **The acceptance criterion of 1.3: a step that goes backwards.**

  It subscribes to `clarification_answered` from the `resolution` stage and
  publishes `item_paired` from the `matching` stage — so the pair closes
  **backwards**, after the process has already moved on. The workshop describes
  exactly this shape: a turnover with no invoice, then the invoice arrives and the
  pair closes.

  `mix pns.check` **is meant to report this**. One backward edge is normal; a
  growing count means the ADR §15 decision "processes watched, not steered" is not
  holding — which is what the review trigger is about.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :clarification_answered,
    publishes: [:item_paired]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_paired, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Matching.OnItemPaired do
  @moduledoc """
  A control: `matching` → `resolution`, forwards.

  Closes the case once nothing is left unresolved. Counts **from the log, by run
  identity** — because the same event occurs many times in one run and a per-type
  counter would count somebody else's items.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_paired,
    publishes: [:case_closed]

  @impl PNS.Handler
  def handle(%{case_id: case_id}, _ctx) do
    if ProcessShapes.Matching.closable?(case_id) do
      paired = ProcessShapes.Matching.count(case_id, "item_paired")
      {:ok, [PNS.event(:case_closed, %{case_id: case_id, paired: paired})]}
    else
      :ok
    end
  end
end

defmodule ProcessShapes.Intake.OnItemNoted do
  @moduledoc """
  Exists so the retention rule can be tested where it actually matters.

  `item_noted` carries the only `retain: :drop` field in the repository, and without a
  handler there is no span, so a test asserting "no payload value reaches telemetry"
  would pass by receiving nothing at all. It publishes nothing and does nothing; being
  observed is the whole job.
  """

  use PNS.Handler, contract: ProcessShapes.Rig, event: :item_noted, publishes: []

  @impl PNS.Handler
  def handle(_payload, _ctx), do: :ok
end

defmodule ProcessShapes.Intake.OnItemMeasuredFirst do
  @moduledoc """
  One of **two** synchronous handlers on `item_measured`, for stage 2.4.

  Deliberately named so that alphabetical order and the intended order disagree:
  `First` sorts after `Second`. That is the whole point of the warning — the order
  reproduces and means nothing, so a contract that depends on it is expressing
  sequence through the spelling of a module name.

  Both publish nothing, so the graph, the wiring version and every path report are
  untouched by their presence.
  """

  use PNS.Handler, contract: ProcessShapes.Rig, event: :item_measured, publishes: []

  @impl PNS.Handler
  def handle(_payload, _ctx), do: :ok
end

defmodule ProcessShapes.Intake.OnItemMeasuredSecond do
  @moduledoc "The other one. Sorts first, which is exactly the trap being warned about."

  use PNS.Handler, contract: ProcessShapes.Rig, event: :item_measured, publishes: []

  @impl PNS.Handler
  def handle(_payload, _ctx), do: :ok
end

defmodule ProcessShapes.Intake.OnItemDisputed do
  @moduledoc """
  Half of a cycle that closes **inside one transaction**, for stage 2.4.

  It publishes `item_rechecked`, whose handler publishes `item_disputed` straight
  back. Without a guard the recursion runs until the stack or the connection gives
  out, and both of those failures arrive as something other than "your contract has a
  loop".
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_disputed,
    publishes: [:item_rechecked]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_rechecked, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Intake.OnItemRechecked do
  @moduledoc "The other half: publishes back what caused it."

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_rechecked,
    publishes: [:item_disputed]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_disputed, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Intake.OnItemAppealed do
  @moduledoc """
  Half of a cycle that closes **across the queue**, for stage 2.4.

  A loop through jobs does not exhaust a stack — it runs forever, more slowly, and
  each hop looks like ordinary work. So the guard has to travel with the job, and
  this pair is what proves it does rather than a comment saying it should.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_appealed,
    publishes: [:item_reopened]

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_reopened, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Intake.OnItemReopened do
  @moduledoc "The other half, and it runs through the queue."

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_reopened,
    publishes: [:item_appealed],
    async: true

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    {:ok, [PNS.event(:item_appealed, %{case_id: case_id, item_no: item_no})]}
  end
end

defmodule ProcessShapes.Intake.OnItemFlagged do
  @moduledoc """
  **Fails on purpose, for stage 2.3: a synchronous handler that raises.**

  It declares a path it never takes, because it dies first. That combination is the
  whole point: the edge is declared, never observed, and the reason is a defect — so
  a path report that only knows "declared, never observed" describes it as a dead or
  untested path, which sends a developer's bug to the process owner as a question
  about their process.

  Whether it raises depends on the payload, for the same reason as the stage 2.1
  fixtures: the control is the same handler **not** failing, and without it a test
  could pass against a mechanism that recorded a failure for every handler call.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_flagged,
    publishes: [:pairing_unresolved]

  @impl PNS.Handler
  def handle(%{item_no: item_no}, _ctx) do
    if item_no > 0 do
      raise RuntimeError, "the review desk is unreachable"
    else
      :ok
    end
  end
end

defmodule ProcessShapes.Resolution.OnItemReviewed do
  @moduledoc """
  **Deliberately broken, for stage 2.1: emits what it never declared.**

  `publishes: []` and yet it returns an `item_paired`. Both compilation and
  `mix pns.check` accept this, because each checks a different thing: the compile
  gate verifies that every name in `publishes:` exists in the contract, and the
  check reasons about declarations rather than about what a function body returns.
  Only the runtime half catches it.

  **Whether it violates depends on the payload**, which is the point rather than
  convenience. A handler that always violated would leave the negative case
  untested — and the negative case is the one worth having: the same handler,
  emitting nothing, must not raise. Otherwise a check that fired on any handler
  return at all would pass the positive test too.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_reviewed,
    publishes: []

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    if item_no > 0 do
      {:ok, [PNS.event(:item_paired, %{case_id: case_id, item_no: item_no})]}
    else
      :ok
    end
  end
end

defmodule ProcessShapes.Resolution.OnItemEscalated do
  @moduledoc """
  The same violation as `OnItemReviewed`, on the **other** dispatch path.

  Two fixtures rather than one because a single rule reached from two call sites is
  exactly the thing that drifts, so each path has to be pinned separately. And they
  cannot share an event: the synchronous handler rolls the transaction back, so a
  queued job on the same event would never get to run.
  """

  use PNS.Handler,
    contract: ProcessShapes.Rig,
    event: :item_escalated,
    publishes: [],
    async: true

  @impl PNS.Handler
  def handle(%{case_id: case_id, item_no: item_no}, _ctx) do
    if item_no > 0 do
      {:ok, [PNS.event(:item_paired, %{case_id: case_id, item_no: item_no})]}
    else
      :ok
    end
  end
end
