defmodule EhosContract.DispatchRecordQueryTest do
  @moduledoc """
  The two other ways into a v2 contract (v2 §11): recording an event nobody
  commands (D6), and asking a query, narrowed to the rows a credential grants
  (D10, D14).
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.OpenAccount
  alias DispatchRig.Ledger.Events.{BalanceConfirmed, InterestRecorded}
  alias DispatchRig.Ledger.Queries.BalancesForBranch
  alias DispatchRig.Ledger.ReadModels.Balances.Row
  alias EhosContract.{Actor, Authorizer, CommandRecord, Event}

  @query "dispatch_rig.balances_for_branch"

  defp clerk(branches) do
    Actor.credential("u-1", ["dispatch_rig.open_account", @query], %{
      @query => %{"branch_id" => branches}
    })
  end

  defp log, do: Repo.all(from(e in Event, order_by: e.position))
  defp rows, do: Repo.all(from(c in CommandRecord, order_by: c.recorded_at))

  defp ask(branch, actor),
    do: EhosContract.query(Ledger, %BalancesForBranch{branch_id: branch}, actor: actor)

  setup do
    for {account, branch} <- [{"a-1", "b-7"}, {"a-2", "b-7"}, {"a-3", "b-9"}] do
      {:ok, _} =
        EhosContract.dispatch(Ledger, %OpenAccount{account_id: account, branch_id: branch},
          actor: clerk(["b-7"])
        )
    end

    :ok
  end

  describe "record/3" do
    test "a :system actor the event names records it into the unit's stream, and it is projected" do
      assert {:ok, receipt} =
               EhosContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 5},
                 actor: Actor.system(:nightly_import),
                 idempotency_key: "interest:a-1:2026-09"
               )

      event = List.last(log())
      assert event.type == "dispatch_rig.ledger.interest_recorded"
      assert {event.stream_id, event.stream_version} == {"account:a-1", 2}
      assert event.actor == "system:nightly_import"
      assert receipt.positions == [event.position]
      assert %{outcome: "accepted", type: "record:interest_recorded"} = List.last(rows())

      assert Repo.one(
               from(b in "dispatch_rig_balances", where: b.account_id == "a-1", select: b.balance)
             ) ==
               5

      # Recorded twice under one key, appended once.
      assert {:ok, %{duplicate: true}} =
               EhosContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 5},
                 actor: Actor.system(:nightly_import),
                 idempotency_key: "interest:a-1:2026-09"
               )

      assert length(log()) == 4
    end

    test "a credential records a person's observation with the event's capability, and not without it" do
      assert EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"},
               actor: clerk(["b-7"])
             ) ==
               {:error, :missing_capability}

      assert length(log()) == 3

      # The control: the auditor's credential, granted the recording by name.
      auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

      assert {:ok, _} =
               EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"}, actor: auditor)

      assert %{type: "dispatch_rig.ledger.balance_confirmed", actor: "actor:u-2"} =
               List.last(log())

      assert %{outcome: "accepted", type: "record:balance_confirmed"} = List.last(rows())
    end

    test "what only the application's own code does is granted to no credential, whatever it carries" do
      # `interest_recorded` is only the nightly import's to record, and `flag_account`
      # only a reaction's to issue: neither has a capability, so a credential that
      # names them anyway — a grant made by mistake — is refused (plan, E9a review).
      mistaken =
        Actor.credential("u-3", ["dispatch_rig.interest_recorded", "dispatch_rig.flag_account"])

      assert EhosContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 5},
               actor: mistaken
             ) == {:error, :missing_capability}

      assert EhosContract.dispatch(
               Ledger,
               %DispatchRig.Ledger.Commands.FlagAccount{account_id: "a-1"},
               actor: mistaken
             ) == {:error, :missing_capability}

      assert length(log()) == 3
    end

    test "a :system actor the event does not name, or a person's name, is refused" do
      assert EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"},
               actor: Actor.system(:nightly_import)
             ) == {:error, :not_declared}

      assert EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"},
               actor: Actor.system(:auditor)
             ) == {:error, :not_declared}
    end

    # Issue #430's review: a recording's scenario judges a person apart from the
    # authorizer, and nothing a host passes as `actor:` reaches that path.
    test "an actor that is no EhosContract.Actor is refused before anything is checked" do
      for actor <- [:person, nil] do
        assert_raise ArgumentError, ~r/takes `actor:`, an EhosContract.Actor/, fn ->
          EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"}, actor: actor)
        end
      end

      assert length(log()) == 3
    end

    test "an event a command emits is not recorded" do
      assert_raise ArgumentError, ~r/only an event declaring recorded_by: is recorded/, fn ->
        EhosContract.record(
          Ledger,
          %DispatchRig.Ledger.Events.Deposited{account_id: "a-1", amount: 1},
          actor: Actor.system(:nightly_import)
        )
      end
    end
  end

  describe "query/3" do
    test "a value within the grant is answered with that branch's rows" do
      assert {:ok, rows} = ask("b-7", clerk(["b-7", "b-9"]))
      assert rows |> Enum.map(& &1.account_id) |> Enum.sort() == ["a-1", "a-2"]
      assert Enum.all?(rows, &match?(%Row{branch_id: "b-7"}, &1))
    end

    test "a value outside the grant is refused before the implementation runs" do
      assert ask("b-9", clerk(["b-7"])) == {:error, :outside_scope}
      refute_received :dispatch_rig_asked

      # Control: within the grant, it runs.
      assert {:ok, _} = ask("b-7", clerk(["b-7"]))
      assert_received :dispatch_rig_asked
    end

    test "a scope parameter that does not fit its type is asked with no value, and refused" do
      assert ask(%{"not" => "a branch"}, clerk(["b-7"])) == {:error, :outside_scope}
    end

    test "a scoped capability granted with no values is refused: fail closed" do
      assert ask("b-7", clerk([])) == {:error, :unscoped_grant}

      no_entry = Actor.credential("u-1", [@query])
      assert ask("b-7", no_entry) == {:error, :unscoped_grant}
    end

    test "an implementation that answers another branch's row is stopped" do
      Process.put(:dispatch_rig_leak, true)

      assert_raise Authorizer.OutsideScopeError, ~r/no row was returned/, fn ->
        ask("b-7", clerk(["b-7"]))
      end
    end

    test "control: the same leaking implementation passes when every row is granted" do
      Process.put(:dispatch_rig_leak, true)
      assert {:ok, rows} = ask("b-7", clerk(["b-7", "b-9"]))
      assert length(rows) == 3
    end

    test "a query returning one answers a row or nil, and a list raises" do
      auditor = Actor.credential("u-9", ["dispatch_rig.balance_of"])

      ask_one =
        &EhosContract.query(Ledger, %DispatchRig.Ledger.Queries.BalanceOf{account_id: &1},
          actor: auditor
        )

      assert {:ok, %Row{account_id: "a-1"}} = ask_one.("a-1")
      assert {:ok, nil} = ask_one.("a-404")

      Process.put(:dispatch_rig_as_list, true)
      assert_raise ArgumentError, ~r/it answers one/, fn -> ask_one.("a-1") end
    end

    test "the application's own :system actor is not narrowed, and a query writes nothing" do
      Process.put(:dispatch_rig_leak, true)
      before = {length(log()), length(rows())}

      assert {:ok, rows} = ask("b-7", Actor.system(:nightly_import))
      assert length(rows) == 3
      assert {length(log()), length(rows())} == before
    end
  end
end
