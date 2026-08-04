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

    result
  end
end
