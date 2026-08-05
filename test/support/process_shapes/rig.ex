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

  @repo Application.compile_env!(:pns_prototype, :repo)

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

  defp repo, do: @repo

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
