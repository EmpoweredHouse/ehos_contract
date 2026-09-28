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

  describe "D1: names are unique per kind" do
    test "two contexts of one name are refused at the second" do
      message =
        refused("TwoContexts", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          context :settlement, "Rozliczenia 2", subdomain: :supporting
        """)

      assert message =~ "D1: two contexts are named :settlement (two_contexts.ex:5)"
    end

    test "every kind is checked, and every violation is reported at once" do
      message =
        refused("EveryKind", """
          actor :reception, :human, "Recepcja"
          actor :reception, :human, "Recepcja"
          subject :patient, "Pacjent"
          subject :patient, "Pacjent"
          value :money, :integer
          value :money, :integer
          external :registry, "Rejestr", direction: :outbound
          external :registry, "Rejestr", direction: :outbound
        """)

      assert message =~ "two actors are named :reception (every_kind.ex:5)"
      assert message =~ "two subjects are named :patient (every_kind.ex:7)"
      assert message =~ "two values are named :money (every_kind.ex:9)"
      assert message =~ "two externals are named :registry (every_kind.ex:11)"
    end

    test "a term defined twice in one context is refused" do
      message =
        refused("TwoTerms", """
          context :settlement, "Rozliczenia" do
            subdomain :supporting
            term "Wizyta", definition: "Spotkanie"
            term "Wizyta", definition: "Inne spotkanie"
          end
        """)

      assert message =~
               ~s|D1: context :settlement defines the term "Wizyta" twice (two_terms.ex:7)|
    end

    test "the same relation twice is refused, a symmetric one in either order" do
      message =
        refused("TwoRelations", """
          context :scheduling, "Umawianie", subdomain: :core
          context :settlement, "Rozliczenia", subdomain: :supporting
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
        context :settlement, "Rozliczenia", subdomain: :supporting
        actor :settlement, :system, "Rozliczenia"
        value :money, :integer
        subject :patient, "Pacjent"
      """)
    end
  end

  describe "D2: one translation per language, none into the term's own" do
    test "a second translation into one language is refused" do
      message =
        refused("TwoEnglish", """
          context :settlement, "Rozliczenia" do
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
          context :settlement, "Rozliczenia" do
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
        context :settlement, "Rozliczenia" do
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
      assert refused("UnitOnText", "  value :note, :string, unit: :grosze\n") =~
               "D3: value :note has unit :grosze, and a unit counts only an :integer or a :decimal"
    end

    test "an unknown type, a malformed enum and a repeated member are refused" do
      message =
        refused("BadTypes", """
          value :price, :money
          value :method, {:enum, []}
          value :status, {:enum, [:open, :closed, :open]}
          value :flag, {:enum, [true]}

          value :line do
            field :amount, :cents
          end
        """)

      assert message =~ "value :price: type :money is neither a built-in type"
      assert message =~ "value :method: an enum is a non-empty list of members"
      assert message =~ "value :status: an enum repeats a member: [:open, :closed, :open]"
      assert message =~ "value :flag: an enum member is an atom, or an atom with a label"
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
          subject :patient, "Pacjent"

          value :contact do
            field :note, :string, default: "brak"
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
        value :fee, :money, unit: :grosze
      """)
    end

    test "a unit on a value whose type is a non-numeric value is still refused" do
      assert refused(
               "UnitOnTextAlias",
               "  value :note, :string\n  value :memo, :note, unit: :grosze\n"
             ) =~
               "D3: value :memo has unit :grosze"
    end

    test "a personal field of a value that holds personal data of its own is refused" do
      message =
        refused("PersonalInPersonal", """
          subject :patient, "Pacjent"

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
        subject :patient, "Pacjent"

        value :contact do
          field :patient_id, :id, subject: :patient
          field :phone, :string, personal: :patient_id, optional: true
        end
      """)
    end

    test "the control: every built-in type, a unit, labels, lists and nested values compile" do
      compiles("WellFormed", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        value :money, :integer, unit: :grosze, label: "Kwota", context: :settlement
        value :rate, :decimal, unit: :percent
        value :method, {:enum, [card: "Karta", cash: "Gotówka"]}
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

  describe "D4: a person is not backed by a system" do
    test "a human actor with backed_by is refused" do
      message =
        refused("BackedPerson", """
          external :payer_registry, "Rejestr płatnika", direction: :outbound
          actor :reception, :human, "Recepcja", backed_by: :payer_registry
        """)

      assert message =~
               "D4: actor :reception is a person and cannot be backed_by :payer_registry;"

      assert message =~ "(backed_person.ex:5)"
    end

    test "a system actor backed by an undeclared external, and an undeclared context, are refused" do
      message =
        refused("UnknownBacking", """
          actor :gateway, :system, "Bramka", backed_by: :payer_registry, context: :billing
        """)

      assert message =~
               "D4: actor :gateway is backed_by :payer_registry, which this domain does not declare"

      assert message =~
               "D4: actor :gateway names context :billing, which this domain does not declare"
    end

    test "the control: a system actor backed by a declared external, in a declared context, compiles" do
      compiles("Backed", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        external :payer_registry, "Rejestr płatnika", direction: :outbound
        actor :gateway, :system, "Bramka", backed_by: :payer_registry, context: :settlement
        actor :reception, :human, "Recepcja", context: :settlement
      """)
    end
  end

  describe "D5 and D1, since plan EL2: a directed relation may end at an external system" do
    test "control: settlement conforms to an external, as ESDM allows" do
      compiles("ConformsToKsef", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        external :ksef, "KSeF", direction: :outbound
        relation :conformist, upstream: :ksef, downstream: :settlement
      """)
    end

    test "two externals, a symmetric relation to one, and a name both kinds have are refused" do
      message =
        refused("ExternalsWrong", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          external :ksef, "KSeF", direction: :outbound
          external :p1, "P1", direction: :outbound
          external :settlement, "Rozliczenia zewnętrzne", direction: :inbound
          relation :conformist, upstream: :ksef, downstream: :p1
          relation :partnership, between: [:settlement, :ksef]
        """)

      assert message =~
               "D5: relation :conformist joins no context of this domain: one end has to be a " <>
                 "context (externals_wrong.ex:8)"

      assert message =~
               "D5: relation :partnership is symmetric and names external :ksef: a symmetric " <>
                 "relation joins contexts; an external may end a directed one (externals_wrong.ex:9)"

      assert message =~
               "D1: :settlement is a context and an external; a relation could not tell which it " <>
                 "names (externals_wrong.ex:7)"
    end
  end

  describe "D8: a field's issuer is an external of this domain (plan EL2)" do
    test "an entity's field issued by an unknown external is refused; control: a known one" do
      message =
        refused("IssuedWrong", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          external :ksef, "KSeF", direction: :outbound

          entity :invoice, "Faktura", context: :settlement, identified_by: :invoice_no do
            field :invoice_no, :id, issued_by: :kse
          end
        """)

      assert message =~
               "D8: entity :invoice, field :invoice_no is issued_by: :kse, which is not an external " <>
                 "of this domain; did you mean :ksef? (issued_wrong.ex:8)"

      compiles("IssuedRight", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        external :ksef, "KSeF", direction: :outbound

        entity :invoice, "Faktura", context: :settlement, identified_by: :invoice_no do
          field :invoice_no, :id, issued_by: :ksef
        end
      """)

      [invoice] = Module.concat(__MODULE__, IssuedRight).__eh_os_contract_model__().entities
      assert [%{name: :invoice_no, issued_by: :ksef}] = invoice.fields
    end
  end

  describe "D7: a context belongs to a subdomain the domain declares (plan EL2)" do
    test "a context naming an undeclared subdomain is refused, with the closest name" do
      message =
        refused("UnknownSubdomain", """
          context :settlement, "Rozliczenia", subdomain: :suporting
        """)

      assert message =~
               "D7: context :settlement belongs to subdomain :suporting, which this domain does " <>
                 "not declare; did you mean :supporting? (unknown_subdomain.ex:4)"
    end

    test "control: a context naming a declared one compiles, and the kind is the subdomain's" do
      compiles("KnownSubdomain", """
        context :settlement, "Rozliczenia", subdomain: :supporting
      """)

      model = Module.concat(__MODULE__, KnownSubdomain).__eh_os_contract_model__()

      assert %{name: :supporting, type: :supporting} =
               Enum.find(model.subdomains, &(&1.name == :supporting))
    end
  end

  describe "D5: a relation's roles fit its type, and its ends exist" do
    @contexts """
      context :scheduling, "Umawianie", subdomain: :core
      context :settlement, "Rozliczenia", subdomain: :supporting
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
      context :month, "Miesiąc", subdomain: :core
    """

    test "an unknown context, a wrong identity and a personal field are refused" do
      message =
        refused(
          "EntityWrong",
          @periods <>
            """
              entity :period, "Okres", context: :billing, identified_by: :period_key do
                field :period_id, :id
              end

              entity :service, "Usługa", context: :month, identified_by: :service_id do
                field :service_id, :id, optional: true
              end

              entity :clinic, "Placówka", context: :month, identified_by: :clinic_id do
                field :clinic_id, :id
                field :owner, :string, personal: :clinic_id
              end
            """
        )

      assert message =~
               "D6: entity :period names context :billing, which this domain does not declare " <>
                 "(entity_wrong.ex:5)"

      assert message =~
               "D6: entity :period is identified by :period_key, which is not one of its fields"

      assert message =~
               "D6: entity :service is identified by :service_id, which is not a required, " <>
                 "non-personal :id field (entity_wrong.ex:9)"

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
              entity :period, "Okres", context: :month, identified_by: :period_id do
                field :period_id, :id
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
                 "domain does not declare (reference_wrong.ex:7)"

      assert message =~
               "D6: value :line, field :service_id: {:id, :service} names an entity this domain " <>
                 "does not declare (reference_wrong.ex:11)"

      assert message =~
               "D6: value :clinic_ref is {:id, :clinic}, which names an entity this domain does " <>
                 "not declare (reference_wrong.ex:14)"
    end

    test "the control: an entity, and fields naming it, compile into the model as :id" do
      compiles(
        "EntityRight",
        @periods <>
          """
            entity :period, "Okres", context: :month, identified_by: :period_id,
              source: "US-MON-01" do
              field :period_id, :id
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

      assert [%{name: :period, context: :month, identified_by: :period_id} = period] =
               model.entities

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
              subject :patient, "Pacjent"

              value :contact do
                field :patient_id, :id, subject: :patient
                field :phone, :string, personal: :patient_id
              end

              entity :card, "Karta", context: :month, identified_by: :card_id do
                field :card_id, :id
                field :card_id, :string
                field :holder_id, :id, subject: :holder
                field :contact, :contact
              end
            """
        )

      assert message =~ "D6: entity :card declares field :card_id twice (entity_fields.ex:14)"

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
            subject :patient, "Pacjent"

            entity :card, "Karta", context: :month, identified_by: :card_id do
              field :card_id, :id
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
      # `subdomains`, which every domain has since plan EL2 (D7).
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
              {key, Enum.map(Map.fetch!(model, key), &digest_form/1)}
            end
        )

      assert model.version == before
    end
  end

  # The digest's form of a declaration, as `EhOsContract.Domain.Build` sorts it. A value
  # without invariants is hashed without the key (plan EL2b).
  defp digest_form(%{invariants: []} = value),
    do: value |> Map.delete(:invariants) |> digest_form()

  defp digest_form(declaration) do
    Map.new(declaration, fn
      {key, list} when key in [:terms, :translations, :avoid, :fields] and is_list(list) ->
        {key, list |> Enum.map(&digest_form/1) |> Enum.sort_by(&EhOsContract.Digest.canonical/1)}

      {:between, list} ->
        {:between, Enum.sort(list)}

      other ->
        other
    end)
  end

  describe "the Spark schema (layer L1)" do
    test "an unknown option is refused with the file and line of the declaration" do
      error =
        domain(
          "UnknownOption",
          ~s|  context :settlement, "Rozliczenia", subdomain: :supporting, colour: :blue|
        )
        |> compile_error("unknown_option_domain.ex")

      assert Exception.message(error) =~ "unknown options [:colour]"
      assert Exception.message(error) =~ "unknown_option_domain.ex:4"
    end

    test "a translation without its definition is refused (plan EL2, as in ESDM)" do
      message =
        refused("TranslationWithoutDefinition", """
          context :settlement, "Rozliczenia", subdomain: :supporting do
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
