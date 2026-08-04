defmodule Taxvision.Notifications do
  @moduledoc """
  Powiadomienia. Z warsztatu (sekcja 12, HS1, HS26): encja w bazie, log
  dostarczeń, **kwoty nigdy w treści maila**, krytyczne wymagają potwierdzenia.
  """

  use Boundary,
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts],
    exports: [Notification]
end

defmodule Taxvision.Notifications.Notification do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_notifications" do
    field :company_id, :string
    field :period, :string
    field :recipient, :string
    field :subject, :string
    # Odsyłacz, nie treść: diff siedzi w logu zdarzeń, tutaj jest tylko jego
    # odcisk. To jednocześnie reguła z warsztatu i skutek `retain: %{diff: :hash}`.
    field :body_ref, :string
    field :idempotency_key, :string
    field :sent_at, :utc_datetime_usec
  end
end

defmodule Taxvision.Notifications.OnRegistryDiscrepancyDetected do
  @moduledoc """
  Handler **asynchroniczny**: wychodzi na zewnątrz (mail), więc nie ma prawa
  siedzieć w transakcji. Idzie przez Obana, wstawiony w tej samej transakcji co
  zmiana stanu — outbox darmo.

  Oban daje at-least-once, więc to zdarzenie **przyjdzie drugi raz**.
  Idempotencja jest tu warunkiem poprawności, nie dobrą praktyką, i dlatego
  makro handlera nie pozwoliło zadeklarować `async: true` bez klucza.
  """

  use PNS.Handler,
    contract: Taxvision.Contracts.AccountingMonth,
    event: :registry_discrepancy_detected,
    publishes: [:discrepancy_notification_sent],
    async: true

  import Ecto.Query

  alias Taxvision.Notifications.Notification

  @recipients ["ksiegowa@biuro.example", "klient@firma.example"]

  @impl PNS.Handler
  def handle(%{company_id: company_id, period: period} = payload, ctx) do
    key = ctx.idempotency_key

    # Sprawdzenie idempotencji na własnej tabeli. Ograniczenie tej metody jest
    # nazwane, nie zamiecione: dosięga własnych tabel i liczników wywołań
    # mocków, i nic więcej (notatki §6).
    if Taxvision.Repo.exists?(from n in Notification, where: n.idempotency_key == ^key) do
      :ok
    else
      now = DateTime.utc_now()

      entries =
        for recipient <- @recipients do
          %{
            id: Ecto.UUID.generate(),
            company_id: company_id,
            period: period,
            recipient: recipient,
            subject: "Rozjazd danych rejestrowych — miesiąc #{period} zablokowany",
            body_ref: Map.get(payload, :diff) || "brak",
            idempotency_key: key,
            sent_at: now
          }
        end

      {count, _} = Taxvision.Repo.insert_all(Notification, entries)

      {:ok,
       [
         PNS.event(:discrepancy_notification_sent, %{
           company_id: company_id,
           period: period,
           recipients: count
         })
       ]}
    end
  end
end
