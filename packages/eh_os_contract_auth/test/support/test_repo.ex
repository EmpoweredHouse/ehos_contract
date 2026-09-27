defmodule EhOsContract.Auth.TestRepo do
  @moduledoc """
  The repo the package's own suite runs against, migrated by
  `EhOsContract.Auth.Migrations` the way a consumer migrates.
  """

  use Ecto.Repo, otp_app: :eh_os_contract_auth, adapter: Ecto.Adapters.Postgres
end
