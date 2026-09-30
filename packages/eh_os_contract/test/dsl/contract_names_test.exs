defmodule EhOsContract.ContractNamesTest do
  @moduledoc """
  v2 plan, E4: **N1 and N2 of v2 §6** — what a contract's names may not be. Each
  refusal names the declaration's file and line, and has a control beside it that
  compiles.
  """

  use EhOsContract.DslCase, async: false

  @valid """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
      event :visit_closed, "Wizyta zamknięta", terminal: true
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end
  """

  test "control: a contract with none of these problems compiles" do
    assert %{version: _} = compile_contract("NamesValid", @valid)
  end

  describe "N1: snake_case" do
    test "a name that is not is refused, whatever it names" do
      message =
        refuse_contract("NotSnakeCase", """
          aggregate :Visit, "Wizyta" do
            identity :visit_id
            command :closeVisit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~ "N1: aggregate :Visit is not snake_case (not_snake_case.ex:4)"
      assert message =~ "N1: command :closeVisit is not snake_case (not_snake_case.ex:6)"
    end

    test "a name ending in a newline is refused, since it becomes a capability" do
      message =
        refuse_contract("NewlineName", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :"close\n", "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~ ~s|N1: command :"close\\n" is not snake_case (newline_name.ex:6)|
    end
  end

  describe "N1: one name per namespace" do
    test "two units of one name, an aggregate and a dcb" do
      message =
        refuse_contract("TwoUnits", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          dcb :visit, "Wizyta 2" do
            identity :visit_id
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~ "N1: two units are named :visit (two_units.ex:10)"
    end

    test "a command and an event share a namespace with timers and consumed events" do
      message =
        refuse_contract("SharedNamespace", """
          consumes Clinic.Contracts.Booking, :visit_booked, as: [visit_booked: :close_visit]

          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
            event :close_visit, "Wizyta zamknięta 2", terminal: true
          end

          process_manager :chase, "Pogoń", correlate: :visit_id do
            starts_on :visit_closed, sets: :visit_closed
            timer :visit_closed, wait: {1, :day}
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N1: event :close_visit has the name of a command; commands, events, timers and " <>
                 "consumed events share one namespace (shared_namespace.ex:10)"

      assert message =~ "N1: timer :visit_closed has the name of an event"
      assert message =~ "(shared_namespace.ex:15)"
      assert message =~ "N1: consumed event :close_visit has the name of a command"
      assert message =~ "(shared_namespace.ex:4)"
    end

    test "invariants and stage groups within a unit, stages and promises within the process" do
      message =
        refuse_contract("Nested", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            invariant :paid, "Zapłacono"
            invariant :paid, "Zapłacono 2"
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

            stage :closing do
              event :visit_closed, "Wizyta zamknięta", terminal: true
            end

            stage :closing do
            end
          end

          process :visit, "Wizyta" do
            correlate :visit_id
            stage :closing
            stage :closing

            promise :closed do
              from :visit_closed
              eventually :visit_closed
            end

            promise :closed do
              from :visit_closed
              eventually :visit_closed
            end
          end
        """)

      assert message =~ "N1: aggregate :visit has two invariants named :paid (nested.ex:7)"
      assert message =~ "N1: aggregate :visit groups stage :closing twice (nested.ex:14)"
      assert message =~ "N1: process :visit has two stages named :closing (nested.ex:21)"
      assert message =~ "N1: process :visit has two promises named :closed (nested.ex:28)"
    end

    test "two names that camelize alike, where the name is a module or an alias" do
      message =
        refuse_contract("CamelizeAlike", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: [:visit_closed, :visit_closed_]
            command :close_visit_2, "Zamknięcie 2", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
            event :visit_closed_, "Wizyta zamknięta 2", terminal: true
          end

          read_model :closed_visits, "Zamknięte wizyty", projects: :visit_closed do
            field :closed_on, :date
          end

          read_model :closed__visits, "Zamknięte wizyty 2", projects: :visit_closed do
            field :closed_on, :date
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N1: event :visit_closed_ camelizes to VisitClosed, as event :visit_closed does, " <>
                 "and an implementation would alias both as VisitClosed; rename one of them " <>
                 "(camelize_alike.ex:9)"

      assert message =~
               "N1: :closed__visits camelizes to ClosedVisits, as :closed_visits does, and two " <>
                 "read models would be one generated module; rename one of them (camelize_alike.ex:16)"

      refute message =~ ":close_visit_2 camelizes"
    end

    test "control: names that camelize differently compile" do
      assert %{version: _} =
               compile_contract("CamelizeApart", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id
                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
                   command :close_visit2, "Zamknięcie 2", by: :reception, emits: :visit_closed
                   event :visit_closed, "Wizyta zamknięta", terminal: true
                 end

                 process :visit, "Wizyta" do
                   correlate :visit_id
                 end
               """)
    end

    test "a query with a command's name, since both are capabilities <domain>.<name> (D14)" do
      message =
        refuse_contract("QueryLikeCommand", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          read_model :closed_visits, "Zamknięte wizyty", projects: :visit_closed do
            field :closed_on, :date
          end

          query :close_visit, "Zamykane wizyty", reads: :closed_visits, by: :reception

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N1: query :close_visit has the name of a command; both are capabilities named " <>
                 "<domain>.close_visit (D14) (query_like_command.ex:14)"
    end

    test "each other kind of declaration" do
      message =
        refuse_contract("Kinds", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          effect :notify, "Powiadom", handles: :visit_closed, calls: :mail, idempotency: :downstream
          effect :notify, "Powiadom 2", handles: :visit_closed, calls: :mail, idempotency: :downstream

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~ "N1: two effects are named :notify (kinds.ex:11)"
    end

    # v1 refused two commands of one name; v2's namespace is shared, so the second
    # is refused as a clash with the first (plan E11a, the gates only partly ported).
    test "two commands of one name" do
      message =
        refuse_contract("TwoCommands", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            command :close_visit, "Zamknięcie wizyty 2", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N1: command :close_visit has the name of a command; commands, events, timers and " <>
                 "consumed events share one namespace (two_commands.ex:7)"
    end
  end

  describe "N2: reserved words and Kernel clashes" do
    test "a reserved word, a Kernel function and evolve are refused" do
      message =
        refuse_contract("Clashes", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :send, "Wysłanie", by: :reception, emits: :end
            command :evolve, "Rozwój", by: :reception, emits: :end
            event :end, "Koniec", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N2: command :send would define send/2, which clashes with Kernel.send/2 (clashes.ex:6)"

      assert message =~
               "N2: command :evolve would clash with evolve/2, which every unit defines (clashes.ex:7)"

      assert message =~ "N2: event :end is a word Elixir reserves (clashes.ex:8)"
    end

    test "an event is checked at the arities a handler can give it" do
      message =
        refuse_contract("EventClash", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :spawn
            event :spawn, "Coś", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N2: event :spawn would define spawn/1, which clashes with Kernel.spawn/1 (event_clash.ex:7)"
    end

    # The EL2b review: a handler's callback module_info/1 compiles in no module.
    test "an event is not named after a function every module defines" do
      message =
        refuse_contract("EventModuleInfo", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :module_info
            event :module_info, "Coś", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N2: event :module_info would define module_info/1, which every module defines " <>
                 "already (event_module_info.ex:7)"
    end

    test "state and row, which an implementation aliases as State and Row" do
      message =
        refuse_contract("Aliased", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :state, "Stan", by: :reception, emits: :row
            event :row, "Wiersz", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "N2: command :state would be aliased State in an implementation, which is the " <>
                 "alias of a unit's state (aliased.ex:6)"

      assert message =~
               "N2: event :row would be aliased Row in an implementation, which is the alias of " <>
                 "a read model's row (aliased.ex:7)"
    end

    test "control: a name that only begins like a Kernel function compiles" do
      assert %{} =
               compile_contract("NoClash", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id
                   command :send_reminder, "Przypomnienie", by: :reception, emits: :reminder_sent
                   event :reminder_sent, "Wysłano przypomnienie", terminal: true
                 end

                 process :visit, "Wizyta" do
                   correlate :visit_id
                 end
               """)
    end
  end
end
