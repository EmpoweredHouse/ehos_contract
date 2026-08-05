defmodule Taxvision.Api do
  @moduledoc """
  Krawędź żądania. Tu przechodzą **trzy poziomy IAM**, każdy dając inną
  odpowiedź — i to jest cały test tego, czy szew jest postawiony w dobrym
  miejscu.

  | Poziom | Kto właścicielem | Odpowiedź przy odmowie |
  |---|---|---|
  | Uwierzytelnienie — kto to jest | kupione | `:unauthenticated` |
  | Entitlement — czy dosięga API księgowego | kupione, claim z tokenu | `:forbidden`, **przed** kodem domenowym |
  | Reguła domenowa — czy może otworzyć **ten** miesiąc | nasze, reguła w kontrakcie | odrzucenie z powodem, zapisany przypadek |

  Trzeci wiersz jest tym, o co idzie gra. Gdyby dał się przejść konfiguracją
  providera, poziomy nie byłyby rozdzielone i cała wartość byłaby kupiona.

  To jest odpowiednik pipeline'u Phoenixa, napisany bez Phoenixa. Warstwa web nie
  pokazuje w tym wycinku nic spornego, a REST przeciw GraphQL jest w decyzji 008
  wciąż otwarte — budowanie API przesądzałoby otwartą decyzję. Podmiana jest
  mechaniczna: `authenticate` i `entitle` to dwa plugi, `open_month` to akcja
  kontrolera.

  Zwróć uwagę, czego tu **nie** ma: dostępu do `Taxvision.Tasks`,
  `Taxvision.Notifications` ani `Taxvision.AccountingMonth`. Krawędź emituje
  zdarzenie i na tym kończy się jej wiedza o tym, co się dalej dzieje. Gdyby
  wołała te moduły wprost, `boundary` by ją zatrzymał — i to jest ta różnica
  między architekturą event-driven a nazwaniem czegoś event-driven.
  """

  use Boundary,
    deps: [
      PNS,
      Taxvision.Contracts,
      Taxvision.Authorization,
      Taxvision.RegistryCheck,
      Taxvision.Adapters
    ],
    exports: []

  alias Taxvision.Contracts.AccountingMonth

  @doc "Otwiera miesiąc księgowy. Zwraca `{:ok, correlation_id}` albo powód odmowy."
  def open_month(token, %{company_id: company_id, period: period}) do
    with {:ok, actor} <- authenticate(token),
         :ok <- entitle(actor),
         {:ok, registries} <- Taxvision.Adapters.RegistryLookup.lookup(company_id),
         input = build_input(actor, company_id, period, registries),
         :ok <- Taxvision.Authorization.authorize_open_month(input),
         emissions when is_list(emissions) <- Taxvision.RegistryCheck.decide(input),
         {:ok, events} <- PNS.emit_all(AccountingMonth, emissions, %{actor: actor.subject}) do
      {:ok, List.first(events).correlation_id}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp authenticate(token) do
    case PNS.Auth.verify(token) do
      {:ok, actor} -> {:ok, actor}
      {:error, _} -> {:error, :unauthenticated}
    end
  end

  defp entitle(actor) do
    # Jeden claim, zero sieci. Odcięcie następuje tutaj, więc żadne zdarzenie
    # nie trafia do logu — i to jest sprawdzalne brakiem wiersza, nie treścią
    # odpowiedzi.
    if PNS.Auth.entitled?(actor, :accounting), do: :ok, else: {:error, :forbidden}
  end

  defp build_input(actor, company_id, period, registries) do
    %{
      command: :open_month,
      company_id: company_id,
      period: period,
      actor: actor.subject,
      actor_roles: actor.roles,
      # Najemca czytany z claimu przez **kod domenowy**, nie ze struktury
      # silnika: „czyja to firma" jest pytaniem TaxVision, nie PNS-a.
      actor_company: actor.claims["company_id"],
      completeness_confirmed: true,
      checked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: registries
    }
  end
end
