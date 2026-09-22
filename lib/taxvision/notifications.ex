defmodule Taxvision.Notifications do
  @moduledoc """
  Notifications. From the workshop (section 12, HS1, HS26): an entity in the
  database, a delivery log, **amounts never in the body of an email**, and
  critical ones requiring acknowledgement.
  """

  use Boundary,
    # `Taxvision.Periods` is here because the subject line needs a month's name. Declared
    # rather than reached for: `boundary` refused the reference the moment it appeared,
    # which is the no-join rule making a new cross-module dependency visible instead of
    # letting it arrive as a join somebody notices later.
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts, Taxvision.Periods],
    exports: [Notification]
end

defmodule Taxvision.Notifications.Notification do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_notifications" do
    field(:company_id, :string)
    field(:period_id, :binary_id)
    field(:recipient, :string)
    field(:subject, :string)
    # A reference, not the content: the diff lives in the event log and only its
    # fingerprint is here. That is both a workshop rule and the consequence of
    # `retain: %{diff: :hash}`.
    field(:body_ref, :string)
    field(:idempotency_key, :string)
    field(:sent_at, :utc_datetime_usec)
  end
end

defmodule Taxvision.Notifications.OnRegistryDiscrepancyDetected do
  @moduledoc """
  An **asynchronous** handler: it reaches outside (email), so it has no business
  sitting inside a transaction. It goes through Oban, inserted in the same
  transaction as the state change — an outbox for free.

  Oban gives at-least-once, so this event **will arrive a second time**.
  Idempotency here is a correctness condition rather than a good practice, which
  is why the handler macro refused `async: true` without a key.
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
  def handle(%{company_id: company_id, period_id: period_id} = payload, ctx) do
    key = ctx.idempotency_key

    # The idempotency check against this module's own table. The limit of that
    # method is named rather than swept away: it reaches its own tables and mock
    # call counters, and nothing more (notes §6).
    if Taxvision.Repo.exists?(from(n in Notification, where: n.idempotency_key == ^key)) do
      :ok
    else
      now = DateTime.utc_now()

      # **The outbound edge, and it is symmetric with the inbound one.** Facts carry an
      # identifier; a person reads a name. `Taxvision.Api` resolves the name coming in,
      # and this resolves it going out — otherwise an accountant gets an email saying
      # "month 3f2a8c…-… blocked", which is a uuid leaking out of the place uuids are
      # for. Names at the edges, identifiers inside.
      period = Taxvision.Periods.fetch_by_id!(period_id)

      entries =
        for recipient <- @recipients do
          %{
            id: Ecto.UUID.generate(),
            company_id: company_id,
            period_id: period_id,
            recipient: recipient,
            subject: "Rozjazd danych rejestrowych — miesiąc #{period.name} zablokowany",
            body_ref: Map.get(payload, :diff) || "none",
            idempotency_key: key,
            sent_at: now
          }
        end

      {count, _} = Taxvision.Repo.insert_all(Notification, entries)

      {:ok,
       [
         PNS.event(:discrepancy_notification_sent, %{
           company_id: company_id,
           period_id: period_id,
           recipients: count
         })
       ]}
    end
  end
end
