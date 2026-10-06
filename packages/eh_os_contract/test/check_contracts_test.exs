defmodule EhOsContract.CheckContractsTest do
  @moduledoc """
  Plan EL1: **the rules v1 contracts had, over v2 contracts**, and one only an
  implementation answers — a reaction back into an earlier stage, two reactions in
  one transaction, free text left unsealed, an event a command declares and never
  emits; and plan DD, X1: a reaction to another context's event in its transaction. Each finding points at its declaration, with a control beside it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Contracts, Finding}

  @visits EhOsContract.CheckContractsTest.Visits
  @decider EhOsContract.CheckContractsTest.Visit

  setup_all do
    compile(
      """
      defmodule #{inspect(@visits)} do
        use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.#{contract_name(@visits)}"

        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :book, "Umów", by: :reception, emits: :booked do
            field :note, :string
          end

          command :arrive, "Przyjdź", by: :reception, emits: [:arrived, :no_show]
          command :reopen, "Otwórz", by: :reception, emits: :reopened

          stage :booking do
            event :booked, "Umówiono" do
              field :note, :string
            end

            event :reopened, "Otwarto ponownie" do
              field :attempt, :integer
            end
          end

          stage :arrival do
            event :arrived, "Przyszedł"
            event :no_show, "Nie przyszedł"
          end
        end

        policy :greet, "Powitanie", handles: :booked, issues: :arrive
        policy :reopen_after_arrival, "Ponowne otwarcie", handles: :arrived, issues: :reopen
        effect :log_booking, "Zapis", handles: :booked, delivery: :in_transaction

        process :visit, "Wizyta" do
          correlate :visit_id
          stage :booking
          stage :arrival
        end
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
    for %Finding{rule: ^rule} = f <- Contracts.findings([@visits], [@decider]),
        do: {f.message, Finding.place(f)}
  end

  test "a reaction issuing into an earlier stage; control: one issuing forward" do
    assert [{message, {"visits.ex", 31}}] = findings("backward-edge")

    assert message =~
             "policy :reopen_after_arrival of #{inspect(@visits)} reacts to :arrived in stage " <>
               ":arrival and issues :reopen, whose :reopened is in the earlier stage :booking"
  end

  test "two reactions in the transaction recording one event; control: an event with one" do
    # At the first of them, as they are listed.
    assert [{message, {"visits.ex", 32}}] = findings("competing-in-transaction-consumers")

    assert message =~
             ":booked of #{inspect(@visits)} has 2 reactions inside the transaction that " <>
               "records it — effect :log_booking of #{inspect(@visits)}, policy :greet of"
  end

  test "free text in an event, not personal; control: a number, and a command's field" do
    assert [{message, {"visits.ex", 16}}] = findings("free-text-not-personal")
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
      defmodule EhOsContract.CheckContractsTest.Orphaned do
        use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.orphaned"

        consumes EhOsContract.CheckContractsTest.Nowhere, :arrived

        aggregate :desk, "Recepcja" do
          identity :visit_id
          command :greet, "Powitaj", by: :reception, emits: :greeted
          event :greeted, "Powitano"
        end

        policy :greet_on_arrival, "Powitanie", handles: :arrived, issues: :greet
        policy :count_arrival, "Liczenie", handles: :arrived, issues: :greet
      end
      """,
      "orphaned.ex"
    )

    assert for(
             f <- Contracts.findings([EhOsContract.CheckContractsTest.Orphaned], []),
             f.rule == "competing-in-transaction-consumers",
             do: f
           ) == []
  end

  test "free text inside a list, a value that is text, and a value's field is free text too" do
    compile(
      """
      defmodule EhOsContract.CheckContractsTest.Notes do
        use EhOsContract.Domain, name: :notes, language: :pl

        context :desk, "Recepcja", subdomain: :core
        actor :reception, :human, "Recepcja"
        value :remark, :string
        value :again, :remark

        value :contact do
          field :note, :string
          field :floor, :integer
        end

        subdomain :core, "Core", type: :core
      end

      defmodule EhOsContract.CheckContractsTest.Desk do
        use EhOsContract.Contract, domain: EhOsContract.CheckContractsTest.Notes, context: :desk, id: "notes.desk"

        aggregate :desk, "Recepcja" do
          identity :visit_id
          command :note, "Notatka", by: :reception, emits: :noted

          event :noted, "Zanotowano" do
            field :lines, {:list, :string}
            field :remark, :again
            field :contact, :contact
            field :count, :integer
          end
        end
      end
      """,
      "notes.ex"
    )

    assert Contracts.findings([EhOsContract.CheckContractsTest.Desk], [])
           |> Enum.filter(&(&1.rule == "free-text-not-personal"))
           |> Enum.map(&(&1.message |> String.split(" of ") |> hd())) ==
             [":noted.lines", ":noted.remark", ":noted.contact.note"]
  end

  test "reactions of two contracts to one event compete in one transaction" do
    compile(
      """
      defmodule EhOsContract.CheckContractsTest.Reception do
        use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.reception"

        consumes #{inspect(@visits)}, :booked, as: [booked: :visit_booked]

        aggregate :desk, "Recepcja" do
          identity :visit_id
          command :prepare, "Przygotuj", by: :reception, emits: :prepared
          event :prepared, "Przygotowano"
        end

        policy :prepare_desk, "Przygotowanie", handles: :visit_booked, issues: :prepare
      end
      """,
      "reception.ex"
    )

    assert [%Finding{message: message}] =
             Contracts.findings([@visits, EhOsContract.CheckContractsTest.Reception], [@decider])
             |> Enum.filter(&(&1.rule == "competing-in-transaction-consumers"))

    assert message =~ ":booked of #{inspect(@visits)} has 3 reactions"
    assert message =~ "policy :prepare_desk of EhOsContract.CheckContractsTest.Reception"
  end

  test "reactions declared :in_transaction on another context's event; control: :at_least_once" do
    compile(
      """
      defmodule EhOsContract.CheckContractsTest.Billing do
        use EhOsContract.Contract, domain: Clinic, context: :billing, id: "clinic.billing"

        consumes #{inspect(@visits)}, :booked

        aggregate :bill, "Rachunek" do
          identity :visit_id
          command :open_bill, "Otwórz rachunek", by: :reception, emits: :bill_opened
          event :bill_opened, "Rachunek otwarty"
        end

        policy :bill_on_booking, "Umówiono — rachunek", handles: :booked, issues: :open_bill,
          delivery: :in_transaction
        policy :bill_later, "Umówiono — rachunek później", handles: :booked, issues: :open_bill,
          delivery: :at_least_once, idempotency: [key: :event_id, owner: :infrastructure]
        effect :note_booking, "Zapis", handles: :booked, delivery: :in_transaction

        read_model :booked, "Umówione", projects: :booked, delivery: :in_transaction do
          field :visit_id, :id
        end
      end
      """,
      "billing.ex"
    )

    found =
      for %Finding{rule: "in-transaction-across-contexts"} = f <-
            Contracts.findings([@visits, EhOsContract.CheckContractsTest.Billing], [@decider]),
          do: {f.message |> String.split(" of ") |> hd(), Finding.place(f)}

    assert found == [
             {"policy :bill_on_booking", {"billing.ex", 12}},
             {"effect :note_booking", {"billing.ex", 16}},
             {"read model :booked", {"billing.ex", 18}}
           ]

    [policy, _effect, read_model] =
      for %Finding{rule: "in-transaction-across-contexts", message: m} <-
            Contracts.findings([EhOsContract.CheckContractsTest.Billing], []),
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
      defmodule EhOsContract.CheckContractsTest.Desk2 do
        use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.desk2"

        consumes #{inspect(@visits)}, :booked

        aggregate :desk, "Recepcja" do
          identity :visit_id
          command :prepare, "Przygotuj", by: :reception, emits: :prepared
          event :prepared, "Przygotowano"
        end

        policy :prepare_desk, "Przygotowanie", handles: :booked, issues: :prepare,
          delivery: :in_transaction
      end
      """,
      "desk2.ex"
    )

    assert for(
             %Finding{rule: "in-transaction-across-contexts"} = f <-
               Contracts.findings([EhOsContract.CheckContractsTest.Desk2], []),
             do: f
           ) == []
  end
end
