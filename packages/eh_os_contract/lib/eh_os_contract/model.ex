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
  The model of a contract, or of a domain. Passing a model returns it unchanged, so a
  reader that asks many questions can build it once.

  A module compiled from a v2 DSL carries its model as `__eh_os_contract_model__/0`
  (v2 §9), and that is returned as it is. The first such module is a domain
  (`EhOsContract.Domain`, `kind: :domain`). A v1 contract has no compiled model, and
  `EhOsContract.Model.V1` builds one from its generated functions.

  The accessors below read contracts. A domain's model is plain data with its own
  keys (`contexts`, `actors`, `values`, …), read directly until a reader needs more.
  """
  @spec fetch(contract() | module()) :: t() | map()
  def fetch(%{format: 1, kind: kind} = model) when kind in [:contract, :domain], do: model

  def fetch(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract_model__, 0),
      do: module.__eh_os_contract_model__(),
      else: EhOsContract.Model.V1.build(module)
  end

  # The accessors below read a contract. A domain module has a model too, with other
  # keys, so asking one for events would fail on a missing key; it is refused by name.
  @spec contract!(contract()) :: t()
  defp contract!(contract) do
    case fetch(contract) do
      # A v2 contract's model has other keys (`units`, one `process`), and nothing
      # reads one before dispatch does (v2 plan, E6).
      %{kind: :contract, units: _, module: module} ->
        raise ArgumentError,
              "#{inspect(module)} is a v2 contract, and these accessors read v1 contracts"

      %{kind: :contract} = model ->
        model

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
    end
  end

  @doc """
  The capabilities a v2 contract declares, under the names EHOS grants them by (v2
  §16, D14): `<domain>.<command>` for each command, `<domain>.<query>` for each
  query, where `<domain>` is the domain's `name:`. Each says which roles may use it,
  `<domain>.<actor>` for every actor in its `by:`, and a query also the field its
  grant is scoped by (D10).

      %{"rehmed.record_payment" =>
          %{kind: :command, name: :record_payment, roles: ["rehmed.reception"], scope: nil}}

  Derived from the declarations, never written down. The domain's name is read from
  the compiled domain at the call, since a contract records no compile dependency on
  its domain (v2 §8); a domain that is not compiled is refused by name, and so are a
  v1 contract, which declares no capabilities, and a domain.
  """
  @spec capabilities(contract() | module()) :: %{
          String.t() => %{
            kind: :command | :query,
            name: atom(),
            roles: [String.t()],
            scope: atom() | nil
          }
        }
  def capabilities(contract) do
    case fetch(contract) do
      %{kind: :contract, grants: _} = model ->
        prefix = domain_name!(model)
        role = &"#{prefix}.#{&1}"

        commands =
          for c <- model.commands,
              do: {role.(c.name), %{kind: :command, name: c.name, by: c.by, scope: nil}}

        queries =
          for q <- model.queries,
              do: {role.(q.name), %{kind: :query, name: q.name, by: q.by, scope: q.scope}}

        Map.new(commands ++ queries, fn {capability, declared} ->
          {by, declared} = Map.pop!(declared, :by)
          {capability, Map.put(declared, :roles, by |> Enum.map(role) |> Enum.sort())}
        end)

      %{kind: :contract, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a v1 contract, which declares no capabilities"

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
    end
  end

  defp domain_name!(%{domain: domain, module: module}) do
    case Code.ensure_loaded?(domain) && fetch(domain) do
      %{kind: :domain, name: name} ->
        name

      _ ->
        raise ArgumentError,
              "#{inspect(module)} names domain #{inspect(domain)}, which is not a compiled " <>
                "EhOsContract.Domain; its capabilities are named after the domain's name:"
    end
  end

  @doc "The contract module the model was built from."
  @spec module(contract()) :: module()
  def module(contract), do: contract!(contract).module

  @doc "Every declared event, in declaration order."
  @spec events(contract()) :: [map()]
  def events(contract), do: contract!(contract).events

  @doc "The names of every declared event, in declaration order."
  @spec event_names(contract()) :: [atom()]
  def event_names(contract), do: Enum.map(events(contract), & &1.name)

  @doc "Whether the contract declares an event under that name."
  @spec event?(contract(), atom()) :: boolean()
  def event?(contract, name), do: Enum.any?(events(contract), &(&1.name == name))

  @doc "One declared event by name. Raises when the contract does not declare it."
  @spec event(contract(), atom()) :: map()
  def event(contract, name) do
    model = contract!(contract)

    Enum.find(model.events, &(&1.name == name)) ||
      raise ArgumentError, "#{inspect(model.module)}: no such event #{inspect(name)}"
  end

  @doc "Every declared process, in declaration order."
  @spec processes(contract()) :: [map()]
  def processes(contract), do: contract!(contract).processes

  @doc "One declared process by name, or `nil`."
  @spec process(contract(), atom()) :: map() | nil
  def process(contract, name), do: Enum.find(processes(contract), &(&1.name == name))

  @doc """
  The process an event belongs to, or `nil` — for an event the contract does not
  declare as well as for one that names no process.
  """
  @spec process_of(contract(), atom()) :: map() | nil
  def process_of(contract, event_name) do
    model = contract!(contract)

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
  def traces(contract), do: contract!(contract).traces

  @doc "One declared trace assertion by name, or `nil`."
  @spec trace(contract(), atom()) :: map() | nil
  def trace(contract, name), do: Enum.find(traces(contract), &(&1.name == name))

  @doc "Every declared external dependency, in declaration order."
  @spec externals(contract()) :: [map()]
  def externals(contract), do: contract!(contract).externals

  @doc "One declared external dependency by name, or `nil`."
  @spec external(contract(), atom()) :: map() | nil
  def external(contract, name), do: Enum.find(externals(contract), &(&1.name == name))

  @doc "Every declared rule, in declaration order."
  @spec rules(contract()) :: [map()]
  def rules(contract), do: contract!(contract).rules

  @doc "One declared rule by name, or `nil`."
  @spec rule(contract(), atom()) :: map() | nil
  def rule(contract, name), do: Enum.find(rules(contract), &(&1.name == name))

  @doc "Every declared example, in declaration order."
  @spec examples(contract()) :: [map()]
  def examples(contract), do: contract!(contract).examples

  @doc "Every declared command, in declaration order."
  @spec commands(contract()) :: [map()]
  def commands(contract), do: contract!(contract).commands

  @doc "One declared command by name, or `nil`."
  @spec command(contract(), atom()) :: map() | nil
  def command(contract, name), do: Enum.find(commands(contract), &(&1.name == name))

  @doc """
  The contract version: a hash of every declaration, stamped on every event.
  """
  @spec version(contract()) :: String.t()
  def version(contract), do: contract!(contract).version

  @doc """
  One digest per declaration, keyed `"<kind>:<name>"`. What
  `EhOsContract.Deployment` records to say which declaration moved.
  """
  @spec digests(contract()) :: %{String.t() => String.t()}
  def digests(contract), do: contract!(contract).digests
end
