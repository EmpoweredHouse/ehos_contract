defmodule Taxvision.Repo.Migrations.AddProcessInstance do
  use Ecto.Migration

  def change do
    alter table(:pns_events) do
      # Tożsamość przebiegu, policzona przy emisji z pól zadeklarowanych w
      # `instance:`. Liczenie jej w zapytaniu z payloadu byłoby możliwe, ale
      # wiązałoby każdą kwerendę z **dzisiejszą** wersją kontraktu — a log
      # obejmuje każdą wersję od pierwszego deployu. To ten sam argument, który
      # posadził tu `contract_version`.
      add :process, :string
      add :instance_id, :string
    end

    # Po tym idzie każde zapytanie per przebieg: assercja `trace`, licznik
    # instancji na krawędzi, lista zdarzeń jednego przebiegu.
    create index(:pns_events, [:instance_id])
    create index(:pns_events, [:process, :instance_id])
  end
end
