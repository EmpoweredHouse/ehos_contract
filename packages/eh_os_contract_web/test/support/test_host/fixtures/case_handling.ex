defmodule EhOsContract.Web.TestHost.Fixtures.CaseHandling do
  @moduledoc """
  INVENTED — not a domain, only material for the dashboard's own suite. Proves the
  screens render real `EhOsContract.Conformance.report/2` output, not hand-built
  data, without needing any client tree.

  **In the v2 DSL since E7c** (v2 plan, "Losy fikstur"), with two policies where v1
  had two handlers. A case is opened and decided; an approved case is closed and a
  rejected one closed as rejected, each by its policy inside the transaction. This
  suite only ever takes the approval, so the rejection's steps are real, unforced
  untraversed steps rather than ones asserted into existence.
  """

  use EhOsContract.Next.Contract,
    domain: EhOsContract.Web.TestHost.Fixtures.Domain,
    context: :cases

  aggregate :case, "Case" do
    identity :case_id

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
    event :case_closed, "Case closed", terminal: true
    event :case_closed_as_rejected, "Case closed as rejected", terminal: true
  end

  policy :close_approved, "Close an approved case", handles: :case_approved, issues: :close_case

  policy :close_rejected, "Close a rejected case",
    handles: :case_rejected,
    issues: :close_as_rejected

  process :handling, "Case handling" do
    correlate :case_id

    promise :closes_promptly do
      from :case_opened
      eventually :case_closed
      within {1, :hour}
      or_else :case_closed_as_rejected
    end
  end
end

defmodule EhOsContract.Web.TestHost.Fixtures.Case do
  @moduledoc "The decider of the case."

  use EhOsContract.Web.TestHost.Fixtures.CaseHandling, aggregate: :case

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

defmodule EhOsContract.Web.TestHost.Fixtures.CloseApproved do
  @moduledoc "The ordinary ending — the only one this suite ever takes."

  use EhOsContract.Web.TestHost.Fixtures.CaseHandling, policy: :close_approved

  @impl true
  def case_approved(%CaseApproved{case_id: id}), do: issue(%CloseCase{case_id: id})
end

defmodule EhOsContract.Web.TestHost.Fixtures.CloseRejected do
  @moduledoc """
  The alternate ending. Declared so its steps exist; never taken by this suite,
  which is what makes them real untraversed steps rather than a claim about them.
  """

  use EhOsContract.Web.TestHost.Fixtures.CaseHandling, policy: :close_rejected

  @impl true
  def case_rejected(%CaseRejected{case_id: id}), do: issue(%CloseAsRejected{case_id: id})
end
