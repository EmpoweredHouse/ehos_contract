defmodule Taxvision.AccountingMonth do
  @moduledoc """
  Agregat rdzenia z sekcji 12 warsztatu: stepper Gromadzenie -> Meczowanie ->
  Wynik, otwarcie warunkowane pozytywną weryfikacją rejestrową, każdy krok ma
  deadline, rozliczenie miesiąc w tył.

  W tym wycinku zaimplementowane jest wyłącznie otwarcie. Kroki 3.2-3.4 są
  zadeklarowane w kontrakcie i nieobsłużone — celowo.
  """

  use Boundary,
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts],
    exports: [Month]
end

defmodule Taxvision.AccountingMonth.Month do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_accounting_months" do
    field :company_id, :string
    field :period, :string
    field :status, :string
    field :opened_at, :utc_datetime_usec
  end
end

defmodule Taxvision.AccountingMonth.OnMonthlyTasksGenerated do
  @moduledoc """
  Handler synchroniczny. Kolejność z warsztatu jest tu istotna i nieprzypadkowa:
  taski powstają **przed** otwarciem miesiąca (`najpierw checki, potem taski`,
  a otwarcie na końcu) — więc miesiąc bez tasków nie istnieje.
  """

  use PNS.Handler,
    contract: Taxvision.Contracts.AccountingMonth,
    event: :monthly_tasks_generated,
    publishes: [:accounting_month_opened]

  alias Taxvision.AccountingMonth.Month

  @impl PNS.Handler
  def handle(%{company_id: company_id, period: period}, _ctx) do
    Taxvision.Repo.insert!(%Month{
      company_id: company_id,
      period: period,
      status: "open",
      opened_at: DateTime.utc_now()
    })

    {:ok, [PNS.event(:accounting_month_opened, %{company_id: company_id, period: period})]}
  end
end
