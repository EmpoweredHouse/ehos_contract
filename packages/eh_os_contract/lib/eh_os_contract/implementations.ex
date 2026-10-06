defmodule EhOsContract.Implementations do
  @moduledoc """
  Which module implements which declaration of a v2 contract, found in the binary
  that runs (v2 §10.5).

  A contract names no implementation (v2 §8), so dispatch looks them up: every
  module of the host's applications — `config :eh_os_contract, applications: [...]`,
  and the contract's own — whose `__eh_os_implementation__/0` names a declaration.
  The scan runs once per set of applications and is kept in `:persistent_term`; a
  module added to a running node is found after a restart.

  Two implementations of one declaration fail the lookup, as they fail the compile
  (X8): which one ran would depend on the order of a scan.
  """

  @doc """
  The module implementing `kind` `name` of the contract `model`. Raises when there
  is none: dispatch cannot decide without the code that decides.
  """
  @spec fetch!(map(), atom(), atom()) :: module()
  def fetch!(model, kind, name) do
    case Map.get(index(model.module).declarations, {model.module, kind, name}) do
      [module] ->
        module

      nil ->
        raise ArgumentError,
              "no module implements #{kind} #{inspect(name)} of #{inspect(model.module)}; bind " <>
                "one with `use #{inspect(model.module)}, #{kind}: #{inspect(name)}`"

      many ->
        raise ArgumentError,
              "#{kind} #{inspect(name)} of #{inspect(model.module)} has #{length(many)} " <>
                "implementations: #{inspect(many)}"
    end
  end

  @doc """
  The stored types the `evolve/2` of `module`, a unit's implementation, folds, or
  `:all`: what dispatch has to read and decode to rebuild its state, and what a
  scenario's `given` is compared on (plan E11f-5). `:all` too for `nil`, a unit
  nobody implemented.
  """
  @spec folded_types(map(), module() | nil) :: MapSet.t(String.t()) | :all
  def folded_types(_model, nil), do: :all

  def folded_types(model, module) do
    case Map.get(module.__eh_os_implementation__(), :folds, :all) do
      :all ->
        :all

      names ->
        MapSet.new(names, fn name ->
          {_contract, declaration} = EhOsContract.Model.declaring(model, name)
          declaration.type
        end)
    end
  end

  @typedoc """
  A declaration that reacts to events: a read model, a policy or an effect of a v2
  contract of the host's applications — or a `publish`, whose relay takes the events
  it publishes and hands them to `EhOsContract.Bus` (v2 §16). A relay is implemented
  by the engine, so its `module` is `nil`, and it carries its `publication`.

  `callbacks` maps each stored type it takes to its callback: the event's name in the
  consumer's contract, which differs from the publisher's when `as:` renames it. A
  process manager also takes its timers' firings, `:timer_elapsed`, and a read model
  that projects personal data every erasure, `:forget` (v2 §14); `forgets` holds the
  subject types it forgets, the ones whose personal data it projects.
  `module` is `nil` for a declaration nobody implemented. `key` names it,
  `"<contract id>:<kind>:<name>"`: its row in `eh_os_contract_subscriptions` and its
  effect jobs' argument. `version` is what that row compares to
  tell a changed declaration: the digest of the declaration and of every event it
  takes, so a read model whose event gained a field is stale too.
  """
  @type consumer :: %{
          required(:kind) => :read_model | :policy | :process_manager | :effect | :relay,
          optional(:publication) => map(),
          required(:contract) => module(),
          required(:name) => atom(),
          required(:delivery) => :in_transaction | :at_least_once,
          required(:module) => module() | nil,
          required(:callbacks) => %{String.t() => atom()},
          required(:forgets) => MapSet.t(atom()),
          required(:key) => String.t(),
          required(:version) => String.t()
        }

  @typedoc "A consumer as it takes one stored `type`, with the `callback` for it."
  @type inline :: %{
          required(:kind) => :read_model | :policy | :effect,
          required(:contract) => module(),
          required(:name) => atom(),
          required(:type) => String.t(),
          required(:callback) => atom(),
          required(:module) => module() | nil,
          optional(atom()) => term()
        }

  @doc """
  The read models, policies and effects delivered `:in_transaction` that take events
  of `type`, in any v2 contract of the host's applications: read models first, then
  policies, then effects, each in the order of their modules' names, so the order
  never depends on a scan. `module` is `nil` for a declaration nobody implemented,
  and dispatch refuses to go on without it.
  """
  @spec inline(module(), String.t()) :: [inline()]
  def inline(contract, type), do: Map.get(index(contract).inline, type, [])

  @doc """
  The effects delivered `:at_least_once` that take events of `type`, in the same
  order as `inline/2`: dispatch enqueues one job for each.
  """
  @spec effects(module(), String.t()) :: [inline()]
  def effects(contract, type), do: Map.get(index(contract).effects, type, [])

  @doc """
  The processes of the v2 contracts that `include` events of `type` (D7), each with
  the fields that correlate its runs, in the applications dispatch of `contract`
  looks in: the runs an event of that type belongs to besides its home run.
  """
  @spec included(module(), String.t()) :: [%{name: atom(), correlate: [atom()]}]
  def included(contract, type), do: Map.get(index(contract).included, type, [])

  @doc """
  Every consumer that keeps a row in `eh_os_contract_subscriptions`, in the order of
  their keys: read models and policies delivered `:at_least_once`, process managers
  and relays, which a runner feeds in order, and read models delivered `:in_transaction`, whose
  row lets them be rebuilt. The host's applications are the configured ones:
  unlike dispatch, a boot does not know which contract will be dispatched, so an
  ordered consumer of a contract outside `config :eh_os_contract, applications:` gets
  no row and no runner.
  """
  @spec subscribed() :: [consumer()]
  def subscribed, do: index(nil).subscribed

  @typedoc """
  What takes another application's published event (D12, v2 §16): one per
  `subscribe "<name>"` that a policy of the contract handles. `from` is the versioned
  name it takes from `EhOsContract.Bus`, `name` the event's name in the contract,
  `fields` what the contract reads of it, and `policies` the policies that handle it,
  each as it takes the event, in the order of their modules' names. `key`,
  `"<contract id>:inbox:<name>"`, names its rows in `eh_os_contract_inbox` and its
  durable consumer on the transport.
  """
  @type inbox :: %{
          kind: :inbox,
          contract: module(),
          name: atom(),
          from: String.t(),
          fields: [map()],
          policies: [inline()],
          key: String.t()
        }

  @doc """
  Every inbox of the host's applications, the configured ones as for `subscribed/0`,
  in the order of their keys. A received event no policy handles has none: nothing
  would react to it, so nothing subscribes to it.
  """
  @spec inboxes() :: [inbox()]
  def inboxes, do: index(nil).inboxes

  @doc """
  Whether any consumer is fed from the log after the transaction, in the
  applications dispatch of `contract` looks in: what a runner would wake up for.
  """
  @spec ordered?(module()) :: boolean()
  def ordered?(contract),
    do: Enum.any?(index(contract).subscribed, &(&1.delivery == :at_least_once))

  @doc """
  `consumer` as it takes the stored `type`: `inline()`, with the callback for it.
  """
  @spec taking(consumer(), String.t()) :: inline()
  def taking(consumer, type),
    do: Map.merge(consumer, %{type: type, callback: Map.fetch!(consumer.callbacks, type)})

  @doc """
  The consumer whose key, `"<contract id>:<kind>:<name>"`, is `key`, or `nil`. Looked
  up among the configured applications and `application`, when given: an effect's job
  passes the one its dispatch looked in, which the key's id cannot name (plan DD, ID4,
  #178).
  """
  @spec consumer(String.t(), atom() | nil) :: consumer() | nil
  def consumer(key, application \\ nil),
    do: Enum.find(index_of(List.wrap(application)).consumers, &(&1.key == key))

  @doc """
  The contract whose `id` is `id`, or `nil`: what a row of the log or a consumer's key
  names (plan DD, ID4, #178). Looked up among the configured applications and
  `application`, when given — the one a dispatch also looked in, which an id cannot
  name. The whole id, never a prefix of it, so `clinic.a` never finds `clinic.a.b`.

  A subscription and a process manager decode with no `application`: they find a
  contract of the configured applications, or a sibling one of them consumes.
  """
  @spec contract(String.t(), atom() | nil) :: map() | nil
  def contract(id, application \\ nil) when is_binary(id),
    do: Map.get(index_of(List.wrap(application)).contracts, id)

  @doc false
  @spec index(module() | nil) :: %{
          declarations: %{{module(), atom(), atom()} => [module()]},
          inline: %{String.t() => [inline()]},
          effects: %{String.t() => [inline()]},
          consumers: [consumer()],
          subscribed: [consumer()],
          inboxes: [inbox()],
          included: %{String.t() => [%{name: atom(), correlate: [atom()]}]},
          contracts: %{String.t() => map()}
        }
  def index(contract), do: index_of(List.wrap(contract && Application.get_application(contract)))

  defp index_of(also) do
    apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)) ++ also)

    key = {__MODULE__, apps}

    case :persistent_term.get(key, nil) do
      nil ->
        index = build(apps)
        :persistent_term.put(key, index)
        index

      index ->
        index
    end
  end

  defp build(apps) do
    modules =
      for app <- apps,
          module <- Application.spec(app, :modules) || [],
          Code.ensure_loaded?(module),
          do: module

    declarations =
      for module <- modules,
          function_exported?(module, :__eh_os_implementation__, 0),
          %{contract: contract, kind: kind, name: name} = module.__eh_os_implementation__(),
          reduce: %{} do
        acc -> Map.update(acc, {contract, kind, name}, [module], &Enum.sort([module | &1]))
      end

    contracts =
      for module <- modules,
          function_exported?(module, :__eh_os_contract_model__, 0),
          match?(%{kind: :contract, units: _}, module.__eh_os_contract_model__()),
          do: module.__eh_os_contract_model__()

    known = by_id(contracts)

    consumers =
      contracts
      |> Enum.flat_map(&consumers(&1, declarations))
      |> Enum.sort_by(&{order(&1.kind), inspect(&1.module), &1.name})

    %{
      declarations: declarations,
      consumers: consumers,
      inline: by_type(Enum.filter(consumers, &(&1.delivery == :in_transaction))),
      effects:
        by_type(Enum.filter(consumers, &(&1.kind == :effect and &1.delivery == :at_least_once))),
      subscribed:
        consumers
        |> Enum.filter(
          &(&1.kind != :effect and (&1.delivery == :at_least_once or &1.kind == :read_model))
        )
        |> Enum.sort_by(& &1.key),
      inboxes:
        contracts
        |> Enum.flat_map(&inboxes(&1, declarations))
        |> Enum.sort_by(& &1.key),
      included: included(contracts),
      contracts: known
    }
  end

  @doc false
  # The contracts an id finds (plan DD, ID4, #178): the scanned ones, and the siblings
  # they consume, which their `consumes` names by module, so a subscription decodes a
  # sibling's event wherever the node loaded it from. One id, one contract.
  @spec by_id([map()]) :: %{String.t() => map()}
  def by_id(contracts) do
    siblings =
      for contract <- contracts,
          %{kind: :contract, from: from} <- contract.consumes,
          do: EhOsContract.Model.fetch(from)

    known = Enum.uniq_by(contracts ++ siblings, & &1.module)
    :ok = EhOsContract.Registry.unique_ids!(known)
    Map.new(known, &{&1.id, &1})
  end

  defp inboxes(model, declarations) do
    for %{kind: :published, from: from, as: as, fields: fields} <- model.consumes,
        policies = received_by(model, declarations, from, as),
        policies != [] do
      %{
        kind: :inbox,
        contract: model.module,
        name: as,
        from: from,
        fields: fields,
        policies: policies,
        key: "#{model.id}:inbox:#{as}"
      }
    end
  end

  # The policies of `model` that handle the received event `as`, each as it takes it:
  # its callback is the event's name in the contract, and its type the name it was
  # published under, which names the policy's link in a chain.
  defp received_by(model, declarations, from, as) do
    for policy <- model.policies, as in policy.handles do
      %{
        kind: :policy,
        contract: model.module,
        name: policy.name,
        type: from,
        callback: as,
        module: implemented(declarations, model, :policy, policy.name)
      }
    end
    |> Enum.sort_by(&{inspect(&1.module), &1.name})
  end

  defp implemented(declarations, model, kind, name) do
    case Map.get(declarations, {model.module, kind, name}) do
      [module] -> module
      _none_or_many -> nil
    end
  end

  # A process includes a sibling's event by the name it consumes it under, and the
  # event is stored under the sibling's type. Another application's event is received
  # into an inbox, never this log (D12), so its runs are not written here.
  defp included(contracts) do
    for %{process: %{includes: [_ | _]} = process} = model <- contracts,
        include <- process.includes,
        {:contract, from, original} <- [EhOsContract.Model.consumed(model, include.event)],
        %{name: ^original, type: type} <- EhOsContract.Model.fetch(from).events,
        uniq: true do
      {type, %{name: process.name, correlate: process.correlate}}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {type, runs} -> {type, Enum.sort(runs)} end)
  end

  @doc """
  The order of kinds of consumer: in the dispatch transaction, read models, then
  policies, then effects; in the index, where a process manager sorts with policies
  and a relay, which never runs in the transaction, comes last.
  """
  @spec order(:read_model | :policy | :process_manager | :effect | :relay) :: 0 | 1 | 2 | 3
  def order(:read_model), do: 0
  def order(:policy), do: 1
  def order(:process_manager), do: 1
  def order(:effect), do: 2
  def order(:relay), do: 3

  defp by_type(consumers) do
    consumers
    |> Enum.flat_map(fn c -> for {type, _} <- c.callbacks, do: {type, taking(c, type)} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp consumers(model, declarations) do
    read_models = for r <- model.read_models, do: {:read_model, r, r.projects}
    policies = for p <- model.policies, do: {:policy, p, p.handles}
    effects = for e <- model.effects, do: {:effect, e, e.handles}
    managers = for pm <- model.process_managers, do: {:process_manager, pm, triggers(pm)}

    reacting =
      for {kind, declaration, events} <- read_models ++ policies ++ effects ++ managers,
          do: reacting(model, declarations, kind, declaration, events)

    reacting ++ Enum.map(model.publishes, &relay(model, &1))
  end

  # A publish's relay: one ordered subscription over the one type it publishes.
  defp relay(model, publication) do
    {type, digest} = stored(model, publication.from)

    %{
      kind: :relay,
      contract: model.module,
      name: publication.name,
      delivery: :at_least_once,
      module: nil,
      callbacks: %{type => publication.from},
      forgets: MapSet.new(),
      publication: publication,
      key: "#{model.id}:relay:#{publication.name}",
      version:
        EhOsContract.Digest.hash([
          Map.fetch!(model.digests, "publish:#{publication.name}"),
          digest
        ])
    }
  end

  defp reacting(model, declarations, kind, declaration, events) do
    module = implemented(declarations, model, kind, declaration.name)

    # Received from another application: into an inbox, never this log (D12).
    taken =
      for event <- events,
          {type, digest} = stored(model, event),
          type,
          do: {type, event, digest}

    # A process manager also takes its own timers' firings, one type for all of them.
    timers =
      if kind == :process_manager,
        do: %{EhOsContract.ProcessManager.elapsed() => :timer_elapsed},
        else: %{}

    # A read model that projects personal data also takes every erasure, and
    # forgets a subject of the types it holds (v2 §14).
    subjects =
      if kind == :read_model,
        do: Enum.reduce(events, MapSet.new(), &MapSet.union(&2, subjects(model, &1))),
        else: MapSet.new()

    forgets =
      if MapSet.size(subjects) > 0,
        do: %{EhOsContract.Personal.erased_type() => :forget},
        else: %{}

    %{
      kind: kind,
      contract: model.module,
      name: declaration.name,
      delivery: declaration.delivery,
      module: module,
      callbacks:
        Map.new(taken, fn {type, event, _} -> {type, event} end)
        |> Map.merge(timers)
        |> Map.merge(forgets),
      forgets: subjects,
      key: "#{model.id}:#{kind}:#{declaration.name}",
      version:
        EhOsContract.Digest.hash([
          Map.fetch!(model.digests, "#{kind}:#{declaration.name}")
          | Enum.map(taken, &elem(&1, 2))
        ])
    }
  end

  # The subject types whose personal data an event a contract names, its own or a
  # sibling's, carries at any depth.
  defp subjects(model, event) do
    case EhOsContract.Model.declaring(model, event) do
      {contract, %{fields: fields}} ->
        EhOsContract.Codec.personal_subjects(
          fields,
          EhOsContract.Codec.values(EhOsContract.Model.fetch(contract).domain)
        )

      nil ->
        MapSet.new()
    end
  end

  # The events a process manager takes: what it starts, reacts and ends on, and not
  # its own timers, whose firings come as one type of their own.
  defp triggers(pm) do
    timers = MapSet.new(pm.timers, & &1.name)

    (Enum.map(pm.starts_on ++ pm.on, & &1.event) ++ pm.ends_on)
    |> Enum.reject(&MapSet.member?(timers, &1))
    |> Enum.uniq()
  end

  # The stored type of an event as a contract names it, its own or a sibling's, and
  # the digest of its declaration; `{nil, nil}` for one another application publishes.
  defp stored(model, event) do
    case EhOsContract.Model.declaring(model, event) do
      {contract, %{name: name, type: type}} ->
        {type, Map.fetch!(EhOsContract.Model.fetch(contract).digests, "event:#{name}")}

      nil ->
        {nil, nil}
    end
  end
end
