defmodule EhOsContract.RunStateAndIdempotencyTest do
  @moduledoc """
  Plan EP4: **what a contract says that can be run or checked.** A process manager's
  scenario says the `state` its run holds after the trigger, and `ScenarioCase` folds
  the step as the engine does and compares it; S3 and S6 refuse a state that names no
  field of the run, that is said twice, or that is said of anything but a process
  manager. A reaction's `idempotency` names its `key` and its `owner`, and only an
  effect's owner is `:downstream` (P3); the callback's doc and the page say what the
  owner asks of the code.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Contract.Doc
  alias EhOsContract.{Model, Pages, ScenarioCase}

  @contract """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :pay, "Płatność", by: :reception, emits: :paid
      command :remind, "Przypomnienie", emits: :reminded
      event :paid, "Zapłacono" do
        field :amount, :integer
      end
      event :reminded, "Przypomniano"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    policy :thank, "Podziękuj za płatność", handles: :paid, issues: :remind,
      delivery: :at_least_once, idempotency: [key: :event_id, owner: :infrastructure]

    effect :receipt, "Wyślij paragon", handles: :paid, calls: :mail,
      idempotency: [key: :event_id, owner: :downstream]

    process_manager :chase, "Pogoń" do
      correlate :visit_id

      state do
        field :paid, :integer, default: 0
        field :remind_at, :timestamp, optional: true
      end

      starts_on :paid, sets: :later
      on :paid
      timer :later, "Later", at: :remind_at, issues: :remind
      ends_on :reminded
    end

    scenario "pierwsza płatność — termin przypomnienia" do
      target :chase
      on :paid, %{visit_id: "w-1", amount: 30}
      sets :later
      state %{visit_id: "w-1", paid: 30, remind_at: "2026-01-02T09:00:00Z"}
    end

    scenario "druga płatność — suma rośnie" do
      target :chase
      given :paid, %{amount: 30}
      on :paid, %{amount: 20}
      state %{paid: 50}
    end

    scenario "płatność — run innej wizyty" do
      target :chase
      on :paid, %{amount: 20}
      state %{visit_id: "w-9"}
    end

    scenario "przypomnienie po zakończeniu" do
      target :chase
      given :paid, %{amount: 30}
      given :reminded
      on :later
      state %{paid: 30}
    end

    scenario "przypomniano, zanim cokolwiek zapłacono" do
      target :chase
      given :reminded
      on :paid, %{amount: 20}
      state %{paid: 20}
    end

    scenario "płatności dwóch wizyt" do
      target :chase
      given :paid, %{visit_id: "w-1", amount: 30}
      on :paid, %{visit_id: "w-2", amount: 20}
      state %{paid: 50}
    end

    scenario "płatności dwóch wizyt — przypomnienie" do
      target :chase
      given :paid, %{visit_id: "w-1", amount: 30}
      given :paid, %{visit_id: "w-2", amount: 20}
      on :later
      issues :remind
    end

    scenario "druga płatność tej samej wizyty" do
      target :chase
      given :paid, %{visit_id: "w-1", amount: 30}
      on :paid, %{amount: 20}
      state %{visit_id: "w-1", paid: 50}
    end

    scenario "przypomnienie — stan bez zmian" do
      target :chase
      given :paid, %{amount: 30}
      on :later
      issues :remind
      state %{paid: 30}
    end
  """

  @chase """
  defmodule EhOsContract.Fixtures.Implementations.RunStateChase do
    use EhOsContract.Fixtures.RunState, process_manager: :chase

    @impl true
    def later(%State{visit_id: id}), do: issue(%Remind{visit_id: id})

    @impl true
    def evolve(%State{paid: paid} = state, %Paid{amount: amount, __meta__: meta}),
      do: %{state | paid: paid + amount, remind_at: DateTime.add(meta.occurred_at, 1, :day)}

    def evolve(state, %Reminded{}), do: state
  end

  defmodule EhOsContract.Fixtures.Implementations.RunStateForgetful do
    use EhOsContract.Fixtures.RunState, process_manager: :chase

    @impl true
    def later(%State{visit_id: id}), do: issue(%Remind{visit_id: id})

    @impl true
    def evolve(state, _event), do: state
  end
  """

  setup_all do
    compile(
      """
      defmodule EhOsContract.RunStateAndIdempotencyTest.Domain do
        use EhOsContract.Domain, name: :clinic, language: :pl
        subdomain :billing, "Rozliczenia", type: :supporting
        context :settlement, "Rozliczenia", subdomain: :billing
      end
      """,
      "run_state_domain.ex"
    )

    model = compile_contract("RunState", @contract)
    compile(@chase, "run_state_chase.ex")

    %{model: model, domain: Model.fetch(EhOsContract.RunStateAndIdempotencyTest.Domain)}
  end

  defp run(model, description, implementation) do
    scenario = Enum.find(model.scenarios, &(&1.description == description))
    ScenarioCase.run(EhOsContract.Fixtures.RunState, scenario, [implementation])
  end

  @right EhOsContract.Fixtures.Implementations.RunStateChase
  @forgetful EhOsContract.Fixtures.Implementations.RunStateForgetful

  describe "a process manager's state in a scenario" do
    test "is kept in the model only where a scenario says it", %{model: model} do
      assert %{state: %{paid: 50}} =
               Enum.find(model.scenarios, &(&1.description == "druga płatność — suma rośnie"))

      model =
        compile_contract("RunStateNone", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :pay, "Płatność", by: :reception, emits: :paid
            event :paid, "Zapłacono"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          process_manager :chase, "Pogoń" do
            correlate :visit_id
            starts_on :paid, sets: :later
            timer :later, "Later", wait: {1, :day}
          end

          scenario "płatność — termin" do
            on :paid
            sets :later
          end
        """)

      refute model.scenarios |> hd() |> Map.has_key?(:state)
    end

    test "passes when the run holds it after the step: the event folded, a timer folding none",
         %{model: model} do
      for description <- [
            "pierwsza płatność — termin przypomnienia",
            "druga płatność — suma rośnie",
            "przypomnienie — stan bez zmian"
          ] do
        assert run(model, description, @right), description
      end
    end

    # Reverse check: an evolve/2 that keeps nothing issues the same commands, and only
    # the state tells it apart.
    test "fails when evolve/2 does not keep what the scenario says", %{model: model} do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "druga płatność — suma rośnie", @forgetful)
        end

      message = ExUnit.AssertionError.message(error)
      assert message =~ "the scenario requires the run to hold, after :paid:"
      assert message =~ "%{paid: 50}"
      assert message =~ "paid: 0"
    end

    # What a scenario's state says is what it checks, never what it builds: a run
    # correlated by it would hold it whatever the code does.
    test "fails on a correlation no given or trigger gives the run", %{model: model} do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "płatność — run innej wizyty", @right)
        end

      assert ExUnit.AssertionError.message(error) =~ ~s|visit_id: "scenario"|
    end

    # What the engine would never take holds no state: a timer of an ended run, a given
    # before anything started the run, and events of two runs folded as one.
    test "fails on a step the engine would not take", %{model: model} do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "przypomnienie po zakończeniu", @right)
        end

      assert ExUnit.AssertionError.message(error) =~
               "the engine would not take :later: the run of :chase is ended"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "przypomniano, zanim cokolwiek zapłacono", @right)
        end

      assert ExUnit.AssertionError.message(error) =~
               "given :reminded reaches no run: the engine starts a run of :chase only on [:paid]"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "płatności dwóch wizyt", @right)
        end

      assert ExUnit.AssertionError.message(error) =~
               ~s|belong to more than one run of :chase: :visit_id is "w-1", "w-2"|

      # Any scenario of the process manager, not only one that says a state.
      error =
        assert_raise ExUnit.AssertionError, fn ->
          run(model, "płatności dwóch wizyt — przypomnienie", @right)
        end

      assert ExUnit.AssertionError.message(error) =~ "belong to more than one run of :chase"

      # Control: a value one event names and another leaves out is one run.
      assert run(model, "druga płatność tej samej wizyty", @right)
    end

    test "S3 refuses a field the run does not have, and a value of the wrong type" do
      message =
        refuse_contract("RunStateFields", """
        #{@contract}
          scenario "płatność — zła nazwa pola" do
            target :chase
            on :paid, %{amount: 1}
            state %{owed: 1, paid: "dużo"}
          end
        """)

      assert message =~
               "S3: scenario \"płatność — zła nazwa pola\" (process manager :chase): the state " <>
                 "of process manager :chase has no field :owed"

      assert message =~ "the state of process manager :chase, field :paid:"
    end

    test "S6 refuses a state said twice, or of anything but a process manager" do
      message =
        refuse_contract("RunStateWhere", """
        #{@contract}
          scenario "płatność — stan dwa razy" do
            target :chase
            on :paid, %{amount: 1}
            state %{paid: 1}
            state %{paid: 1}
          end

          scenario "płatność — stan polityki" do
            target :thank
            on :paid, %{amount: 1}
            issues :remind
            state %{paid: 1}
          end

          scenario "płatność — stan komendy" do
            command :pay
            expect :paid
            state %{paid: 1}
          end
        """)

      assert message =~
               "S6: scenario \"płatność — stan dwa razy\" (process manager :chase): " <>
                 "a scenario says the state once"

      assert message =~ "(policy :thank): state belongs to a process manager's scenario"
      assert message =~ "płatność — stan komendy"
      assert message =~ "state belongs to a process manager's scenario"
    end
  end

  describe "idempotency with its owner" do
    test "is a key and an owner in the model", %{model: model} do
      assert [%{idempotency: %{key: :event_id, owner: :infrastructure}}] = model.policies
      assert [%{idempotency: %{key: :event_id, owner: :downstream}}] = model.effects
      assert [%{idempotency: nil}] = model.process_managers
    end

    test "P3 refuses a downstream owner on a policy and on a process manager" do
      message =
        refuse_contract("DownstreamPolicy", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :pay, "Płatność", by: :reception, emits: :paid
            command :remind, "Przypomnienie", emits: :reminded
            event :paid, "Zapłacono"
            event :reminded, "Przypomniano"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          policy :thank, "Podziękuj", handles: :paid, issues: :remind,
            delivery: :at_least_once, idempotency: [key: :event_id, owner: :downstream]

          process_manager :chase, "Pogoń", idempotency: [key: :event_id, owner: :downstream] do
            correlate :visit_id
            starts_on :paid
          end
        """)

      assert message =~
               "P3: policy :thank issues commands to this engine, so no system downstream keeps " <>
                 "its idempotency; its owner is :self or :infrastructure (downstream_policy.ex:16)"

      assert message =~ "P3: process manager :chase issues commands to this engine"
    end

    test "P3 refuses the engine as an effect's owner, and on a key other than the event's id" do
      message =
        refuse_contract("InfrastructureEffect", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :pay, "Płatność", by: :reception, emits: :paid
            command :remind, "Przypomnienie", emits: :reminded
            event :paid, "Zapłacono"
            event :reminded, "Przypomniano"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          effect :receipt, "Wyślij paragon", handles: :paid, calls: :mail,
            idempotency: [key: :event_id, owner: :infrastructure]

          policy :thank, "Podziękuj", handles: :paid, issues: :remind,
            delivery: :at_least_once, idempotency: [key: :visit_id, owner: :infrastructure]
        """)

      assert message =~
               "P3: effect :receipt calls outside the engine, which keys only the commands a " <>
                 "reaction issues; its owner is :self or :downstream"

      assert message =~
               "P3: policy :thank is kept idempotent by the engine, which keys what it issues by " <>
                 "the event's id; its key is :event_id, not :visit_id"
    end

    test "an owner is required, and is one of three" do
      for idempotency <- ["[key: :event_id]", "[key: :event_id, owner: :somebody]", ":event_id"] do
        assert_raise Spark.Error.DslError, fn ->
          compile_contract("Owner#{System.unique_integer([:positive])}", """
            aggregate :visit, "Wizyta" do
              identity :visit_id
              command :pay, "Płatność", by: :reception, emits: :paid
              event :paid, "Zapłacono"
            end

            process :visit, "Wizyta" do
              correlate :visit_id
            end

            effect :receipt, "Wyślij paragon", handles: :paid, idempotency: #{idempotency}
          """)
        end
      end
    end
  end

  describe "the readers" do
    test "the callback's doc says what the owner asks of the code", %{model: model} do
      assert Doc.callback(model, :effect, :receipt, :paid) =~
               "A second delivery is harmless on `event_id`: the system it calls is given " <>
                 "the key and ignores a repeat."

      assert Doc.callback(model, :policy, :thank, :paid) =~
               "the engine keys what it does by it, with no code here."

      assert Doc.callback(model, :process_manager, :chase, :paid) =~
               ~s|"druga płatność — suma rośnie": holds `paid`|
    end

    test "the pages say the owner and the state a scenario holds", %{
      model: model,
      domain: domain
    } do
      pages = Pages.render(domain, [%{model | domain: domain.module}])
      text = pages |> Enum.map_join("\n", &elem(&1, 1))

      assert text =~ "the system it calls is given the key and ignores a repeat."

      assert text =~
               "holds `paid`, `remind_at`, `visit_id`"
    end
  end
end
