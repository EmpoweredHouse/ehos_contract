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

    # Wdrożenia zapisuje **boot aplikacji**, czyli poza sandboxem — te wiersze
    # commitują się do bazy testowej na stałe i przeciekłyby do każdego testu,
    # który cokolwiek o wdrożeniach twierdzi. Czyszczenie idzie wewnątrz
    # transakcji sandboxa, więc cofa się po teście, a zachowanie produkcyjne
    # zostaje nietknięte: tam zapis przy boocie jest właśnie tym, co ma być.
    Taxvision.Repo.delete_all(PNS.Deployment)

    # Okres jest **kanonicznym wierszem**, a nie stringiem parsowanym w locie, więc
    # musi istnieć, zanim ktokolwiek cokolwiek w nim zaksięguje. W produkcji
    # zakłada go admin albo harmonogram; tutaj zakłada go setup, bo wymaganie tego
    # od każdego testu osobno dodałoby szumu bez sygnału.
    #
    # Że to wymaganie faktycznie obowiązuje, pilnuje jeden test w
    # `periods_test.exs` — i tylko on zakłada okres sam.
    for miesiac <- ~w(2026-05 2026-06 2026-07 2026-08), do: Taxvision.Periods.ensure!(miesiac)

    :ok
  end

  @doc "Token dla dev/testów. Prawdziwy provider nie oddaje sekretu do podpisu."
  def token(claims), do: PNS.Auth.LocalToken.sign(claims)

  # `sub` jest **nieprzezroczystym, stabilnym identyfikatorem**, nie mailem.
  # Pierwsza wersja fikstury wpisywała tu adres e-mail i przez to każde
  # zdarzenie w logu niosło dane osobowe w kolumnie `actor` — mimo że szew był
  # zaprojektowany poprawnie. Mail się zmienia przy zmianie nazwiska, `sub` nie,
  # więc mail w tej roli psuje też ciągłość audytu.
  @accountant_sub "018f2a3c-7b4e-7c21-9d55-0a1b2c3d4e5f"
  @client_sub "018f2a3c-9d10-7f88-b402-6e7f8a9b0c1d"

  def accountant_sub, do: @accountant_sub
  def client_sub, do: @client_sub

  def accountant(company_id \\ "c-1"),
    do: token(%{"sub" => @accountant_sub, "company_id" => company_id, "roles" => ["accounting"]})

  def client(company_id \\ "c-1"),
    do: token(%{"sub" => @client_sub, "company_id" => company_id, "roles" => ["client"]})

  @doc "Kanoniczny okres. Zakładany w setupie, bo bez niego nie da się otworzyć miesiąca."
  def period!(name), do: Taxvision.Periods.ensure!(name)

  def events_of(type) do
    name = to_string(type)
    Taxvision.Repo.all(from e in PNS.Event, where: e.type == ^name, order_by: e.occurred_at)
  end
end
