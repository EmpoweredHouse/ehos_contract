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

  @doc false
  @spec index(module()) :: %{declarations: %{{module(), atom(), atom()} => [module()]}}
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
    declarations =
      for app <- apps,
          module <- Application.spec(app, :modules) || [],
          Code.ensure_loaded?(module),
          function_exported?(module, :__eh_os_implementation__, 0),
          %{contract: contract, kind: kind, name: name} = module.__eh_os_implementation__(),
          reduce: %{} do
        acc -> Map.update(acc, {contract, kind, name}, [module], &Enum.sort([module | &1]))
      end

    %{declarations: declarations}
  end
end
