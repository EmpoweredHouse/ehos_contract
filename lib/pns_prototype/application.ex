defmodule PnsPrototype.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [PNS, Taxvision]

  @impl true
  def start(_type, _args) do
    children = [
      Taxvision.Repo,
      {Oban, Application.fetch_env!(:pns_prototype, Oban)}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: PnsPrototype.Supervisor)

    # Skan rejestru przy boocie. Graf pochodzi z binarki, która faktycznie
    # działa — nie z pliku obok niej.
    PNS.Registry.load!()

    # Zapis wdrożonej wersji: co jest zadeklarowane i od kiedy obowiązuje.
    # Bez tego nie da się odróżnić historii od driftu dla **ścieżek**, bo
    # `version/0` haszuje kontrakt, a ścieżki pochodzą z handlerów.
    PNS.Deployment.record!()

    result
  end
end
