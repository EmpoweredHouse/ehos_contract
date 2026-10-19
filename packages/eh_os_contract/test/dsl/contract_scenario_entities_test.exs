defmodule EhOsContract.ContractScenarioEntitiesTest do
  @moduledoc """
  Plan DD, T2a (#240): **S12** — a scenario of a command that reads entities gives
  each entity's row with `given_entity`, and no other scenario gives one. Whether the
  row's fields are the entity's is X9's (`ContractLinksScenariosTest`).
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Visit" do
      identity :visit_id

      command :book_visit, "Book", by: :reception, emits: :visit_booked, reads: [service: :service_id] do
        field :service_id, {:id, :service}
      end

      command :cancel_visit, "Cancel", by: :reception, emits: :visit_cancelled

      event :visit_booked, "Booked"
      event :visit_cancelled, "Cancelled"
    end
  """

  test "a missing row, a row of an entity not read, and a row for a command that reads none" do
    message =
      refuse_contract(
        "EntitiesWrong",
        @unit <>
          """

            scenario "booking without a service" do
              given_entity :room, %{room_id: "r-1"}
              command :book_visit, %{service_id: "s-1"}
              expect :visit_booked
            end

            scenario "cancellation" do
              given_entity :service, %{service_id: "s-1"}
              command :cancel_visit, %{}
              expect :visit_cancelled
            end
          """
      )

    assert message =~
             ~s|S12: scenario "booking without a service": given_entity :room is not an entity | <>
               "command :book_visit reads ([:service])"

    assert message =~
             ~s|S12: scenario "booking without a service": command :book_visit reads :service, and | <>
               "the scenario gives no given_entity :service"

    assert message =~
             ~s|S12: scenario "cancellation": given_entity gives a row only to a command that | <>
               "reads: entities"
  end

  test "control: the row of the entity read compiles, and the model keeps it" do
    model =
      compile_contract(
        "EntitiesRight",
        @unit <>
          """

            scenario "booking" do
              given_entity :service, %{service_id: "s-1", registry_reported: true}
              command :book_visit, %{service_id: "s-1"}
              expect :visit_booked
            end

            scenario "cancellation" do
              command :cancel_visit, %{}
              expect :visit_cancelled
            end
          """
      )

    booked = Enum.find(model.scenarios, &(&1.description == "booking"))
    cancelled = Enum.find(model.scenarios, &(&1.description == "cancellation"))

    assert booked.given_entities == [
             %{entity: :service, data: %{service_id: "s-1", registry_reported: true}}
           ]

    # Kept only where given, so no other scenario's digest moves.
    refute Map.has_key?(cancelled, :given_entities)
  end
end
