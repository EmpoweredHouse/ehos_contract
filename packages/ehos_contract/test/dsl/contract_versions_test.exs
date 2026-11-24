defmodule EhosContract.ContractVersionsTest do
  @moduledoc """
  Plan DD, V1 (#333): **U1–U4** — the steps (`upcast`) that read a row written with an
  older version of an event's fields in the current one. Each refusal names the
  declaration's file and line, and has a control beside it that compiles.
  """

  use EhosContract.DslCase, async: false

  # A demand for a computer, whose reason was renamed and whose priority is new.
  defp demand(event) do
    """
      aggregate :demand, "Request" do
        identity :demand_id

        command :open_demand, "Open a request", by: :employee, emits: :demand_opened

    #{event}
      end
    """
  end

  describe "control" do
    test "the steps compile into the event's model, in the order of their versions" do
      model =
        compile_contract(
          "VersionsRight",
          demand("""
              event :demand_opened, "Request opened", schema_version: 3 do
                field :patient_id, :id, subject: :patient
                field :note, :string, personal: :patient_id, optional: true
                field :demand_reason, :string
                field :priority, :string
                field :opened_on, :date, optional: true

                upcast from: 2, rename: [why: :demand_reason], default: [opened_on: ~D[2026-01-01]]
                upcast from: 1, rename: [reason: :why, remark: :note], default: [priority: :normal]
              end
          """)
        )

      [event] = model.events

      assert event.upcasts == [
               %{from: 1, rename: %{reason: :why, remark: :note}, default: %{priority: "normal"}},
               %{from: 2, rename: %{why: :demand_reason}, default: %{opened_on: "2026-01-01"}}
             ]
    end

    test "an event at its first version has no steps, and keeps none in its model" do
      model =
        compile_contract("VersionsNone", demand(~s(    event :demand_opened, "Open")))

      refute Map.has_key?(hd(model.events), :upcasts)
    end

    test "a step with neither a rename nor a default says the fields kept their shape" do
      model =
        compile_contract(
          "VersionsEmpty",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                upcast from: 1
              end
          """)
        )

      assert hd(model.events).upcasts == [%{from: 1, rename: %{}, default: %{}}]
    end
  end

  describe "U1: a step per version below the current one" do
    test "a version without its step is refused" do
      message =
        refuse_contract(
          "VersionsMissing",
          demand("""
              event :demand_opened, "Open", schema_version: 3 do
                upcast from: 2
              end
          """)
        )

      assert message =~
               "U1: event :demand_opened is at schema_version 3 and has no `upcast from: 1`"

      assert message =~ "(versions_missing.ex:"
    end

    test "an event raised to version 2 with no step at all is refused" do
      message =
        refuse_contract(
          "VersionsNoStep",
          demand(~s(    event :demand_opened, "Open", schema_version: 2))
        )

      assert message =~
               "U1: event :demand_opened is at schema_version 2 and has no `upcast from: 1`"
    end

    test "two steps from one version, and a step from the current one, are refused" do
      message =
        refuse_contract(
          "VersionsTwice",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                upcast from: 1
                upcast from: 1
                upcast from: 2
              end
          """)
        )

      assert message =~ "U1: event :demand_opened has 2 steps `upcast from: 1`"
      assert message =~ "U1: event :demand_opened has `upcast from: 2`, and its fields are at"
    end
  end

  describe "U2: a step leads to the fields the event has" do
    test "a rename or a default to a field the event will not have is refused" do
      message =
        refuse_contract(
          "VersionsUnknown",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :demand_reason, :string

                upcast from: 1, rename: [reason: :demand_reasn], default: [priority: "normal"]
              end
          """)
        )

      assert message =~
               "U2: event :demand_opened, `upcast from: 1` renames a field to :demand_reasn, " <>
                 "which is neither a field of the event nor a name a later step renames"

      assert message =~ "`upcast from: 1` gives a default to :priority"
    end

    test "a name a later step renames is a target an earlier step may lead to" do
      compile_contract(
        "VersionsChain",
        demand("""
            event :demand_opened, "Open", schema_version: 3 do
              field :demand_reason, :string

              upcast from: 1, rename: [reason: :why]
              upcast from: 2, rename: [why: :demand_reason]
            end
        """)
      )
    end

    test "a rename to itself, to what is not a name, or of two fields to one is refused" do
      message =
        refuse_contract(
          "VersionsBadRename",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :demand_reason, :string

                upcast from: 1,
                  rename: [demand_reason: :demand_reason, reason: :demand_reason, why: "text"]
              end
          """)
        )

      assert message =~ "renames :demand_reason to itself"
      assert message =~ "renames 2 fields to :demand_reason; a field has one old name"
      assert message =~ ~s(renames :why to "text", which is not a field's name)
    end
  end

  describe "U3: the identity and personal data" do
    test "renaming the identity, or giving it or a personal field a default, is refused" do
      message =
        refuse_contract(
          "VersionsIdentity",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :patient_id, :id, subject: :patient
                field :note, :string, personal: :patient_id

                upcast from: 1, rename: [id: :demand_id], default: [demand_id: "x", note: "none"]
              end
          """)
        )

      assert message =~
               "U3: event :demand_opened, `upcast from: 1` renames :id to the unit's identity, " <>
                 ":demand_id; every row of a stream holds it"

      assert message =~ "`upcast from: 1` gives a default to the unit's identity, :demand_id"
      assert message =~ "gives a default to the personal field :note"
    end

    test "renaming a personal field compiles: its seal opens under its old name" do
      compile_contract(
        "VersionsPersonal",
        demand("""
            event :demand_opened, "Open", schema_version: 2 do
              field :patient_id, :id, subject: :patient
              field :note, :string, personal: :patient_id

              upcast from: 1, rename: [remark: :note]
            end
        """)
      )
    end
  end

  describe "U2, U3 and U4: what the review of V1 found" do
    test "an old name renamed twice in one step is refused" do
      message =
        refuse_contract(
          "VersionsTwiceOld",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :demand_reason, :string
                field :why, :string

                upcast from: 1, rename: [reason: :why, reason: :demand_reason]
              end
          """)
        )

      assert message =~ "U2: event :demand_opened, `upcast from: 1` renames :reason 2 times"
    end

    test "a field the log tags rows with is not renamed onto or defaulted; control: an optional one" do
      message =
        refuse_contract(
          "VersionsTagged",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :company_id, :id
                field :opened_on, :date

                upcast from: 1, rename: [company_ref: :company_id], default: [opened_on: ~D[2026-01-01]]
              end
          """)
        )

      assert message =~
               "U3: event :demand_opened, `upcast from: 1` renames :company_ref to :company_id, " <>
                 "which the log tags each row with"

      assert message =~ "gives a default to :opened_on, which the log tags each row with"

      compile_contract(
        "VersionsUntagged",
        demand("""
            event :demand_opened, "Open", schema_version: 2 do
              field :company_id, :id, optional: true

              upcast from: 1, rename: [company_ref: :company_id]
            end
        """)
      )
    end

    test "a default reaching a personal field through a later rename is refused" do
      message =
        refuse_contract(
          "VersionsLaterPersonal",
          demand("""
              event :demand_opened, "Open", schema_version: 3 do
                field :patient_id, :id, subject: :patient
                field :note, :string, personal: :patient_id, optional: true

                upcast from: 1, default: [remark: "none"]
                upcast from: 2, rename: [remark: :note]
              end
          """)
        )

      assert message =~
               "U3: event :demand_opened, `upcast from: 1` gives a default to the personal field " <>
                 ":remark (:note now)"
    end

    test "one field given two defaults in a step is refused; control: nil for an optional one" do
      message =
        refuse_contract(
          "VersionsDefaultTwice",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :priority, :string

                upcast from: 1, default: [priority: "normal", priority: "high"]
              end
          """)
        )

      assert message =~ "U2: event :demand_opened, `upcast from: 1` gives :priority 2 defaults"

      compile_contract(
        "VersionsNilOptional",
        demand("""
            event :demand_opened, "Open", schema_version: 2 do
              field :note, :string, optional: true

              upcast from: 1, default: [note: nil]
            end
        """)
      )
    end

    test "a default that is not a value of its field is refused; control: one that is" do
      message =
        refuse_contract(
          "VersionsBadDefault",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :priority, :string
                field :count, :integer
                field :plan, {:enum, [:basic, :full]}

                upcast from: 1, default: [priority: 1, count: nil, plan: :gold]
              end
          """)
        )

      assert message =~
               "U4: event :demand_opened, `upcast from: 1` gives :priority the default 1, which is not a value of :string"

      assert message =~ "gives :count the default nil"
      assert message =~ "gives :plan the default :gold"

      compile_contract(
        "VersionsGoodDefault",
        demand("""
            event :demand_opened, "Open", schema_version: 2 do
              field :priority, :string
              field :count, :integer
              field :plan, {:enum, [:basic, :full]}

              upcast from: 1, default: [priority: "normal", count: 0, plan: :basic]
            end
        """)
      )
    end
  end

  # Plan DD, V2 (#338): a step by a function of the unit's implementation.
  describe "a step by a function" do
    test "a function step that renames or gives defaults too is refused" do
      message =
        refuse_contract(
          "VersionsFunctionAndRename",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :demand_reason, :string

                upcast from: 1, function: :from_one, rename: [reason: :demand_reason]
              end
          """)
        )

      assert message =~
               "U2: event :demand_opened, `upcast from: 1` names the function :from_one and " <>
                 "renames or gives defaults too"
    end

    test "a function named like a command of the unit is refused" do
      message =
        refuse_contract(
          "VersionsFunctionCommand",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                upcast from: 1, function: :open_demand
              end
          """)
        )

      assert message =~
               "U2: event :demand_opened, `upcast from: 1` names the function :open_demand, " <>
                 "the name of a command of the unit"
    end

    test "a function named like what the implementation imports is refused" do
      message =
        refuse_contract(
          "VersionsFunctionEmit",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                upcast from: 1, function: :emit
              end
          """)
        )

      assert message =~ "names the function :emit, which the implementation imports"
    end

    test "a step before a function is judged by its own names: onto a tagged field, refused" do
      message =
        refuse_contract(
          "VersionsBeforeFunctionTagged",
          demand("""
              event :demand_opened, "Open", schema_version: 3 do
                field :company_id, :id

                upcast from: 1, rename: [company_ref: :company_id]
                upcast from: 2, function: :from_two
              end
          """)
        )

      assert message =~
               "U3: event :demand_opened, `upcast from: 1` renames :company_ref to :company_id"
    end

    test "a step before a function is not held to the names it leads to" do
      compile_contract(
        "VersionsBeforeFunction",
        demand("""
            event :demand_opened, "Open", schema_version: 3 do
              field :demand_reason, :string

              upcast from: 1, rename: [reason: :why]
              upcast from: 2, function: :from_two
            end
        """)
      )
    end

    test "the implementation must define the function, and is shown the clause (I2)" do
      model =
        compile_contract(
          "VersionsFunction",
          demand("""
              event :demand_opened, "Open", schema_version: 2 do
                field :amount, :decimal

                upcast from: 1, function: :amount_from_minor
              end
          """)
        )

      assert hd(model.events).upcasts == [%{from: 1, function: :amount_from_minor}]

      error =
        assert_raise(CompileError, fn ->
          compile(
            """
            defmodule EhosContract.Fixtures.VersionsFunctionImpl do
            use EhosContract.Fixtures.VersionsFunction, aggregate: :demand

            @impl true
            def open_demand(_command, _state), do: {:ok, []}
            end
            """,
            "versions_function_impl.ex"
          )
        end)

      assert Exception.message(error) =~
               "I2: EhosContract.Fixtures.VersionsFunctionImpl does not define amount_from_minor/1"

      assert Exception.message(error) =~ "def amount_from_minor(data) do"
    end
  end
end
