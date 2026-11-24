defmodule EhosContract.Web.TestHost.Repo do
  @moduledoc """
  The repo the contract status screen's own suite runs against.

  Mirrors `EhosContract.TestRepo` in packages/ehos_contract: it exists so this package's
  LiveView can be proven against real conformance data without a client
  application, using `EhosContract.Migrations` the same way any consumer would.
  """

  use Ecto.Repo, otp_app: :ehos_contract_web, adapter: Ecto.Adapters.Postgres
end
