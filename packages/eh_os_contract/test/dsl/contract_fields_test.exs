defmodule EhOsContract.Next.ContractFieldsTest do
  @moduledoc """
  v2 plan, E4: **F1–F6 of v2 §6** — the fields of every struct a contract declares —
  and F7 from E8.
  Each refusal names the declaration's file and line, and has a control beside it
  that compiles.
  """

  use EhOsContract.DslCase, async: false

  defp unit(fields) do
    """
      aggregate :visit, "Wizyta" do
        identity :visit_id

        command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed do
    #{fields}
        end

        event :visit_closed, "Wizyta zamknięta", terminal: true
      end

      process :visit, "Wizyta" do
        correlate :visit_id
      end
    """
  end

  describe "F1: unique, and not starting with __" do
    test "a field declared twice, and one the generated struct keeps" do
      message =
        refuse_contract(
          "FieldTwice",
          unit("""
                field :note, :string
                field :note, :string
                field :__meta__, :string
          """)
        )

      assert message =~ "F1: command :close_visit declares field :note twice (field_twice.ex:9)"

      assert message =~
               "F1: command :close_visit: field :__meta__ starts with __, which the generated struct " <>
                 "keeps for itself (field_twice.ex:10)"
    end

    test "control: the same name in two structs is two fields" do
      assert %{} =
               compile_contract("FieldInTwoStructs", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id

                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed do
                     field :note, :string
                   end

                   event :visit_closed, "Wizyta zamknięta", terminal: true do
                     field :note, :string
                   end
                 end

                 process :visit, "Wizyta" do
                   correlate :visit_id
                 end
               """)
    end
  end

  describe "F2: well-formed types" do
    test "an empty enum, a repeated member, and something that is not a type" do
      message =
        refuse_contract(
          "BadTypes",
          unit("""
                field :none, {:enum, []}
                field :twice, {:list, {:enum, [:card, card: "Karta"]}}
                field :number, 42
          """)
        )

      assert message =~ "F2: command :close_visit, field :none: an enum is a non-empty list"
      assert message =~ "F2: command :close_visit, field :twice: an enum repeats a member"

      assert message =~
               "F2: command :close_visit, field :number: 42 is not a type (bad_types.ex:10)"
    end

    test "control: built-in types, lists, labelled enums and domain values compile" do
      assert %{commands: [%{fields: [_id | fields]}]} =
               compile_contract(
                 "GoodTypes",
                 unit("""
                       field :at, :timestamp
                       field :lines, {:list, :money}
                       field :method, {:enum, [card: "Karta", cash: "Gotówka"]}
                       field :amount, :money
                 """)
               )

      assert Enum.map(fields, & &1.type) == [
               :timestamp,
               {:list, :money},
               {:enum, [card: "Karta", cash: "Gotówka"]},
               :money
             ]
    end
  end

  describe "F3: a default only in a state" do
    test "a command field with a default is refused" do
      message =
        refuse_contract("DefaultInCommand", unit("      field :paid, :integer, default: 0"))

      assert message =~
               "F3: command :close_visit, field :paid has a default, which only a state may have " <>
                 "(default_in_command.ex:8)"
    end

    test "control: a state field with one compiles" do
      assert %{units: [%{state: %{fields: [_id, %{name: :paid, default: 0}]}}]} =
               compile_contract("DefaultInState", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id

                   state do
                     field :paid, :integer, default: 0
                   end

                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
                   event :visit_closed, "Wizyta zamknięta", terminal: true
                 end

                 process :visit, "Wizyta" do
                   correlate :visit_id
                 end
               """)
    end
  end

  describe "F4: a correlation field is required and not personal" do
    test "an event's correlation field declared optional or personal is refused" do
      message =
        refuse_contract("OptionalCorrelation", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

            event :visit_closed, "Wizyta zamknięta", terminal: true do
              field :patient_id, :id, subject: :patient
              field :clinic_id, :id, optional: true
              field :episode_id, :id, personal: :patient_id
            end
          end

          process :visit, "Wizyta" do
            correlate [:visit_id, :clinic_id, :episode_id]
          end
        """)

      assert message =~
               "F4: event :visit_closed, field :clinic_id tells which run of process :visit the " <>
                 "event belongs to, so it cannot be optional (optional_correlation.ex:10)"

      assert message =~ "field :episode_id tells which run of process :visit"
      assert message =~ "so it cannot be personal (optional_correlation.ex:11)"
    end

    test "control: an optional field outside the correlation compiles" do
      assert %{} =
               compile_contract("OptionalElsewhere", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id
                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

                   event :visit_closed, "Wizyta zamknięta", terminal: true do
                     field :note, :string, optional: true
                   end
                 end

                 process :visit, "Wizyta" do
                   correlate :visit_id
                 end
               """)
    end
  end

  describe "F5: personal data names a subject's identifier in the same struct" do
    test "a missing, optional or subject-less identifier is refused" do
      message =
        refuse_contract(
          "PersonalWrong",
          unit("""
                field :patient_id, :id, subject: :patient
                field :carer_id, :id, optional: true, subject: :patient
                field :clinic_id, :id
                field :name, :string, personal: :nobody
                field :phone, :string, personal: :carer_id
                field :address, :string, personal: :clinic_id
          """)
        )

      assert message =~
               "F5: command :close_visit, field :name is personal to :nobody, which is not a field " <>
                 "declared here (personal_wrong.ex:11)"

      assert message =~
               "field :phone is personal to :carer_id, which is optional (personal_wrong.ex:12)"

      assert message =~
               "field :address is personal to :clinic_id, which is not an :id field declaring a " <>
                 "subject (personal_wrong.ex:13)"
    end

    test "control: personal to a required subject identifier compiles" do
      assert %{} =
               compile_contract(
                 "PersonalRight",
                 unit("""
                       field :patient_id, :id, subject: :patient
                       field :name, :string, personal: :patient_id
                 """)
               )
    end

    test "control: personal to a subject identifier that is an entity's compiles" do
      # Stored as an :id, like any subject identifier (plan EM2).
      assert %{} =
               compile_contract(
                 "PersonalToEntity",
                 unit("""
                       field :patient_id, {:id, :patient_card}, subject: :patient
                       field :name, :string, personal: :patient_id
                 """)
               )
    end
  end

  describe "F7: nothing personal where the library keeps it outside the log" do
    # Line 4 of the file is the first line of the body.
    defp outside(state, params, scope) do
      """
        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

          event :visit_closed, "Wizyta zamknięta", terminal: true do
            field :patient_id, :id, subject: :patient
            field :name, :string, personal: :patient_id
          end
        end

        process :visit, "Wizyta" do
          correlate :visit_id
        end

        process_manager :chase, "Pogoń za dokumentacją" do
          correlate :visit_id

          state do
      #{state}
          end

          starts_on :visit_closed
        end

        read_model :visits, "Wizyty", projects: :visit_closed do
          field :patient_id, :id, subject: :patient
          field :name, :string, personal: :patient_id
        end

        query :visits_of, "Wizyty pacjenta", reads: :visits, by: :reception do
      #{params}
          scope #{inspect(scope)}
        end
      """
    end

    # A query's parameter takes no `personal:` at all, so its scope is caught only
    # when it is of a domain value that holds personal data: L3, in
    # `contract_links_domain_test.exs`.
    test "a process manager's state" do
      message =
        refuse_contract(
          "PersonalOutside",
          outside(
            """
                  field :patient_id, :id, subject: :patient
                  field :phone, :string, personal: :patient_id
            """,
            """
                  param :patient_id, :id
            """,
            :patient_id
          )
        )

      assert message =~
               "F7: process manager :chase, state, field :phone is personal, and a process " <>
                 "manager's state is stored outside the log, where erasure cannot reach it " <>
                 "(personal_outside.ex:24)"
    end

    test "control: personal in an event and in a read model's row" do
      assert %{} =
               compile_contract(
                 "PersonalInside",
                 outside(
                   """
                         field :patient_id, :id, subject: :patient
                   """,
                   """
                         param :patient_id, :id
                   """,
                   :patient_id
                 )
               )
    end
  end

  describe "F6: an injected identity field is not declared again" do
    test "in a command, an event and the state" do
      message =
        refuse_contract("IdentityAgain", """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            state do
              field :visit_id, :id
            end

            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed do
              field :visit_id, :id
            end

            event :visit_closed, "Wizyta zamknięta", terminal: true do
              field :visit_id, :id
            end
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "F6: aggregate :visit, state declares :visit_id, which the unit's identity already " <>
                 "injects (identity_again.ex:8)"

      assert message =~ "F6: command :close_visit declares :visit_id, which"
      assert message =~ "(identity_again.ex:12)"
      assert message =~ "F6: event :visit_closed declares :visit_id"
      assert message =~ "(identity_again.ex:16)"
    end
  end
end
