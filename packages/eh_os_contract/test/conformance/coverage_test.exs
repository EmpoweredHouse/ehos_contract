defmodule EhOsContract.CoverageTest do
  @moduledoc """
  Scenario coverage (v2 §13, plan E7c-2): which of a contract's command scenarios
  the log saw happen, by type only, and which decisions no scenario declares.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhOsContract.{Actor, Conformance, Coverage, Report}

  @clerk Actor.credential("u-1", [
           "dispatch_rig.open_account",
           "dispatch_rig.deposit",
           "dispatch_rig.withdraw"
         ])

  @refused "a withdrawal beyond the balance is refused"
  @through "a withdrawal within the balance goes through"

  defp dispatch(command), do: EhOsContract.dispatch(Ledger, command, actor: @clerk)

  setup do
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    :ok
  end

  test "only a scenario a command triggers is counted; a query leaves no row" do
    assert %{declared: 2, observed: 0, never_observed: [@refused, @through]} = Coverage.of(Ledger)
  end

  test "a withdrawal within the balance, after a deposit, is the scenario that goes through" do
    {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 100})
    {:ok, _} = dispatch(%Withdraw{account_id: "a-1", amount: 60})

    assert %{observed: 1, never_observed: [@refused]} = Coverage.of(Ledger)
  end

  test "a refusal on the scenario's invariant is the scenario that refuses" do
    {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 100})
    {:error, _} = dispatch(%Withdraw{account_id: "a-1", amount: 150})

    assert %{observed: 1, never_observed: [@through]} = Coverage.of(Ledger)
  end

  test "control: without the scenario's given types in the stream, it is not the scenario" do
    # Refused on the invariant, but nothing was deposited: the scenario says after a deposit.
    {:error, _} = dispatch(%Withdraw{account_id: "a-1", amount: 150})

    assert %{observed: 0} = Coverage.of(Ledger)
  end

  # A boundary reads only what its `evolve/2` folds, so its command's `given_types` lack
  # the rest, and a scenario's `given` is compared on the folded types alone (plan
  # E11f-5). No boundary of the rigs passes an event over, so this uses an aggregate's
  # folds: `DispatchRig.Account` passes `account_opened` over, and the row is written as
  # a boundary's would be, with the deposit alone. The scenario giving both still counts.
  test "a scenario's given counts only the types its unit's evolve/2 folds" do
    model = EhOsContract.Model.fetch(Ledger)

    scenarios =
      Enum.map(model.scenarios, fn
        %{description: @through, given: given} = scenario ->
          opened = %{hd(given) | event: :account_opened, data: %{}}
          %{scenario | given: [opened | given]}

        scenario ->
          scenario
      end)

    Repo.insert!(%EhOsContract.CommandRecord{
      id: Ecto.UUID.generate(),
      contract: EhOsContract.Model.fetch(Ledger).id,
      type: "withdraw",
      issued_by: "actor:u-1",
      correlation_id: Ecto.UUID.generate(),
      outcome: "accepted",
      given_types: ["dispatch_rig.ledger.deposited"],
      emitted_types: ["dispatch_rig.ledger.withdrawn"]
    })

    assert %{observed: 1, never_observed: [@refused]} =
             Coverage.of(%{model | scenarios: scenarios})
  end

  test "a decision no scenario of its command declares is an outcome to ask about" do
    assert [%{command: %{name: :open_account}, emitted: ["Account opened"], rejected: nil}] =
             Coverage.of(Ledger).undeclared_outcomes
  end

  test "the report says it in sentences" do
    t = Report.render(Conformance.report(Ledger))

    assert t =~ "SCENARIOS\n  Scenarios: 0 of 2 observed in this period."
    assert t =~ ~s(    · "#{@refused}")
    assert t =~ "  Outcomes no scenario declares:\n    · Open an account → Account opened"
  end

  test "on the wire" do
    wire = Conformance.as_data(Ledger)["report"]
    assert %{"declared" => 2, "observed" => 0} = wire["scenarios"]
    assert Map.has_key?(wire["wiring"], "version")
  end
end
