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

  @typedoc """
  A declaration that reacts to events: a read model, a policy or an effect of a v2
  contract of the host's applications.

  `callbacks` maps each stored type it takes to its callback: the event's name in the
  consumer's contract, which differs from the publisher's when `as:` renames it.
  `module` is `nil` for a declaration nobody implemented. `key` names it,
  `"<contract>:<kind>:<name>"`: its row in `eh_os_contract_subscriptions` and its
  effect jobs' argument. `version` is what that row compares to
  tell a changed declaration: the digest of the declaration and of every event it
  takes, so a read model whose event gained a field is stale too.
  """
  @type consumer :: %{
          kind: :read_model | :policy | :process_manager | :effect,
          contract: module(),
          name: atom(),
          delivery: :in_transaction | :at_least_once,
          module: module() | nil,
          callbacks: %{String.t() => atom()},
          key: String.t(),
          version: String.t()
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
  Every consumer that keeps a row in `eh_os_contract_subscriptions`, in the order of
  their keys: read models and policies delivered `:at_least_once` and process
  managers, which a runner feeds in order, and read models delivered `:in_transaction`, whose
  row lets them be rebuilt. The host's applications are the configured ones:
  unlike dispatch, a boot does not know which contract will be dispatched, so an
  ordered consumer of a contract outside `config :eh_os_contract, applications:` gets
  no row and no runner.
  """
  @spec subscribed() :: [consumer()]
  def subscribed, do: index(nil).subscribed

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
  The consumer whose key is `key`, or `nil`. Looked up where dispatch looks: the
  configured applications and the application of the contract the key names, so an
  effect's job finds the effect its dispatch enqueued it for.
  """
  @spec consumer(String.t()) :: consumer() | nil
  def consumer(key) do
    [contract | _] = String.split(key, ":")
    Enum.find(index(existing(contract)).consumers, &(&1.key == key))
  end

  defp existing(contract) do
    Module.safe_concat([contract])
  rescue
    ArgumentError -> nil
  end

  @doc false
  @spec index(module() | nil) :: %{
          declarations: %{{module(), atom(), atom()} => [module()]},
          inline: %{String.t() => [inline()]},
          effects: %{String.t() => [inline()]},
          consumers: [consumer()],
          subscribed: [consumer()]
        }
  def index(contract) do
    apps =
      Enum.uniq(
        List.wrap(Application.get_env(:eh_os_contract, :applications)) ++
          List.wrap(contract && Application.get_application(contract))
      )

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
        |> Enum.sort_by(& &1.key)
    }
  end

  @doc "Where a kind of consumer runs in the dispatch transaction: read models, policies, effects."
  @spec order(:read_model | :policy | :process_manager | :effect) :: 0 | 1 | 2
  def order(:read_model), do: 0
  def order(:policy), do: 1
  def order(:process_manager), do: 1
  def order(:effect), do: 2

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

    for {kind, declaration, events} <- read_models ++ policies ++ effects ++ managers do
      module =
        case Map.get(declarations, {model.module, kind, declaration.name}) do
          [module] -> module
          _none_or_many -> nil
        end

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

      %{
        kind: kind,
        contract: model.module,
        name: declaration.name,
        delivery: declaration.delivery,
        module: module,
        callbacks: Map.merge(Map.new(taken, fn {type, event, _} -> {type, event} end), timers),
        key: "#{inspect(model.module)}:#{kind}:#{declaration.name}",
        version:
          EhOsContract.Digest.hash([
            Map.fetch!(model.digests, "#{kind}:#{declaration.name}")
            | Enum.map(taken, &elem(&1, 2))
          ])
      }
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
    case Enum.find(model.events, &(&1.name == event)) do
      %{type: type} ->
        {type, Map.fetch!(model.digests, "event:#{event}")}

      nil ->
        case EhOsContract.Model.consumed(model, event) do
          {:contract, from, original} ->
            publisher = EhOsContract.Model.fetch(from)
            %{type: type} = Enum.find(publisher.events, &(&1.name == original))
            {type, Map.fetch!(publisher.digests, "event:#{original}")}

          _published ->
            {nil, nil}
        end
    end
  end
end
