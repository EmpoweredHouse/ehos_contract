defmodule EhOsContract.ImplementationTest do
  @moduledoc """
  v2 plan, E5: **binding an implementation to a contract, and I1–I7 of v2 §6** —
  each refusal a `CompileError` pointing at the implementation's file and line, never
  at the library, with a control beside it that compiles without a single warning.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Next.Fixtures.Billing

  @contract """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      state do
        field :paid, :integer, default: 0
      end

      invariant :paid_in_full, "Zapłacono całość"

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :integer
      end

      command :close, "Zamknięcie",
        by: :reception,
        emits: [:closed, :closed_without_payment],
        rejects: :paid_in_full

      command :remind, "Przypomnienie", emits: :reminded

      event :payment_recorded, "Zapłacono" do
        field :amount, :integer
      end

      event :closed, "Zamknięto", terminal: true
      event :closed_without_payment, "Zamknięto bez płatności", terminal: true
      event :reminded, "Przypomniano"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    policy :remind_on_payment, "Przypomnij po płatności", handles: :payment_recorded, issues: :remind
    effect :notify, "Powiadom", handles: :closed, idempotency: :downstream

    process_manager :chase, "Pogoń" do
      correlate :visit_id

      state do
        field :reminders, :integer, default: 0
      end

      starts_on :payment_recorded, sets: :later
      timer :later, wait: {1, :day}, issues: :remind
      ends_on :closed
    end

    read_model :payments, "Płatności", projects: :payment_recorded do
      field :visit_id, :id
      field :amount, :integer
    end

    query :payments_of, "Płatności wizyty", reads: :payments, by: :reception do
      param :visit_id, :id
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  """

  # The body of a whole aggregate implementation; line 4 of the file is its first.
  @aggregate """
    @impl true
    def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
      do: emit(%PaymentRecorded{visit_id: id, amount: a})

    @impl true
    def close(%Close{visit_id: id}, %State{paid: 0}), do: emit(%ClosedWithoutPayment{visit_id: id})
    def close(%Close{visit_id: id}, %State{paid: 100}), do: emit([%Closed{visit_id: id}])
    def close(_command, _state), do: reject(:paid_in_full)

    @impl true
    def remind(%Remind{visit_id: id}, _state), do: emit(for _ <- [1], do: %Reminded{visit_id: id})

    @impl true
    def evolve(%State{} = state, %PaymentRecorded{amount: a}), do: %{state | paid: state.paid + a}
    def evolve(state, _event), do: state
  """

  setup_all do
    compile(contract("Billing", @contract), "billing.ex")
    :ok
  end

  # An implementation `EhOsContract.Next.Implementations.<name>` whose body starts at
  # line 4 of `<name, underscored>.ex`.
  defp implementation(name, binding, body) do
    source = """
    defmodule EhOsContract.Next.Implementations.#{name} do
      use EhOsContract.Next.Fixtures.Billing, #{binding}

    #{body}
    end
    """

    {source, "#{Macro.underscore(name)}.ex"}
  end

  defp refused({source, file}, fragment, line), do: assert_refused(source, file, fragment, line)

  # Compiles, and without a single diagnostic: the gate compiles with
  # --warnings-as-errors, so a warning would be a refusal there.
  defp compiles_clean({source, file}) do
    {_, diagnostics} = Code.with_diagnostics(fn -> compile(source, file) end)
    assert diagnostics == []
    Module.concat(EhOsContract.Next.Implementations, file |> Path.rootname() |> Macro.camelize())
  end

  describe "binding" do
    test "control: a whole aggregate compiles, and says what it emits" do
      module = compiles_clean(implementation("Visit", "aggregate: :visit", @aggregate))

      assert module.__eh_os_implementation__() == %{
               contract: Billing,
               kind: :aggregate,
               name: :visit,
               emitted: %{
                 {:record_payment, 2} => [:payment_recorded],
                 {:close, 2} => [:closed_without_payment, :closed],
                 {:remind, 2} => [:reminded]
               }
             }

      assert Billing.Aggregates.Visit in module.module_info(:attributes)[:behaviour]
    end

    test "control: a policy, an effect, a process manager, a read model and a query compile" do
      compiles_clean(
        implementation("Remind", "policy: :remind_on_payment", """
          @impl true
          def payment_recorded(%PaymentRecorded{visit_id: id}), do: issue(%Remind{visit_id: id})
        """)
      )

      compiles_clean(
        implementation("Notify", "effect: :notify", """
          @impl true
          def closed(%Closed{}), do: :ok
        """)
      )

      compiles_clean(
        implementation("Chase", "process_manager: :chase", """
          @impl true
          def later(%State{}), do: issue([%Remind{visit_id: "w-1"}])

          @impl true
          def evolve(%State{} = state, %PaymentRecorded{}), do: state
          def evolve(%State{} = state, %Closed{}), do: state
        """)
      )

      compiles_clean(
        implementation("Payments", "read_model: :payments", """
          @impl true
          def payment_recorded(%PaymentRecorded{}), do: :ok
        """)
      )

      compiles_clean(
        implementation("PaymentsOf", "query: :payments_of", """
          @impl true
          def payments_of(%PaymentsOf{visit_id: id}, _ctx), do: [%Row{visit_id: id, amount: 1}]
        """)
      )
    end
  end

  describe "I1: the declaration exists" do
    test "a misspelled name gets a did-you-mean" do
      refused(
        implementation("Misspelled", "aggregate: :vist", @aggregate),
        "I1: use EhOsContract.Next.Fixtures.Billing: there is no aggregate :vist; did you " <>
          "mean :visit?",
        2
      )
    end

    test "a name of another kind, no kind, two kinds, an unknown key" do
      refused(
        implementation("OtherKind", "policy: :visit", ""),
        "I1: use EhOsContract.Next.Fixtures.Billing: :visit is not a policy but an aggregate",
        2
      )

      refused(
        implementation("NoKind", "[]", ""),
        "I1: use EhOsContract.Next.Fixtures.Billing names no declaration",
        2
      )

      refused(
        implementation("TwoKinds", "aggregate: :visit, policy: :remind_on_payment", ""),
        "an implementation binds to one",
        2
      )

      refused(
        implementation("UnknownKey", "saga: :visit", ""),
        "I1: use EhOsContract.Next.Fixtures.Billing takes one of [:aggregate, :dcb, :policy, " <>
          ":effect, :process_manager, :read_model, :query]; [:saga] is not among them",
        2
      )
    end
  end

  describe "I1: one module, one declaration" do
    test "a second binding in the same module is refused" do
      refused(
        implementation("BoundTwice", "effect: :notify", """
          use EhOsContract.Next.Fixtures.Billing, read_model: :payments

          @impl true
          def closed(%Closed{}), do: :ok
        """),
        "I1: EhOsContract.Next.Implementations.BoundTwice already implements effect :notify of " <>
          "EhOsContract.Next.Fixtures.Billing; one module implements one declaration",
        4
      )
    end
  end

  describe "I2 and I3: every callback, and every event evolve/2 is kept from" do
    test "a missing callback is named with the clause to add" do
      body =
        String.replace(
          @aggregate,
          "  @impl true\n  def remind(%Remind{visit_id: id}, _state), do: emit(for _ <- [1], do: %Reminded{visit_id: id})\n\n",
          ""
        )

      message =
        refused(
          implementation("NoRemind", "aggregate: :visit", body),
          "I2: EhOsContract.Next.Implementations.NoRemind does not define remind/2, which " <>
            "aggregate :visit of EhOsContract.Next.Fixtures.Billing expects. Add:",
          2
        )

      assert message =~ "    @impl true\n    def remind(%Remind{} = remind, %State{} = state) do"
    end

    test "evolve/2 without a clause for an event, and without a catch-all" do
      body = String.replace(@aggregate, "  def evolve(state, _event), do: state\n", "")

      refused(
        implementation("Uncovered", "aggregate: :visit", body),
        "I3: EhOsContract.Next.Implementations.Uncovered.evolve/2 has no clause for %Closed{}, " <>
          "%ClosedWithoutPayment{}, %Reminded{}. Add one for each, or a catch-all",
        2
      )
    end

    test "a guarded variable is not a catch-all" do
      body =
        String.replace(
          @aggregate,
          "  def evolve(state, _event), do: state\n",
          "  def evolve(state, event) when is_struct(event, Reminded), do: state\n"
        )

      refused(
        implementation("GuardedVariable", "aggregate: :visit", body),
        "I3: EhOsContract.Next.Implementations.GuardedVariable.evolve/2 has no clause for " <>
          "%Closed{}, %ClosedWithoutPayment{}, %Reminded{}.",
        2
      )
    end

    test "control: a clause for each event covers evolve/2 without a catch-all" do
      body =
        String.replace(@aggregate, "  def evolve(state, _event), do: state\n", """
          def evolve(state, %Closed{}), do: state
          def evolve(state, %ClosedWithoutPayment{} = _event), do: state
          def evolve(state, event = %Reminded{}) when is_struct(event), do: state
        """)

      compiles_clean(implementation("Covered", "aggregate: :visit", body))
    end
  end

  describe "I4 and I5: what a decision emits and rejects on" do
    test "an event the command does not emit, and one that is not a literal" do
      body =
        String.replace(
          @aggregate,
          "do: emit(%PaymentRecorded{visit_id: id, amount: a})",
          "do: emit(%Closed{visit_id: id})"
        )

      refused(
        implementation("WrongEvent", "aggregate: :visit", body),
        "I4: emit/1 gets %EhOsContract.Next.Fixtures.Billing.Events.Closed{}, which is not " <>
          "among the events command :record_payment emits, [:payment_recorded]",
        6
      )

      body =
        String.replace(
          @aggregate,
          "do: emit(%PaymentRecorded{visit_id: id, amount: a})",
          "do: emit(Map.new())"
        )

      refused(
        implementation("NotLiteral", "aggregate: :visit", body),
        "I4: emit/1 takes struct literals — %Name{}, a list of them, or a for producing them " <>
          "— so what it produces is known at compile time; got Map.new()",
        6
      )
    end

    test "a for with uniq: is a literal; one with into: is not" do
      uniq =
        String.replace(
          @aggregate,
          "emit(for _ <- [1], do: %Reminded{visit_id: id})",
          "emit(for _ <- [1], uniq: true, do: %Reminded{visit_id: id})"
        )

      compiles_clean(implementation("ForUniq", "aggregate: :visit", uniq))

      into =
        String.replace(
          @aggregate,
          "emit(for _ <- [1], do: %Reminded{visit_id: id})",
          "emit(for _ <- [1], into: %{}, do: {id, %Reminded{visit_id: id}})"
        )

      refused(
        implementation("ForInto", "aggregate: :visit", into),
        "I4: emit/1 takes struct literals",
        14
      )
    end

    test "control: outside a command's callback, any event of the unit may be emitted" do
      compiles_clean(
        implementation("Helper", "aggregate: :visit", """
        #{@aggregate}
          defp closing(id), do: emit(%Closed{visit_id: id})
          def close_now(id), do: closing(id)
        """)
      )
    end

    test "a rejection the command does not declare, and one that is not a literal" do
      body =
        String.replace(
          @aggregate,
          "def remind(%Remind{visit_id: id}, _state), do: emit(for _ <- [1], do: %Reminded{visit_id: id})",
          "def remind(%Remind{}, _state), do: reject(:paid_in_full)"
        )

      refused(
        implementation("WrongRejection", "aggregate: :visit", body),
        "I5: reject/1 gets :paid_in_full, which is not among the invariants command :remind " <>
          "rejects on, []",
        14
      )

      body =
        String.replace(
          @aggregate,
          "reject(:paid_in_full)",
          "reject(Enum.random([:paid_in_full]))"
        )

      refused(
        implementation("RejectionNotLiteral", "aggregate: :visit", body),
        "I5: reject/1 takes the invariant as an atom literal",
        11
      )
    end
  end

  describe "I6 and I7: what a reaction issues, and which macro goes where" do
    test "a command the policy does not issue" do
      refused(
        implementation("WrongIssue", "policy: :remind_on_payment", """
          @impl true
          def payment_recorded(%PaymentRecorded{visit_id: id}),
            do: issue(%EhOsContract.Next.Fixtures.Billing.Commands.Close{visit_id: id})
        """),
        "I6: issue/1 gets %EhOsContract.Next.Fixtures.Billing.Commands.Close{}, which is not " <>
          "among the commands :payment_recorded issues, [:remind]",
        6
      )
    end

    test "emit in a policy, issue in an aggregate, and emit in an effect" do
      refused(
        implementation("EmitInPolicy", "policy: :remind_on_payment", """
          @impl true
          def payment_recorded(%PaymentRecorded{}), do: emit(%Reminded{visit_id: "w-1"})
        """),
        "I7: emit/1 belongs in an aggregate or a dcb, and this module implements policy " <>
          ":remind_on_payment",
        5
      )

      body =
        String.replace(
          @aggregate,
          "def remind(%Remind{visit_id: id}, _state), do: emit(for _ <- [1], do: %Reminded{visit_id: id})",
          "def remind(%Remind{} = command, _state), do: issue(command)"
        )

      refused(
        implementation("IssueInAggregate", "aggregate: :visit", body),
        "I7: issue/1 belongs in a policy or a process manager, and this module implements " <>
          "aggregate :visit",
        14
      )

      refused(
        implementation("EmitInEffect", "effect: :notify", """
          @impl true
          def closed(%Closed{visit_id: id}), do: emit(%Closed{visit_id: id})
        """),
        "I7: emit/1 belongs in an aggregate or a dcb, and this module implements effect :notify",
        5
      )
    end
  end
end
