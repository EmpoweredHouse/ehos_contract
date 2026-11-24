defmodule EhosContract.Refusals do
  # What of a contract can say no (plan DD, L2 (#272)): the check's two rules about the
  # core and the unit pages' "Records only" read it the same way.
  #
  # A command refuses when its `rejects:` names an invariant; a lifecycle's
  # `or_rejects:` and `actor_is`'s are in it already. A unit records only when it has an
  # event and none of its commands refuses, a unit whose events are all `recorded_by:`
  # included; a unit with no event at all is `aggregate-without-events`'s. It is
  # derived, never declared, since a declared marker would make a unit without rules
  # legal by writing it down.
  @moduledoc false

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
end
