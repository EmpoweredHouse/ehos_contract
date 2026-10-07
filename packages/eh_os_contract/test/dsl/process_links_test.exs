defmodule EhOsContract.ProcessLinksTest do
  @moduledoc """
  Plan DD, P2c (#210): **a process module checked against its domain and the contracts
  it includes** (L3, `EhOsContract.Contract.Links.Processes`), under the contract's
  codes: X1 and D11 for its domain and id, X2 for its accountable actor, X5 for each
  include, X6 for its `correlate`, X7 for its id among the system's processes. Each
  refusal names the module's file and line, and has a control beside it that passes.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.ProcLinksClinic
  @other EhOsContract.Fixtures.ProcLinksOther

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :scheduling, "Umawianie wizyt", subdomain: :core
        context :documentation, "Dokumentacja", subdomain: :core
        actor :reception, :human, "Recepcja", context: :scheduling
        actor :doctor, :human, "Lekarz", context: :documentation
        subject :patient, "Pacjent"

        value :visit_code, :id
        value :other_code, :id

        subdomain :core, "Core", type: :core
      end
      """,
      "proc_links_clinic.ex"
    )

    compile(
      """
      defmodule #{inspect(@other)} do
        use EhOsContract.Domain, name: :other, language: :pl

        context :scheduling, "Umawianie wizyt", subdomain: :core
        actor :reception, :human, "Recepcja"

        subdomain :core, "Core", type: :core
      end
      """,
      "proc_links_other.ex"
    )

    :ok
  end

  @visit_fields """
        field :visit_id, :id
        field :room, :string
  """

  # A contract with one aggregate deciding `:visit_completed` (line 9) with `fields`,
  # and what `extra` adds from line 13.
  defp unit_contract(name, fields, opts \\ []) do
    domain = Keyword.get(opts, :domain, @domain)
    namespace = if domain == @other, do: "other", else: "clinic"

    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{inspect(domain)}, context: :scheduling, id: "#{namespace}.#{contract_name(name)}"

      aggregate :booking, "Rezerwacja" do
        identity :booking_id

        command :complete_visit, "Zakończenie wizyty", by: :reception, emits: :visit_completed

        event :visit_completed, "Wizyta zakończona" do
    #{fields}
        end
      end

    #{Keyword.get(opts, :extra, "")}
    end
    """
  end

  # A process module whose `correlate` is at line 4 and whose one stage, including
  # `include`, at line 6.
  defp process(name, include, opts \\ []) do
    {correlate, opts} = Keyword.pop(opts, :correlate, ":visit_id")

    process_module(
      name,
      """
        correlate #{correlate}

        stage :departure, include: [#{include}]
      """,
      Keyword.merge([domain: @domain], opts)
    )
  end

  defp file(name), do: "#{Macro.underscore(name)}.ex"

  # The contract `<prefix>Scheduling` with `fields`, and the process module
  # `<prefix>Visit` including its `:visit_completed`, checked together.
  defp pair(prefix, fields, opts \\ []) do
    scheduling = "#{prefix}Scheduling"
    include = "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_completed}"

    links([
      {file(scheduling), unit_contract(scheduling, fields)},
      {file("#{prefix}Visit"), process("#{prefix}Visit", include, opts)}
    ])
  end

  # `<prefix>Scheduling`, whose `:visit_completed` carries `:visit_id` as a
  # `:visit_code`, and `<prefix>Documentation`, whose `:visit_done` carries `fields`,
  # both included by `<prefix>Visit`, checked together.
  defp two(prefix, fields) do
    scheduling = "#{prefix}Scheduling"
    documentation = "#{prefix}Documentation"

    done =
      documentation
      |> unit_contract(fields)
      |> String.replace(":visit_completed", ":visit_done")
      |> String.replace(":complete_visit", ":close_visit")

    links([
      {file(scheduling), unit_contract(scheduling, "      field :visit_id, :visit_code")},
      {file(documentation), done},
      {file("#{prefix}Visit"),
       process(
         "#{prefix}Visit",
         "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_completed}, " <>
           "{#{inspect(Module.concat(@fixtures, documentation))}, :visit_done}"
       )}
    ])
  end

  test "control: a process module including a declared event that carries its correlation passes" do
    assert pair("ProcRight", @visit_fields, accountable: :reception) == []
  end

  describe "X1 and D11: the domain and the id" do
    test "a domain that is not a compiled domain" do
      violations = pair("ProcNoDomain", @visit_fields, domain: Nowhere)

      assert assert_linked(violations, "X1:", "proc_no_domain_visit.ex", 2) =~
               "#{inspect(@fixtures)}.ProcNoDomainVisit names domain Nowhere, which is not a " <>
                 "compiled EhOsContract.Domain"
    end

    test "an id outside the domain's namespace" do
      violations = pair("ProcOutside", @visit_fields, id: "elsewhere.visit")

      assert assert_linked(violations, "D11:", "proc_outside_visit.ex", 2) =~
               ~s|the process's id: "elsewhere.visit" is outside the application's namespace | <>
                 ~s|"clinic.", the name: of #{inspect(@domain)}|
    end
  end

  describe "X2: the accountable actor" do
    test "an actor the domain does not declare" do
      violations = pair("ProcNobody", @visit_fields, accountable: :recepton)

      assert assert_linked(violations, "X2:", "proc_nobody_visit.ex", 2) =~
               ~s|process "clinic.proc_nobody_visit": accountable :recepton is not an actor | <>
                 ~s|of #{inspect(@domain)}; did you mean :reception?|
    end

    test "control: an actor of any context, since a process module crosses them" do
      assert pair("ProcDoctor", @visit_fields, accountable: :doctor) == []
    end
  end

  describe "X5: what a stage includes" do
    test "a module that is not a compiled contract" do
      violations =
        links([{file("ProcNowhereVisit"), process("ProcNowhereVisit", "{Nowhere, :visit_done}")}])

      assert assert_linked(violations, "X5:", "proc_nowhere_visit.ex", 6) =~
               ~s|process "clinic.proc_nowhere_visit", stage :departure, includes :visit_done | <>
                 "from Nowhere, which is not a compiled contract"
    end

    test "a contract of another domain" do
      violations =
        links([
          {file("ProcForeignScheduling"),
           unit_contract("ProcForeignScheduling", @visit_fields, domain: @other)},
          {file("ProcForeignVisit"),
           process(
             "ProcForeignVisit",
             "{#{inspect(@fixtures)}.ProcForeignScheduling, :visit_completed}"
           )}
        ])

      assert assert_linked(violations, "X5:", "proc_foreign_visit.ex", 6) =~
               "a contract of domain #{inspect(@other)}, not #{inspect(@domain)}: another " <>
                 "application's events arrive only through a publish (D11)"
    end

    test "an event the contract does not declare" do
      scheduling = "ProcMissingScheduling"

      violations =
        links([
          {file(scheduling), unit_contract(scheduling, @visit_fields)},
          {file("ProcMissingVisit"),
           process(
             "ProcMissingVisit",
             "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_complete}"
           )}
        ])

      assert assert_linked(violations, "X5:", "proc_missing_visit.ex", 6) =~
               "which declares no such event (proc_missing_scheduling.ex:2); did you mean " <>
                 ":visit_completed?"
    end

    test "an event the contract receives from another application" do
      scheduling = "ProcInboundScheduling"

      extra = """
        subscribe "other.visit.moved.v1", as: :visit_moved do
          field :visit_id, :id
        end
      """

      violations =
        links([
          {file(scheduling), unit_contract(scheduling, @visit_fields, extra: extra)},
          {file("ProcInboundVisit"),
           process(
             "ProcInboundVisit",
             "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_moved}"
           )}
        ])

      assert assert_linked(violations, "X5:", "proc_inbound_visit.ex", 6) =~
               "which it receives from another application into an inbox, not into this log " <>
                 "(D12); a run across applications is assembled by EHOS"
    end

    test "an event the contract consumes from a sibling" do
      scheduling = "ProcSourceScheduling"
      relay = "ProcRelayScheduling"

      extra = "  consumes #{inspect(Module.concat(@fixtures, scheduling))}, :visit_completed\n"

      relay_source =
        relay
        |> unit_contract(@visit_fields, extra: extra)
        |> String.replace(":visit_completed, \"Wizyta zakończona\"", ":visit_noted, \"Wizyta\"")
        |> String.replace("emits: :visit_completed", "emits: :visit_noted")

      violations =
        links([
          {file(scheduling), unit_contract(scheduling, @visit_fields)},
          {file(relay), relay_source},
          {file("ProcRelayVisit"),
           process(
             "ProcRelayVisit",
             "{#{inspect(Module.concat(@fixtures, relay))}, :visit_completed}"
           )}
        ])

      assert assert_linked(violations, "X5:", "proc_relay_visit.ex", 6) =~
               "which it consumes from #{inspect(@fixtures)}.ProcSourceScheduling; include it " <>
                 "from the contract that declares it"
    end
  end

  describe "X6: what tells one run from another" do
    test "an included event without the field" do
      violations = pair("ProcNoField", "      field :room, :string")

      assert assert_linked(violations, "X6:", "proc_no_field_visit.ex", 6) =~
               ~s|process "clinic.proc_no_field_visit" includes :visit_completed and | <>
                 "correlates on :visit_id, which event :visit_completed of " <>
                 "#{inspect(@fixtures)}.ProcNoFieldScheduling (proc_no_field_scheduling.ex:9) " <>
                 "does not have"
    end

    test "a field declared optional, or personal" do
      optional = pair("ProcOptional", "      field :visit_id, :id, optional: true")

      assert assert_linked(optional, "X6:", "proc_optional_visit.ex", 6) =~
               "declares optional; a field telling which run an event belongs to cannot be"

      personal =
        pair("ProcPersonal", """
              field :visit_id, :id, personal: :patient_id
              field :patient_id, :id, subject: :patient
        """)

      assert assert_linked(personal, "X6:", "proc_personal_visit.ex", 6) =~
               "declares personal; a field telling which run an event belongs to cannot be"
    end

    test "a field that is not an identifier" do
      violations = pair("ProcRoom", @visit_fields, correlate: ":room")

      assert assert_linked(violations, "X6:", "proc_room_visit.ex", 6) =~
               "correlates on :room, which event :visit_completed of " <>
                 "#{inspect(@fixtures)}.ProcRoomScheduling (proc_room_scheduling.ex:9) has as " <>
                 ":string, not :id"
    end

    test "two included events carrying the field as two different identifiers" do
      violations = two("ProcCodes", "      field :visit_id, :other_code")

      assert assert_linked(violations, "X6:", "proc_codes_visit.ex", 6) =~
               "includes :visit_done and correlates on :visit_id, which event :visit_done of " <>
                 "#{inspect(@fixtures)}.ProcCodesDocumentation " <>
                 "(proc_codes_documentation.ex:9) has as :other_code, not :visit_code"
    end

    test "control: a domain value of :id and a plain :id are one identifier" do
      assert two("ProcValue", @visit_fields) == []
    end
  end

  describe "X7: a process's name is the application's" do
    test "two process modules of one id" do
      scheduling = "ProcTwiceScheduling"
      include = "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_completed}"

      violations =
        links([
          {file(scheduling), unit_contract(scheduling, @visit_fields)},
          {file("ProcTwiceA"), process("ProcTwiceA", include, id: "clinic.visit")},
          {file("ProcTwiceB"), process("ProcTwiceB", include, id: "clinic.visit")}
        ])

      assert assert_linked(violations, "X7:", "proc_twice_b.ex", 2) =~
               ~s|process "clinic.visit" of #{inspect(@fixtures)}.ProcTwiceB is also declared | <>
                 "by #{inspect(@fixtures)}.ProcTwiceA (proc_twice_a.ex:2); a process's name " <>
                 "keys its runs, so it is unique in the application"
    end

    test "control: a process module's id may be a contract's id, which types events, not runs" do
      scheduling = "ProcSharedScheduling"
      include = "{#{inspect(Module.concat(@fixtures, scheduling))}, :visit_completed}"

      assert links([
               {file(scheduling), unit_contract(scheduling, @visit_fields)},
               {file("ProcSharedVisit"),
                process("ProcSharedVisit", include, id: "clinic.proc_shared_scheduling")}
             ]) == []
    end
  end
end
