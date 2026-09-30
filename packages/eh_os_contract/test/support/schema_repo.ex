defmodule EhOsContract.SchemaRepo do
  @moduledoc """
  The repo of `EhOsContract.SchemaTest`, which starts it as the role it plays — the
  owner that migrates, or the role the application runs as — with the test's schema
  as the connection's `search_path`, the way EHOS hands both to an application.

  Nothing configures it: every option comes from the test, so no other test can
  reach it by accident.
  """

  use Ecto.Repo, otp_app: :eh_os_contract, adapter: Ecto.Adapters.Postgres
end
