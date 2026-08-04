defmodule PNS.Event do
  @moduledoc """
  Log zdarzeń (notatki §3). Append-only.

  `contract_version` jest tym, co trzyma nakładkę uczciwie: graf statyczny
  opisuje kod wdrożony teraz, log obejmuje każdą wersję od pierwszego deployu.
  Zdarzenie usunięte w zeszłym miesiącu to legalna historia, nie drift.
  Tanie teraz, niemożliwe do dopisania później.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pns_events" do
    field :type, :string
    field :contract, :string
    field :contract_version, :string
    field :correlation_id, :binary_id
    field :causation_id, :binary_id
    field :payload, :map
    field :actor, :string
    field :occurred_at, :utc_datetime_usec
  end
end

defmodule PNS.EventHandling do
  @moduledoc """
  Wynik obsługi należy do handlera, nie do zdarzenia (notatki §3).

  Zdarzenie nie zawodzi — zawodzi handler, który je przetwarza. Status na
  zdarzeniu dałby dashboard, który nie umie odpowiedzieć, który handler jest
  zepsuty.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pns_event_handlings" do
    field :event_id, :binary_id
    field :handler, :string
    # "Udało się po trzech próbach" to inny stan niż "udało się",
    # a klapiący handler jest użytecznym sygnałem.
    field :attempt, :integer, default: 1
    field :status, :string
    field :duration_us, :integer
    field :error, :string
    field :inserted_at, :utc_datetime_usec
  end
end
