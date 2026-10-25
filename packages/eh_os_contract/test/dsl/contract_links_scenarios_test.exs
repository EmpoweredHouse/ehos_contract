defmodule EhOsContract.ContractLinksScenariosTest do
  @moduledoc """
  v2 plan, E5b: **X9** (v2 §6) — scenario values L2 could not check: values of
  domain types, and the data of an event consumed from a sibling contract. Each
  violation names the scenario's declaration, and has a control that passes.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.ScenariosClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :en

        context :settlement, "Settlement", subdomain: :core
        actor :reception, :human, "Reception"
        actor :terminal, :system, "Payment terminal"

        value :money, :integer, unit: :cents
        value :status, {:enum, [:active, :expired]}

        value :charge, :integer, unit: :cents do
          invariant :not_negative, "A charge is not negative",
            violated_by: [-1],
            satisfied_by: [0]
        end

        value :receipt do
          field :charges, {:list, :charge}
        end

        entity :service, "Service", context: :settlement, identity: :service_id do
          field :reported_to_registry, :boolean
          field :fee, :money, optional: true
        end

        value :address do
          field :street, :string
          field :city, :string
          field :apartment, :string, optional: true
        end

        subdomain :core, "Core", type: :core
      end
      """,
      "scenarios_clinic.ex"
    )

    :ok
  end

  describe "values of domain types" do
    # The command's data at line 19, the expected event's at line 20.
    defp registration(name, command, expected) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         aggregate :visit, "Visit" do
           identity :visit_id

           command :register, "Registration", by: :reception, emits: :registered do
             field :status, :status
             field :address, :address
             field :amounts, {:list, :money}
           end

           event :registered, "Registered" do
             field :status, :status
           end
         end

         scenario "registration" do
           command :register, #{command}
           expect :registered, #{expected}
         end
       end
       """}
    end

    test "control: values that fit pass" do
      assert links([
               registration(
                 "ScnValuesRight",
                 ~s|%{status: :active, address: %{street: "Elm Street", city: "Springfield"}, amounts: [100, 200]}|,
                 "%{status: :active}"
               )
             ]) == []
    end

    test "an enum member, a value's fields, a list's items, and what is expected" do
      violations =
        links([
          registration(
            "ScnValuesWrong",
            ~s|%{status: :unknown, address: %{street: "Elm Street", zip: "12345"}, amounts: [100, "200"]}|,
            "%{status: :gone}"
          )
        ])

      file = "scn_values_wrong.ex"

      assert assert_linked(violations, "field :status: :unknown", file, 19) =~
               ~s|X9: scenario "registration": command :register, field :status: :unknown is not | <>
                 "one of [:active, :expired]"

      assert_linked(violations, "field :address: :address has no field :zip", file, 19)
      assert_linked(violations, "field :address: :address needs :city", file, 19)
      assert_linked(violations, ~s|field :amounts: "200" is not an :integer|, file, 19)
      assert_linked(violations, "event :registered, field :status: :gone", file, 20)
      assert length(violations) == 5
    end
  end

  describe "a query's parameters and the rows it answers" do
    # The query's parameters at line 23, the rows at line 24.
    defp statuses(name, params, rows) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         aggregate :visit, "Visit" do
           identity :visit_id
           command :register, "Registration", by: :reception, emits: :registered

           event :registered, "Registered" do
             field :status, :status
           end
         end

         read_model :statuses, "Statuses", projects: :registered do
           field :visit_id, :id
           field :status, :status
         end

         query :with_status, "Visits with a status", reads: :statuses, by: :reception do
           param :status, :status
         end

         scenario "active visits" do
           query :with_status, #{params}
           answers #{rows}
         end
       end
       """}
    end

    test "a member of the domain's enum in a parameter and in a row" do
      violations = links([statuses("ScnQueryWrong", "%{status: :asleep}", "[%{status: :gone}]")])
      file = "scn_query_wrong.ex"

      assert assert_linked(violations, "field :status: :asleep", file, 23) =~
               ~s|X9: scenario "active visits": query :with_status, field :status: :asleep|

      assert assert_linked(violations, "field :status: :gone", file, 24) =~
               ~s|X9: scenario "active visits": a row of read model :statuses, field :status|

      assert length(violations) == 2
    end

    test "control: members that fit pass" do
      assert links([statuses("ScnQueryRight", "%{status: :active}", "[%{status: :active}]")]) ==
               []
    end
  end

  describe "the data of a sibling's event" do
    defp booking(name) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         aggregate :booking, "Booking" do
           identity :booking_id

           command :book_visit, "Booking a visit", by: :reception, emits: :visit_booked

           event :visit_booked, "Visit booked" do
             field :visit_id, :id
             field :room, :string
             field :note, :string, optional: true
           end
         end
       end
       """}
    end

    # The delivered event's data at line 16.
    defp billing(name, booking, data) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         consumes #{inspect(Module.concat(@fixtures, booking))}, :visit_booked

         aggregate :billing, "Billing" do
           identity :visit_id
           command :bill_visit, "Billing a visit", by: :reception, emits: :visit_billed
           event :visit_billed, "Visit billed"
         end

         policy :bill_on_booking, "Bill after booking",
           handles: :visit_booked, issues: :bill_visit

         scenario "a booking billed" do
           on :visit_booked, #{data}
           issues :bill_visit
         end
       end
       """}
    end

    test "control: data that fits the sibling's event passes, without its identity" do
      assert links([
               booking("ScnSiblingRightBooking"),
               billing(
                 "ScnSiblingRightBilling",
                 "ScnSiblingRightBooking",
                 ~s|%{visit_id: "v-1", room: "12"}|
               )
             ]) == []
    end

    test "an unknown key, a missing field and a value of the wrong type" do
      violations =
        links([
          booking("ScnSiblingWrongBooking"),
          billing(
            "ScnSiblingWrongBilling",
            "ScnSiblingWrongBooking",
            ~s|%{visit_id: 1, rooom: "12"}|
          )
        ])

      file = "scn_sibling_wrong_billing.ex"

      assert assert_linked(violations, "no field :rooom", file, 16) =~
               ~s|X9: scenario "a booking billed": event :visit_booked of | <>
                 "#{inspect(@fixtures)}.ScnSiblingWrongBooking (scn_sibling_wrong_booking.ex:9): " <>
                 "no field :rooom"

      assert_linked(violations, "needs :room", file, 16)
      assert_linked(violations, "field :visit_id: 1 is not an :id, a string", file, 16)
      assert length(violations) == 3
    end
  end

  describe "the examples of a domain service's rule (plan EL2b)" do
    # The rule at line 10.
    defp pricing(name, examples) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         domain_service :pricing, "Price list" do
           function :fee, "Fee" do
             argument :status, :status
             argument :address, :address
             returns :money

             rule :by_status, "Depends on the status",
               examples: #{examples}
           end
         end

         aggregate :visit, "Visit" do
           identity :visit_id
           command :close, "Closing", by: :reception, emits: :closed
           event :closed, "Closed"
         end
       end
       """}
    end

    test "control: arguments and a result of domain types that fit pass" do
      assert links([
               pricing(
                 "RuleValuesRight",
                 ~s|[{[:active, %{street: "Elm Street", city: "Springfield"}], 100}]|
               )
             ]) == []
    end

    test "an argument or a result not of its domain type is refused at the rule" do
      violations =
        links([
          pricing(
            "RuleValuesWrong",
            ~s|[{[:lapsed, %{street: "Elm Street"}], "a hundred"}]|
          )
        ])

      assert_linked(
        violations,
        "X9: rule :by_status of function :fee, example 1: argument :status: :lapsed is not " <>
          "one of [:active, :expired]",
        "rule_values_wrong.ex",
        10
      )

      assert_linked(violations, "argument :address: :address needs :city", "rule_values_wrong.ex")

      assert_linked(
        violations,
        ~s|the result: "a hundred" is not an :integer|,
        "rule_values_wrong.ex"
      )
    end
  end

  describe "the row of an entity a command reads (plan DD, T2a, #240)" do
    # The given_entity at line 18.
    defp booking(name, row) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         aggregate :visit, "Visit" do
           identity :visit_id

           command :book_visit, "Book", by: :reception, emits: :visit_booked, reads: [service: :service_id] do
             field :service_id, {:id, :service}
           end

           event :visit_booked, "Visit booked"
         end

         scenario "booking" do
           given_entity :service, #{row}
           command :book_visit, %{service_id: "s-1"}
           expect :visit_booked
         end
       end
       """}
    end

    test "control: a row of the entity's fields, its identity among them, passes" do
      assert links([
               booking("ScnEntityRight", ~s|%{service_id: "s-1", reported_to_registry: true}|)
             ]) ==
               []
    end

    test "a field the entity lacks, one it requires, and a value of the wrong type" do
      violations =
        links([
          booking("ScnEntityWrong", ~s|%{reported_to_registry: "yes", fee: -1.5, colour: :red}|)
        ])

      for problem <- [
            "given_entity :service, no field :colour",
            "given_entity :service, needs :service_id",
            ~s|given_entity :service, field :reported_to_registry: "yes" is not a :boolean|,
            "given_entity :service, field :fee:"
          ] do
        assert_linked(violations, problem, "scn_entity_wrong.ex")
      end
    end
  end

  describe "a recording refused on a value's invariant (S4, issue #430)" do
    # The scenario at line 13.
    defp recording(name, rejected) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

         aggregate :visit, "Visit" do
           identity :visit_id

           event :charged, "Charged", recorded_by: :terminal do
             field :receipt, :receipt
             field :status, :status
           end
         end

         scenario "a charge below zero" do
           actor :terminal
           record :charged, %{receipt: %{charges: [-1]}, status: :active}
           rejected #{inspect(rejected)}
         end
       end
       """}
    end

    test "control: an invariant of a value the event holds, at any depth, passes" do
      assert links([recording("ScnRecordRight", :not_negative)]) == []
    end

    test "a name no value of the event's fields declares" do
      violations = links([recording("ScnRecordWrong", :paid_in_full)])

      assert assert_linked(violations, "rejected :paid_in_full", "scn_record_wrong.ex", 13) =~
               ~s|S4: scenario "a charge below zero": rejected :paid_in_full is no invariant of a | <>
                 "domain value event :charged holds; a recording is refused only on one, and its " <>
                 "fields hold [:not_negative]"

      assert length(violations) == 1
    end

    # The review of #430: each value once, a value shared at every depth too (2^30 paths
    # here, one walk), and what a value is made of before the value, as dispatch asks
    # them (`EhOsContract.Codec`), so the value named is the one dispatch refuses on.
    @tag timeout: 5_000
    test "the values a recording's fields hold, each once, the parts first" do
      layered =
        Map.new(0..29, fn i ->
          next = :"layer_#{i + 1}"
          {:"layer_#{i}", %{type: nil, fields: [%{type: next}, %{type: {:list, next}}]}}
        end)
        |> Map.put(:layer_30, %{type: :integer})

      held = EhOsContract.Contract.Links.Scenarios.held([:layer_0], layered)

      assert length(held) == 31
      assert hd(held) == :layer_30 and List.last(held) == :layer_0

      itself = %{
        node: %{type: nil, fields: [%{type: :node}, %{type: :amount}]},
        amount: %{type: :integer}
      }

      assert EhOsContract.Contract.Links.Scenarios.held([:node, :string], itself) ==
               [:amount, :node]
    end

    test "the value a recording is refused on is one its fields hold, the innermost first" do
      positive = [%{name: :positive}]

      values = %{
        outer: %{type: :inner, invariants: positive},
        inner: %{type: :integer, invariants: positive},
        elsewhere: %{type: :integer, invariants: positive}
      }

      assert EhOsContract.Contract.Links.Scenarios.refusing_value(
               [%{type: :outer}],
               :positive,
               values
             ) == :inner

      assert EhOsContract.Contract.Links.Scenarios.refusing_value(
               [%{type: :string}],
               :positive,
               values
             ) == nil
    end
  end
end
