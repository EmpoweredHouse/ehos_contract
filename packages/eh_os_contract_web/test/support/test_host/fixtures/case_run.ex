defmodule EhOsContract.Web.TestHost.Fixtures.CaseRun do
  @moduledoc """
  INVENTED — not a domain, only material for the dashboard's own suite: a case's run
  from opening to closing as a process module of its own, so that the conformance
  endpoint has a process to serve (plan DD, P2w, #259).
  """

  use EhOsContract.Process,
    id: "web_test_host.case_run",
    domain: EhOsContract.Web.TestHost.Fixtures.Domain,
    label: "A case, from opening to closing"

  correlate :case_id

  stage :opening, include: [{EhOsContract.Web.TestHost.Fixtures.CaseHandling, :case_opened}]
  stage :closing, include: [{EhOsContract.Web.TestHost.Fixtures.CaseHandling, :case_closed}]

  ends_on :case_closed

  promise :closed_within_a_week do
    from :case_opened
    eventually :case_closed
    within {7, :day}
  end
end
