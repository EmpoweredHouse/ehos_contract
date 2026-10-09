defmodule EhOsContract.Refusals do
  # What of a contract can say no (plan DD, L2 (#272)): the check's two rules about the
  # core and the unit pages' "Records only" read it the same way.
  #
  # A command refuses when its `rejects:` names an invariant; a lifecycle's
  # `or_rejects:` and `actor_is`'s are in it already. A unit records only when none of
  # its commands refuses, a unit whose events are all `recorded_by:` included: it is
  # derived, never declared, since a declared marker would make a unit without rules
  # legal by writing it down.
  @moduledoc false

  @doc "Whether `command`, of a contract's model, can be refused."
  @spec refuses?(map()) :: boolean()
  def refuses?(command), do: command.rejects != []

  @doc "Whether no command of `unit`, of the contract `model`, can be refused."
  @spec records_only?(map(), map()) :: boolean()
  def records_only?(model, unit) do
    not Enum.any?(model.commands, &(&1.unit == unit.name and refuses?(&1)))
  end

  @doc """
  The commands of the contract `model` a reaction issues: a policy, or a process
  manager on its start, on an event or when a timer fires.
  """
  @spec issued_by_reactions(map()) :: MapSet.t(atom())
  def issued_by_reactions(model) do
    policies = Enum.flat_map(model.policies, &List.wrap(&1.issues))

    managers =
      Enum.flat_map(model.process_managers, fn pm ->
        Enum.flat_map(pm.starts_on ++ pm.on ++ pm.timers, &List.wrap(Map.get(&1, :issues, [])))
      end)

    MapSet.new(policies ++ managers)
  end
end
