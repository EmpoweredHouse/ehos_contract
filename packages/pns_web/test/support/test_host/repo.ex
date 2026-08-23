defmodule PNS.Web.TestHost.Repo do
  @moduledoc """
  The repo the contract status screen's own suite runs against.

  Mirrors `PNS.TestRepo` in packages/pns_core: it exists so this package's
  LiveView can be proven against real conformance data without a client
  application, using `PNS.Migrations` the same way any consumer would.
  """

  use Ecto.Repo, otp_app: :pns_web, adapter: Ecto.Adapters.Postgres
end
