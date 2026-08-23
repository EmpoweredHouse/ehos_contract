defmodule PNS.Web.TestHost.Fixtures.CaseHandling do
  @moduledoc """
  INVENTED — not a domain, only material for the contract status screen's own
  suite. Proves the screen renders real `PNS.Conformance.report/2` output, not
  hand-built data, without needing any client tree.

  Two declared endings from one decision point, mirroring
  `packages/pns_core`'s own `ProcessShapes.Promised` at a smaller size: this
  suite only ever exercises one of them, so the other is a real, unforced
  untraversed path rather than one asserted into existence.
  """

  use PNS.Contract

  event :case_opened, label: "Case opened", payload: %{case_id: :id}, process: :handling
  event :case_approved, label: "Case approved", payload: %{case_id: :id}, process: :handling
  event :case_rejected, label: "Case rejected", payload: %{case_id: :id}, process: :handling

  event :case_closed,
    label: "Case closed",
    payload: %{case_id: :id},
    process: :handling,
    terminal: true

  event :case_closed_as_rejected,
    label: "Case closed as rejected",
    payload: %{case_id: :id},
    process: :handling,
    terminal: true

  process :handling, label: "Case handling", instance: [:case_id]

  trace :closes_promptly do
    from :case_opened
    eventually :case_closed, within: {1, :hour}
    or_else :case_closed_as_rejected
  end
end

defmodule PNS.Web.TestHost.Fixtures.CaseHandling.OnCaseApproved do
  @moduledoc "The ordinary ending — the only one this suite ever takes."

  use PNS.Handler,
    contract: PNS.Web.TestHost.Fixtures.CaseHandling,
    event: :case_approved,
    publishes: [:case_closed]

  @impl PNS.Handler
  def handle(%{case_id: id}, _ctx), do: {:ok, [PNS.event(:case_closed, %{case_id: id})]}
end

defmodule PNS.Web.TestHost.Fixtures.CaseHandling.OnCaseRejected do
  @moduledoc """
  The alternate ending. Declared so the path exists in the static graph;
  never exercised by this suite, which is what makes it a real untraversed
  path rather than a claim about one.
  """

  use PNS.Handler,
    contract: PNS.Web.TestHost.Fixtures.CaseHandling,
    event: :case_rejected,
    publishes: [:case_closed_as_rejected]

  @impl PNS.Handler
  def handle(%{case_id: id}, _ctx),
    do: {:ok, [PNS.event(:case_closed_as_rejected, %{case_id: id})]}
end
