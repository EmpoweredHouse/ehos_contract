defmodule EhosContract.Web.TestHost.Fixtures.CaseRun do
  @moduledoc """
  INVENTED — not a domain, only material for the dashboard's own suite: a case's run
  from opening to closing as a process module of its own, so that the conformance
  endpoint has a process to serve (plan DD, P2w, #259).
  """

  use EhosContract.Process,
    id: "web_test_host.case_run",
    domain: EhosContract.Web.TestHost.Fixtures.Domain,
    label: "A case, from opening to closing"

  correlate :case_id

  stage :opening, include: [{EhosContract.Web.TestHost.Fixtures.CaseHandling, :case_opened}]

  stage :closing,
    include: [
      {EhosContract.Web.TestHost.Fixtures.CaseHandling, [:case_closed, :case_closed_as_rejected]}
    ]

  ends_on [:case_closed, :case_closed_as_rejected]

  promise :closed_within_a_week do
    from :case_opened
    eventually :case_closed
    within {7, :day}
    or_else :case_closed_as_rejected
  end
end
