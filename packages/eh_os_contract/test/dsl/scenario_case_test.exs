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
    aggregate :visit, "Visit" do
      identity :visit_id

      state do
        field :paid, :integer, default: 0
      end

      invariant :paid_in_full, "Paid in full"

      command :record_payment, "Recording a payment",
        by: :reception,
        emits: [:payment_recorded, :receipt_issued] do
        field :amount, :integer
        field :paid_at, :timestamp
      end

      command :close, "Closing", by: :reception, emits: :closed, rejects: :paid_in_full
      command :remind, "Reminder", emits: :reminded

      event :payment_recorded, "Paid" do
        field :amount, :integer
        field :paid_at, :timestamp
      end

      event :receipt_issued, "Receipt issued"
      event :closed, "Closed"
      event :reminded, "Reminded"
    end

    policy :remind_on_payment, "Remind after a payment", handles: :payment_recorded, issues: :remind

    process_manager :chase, "Chase" do
      correlate :visit_id
      starts_on :payment_recorded, sets: :later
      timer :later, "Later", wait: {1, :day}, issues: :remind
      ends_on :closed
    end

    scenario "payment — a receipt among the events" do
      command :record_payment, %{amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      expect :payment_recorded, %{paid_at: "2026-09-01T09:00:00Z"}
      expect :receipt_issued
    end

    scenario "a receipt alone is enough" do
      command :record_payment, %{amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      expect :receipt_issued
    end

    scenario "paid too little — closing rejected" do
      given :payment_recorded, %{amount: 50, paid_at: "2026-09-01T09:00:00Z"}
      command :close
      rejected :paid_in_full
    end

    scenario "paid in full — visit closed" do
      given :payment_recorded, %{visit_id: "w-7", amount: 100, paid_at: "2026-09-01T09:00:00Z"}
      command :close
      expect :closed, %{visit_id: "w-7"}
    end

    scenario "a September payment — visit closed" do
      given :payment_recorded, %{visit_id: "w-8", amount: 100, paid_at: "2026-09-01T09:00:00Z"},
        at: "2026-09-01T09:00:00Z"

      command :close
      expect :closed, %{visit_id: "w-8"}
    end

    scenario "payment — reminder" do
      target :remind_on_payment
      on :payment_recorded, %{amount: 1, paid_at: "2026-09-01T09:00:00Z"}
      issues :remind
    end

    scenario "chase — the timer issues a reminder" do
      target :chase
      given :payment_recorded, %{visit_id: "w-3", amount: 1, paid_at: "2026-09-01T09:00:00Z"}
      on :later
      issues :remind, %{visit_id: "w-3"}
    end
  """

  @visit """
  defmodule EhOsContract.Fixtures.Implementations.ScenarioVisit do
    use EhOsContract.Fixtures.Scenarios, aggregate: :visit

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

  defmodule EhOsContract.Fixtures.Implementations.ScenarioPolicy do
    use EhOsContract.Fixtures.Scenarios, policy: :remind_on_payment

    @impl true
    def payment_recorded(%PaymentRecorded{visit_id: id}), do: issue(%Remind{visit_id: id})
  end

  defmodule EhOsContract.Fixtures.Implementations.ScenarioChase do
    use EhOsContract.Fixtures.Scenarios, process_manager: :chase

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
    EhOsContract.Fixtures.Implementations.ScenarioVisit,
    EhOsContract.Fixtures.Implementations.ScenarioPolicy,
    EhOsContract.Fixtures.Implementations.ScenarioChase
  ]

  defp scenario(description) do
    Enum.find(
      Model.fetch(EhOsContract.Fixtures.Scenarios).scenarios,
      &(&1.description == description)
    )
  end

  defp run(description, implementations),
    do:
      ScenarioCase.run(
        EhOsContract.Fixtures.Scenarios,
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
    defmodule EhOsContract.Fixtures.Implementations.#{name} do
      use EhOsContract.Fixtures.Scenarios, aggregate: :visit

    #{body}
    end
    """)

    Module.concat(EhOsContract.Fixtures.Implementations, name)
  end

  describe "the right implementation" do
    test "passes every scenario, of a unit, a policy and a process manager" do
      for scenario <- Model.fetch(EhOsContract.Fixtures.Scenarios).scenarios do
        assert ScenarioCase.run(EhOsContract.Fixtures.Scenarios, scenario, @right)
      end
    end
  end

  describe "when a given happened (plan DD, S2, #251)" do
    test "a given's at: is the moment its event carries, and a given without one is not" do
      september =
        visit("September", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id}, _state), do: emit(%ReceiptIssued{visit_id: id})

          @impl true
          def close(%Close{visit_id: id}, %State{paid: 100}), do: emit(%Closed{visit_id: id})
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          # Counts only a payment that happened in September.
          @impl true
          def evolve(state, %PaymentRecorded{amount: a, __meta__: %{occurred_at: %{month: 9}}}),
            do: %{state | paid: state.paid + a}

          def evolve(state, _event), do: state
        """)

      assert run("a September payment — visit closed", [september])

      # Without at:, the given happened on 1 January 2026, the scenario's first moment.
      assert failure("paid in full — visit closed", [september]) =~
               "{:error, %EhOsContract.Rejection{invariant: :paid_in_full}}"
    end

    test "the model keeps a given's at: only where it is set" do
      assert [%{at: "2026-09-01T09:00:00Z"}] =
               scenario("a September payment — visit closed").given

      assert [given] = scenario("paid in full — visit closed").given
      refute Map.has_key?(given, :at)
    end

    test "an at: that is no timestamp, or earlier than the given before it, is refused" do
      body = fn first, second ->
        """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close, "Closing", by: :reception, emits: :closed
            event :opened, "Opened", recorded_by: :reception
            event :closed, "Closed"
          end

          scenario "two events — closing" do
            given :opened#{if first, do: ", at: #{inspect(first)}"}
            given :opened, at: #{inspect(second)}
            command :close
            expect :closed
          end
        """
      end

      assert refuse_contract("DatedOrder", body.("2026-09-02T09:00:00Z", "2026-09-01T09:00:00Z")) =~
               ~s|S3: scenario "two events — closing": given :opened happened at | <>
                 "2026-09-01T09:00:00Z, before the given before it (2026-09-02T09:00:00Z)"

      assert refuse_contract("DatedForm", body.("2026-09-01", "2026-09-02T09:00:00Z")) =~
               ~s|given :opened, at: "2026-09-01" is not an ISO 8601 timestamp with an offset|

      assert refuse_contract("DatedLate", body.(nil, "2026-09-02T09:00:00Z")) =~
               "given :opened has no at:, and comes before given :opened, which has one; it " <>
                 "would happen on 2026-01-01T09:00:00Z, so date it too"

      assert %{scenarios: [_]} =
               compile_contract(
                 "DatedFine",
                 body.("2026-09-01T09:00:00Z", "2026-09-01T09:00:00Z")
               )
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

      message = failure("payment — a receipt among the events", [reversed])

      assert message =~
               "the scenario requires these events to appear among those produced, in this order"

      # Control: the one expected event alone is a subsequence either way.
      assert run("a receipt alone is enough", [reversed])
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

      assert failure("payment — a receipt among the events", [late]) =~
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

      assert failure("paid in full — visit closed", [forgetful]) =~
               "expected command :close to emit events, and it returned " <>
                 "{:error, %EhOsContract.Rejection{invariant: :paid_in_full}}"

      assert run("paid too little — closing rejected", [forgetful])
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

      assert failure("a receipt alone is enough", [sly]) =~
               "EhOsContract.Fixtures.Scenarios.Events.Closed is not among what command " <>
                 ":record_payment emits, [:payment_recorded, :receipt_issued]"
    end

    test "data of a domain type that does not fit, which only the run can see" do
      compile("""
      defmodule EhOsContract.Fixtures.MomentDomain do
        use EhOsContract.Domain, name: :moments, language: :pl
        context :clinic, "Clinic", subdomain: :core
        value :moment, :timestamp

        subdomain :core, "Core", type: :core
      end

      defmodule EhOsContract.Fixtures.Moments do
        use EhOsContract.Contract, domain: EhOsContract.Fixtures.MomentDomain, context: :clinic, id: "moments.moments"

        aggregate :visit, "Visit" do
          identity :visit_id

          command :arrive, "Arrival", by: :reception, emits: :arrived do
            field :at, :moment
          end

          event :arrived, "Arrived" do
            field :at, :moment
          end
        end

        scenario "arrived yesterday" do
          command :arrive, %{at: "yesterday"}
          expect :arrived
        end

        scenario "arrived at nine" do
          command :arrive, %{at: "2026-09-01T09:00:00Z"}
          expect :arrived, %{at: "2026-09-01T09:00:00Z"}
        end
      end

      defmodule EhOsContract.Fixtures.Implementations.Moments do
        use EhOsContract.Fixtures.Moments, aggregate: :visit

        @impl true
        def arrive(%Arrive{visit_id: id, at: %DateTime{} = at}, _state),
          do: emit(%Arrived{visit_id: id, at: at})
      end
      """)

      [yesterday, nine] = Model.fetch(EhOsContract.Fixtures.Moments).scenarios
      implementations = [EhOsContract.Fixtures.Implementations.Moments]

      error =
        assert_raise ExUnit.AssertionError, fn ->
          ScenarioCase.run(EhOsContract.Fixtures.Moments, yesterday, implementations)
        end

      assert error.message ==
               ~s|scenario data, field :at: "yesterday" is not an ISO 8601 timestamp with an | <>
                 ~s|offset, "2026-09-01T09:00:00Z"|

      assert ScenarioCase.run(EhOsContract.Fixtures.Moments, nine, implementations)
    end

    test "a decision that returns a map, not a struct" do
      mapped =
        visit("Mapped", """
          @impl true
          def record_payment(%RecordPayment{visit_id: id}, _state), do: {:ok, [%{visit_id: id}]}

          @impl true
          def close(_command, _state), do: reject(:paid_in_full)

          @impl true
          def remind(%Remind{visit_id: id}, _state), do: emit(%Reminded{visit_id: id})

          @impl true
          def evolve(state, _event), do: state
        """)

      assert failure("a receipt alone is enough", [mapped]) =~
               ~s|command :record_payment emits structs, and the code produced | <>
                 ~s|%{visit_id: "scenario"}, which is not one|
    end

    test "no implementation, and two" do
      assert failure("a receipt alone is enough", []) =~
               "no module implements aggregate :visit of EhOsContract.Fixtures.Scenarios, so " <>
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

      assert failure("a receipt alone is enough", [twin | @right]) =~
               "aggregate :visit of " <>
                 "EhOsContract.Fixtures.Scenarios has 2 implementations"
    end
  end
end
