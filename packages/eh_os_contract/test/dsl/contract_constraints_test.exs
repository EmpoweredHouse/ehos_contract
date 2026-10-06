defmodule EhOsContract.ContractConstraintsTest do
  @moduledoc """
  Plan EL2, the user's choice after asking whether the engine can check it: **a
  command's constraint is checked as an invariant is**. The contract names it and
  says it in prose; the command `rejects:` it; the implementation `reject/1`s on it;
  a scenario refuses the command on it, and the test generated from that scenario
  shows the code does. A query's constraint is prose alone, since a query refuses
  nothing.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model
  alias EhOsContract.ScenarioCase

  @payments """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      command :record_payment, "Przyjęcie płatności",
        by: :reception, emits: :payment_recorded, rejects: :positive_amount do
        field :amount, :integer
        constraint :positive_amount, "Kwota płatności jest dodatnia", source: "E-55"
      end

      command :note, "Notatka", by: :reception, emits: :noted

      event :payment_recorded, "Zapłacono" do
        field :amount, :integer
      end

      event :noted, "Zanotowano"
    end

    read_model :payments, "Płatności", projects: :payment_recorded do
      field :amount, :integer
    end

    query :payments_of, "Płatności wizyty", reads: :payments, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Recepcja widzi tylko wizyty swojej przychodni"
    end

    scenario "płatność 0 zł — odmowa" do
      command :record_payment, %{amount: 0}
      rejected :positive_amount
    end

    scenario "płatność 100 zł — przyjęta" do
      command :record_payment, %{amount: 100}
      expect :payment_recorded
    end
  """

  setup_all do
    compile(contract("Payments", @payments), "payments.ex")

    compile("""
    defmodule EhOsContract.Fixtures.Implementations.PaymentsVisit do
      use EhOsContract.Fixtures.Payments, aggregate: :visit

      @impl true
      def record_payment(%RecordPayment{amount: a}, _state) when a <= 0,
        do: reject(:positive_amount)

      def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
        do: emit(%PaymentRecorded{visit_id: id, amount: a})

      @impl true
      def note(%Note{visit_id: id}, _state), do: emit(%Noted{visit_id: id})
    end

    defmodule EhOsContract.Fixtures.Implementations.PaymentsLax do
      use EhOsContract.Fixtures.Payments, aggregate: :visit

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
      model = Model.fetch(EhOsContract.Fixtures.Payments)
      record = Enum.find(model.commands, &(&1.name == :record_payment))

      assert record.constraints == [
               %{name: :positive_amount, label: "Kwota płatności jest dodatnia", source: "E-55"}
             ]

      refute Map.has_key?(Enum.find(model.commands, &(&1.name == :note)), :constraints)
    end

    test "the scenario refusing on it passes against code that refuses, and fails against code that does not" do
      scenario =
        Enum.find(
          Model.fetch(EhOsContract.Fixtures.Payments).scenarios,
          &(&1.description == "płatność 0 zł — odmowa")
        )

      assert ScenarioCase.run(
               EhOsContract.Fixtures.Payments,
               scenario,
               [EhOsContract.Fixtures.Implementations.PaymentsVisit]
             )

      assert_raise ExUnit.AssertionError, fn ->
        ScenarioCase.run(EhOsContract.Fixtures.Payments, scenario, [
          EhOsContract.Fixtures.Implementations.PaymentsLax
        ])
      end
    end

    test "a query's constraint is prose in the model" do
      query =
        Enum.find(
          Model.fetch(EhOsContract.Fixtures.Payments).queries,
          &(&1.name == :payments_of)
        )

      assert [%{name: :own_clinic}] = query.constraints
    end
  end

  describe "the digest" do
    test "does not see the order constraints are written in" do
      body = fn first, second ->
        """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :record_payment, "Płatność", by: :reception, emits: :paid, rejects: [:positive, :whole] do
              field :amount, :integer
        #{first}
        #{second}
            end

            event :paid, "Zapłacono"
          end

          scenario "0 zł" do
            command :record_payment, %{amount: 0}
            rejected :positive
          end

          scenario "pół grosza" do
            command :record_payment, %{amount: 1}
            rejected :whole
          end
        """
      end

      positive = ~s|      constraint :positive, "Kwota jest dodatnia"|
      whole = ~s|      constraint :whole, "Kwota jest w pełnych groszach"|

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
          aggregate :visit, "Wizyta" do
            identity :visit_id
            invariant :paid_once, "Wizyta jest opłacona raz"

            command :record_payment, "Płatność", by: :reception, emits: :paid, rejects: [:paid_once, :positive] do
              constraint :positive, "Kwota jest dodatnia"
              constraint :positive, "Kwota jest większa od zera"
              constraint :paid_once, "Raz"
              constraint :in_hours, "W godzinach pracy"
            end

            event :paid, "Zapłacono"
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
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :record_payment, "Płatność", by: :reception, emits: :paid, rejects: :positive do
              field :amount, :integer
              constraint :positive, "Kwota jest dodatnia"
            end

            event :paid, "Zapłacono"
          end

          scenario "płatność przyjęta" do
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
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :record_payment, "Płatność", by: :reception, emits: :paid, rejects: :PositiveAmount do
              constraint :PositiveAmount, "Kwota jest dodatnia"
            end

            event :paid, "Zapłacono"
          end

          read_model :payments, "Płatności", projects: :paid do
            field :visit_id, :id
          end

          query :payments_of, "Płatności", reads: :payments, by: :reception do
            param :visit_id, :id
            constraint :own_clinic, "Tylko własna przychodnia"
            constraint :own_clinic, "Tylko własna przychodnia, drugi raz"
          end
        """)

      assert message =~ "N1: constraint :PositiveAmount is not snake_case"
      assert message =~ "N1: query :payments_of has two constraints named :own_clinic"
    end
  end
end
