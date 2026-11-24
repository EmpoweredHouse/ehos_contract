defmodule EhosContract.Auth.TestRepo do
  @moduledoc """
  The repo the package's own suite runs against, migrated by
  `EhosContract.Auth.Migrations` the way a consumer migrates.
  """

  use Ecto.Repo, otp_app: :ehos_contract_auth, adapter: Ecto.Adapters.Postgres
end
