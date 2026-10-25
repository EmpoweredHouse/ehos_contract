defmodule EhOsContract.ContractFieldsTest do
  @moduledoc """
  v2 plan, E4: **F1–F6 of v2 §6** — the fields of every struct a contract declares —
  F7 from E8 and F10 from T1.
  Each refusal names the declaration's file and line, and has a control beside it
  that compiles.
  """

  use EhOsContract.DslCase, async: false

  defp unit(fields) do
    """
      aggregate :visit, "Visit" do
        identity :visit_id

        command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed do
    #{fields}
        end

        event :visit_closed, "Visit closed"
      end
    """
  end

  describe "F1: snake_case, unique, and not starting with __" do
    test "a unit's identity is held to a field's name, at the unit" do
      message =
        refuse_contract("IdentityForms", """
          aggregate :visit, "Visit" do
            identity [:"a|b", :__meta__, :visit_id, :visit_id]
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               ~s|F1: aggregate :visit: identity :"a\|b" is not snake_case (identity_forms.ex:4)|

      assert message =~
               "F1: aggregate :visit: identity :__meta__ starts with __, which the generated " <>
                 "struct keeps for itself"

      assert message =~ "F1: aggregate :visit: identity names :visit_id twice"
      refute message =~ ":visit_id is not snake_case"
    end

    # Plan DD, L3 (#286): an identity field may be typed as another unit's number.
    test "an identity field typed by a built-in type other than :id is refused, at the unit" do
      message =
        refuse_contract("IdentityTypes", """
          aggregate :visit, "Visit" do
            identity [:visit_id, clinic_id: :string, generated: :uuid]
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "F1: aggregate :visit: identity :clinic_id is :string; an identity field is an " <>
                 ":id, {:id, name} for another unit's or an entity's number, or a domain value " <>
                 "resting on :id (identity_types.ex:4)"

      assert message =~
               "identity :generated is :uuid; an identity field is an :id, {:id, name} for " <>
                 "another unit's or an entity's number, or a domain value resting on :id; to have " <>
                 "the library generate it, write `identity :name, generated: :uuid`"
    end

    test "a generated identity typed as another's number or by a domain value is refused" do
      for {name, type} <- [
            {"IdentityGeneratedRef", "{:id, :booking}"},
            {"IdentityGeneratedValue", ":period"}
          ] do
        message =
          refuse_contract(name, """
            aggregate :visit, "Visit" do
              identity [visit_id: #{type}], generated: :uuid
              command :open_visit, "Opening a visit", by: :reception, emits: :visit_opened, creates: true
              event :visit_opened, "Visit opened"
            end
          """)

        assert message =~
                 "F1: aggregate :visit: identity :visit_id is #{type}, and the library " <>
                   "generates the identity: a new one is a UUID, no other unit's or entity's " <>
                   "number and no domain value's"
      end
    end

    test "control: a typed identity is injected as an :id that refers to what it names" do
      compile_contract("IdentityTyped", """
        aggregate :visit_documentation, "A visit's documentation" do
          identity [:period_id, visit_id: {:id, :visit}]
          command :document, "Document", by: :reception, emits: :documented
          event :documented, "Documented"
        end
      """)

      model = EhOsContract.Model.fetch(EhOsContract.Fixtures.IdentityTyped)
      [unit] = model.units
      [command] = model.commands
      [event] = model.events

      assert unit.identity == [:period_id, :visit_id]

      for fields <- [unit.state.fields, command.fields, event.fields] do
        assert [%{name: :period_id, type: :id} = period, %{name: :visit_id} = visit] = fields
        refute Map.has_key?(period, :refers_to)
        assert %{type: :id, refers_to: :visit} = visit
      end
    end

    # #435: a key named by a domain value is held to the value's invariants, as any field.
    test "control: an identity typed by a domain value is injected with the value's type" do
      compile_contract("IdentityValue", """
        aggregate :accounting_month, "Accounting month" do
          identity [:company_id, period_id: :period]
          command :open_month, "Open a month", by: :reception, emits: :month_opened
          event :month_opened, "Month opened"
        end
      """)

      model = EhOsContract.Model.fetch(EhOsContract.Fixtures.IdentityValue)
      [unit] = model.units
      [command] = model.commands
      [event] = model.events

      assert unit.identity == [:company_id, :period_id]

      for fields <- [unit.state.fields, command.fields, event.fields] do
        assert [%{name: :company_id, type: :id}, %{name: :period_id, type: :period} = period] =
                 fields

        refute Map.has_key?(period, :refers_to)
      end
    end

    test "a field whose name is not snake_case is refused, once, and __ keeps its own refusal" do
      message =
        refuse_contract(
          "FieldForms",
          unit("""
                field :"a|b", :string
                field :Note, :string
                field :"note\\n", :string
                field :__meta__, :string
                field :note_2, :string
          """)
        )

      for {name, line} <- [{~s|:"a\|b"|, 8}, {":Note", 9}, {~s|:"note\\n"|, 10}] do
        assert message =~
                 "F1: command :close_visit: field #{name} is not snake_case (field_forms.ex:#{line})"
      end

      refute message =~ ":__meta__ is not snake_case"
      assert message =~ "field :__meta__ starts with __"
      refute message =~ ":note_2"
    end

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
                 aggregate :visit, "Visit" do
                   identity :visit_id

                   command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed do
                     field :note, :string
                   end

                   event :visit_closed, "Visit closed" do
                     field :note, :string
                   end
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
                field :twice, {:list, {:enum, [:card, card: "Card"]}}
                field :number, 42
                field :blank, {:enum, [:card, cash: " "]}
          """)
        )

      assert message =~ "F2: command :close_visit, field :none: an enum is a non-empty list"
      assert message =~ "F2: command :close_visit, field :twice: an enum repeats a member"

      assert message =~
               "F2: command :close_visit, field :number: 42 is not a type (bad_types.ex:10)"

      assert message =~
               "F2: command :close_visit, field :blank: an enum member's label is blank: :cash"
    end

    test "control: built-in types, lists, labelled enums and domain values compile" do
      assert %{commands: [%{fields: [_id | fields]}]} =
               compile_contract(
                 "GoodTypes",
                 unit("""
                       field :at, :timestamp
                       field :lines, {:list, :money}
                       field :method, {:enum, [card: "Card", cash: "Cash"]}
                       field :amount, :money
                 """)
               )

      assert Enum.map(fields, & &1.type) == [
               :timestamp,
               {:list, :money},
               {:enum, [card: "Card", cash: "Cash"]},
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
                 aggregate :visit, "Visit" do
                   identity :visit_id

                   state do
                     field :paid, :integer, default: 0
                   end

                   command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
                   event :visit_closed, "Visit closed"
                 end
               """)
    end
  end

  describe "F4: a correlation field is required and not personal" do
    test "an event's correlation field declared optional or personal is refused" do
      message =
        refuse_contract("OptionalCorrelation", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed

            event :visit_closed, "Visit closed" do
              field :patient_id, :id, subject: :patient
              field :clinic_id, :id, optional: true
              field :episode_id, :id, personal: :patient_id
            end
          end

          process_manager :chase, "Chase" do
            correlate [:visit_id, :clinic_id, :episode_id]
            starts_on :visit_closed
            ends_on :visit_closed
          end
        """)

      assert message =~
               "F4: event :visit_closed, field :clinic_id tells which run of process manager " <>
                 ":chase the event belongs to, so it cannot be optional (optional_correlation.ex:10)"

      assert message =~ "field :episode_id tells which run of process manager :chase"
      assert message =~ "so it cannot be personal (optional_correlation.ex:11)"
    end

    # Plan DD, C1 (#304): a field named twice in `correlate` is P4's to refuse, once;
    # what F4 says of it is said once too, not once per mention.
    test "a correlation field named twice is reported once" do
      message =
        refuse_contract("CorrelatedTwiceOptional", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed

            event :visit_closed, "Visit closed" do
              field :clinic_id, :id, optional: true
            end
          end

          process_manager :chase, "Chase" do
            correlate [:clinic_id, :clinic_id]
            starts_on :visit_closed
            ends_on :visit_closed
          end
        """)

      assert message =~ "P4: process manager :chase correlates on :clinic_id twice"

      assert length(String.split(message, "field :clinic_id tells which run")) == 2,
             message
    end

    test "control: an optional field outside the correlation compiles" do
      assert %{} =
               compile_contract("OptionalElsewhere", """
                 aggregate :visit, "Visit" do
                   identity :visit_id
                   command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed

                   event :visit_closed, "Visit closed" do
                     field :note, :string, optional: true
                   end
                 end

                 process_manager :chase, "Chase" do
                   correlate :visit_id
                   starts_on :visit_closed
                   ends_on :visit_closed
                 end
               """)
    end
  end

  describe "F8: a correlation field is an :id" do
    test "an event's field, or a manager's state field, of another type is refused" do
      message =
        refuse_contract("TextCorrelation", """
          aggregate :invoice, "Invoice" do
            identity :invoice_id
            command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded

            event :invoice_recorded, "Recorded" do
              field :invoice_number, :string
              field :batches, {:list, :id}
            end
          end

          process_manager :chase, "Chase" do
            correlate [:invoice_number, :batches, :reminder]

            state do
              field :reminder, {:enum, [:soft, :hard]}
            end

            starts_on :invoice_recorded
            ends_on :invoice_recorded
          end
        """)

      assert message =~
               "F8: event :invoice_recorded, field :invoice_number tells which run of process " <>
                 "manager :chase the event belongs to, so its value is part of an index key, and it " <>
                 "is :string; correlate only on an identifier, an :id of at most 255 bytes, as " <>
                 "match: does (text_correlation.ex:9)"

      assert message =~ "field :batches tells which run of process manager :chase"
      assert message =~ "is {:list, :id}; correlate only on an identifier"

      assert message =~
               "F8: process manager :chase, state, field :reminder is what it correlates on"
    end

    test "a manager's undeclared correlation typed by an event it does not handle is refused" do
      # The manager's state takes the type of the first local event with the field, handled
      # or not, and a sibling's event with that field of that type then passes X6.
      message =
        refuse_contract("UnhandledCorrelation", """
          aggregate :invoice, "Invoice" do
            identity :invoice_id
            command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded
            command :note_invoice, "Note", by: :reception, emits: :invoice_noted

            event :invoice_recorded, "Recorded"

            event :invoice_noted, "Note" do
              field :ref, :string
            end
          end

          process_manager :chase, "Chase" do
            correlate :ref
            starts_on :invoice_recorded
            ends_on :invoice_recorded
          end
        """)

      assert message =~
               "F8: event :invoice_noted, field :ref gives process manager :chase's state the " <>
                 "type of what it correlates on, so its value is part of an index key, and it " <>
                 "is :string"
    end

    test "control: a later event's field gives a manager's undeclared correlation nothing" do
      assert %{} =
               compile_contract("LaterCorrelation", """
                 aggregate :invoice, "Invoice" do
                   identity :invoice_id
                   command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded
                   command :note_invoice, "Note", by: :reception, emits: :invoice_noted

                   event :invoice_recorded, "Recorded" do
                     field :ref, :id
                   end

                   event :invoice_noted, "Note" do
                     field :ref, :string
                   end
                 end

                 process_manager :chase, "Chase" do
                   correlate :ref
                   starts_on :invoice_recorded
                   ends_on :invoice_recorded
                 end
               """)
    end

    test "control: an earlier unit's identity types a manager's undeclared correlation" do
      assert %{} =
               compile_contract("IdentityCorrelation", """
                 aggregate :invoice, "Invoice" do
                   identity :invoice_id
                   command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded
                   event :invoice_recorded, "Recorded" do
                     field :batch_id, :id
                   end
                 end

                 aggregate :payment, "Payment" do
                   identity :payment_id
                   command :record_payment, "Payment", by: :reception, emits: :payment_recorded

                   event :payment_recorded, "Paid" do
                     field :batch_id, :id
                     field :invoice_id, :string
                   end
                 end

                 process_manager :chase, "Chase" do
                   correlate :invoice_id
                   starts_on :invoice_recorded
                   ends_on :invoice_recorded
                 end
               """)
    end

    test "a handled event that also types a manager's correlation is one finding" do
      message =
        refuse_contract("HandledAndTyping", """
          aggregate :invoice, "Invoice" do
            identity :invoice_id
            command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded

            event :invoice_recorded, "Recorded" do
              field :ref, :string
            end
          end

          process_manager :chase, "Chase" do
            correlate :ref
            starts_on :invoice_recorded
            ends_on :invoice_recorded
          end
        """)

      assert [_one] = Regex.scan(~r/F8: event :invoice_recorded, field :ref/u, message)
    end

    test "control: an :id, an entity's identifier and a domain value compile here" do
      assert %{} =
               compile_contract("IdCorrelation", """
                 aggregate :invoice, "Invoice" do
                   identity :invoice_id
                   command :record_invoice, "Invoice", by: :reception, emits: :invoice_recorded

                   event :invoice_recorded, "Recorded" do
                     field :clinic_id, {:id, :clinic}
                     field :period, :period
                     field :batch_id, :id
                   end
                 end

                 process_manager :chase, "Chase" do
                   correlate [:invoice_id, :clinic_id, :period, :batch_id]
                   starts_on :invoice_recorded
                   ends_on :invoice_recorded
                 end
               """)
    end
  end

  describe "F9: a key of at most six fields" do
    test "an identity and a manager's correlate of seven are refused" do
      seven = "[:a_id, :b_id, :c_id, :d_id, :e_id, :f_id, :g_id]"

      message =
        refuse_contract("SevenFields", """
          aggregate :ledger, "Ledger" do
            identity #{seven}
            command :open_ledger, "Opening", by: :reception, emits: :ledger_opened
            event :ledger_opened, "Opened"
          end

          process_manager :chase, "Chase" do
            correlate #{seven}
            starts_on :ledger_opened
            ends_on :ledger_opened
          end
        """)

      assert message =~
               "F9: aggregate :ledger: identity has 7 fields, and a key has at most 6: it is " <>
                 "one index entry, which more fields of an :id at its bound would overflow " <>
                 "(seven_fields.ex:4)"

      assert message =~ "F9: process manager :chase: correlate has 7 fields"
    end

    test "control: six fields compile" do
      six = "[:a_id, :b_id, :c_id, :d_id, :e_id, :f_id]"

      assert %{} =
               compile_contract("SixFields", """
                 aggregate :ledger, "Ledger" do
                   identity #{six}
                   command :open_ledger, "Opening", by: :reception, emits: :ledger_opened
                   event :ledger_opened, "Opened"
                 end

                 process_manager :chase, "Chase" do
                   correlate #{six}
                   starts_on :ledger_opened
                   ends_on :ledger_opened
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
        aggregate :visit, "Visit" do
          identity :visit_id

          command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed

          event :visit_closed, "Visit closed" do
            field :patient_id, :id, subject: :patient
            field :name, :string, personal: :patient_id
          end
        end

        process_manager :chase, "Chasing the documentation" do
          correlate :visit_id

          state do
      #{state}
          end

          starts_on :visit_closed
        end

        read_model :visits, "Visits", projects: :visit_closed do
          field :patient_id, :id, subject: :patient
          field :name, :string, personal: :patient_id
        end

        query :visits_of, "A patient's visits", reads: :visits, by: :reception do
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
                 "(personal_outside.ex:20)"
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
          aggregate :visit, "Visit" do
            identity :visit_id

            state do
              field :visit_id, :id
            end

            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed do
              field :visit_id, :id
            end

            event :visit_closed, "Visit closed" do
              field :visit_id, :id
            end
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

  describe "F10: supplied_by: :host only where a request would fill the field" do
    @supplied "supplied_by: :host"

    # Line 4 of the file is the first line of the body: the state's field is at line 8,
    # the scope at 13, the command's field at 14, the decided event's at 18 and the
    # recorded event's at 22.
    defp supplied(state, scope, command, decided, recorded) do
      """
        aggregate :visit, "Visit" do
          identity :visit_id

          state do
            field :notes, :integer, default: 0#{state}
          end

          command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed,
            scope: :clinic_id do
            field :clinic_id, :id#{scope}
            field :reported_to_registry, :boolean#{command}
          end

          event :visit_closed, "Visit closed" do
            field :reported_to_registry, :boolean#{decided}
          end

          event :patient_arrived, "Patient arrived", recorded_by: :reception do
            field :arrived_at, :timestamp#{recorded}
          end
        end
      """
    end

    test "a state's field, a command's scope, and an event no actor records" do
      on = ", " <> @supplied
      message = refuse_contract("SuppliedWrong", supplied(on, on, "", on, ""))

      assert message =~
               "F10: aggregate :visit, state, field :notes is supplied_by: :host, and only a " <>
                 "command's field or a recorded event's (recorded_by:) is one a request fills, " <>
                 "which the host can fill instead (supplied_wrong.ex:8)"

      assert message =~
               "F10: command :close_visit, field :clinic_id is its scope, and is supplied_by: " <>
                 ":host: the authorization decision reads the scope's value before the host " <>
                 "supplies anything (supplied_wrong.ex:13)"

      assert message =~
               "F10: event :visit_closed, field :reported_to_registry is supplied_by: :host, and only " <>
                 "a command's field or a recorded event's (recorded_by:) is one a request fills, " <>
                 "which the host can fill instead (supplied_wrong.ex:18)"
    end

    test "control: a command's field and a recorded event's, kept in the model only there" do
      on = ", " <> @supplied
      model = compile_contract("SuppliedRight", supplied("", "", on, "", on))

      field = fn fields, name -> Enum.find(fields, &(&1.name == name)) end
      [command] = model.commands
      decided = Enum.find(model.events, &(&1.name == :visit_closed))

      assert field.(command.fields, :reported_to_registry).supplied_by == :host

      refute Map.has_key?(field.(decided.fields, :reported_to_registry), :supplied_by),
             "a field without supplied_by: has no key, so no contract written before T1 moves"
    end
  end
end
