defmodule EhosContract.Auth.SchemaRepo do
  @moduledoc """
  The repo of `EhosContract.Auth.SchemaTest`, which starts it as the role it plays —
  the owner that migrates, or the role the application runs as — with the test's
  schema as the connection's `search_path`, the way EHOS hands both to an
  application.
  """

  use Ecto.Repo, otp_app: :ehos_contract_auth, adapter: Ecto.Adapters.Postgres
end
