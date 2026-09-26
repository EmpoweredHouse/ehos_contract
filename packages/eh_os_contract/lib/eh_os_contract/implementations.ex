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

  @typedoc "A read model or a policy that runs inside the dispatch transaction."
  @type inline :: %{
          kind: :read_model | :policy,
          contract: module(),
          name: atom(),
          callback: atom(),
          module: module() | nil
        }

  @doc """
  The read models and policies delivered `:in_transaction` that take events of
  `type`, in any v2 contract of the host's applications: read models first, then
  policies, each in the order of their modules' names, so the order never depends
  on a scan. `callback` is the event's name in the consumer's contract, which
  differs from the publisher's when `as:` renames it. `module` is `nil` for a
  declaration nobody implemented, and dispatch refuses to go on without it.
  """
  @spec inline(module(), String.t()) :: [inline()]
  def inline(contract, type), do: Map.get(index(contract).inline, type, [])

  @doc false
  @spec index(module()) :: %{
          declarations: %{{module(), atom(), atom()} => [module()]},
          inline: %{String.t() => [inline()]}
        }
  def index(contract) do
    apps =
      Enum.uniq(
        List.wrap(Application.get_env(:eh_os_contract, :applications)) ++
          List.wrap(Application.get_application(contract))
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

    inline =
      contracts
      |> Enum.flat_map(&consumers(&1, declarations))
      |> Enum.sort_by(fn {_type, c} -> {c.kind != :read_model, inspect(c.module), c.name} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    %{declarations: declarations, inline: inline}
  end

  defp consumers(model, declarations) do
    read_models = for r <- model.read_models, do: {:read_model, r, r.projects}
    policies = for p <- model.policies, do: {:policy, p, p.handles}

    for {kind, declaration, events} <- read_models ++ policies,
        declaration.delivery == :in_transaction,
        event <- events do
      module =
        case Map.get(declarations, {model.module, kind, declaration.name}) do
          [module] -> module
          _none_or_many -> nil
        end

      {type(model, event),
       %{
         kind: kind,
         contract: model.module,
         name: declaration.name,
         callback: event,
         module: module
       }}
    end
  end

  # The stored type of an event as a contract names it: its own, or a sibling's.
  defp type(model, event) do
    case Enum.find(model.events, &(&1.name == event)) do
      %{type: type} ->
        type

      nil ->
        case EhOsContract.Model.consumed(model, event) do
          {:contract, from, original} ->
            Enum.find(EhOsContract.Model.fetch(from).events, &(&1.name == original)).type

          # Received from another application: into an inbox, never this log (D12).
          _published ->
            nil
        end
    end
  end
end
