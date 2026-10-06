defmodule EhOsContract.ContractDomainServicesTest do
  @moduledoc """
  Plan EM2: **what a contract refuses in a domain service** — the names (N1, N2),
  the types of its arguments and results (F1, F2) and, since EL2b, the examples of
  its rules (S9) — each with a control that
  compiles, and that a contract declaring none keeps the version it had before the
  kind existed.
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie", by: :reception, emits: :visit_closed
      event :visit_closed, "Zamknięto"
    end
  """

  test "two functions or two rules of one name, a Kernel clash and a repeated argument are refused" do
    message =
      refuse_contract("ServicesNamed", """
        domain_service :pricing, "Cennik" do
          function :price, "Cena" do
            argument :minutes, :integer
            argument :minutes, :integer
            returns :integer
            rule :rounded, "Zaokrąglona", examples: [{[1, 2], 3}]
            rule :rounded, "Zaokrąglona w górę", examples: [{[1, 2], 3}]
          end

          function :price, "Cena druga" do
            returns :integer
          end

          function :send, "Wyślij" do
            argument :to, :string
            argument :What, :string
            returns :boolean
          end
        end

      #{@unit}
      """)

    assert message =~
             "N1: domain service :pricing has two functions named :price (services_named.ex:13)"

    assert message =~ "N1: function :price has two rules named :rounded (services_named.ex:10)"
    assert message =~ "N2: function :send would define send/2, which clashes with Kernel.send/2"

    # An argument's name is N1's, refused once.
    assert message =~ "N1: argument :What is not snake_case"
    refute message =~ "field :What"

    assert message =~
             "F1: domain service :pricing, function :price declares field :minutes twice " <>
               "(services_named.ex:7)"
  end

  test "a function a behaviour's module defines already is refused; evolve is not" do
    message =
      refuse_contract("ServicesTaken", """
        domain_service :lookup, "Wyszukiwanie" do
          function :behaviour_info, "Informacja" do
            argument :what, :string
            returns :string
          end

          function :module_info, "Moduł" do
            returns :string
          end
        end

      #{@unit}
      """)

    assert message =~
             "N2: function :behaviour_info would define behaviour_info/1, which every module " <>
               "defines already (services_taken.ex:5)"

    assert message =~ "N2: function :module_info would define module_info/0"
  end

  test "control: a function named evolve compiles, since a service's module has no evolve/2" do
    assert %{domain_services: [%{functions: [%{name: :evolve}]}]} =
             compile_contract("ServicesEvolve", """
               domain_service :growth, "Wzrost" do
                 function :evolve, "Następna wartość" do
                   argument :value, :integer
                   returns :integer
                 end
               end

             #{@unit}
             """)
  end

  test "a function that says nothing of what it returns is refused" do
    assert refuse_contract("ServicesSilent", """
             domain_service :pricing, "Cennik" do
               function :price, "Cena" do
                 argument :minutes, :integer
               end
             end

           #{@unit}
           """) =~
             "F2: domain service :pricing, function :price returns nothing: say what it returns " <>
               "with `returns type` (services_silent.ex:5)"
  end

  test "a malformed argument or result type is refused" do
    message =
      refuse_contract("ServicesTyped", """
        domain_service :pricing, "Cennik" do
          function :price, "Cena" do
            argument :method, {:enum, []}
            returns "integer"
          end
        end

      #{@unit}
      """)

    assert message =~
             "F2: domain service :pricing, function :price, field :method: an enum is a " <>
               "non-empty list of members"

    assert message =~
             ~s|F2: domain service :pricing, function :price returns "integer" is not a type| <>
               " (services_typed.ex:7)"
  end

  test "control: a service with functions, arguments of every shape and rules compiles into the model" do
    model =
      compile_contract("ServicesRight", """
        domain_service :pricing, "Cennik", source: "AGG-06" do
          function :price, "Cena usługi" do
            argument :service_id, {:id, :service}
            argument :minutes, :integer, optional: true
            returns :money
            rule :rounded, "Zaokrąglona do pełnych złotych",
              examples: [{["s-1", 61], 2}, {["s-1", nil], 0}],
              source: "W1 00:10:00"
          end

          function :free, "Czy bezpłatna" do
            argument :service_id, :id
            returns :boolean, optional: true
          end
        end

      #{@unit}
      """)

    assert [%{name: :pricing, source: "AGG-06", functions: [price, free]}] = model.domain_services

    assert [
             %{name: :service_id, type: :id, refers_to: :service},
             %{name: :minutes, type: :integer, optional: true}
           ] = price.arguments

    assert %{
             returns: %{type: :money, optional: false},
             rules: [%{name: :rounded, examples: [{["s-1", 61], 2}, {["s-1", nil], 0}]}]
           } = price

    assert %{name: :free, returns: %{type: :boolean, optional: true}} = free
    assert Map.has_key?(model.digests, "domain_service:pricing")

    assert EhOsContract.Model.module_for(model, :domain_service, :pricing) ==
             EhOsContract.Fixtures.ServicesRight.DomainServices.Pricing
  end

  describe "S9: a rule is shown on examples (plan EL2b)" do
    defp rule(examples) do
      """
        domain_service :pricing, "Cennik" do
          function :price, "Cena" do
            argument :minutes, :integer
            argument :method, {:enum, [:card, :cash]}, optional: true
            returns :integer
            rule :rounded, "Zaokrąglona", #{examples}
          end
        end

      #{@unit}
      """
    end

    test "a rule without examples is refused" do
      message =
        assert_refused(
          contract("RuleSilent", String.replace(rule(""), ~s|, \n|, "\n")),
          "rule_silent.ex",
          "examples"
        )

      assert message =~ "required :examples option not found"
    end

    # A test of its own: Spark leaves the entity it was building on the process's
    # stack when a required option is missing, and the next compile in the same
    # process would find it there.
    test "a rule with an empty list of examples is refused" do
      assert refuse_contract("RuleEmpty", rule("examples: []")) =~
               "S9: rule :rounded of function :price of domain service :pricing gives no " <>
                 "example; give at least one, `examples: [{[argument, …], result}]`, since each " <>
                 "is a test (rule_empty.ex:9)"
    end

    test "an example is the function's arguments and its result, each of its type" do
      message =
        refuse_contract(
          "RuleUnfit",
          rule(~s|examples: [{[61], 2}, [61, :card], {[61, :cheque], "2"}, {[nil, nil], nil}]|)
        )

      assert message =~
               "S9: rule :rounded of function :price, example 1: {[61], 2} is not " <>
                 "{[argument, …], result} with 2 arguments"

      assert message =~ "example 2: [61, :card] is not {[argument, …], result}"
      assert message =~ "example 3: argument :method: :cheque is not one of [:card, :cash]"
      assert message =~ ~s|example 3: the result: "2" is not an :integer|

      assert message =~
               "example 4: argument :minutes: nil, and the declaration does not say optional"

      assert message =~ "example 4: the result: nil, and the declaration does not say optional"
      refute message =~ "argument :method: nil"
    end

    test "an example given twice is refused, since each names its test" do
      assert refuse_contract("RuleTwice", rule("examples: [{[61, nil], 2}, {[61, nil], 2}]")) =~
               "S9: rule :rounded of function :price gives the example {[61, nil], 2} twice"
    end
  end

  describe "the examples, as tests (plan EL2b)" do
    alias EhOsContract.ScenarioCase

    test "each runs the function through the contract's module and compares what it returns" do
      model =
        compile_contract("RuleRun", """
          domain_service :pricing, "Cennik" do
            function :price, "Cena" do
              argument :minutes, :integer
              returns :decimal

              rule :per_minute, "Złoty za minutę", examples: [{[3], "3.00"}, {[0], 0}]
            end
          end

        #{@unit}
        """)

      implement = fn name, body ->
        [{module, _}] =
          compile(
            """
            defmodule EhOsContract.Fixtures.#{name} do
              use #{inspect(model.module)}, domain_service: :pricing

              @impl true
              def price(minutes), do: #{body}
            end
            """,
            "#{Macro.underscore(name)}.ex"
          )

        module
      end

      right = implement.("RightPricing", "Decimal.new(minutes)")
      wrong = implement.("WrongPricing", "Decimal.new(minutes + 1)")
      [three, zero] = ScenarioCase.rule_examples(model.module)

      assert ScenarioCase.describe(three) ==
               ~s|rule :per_minute of pricing.price: price(3) returns "3.00"|

      # 3 is 3.00: a decimal is compared as a value.
      assert ScenarioCase.run_rule_example(model.module, three, [right])
      assert ScenarioCase.run_rule_example(model.module, zero, [right])

      error =
        assert_raise ExUnit.AssertionError, fn ->
          ScenarioCase.run_rule_example(model.module, zero, [wrong])
        end

      assert error.message =~ "price(0) returned Decimal.new(\"1\"), and rule :per_minute gives"
    end
  end

  test "a contract without domain services hashes as it did before they existed" do
    with_one =
      compile_contract("ServicesOne", "#{@unit}\n  domain_service :pricing, \"Cennik\"\n",
        id: "clinic.services"
      )

    without = compile_contract("ServicesNone", @unit, id: "clinic.services")

    # The service moves the version, and nothing else's digest.
    assert Map.delete(with_one.digests, "domain_service:pricing") == without.digests
    refute with_one.version == without.version

    # The version the invented ledger had before the kind existed, read on the
    # commit before EM2; the sandbox's Rehmed.Contracts.VisitSettlement kept its
    # recorded 2ae1d0074cbc the same way. An empty group hashed in would move both.
    # The ledger's moved once since, from 4e94b8af0057, with plan EP4: its reactions'
    # `idempotency` names a key and an owner; and from 06808eb90e9f with plan N1: its
    # scenarios lost the raw `scope` key, keeping the resolved `target`; and from
    # 2d4f6e4d01fe with plan N3: its timers have labels; and from ccaadcbebb04 with plan
    # W2: it records a day's close, the event its day tags are tested on, its date of a
    # business day the domain declares; and from b50c8a8121d7 with plan DD, ID3 (#173): its
    # events are typed by its id, `dispatch_rig.ledger`, not its process.
    assert EhOsContract.Model.fetch(DispatchRig.Ledger).version == "256523735770"
  end
end
