defmodule EhOsContract.Auth.Choice do
  # Issues #475 and #477: who answers where EHOS may not, chosen the same way for the people,
  # grants and mail, so the three cannot drift apart.
  @moduledoc false

  @typedoc false
  @type spec :: %{
          key: atom(),
          behaviour: module(),
          callbacks: [{atom(), arity()}],
          ehos?: boolean(),
          ehos: module(),
          unconfigured: module(),
          stand_ins: [module()],
          configured: String.t()
        }

  @doc false
  # The module `config :eh_os_contract_auth, <key>:` names, checked to implement `behaviour`;
  # with none, EHOS's where its credentials are configured and `unconfigured` where they are not.
  # Raises for a stand-in where EHOS's credentials are configured: a release answering for EHOS.
  @spec choose!(spec()) :: module()
  def choose!(%{key: key, ehos?: ehos?} = spec) do
    module =
      case Application.get_env(:eh_os_contract_auth, key) do
        nil -> if ehos?, do: spec.ehos, else: spec.unconfigured
        module when is_atom(module) and module not in [true, false] -> implements!(module, spec)
        other -> raise ArgumentError, "#{config(key)} takes a module, not #{inspect(other)}"
      end

    if ehos? and module in spec.stand_ins do
      raise ArgumentError,
            "#{config(key)} names #{inspect(module)}, a stand-in for development or tests, " <>
              "where #{spec.configured} is configured too"
    end

    module
  end

  @doc false
  # Whether the workload's credential is configured, which reading the people and sending mail
  # share; `people:` is its older name.
  @spec workload?() :: boolean()
  def workload? do
    Application.get_env(:eh_os_contract_auth, :workload) != nil or
      Application.get_env(:eh_os_contract_auth, :people) != nil
  end

  defp implements!(module, %{key: key, behaviour: behaviour, callbacks: callbacks}) do
    if Code.ensure_loaded?(module) and
         Enum.all?(callbacks, fn {name, arity} -> function_exported?(module, name, arity) end),
       do: module,
       else:
         raise(
           ArgumentError,
           "#{config(key)} names #{inspect(module)}, which does not implement #{inspect(behaviour)}"
         )
  end

  defp config(key), do: "config :eh_os_contract_auth, #{key}:"
end
