defmodule EhOsContract.ReactionsTest do
  @moduledoc """
  Plan DD, C1 (#304): one list of the commands reactions issue, read the same off a
  contract's model and off its DSL declarations, which the compile-time rules see.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.{Model, Reactions}
  alias EhOsContract.Contract.Rules

  @ledger DispatchRig.Ledger

  defp listed(issued),
    do: Enum.map(issued, &{&1.kind, &1.reaction.name, &1.trigger, &1.on, &1.command})

  test "every way a reaction issues, a timer's included, in declaration order" do
    assert @ledger |> Model.fetch() |> Reactions.issued() |> listed() == [
             {:policy, :flag_large_deposit, :handles, :deposited, :flag_account},
             {:policy, :echo_deposit, :handles, :deposited, :deposit},
             {:policy, :flag_large_withdrawal, :handles, :withdrawn, :flag_account},
             {:policy, :return_small_change, :handles, :withdrawn, :deposit},
             {:process_manager, :first_deposit_chase, :on, :interest_recorded, :flag_account},
             {:process_manager, :first_deposit_chase, :timer, :first_deposit_due, :flag_account},
             {:process_manager, :first_deposit_chase, :timer, :review, :flag_account}
           ]
  end

  test "an issuance carries the declaration it issues through: a timer's, for a timer" do
    issued = @ledger |> Model.fetch() |> Reactions.issued()

    assert [%{label: "First deposit due"}, %{label: "Review"}] =
             for(%{trigger: :timer, way: way} <- issued, do: way)

    assert Enum.all?(issued, &(&1.trigger != :handles or &1.way == nil))
  end

  test "whether a reaction issues a command is what its list says, for every command" do
    model = Model.fetch(@ledger)

    for {kind, reactions} <- [policy: model.policies, process_manager: model.process_managers],
        reaction <- reactions,
        command <- Enum.map(model.commands, & &1.name) do
      listed? = Enum.any?(Reactions.issued_by(kind, reaction), &(&1.command == command))

      assert Reactions.issues?(kind, reaction, command) == listed?,
             inspect({reaction.name, command})
    end

    # What P1 refuses, and dispatch would otherwise permit: a policy on no event.
    refute Reactions.issues?(:policy, %{handles: [], issues: [:deposit]}, :deposit)
  end

  test "what goes out when a timer fires: a timer's own, and an on naming one" do
    pm = %{
      starts_on: [%{event: :opened, issues: [:remind]}],
      on: [%{event: :later, issues: [:remind]}, %{event: :paid, issues: [:thank]}],
      timers: [%{name: :later, issues: [:chase]}]
    }

    assert pm
           |> then(&Reactions.issued_by(:process_manager, &1))
           |> Enum.map(&{&1.on, Reactions.timer?(&1)}) ==
             [opened: false, later: true, paid: false, later: true]
  end

  test "what one reaction issues, and what its callback of one name may issue, each once" do
    model = Model.fetch(@ledger)
    [pm] = model.process_managers
    policy = Enum.find(model.policies, &(&1.name == :echo_deposit))

    assert Reactions.commands(:process_manager, pm) == [:flag_account]
    assert Reactions.commands_on(:process_manager, pm, :review) == [:flag_account]
    assert Reactions.commands_on(:process_manager, pm, :deposited) == []
    assert Reactions.commands_on(:policy, policy, :deposited) == [:deposit]
    assert Reactions.commands_on(:policy, policy, :withdrawn) == []
  end

  # What `Consumer` reads directly on every event a policy takes.
  test "a policy's commands are its `issues:`, each once" do
    for policy <- Model.fetch(@ledger).policies,
        do: assert(Reactions.commands(:policy, policy) == Enum.uniq(List.wrap(policy.issues)))
  end

  test "the DSL's declarations give the same list as the model" do
    declarations = Rules.declarations(@ledger.spark_dsl_config())

    assert listed(Reactions.issued(declarations)) ==
             listed(Reactions.issued(Model.fetch(@ledger)))
  end
end
