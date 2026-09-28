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
    deps: [EhOsContract, Taxvision.Repo, Taxvision.Contracts, Taxvision.Periods],
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
