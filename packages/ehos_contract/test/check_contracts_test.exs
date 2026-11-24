defmodule EhosContract.CheckContractsTest do
  @moduledoc """
  Plan EL1: **the rules v1 contracts had, over v2 contracts**, and one only an
  implementation answers — a reaction back into an earlier stage of a process module,
  two reactions in
  one transaction, free text left unsealed, an event a command declares and never
  emits; and plan DD, X1: a reaction to another context's event in its transaction. Each finding points at its declaration, with a control beside it.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Contracts, Finding}

  @visits EhosContract.CheckContractsTest.Visits
  @decider EhosContract.CheckContractsTest.Visit
  @run EhosContract.CheckContractsTest.VisitRun

  setup_all do
    compile(
      """
      defmodule #{inspect(@visits)} do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.#{contract_name(@visits)}"

        aggregate :visit, "Visit" do
          identity :visit_id

          command :book, "Book", by: :reception, emits: :booked do
            field :note, :string
          end

          command :arrive, "Arrive", by: :reception, emits: [:arrived, :no_show]
          command :reopen, "Reopen", by: :reception, emits: :reopened

          event :booked, "Booked" do
            field :note, :string
          end

          event :reopened, "Reopened" do
            field :attempt, :integer
          end

          event :arrived, "Arrived"
          event :no_show, "Did not arrive"
        end

        policy :greet, "Greeting", handles: :booked, issues: :arrive
        policy :reopen_after_arrival, "Reopening", handles: :arrived, issues: :reopen
        effect :log_booking, "Log", handles: :booked, delivery: :in_transaction
      end

      defmodule #{inspect(@run)} do
        use EhosContract.Process, id: "clinic.visit_run", domain: Clinic, label: "Visit"

        correlate :visit_id

        stage :booking, include: [{#{inspect(@visits)}, [:booked, :reopened]}]
        stage :arrival, include: [{#{inspect(@visits)}, [:arrived, :no_show]}]
      end

      defmodule #{inspect(@decider)} do
        use #{inspect(@visits)}, aggregate: :visit

        @impl true
        def book(%Book{visit_id: id, note: note}, _state), do: emit(%Booked{visit_id: id, note: note})

        @impl true
        def arrive(%Arrive{visit_id: id}, _state), do: emit(%Arrived{visit_id: id})

        @impl true
        def reopen(%Reopen{visit_id: id}, _state), do: reopened(id)

        defp reopened(id), do: emit(%Reopened{visit_id: id, attempt: 1})
      end
      """,
      "visits.ex"
    )

    :ok
  end

  defp findings(rule) do
    for %Finding{rule: ^rule} = f <- Contracts.findings([@visits], [@decider], [@run]),
        do: {f.message, Finding.place(f)}
  end

  test "a reaction issuing into an earlier stage of a process; control: one issuing forward" do
    assert [{message, {"visits.ex", 27}}] = findings("backward-edge")

    assert message =~
             "policy :reopen_after_arrival of #{inspect(@visits)} reacts to :arrived in stage " <>
               ":arrival of #{inspect(@run)} and issues :reopen, whose :reopened is in the " <>
               "earlier stage :booking"
  end

  test "control: without a process that stages them, no reaction goes back" do
    assert for(
             f <- Contracts.findings([@visits], [@decider], []),
             f.rule == "backward-edge",
             do: f
           ) == []
  end

  test "a sibling's event a reaction consumes is found in the stage the process gives it" do
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Frontdesk do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.frontdesk"

        consumes #{inspect(@visits)}, :arrived, as: [arrived: :patient_here]

        aggregate :desk, "Front desk" do
          identity :visit_id
          command :check_in, "Check-in", emits: :checked_in
          event :checked_in, "Checked in"
        end

        policy :check_in_on_arrival, "Check in on arrival", handles: :patient_here, issues: :check_in
      end

      defmodule EhosContract.CheckContractsTest.FrontdeskRun do
        use EhosContract.Process, id: "clinic.frontdesk_run", domain: Clinic, label: "Front desk"

        correlate :visit_id

        stage :desk, include: [{EhosContract.CheckContractsTest.Frontdesk, [:checked_in]}]
        stage :arrival, include: [{#{inspect(@visits)}, [:arrived]}]
      end
      """,
      "frontdesk.ex"
    )

    desk = EhosContract.CheckContractsTest.Frontdesk
    run = EhosContract.CheckContractsTest.FrontdeskRun

    assert [%Finding{message: message} = finding] =
             for(f <- Contracts.findings([desk], [], [run]), f.rule == "backward-edge", do: f)

    assert message =~
             "policy :check_in_on_arrival of #{inspect(desk)} reacts to :patient_here in stage " <>
               ":arrival of #{inspect(run)} and issues :check_in, whose :checked_in is in the " <>
               "earlier stage :desk"

    assert Finding.place(finding) == {"frontdesk.ex", 12}
  end

  test "two reactions in the transaction recording one event; control: an event with one" do
    # At the first of them, as they are listed.
    assert [{message, {"visits.ex", 28}}] = findings("competing-in-transaction-consumers")

    assert message =~
             ":booked of #{inspect(@visits)} has 2 reactions inside the transaction that " <>
               "records it — effect :log_booking of #{inspect(@visits)}, policy :greet of"
  end

  test "free text in an event, not personal; control: a number, and a command's field" do
    assert [{message, {"visits.ex", 15}}] = findings("free-text-not-personal")
    assert message =~ ":booked.note of #{inspect(@visits)} is free text and not `personal:`"
  end

  test "an event a command declares and no emit/1 names; control: one emitted in a helper" do
    assert [{message, {"visits.ex", 11}}] = findings("emits-never-produced")

    assert message =~
             "command :arrive of #{inspect(@visits)} may emit :no_show, and no emit/1 in " <>
               "#{inspect(@decider)} names it"
  end

  test "control: a contract nothing implements has no finding about what it emits" do
    assert for(f <- Contracts.findings([@visits], []), f.rule == "emits-never-produced", do: f) ==
             []
  end

  test "a reaction to an event of a contract nobody compiled is left to X5, and check goes on" do
    # A project without the compiler: the consumed contract does not exist, and every
    # finding is built before any is printed, so a raise here would hide X5 as well.
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Orphaned do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.orphaned"

        consumes EhosContract.CheckContractsTest.Nowhere, :arrived

        aggregate :desk, "Front desk" do
          identity :visit_id
          command :greet, "Greet", by: :reception, emits: :greeted
          event :greeted, "Greeted"
        end

        policy :greet_on_arrival, "Greeting", handles: :arrived, issues: :greet
        policy :count_arrival, "Counting", handles: :arrived, issues: :greet
      end
      """,
      "orphaned.ex"
    )

    assert for(
             f <- Contracts.findings([EhosContract.CheckContractsTest.Orphaned], []),
             f.rule == "competing-in-transaction-consumers",
             do: f
           ) == []
  end

  test "free text in a list, behind a value and in a value's field; control: a code and its alias" do
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Notes do
        use EhosContract.Domain, name: :notes, language: :en

        context :desk, "Front desk", subdomain: :core
        actor :reception, :human, "Front desk"
        value :remark, :string
        value :again, :remark

        value :nip, :string, code: true do
          invariant :ten_digits, "Ten digits", violated_by: ["1"], satisfied_by: ["1234567890"]
        end

        value :office_nip, :nip

        value :contact do
          field :note, :string
          field :floor, :integer
        end

        subdomain :core, "Core", type: :core
      end

      defmodule EhosContract.CheckContractsTest.Desk do
        use EhosContract.Contract, domain: EhosContract.CheckContractsTest.Notes, context: :desk, id: "notes.desk"

        aggregate :desk, "Front desk" do
          identity :visit_id
          command :note, "Note", by: :reception, emits: :noted

          event :noted, "Noted" do
            field :lines, {:list, :string}
            field :remark, :again
            field :contact, :contact
            field :count, :integer
            field :nip, :nip
            field :office_nip, :office_nip
            field :nips, {:list, :nip}
          end
        end
      end
      """,
      "notes.ex"
    )

    assert Contracts.findings([EhosContract.CheckContractsTest.Desk], [])
           |> Enum.filter(&(&1.rule == "free-text-not-personal"))
           |> Enum.map(&(&1.message |> String.split(" of ") |> hd())) ==
             [":noted.lines", ":noted.remark", ":noted.contact.note"]
  end

  test "reactions of two contracts to one event compete in one transaction" do
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Reception do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.reception"

        consumes #{inspect(@visits)}, :booked, as: [booked: :visit_booked]

        aggregate :desk, "Front desk" do
          identity :visit_id
          command :prepare, "Prepare", by: :reception, emits: :prepared
          event :prepared, "Prepared"
        end

        policy :prepare_desk, "Preparation", handles: :visit_booked, issues: :prepare
      end
      """,
      "reception.ex"
    )

    assert [%Finding{message: message}] =
             Contracts.findings([@visits, EhosContract.CheckContractsTest.Reception], [@decider])
             |> Enum.filter(&(&1.rule == "competing-in-transaction-consumers"))

    assert message =~ ":booked of #{inspect(@visits)} has 3 reactions"
    assert message =~ "policy :prepare_desk of EhosContract.CheckContractsTest.Reception"
  end

  test "reactions declared :in_transaction on another context's event; control: :at_least_once" do
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Billing do
        use EhosContract.Contract, domain: Clinic, context: :billing, id: "clinic.billing"

        consumes #{inspect(@visits)}, :booked

        aggregate :bill, "Bill" do
          identity :visit_id
          command :open_bill, "Open a bill", by: :reception, emits: :bill_opened
          event :bill_opened, "Bill opened"
        end

        policy :bill_on_booking, "Booked — a bill", handles: :booked, issues: :open_bill,
          delivery: :in_transaction
        policy :bill_later, "Booked — a bill later", handles: :booked, issues: :open_bill,
          delivery: :at_least_once, idempotency: [key: :event_id, owner: :infrastructure]
        effect :note_booking, "Log", handles: :booked, delivery: :in_transaction

        read_model :booked, "Booked", projects: :booked, delivery: :in_transaction do
          field :visit_id, :id
        end
      end
      """,
      "billing.ex"
    )

    found =
      for %Finding{rule: "in-transaction-across-contexts"} = f <-
            Contracts.findings([@visits, EhosContract.CheckContractsTest.Billing], [@decider]),
          do: {f.message |> String.split(" of ") |> hd(), Finding.place(f)}

    assert found == [
             {"policy :bill_on_booking", {"billing.ex", 12}},
             {"effect :note_booking", {"billing.ex", 16}},
             {"read model :booked", {"billing.ex", 18}}
           ]

    [policy, _effect, read_model] =
      for %Finding{rule: "in-transaction-across-contexts", message: m} <-
            Contracts.findings([EhosContract.CheckContractsTest.Billing], []),
          do: m

    assert policy =~
             "takes :booked of #{inspect(@visits)} (context :settlement) inside the transaction " <>
               "that records it, so context :billing commits with another"

    assert policy =~ "use `delivery: :at_least_once` with its `idempotency`"

    # A read model takes no `idempotency`, so the advice does not ask for one.
    assert read_model =~ ~r/use `delivery: :at_least_once`$/

    # The same reaction in the publisher's own context is not across anything.
    compile(
      """
      defmodule EhosContract.CheckContractsTest.Desk2 do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.desk2"

        consumes #{inspect(@visits)}, :booked

        aggregate :desk, "Front desk" do
          identity :visit_id
          command :prepare, "Prepare", by: :reception, emits: :prepared
          event :prepared, "Prepared"
        end

        policy :prepare_desk, "Preparation", handles: :booked, issues: :prepare,
          delivery: :in_transaction
      end
      """,
      "desk2.ex"
    )

    assert for(
             %Finding{rule: "in-transaction-across-contexts"} = f <-
               Contracts.findings([EhosContract.CheckContractsTest.Desk2], []),
             do: f
           ) == []
  end
end
