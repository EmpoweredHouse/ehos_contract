defmodule EhOsContract.Web.TestHost.Fixtures.AppealsDomain do
  @moduledoc """
  INVENTED — a second domain, the home of the dashboard suite's second contract, so
  that the graph screen has two domains to draw.
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
  registered — the graph's selector, and the conformance API asked for a report
  without naming which contract.
  """

  use EhOsContract.Contract,
    domain: EhOsContract.Web.TestHost.Fixtures.AppealsDomain,
    context: :appeals,
    id: "web_test_appeals.appeals"

  aggregate :appeal, "Appeal" do
    identity :appeal_id

    event :appeal_lodged, "Appeal lodged", recorded_by: :appeals_clerk
  end
end
