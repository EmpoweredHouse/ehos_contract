defmodule Taxvision.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Ecto.Query

  using do
    quote do
      import Ecto.Query
      import Taxvision.DataCase

      alias Taxvision.Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Taxvision.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    PNS.Registry.load!()
    :ok
  end

  @doc "Token dla dev/testów. Prawdziwy provider nie oddaje sekretu do podpisu."
  def token(claims), do: PNS.Auth.LocalToken.sign(claims)

  def accountant(company_id \\ "c-1"),
    do: token(%{"sub" => "ksiegowa@biuro.example", "company_id" => company_id, "roles" => ["accounting"]})

  def client(company_id \\ "c-1"),
    do: token(%{"sub" => "klient@firma.example", "company_id" => company_id, "roles" => ["client"]})

  def events_of(type) do
    name = to_string(type)
    Taxvision.Repo.all(from e in PNS.Event, where: e.type == ^name, order_by: e.occurred_at)
  end
end
