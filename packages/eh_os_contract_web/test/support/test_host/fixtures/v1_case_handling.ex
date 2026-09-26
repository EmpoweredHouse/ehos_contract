defmodule EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling do
  @moduledoc """
  INVENTED — not a domain. **The v1 original of
  `EhOsContract.Web.TestHost.Fixtures.CaseHandling`, kept for the AsyncAPI endpoint
  alone**: `EhOsContract.AsyncAPI` reads v1 contracts until E10 derives it from v2's
  `publish` (v2 plan). Goes then, or at the cut (E11) at the latest.

  Two declared endings from one decision point, mirroring
  `packages/eh_os_contract`'s own `ProcessShapes.Promised` at a smaller size: this
  suite only ever exercises one of them, so the other is a real, unforced
  untraversed path rather than one asserted into existence.
  """

  use EhOsContract.Contract

  event :case_opened, label: "Case opened", payload: %{case_id: :id}, process: :v1_handling
  event :case_approved, label: "Case approved", payload: %{case_id: :id}, process: :v1_handling
  event :case_rejected, label: "Case rejected", payload: %{case_id: :id}, process: :v1_handling

  event :case_closed,
    label: "Case closed",
    payload: %{case_id: :id},
    process: :v1_handling,
    terminal: true

  event :case_closed_as_rejected,
    label: "Case closed as rejected",
    payload: %{case_id: :id},
    process: :v1_handling,
    terminal: true

  process :v1_handling, label: "Case handling (v1)", instance: [:case_id]

  trace :closes_promptly do
    from :case_opened
    eventually :case_closed, within: {1, :hour}
    or_else :case_closed_as_rejected
  end
end

defmodule EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling.OnCaseApproved do
  @moduledoc "The ordinary ending — the only one this suite ever takes."

  use EhOsContract.Handler,
    contract: EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling,
    event: :case_approved,
    publishes: [:case_closed]

  @impl EhOsContract.Handler
  def handle(%{case_id: id}, _ctx), do: {:ok, [EhOsContract.event(:case_closed, %{case_id: id})]}
end

defmodule EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling.OnCaseRejected do
  @moduledoc """
  The alternate ending. Declared so the path exists in the static graph;
  never exercised by this suite, which is what makes it a real untraversed
  path rather than a claim about one.
  """

  use EhOsContract.Handler,
    contract: EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling,
    event: :case_rejected,
    publishes: [:case_closed_as_rejected]

  @impl EhOsContract.Handler
  def handle(%{case_id: id}, _ctx),
    do: {:ok, [EhOsContract.event(:case_closed_as_rejected, %{case_id: id})]}
end
