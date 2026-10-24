defmodule EhOsContract.DomainRulesTest do
  @moduledoc """
  v2 plan, E3: **what a domain module refuses to compile, and where the refusal
  points.**

  Each refusal is a `Spark.Error.DslError` whose message names the problem and the
  file and line of the declaration at fault. That second half is a property of
  Spark this stage has to confirm before E4 builds on it. Each rule has a control
  beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  defp domain(name, body) do
    """
    defmodule EhOsContract.DomainRulesTest.#{name} do
      use EhOsContract.Domain, name: :clinic, language: :pl

    #{body}

      subdomain :supporting, "Supporting", type: :supporting
      subdomain :core, "Core", type: :core
    end
    """
  end

  defp refused(name, body) do
    error = compile_error(domain(name, body), "#{Macro.underscore(name)}.ex")
    Exception.message(error)
  end

  defp compiles(name, body) do
    compiled = Code.compile_string(domain(name, body)) |> Enum.map(&elem(&1, 0))
    assert Module.concat(__MODULE__, name) in compiled
  end

  describe "D1: a label says something" do
    test "a blank label is refused, also on a nested declaration" do
      message =
        refused("BlankLabels", """
          context :settlement, " ", subdomain: :supporting
          actor :reception, :human, ""
          subject :patient, "\\u2066\\u200F\\u2069"

          entity :service, "Service", context: :settlement, identity: :service_id do
            field :name, :string, label: ""
          end
        """)

      assert message =~
               "D1: context :settlement has a blank label; say what the business calls it " <>
                 "(blank_labels.ex:4)"

      assert message =~ "D1: actor :reception has a blank label"
      # A direction isolate and mark print as nothing, as a space does. Elixir takes an
      # isolate only escaped in source, so the fixture carries the escape.
      assert message =~ "D1: subject :patient has a blank label"
      assert message =~ "D1: field :name has a blank label"
    end

    test "control: a label in Polish passes" do
      compiles("LabelsGiven", """
        context :settlement, "Należności", subdomain: :supporting
        actor :reception, :human, "Recepcja"
      """)
    end
  end

  describe "D1: names are snake_case, and unique per kind" do
    test "two contexts of one name are refused at the second" do
      message =
        refused("TwoContexts", """
          context :settlement, "Settlement", subdomain: :supporting
          context :settlement, "Settlement 2", subdomain: :supporting
        """)

      assert message =~ "D1: two contexts are named :settlement (two_contexts.ex:5)"
    end

    test "every kind is checked, and every violation is reported at once" do
      message =
        refused("EveryKind", """
          actor :reception, :human, "Reception"
          actor :reception, :human, "Reception"
          subject :patient, "Patient"
          subject :patient, "Patient"
          value :money, :integer
          value :money, :integer
          external :registry, "Registry", direction: :outbound
          external :registry, "Registry", direction: :outbound
        """)

      assert message =~ "two actors are named :reception (every_kind.ex:5)"
      assert message =~ "two subjects are named :patient (every_kind.ex:7)"
      assert message =~ "two values are named :money (every_kind.ex:9)"
      assert message =~ "two externals are named :registry (every_kind.ex:11)"
    end

    test "a name that is not snake_case is refused, whatever it names" do
      message =
        refused("NameForms", """
          context :"front desk", "Reception", subdomain: :supporting
          subject :Patient, "Patient"
          value :"a/b", :integer
          external :"registry-v2", "Registry", direction: :outbound
          subdomain true, "True", type: :generic
          context :"desk#{"\\n"}", "Reception 2", subdomain: :supporting
          context :settlement, "Settlement", subdomain: :supporting
          actor :Reception, :human, "Reception"

          entity :"Invoice", "Invoice", context: :settlement, identity: :invoice_no do
          end
        """)

      for {kind, name, line} <- [
            {"context", ~s|:"front desk"|, 4},
            {"subject", ":Patient", 5},
            {"value", ~s|:"a/b"|, 6},
            {"external", ~s|:"registry-v2"|, 7},
            {"subdomain", "true", 8},
            {"context", ~s|:"desk\\n"|, 9},
            {"entity", ":Invoice", 13}
          ] do
        assert message =~
                 "D1: #{kind} #{name} is not snake_case, as every name of a domain is " <>
                   "(name_forms.ex:#{line})"
      end

      refute message =~ ":settlement is not"
      refute message =~ ":invoice_no"
      # An actor's name is D4's, refused once.
      refute message =~ "D1: actor"
      assert message =~ "D4: actor :Reception is not snake_case"
    end

    test "two values that camelize alike are refused, since they would be one module" do
      message =
        refused("OneModule", """
          value :money_amount, :integer
          value :money_amount_, :integer
          value :money__amount, :integer
          value :desk2, :integer
          value :desk_2, :integer
          value :money_amount, :integer
          value :money_amount_, :integer
        """)

      assert message =~
               "D1: value :money_amount_ camelizes to MoneyAmount, as value :money_amount does, " <>
                 "and a value's invariants are the module Values.MoneyAmount; rename one of them " <>
                 "(one_module.ex:5)"

      assert message =~
               "D1: value :money__amount camelizes to MoneyAmount, as value :money_amount does"

      assert message =~ "D1: value :desk_2 camelizes to Desk2, as value :desk2 does"
      assert message =~ "D1: two values are named :money_amount (one_module.ex:9)"
      assert message =~ "D1: two values are named :money_amount_ (one_module.ex:10)"
      refute message =~ "value :money_amount camelizes"
      # A repeated name is refused once, as two of one name.
      assert length(String.split(message, "value :money_amount_ camelizes")) == 2
    end

    test "a value named after a built-in type is refused; control: snake_case names" do
      message =
        refused("BuiltInName", """
          value :map, :string
          value :integer, :integer
          value :bool, :boolean
          value :var, :string
          value :char_list, :string
          value :date, :string
          value :id, :string
        """)

      assert message =~
               "D1: value :map is named after a type Elixir builds in, and its @type could not " <>
                 "be defined; name it after what it holds (built_in_name.ex:4)"

      for name <- [:integer, :bool, :var, :char_list],
          do:
            assert(message =~ "D1: value #{inspect(name)} is named after a type Elixir builds in")

      assert message =~
               "D1: value :date is named after a built-in field type, which a field of type " <>
                 ":date would mean instead; name it after what it holds (built_in_name.ex:9)"

      assert message =~ "D1: value :id is named after a built-in field type"

      compiles("NotBuiltInName", """
        context :front_desk2, "Reception", subdomain: :supporting
        subject :patient, "Patient"
        external :registry_v2, "Registry", direction: :outbound
        value :money, :integer
        value :money_amount, :integer
        value :desk2, :integer
      """)
    end

    test "a term defined twice in one context is refused" do
      message =
        refused("TwoTerms", """
          context :settlement, "Settlement" do
            subdomain :supporting
            term "Visit", definition: "Meeting"
            term "Visit", definition: "Another meeting"
          end
        """)

      assert message =~
               ~s|D1: context :settlement defines the term "Visit" twice (two_terms.ex:7)|
    end

    test "the same relation twice is refused, a symmetric one in either order" do
      message =
        refused("TwoRelations", """
          context :scheduling, "Scheduling", subdomain: :core
          context :settlement, "Settlement", subdomain: :supporting
          relation :customer_supplier, upstream: :scheduling, downstream: :settlement
          relation :customer_supplier, upstream: :scheduling, downstream: :settlement
          relation :partnership, between: [:scheduling, :settlement]
          relation :partnership, between: [:settlement, :scheduling]
        """)

      assert message =~
               "D1: relation :customer_supplier between :scheduling and :settlement is declared twice (two_relations.ex:7)"

      assert message =~
               "D1: relation :partnership between :scheduling and :settlement is declared twice (two_relations.ex:9)"
    end

    test "the control: one name per kind, and one name reused across kinds, compile" do
      compiles("UniqueNames", """
        context :settlement, "Settlement", subdomain: :supporting
        actor :settlement, :system, "Settlement"
        value :money, :integer
        subject :patient, "Patient"
      """)
    end
  end

  describe "D2: one translation per language, none into the term's own" do
    test "a second translation into one language is refused" do
      message =
        refused("TwoEnglish", """
          context :settlement, "Settlement" do
            subdomain :supporting

            term "Wizyta" do
              definition "Spotkanie"
              translation :en, "Visit", definition: "A patient's appointment with a specialist"
              translation :en, "Appointment", definition: "An arranged meeting"
            end
          end
        """)

      assert message =~
               ~s|D2: the term "Wizyta" in context :settlement has a second translation into :en (two_english.ex:10)|
    end

    test "a translation into the domain's language is refused" do
      message =
        refused("IntoPolish", """
          context :settlement, "Settlement" do
            subdomain :supporting

            term "Wizyta" do
              definition "Spotkanie"
              translation :pl, "Wizyta", definition: "Umówione spotkanie pacjenta ze specjalistą"
            end
          end
        """)

      assert message =~
               ~s|is translated into :pl, which is the language it is written in (into_polish.ex:9)|
    end

    test "a context in another language takes that language as the term's own" do
      message =
        refused("IntoEnglish", """
          context :billing, "Billing" do
            subdomain :supporting
            language :en

            term "Visit" do
              definition "A patient's appointment"
              translation :en, "Visit", definition: "A patient's appointment with a specialist"
            end
          end
        """)

      assert message =~ "is translated into :en, which is the language it is written in"
    end

    test "the control: one translation per other language compiles" do
      compiles("Translated", """
        context :settlement, "Settlement" do
          subdomain :supporting

          term "Wizyta" do
            definition "Spotkanie"
            translation :en, "Visit", definition: "A patient's appointment with a specialist"
            translation :de, "Besuch", definition: "Termin eines Patienten bei einem Spezialisten"
          end
        end
      """)
    end
  end

  describe "D3: a value is one type or fields, well formed, without cycles" do
    test "neither a type nor fields, and both, are refused" do
      message =
        refused("TypeOrFields", """
          value :nothing

          value :both, :string do
            field :street, :string
          end
        """)

      assert message =~
               "D3: value :nothing has neither a type nor fields; give it exactly one (type_or_fields.ex:4)"

      assert message =~
               "D3: value :both has both a type and fields; keep one (type_or_fields.ex:6)"
    end

    test "a unit on a type that does not count is refused" do
      assert refused("UnitOnText", "  value :note, :string, unit: :cents\n") =~
               "D3: value :note has unit :cents, and a unit counts only an :integer or a :decimal"
    end

    test "a code that is not text, or that no invariant pins, is refused; control: codes by alias" do
      message =
        refused("CodeWithoutForm", """
          value :count, :integer, code: true
          value :free, :string, code: true

          value :nip, :string, code: true do
            invariant :ten_digits, "Ten digits", violated_by: ["1"], satisfied_by: ["1234567890"]
          end

          value :office_nip, :nip
          value :branch_nip, :nip, code: true

          value :checked, :string do
            invariant :ten_digits, "Ten digits", violated_by: ["1"], satisfied_by: ["1234567890"]
          end

          value :tax_no, :checked, code: true
        """)

      assert message =~
               "D3: value :count is a code, and a code is text: a :string, or a value that is one " <>
                 "(code_without_form.ex:4)"

      assert message =~
               "D3: value :free is a code and neither it nor a value it names declares an " <>
                 "invariant, so nothing holds it to a form; declare the invariants that do, or " <>
                 "leave it free text (code_without_form.ex:5)"

      for name <- [":nip", ":office_nip", ":branch_nip", ":checked", ":tax_no"],
          do: refute(message =~ "value #{name} ")
    end

    test "an unknown type, a malformed enum and a repeated member are refused" do
      message =
        refused("BadTypes", """
          value :price, :money
          value :method, {:enum, []}
          value :status, {:enum, [:open, :closed, :open]}
          value :flag, {:enum, [true]}
          value :method_blank, {:enum, [card: "Card", cash: ""]}
          value :flag_labelled, {:enum, [{false, ""}, {nil, "Brak"}]}

          value :line do
            field :amount, :cents
          end
        """)

      assert message =~ "value :price: type :money is neither a built-in type"
      assert message =~ "value :method: an enum is a non-empty list of members"
      assert message =~ "value :status: an enum repeats a member: [:open, :closed, :open]"
      assert message =~ "value :flag: an enum member is an atom, or an atom with a label"
      assert message =~ "value :method_blank: an enum member's label is blank: :cash"
      # `false` and `nil` are refused as names with a label as without one.
      assert message =~ "value :flag_labelled: an enum member is an atom, or an atom with a label"
      assert message =~ "value :line, field :amount: type :cents is neither a built-in type"
    end

    test "a value naming a context the domain does not declare is refused" do
      assert refused("NoSuchContext", "  value :money, :integer, context: :billing\n") =~
               "D3: value :money names context :billing, which this domain does not declare"
    end

    test "values referring to each other in a cycle are refused, once per cycle" do
      message =
        refused("Cycle", """
          value :a do
            field :b, :b
          end

          value :b do
            field :items, {:list, :a}
          end

          value :self do
            field :parent, :self
          end
        """)

      assert message =~ "D3: values refer to each other in a cycle: :a -> :b -> :a (cycle.ex:4)"
      assert message =~ "cycle: :self -> :self (cycle.ex:12)"
      refute message =~ ":b -> :a -> :b"
    end

    test "a value's field takes no default, and its subject and personal must hold" do
      message =
        refused("FieldOptions", """
          subject :patient, "Patient"

          value :contact do
            field :note, :string, default: "none"
            field :owner_id, :id, subject: :nobody
            field :patient_id, :id, subject: :patient, optional: true
            field :phone, :string, personal: :patient_id
            field :email, :string, personal: :missing_id
            field :name, :string, personal: :note
          end
        """)

      assert message =~
               "F3: value :contact, field :note has a default, which only a contract's state may have"

      assert message =~
               "field :owner_id names subject :nobody, which this domain does not declare"

      assert message =~ "field :phone is personal to :patient_id, which is optional"

      assert message =~
               "field :email is personal to :missing_id, which is not a field of this value"

      assert message =~
               "field :name is personal to :note, which is not an :id field declaring a subject"
    end

    test "the control: a unit on a value whose type is another numeric value compiles" do
      compiles("UnitOnAlias", """
        value :money, :integer
        value :fee, :money, unit: :cents
      """)
    end

    test "a unit on a value whose type is a non-numeric value is still refused" do
      assert refused(
               "UnitOnTextAlias",
               "  value :note, :string\n  value :memo, :note, unit: :cents\n"
             ) =~
               "D3: value :memo has unit :cents"
    end

    test "a personal field of a value that holds personal data of its own is refused" do
      message =
        refused("PersonalInPersonal", """
          subject :patient, "Patient"

          value :contact do
            field :patient_id, :id, subject: :patient
            field :phone, :string, personal: :patient_id
          end

          value :card do
            field :patient_id, :id, subject: :patient
            field :carer, :contact, personal: :patient_id
            field :carers, {:list, :contact}
          end
        """)

      assert message =~
               "F5: value :card, field :carer is personal, and :contact holds personal data of its " <>
                 "own, which would be sealed under this field's subject"

      # Control: a list of contacts that is not itself personal says whose each is.
      refute message =~ "field :carers"
    end

    test "the control: a personal field of a required subject identifier compiles" do
      compiles("PersonalField", """
        subject :patient, "Patient"

        value :contact do
          field :patient_id, :id, subject: :patient
          field :phone, :string, personal: :patient_id, optional: true
        end
      """)
    end

    test "the control: every built-in type, a unit, labels, lists and nested values compile" do
      compiles("WellFormed", """
        context :settlement, "Settlement", subdomain: :supporting
        value :money, :integer, unit: :cents, label: "Amount", context: :settlement
        value :rate, :decimal, unit: :percent
        value :method, {:enum, [card: "Card", cash: "Cash"]}
        value :status, {:enum, [:open, :closed]}

        value :line do
          field :id, :id
          field :note, :string, optional: true
          field :amount, :money
          field :paid, :boolean
          field :on, :date
          field :at, :timestamp
          field :methods, {:list, :method}
        end

        value :invoice do
          field :lines, {:list, :line}
        end
      """)
    end
  end

  describe "D4: an actor is named as a role, and a person is not backed by a system" do
    test "an actor whose name is not snake_case is refused, since it is a role" do
      message =
        refused("ActorNames", """
          actor :"*", :human, "Everyone"
          actor :"billing.clerk", :human, "Accountant"
          actor :Reception, :human, "Reception"
          actor :"clerk\n", :human, "Clerk"
          actor :front_desk2, :human, "Reception 2"
          actor :"Registry Bot", :system, "Registry robot"
          actor true, :human, "True"
        """)

      assert message =~
               ~s|D4: actor :* is not snake_case; it is the role "clinic.*" (actor_names.ex:4)|

      assert message =~
               ~s|D4: actor :"billing.clerk" is not snake_case; it is the role "clinic.billing.clerk"|

      assert message =~ "D4: actor :Reception is not snake_case"
      assert message =~ ~s|D4: actor :"clerk\\n" is not snake_case|
      assert message =~ ~s|D4: actor :"Registry Bot" is not snake_case, as every name in by: is|
      assert message =~ ~s|D4: actor true is not snake_case; it is the role "clinic.true"|
      refute message =~ "front_desk2"
    end

    test "a human actor with backed_by is refused" do
      message =
        refused("BackedPerson", """
          external :payer_registry, "Payer registry", direction: :outbound
          actor :reception, :human, "Reception", backed_by: :payer_registry
        """)

      assert message =~
               "D4: actor :reception is a person and cannot be backed_by :payer_registry;"

      assert message =~ "(backed_person.ex:5)"
    end

    test "a system actor backed by an undeclared external, and an undeclared context, are refused" do
      message =
        refused("UnknownBacking", """
          actor :gateway, :system, "Gateway", backed_by: :payer_registry, context: :billing
        """)

      assert message =~
               "D4: actor :gateway is backed_by :payer_registry, which this domain does not declare"

      assert message =~
               "D4: actor :gateway names context :billing, which this domain does not declare"
    end

    test "the control: a system actor backed by a declared external, in a declared context, compiles" do
      compiles("Backed", """
        context :settlement, "Settlement", subdomain: :supporting
        external :payer_registry, "Payer registry", direction: :outbound
        actor :gateway, :system, "Gateway", backed_by: :payer_registry, context: :settlement
        actor :reception, :human, "Reception", context: :settlement
      """)
    end
  end

  describe "D4: a person actor may grant another person actor's role" do
    test "the control: a person may grant other persons, along a chain" do
      compiles("Grants", """
        actor :owner, :human, "Owner", may_grant: [:office_employee]
        actor :office_employee, :human, "Office employee", may_grant: [:client]
        actor :client, :human, "Client"
      """)
    end

    test "a rule on a system, or naming itself, a system, an undeclared actor or one twice, is refused" do
      message =
        refused("BrokenGrants", """
          external :registry, "Registry", direction: :outbound
          actor :sync, :system, "Sync", backed_by: :registry, may_grant: [:client]
          actor :office_employee, :human, "Office employee",
            may_grant: [:office_employee, :sync, :supplier, :client, :client]
          actor :client, :human, "Client"
        """)

      assert message =~
               "D4: actor :sync is a system and cannot have may_grant; only a person brings " <>
                 "people in (broken_grants.ex:5)"

      assert message =~ "D4: actor :office_employee's may_grant names the actor itself"

      assert message =~
               "D4: actor :office_employee's may_grant names :sync, a system; only a person is " <>
                 "granted a role"

      assert message =~
               "D4: actor :office_employee's may_grant names :supplier, which this domain does " <>
                 "not declare as an actor"

      assert message =~ "D4: actor :office_employee's may_grant names :client twice"
      refute message =~ "names :client,"
    end

    test "rules that lead back to an actor are refused at each actor on the cycle, not one leading into it" do
      message =
        refused("GrantCycle", """
          actor :owner, :human, "Owner", may_grant: [:office_employee]
          actor :office_employee, :human, "Office employee", may_grant: [:client]
          actor :client, :human, "Client", may_grant: [:auditor]
          actor :auditor, :human, "Auditor", may_grant: [:office_employee]
        """)

      assert message =~
               "D4: actor :office_employee's may_grant puts it on a cycle of grant rules with " <>
                 ":auditor, :client"

      assert message =~ "D4: actor :client's may_grant puts it on a cycle"
      assert message =~ "D4: actor :auditor's may_grant puts it on a cycle"
      refute message =~ "actor :owner"
    end

    test "a refusal of a long cycle names three others and how many more" do
      ring =
        Enum.map_join(1..8, "\n", fn i ->
          ~s|  actor :a#{i}, :human, "A#{i}", may_grant: [:a#{rem(i, 8) + 1}]|
        end)

      message = refused("GrantRing", ring)

      assert message =~
               "D4: actor :a1's may_grant puts it on a cycle of grant rules with :a2, :a3, :a4 " <>
                 "and 4 more"
    end
  end

  describe "D4's grant rule and the domain's version" do
    test "an actor without a rule hashes as it did before actors could have one" do
      compiles("NoGrantRule", """
        actor :office_employee, :human, "Office employee"
      """)

      model = Module.concat(__MODULE__, NoGrantRule).__eh_os_contract_model__()

      # The domain hashed as before the option, its actors without the key.
      before =
        EhOsContract.Digest.hash_groups(
          [domain: [%{name: model.name, language: model.language}]] ++
            for key <- [
                  :subdomains,
                  :contexts,
                  :actors,
                  :subjects,
                  :values,
                  :externals,
                  :relations
                ] do
              {key,
               model
               |> Map.fetch!(key)
               |> Enum.map(&Map.delete(&1, :may_grant))
               |> Enum.map(&digest_form/1)
               |> Enum.map(&EhOsContract.Digest.agreement/1)}
            end
        )

      assert model.version == before
    end

    test "a rule is a set: its order moves no version, its names do" do
      compiles("GrantsAB", """
        actor :owner, :human, "Owner", may_grant: [:client, :auditor]
        actor :client, :human, "Client"
        actor :auditor, :human, "Auditor"
      """)

      compiles("GrantsBA", """
        actor :owner, :human, "Owner", may_grant: [:auditor, :client]
        actor :client, :human, "Client"
        actor :auditor, :human, "Auditor"
      """)

      compiles("GrantsA", """
        actor :owner, :human, "Owner", may_grant: [:auditor]
        actor :client, :human, "Client"
        actor :auditor, :human, "Auditor"
      """)

      version = &Module.concat(__MODULE__, &1).__eh_os_contract_model__().version

      assert version.(GrantsAB) == version.(GrantsBA)
      refute version.(GrantsAB) == version.(GrantsA)
    end
  end

  describe "D5 and D1, since plan EL2: a directed relation may end at an external system" do
    test "control: settlement conforms to an external, as ESDM allows" do
      compiles("ConformsToRegistry", """
        context :settlement, "Settlement", subdomain: :supporting
        external :einvoicing, "E-invoicing registry", direction: :outbound
        relation :conformist, upstream: :einvoicing, downstream: :settlement
      """)
    end

    test "two externals, a symmetric relation to one, and a name both kinds have are refused" do
      message =
        refused("ExternalsWrong", """
          context :settlement, "Settlement", subdomain: :supporting
          external :einvoicing, "E-invoicing registry", direction: :outbound
          external :registry, "Health registry", direction: :outbound
          external :settlement, "External settlement", direction: :inbound
          relation :conformist, upstream: :einvoicing, downstream: :registry
          relation :partnership, between: [:settlement, :einvoicing]
        """)

      assert message =~
               "D5: relation :conformist joins no context of this domain: one end has to be a " <>
                 "context (externals_wrong.ex:8)"

      assert message =~
               "D5: relation :partnership is symmetric and names external :einvoicing: a symmetric " <>
                 "relation joins contexts; an external may end a directed one (externals_wrong.ex:9)"

      assert message =~
               "D1: :settlement is a context and an external; a relation could not tell which it " <>
                 "names (externals_wrong.ex:7)"
    end
  end

  describe "D13: the domain's days are in a zone the time zone database knows (plan W2)" do
    defp zoned(module, zone) do
      """
      defmodule EhOsContract.DomainRulesTest.#{module} do
        use EhOsContract.Domain, name: :clinic, language: :pl, time_zone: #{inspect(zone)}
      end
      """
    end

    test "a zone the database does not know is refused; control: Warsaw, and UTC by default" do
      message = Exception.message(compile_error(zoned("ZoneWrong", "Europe/Warszawa"), "zone.ex"))

      assert message =~
               ~s|D13: the domain's time_zone: "Europe/Warszawa" is not a zone the configured | <>
                 "time zone database (Tz.TimeZoneDatabase) knows"

      Code.compile_string(zoned("ZoneRight", "Europe/Warsaw"))

      assert Module.concat(__MODULE__, ZoneRight).__eh_os_contract_model__().time_zone ==
               "Europe/Warsaw"
    end

    test "a domain that names no zone keeps UTC, and the version it had" do
      Code.compile_string("""
      defmodule EhOsContract.DomainRulesTest.ZoneDefault do
        use EhOsContract.Domain, name: :clinic, language: :pl
      end
      """)

      Code.compile_string("""
      defmodule EhOsContract.DomainRulesTest.ZoneUtc do
        use EhOsContract.Domain, name: :clinic, language: :pl, time_zone: "Etc/UTC"
      end
      """)

      default = Module.concat(__MODULE__, ZoneDefault).__eh_os_contract_model__()
      utc = Module.concat(__MODULE__, ZoneUtc).__eh_os_contract_model__()
      assert default.time_zone == "Etc/UTC"
      assert default.version == utc.version
    end
  end

  describe "D11: the domain's name is one segment of an application's namespace (after #50)" do
    defp named(module, name, body \\ "") do
      """
      defmodule EhOsContract.DomainRulesTest.#{module} do
        use EhOsContract.Domain, name: #{inspect(name)}, language: :pl

      #{body}
      end
      """
    end

    test "a name with a dot, a dash at an end, a capital, a space, a newline, or nil is refused at use" do
      for {name, index} <-
            Enum.with_index([
              :"acme.billing",
              :"shop-",
              :"-shop",
              :My_shop,
              :"my shop",
              :"1shop",
              :_shop,
              :"shop\n",
              :"",
              nil,
              true
            ]) do
        module = "BadName#{index}"
        file = "#{Macro.underscore(module)}.ex"
        message = Exception.message(compile_error(named(module, name), file))

        assert message =~
                 "D11: the domain's name: #{inspect(name)} is not an application's namespace: " <>
                   "lowercase letters, digits, _ and -, starting with a letter and not ending " <>
                   "with a dash, like :\"my-shop\"; it begins every name the domain's contracts " <>
                   "publish (#{file}:2)"
      end
    end

    test "control: a dash inside, an underscore anywhere after the first letter, digits" do
      for {name, index} <-
            Enum.with_index([:"my-shop", :dispatch_rig, :shop_, :lending, :a, :shop2, :"a-b_c-9"]) do
        module = "GoodName#{index}"
        compiled = Code.compile_string(named(module, name)) |> Enum.map(&elem(&1, 0))
        assert Module.concat(__MODULE__, module) in compiled
        assert Module.concat(__MODULE__, module).__eh_os_contract_model__().name == name
      end
    end

    test "is reported with the domain's other violations, at once" do
      message =
        Exception.message(
          compile_error(
            named("BadNameAndMore", :"acme.billing", """
              actor :reception, :human, "Reception"
              actor :reception, :human, "Reception"
            """),
            "bad_name_and_more.ex"
          )
        )

      assert message =~ ~s|D11: the domain's name: :"acme.billing"|
      assert message =~ "publish (bad_name_and_more.ex:2)"
      assert message =~ "D1: two actors are named :reception (bad_name_and_more.ex:5)"
    end
  end

  describe "D3 and D6: a field's name is snake_case, and named once" do
    test "a value's and an entity's field is snake_case and named once" do
      message =
        refused("FieldNames", """
          context :settlement, "Settlement", subdomain: :supporting

          value :address do
            field :City, :string
            field :street, :string
            field :street, :string, optional: true
          end

          entity :invoice, "Invoice", context: :settlement, identity: :invoice_no do
            field :"Invoice No", :string
          end
        """)

      assert message =~ "D3: value :address, field :City is not snake_case (field_names.ex:7)"
      assert message =~ "D3: value :address declares field :street twice (field_names.ex:9)"

      assert message =~
               ~s|D6: entity :invoice, field :"Invoice No" is not snake_case (field_names.ex:13)|

      refute message =~ ":invoice_no is not"
    end
  end

  describe "D8: a field's issuer is an external of this domain (plan EL2)" do
    test "an entity issued by an unknown external is refused, and its field; control: a known one" do
      message =
        refused("IssuedWrong", """
          context :settlement, "Settlement", subdomain: :supporting
          external :einvoicing, "E-invoicing registry", direction: :outbound

          entity :invoice, "Invoice", context: :settlement, identity: :invoice_no, issued_by: :einvoice do
            field :seller_id, :id, issued_by: :einvoice
          end
        """)

      assert message =~
               "D8: entity :invoice, identity :invoice_no is issued_by: :einvoice, which is not an " <>
                 "external of this domain; did you mean :einvoicing? (issued_wrong.ex:7)"

      assert message =~
               "D8: entity :invoice, field :seller_id is issued_by: :einvoice, which is not an external " <>
                 "of this domain; did you mean :einvoicing? (issued_wrong.ex:8)"

      compiles("IssuedRight", """
        context :settlement, "Settlement", subdomain: :supporting
        external :einvoicing, "E-invoicing registry", direction: :outbound

        entity :invoice, "Invoice", context: :settlement, identity: :invoice_no, issued_by: :einvoicing do
        end
      """)

      [invoice] = Module.concat(__MODULE__, IssuedRight).__eh_os_contract_model__().entities
      assert [%{name: :invoice_no, issued_by: :einvoicing}] = invoice.fields
    end
  end

  describe "D7: a context belongs to a subdomain the domain declares (plan EL2)" do
    test "a context naming an undeclared subdomain is refused, with the closest name" do
      message =
        refused("UnknownSubdomain", """
          context :settlement, "Settlement", subdomain: :suporting
        """)

      assert message =~
               "D7: context :settlement belongs to subdomain :suporting, which this domain does " <>
                 "not declare; did you mean :supporting? (unknown_subdomain.ex:4)"
    end

    test "control: a context naming a declared one compiles, and the kind is the subdomain's" do
      compiles("KnownSubdomain", """
        context :settlement, "Settlement", subdomain: :supporting
      """)

      model = Module.concat(__MODULE__, KnownSubdomain).__eh_os_contract_model__()

      assert %{name: :supporting, type: :supporting} =
               Enum.find(model.subdomains, &(&1.name == :supporting))
    end
  end

  describe "D5: a relation's roles fit its type, and its ends exist" do
    @contexts """
      context :scheduling, "Scheduling", subdomain: :core
      context :settlement, "Settlement", subdomain: :supporting
    """

    test "a directed relation written with between is refused" do
      assert refused(
               "DirectedBetween",
               @contexts <> "  relation :conformist, between: [:scheduling, :settlement]\n"
             ) =~
               "D5: relation :conformist has a direction: give it upstream: and downstream:, and no between: (directed_between.ex:6)"
    end

    test "a symmetric relation written with a direction is refused" do
      assert refused(
               "SymmetricDirected",
               @contexts <>
                 "  relation :partnership, upstream: :scheduling, downstream: :settlement\n"
             ) =~
               "D5: relation :partnership is symmetric: give it between: [a, b], and no upstream: or downstream:"
    end

    test "an end the domain does not declare, and a context related to itself, are refused" do
      message =
        refused(
          "BadEnds",
          @contexts <>
            """
              relation :customer_supplier, upstream: :scheduling, downstream: :billing
              relation :shared_kernel, between: [:settlement, :settlement]
            """
        )

      assert message =~
               "D5: relation :customer_supplier names context or external :billing, which this domain does not declare"

      assert message =~ "D5: relation :shared_kernel relates context :settlement to itself"
    end

    test "the control: each of the eight types, written the way it reads, compiles" do
      directed =
        for type <-
              ~w(customer_supplier conformist anticorruption_layer open_host_service published_language) do
          "  relation :#{type}, upstream: :scheduling, downstream: :settlement\n"
        end

      symmetric =
        for type <- ~w(partnership shared_kernel separate_ways) do
          "  relation :#{type}, between: [:scheduling, :settlement]\n"
        end

      compiles("EveryRelation", @contexts <> Enum.join(directed ++ symmetric))
    end
  end

  describe "D6: an entity, and every field that names one" do
    @periods """
      context :month, "Month", subdomain: :core
    """

    test "an unknown context, a wrong identity and a personal field are refused" do
      message =
        refused(
          "EntityWrong",
          @periods <>
            """
              entity :period, "Period", context: :billing, identity: :"Period key" do
                field :name, :string
              end

              entity :service, "Service", context: :month, identity: :service_id do
                field :service_id, :id, optional: true
              end

              entity :invoice, "Invoice", context: :month, identity: :number do
                field :number, :id, issued_by: :einvoicing
              end

              entity :clinic, "Clinic", context: :month, identity: :clinic_id do
                field :owner, :string, personal: :clinic_id
              end
            """
        )

      assert message =~
               "D6: entity :period names context :billing, which this domain does not declare " <>
                 "(entity_wrong.ex:5)"

      assert message =~ ~s|D6: entity :period, identity :"Period key" is not snake_case|

      assert message =~
               "D6: entity :service declares field :service_id, which is its identity; the " <>
                 "library injects it as a required, non-personal :id, so declare no field for it " <>
                 "(entity_wrong.ex:10)"

      # Plan N1: a field that carried the issuer says where the issuer goes now.
      assert message =~
               "D6: entity :invoice declares field :number, which is its identity; the library " <>
                 "injects it as a required, non-personal :id, so declare no field for it, and " <>
                 "write issued_by: :einvoicing on the entity, which gives it (entity_wrong.ex:14)"

      assert message =~
               "D6: entity :clinic, field :owner has personal:, and an entity's rows are the " <>
                 "application's, outside the log, where erasure cannot reach them"
    end

    test "{:id, entity} naming an entity the domain does not declare is refused" do
      message =
        refused(
          "ReferenceWrong",
          @periods <>
            """
              entity :period, "Period", context: :month, identity: :period_id do
                field :previous_id, {:id, :perod}
              end

              value :line do
                field :service_id, {:list, {:id, :service}}
              end

              value :clinic_ref, {:id, :clinic}
            """
        )

      assert message =~
               "D6: entity :period, field :previous_id: {:id, :perod} names an entity this " <>
                 "domain does not declare (reference_wrong.ex:6)"

      assert message =~
               "D6: value :line, field :service_id: {:id, :service} names an entity this domain " <>
                 "does not declare (reference_wrong.ex:10)"

      assert message =~
               "D6: value :clinic_ref is {:id, :clinic}, which names an entity this domain does " <>
                 "not declare (reference_wrong.ex:13)"
    end

    test "the control: an entity, and fields naming it, compile into the model as :id" do
      compiles(
        "EntityRight",
        @periods <>
          """
            entity :period, "Period", context: :month, identity: :period_id,
              source: "US-INV-07" do
              field :name, :string
              field :ends_on, :date
              field :previous_id, {:id, :period}, optional: true
            end

            value :line do
              field :period_ids, {:list, {:id, :period}}
            end
          """
      )

      model = Module.concat(__MODULE__, EntityRight).__eh_os_contract_model__()

      assert [%{name: :period, context: :month, identity: :period_id} = period] =
               model.entities

      # Plan N1: the identity is injected first, as a unit's is.
      assert [
               %{name: :period_id, type: :id, optional: false, personal: nil, subject: nil}
               | _
             ] = period.fields

      refute Map.has_key?(period, :issued_by)

      assert %{type: :id, refers_to: :period} =
               Enum.find(period.fields, &(&1.name == :previous_id))

      refute Map.has_key?(Enum.find(period.fields, &(&1.name == :name)), :refers_to)

      assert [%{type: {:list, :id}, refers_to: :period}] =
               Enum.find(model.values, &(&1.name == :line)).fields

      assert Map.has_key?(model.digests, "entity:period")
    end

    test "a field twice, an unknown subject and personal data inside a value are refused" do
      message =
        refused(
          "EntityFields",
          @periods <>
            """
              subject :patient, "Patient"

              value :contact do
                field :patient_id, :id, subject: :patient
                field :phone, :string, personal: :patient_id
              end

              entity :card, "Card", context: :month, identity: :card_id do
                field :number, :string
                field :number, :string
                field :holder_id, :id, subject: :holder
                field :contact, :contact
              end
            """
        )

      assert message =~ "D6: entity :card declares field :number twice (entity_fields.ex:14)"

      assert message =~
               "D6: entity :card, field :holder_id names subject :holder, which this domain does " <>
                 "not declare (entity_fields.ex:15)"

      assert message =~
               "D6: entity :card, field :contact is of :contact, which holds personal data, and " <>
                 "an entity's rows are the application's"
    end

    test "control: a value's personal field may name a subject identifier that is an entity's" do
      compiles(
        "PersonalToEntity",
        @periods <>
          """
            subject :patient, "Patient"

            entity :card, "Card", context: :month, identity: :card_id do
            end

            value :contact do
              field :patient_id, {:id, :card}, subject: :patient
              field :phone, :string, personal: :patient_id
            end
          """
      )
    end

    test "a domain without entities hashes as it did before entities existed" do
      compiles("NoEntities", @periods <> "  value :money, :integer\n")
      model = Module.concat(__MODULE__, NoEntities).__eh_os_contract_model__()

      # The groups a domain was hashed over before the kind was added, and
      # `subdomains`, which every domain has since plan EL2 (D7), each without its words
      # (plan DD, V5, #322).

      before =
        EhOsContract.Digest.hash_groups(
          [domain: [%{name: model.name, language: model.language}]] ++
            for key <- [
                  :subdomains,
                  :contexts,
                  :actors,
                  :subjects,
                  :values,
                  :externals,
                  :relations
                ] do
              {key,
               model
               |> Map.fetch!(key)
               |> Enum.map(&digest_form/1)
               |> Enum.map(&EhOsContract.Digest.agreement/1)}
            end
        )

      assert model.version == before
    end
  end

  # The digest's form of a declaration, as `EhOsContract.Domain.Build` sorts it. A value
  # without invariants is hashed without the key (plan EL2b).
  defp digest_form(%{invariants: []} = value),
    do: value |> Map.delete(:invariants) |> digest_form()

  # Plan EP5a and EP5b: an external without operations, an actor without
  # responsibilities, as before either existed.
  defp digest_form(%{operations: []} = external),
    do: external |> Map.delete(:operations) |> digest_form()

  defp digest_form(%{responsibilities: []} = actor),
    do: actor |> Map.delete(:responsibilities) |> digest_form()

  # An actor without a grant rule, as before it could have one.
  defp digest_form(%{may_grant: []} = actor),
    do: actor |> Map.delete(:may_grant) |> digest_form()

  defp digest_form(declaration) when is_map(declaration) do
    Map.new(declaration, fn
      {key, list}
      when key in [:terms, :translations, :avoid, :fields, :operations, :responsibilities] and
             is_list(list) ->
        {key, list |> Enum.map(&digest_form/1) |> Enum.sort_by(&EhOsContract.Digest.canonical/1)}

      {:between, list} ->
        {:between, Enum.sort(list)}

      {:may_grant, list} ->
        {:may_grant, Enum.sort(list)}

      other ->
        other
    end)
  end

  # A relation's pair is a list of two words, kept as written.
  defp digest_form(other), do: other

  describe "the Spark schema (layer L1)" do
    test "an unknown option is refused with the file and line of the declaration" do
      error =
        domain(
          "UnknownOption",
          ~s|  context :settlement, "Settlement", subdomain: :supporting, colour: :blue|
        )
        |> compile_error("unknown_option_domain.ex")

      assert Exception.message(error) =~ "unknown options [:colour]"
      assert Exception.message(error) =~ "unknown_option_domain.ex:4"
    end

    test "a translation without its definition is refused (plan EL2, as in ESDM)" do
      message =
        refused("TranslationWithoutDefinition", """
          context :settlement, "Settlement", subdomain: :supporting do
            term "Wizyta", definition: "Spotkanie" do
              translation :en, "Visit"
            end
          end
        """)

      assert message =~ "required :definition option not found"
      assert message =~ "translation_without_definition.ex:6"
    end

    test "a missing use option is refused" do
      assert_raise Spark.Options.ValidationError, ~r/language/, fn ->
        Code.compile_string("""
        defmodule EhOsContract.DomainRulesTest.NoLanguage do
          use EhOsContract.Domain, name: :clinic
        end
        """)
      end
    end
  end
end
