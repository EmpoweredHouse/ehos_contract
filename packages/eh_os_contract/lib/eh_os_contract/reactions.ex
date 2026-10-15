defmodule EhOsContract.Reactions do
  # Which commands a contract's reactions issue (plan DD, C1, #304): the one answer to
  # that question. The rules read it off the DSL's declarations at compile time,
  # everything else off the model, and both carry the keys it reads. Each caller filters
  # it where it reads it, and says why there.
  @moduledoc false

  @typedoc """
  One command a reaction issues, and what issues it: a policy on an event it handles
  (`:handles`), a process manager on an event that starts its run (`:starts_on`) or
  comes during it (`:on`, whose `on` may name one of its own timers), or one of its
  timers when it fires (`:timer`, `on` naming the timer). `reaction` is the policy or
  the process manager, and `way` the `starts_on`, `on` or `timer` declaration it issues
  through, `nil` for a policy.
  """
  @type issuance :: %{
          command: atom(),
          kind: :policy | :process_manager,
          reaction: map(),
          trigger: :handles | :starts_on | :on | :timer,
          on: atom(),
          way: map() | nil
        }

  @doc """
  Every command a reaction of `contract` issues, with what issues it, in declaration
  order: each policy, then each process manager's starts, its events and its timers.
  `contract` is a contract's model, or its DSL declarations, which have the same
  `:policies` and `:process_managers`. A command issued in two ways is listed twice.
  """
  @spec issued(%{
          :policies => [map()],
          :process_managers => [map()],
          optional(atom()) => term()
        }) :: [issuance()]
  def issued(contract) do
    Enum.flat_map(contract.policies, &issued_by(:policy, &1)) ++
      Enum.flat_map(contract.process_managers, &issued_by(:process_manager, &1))
  end

  @doc """
  What one reaction, a policy or a process manager, issues, as `issued/1` lists it. A
  policy issues on each event it handles.
  """
  @spec issued_by(:policy | :process_manager, map()) :: [issuance()]
  def issued_by(:policy, policy) do
    for event <- List.wrap(policy.handles), command <- List.wrap(policy.issues) do
      %{
        command: command,
        kind: :policy,
        reaction: policy,
        trigger: :handles,
        on: event,
        way: nil
      }
    end
  end

  def issued_by(:process_manager, pm) do
    for {trigger, on, way} <- ways(pm), command <- List.wrap(way.issues) do
      %{
        command: command,
        kind: :process_manager,
        reaction: pm,
        trigger: trigger,
        on: on,
        way: way
      }
    end
  end

  @doc """
  The commands one reaction issues, each once, in the order `issued_by/2` first lists
  them.
  """
  @spec commands(:policy | :process_manager, map()) :: [atom()]
  def commands(kind, reaction),
    do: for(%{command: c} <- issued_by(kind, reaction), uniq: true, do: c)

  @doc """
  The commands one reaction issues on `on`, each once: a policy's, on an event it
  handles; a process manager's, through the ways in on that event, or that timer's
  firing — what the callback of that name may issue.
  """
  @spec commands_on(:policy | :process_manager, map(), atom()) :: [atom()]
  def commands_on(kind, reaction, on),
    do: for(%{command: c, on: ^on} <- issued_by(kind, reaction), uniq: true, do: c)

  @doc """
  Whether the one reaction, a policy or a process manager, issues `command`, as
  `issued_by/2` would list it, without building the list: what dispatch asks of every
  command a reaction sends.
  """
  @spec issues?(:policy | :process_manager, map(), atom()) :: boolean()
  def issues?(:policy, policy, command),
    do: List.wrap(policy.handles) != [] and command in List.wrap(policy.issues)

  def issues?(:process_manager, pm, command),
    do: Enum.any?(ways(pm), fn {_trigger, _on, way} -> command in List.wrap(way.issues) end)

  @doc """
  Whether `issuance` goes out when a timer fires rather than on an event: a timer's own
  (`:timer`), or an `on` that names one of the process manager's timers.
  """
  @spec timer?(issuance()) :: boolean()
  def timer?(%{trigger: :timer}), do: true

  def timer?(%{trigger: :on, on: on, reaction: pm}),
    do: Enum.any?(pm.timers, &(&1.name == on))

  def timer?(_issuance), do: false

  # A process manager's ways in, in declaration order: its starts, its events, its timers.
  defp ways(pm) do
    for(s <- pm.starts_on, do: {:starts_on, s.event, s}) ++
      for(o <- pm.on, do: {:on, o.event, o}) ++
      for t <- pm.timers, do: {:timer, t.name, t}
  end
end
