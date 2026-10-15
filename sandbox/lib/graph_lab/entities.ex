defmodule GraphLab.Entities do
  @moduledoc """
  The service catalogue of the test set (`GraphLab`): physiotherapy is reported to P1,
  fitness is not, and any other service is not in the catalogue.

  **The host does not configure it**: the sandbox's configuration names another
  `EhOsContract.Entities`, and the test set leaves it as it is. Its scenarios give their
  rows with `given_entity`, so only a booking dispatched in the host reads a catalogue,
  and only `mix graph_lab.traffic` dispatches one: it points the engine here for its own
  run.
  """

  @behaviour EhOsContract.Entities

  @services %{
    "service-physiotherapy" => %{service_id: "service-physiotherapy", p1_reported: true},
    "service-fitness" => %{service_id: "service-fitness", p1_reported: false}
  }

  @impl true
  def fetch(_actor, GraphLab.Domain, :service, id) do
    case Map.fetch(@services, id) do
      {:ok, service} -> {:ok, service}
      :error -> :not_found
    end
  end

  # An entity something else reads while the traffic task points the engine here: said by
  # name, rather than a FunctionClauseError whose log would print the actor.
  def fetch(_actor, domain, entity, _id) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} keeps no #{inspect(entity)} of #{inspect(domain)}: only the " <>
            "test set's service catalogue"
  end
end
