defmodule Taxvision.Repo.Migrations.CreatePeriods do
  use Ecto.Migration

  @moduledoc """
  Okres rozliczeniowy przestaje być stringiem i staje się wierszem.

  Zysk nie jest taki, jak się wydaje na pierwszy rzut oka — „jeden okres
  istnieje" daje też unikalny indeks na kolumnie tekstowej. Prawdziwy zysk to
  **kanonizacja**: przy jednym wierszu na okres `"2026-7"` obok `"2026-07"`
  przestaje być możliwe, a nie tylko niezalecane.

  Zakres dat jest tym, po co ta tabela naprawdę istnieje: dwa różne moduły
  potrzebują tej samej odpowiedzi na pytanie „do kiedy trwa lipiec", a joiny
  międzymodułowe są zabronione.
  """

  def change do
    # Własność: Taxvision.Periods
    create table(:taxvision_periods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
    end

    # Kanonizacja jest tutaj, nie w konwencji nazewniczej.
    create unique_index(:taxvision_periods, [:name])

    # Dwa moduły, ta sama odpowiedź, dwie kopie. Duplikacja jest **strategiczna
    # i ma nazwane źródło prawdy** (`Taxvision.Periods`) — nie jest wspólną
    # tabelą i nie jest joinem.
    alter table(:taxvision_tasks) do
      add :due_on, :date
    end

    alter table(:taxvision_accounting_months) do
      add :closes_on, :date
    end
  end
end
