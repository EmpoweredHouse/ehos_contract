defmodule EhosContract.Web.TestHost.Fixtures.CaseHandling do
  @moduledoc """
  INVENTED — not a domain, only material for the dashboard's own suite. Proves the
  screens render real `EhosContract.Conformance.report/2` output, not hand-built
  data, without needing any client tree.

  **In the v2 DSL since E7c**, with two policies. A case is opened and decided; an approved case is closed and a
  rejected one closed as rejected, each by its policy inside the transaction. This
  suite only ever takes the approval, so the rejection's steps are real, unforced
  untraversed steps rather than ones asserted into existence.
  """

  use EhosContract.Contract,
    domain: EhosContract.Web.TestHost.Fixtures.Domain,
    context: :cases,
    id: "web_test_host.case_handling"

  aggregate :case, "Case" do
    identity :case_id

    # Plan LC4b: a lifecycle for the screens to draw and report on. The suite only
    # approves, so the rejection's transitions are never taken.
    lifecycle do
      status :open, "Open"
      status :approved, "Approved"
      status :rejected, "Rejected"
      status :closed, "Closed", final: true
      status :closed_rejected, "Closed as rejected", final: true

      initial :open, on: :case_opened
      transition :open, :case_approved, :approved
      transition :open, :case_rejected, :rejected
      transition :approved, :case_closed, :closed
      transition :rejected, :case_closed_as_rejected, :closed_rejected
    end

    command :open_case, "Open a case", by: :case_officer, emits: :case_opened

    command :decide_case, "Decide a case",
      by: :case_officer,
      emits: [:case_approved, :case_rejected] do
      field :approve, :boolean
    end

    command :close_case, "Close a case", emits: :case_closed
    command :close_as_rejected, "Close a case as rejected", emits: :case_closed_as_rejected

    event :case_opened, "Case opened"
    event :case_approved, "Case approved"
    event :case_rejected, "Case rejected"
    event :case_closed, "Case closed"
    event :case_closed_as_rejected, "Case closed as rejected"
  end

  policy :close_approved, "Close an approved case", handles: :case_approved, issues: :close_case

  policy :close_rejected, "Close a rejected case",
    handles: :case_rejected,
    issues: :close_as_rejected
end

defmodule EhosContract.Web.TestHost.Fixtures.Case do
  @moduledoc "The decider of the case."

  use EhosContract.Web.TestHost.Fixtures.CaseHandling, aggregate: :case

  @impl true
  def open_case(%OpenCase{case_id: id}, _state), do: emit(%CaseOpened{case_id: id})

  @impl true
  def decide_case(%DecideCase{case_id: id, approve: true}, _state),
    do: emit(%CaseApproved{case_id: id})

  def decide_case(%DecideCase{case_id: id, approve: false}, _state),
    do: emit(%CaseRejected{case_id: id})

  @impl true
  def close_case(%CloseCase{case_id: id}, _state), do: emit(%CaseClosed{case_id: id})

  @impl true
  def close_as_rejected(%CloseAsRejected{case_id: id}, _state),
    do: emit(%CaseClosedAsRejected{case_id: id})
end

defmodule EhosContract.Web.TestHost.Fixtures.CloseApproved do
  @moduledoc "The ordinary ending — the only one this suite ever takes."

  use EhosContract.Web.TestHost.Fixtures.CaseHandling, policy: :close_approved

  @impl true
  def case_approved(%CaseApproved{case_id: id}), do: issue(%CloseCase{case_id: id})
end

defmodule EhosContract.Web.TestHost.Fixtures.CloseRejected do
  @moduledoc """
  The alternate ending. Declared so its steps exist; never taken by this suite,
  which is what makes them real untraversed steps rather than a claim about them.
  """

  use EhosContract.Web.TestHost.Fixtures.CaseHandling, policy: :close_rejected

  @impl true
  def case_rejected(%CaseRejected{case_id: id}), do: issue(%CloseAsRejected{case_id: id})
end
