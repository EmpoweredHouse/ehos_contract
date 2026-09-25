defmodule EhOsContract.ScenarioCaseTest do
  @moduledoc """
  v2 plan, E5: **`EhOsContract.ScenarioCase` runs a scenario against its
  implementation** and keeps `ContractExample`'s semantics: what is expected appears
  among what is produced, in order, not necessarily alone. Every failure below is
  paired with the right implementation passing the same scenario.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model
  alias EhOsContract.ScenarioCase

  @contract """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      state do
        field :paid, :integer, default: 0
      end

      invariant :paid_in_full, "Zapłacono całość"

      command :record_payment, "Przyjęcie płatności",
        by: :reception,
        emits: [:payment_recorded, :receipt_issued] do
        field :amount, :integer
        field :paid_at, :timestamp
      end

      command :close, "Zamknięcie", by: :reception, emits: :closed, rejects: :paid_in_full
      command :remind, "Przypomnienie", emits: :reminded

      event :payment_recorded, "Zapłacono" do
        field :amount, :integer
        field :paid_at, :timestamp
      end

      event :receipt_issued, "Wydano paragon"
      event :closed, "Zamknięto", terminal: true
      event :reminded, "Przypomniano"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    policy :remind_on_payment, "Przypomnij po płatności", handles: :payment_recorded, issues: :remind

    process_manager :chase, "Pogoń" do
      correlate :visit_id
      starts_on :payment_recorded, sets: :later
      timer :later, wait: {1, :day}, issues: :remind
      ends_on :closed
    end

    scenario "płatność — paragon wśród zdarzeń" do
      command :record_payment, %{amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      expect :payment_recorded, %{paid_at: "2026-09-01T09:00:00Z"}
      expect :receipt_issued
    end

    scenario "sam paragon wystarcza" do
      command :record_payment, %{amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      expect :receipt_issued
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
      given :payment_recorded, %{amount: 50, paid_at: "2026-09-01T09:00:00Z"}
      command :close
      rejected :paid_in_full
    end

    scenario "zapłacono całość — wizyta zamknięta" do
      given :payment_recorded, %{visit_id: "w-7", amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      command :close
      expect :closed, %{visit_id: "w-7"}
    end

    scenario "płatność — przypomnienie" do
      scope :remind_on_payment
      on :payment_recorded, %{amount: 1, paid_at: "2026-09-01T09:00:00Z"}
      issues :remind
    end

    scenario "pogoń — timer wydaje przypomnienie" do
      scope :chase
      given :payment_recorded, %{visit_id: "w-3", amount: 1, paid_at: "2026-09-01T09:00:00Z"}
      on :later
      issues :remind, %{visit_id: "w-3"}
    end
  """

  @visit """
  defmodule EhOsContract.Next.Implementations.ScenarioVisit do
    use EhOsContract.Next.Fixtures.Scenarios, aggregate: :visit

    @impl true
    def record_payment(%RecordPayment{visit_id: id, amount: a, paid_at: at}, _state),
      do: emit([%PaymentRecorded{visit_id: id, amount: a, paid_at: at}, %ReceiptIssued{visit_id: id}])

    @impl true
    def close(%Close{visit_id: id}, %State{paid: 100}), do: emit(%Closed{visit_id: id})
    def close(_command, _state), do: reject(:paid_in_full)

    @impl true
    def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

    @impl true
    def evolve(state, %PaymentRecorded{amount: a}), do: %{state | paid: state.paid + a}
    def evolve(state, _event), do: state
  end

  defmodule EhOsContract.Next.Implementations.ScenarioPolicy do
    use EhOsContract.Next.Fixtures.Scenarios, policy: :remind_on_payment

    @impl true
    def payment_recorded(%PaymentRecorded{visit_id: id}), do: issue(%Remind{visit_id: id})
  end

  defmodule EhOsContract.Next.Implementations.ScenarioChase do
    use EhOsContract.Next.Fixtures.Scenarios, process_manager: :chase

    @impl true
    def later(%State{visit_id: id}), do: issue(%Remind{visit_id: id})
  end
  """

  setup_all do
    compile(contract("Scenarios", @contract), "scenarios.ex")
    compile(@visit, "scenario_implementations.ex")
    :ok
  end

  @right [
    EhOsContract.Next.Implementations.ScenarioVisit,
    EhOsContract.Next.Implementations.ScenarioPolicy,
    EhOsContract.Next.Implementations.ScenarioChase
  ]

  defp scenario(description) do
    Enum.find(
      Model.fetch(EhOsContract.Next.Fixtures.Scenarios).scenarios,
      &(&1.description == description)
    )
  end

  defp run(description, implementations),
    do:
      ScenarioCase.run(
        EhOsContract.Next.Fixtures.Scenarios,
        scenario(description),
        implementations
      )

  defp failure(description, implementations) do
    error = assert_raise ExUnit.AssertionError, fn -> run(description, implementations) end
    ExUnit.AssertionError.message(error)
  end

  # A second implementation of the aggregate, compiled as `name` with `body`.
  defp visit(name, body) do
    compile("""
    defmodule EhOsContract.Next.Implementations.#{name} do
      use EhOsContract.Next.Fixtures.Scenarios, aggregate: :visit

    #{body}
    end
    """)

    Module.concat(EhOsContract.Next.Implementations, name)
  end

  describe "the right implementation" do
    test "passes every scenario, of a unit, a policy and a process manager" do
      for scenario <- Model.fetch(EhOsContract.Next.Fixtures.Scenarios).scenarios do
        assert ScenarioCase.run(EhOsContract.Next.Fixtures.Scenarios, scenario, @right)
      end
    end
  end

  describe "what fails a scenario" do
    test "the expected events out of order" do
      reversed =
        visit("Reversed", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id, amount: a, paid_at: at}, _state),
            do: emit([%ReceiptIssued{visit_id: id}, %PaymentRecorded{visit_id: id, amount: a, paid_at: at}])

          @impl true
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      message = failure("płatność — paragon wśród zdarzeń", [reversed])

      assert message =~
               "the scenario requires these events to appear among those produced, in this order"

      # Control: the one expected event alone is a subsequence either way.
      assert run("sam paragon wystarcza", [reversed])
    end

    test "a field the scenario names with another value, a timestamp read as one" do
      late =
        visit("Late", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
            do: emit([%PaymentRecorded{visit_id: id, amount: a, paid_at: ~U[2026-09-02 09:00:00Z]}, %ReceiptIssued{visit_id: id}])

          @impl true
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      assert failure("płatność — paragon wśród zdarzeń", [late]) =~
               ":payment_recorded %{paid_at: ~U[2026-09-01 09:00:00Z]}"
    end

    test "a state evolve/2 does not keep, so the decision goes the other way" do
      forgetful =
        visit("Forgetful", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id}, _state), do: emit(%ReceiptIssued{visit_id: id})

          @impl true
          def close(%Close{visit_id: id}, %State{paid: 100}), do: emit(%Closed{visit_id: id})
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      assert failure("zapłacono całość — wizyta zamknięta", [forgetful]) =~
               "expected command :close to emit events, and it returned " <>
                 "{:error, %EhOsContract.Rejection{invariant: :paid_in_full}}"

      assert run("zapłacono za mało — zamknięcie odrzucone", [forgetful])
    end

    test "an event the command does not emit, built without emit/1" do
      sly =
        visit("Sly", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id}, _state),
            do: {:ok, [struct!(Closed, visit_id: id), struct!(ReceiptIssued, visit_id: id)]}

          @impl true
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      assert failure("sam paragon wystarcza", [sly]) =~
               "EhOsContract.Next.Fixtures.Scenarios.Events.Closed is not among what command " <>
                 ":record_payment emits, [:payment_recorded, :receipt_issued]"
    end

    test "no implementation, and two" do
      assert failure("sam paragon wystarcza", []) =~
               "no module implements aggregate :visit of EhOsContract.Next.Fixtures.Scenarios, so " <>
                 "its scenario has nothing to run"

      twin =
        visit("Twin", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id}, _state), do: emit(%ReceiptIssued{visit_id: id})

          @impl true
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      assert failure("sam paragon wystarcza", [twin | @right]) =~
               "aggregate :visit of " <>
                 "EhOsContract.Next.Fixtures.Scenarios has 2 implementations"
    end
  end
end
