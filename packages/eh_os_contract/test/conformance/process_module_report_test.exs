defmodule EhOsContract.ProcessModuleReportTest do
  @moduledoc """
  Plan DD, P2d (#213): **a process module is shown where a contract's process is** — the
  report, the deployment record and the check. On the invented
  `DispatchRig.AccountReview`, which includes the ledger's withdrawals and balance
  confirmations, ends on a confirmation, is agreed to take two days and promises a
  confirmation within a day of a withdrawal.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.{AccountReview, Ledger}
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.BalanceConfirmed
  alias EhOsContract.Check.Completeness
  alias EhOsContract.{Actor, Conformance, Deployment, Model, Registry, Report}

  @clerk Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit
    dispatch_rig.withdraw))
  @auditor Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

  defp withdraw(account) do
    dispatch(%OpenAccount{account_id: account, branch_id: "b-7"})
    dispatch(%Deposit{account_id: account, amount: 100})
    dispatch(%Withdraw{account_id: account, amount: 50})
  end

  defp confirm(account) do
    {:ok, _} =
      EhOsContract.record(Ledger, %BalanceConfirmed{account_id: account}, actor: @auditor)
  end

  # Three days on: the review of a-1 ended within its two days and its balance was
  # confirmed within the day; a-2's was never confirmed.
  defp later, do: DateTime.add(DateTime.utc_now(), 3, :day)

  describe "the registry" do
    test "finds the process module beside the contracts, and by its id" do
      assert AccountReview in Registry.processes()
      refute AccountReview in Registry.contracts()
      assert Registry.process("dispatch_rig.account_review") == AccountReview
      assert Registry.process("dispatch_rig") == nil
    end
  end

  describe "the model" do
    test "answers for the module's run as for a contract's process" do
      assert %{name: "dispatch_rig.account_review", correlate: [:account_id]} =
               Model.process(AccountReview)

      assert [
               %{type: "dispatch_rig.ledger.withdrawn", stage: :withdrawal, terminal: false},
               %{
                 type: "dispatch_rig.ledger.balance_confirmed",
                 stage: :confirmation,
                 terminal: true
               }
             ] = Model.process_events(AccountReview)

      assert {Ledger, %{name: :withdrawn}} = Model.declaring(AccountReview, :withdrawn)
      assert Model.declaring(AccountReview, :deposited) == nil
    end
  end

  describe "the report" do
    setup do
      withdraw("a-1")
      confirm("a-1")
      withdraw("a-2")
      :ok = Deployment.record!(~U[2026-10-01 00:00:00.000000Z])
      :ok
    end

    test "shows the module's runs, its duration against the deadline and its promise" do
      report = Conformance.report(AccountReview, now: later())

      assert %{process: "dispatch_rig.account_review", module: AccountReview} = report

      assert [
               %{
                 process: "dispatch_rig.account_review",
                 label: "Account review",
                 accountable: "Auditor",
                 runs: 2,
                 declarations: [%{key: :deadline, value: {2, :day}}],
                 duration: %{runs: 2, within: 1, overdue: 1, deadline: {2, :day}},
                 promises: [
                   %{
                     promise: :balance_confirmed_after_withdrawal,
                     from_label: "Withdrawn",
                     eventually_label: "Balance confirmed",
                     satisfied: 1,
                     violated: 1
                   }
                 ]
               }
             ] = report.processes

      assert %{
               process: "dispatch_rig.account_review",
               deployed: %{since: ~U[2026-10-01 00:00:00.000000Z]}
             } = report.deployment

      text = Report.render(report)

      assert text =~ "PROCESS MODULE: dispatch_rig.account_review"
      assert text =~ "deployed since 2026-10-01"
      assert text =~ "PROCESS: Account review"
      assert text =~ "Runs in this period: 2."
      assert text =~ "Deadline: 2 days from the start."
      assert text =~ "1 run still open and already past it."
      assert text =~ "BREACHED in 1 of 2 runs."
      refute text =~ "STEPS"
    end

    test "leaves a contract's report as it was" do
      report = Conformance.report(Ledger, now: later())

      assert %{contract: "dispatch_rig.ledger"} = report
      assert [%{process: :ledger}] = report.processes
    end

    test "is not on the conformance wire" do
      assert_raise ArgumentError, ~r/process module/, fn -> Conformance.as_data(AccountReview) end
    end
  end

  describe "the deployment record" do
    test "has a row for the module, under its id apart from the contracts'" do
      :ok = Deployment.record!(~U[2026-10-01 00:00:00.000000Z])
      model = Model.fetch(AccountReview)

      assert [row] = Deployment.all(AccountReview)
      assert row.contract == "process:dispatch_rig.account_review"
      assert row.contract_version == model.version
      assert row.events == ["balance_confirmed", "withdrawn"]
      assert row.edges == []

      assert Map.has_key?(row.declaration_digests, "promise:balance_confirmed_after_withdrawal")

      # Booting the same code again leaves one row.
      :ok = Deployment.record!(~U[2026-10-02 00:00:00.000000Z])
      assert [_one] = Deployment.all(AccountReview)
    end
  end

  describe "the check" do
    defp unread(processes) do
      for %{rule: "event-without-consumer", message: message} <-
            Completeness.findings([Ledger], processes),
          do: message
    end

    test "counts an event a process module includes as read" do
      assert Enum.any?(unread([]), &(&1 =~ "event :balance_confirmed of DispatchRig.Ledger"))
      refute Enum.any?(unread([AccountReview]), &(&1 =~ ":balance_confirmed"))
    end

    test "applies the process rules to a process module" do
      assert EhOsContract.Check.process_module_findings([AccountReview]) == []

      %{module: unowned} =
        EhOsContract.DslCase.compile_process(
          "UnownedReview",
          """
            correlate :account_id
            stage :withdrawal, include: [{DispatchRig.Ledger, :withdrawn}]
            stage :confirmation, include: [{DispatchRig.Ledger, :balance_confirmed}]
            ends_on :balance_confirmed
            deadline {2, :day}, unverified: true

            promise :confirmed do
              from :withdrawn
              eventually :balance_confirmed
              unverified true
            end
          """,
          id: "dispatch_rig.unowned_review",
          domain: DispatchRig.Domain
        )

      assert unowned
             |> List.wrap()
             |> EhOsContract.Check.process_module_findings()
             |> Enum.map(& &1.rule)
             |> Enum.sort() == [
               "process-without-accountable",
               "promise-without-within",
               "unverified-declaration",
               "unverified-declaration"
             ]
    end
  end
end
