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
  query and `<domain>.<event>` for each event a contract records (`recorded_by:`,
  D6), where `<domain>` is the domain's `name:`. Each says which roles may use it,
  `<domain>.<actor>` for every actor in its `by:` or `recorded_by:`, and a query also
  the field its grant is scoped by (D10).

      %{"rehmed.record_payment" =>
          %{kind: :command, name: :record_payment, roles: ["rehmed.reception"], scope: nil}}

  Derived from the declarations, never written down. The domain's name is read from
  the compiled domain at the call, since a contract records no compile dependency on
  its domain (v2 §8); a domain that is not compiled is refused by name, and so are a
  v1 contract, which declares no capabilities, and a domain.
  """
  @spec capabilities(contract() | module()) :: %{
          String.t() => %{
            kind: :command | :query | :record,
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

        # A person's observation reaches the log through `record/3` with a credential,
        # so it is granted like a command (plan, "Po E8"; E9a).
        records =
          for e <- model.events,
              e.recorded_by != [],
              do: {role.(e.name), %{kind: :record, name: e.name, by: e.recorded_by, scope: nil}}

        Map.new(commands ++ queries ++ records, fn {capability, declared} ->
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
    # Only a compiled model is asked: `fetch/1` on any other module would try it as a
    # v1 contract and fail with that error instead of this one.
    compiled? =
      Code.ensure_loaded?(domain) and function_exported?(domain, :__eh_os_contract_model__, 0)

    case compiled? && domain.__eh_os_contract_model__() do
      %{kind: :domain, name: name} ->
        name

      _ ->
        raise ArgumentError,
              "#{inspect(module)} names domain #{inspect(domain)}, which is not a compiled " <>
                "EhOsContract.Domain; its capabilities are named after the domain's name:"
    end
  end

  @typedoc "What a v2 contract generates a module for (v2 §5)."
  @type generated ::
          :command
          | :event
          | :aggregate
          | :dcb
          | :policy
          | :effect
          | :process_manager
          | :read_model
          | :query
          | :domain_service
          | :value

  @doc """
  The module a v2 contract generates for a declaration (v2 §5): the struct of a
  command, an event or a query's parameters, or the behaviour of a unit, a policy,
  an effect, a process manager or a read model. A domain generates one too, the
  behaviour of a value that declares invariants (plan EL2b):

      Model.module_for(Rehmed.Domain, :value, :money)
      #=> Rehmed.Domain.Values.Money

      Model.module_for(Rehmed.Contracts.VisitSettlement, :command, :record_payment)
      #=> Rehmed.Contracts.VisitSettlement.Commands.RecordPayment

  An event is named as the contract knows it. A local one is `C.Events.X`. One
  consumed from a sibling contract is the sibling's own struct, under its name
  there, so a change to it reaches every subscriber (v2 §7). One received from
  another application is `C.Received.X`, built from the fields this contract
  declares for it (D11). A unit's state is `Module.concat(unit, State)`, a read
  model's row `Module.concat(read_model, Row)`.

  A name the contract does not declare is refused.
  """
  @spec module_for(contract() | map(), generated(), atom()) :: module()
  def module_for(domain, :value, name) do
    case fetch(domain) do
      %{kind: :domain, module: module, values: values} ->
        if Enum.any?(values, &(&1.name == name and &1.invariants != [])),
          do: generated_name(module, Values, name),
          else:
            raise(
              ArgumentError,
              "#{inspect(module)} declares no value #{inspect(name)} with invariants"
            )

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, and only a domain has values"
    end
  end

  def module_for(contract, kind, name) do
    model = v2!(contract)

    generated(model, kind, name) ||
      raise ArgumentError, "#{inspect(model.module)} declares no #{kind} #{inspect(name)}"
  end

  @namespaces [
    command: {:commands, Commands},
    policy: {:policies, Policies},
    effect: {:effects, Effects},
    process_manager: {:process_managers, ProcessManagers},
    read_model: {:read_models, ReadModels},
    query: {:queries, Queries},
    domain_service: {:domain_services, DomainServices}
  ]

  defp generated(model, :event, name) do
    if declared?(model.events, name),
      do: generated_name(model.module, Events, name),
      else: consumed_module(model, name)
  end

  defp generated(model, unit, name) when unit in [:aggregate, :dcb] do
    if Enum.any?(model.units, &(&1.name == name and &1.kind == unit)),
      do: generated_name(model.module, if(unit == :aggregate, do: Aggregates, else: Dcbs), name)
  end

  defp generated(model, kind, name) do
    {key, namespace} = Keyword.fetch!(@namespaces, kind)
    if declared?(Map.fetch!(model, key), name), do: generated_name(model.module, namespace, name)
  end

  defp declared?(declarations, name), do: Enum.any?(declarations, &(&1.name == name))

  defp generated_name(module, namespace, name),
    do: Module.concat([module, namespace, name |> Atom.to_string() |> Macro.camelize()])

  # An event this contract consumes: a sibling's struct under its original name, or
  # the struct received events get here.
  defp consumed_module(model, name) do
    case consumed(model, name) do
      {:contract, from, original} -> generated_name(from, Events, original)
      {:published, _fields} -> generated_name(model.module, Received, name)
      nil -> nil
    end
  end

  @doc """
  Where an event a v2 contract consumes comes from, asked by the name it has in that
  contract:

    * `{:contract, sibling, name}` — a sibling contract's event, under its name
      there, which differs from the local one when `as:` renames it;
    * `{:published, fields}` — another application's published event, with the
      fields this contract declares for it (D11);
    * `nil` — the contract consumes no event of that name.
  """
  @spec consumed(contract() | map(), atom()) ::
          {:contract, module(), atom()} | {:published, [map()]} | nil
  def consumed(contract, name) do
    Enum.find_value(v2!(contract).consumes, fn
      %{kind: :published, as: ^name, fields: fields} ->
        {:published, fields}

      %{kind: :contract, from: from, events: events, renames: renames} ->
        original = Enum.find(events, fn event -> Map.get(renames, event, event) == name end)
        original && {:contract, from, original}

      _ ->
        nil
    end)
  end

  @doc """
  The contract that declares an event a v2 contract names, with its declaration:
  the contract's own event, or a sibling's it consumes, found under the sibling's
  name. `nil` for an event another application publishes, which is received into an
  inbox and never stored in this log (D12), and for a name the contract does not know.
  """
  @spec declaring(contract() | map(), atom()) :: {module(), map()} | nil
  def declaring(contract, name) do
    model = v2!(contract)

    case Enum.find(model.events, &(&1.name == name)) do
      %{} = event ->
        {model.module, event}

      nil ->
        case consumed(model, name) do
          {:contract, from, original} ->
            {from, Enum.find(fetch(from).events, &(&1.name == original))}

          _published_or_unknown ->
            nil
        end
    end
  end

  defp v2!(contract) do
    case fetch(contract) do
      %{kind: :contract, units: _} = model ->
        model

      %{kind: :contract, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a v1 contract, which generates no modules"

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
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
  The contract version: a hash of every declaration, stamped on every event. A v2
  contract's too, which is a key both models have.
  """
  @spec version(contract()) :: String.t()
  def version(contract), do: any_contract!(contract).version

  @doc """
  One digest per declaration, keyed `"<kind>:<name>"`. What
  `EhOsContract.Deployment` records to say which declaration moved. A v2 contract's
  too.
  """
  @spec digests(contract()) :: %{String.t() => String.t()}
  def digests(contract), do: any_contract!(contract).digests

  # A contract of either DSL, for the keys both models have.
  defp any_contract!(contract) do
    case fetch(contract) do
      %{kind: :contract} = model ->
        model

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
    end
  end
end
