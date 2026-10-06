defmodule EhOsContract.CheckRelationsTest do
  @moduledoc """
  Plan EL2, rule 1 of the prose review: **a reference between two contexts that runs against
  the relation declared between them** — from the upstream context of a directed
  relation into the downstream one, or across `separate_ways` at all. Each finding
  stands at the relation, with a control beside it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @domain EhOsContract.CheckRelationsTest.Clinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :relations, language: :pl

        subdomain :core, "Rdzeń", type: :core
        context :scheduling, "Umawianie", subdomain: :core
        context :settlement, "Rozliczenia", subdomain: :core
        context :archive, "Archiwum", subdomain: :core
        actor :reception, :human, "Recepcja"
        relation :customer_supplier, upstream: :scheduling, downstream: :settlement
        relation :separate_ways, between: [:settlement, :archive]
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  defp contract(name, context, consumes) do
    """
    defmodule EhOsContract.CheckRelationsTest.#{name} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: #{inspect(context)}, id: "relations.#{Macro.underscore(name)}"

      #{consumes}

      aggregate :#{Macro.underscore(name)}, "#{name}" do
        identity :visit_id
        command :act_#{Macro.underscore(name)}, "Działaj", by: :reception, emits: :acted_#{Macro.underscore(name)}
        event :acted_#{Macro.underscore(name)}, "Zadziałano"
      end

      process :#{Macro.underscore(name)}, "#{name}" do
        correlate :visit_id
      end
    end
    """
  end

  defp findings(modules) do
    for %Finding{rule: "relation-against-references"} = f <- Completeness.findings(modules),
        do: {f.message, Finding.place(f)}
  end

  test "upstream consuming downstream runs against the relation; control: downstream consuming upstream" do
    compile(
      contract("Booking", :scheduling, "") <>
        contract(
          "Billing",
          :settlement,
          "consumes EhOsContract.CheckRelationsTest.Booking, :acted_booking"
        ) <>
        contract(
          "Planner",
          :scheduling,
          "consumes EhOsContract.CheckRelationsTest.Billing, :acted_billing"
        ),
      "contracts.ex"
    )

    modules = [
      EhOsContract.CheckRelationsTest.Booking,
      EhOsContract.CheckRelationsTest.Billing,
      EhOsContract.CheckRelationsTest.Planner
    ]

    assert [{message, {"contracts.ex", 34}}] = findings(modules)

    assert message =~
             "EhOsContract.CheckRelationsTest.Planner in context :scheduling consumes " <>
               "EhOsContract.CheckRelationsTest.Billing, and relation :customer_supplier from " <>
               "upstream :scheduling to downstream :settlement"

    assert message =~ "says :scheduling does not depend on :settlement"
  end

  test "any reference across separate_ways runs against it" do
    compile(
      contract("Ledger", :settlement, "") <>
        contract(
          "Shelf",
          :archive,
          "consumes EhOsContract.CheckRelationsTest.Ledger, :acted_ledger"
        ),
      "separate.ex"
    )

    assert [{message, {"separate.ex", 19}}] =
             findings([
               EhOsContract.CheckRelationsTest.Ledger,
               EhOsContract.CheckRelationsTest.Shelf
             ])

    assert message =~ "the two contexts do not depend on each other"
  end
end
