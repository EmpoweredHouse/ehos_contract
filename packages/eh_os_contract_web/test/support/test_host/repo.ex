defmodule EhOsContract.Web.TestHost.Repo do
  @moduledoc """
  The repo the contract status screen's own suite runs against.

  Mirrors `EhOsContract.TestRepo` in packages/eh_os_contract: it exists so this package's
  LiveView can be proven against real conformance data without a client
  application, using `EhOsContract.Migrations` the same way any consumer would.
  """

  use Ecto.Repo, otp_app: :eh_os_contract_web, adapter: Ecto.Adapters.Postgres
end
