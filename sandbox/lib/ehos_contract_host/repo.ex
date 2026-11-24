defmodule EhosContractHost.Repo do
  @moduledoc """
  The host's one repo: the engine's log, Oban's jobs and every project's own tables
  share one Postgres and one transaction (ADR §5-6). A project in the sandbox reaches
  it as any application reaches its repo, and none of them owns it.
  """

  use Boundary, top_level?: true, deps: [], exports: []
  use Ecto.Repo, otp_app: :ehos_contract_host, adapter: Ecto.Adapters.Postgres
end
