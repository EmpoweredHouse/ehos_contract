defmodule EhOsContract.Model do
  @moduledoc """
  A contract or a domain as plain data, and the one way every reader asks one
  anything (v2 §9).

  A module compiled from the DSL — `use EhOsContract.Contract` or
  `use EhOsContract.Domain` — carries its model as `__eh_os_contract_model__/0`, and
  readers ask for it through `fetch/1` rather than calling that function themselves.

  ## The data

      %{format: 1, kind: :contract, module: MyApp.Contracts.Month,
        domain: MyApp.Domain, context: :settlement, process: %{...},
        events: [...], commands: [...], units: [...], policies: [...],
        scenarios: [...], ...,
        version: "3f9c…", digests: %{"event:month_opened" => "…"}}

  **Collections are lists in declaration order**, not the maps keyed by name that
  v2 §9 sketches. Readers print in declaration order — the graph lists its nodes
  that way, the report its processes — so a map would change their output. Order
  does not reach the version: `EhOsContract.Digest` makes declaration order
  insignificant, and that is where v2 §9's "declaration order does not matter"
  belongs.

  A domain's model is plain data with its own keys (`contexts`, `actors`, `values`,
  …), read directly until a reader needs more. So is a process module's
  (`use EhOsContract.Process`, plan DD, P2b, #205), of kind `:process`
  (`EhOsContract.Process.Build`); `process/1`, `process_events/1` and `declaring/2`
  answer for it as for a contract's process, so the readers of a run — `EhOsContract.Run`,
  `EhOsContract.Trace`, `EhOsContract.Paths.runs_of/3` — read either (plan DD, P2d, #213).
  """

  @typedoc "A contract module, or the model already built from one."
  @type contract :: module() | t()

  @typedoc "One contract as data: the keys every reader relies on, and the rest."
  @type t :: %{
          required(:format) => 1,
          required(:kind) => :contract,
          required(:module) => module(),
          required(:version) => String.t(),
          required(:digests) => %{String.t() => String.t()},
          optional(atom()) => term()
        }

  @doc """
  The model of a contract, of a domain or of a process module. Passing a model
  returns it unchanged, so a reader that asks many questions can build it once.

  A module that carries no compiled model is refused by name.
  """
  @spec fetch(contract() | module()) :: t() | map()
  def fetch(%{format: 1, kind: kind} = model) when kind in [:contract, :domain, :process],
    do: model

  def fetch(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract_model__, 0),
      do: module.__eh_os_contract_model__(),
      else:
        raise(
          ArgumentError,
          "#{inspect(module)} is not a contract, a domain or a process compiled from " <>
            "EhOsContract's DSL"
        )
  end

  @doc """
  The capabilities a v2 contract declares, under the names EHOS grants them by (v2
  §16, D14): `<domain>.<command>` for each command, `<domain>.<query>` for each
  query and `<domain>.<event>` for each event a contract records (`recorded_by:`,
  D6), where `<domain>` is the domain's `name:`. Each says which roles may use it,
  `<domain>.<actor>` for every `:human` actor in its `by:` or `recorded_by:`, and a
  query also the field its grant is scoped by (D10).

  **Only what a person may do is a capability.** A declaration whose `by:` or
  `recorded_by:` names no `:human` actor — a command only a reaction issues, an event
  only an integration records — has none, so no credential can be granted it; the
  application's own `:system` actor and the reactions reach it as before.

      %{"rehmed.record_payment" =>
          %{kind: :command, name: :record_payment, roles: ["rehmed.reception"], scope: nil}}

  **One more, which is the application's: `<name>.subscribe`** for each event it
  subscribes to from another application and a policy handles (D11, `eh-os` D-41), under
  the publisher's name
  without its version — `subscribe "rehmed.visit.closed.v1"` asks for
  `rehmed.visit.closed.subscribe` — with the event's name in the contract and no
  roles: EHOS grants it to the application per environment, never to a person, and
  the transport delivers by the grant. Nothing in this engine asks for it.

      %{"rehmed.visit.closed.subscribe" =>
          %{kind: :subscribe, name: :visit_closed, roles: [], scope: nil}}

  Derived from the declarations, never written down. The domain's name is read from
  the compiled domain at the call, since a contract records no compile dependency on
  its domain (v2 §8); a domain that is not compiled is refused by name, and so is a
  domain.
  """
  @spec capabilities(contract() | module()) :: %{
          String.t() => %{
            kind: :command | :query | :record | :subscribe,
            name: atom(),
            roles: [String.t()],
            scope: atom() | nil
          }
        }
  def capabilities(contract) do
    case fetch(contract) do
      %{kind: :contract, grants: _} = model ->
        domain = domain!(model)
        role = &"#{domain.name}.#{&1}"
        people = for %{kind: :human, name: name} <- domain.actors, into: MapSet.new(), do: name

        commands =
          for c <- model.commands,
              do:
                {role.(c.name),
                 %{kind: :command, name: c.name, by: c.by, scope: Map.get(c, :scope)}}

        queries =
          for q <- model.queries,
              do: {role.(q.name), %{kind: :query, name: q.name, by: q.by, scope: q.scope}}

        # A person's observation reaches the log through `record/3` with a credential,
        # so it is granted like a command (plan, decided before E9, built in E9a).
        records =
          for e <- model.events,
              e.recorded_by != [],
              do: {role.(e.name), %{kind: :record, name: e.name, by: e.recorded_by, scope: nil}}

        # Only a person holds a credential, so only a declaration a person may use has a
        # capability, and its roles are the people's. What only the application's own
        # code does — a reaction's command, an integration's recording — is not
        # grantable at all: a credential granted it by mistake could otherwise write
        # "sent to P1" without a send (plan, E9a review).
        granted =
          for {capability, declared} <- commands ++ queries ++ records,
              {by, declared} = Map.pop!(declared, :by),
              humans = Enum.filter(by, &MapSet.member?(people, &1)),
              humans != [],
              into: %{},
              do: {capability, Map.put(declared, :roles, humans |> Enum.map(role) |> Enum.sort())}

        Map.merge(granted, subscriptions(model))

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
    end
  end

  # The publisher's name, which D11 versions, less its version: the grant is to take
  # the event, whichever version a consumer reads. Only for an event a policy handles,
  # since only then is there an inbox to take it (`EhOsContract.Implementations.inboxes/0`):
  # a grant with nothing behind it would leave a durable consumer on the transport
  # that nobody reads.
  defp subscriptions(model) do
    for %{kind: :published, from: from, as: as} <- model.consumes,
        Enum.any?(model.policies, &(as in &1.handles)),
        into: %{} do
      {String.replace(from, ~r/\.v[0-9]+\z/, "") <> ".subscribe",
       %{kind: :subscribe, name: as, roles: [], scope: nil}}
    end
  end

  @doc """
  A v2 contract, its domain and its derived capabilities as JSON-ready data for
  EHOS and other tooling.

  The top-level `schema` is the contract of this export. It is deliberately
  separate from the DSL model's internal `format`: the latter can evolve without
  making an unversioned transport shape look stable. Atom keys and values become
  strings, module atoms lose the `Elixir.` prefix, and tuples become arrays, so
  `Jason` can encode the result without knowing any Elixir representation.

  Scenario, rule and invariant examples keep their structure, but values of fields
  declared personal become `null`, including personal fields nested in domain
  values. The public model is documentation, not a second store for fixtures that
  may contain a real person's data.

  The digest covers exactly the generated document before the digest is inserted.
  It therefore moves when the projection changes, when the contract changes or
  when a domain change moves roles or capabilities.
  """
  @spec to_data(contract()) :: map()
  def to_data(contract) do
    model = contract!(contract)
    domain = domain!(model)
    {exported_model, exported_domain} = EhOsContract.Model.Export.redact(model, domain)

    body = %{
      "schema" => "eh_os_contract.model.v1",
      "contract" => json_data(exported_model),
      "domain" => json_data(exported_domain),
      "capabilities" => model |> capabilities() |> json_data()
    }

    Map.put(body, "digest", EhOsContract.Digest.document_hash(body))
  end

  defp json_data(nil), do: nil
  defp json_data(value) when is_boolean(value) or is_binary(value) or is_number(value), do: value

  defp json_data(value) when is_atom(value) do
    case Atom.to_string(value) do
      "Elixir." <> module -> module
      name -> name
    end
  end

  defp json_data(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_data()
  defp json_data(value) when is_list(value), do: Enum.map(value, &json_data/1)

  defp json_data(value) when is_map(value) do
    value
    |> :maps.to_list()
    |> Map.new(fn {key, item} -> {json_key(key), json_data(item)} end)
  end

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key

  defp domain!(%{domain: domain, module: module}) do
    # Only a compiled model is asked: `fetch/1` on any other module would fail with
    # its own error instead of this one.
    compiled? =
      Code.ensure_loaded?(domain) and function_exported?(domain, :__eh_os_contract_model__, 0)

    case compiled? && domain.__eh_os_contract_model__() do
      %{kind: :domain} = model ->
        model

      _ ->
        raise ArgumentError,
              "#{inspect(module)} names domain #{inspect(domain)}, which is not a compiled " <>
                "EhOsContract.Domain; its capabilities are named after the domain's name:"
    end
  end

  @typedoc "What a contract generates a module for."
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
    model = contract!(contract)

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
    Enum.find_value(contract!(contract).consumes, fn
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

  A process module declares no event; for one, this is the contract that declares the
  event it includes under `name` (plan DD, P2d, #213).
  """
  @spec declaring(contract() | map(), atom()) :: {module(), map()} | nil
  def declaring(contract, name) do
    case fetch(contract) do
      %{kind: :process} = model ->
        Enum.find_value(
          process_events(model),
          &(&1.name == name && {&1.contract, &1.declaration})
        )

      _contract ->
        declaring_in_contract(contract!(contract), name)
    end
  end

  defp declaring_in_contract(model, name) do
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

  @typedoc """
  A contract's process as the model holds it: its `name` and `label`, the fields
  that `correlate` its runs, the `accountable` actor, its `stages`, the `includes`
  that place consumed events in it, its `deadline`, its `promises` and its `source`.

  A process module's has the same keys (plan DD, P2d, #213). Its `name` is its `id:`,
  a string, since its runs are filed under it; every event of its run is an include,
  `%{contract, event, stage, terminal}`, and `terminal` is whether `ends_on` names it.
  """
  @type process :: %{
          required(:name) => atom() | String.t(),
          required(:correlate) => [atom()],
          required(:includes) => [map()],
          required(:stages) => [map()],
          required(:promises) => [map()],
          optional(atom()) => term()
        }

  @typedoc """
  One event of a process's run:

    * `type` — the type it is stored under, `"<contract id>.<event>"` of the contract
      that declares it;
    * `name` — its name in this contract, which for an included event is the name it
      is consumed under (`as:`), not the sibling's;
    * `contract` — the module that declares it: this contract, or the sibling;
    * `stage` — the stage group a local event sits in, or the stage its `include`
      sits in; `nil` outside one;
    * `terminal` — whether it ends a run: a local event's own `terminal:`, an
      included one's `include`'s, never the sibling's declaration;
    * `included` — `false` for this contract's own event, `true` for one its process
      includes;
    * `declaration` — the event's declaration in the contract that declares it.
  """
  @type process_event :: %{
          type: String.t(),
          name: atom(),
          contract: module(),
          stage: atom() | nil,
          terminal: boolean(),
          included: boolean(),
          declaration: map()
        }

  @doc """
  The process a contract declares, or `nil` when it declares none. A domain declares
  none either. A process module is one, under its `id:` (plan DD, P2d, #213).

  The one way a reader asks for it: what a process is may move out of the contract,
  and only this function would then change (plan DD, P2a, #202).
  """
  @spec process(contract() | map()) :: process() | nil
  def process(%{kind: :process} = model) do
    %{
      name: model.id,
      label: model.label,
      accountable: model.accountable,
      source: model.source,
      correlate: model.correlate,
      stages: model.stages,
      includes:
        for stage <- model.stages, include <- stage.includes do
          Map.merge(include, %{stage: stage.name, terminal: include.event in model.ends_on})
        end,
      deadline: model.deadline,
      promises: model.promises
    }
  end

  def process(%{} = model), do: Map.get(model, :process)
  def process(module) when is_atom(module), do: module |> fetch() |> process()

  @doc """
  The events of a contract's process's run, in this order: every event the contract
  declares, in declaration order, then every consumed event its process includes, in
  the order of its `include`s — those at the process's level first, then each stage's
  in turn (see `t:process_event/0`). `[]` when the contract declares no process.

  An include whose event cannot be resolved to a declaration — one another
  application publishes, which `R4` refuses, or one its sibling does not declare —
  is left out, since it is stored under no type of this log.

  A process module's run is every event its stages include, in their order, each
  resolved to the contract that declares it; `terminal` is whether `ends_on` names it
  (plan DD, P2d, #213). An include of a contract this node cannot load, of an event
  that contract does not declare, or of a contract of another domain is left out: the
  rules between modules refuse all three (X5). Those rules run per project, and a
  process module of a dependency is read here too, so the domain is checked again: this
  is the one rule for what a module includes, which the check, the deployment record and
  the index of runs (`EhOsContract.Implementations`) all read.
  """
  @spec process_events(contract() | map()) :: [process_event()]
  def process_events(contract) do
    model = if is_atom(contract), do: fetch(contract), else: contract

    case {model, process(model)} do
      {_model, nil} ->
        []

      {%{kind: :process}, process} ->
        for include <- process.includes,
            %{events: events, domain: domain} <- [compiled(include.contract)],
            domain == model.domain,
            %{} = event <- [Enum.find(events, &(&1.name == include.event))] do
          %{
            type: event.type,
            name: include.event,
            contract: include.contract,
            stage: include.stage,
            terminal: include.terminal,
            included: true,
            declaration: event
          }
        end

      {_contract, process} ->
        own =
          for e <- model.events do
            %{
              type: e.type,
              name: e.name,
              contract: model.module,
              stage: e.stage,
              terminal: e.terminal,
              included: false,
              declaration: e
            }
          end

        included =
          for include <- process.includes,
              {contract, %{} = event} <- [declaring(model, include.event)] do
            %{
              type: event.type,
              name: include.event,
              contract: contract,
              stage: include.stage,
              terminal: include.terminal,
              included: true,
              declaration: event
            }
          end

        own ++ included
    end
  end

  # A contract's model, or `nil` for a module that is not one compiled here.
  defp compiled(module) do
    with true <-
           Code.ensure_loaded?(module) and
             function_exported?(module, :__eh_os_contract_model__, 0),
         %{kind: :contract} = model <- module.__eh_os_contract_model__() do
      model
    else
      _ -> nil
    end
  end

  defp contract!(contract) do
    case fetch(contract) do
      %{kind: :contract} = model ->
        model

      %{kind: kind, module: module} ->
        raise ArgumentError, "#{inspect(module)} is a #{kind}, not a contract"
    end
  end

  @doc "The contract version: a hash of every declaration, stamped on every event."
  @spec version(contract()) :: String.t()
  def version(contract), do: contract!(contract).version

  @doc """
  One digest per declaration, keyed `"<kind>:<name>"`. What
  `EhOsContract.Deployment` records to say which declaration moved.
  """
  @spec digests(contract()) :: %{String.t() => String.t()}
  def digests(contract), do: contract!(contract).digests
end
