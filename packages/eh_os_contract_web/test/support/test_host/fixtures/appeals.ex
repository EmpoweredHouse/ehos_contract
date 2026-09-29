defmodule EhOsContract.Web.TestHost.Fixtures.AppealsDomain do
  @moduledoc """
  INVENTED — a second domain, so that a second contract can name its process
  `handling` too: process names are unique within a domain (X7), not across them.
  """

  use EhOsContract.Domain, name: :web_test_appeals, language: :en

  context :appeals, "Appeals", subdomain: :core

  actor :appeals_clerk, :human, "Appeals clerk"

  subdomain :core, "Core", type: :core
end

defmodule EhOsContract.Web.TestHost.Fixtures.Appeals do
  @moduledoc """
  INVENTED — not a domain. The second contract of the dashboard's suite, and the
  smallest one there can be: what the screens must keep apart when two contracts are
  registered — a process of the same name as `CaseHandling`'s, and the conformance
  API asked for a report without naming which contract.
  """

  use EhOsContract.Contract,
    domain: EhOsContract.Web.TestHost.Fixtures.AppealsDomain,
    context: :appeals

  aggregate :appeal, "Appeal" do
    identity :appeal_id

    event :appeal_lodged, "Appeal lodged", recorded_by: :appeals_clerk
  end

  # Labelled to sort after "Case handling", so the screen still opens on that one.
  process :handling, "Handling of appeals" do
    correlate :appeal_id
  end
end
