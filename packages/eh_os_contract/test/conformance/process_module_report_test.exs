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

  describe "what a module includes" do
    test "is one rule: an include of another domain's contract counts nowhere" do
      review = AccountReview.__eh_os_contract_model__()
      elsewhere = %{review | domain: Elsewhere.Domain}

      assert [_, _] = Model.process_events(review)
      assert Model.process_events(elsewhere) == []
      assert EhOsContract.Implementations.runs_of([], [elsewhere]) == %{}

      types = review |> Model.process_events() |> Enum.map(& &1.type) |> Enum.sort()

      assert EhOsContract.Implementations.runs_of([], [review]) |> Map.keys() |> Enum.sort() ==
               types
    end
  end

  describe "the deployment of a module's version" do
    @key "process:dispatch_rig.account_review"

    defp insert(version, wiring, at, digests \\ %{}, events \\ []) do
      Repo.insert!(%Deployment{
        contract: @key,
        contract_version: version,
        wiring_version: wiring,
        events: events,
        edges: [],
        declaration_digests: digests,
        first_seen_at: at
      })
    end

    test "is not recorded: the report says so" do
      report = Conformance.report(AccountReview, now: later())

      assert report.deployment.deployed.since == nil
      assert Report.render(report) =~ "not recorded as deployed"
    end

    test "is dated by the row recorded last for it, so a new wiring is the one shown" do
      version = Model.fetch(AccountReview).version
      insert(version, "wiring-old", ~U[2026-09-01 00:00:00.000000Z])
      insert("an-earlier-version", "wiring-b", ~U[2026-09-03 00:00:00.000000Z])
      insert(version, "wiring-new", ~U[2026-09-05 00:00:00.000000Z])

      assert %{wiring_version: "wiring-new", since: ~U[2026-09-05 00:00:00.000000Z]} =
               Deployment.report(AccountReview).deployed
    end

    test "a new wiring under the same version is no change of version" do
      version = Model.fetch(AccountReview).version
      insert(version, "wiring-old", ~U[2026-09-01 00:00:00.000000Z])
      insert(version, "wiring-new", ~U[2026-09-05 00:00:00.000000Z])

      report = Conformance.report(AccountReview, now: later())

      assert report.deployment.changed == nil
      refute Report.render(report) =~ "Since the previous version"
    end

    test "a new version shows what changed, and its promise's boundary" do
      :ok = Deployment.record!(~U[2026-10-01 00:00:00.000000Z])
      [current] = Deployment.all(AccountReview)
      promise = "promise:balance_confirmed_after_withdrawal"

      insert(
        "an-earlier-version",
        "wiring-old",
        ~U[2026-09-01 00:00:00.000000Z],
        Map.put(current.declaration_digests, promise, "aaaaaaaaaaaa"),
        ["withdrawn"]
      )

      assert Deployment.declaration_boundaries(AccountReview) == %{
               promise => ~U[2026-10-01 00:00:00.000000Z]
             }

      report = Conformance.report(AccountReview, now: later())

      assert %{events_added: ["balance_confirmed"], events_removed: []} =
               report.deployment.changed

      text = Report.render(report)
      assert text =~ "Since the previous version: events added 1, removed 0."
      assert text =~ "Declarations changed: 1 (#{promise})."
    end

    test "keeps its rows apart from a contract's that shares its id" do
      version = Model.fetch(AccountReview).version

      Repo.insert!(%Deployment{
        contract: "dispatch_rig.account_review",
        contract_version: version,
        wiring_version: "a-contract's-wiring",
        events: ["something"],
        edges: [],
        declaration_digests: %{},
        first_seen_at: ~U[2026-09-01 00:00:00.000000Z]
      })

      :ok = Deployment.record!(~U[2026-10-01 00:00:00.000000Z])

      assert [%{contract: @key, events: ["balance_confirmed", "withdrawn"]}] =
               Deployment.all(AccountReview)

      assert %{since: ~U[2026-10-01 00:00:00.000000Z]} =
               Deployment.report(AccountReview).deployed
    end
  end

  describe "mix eh_os_contract.report" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    test "lists the process module after the contracts" do
      ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.EhOsContract.Report.run([]) end)
      assert_received {:mix_shell, :info, [text]}

      {module_at, _} = :binary.match(text, "PROCESS MODULE: dispatch_rig.account_review")
      {last_contract_at, _} = text |> :binary.matches("CONTRACT: ") |> List.last()

      assert last_contract_at < module_at
    end
  end
end
