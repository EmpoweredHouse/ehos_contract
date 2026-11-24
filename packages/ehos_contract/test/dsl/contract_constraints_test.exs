defmodule EhosContract.ContractConstraintsTest do
  @moduledoc """
  Plan EL2, the user's choice after asking whether the engine can check it: **a
  command's constraint is checked as an invariant is**. The contract names it and
  says it in prose; the command `rejects:` it; the implementation `reject/1`s on it;
  a scenario refuses the command on it, and the test generated from that scenario
  shows the code does. A query's constraint is prose alone, since a query refuses
  nothing.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Model
  alias EhosContract.ScenarioCase

  @payments """
    aggregate :visit, "Visit" do
      identity :visit_id

      command :record_payment, "Recording a payment",
        by: :reception, emits: :payment_recorded, rejects: :positive_amount do
        field :amount, :integer
        constraint :positive_amount, "Payment amount is positive", source: "R-31"
      end

      command :note, "Note", by: :reception, emits: :noted

      event :payment_recorded, "Paid" do
        field :amount, :integer
      end

      event :noted, "Noted"
    end

    read_model :payments, "Payments", projects: :payment_recorded do
      field :amount, :integer
    end

    query :payments_of, "A visit's payments", reads: :payments, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Reception sees only its own clinic's visits"
    end

    scenario "a payment of 0 — refused" do
      command :record_payment, %{amount: 0}
      rejected :positive_amount
    end

    scenario "a payment of 100 — accepted" do
      command :record_payment, %{amount: 100}
      expect :payment_recorded
    end
  """

  setup_all do
    compile(contract("Payments", @payments), "payments.ex")

    compile("""
    defmodule EhosContract.Fixtures.Implementations.PaymentsVisit do
      use EhosContract.Fixtures.Payments, aggregate: :visit

      @impl true
      def record_payment(%RecordPayment{amount: a}, _state) when a <= 0,
        do: reject(:positive_amount)

      def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
        do: emit(%PaymentRecorded{visit_id: id, amount: a})

      @impl true
      def note(%Note{visit_id: id}, _state), do: emit(%Noted{visit_id: id})
    end

    defmodule EhosContract.Fixtures.Implementations.PaymentsLax do
      use EhosContract.Fixtures.Payments, aggregate: :visit

      @impl true
      def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
        do: emit(%PaymentRecorded{visit_id: id, amount: a})

      @impl true
      def note(%Note{visit_id: id}, _state), do: emit(%Noted{visit_id: id})
    end
    """)

    :ok
  end

  describe "a command's constraint" do
    test "is in the model with its command, and a command without one has no such key" do
      model = Model.fetch(EhosContract.Fixtures.Payments)
      record = Enum.find(model.commands, &(&1.name == :record_payment))

      assert record.constraints == [
               %{name: :positive_amount, label: "Payment amount is positive", source: "R-31"}
             ]

      refute Map.has_key?(Enum.find(model.commands, &(&1.name == :note)), :constraints)
    end

    test "the scenario refusing on it passes against code that refuses, and fails against code that does not" do
      scenario =
        Enum.find(
          Model.fetch(EhosContract.Fixtures.Payments).scenarios,
          &(&1.description == "a payment of 0 — refused")
        )

      assert ScenarioCase.run(
               EhosContract.Fixtures.Payments,
               scenario,
               [EhosContract.Fixtures.Implementations.PaymentsVisit]
             )

      assert_raise ExUnit.AssertionError, fn ->
        ScenarioCase.run(EhosContract.Fixtures.Payments, scenario, [
          EhosContract.Fixtures.Implementations.PaymentsLax
        ])
      end
    end

    test "a query's constraint is prose in the model" do
      query =
        Enum.find(
          Model.fetch(EhosContract.Fixtures.Payments).queries,
          &(&1.name == :payments_of)
        )

      assert [%{name: :own_clinic}] = query.constraints
    end
  end

  describe "the digest" do
    test "does not see the order constraints are written in" do
      body = fn first, second ->
        """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :record_payment, "Payment", by: :reception, emits: :paid, rejects: [:positive, :whole] do
              field :amount, :integer
        #{first}
        #{second}
            end

            event :paid, "Paid"
          end

          scenario "zero" do
            command :record_payment, %{amount: 0}
            rejected :positive
          end

          scenario "half a cent" do
            command :record_payment, %{amount: 1}
            rejected :whole
          end
        """
      end

      positive = ~s|      constraint :positive, "The amount is positive"|
      whole = ~s|      constraint :whole, "The amount is in whole cents"|

      one = compile_contract("ConstraintsOrderOne", body.(positive, whole), id: "clinic.ordered")

      other =
        compile_contract("ConstraintsOrderOther", body.(whole, positive), id: "clinic.ordered")

      assert one.digests["command:record_payment"] == other.digests["command:record_payment"]
      assert one.version == other.version
    end
  end

  describe "what does not compile" do
    test "A7: a constraint the command does not reject on, one named twice, one named as an invariant" do
      message =
        refuse_contract("ConstraintsWrong", """
          aggregate :visit, "Visit" do
            identity :visit_id
            invariant :paid_once, "A visit is paid once"

            command :record_payment, "Payment", by: :reception, emits: :paid, rejects: [:paid_once, :positive] do
              constraint :positive, "The amount is positive"
              constraint :positive, "The amount is greater than zero"
              constraint :paid_once, "Once"
              constraint :in_hours, "During working hours"
            end

            event :paid, "Paid"
          end
        """)

      assert [_once] =
               Regex.scan(
                 ~r/N1: command :record_payment has two constraints named :positive/,
                 message
               )

      assert message =~
               "A7: command :record_payment, constraint :paid_once has the name of an invariant"

      assert message =~
               "A7: command :record_payment, constraint :in_hours is not in its rejects:, so " <>
                 "nothing checks it; add it there (constraints_wrong.ex:12)"
    end

    test "S8: a constraint no scenario refuses the command on" do
      message =
        refuse_contract("ConstraintUncovered", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :record_payment, "Payment", by: :reception, emits: :paid, rejects: :positive do
              field :amount, :integer
              constraint :positive, "The amount is positive"
            end

            event :paid, "Paid"
          end

          scenario "a payment accepted" do
            command :record_payment, %{amount: 1}
            expect :paid
          end
        """)

      assert message =~
               "S8: constraint :positive of command :record_payment has no scenario in which the " <>
                 "command is rejected on it (constraint_uncovered.ex:9)"
    end

    test "N1: a constraint's name is snake_case, and a query's are named once" do
      message =
        refuse_contract("ConstraintNames", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :record_payment, "Payment", by: :reception, emits: :paid, rejects: :PositiveAmount do
              constraint :PositiveAmount, "The amount is positive"
            end

            event :paid, "Paid"
          end

          read_model :payments, "Payments", projects: :paid do
            field :visit_id, :id
          end

          query :payments_of, "Payments", reads: :payments, by: :reception do
            param :visit_id, :id
            constraint :own_clinic, "Only one's own clinic"
            constraint :own_clinic, "Only one's own clinic, a second time"
          end
        """)

      assert message =~ "N1: constraint :PositiveAmount is not snake_case"
      assert message =~ "N1: query :payments_of has two constraints named :own_clinic"
    end
  end
end
