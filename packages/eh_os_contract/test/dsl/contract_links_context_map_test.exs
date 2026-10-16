defmodule EhOsContract.ContractLinksContextMapTest do
  @moduledoc """
  Plan DD, M1 (#316): **the context map holds the contracts to it**. A reference against a
  directed relation, or across `separate_ways`, does not compile (X11); behind an
  `anticorruption_layer` only a policy takes the upstream contract's event (X12); behind an
  `open_host_service` or a `published_language` a contract consumes only what its upstream
  sibling publishes (X13). A field typed with a value another context declares is a
  reference too. Each refusal has a control beside it that passes.
  """

  use EhOsContract.DslCase, async: false

  @domain EhOsContract.ContractLinksContextMapTest.Clinic
  @ns "EhOsContract.ContractLinksContextMapTest"

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :context_map, language: :pl

        subdomain :core, "Rdzeń", type: :core
        context :scheduling, "Umawianie", subdomain: :core
        context :settlement, "Rozliczenia", subdomain: :core
        context :archive, "Archiwum", subdomain: :core
        context :payers, "Płatnicy", subdomain: :core
        context :catalogue, "Katalog", subdomain: :core
        actor :reception, :human, "Recepcja"

        value :tariff, :integer, label: "Taryfa", context: :settlement

        relation :customer_supplier, upstream: :scheduling, downstream: :settlement
        relation :separate_ways, between: [:settlement, :archive]
        relation :anticorruption_layer, upstream: :settlement, downstream: :payers
        relation :open_host_service, upstream: :catalogue, downstream: :scheduling
      end
      """,
      "context_map_clinic.ex"
    )

    :ok
  end

  # A contract of `context` whose unit acts and records `acted_<name>`, with `body` after
  # its `use` line, which is line 2 of its source.
  defp mapped(name, context, body \\ "") do
    under = Macro.underscore(name)

    """
    defmodule #{@ns}.#{name} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: #{inspect(context)}, id: "context_map.#{under}"

      #{body}

      aggregate :#{under}, "#{name}" do
        identity :visit_id
        command :act_#{under}, "Działaj", by: :reception, emits: :acted_#{under}
        event :acted_#{under}, "Zadziałano"
      end
    end
    """
  end

  defp codes(violations, code),
    do: Enum.filter(violations, &String.starts_with?(&1.message, code))

  describe "X11: a reference against the relation does not compile" do
    test "upstream consuming downstream; control: downstream consuming upstream" do
      violations =
        links([
          {"x11_booking.ex", mapped("X11Booking", :scheduling)},
          {"x11_billing.ex",
           mapped("X11Billing", :settlement, "consumes #{@ns}.X11Booking, :acted_x11_booking")},
          {"x11_planner.ex",
           mapped("X11Planner", :scheduling, "consumes #{@ns}.X11Billing, :acted_x11_billing")}
        ])

      assert [_one] = codes(violations, "X11")

      message = assert_linked(violations, "X11: #{@ns}.X11Planner", "x11_planner.ex", 4)

      assert message =~
               "in context :scheduling consumes #{@ns}.X11Billing, and relation " <>
                 ":customer_supplier from upstream :scheduling to downstream :settlement"

      assert message =~ "says :scheduling does not depend on :settlement"
    end

    test "any reference across separate_ways" do
      violations =
        links([
          {"x11_ledger.ex", mapped("X11Ledger", :settlement)},
          {"x11_shelf.ex",
           mapped("X11Shelf", :archive, "consumes #{@ns}.X11Ledger, :acted_x11_ledger")}
        ])

      assert assert_linked(violations, "X11: #{@ns}.X11Shelf", "x11_shelf.ex", 4) =~
               "the two contexts do not depend on each other"
    end

    test "a field identifying a unit against the relation, at the contract's use" do
      violations =
        links([
          {"x11_unit_booking.ex", mapped("X11UnitBooking", :scheduling)},
          {"x11_unit_keeper.ex",
           mapped("X11UnitKeeper", :scheduling)
           |> String.replace(
             ~s(event :acted_x11_unit_keeper, "Zadziałano"),
             ~s(event :acted_x11_unit_keeper, "Zadziałano" do\n) <>
               "      field :ledger_id, {:id, :x11_unit_ledger}\n    end"
           )},
          {"x11_unit_ledger.ex", mapped("X11UnitLedger", :settlement)}
        ])

      assert assert_linked(violations, "X11: #{@ns}.X11UnitKeeper", "x11_unit_keeper.ex", 2) =~
               "names unit :x11_unit_ledger"
    end

    test "a field typed with a value another context declares, against the relation" do
      violations =
        links([
          {"x11_value.ex",
           mapped("X11Value", :scheduling)
           |> String.replace(
             ~s(event :acted_x11_value, "Zadziałano"),
             ~s(event :acted_x11_value, "Zadziałano" do\n      field :price, :tariff\n    end)
           )}
        ])

      assert assert_linked(violations, "X11: #{@ns}.X11Value", "x11_value.ex", 2) =~
               "uses value :tariff of context :settlement"
    end

    test "control: a value used downstream of its context compiles" do
      violations =
        links([
          {"x11_value_ok.ex",
           mapped("X11ValueOk", :payers)
           |> String.replace(
             ~s(event :acted_x11_value_ok, "Zadziałano"),
             ~s(event :acted_x11_value_ok, "Zadziałano" do\n      field :price, :tariff\n    end)
           )}
        ])

      assert codes(violations, "X11") == []
    end
  end

  describe "X12: behind an anticorruption layer only a policy takes the event" do
    defp payer(name, ledger, reaction) do
      mapped(name, :payers, """
      consumes #{@ns}.#{ledger}, :acted_#{Macro.underscore(ledger)}

        #{reaction}
      """)
    end

    test "a read model taking the upstream contract's event" do
      read_model =
        ~s(read_model :ledgers, "Księgi", projects: :acted_x12_ledger, ) <>
          "delivery: :at_least_once do\n" <>
          "    field :visit_id, :id\n  end"

      violations =
        links([
          {"x12_ledger.ex", mapped("X12Ledger", :settlement)},
          {"x12_reader.ex", payer("X12Reader", "X12Ledger", read_model)}
        ])

      assert assert_linked(violations, "X12: read model :ledgers", "x12_reader.ex", 6) =~
               ":payers translates what :settlement says before using it: only a policy takes the event"
    end

    test "control: a policy taking it, and issuing a command of its own context" do
      policy =
        ~s(policy :translate, "Przetłumacz", handles: :acted_x12_ledger_ok, ) <>
          "issues: :act_x12_translator, delivery: :at_least_once, " <>
          "idempotency: [key: :event_id, owner: :infrastructure]"

      violations =
        links([
          {"x12_ledger_ok.ex", mapped("X12LedgerOk", :settlement)},
          {"x12_translator.ex", payer("X12Translator", "X12LedgerOk", policy)}
        ])

      assert codes(violations, "X12") == []
    end
  end

  describe "X13: behind an open host service only what is published crosses" do
    defp catalogue(name, publish) do
      mapped(name, :catalogue, publish)
    end

    @publish ~s(publish :item_listed, as: "catalogue.item.listed.v1", from: :acted_x13_list_ok, ) <>
               "fields: [:visit_id], idempotent_on: [:visit_id]"

    test "consuming an event the upstream contract does not publish" do
      violations =
        links([
          {"x13_list.ex", catalogue("X13List", "")},
          {"x13_reader.ex",
           mapped("X13Reader", :scheduling, "consumes #{@ns}.X13List, :acted_x13_list")}
        ])

      assert assert_linked(violations, "X13: consumes :acted_x13_list", "x13_reader.ex", 4) =~
               ":catalogue offers only what it publishes; it publishes none"
    end

    test "control: consuming the event it publishes" do
      violations =
        links([
          {"x13_list_ok.ex", catalogue("X13ListOk", @publish)},
          {"x13_reader_ok.ex",
           mapped("X13ReaderOk", :scheduling, "consumes #{@ns}.X13ListOk, :acted_x13_list_ok")}
        ])

      assert codes(violations, "X13") == []
    end
  end
end
