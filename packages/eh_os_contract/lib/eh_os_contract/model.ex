defmodule EhOsContract.Model do
  @moduledoc """
  A contract as plain data, and the one way every reader asks a contract anything
  (v2 §9).

  Readers — `EhOsContract.Trace`, `EhOsContract.Graph`, `EhOsContract.Conformance`
  and the rest — used to call the query functions `use EhOsContract.Contract`
  generates on every contract module (`events/0`, `processes/0`, `traces/0`, …).
  They now call the accessors here, and only `EhOsContract.Model.V1` calls those
  functions. That is the seam the move to v2 runs through: a v2 contract answers
  with its own compiled model, and no reader has to know which DSL wrote it.

  ## The data

      %{format: 1, kind: :contract, module: MyApp.Contracts.Month,
        events: [...], processes: [...], commands: [...], traces: [...],
        externals: [...], rules: [...], examples: [...],
        version: "3f9c…", digests: %{"event:month_opened" => "…"}}

  It is the subset of v2 §9 that v1 has. v1 has no domain, context, units,
  policies or scenarios, so those keys are absent rather than empty: an empty
  collection would claim the contract declares none, which is a statement v1
  cannot make. A v1 contract may hold several processes, so `processes` is a list
  where v2 has one `process`.

  **Collections are lists in declaration order**, not the maps keyed by name that
  v2 §9 sketches. Readers print in declaration order — the graph lists its nodes
  that way, the report its processes — so a map would change their output. Order
  does not reach the version: `EhOsContract.Digest` makes declaration order
  insignificant, and that is where v2 §9's "declaration order does not matter"
  belongs.

  Declarations keep the shape v1 builds them in (`EhOsContract.Contract`), so a
  reader moving onto this module changes the function it calls and nothing else.
  """

  @typedoc "A contract module, or the model already built from one."
  @type contract :: module() | t()

  @typedoc "One contract as data."
  @type t :: %{
          required(:format) => 1,
          required(:kind) => :contract,
          required(:module) => module(),
          required(:events) => [map()],
          required(:processes) => [map()],
          required(:commands) => [map()],
          required(:traces) => [map()],
          required(:externals) => [map()],
          required(:rules) => [map()],
          required(:examples) => [map()],
          required(:version) => String.t(),
          required(:digests) => %{String.t() => String.t()}
        }

  @doc """
  Whether a module is a contract. Used by the registry's scan and by the handler
  gate, which is why it takes any module and never raises.
  """
  @spec contract?(module()) :: boolean()
  def contract?(module) when is_atom(module), do: EhOsContract.Model.V1.contract?(module)

  @doc """
  The model of a contract. Passing a model returns it unchanged, so a reader that
  asks many questions can build it once.
  """
  @spec fetch(contract()) :: t()
  def fetch(%{format: 1, kind: :contract} = model), do: model
  def fetch(module) when is_atom(module), do: EhOsContract.Model.V1.build(module)

  @doc "The contract module the model was built from."
  @spec module(contract()) :: module()
  def module(contract), do: fetch(contract).module

  @doc "Every declared event, in declaration order."
  @spec events(contract()) :: [map()]
  def events(contract), do: fetch(contract).events

  @doc "The names of every declared event, in declaration order."
  @spec event_names(contract()) :: [atom()]
  def event_names(contract), do: Enum.map(events(contract), & &1.name)

  @doc "Whether the contract declares an event under that name."
  @spec event?(contract(), atom()) :: boolean()
  def event?(contract, name), do: Enum.any?(events(contract), &(&1.name == name))

  @doc "One declared event by name. Raises when the contract does not declare it."
  @spec event(contract(), atom()) :: map()
  def event(contract, name) do
    model = fetch(contract)

    Enum.find(model.events, &(&1.name == name)) ||
      raise ArgumentError, "#{inspect(model.module)}: no such event #{inspect(name)}"
  end

  @doc "Every declared process, in declaration order."
  @spec processes(contract()) :: [map()]
  def processes(contract), do: fetch(contract).processes

  @doc "One declared process by name, or `nil`."
  @spec process(contract(), atom()) :: map() | nil
  def process(contract, name), do: Enum.find(processes(contract), &(&1.name == name))

  @doc """
  The process an event belongs to, or `nil` — for an event the contract does not
  declare as well as for one that names no process.
  """
  @spec process_of(contract(), atom()) :: map() | nil
  def process_of(contract, event_name) do
    model = fetch(contract)

    case Enum.find(model.events, &(&1.name == event_name)) do
      %{process: nil} -> nil
      %{process: name} -> process(model, name)
      nil -> nil
    end
  end

  @doc "The events belonging to a process, in declaration order."
  @spec events_of(contract(), atom()) :: [map()]
  def events_of(contract, process_name),
    do: Enum.filter(events(contract), &(&1.process == process_name))

  @doc "Every declared trace assertion, in declaration order."
  @spec traces(contract()) :: [map()]
  def traces(contract), do: fetch(contract).traces

  @doc "One declared trace assertion by name, or `nil`."
  @spec trace(contract(), atom()) :: map() | nil
  def trace(contract, name), do: Enum.find(traces(contract), &(&1.name == name))

  @doc "Every declared external dependency, in declaration order."
  @spec externals(contract()) :: [map()]
  def externals(contract), do: fetch(contract).externals

  @doc "One declared external dependency by name, or `nil`."
  @spec external(contract(), atom()) :: map() | nil
  def external(contract, name), do: Enum.find(externals(contract), &(&1.name == name))

  @doc "Every declared rule, in declaration order."
  @spec rules(contract()) :: [map()]
  def rules(contract), do: fetch(contract).rules

  @doc "One declared rule by name, or `nil`."
  @spec rule(contract(), atom()) :: map() | nil
  def rule(contract, name), do: Enum.find(rules(contract), &(&1.name == name))

  @doc "Every declared example, in declaration order."
  @spec examples(contract()) :: [map()]
  def examples(contract), do: fetch(contract).examples

  @doc "Every declared command, in declaration order."
  @spec commands(contract()) :: [map()]
  def commands(contract), do: fetch(contract).commands

  @doc "One declared command by name, or `nil`."
  @spec command(contract(), atom()) :: map() | nil
  def command(contract, name), do: Enum.find(commands(contract), &(&1.name == name))

  @doc """
  The contract version: a hash of every declaration, stamped on every event.
  """
  @spec version(contract()) :: String.t()
  def version(contract), do: fetch(contract).version

  @doc """
  One digest per declaration, keyed `"<kind>:<name>"`. What
  `EhOsContract.Deployment` records to say which declaration moved.
  """
  @spec digests(contract()) :: %{String.t() => String.t()}
  def digests(contract), do: fetch(contract).digests
end
