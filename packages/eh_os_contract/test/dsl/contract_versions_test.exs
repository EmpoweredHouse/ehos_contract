defmodule EhOsContract.ContractVersionsTest do
  @moduledoc """
  Plan DD, V1 (#333): **V1–V3** — the steps (`upcast`) that read a row written with an
  older version of an event's fields in the current one. Each refusal names the
  declaration's file and line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  # A demand for a computer, whose reason was renamed and whose priority is new.
  defp demand(event) do
    """
      aggregate :demand, "Zapotrzebowanie" do
        identity :demand_id

        command :open_demand, "Otwórz zapotrzebowanie", by: :employee, emits: :demand_opened

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
              event :demand_opened, "Zapotrzebowanie otwarte", schema_version: 3 do
                field :patient_id, :id, subject: :patient
                field :note, :string, personal: :patient_id, optional: true
                field :demand_reason, :string
                field :priority, :string
                field :opened_on, :date

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
        compile_contract("VersionsNone", demand(~s(    event :demand_opened, "Otwarte")))

      refute Map.has_key?(hd(model.events), :upcasts)
    end

    test "a step with neither a rename nor a default says the fields kept their shape" do
      model =
        compile_contract(
          "VersionsEmpty",
          demand("""
              event :demand_opened, "Otwarte", schema_version: 2 do
                upcast from: 1
              end
          """)
        )

      assert hd(model.events).upcasts == [%{from: 1, rename: %{}, default: %{}}]
    end
  end

  describe "V1: a step per version below the current one" do
    test "a version without its step is refused" do
      message =
        refuse_contract(
          "VersionsMissing",
          demand("""
              event :demand_opened, "Otwarte", schema_version: 3 do
                upcast from: 2
              end
          """)
        )

      assert message =~
               "V1: event :demand_opened is at schema_version 3 and has no `upcast from: 1`"

      assert message =~ "(versions_missing.ex:"
    end

    test "an event raised to version 2 with no step at all is refused" do
      message =
        refuse_contract(
          "VersionsNoStep",
          demand(~s(    event :demand_opened, "Otwarte", schema_version: 2))
        )

      assert message =~
               "V1: event :demand_opened is at schema_version 2 and has no `upcast from: 1`"
    end

    test "two steps from one version, and a step from the current one, are refused" do
      message =
        refuse_contract(
          "VersionsTwice",
          demand("""
              event :demand_opened, "Otwarte", schema_version: 2 do
                upcast from: 1
                upcast from: 1
                upcast from: 2
              end
          """)
        )

      assert message =~ "V1: event :demand_opened has 2 steps `upcast from: 1`"
      assert message =~ "V1: event :demand_opened has `upcast from: 2`, and its fields are at"
    end
  end

  describe "V2: a step leads to the fields the event has" do
    test "a rename or a default to a field the event will not have is refused" do
      message =
        refuse_contract(
          "VersionsUnknown",
          demand("""
              event :demand_opened, "Otwarte", schema_version: 2 do
                field :demand_reason, :string

                upcast from: 1, rename: [reason: :demand_reasn], default: [priority: "normal"]
              end
          """)
        )

      assert message =~
               "V2: event :demand_opened, `upcast from: 1` renames a field to :demand_reasn, " <>
                 "which is neither a field of the event nor a name a later step renames"

      assert message =~ "`upcast from: 1` gives a default to :priority"
    end

    test "a name a later step renames is a target an earlier step may lead to" do
      compile_contract(
        "VersionsChain",
        demand("""
            event :demand_opened, "Otwarte", schema_version: 3 do
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
              event :demand_opened, "Otwarte", schema_version: 2 do
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

  describe "V3: the identity and personal data" do
    test "renaming the identity, or giving it or a personal field a default, is refused" do
      message =
        refuse_contract(
          "VersionsIdentity",
          demand("""
              event :demand_opened, "Otwarte", schema_version: 2 do
                field :patient_id, :id, subject: :patient
                field :note, :string, personal: :patient_id

                upcast from: 1, rename: [id: :demand_id], default: [demand_id: "x", note: "brak"]
              end
          """)
        )

      assert message =~
               "V3: event :demand_opened, `upcast from: 1` renames :id to :demand_id, and the " <>
                 "unit's identity is never renamed"

      assert message =~ "gives the identity field :demand_id a default"
      assert message =~ "gives the personal field :note a default"
    end

    test "renaming a personal field compiles: its seal opens under its old name" do
      compile_contract(
        "VersionsPersonal",
        demand("""
            event :demand_opened, "Otwarte", schema_version: 2 do
              field :patient_id, :id, subject: :patient
              field :note, :string, personal: :patient_id

              upcast from: 1, rename: [remark: :note]
            end
        """)
      )
    end
  end
end
