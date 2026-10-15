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

  test "the DSL's declarations give the same list as the model" do
    declarations = Rules.declarations(@ledger.spark_dsl_config())

    assert listed(Reactions.issued(declarations)) ==
             listed(Reactions.issued(Model.fetch(@ledger)))
  end
end
