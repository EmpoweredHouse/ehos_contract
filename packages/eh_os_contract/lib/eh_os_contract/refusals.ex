defmodule EhOsContract.Refusals do
  # What of a contract can say no (plan DD, L2 (#272)): the check's two rules about the
  # core and the unit pages' "Records only" read it the same way.
  #
  # A command refuses when its `rejects:` names an invariant; a lifecycle's
  # `or_rejects:` and `actor_is`'s are in it already. A unit records only when it has an
  # event and none of its commands refuses, a unit whose events are all `recorded_by:`
  # included; a unit with no event at all is `aggregate-without-events`'s. It is
  # derived, never declared, since a declared marker would make a unit without rules
  # legal by writing it down.
  #
  # Which commands a reaction issues is here too (plan DD, C1, #304), since a command only
  # a reaction issues is exempt from the core's rule. It is the one answer to that
  # question: the rules read it off the DSL's declarations at compile time, everything
  # else off the model, and both carry the keys it reads. Each caller filters it where it
  # reads it, and says why there.
  @moduledoc false

  @typedoc """
  One command a reaction issues, and what issues it: a policy on an event it handles
  (`:handles`), a process manager on an event that starts its run (`:starts_on`) or
  comes during it (`:on`, whose `on` may name one of its own timers), or one of its
  timers when it fires (`:timer`, `on` naming the timer). `reaction` is the policy or
  the process manager.
  """
  @type issuance :: %{
          command: atom(),
          kind: :policy | :process_manager,
          reaction: map(),
          trigger: :handles | :starts_on | :on | :timer,
          on: atom()
        }

  @doc "Whether `command`, of a contract's model, can be refused."
  @spec refuses?(map()) :: boolean()
  def refuses?(command), do: command.rejects != []

  @doc """
  Whether `unit`, of the contract `model`, has events and no command of it can be
  refused.
  """
  @spec records_only?(map(), map()) :: boolean()
  def records_only?(model, unit) do
    Enum.any?(model.events, &(&1.unit == unit.name)) and
      not Enum.any?(model.commands, &(&1.unit == unit.name and refuses?(&1)))
  end

  @doc """
  Every command a reaction of `contract` issues, with what issues it, in declaration
  order: each policy, then each process manager's starts, its events and its timers.
  `contract` is a contract's model, or its DSL declarations, which have the same
  `:policies` and `:process_managers`. A command issued in two ways is listed twice.
  """
  @spec issued_by_reactions(%{
          :policies => [map()],
          :process_managers => [map()],
          optional(atom()) => term()
        }) :: [issuance()]
  def issued_by_reactions(contract) do
    Enum.flat_map(contract.policies, &issued_by(:policy, &1)) ++
      Enum.flat_map(contract.process_managers, &issued_by(:process_manager, &1))
  end

  @doc """
  What one reaction, a policy or a process manager, issues, as `issued_by_reactions/1`
  lists it. A policy issues on each event it handles, so one that handles none issues
  nothing.
  """
  @spec issued_by(:policy | :process_manager, map()) :: [issuance()]
  def issued_by(:policy, policy) do
    for event <- List.wrap(policy.handles), command <- List.wrap(policy.issues) do
      %{command: command, kind: :policy, reaction: policy, trigger: :handles, on: event}
    end
  end

  def issued_by(:process_manager, pm) do
    ways =
      for(s <- pm.starts_on, do: {:starts_on, s.event, s.issues}) ++
        for(o <- pm.on, do: {:on, o.event, o.issues}) ++
        for t <- pm.timers, do: {:timer, t.name, t.issues}

    for {trigger, on, issues} <- ways, command <- List.wrap(issues) do
      %{command: command, kind: :process_manager, reaction: pm, trigger: trigger, on: on}
    end
  end
end
