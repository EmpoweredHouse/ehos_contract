defmodule Taxvision.Tasks do
  @moduledoc """
  Taski miesięczne. Moduł **posiada swoje tabele** i nikt inny ich nie tyka
  (ADR §5-6).

  Żadnych joinów do tabel innych modułów i żadnych widoków nad nimi. Zakaz
  podnosi liczbę zapytań, a wygenerowany kod nie zauważy pięciuset — dlatego
  N+1 jest nazwanym ryzykiem, nie niespodzianką (notatki §14).
  """

  use Boundary,
    deps: [PNS, Taxvision.Repo, Taxvision.Contracts],
    exports: [Task]

  @doc "Szablon zadań dla formy prawnej. Zmiany obowiązują od kolejnego miesiąca (P3)."
  def template("JDG"),
    do: ["Pobrać wyciągi", "Skompletować faktury KSeF", "Zaksięgować dokumenty", "Wysłać deklarację"]

  def template(_), do: ["Skompletować dokumenty", "Zaksięgować dokumenty", "Wysłać deklarację"]
end

defmodule Taxvision.Tasks.Task do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "taxvision_tasks" do
    field :company_id, :string
    field :period, :string
    field :name, :string
    field :status, :string, default: "open"
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Taxvision.Tasks.OnRegistryDataConsistent do
  @moduledoc """
  Handler **synchroniczny**: dotyka wyłącznie własnych tabel w tej samej bazie,
  więc idzie w transakcji zmiany stanu.

  Gdyby rzucił, cała transakcja się cofa i wołający dostaje błąd. To jest
  poprawne dokładnie dlatego, że tu nie ma żadnego I/O na zewnątrz: nie ma
  czego ponawiać, bo nic się nie stało. Ten sam mechanizm zastosowany do
  wysyłki maila pozwoliłby pobocznej sprawie zawetować operację biznesową — i
  dlatego takie handlery nie mogą być synchroniczne.
  """

  use PNS.Handler,
    contract: Taxvision.Contracts.AccountingMonth,
    event: :registry_data_consistent,
    publishes: [:monthly_tasks_generated]

  alias Taxvision.Tasks.Task

  @impl PNS.Handler
  def handle(%{company_id: company_id, period: period}, _ctx) do
    names = Taxvision.Tasks.template("JDG")
    now = DateTime.utc_now()

    entries =
      for name <- names do
        %{
          id: Ecto.UUID.generate(),
          company_id: company_id,
          period: period,
          name: name,
          status: "open",
          inserted_at: now
        }
      end

    {count, _} = Taxvision.Repo.insert_all(Task, entries)

    {:ok,
     [
       PNS.event(:monthly_tasks_generated, %{
         company_id: company_id,
         period: period,
         task_count: count
       })
     ]}
  end
end

