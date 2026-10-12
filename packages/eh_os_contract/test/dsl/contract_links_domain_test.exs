defmodule EhOsContract.ContractLinksDomainTest do
  @moduledoc """
  v2 plan, E5b: **the L3 rules that read the domain** — X1–X4, and the parts of D10,
  D11 and (from E8) F7 a contract cannot check alone (v2 §6, §16). Each violation names the
  declaration's file and line, and has a control beside it that passes.
  """

  use EhOsContract.DslCase, async: false

  @domain EhOsContract.Fixtures.LinksClinic

  # The same domain under an EHOS application's name, which may hold a dash (#50).
  @dashed EhOsContract.Fixtures.LinksDashedShop

  setup_all do
    for {module, name, file} <- [
          {@domain, :clinic, "links_clinic.ex"},
          {@dashed, :"my-shop", "links_dashed_shop.ex"}
        ] do
      compile(domain_source(module, name), file)
    end

    :ok
  end

  defp domain_source(module, name) do
    """
    defmodule #{inspect(module)} do
      use EhOsContract.Domain, name: #{inspect(name)}, language: :pl

      context :settlement, "Rozliczenia", subdomain: :core
      context :scheduling, "Terminarz", subdomain: :supporting

      actor :reception, :human, "Recepcja", scope: [:clinic_id]
      actor :cashier, :human, "Kasjer"
      actor :scheduler, :human, "Rejestracja", context: :scheduling

      subject :patient, "Pacjent"
      value :money, :integer, unit: :grosze

      value :contact do
        field :patient_id, :id, subject: :patient
        field :phone, :string, personal: :patient_id
      end

      value :contact_ref, :contact
      value :clinic_ids, {:list, :id}
      value :period_id, :id
      value :clinic_ref, {:id, :clinic}
      external :payer_registry, "Rejestr płatnika", direction: :outbound

      entity :clinic, "Przychodnia", context: :settlement, identity: :clinic_id do
        field :city, :string
      end

      subdomain :core, "Core", type: :core
      subdomain :supporting, "Supporting", type: :supporting
    end
    """
  end

  # Line 4 of the file is the first line of the body.
  defp source(name, body, opts) do
    domain = Keyword.get(opts, :domain, inspect(@domain))
    context = Keyword.get(opts, :context, :settlement)
    namespace = Keyword.get(opts, :namespace, "clinic")

    """
    defmodule EhOsContract.Fixtures.#{name} do
      use EhOsContract.Contract, domain: #{domain}, context: #{inspect(context)}, id: "#{namespace}.#{contract_name(name)}"

    #{body}
    end
    """
  end

  defp links(name, body, opts \\ []),
    do: links([{"#{Macro.underscore(name)}.ex", source(name, body, opts)}])

  # Everything the rules below read, named right.
  @body """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      invariant :paid_once, "Wizyta jest opłacona raz"

      command :record_payment, "Płatność",
        by: [:reception, :cashier], emits: :payment_recorded, rejects: :paid_once do
        field :amount, :money
        field :patient_id, :id, subject: :patient
      end

      event :payment_recorded, "Zapłacono", depends_on: :payer_registry do
        field :amount, :money
        field :clinic_id, {:id, :clinic}
        field :amounts, {:list, :money}
        field :patient_id, :id, subject: :patient
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
      accountable :reception
    end

    effect :notify_payer, "Powiadom płatnika", handles: :payment_recorded,
      calls: :payer_registry, idempotency: [key: :visit_id, owner: :self]

    read_model :payments, "Płatności", projects: :payment_recorded do
      field :clinic_id, :id
      field :amount, :money
    end

    query :payments_in_clinic, "Płatności w przychodni",
      reads: :payments, by: :reception do
      param :clinic_id, :id
      scope :clinic_id
    end

    publish :payment_recorded, as: "clinic.payment.recorded.v1",
      from: :payment_recorded, fields: [:visit_id, :amount]

    scenario "płatność przyjęta" do
      command :record_payment, %{amount: 100, patient_id: "p-1"}
      expect :payment_recorded
    end

    scenario "druga płatność odrzucona" do
      command :record_payment, %{amount: 100, patient_id: "p-1"}
      actor :cashier
      rejected :paid_once
    end
  """

  test "control: a contract naming its domain right passes every rule" do
    assert links("LinksRight", @body) == []
  end

  describe "X1: the domain and the context" do
    test "domain: naming a module that is not a compiled domain points at the use line" do
      violations = links("LinksNoDomain", @body, domain: "EhOsContract.Fixtures.Nowhere")

      assert assert_linked(violations, "X1:", "links_no_domain.ex", 2) =~
               "names domain EhOsContract.Fixtures.Nowhere, which is not a compiled " <>
                 "EhOsContract.Domain"

      # With no domain there is nothing to check the rest against.
      assert length(violations) == 1
    end

    test "a context the domain does not declare" do
      violations = links("LinksNoContext", @body, context: :setlement)

      assert assert_linked(violations, "X1:", "links_no_context.ex", 2) =~
               "belongs to context :setlement, which #{inspect(@domain)} does not declare; " <>
                 "did you mean :settlement?"
    end
  end

  describe "X2: every actor named is the domain's, and of this context" do
    test "a typo in by:, recorded_by:, accountable and a scenario's actor" do
      body =
        @body
        |> String.replace("by: [:reception, :cashier]", "by: [:recepion, :cashier]")
        |> String.replace(
          ~s|"Zapłacono", depends_on|,
          ~s|"Zapłacono", recorded_by: :kasjer, depends_on|
        )
        |> String.replace("accountable :reception", "accountable :recption")
        |> String.replace("actor :cashier", "actor :recepion")

      violations = links("LinksActors", body)

      assert assert_linked(
               violations,
               "X2: command :record_payment: by: :recepion",
               "links_actors.ex",
               9
             ) =~
               "is not an actor of #{inspect(@domain)}; did you mean :reception?"

      assert assert_linked(violations, "recorded_by: :kasjer", "links_actors.ex", 15) =~
               "it declares [:cashier, :reception, :scheduler]"

      assert_linked(
        violations,
        "X2: process :visit: accountable :recption",
        "links_actors.ex",
        23
      )

      assert_linked(
        violations,
        ~s|X2: scenario "druga płatność odrzucona": actor :recepion|,
        "links_actors.ex",
        50
      )

      assert length(violations) == 4
    end

    test "an actor of another context" do
      violations =
        links(
          "LinksOtherContext",
          String.replace(
            @body,
            "by: [:reception, :cashier]",
            "by: [:reception, :cashier, :scheduler]"
          )
        )

      assert assert_linked(violations, "X2:", "links_other_context.ex", 9) =~
               ":scheduler is an actor of context :scheduling, not of :settlement"
    end

    test "control: the same actor passes in its own context" do
      body = """
        aggregate :slot, "Termin" do
          identity :slot_id
          command :book_slot, "Rezerwacja", by: :scheduler, emits: :slot_booked
          event :slot_booked, "Zarezerwowano"
        end
      """

      assert links("LinksOwnContext", body, context: :scheduling) == []
    end
  end

  describe "X3: types and subjects are the domain's" do
    test "a field type that is no value, alone and in a list, and an unknown subject" do
      body =
        @body
        |> String.replace(
          "field :amount, :money\n      field :clinic_id",
          "field :amount, :mony\n      field :clinic_id"
        )
        |> String.replace("{:list, :money}", "{:list, :cash}")
        |> String.replace(
          "field :patient_id, :id, subject: :patient\n    end\n  end",
          "field :patient_id, :id, subject: :patinet\n    end\n  end"
        )

      violations = links("LinksTypes", body)

      assert assert_linked(
               violations,
               "X3: event :payment_recorded, field :amount",
               "links_types.ex",
               16
             ) =~
               ":mony is neither a built-in type nor a value of #{inspect(@domain)}; did you mean :money?"

      assert_linked(violations, "field :amounts: :cash", "links_types.ex", 18)

      assert assert_linked(violations, "subject :patinet", "links_types.ex", 19) =~
               "is not a subject of #{inspect(@domain)}; did you mean :patient?"

      assert length(violations) == 3
    end
  end

  # Plan DD, L3 (#286): a contract of the scheduling context, beside the settlement one
  # `@body` declares, with a unit and a field that may identify another unit.
  defp scheduling(unit, field_type, opts \\ []) do
    reads = if opts[:reads], do: ", reads: [visit: :visit_id]", else: ""

    """
      aggregate #{inspect(unit)}, "Rezerwacja" do
        identity :booking_id

        command :book, "Zarezerwuj", by: :scheduler, emits: :booked#{reads} do
          field :visit_id, #{field_type}
        end

        event :booked, "Zarezerwowano" do
          field :visit_id, #{field_type}
        end
      end
    """
  end

  defp scheduling_links(name, body, other \\ @body) do
    links([
      {"links_settlement_#{Macro.underscore(name)}.ex", source("Settlement#{name}", other, [])},
      {"#{Macro.underscore(name)}.ex", source(name, body, context: :scheduling)}
    ])
  end

  describe "X3: a unit's identifier names exactly one unit or entity of the domain" do
    test "control: {:id, unit} naming a unit of another contract compiles, and refers to it" do
      assert scheduling_links("LinksUnitRef", scheduling(:booking, "{:id, :visit}")) == []

      model = EhOsContract.Model.fetch(EhOsContract.Fixtures.LinksUnitRef)
      event = Enum.find(model.events, &(&1.name == :booked))

      assert %{type: :id, refers_to: :visit} = Enum.find(event.fields, &(&1.name == :visit_id))
    end

    test "{:id, name} naming neither a unit nor an entity is refused, with a suggestion" do
      violations = scheduling_links("LinksUnitTypo", scheduling(:booking, "{:id, :visti}"))

      assert assert_linked(
               violations,
               "X3: event :booked, field :visit_id: {:id, :visti}",
               "links_unit_typo.ex"
             ) =~
               "names no entity of #{inspect(@domain)} and no unit of its contracts; did you " <>
                 "mean :visit?"

      assert_linked(violations, "X3: command :book, field :visit_id", "links_unit_typo.ex")
      assert length(violations) == 2
    end

    test "a name two units share is refused at the reference, naming both" do
      violations = scheduling_links("LinksUnitTwice", scheduling(:visit, "{:id, :visit}"))

      assert assert_linked(
               violations,
               "X3: event :booked, field :visit_id: {:id, :visit} names more than one",
               "links_unit_twice.ex"
             ) =~
               "unit :visit of EhOsContract.Fixtures.LinksUnitTwice, unit :visit of " <>
                 "EhOsContract.Fixtures.SettlementLinksUnitTwice; a reference cannot tell them " <>
                 "apart, so rename one"

      assert length(violations) == 2
    end

    test "control: two units of one name that nothing refers to are not refused" do
      assert scheduling_links("LinksUnitTwiceUnused", scheduling(:visit, ":id")) == []
    end

    test "a name an entity and a unit share is refused at the reference, naming both" do
      violations = scheduling_links("LinksUnitEntity", scheduling(:clinic, ":id"))

      assert assert_linked(
               violations,
               "X3: event :payment_recorded, field :clinic_id: {:id, :clinic} names more than one",
               "links_settlement_links_unit_entity.ex"
             ) =~ "entity :clinic, unit :clinic of EhOsContract.Fixtures.LinksUnitEntity"

      assert length(violations) == 1
    end

    test "an identity typed as a unit's number is checked too, at the unit" do
      body = """
        aggregate :visit_note, "Notatka do wizyty" do
          identity visit_id: {:id, :visti}
          command :note, "Zanotuj", by: :scheduler, emits: :noted
          event :noted, "Zanotowano"
        end
      """

      violations = scheduling_links("LinksIdentityRef", body)

      assert assert_linked(
               violations,
               "X3: aggregate :visit_note: identity :visit_id: {:id, :visti}",
               "links_identity_ref.ex",
               4
             ) =~
               "names no entity of #{inspect(@domain)} and no unit of its contracts; did you mean :visit?"

      assert length(violations) == 1

      right = String.replace(body, ":visti", ":visit")
      assert scheduling_links("LinksIdentityRefRight", right) == []
    end

    test "A8: a command reading a unit by its identifier is refused" do
      violations =
        scheduling_links("LinksUnitRead", scheduling(:booking, "{:id, :visit}", reads: true))

      assert assert_linked(
               violations,
               "A8: command :book reads :visit by :visit_id",
               "links_unit_read.ex"
             ) =~
               "which identifies unit :visit of EhOsContract.Fixtures.SettlementLinksUnitRead; " <>
                 "a command reads only an entity the application keeps, and a unit's state is its events"

      assert length(violations) == 1
    end
  end

  describe "X3: an entity's identifier names an entity of the domain" do
    test "{:id, entity} naming no entity of the domain is refused" do
      body = String.replace(@body, "{:id, :clinic}", "{:id, :clinc}")
      violations = links("LinksEntity", body)

      assert assert_linked(
               violations,
               "X3: event :payment_recorded, field :clinic_id",
               "links_entity.ex",
               17
             ) =~
               "{:id, :clinc} names no entity of #{inspect(@domain)} and no unit of its " <>
                 "contracts; did you mean :clinic?"

      assert length(violations) == 1
    end

    test "a domain service's result of a type that is no value of the domain is refused" do
      body =
        @body <>
          """
            domain_service :pricing, "Cennik" do
              function :price, "Cena" do
                argument :amount, :money
                returns :mony
              end
            end
          """

      violations = links("LinksServiceReturns", body)

      assert assert_linked(
               violations,
               "X3: domain service :pricing, function :price returns :mony",
               "links_service_returns.ex",
               56
             ) =~
               "which is neither a built-in type nor a value of #{inspect(@domain)}; did you mean :money?"

      assert length(violations) == 1
    end

    test "a domain service returning the identifier of an entity the domain lacks is refused" do
      body =
        @body <>
          """
            domain_service :lookup, "Wyszukiwanie" do
              function :nearest, "Najbliższa przychodnia" do
                argument :city, :string
                returns {:id, :clinc}
              end
            end
          """

      violations = links("LinksServiceEntity", body)

      assert assert_linked(
               violations,
               "X3: domain service :lookup, function :nearest returns {:id, :clinc}",
               "links_service_entity.ex",
               56
             ) =~
               "which names no entity of #{inspect(@domain)} and no unit of its contracts; " <>
                 "did you mean :clinic?"

      assert length(violations) == 1
    end

    test "control: the model holds it as an :id that refers to the entity, and tags it" do
      assert links("LinksEntityRight", @body) == []
      model = EhOsContract.Model.fetch(EhOsContract.Fixtures.LinksEntityRight)
      event = Enum.find(model.events, &(&1.name == :payment_recorded))
      field = Enum.find(event.fields, &(&1.name == :clinic_id))

      assert %{type: :id, refers_to: :clinic} = field
      assert EhOsContract.Key.tag_field?(field)
    end
  end

  describe "F8: a correlation field of a domain value rests on :id" do
    test "a value of another type, in an event and in a manager's state, is refused" do
      body =
        @body
        |> String.replace(
          "      field :patient_id, :id, subject: :patient\n    end\n  end",
          "      field :patient_id, :id, subject: :patient\n      field :clinics, :clinic_ids\n" <>
            "    end\n  end"
        )
        |> String.replace("correlate :visit_id\n", "correlate [:visit_id, :amount]\n")
        |> Kernel.<>("""
          process_manager :chase, "Pogoń" do
            correlate [:visit_id, :clinics, :contact]

            state do
              field :contact, :contact
            end

            starts_on :payment_recorded
          end
        """)

      violations = links("LinksTextCorrelation", body)

      assert assert_linked(
               violations,
               "F8: event :payment_recorded, field :amount tells which run of process :visit",
               "links_text_correlation.ex",
               16
             ) =~ "it is :money, which rests on :integer; correlate only on an identifier"

      assert assert_linked(
               violations,
               "field :clinics tells which run of process manager :chase",
               "links_text_correlation.ex",
               20
             ) =~ "it is :clinic_ids, which rests on {:list, :id}"

      assert assert_linked(
               violations,
               "F8: process manager :chase, state, field :contact is what it correlates on",
               "links_text_correlation.ex"
             ) =~ "it is :contact, which rests on fields of its own"
    end

    test "control: a value resting on :id, or on an entity's identifier, is a correlation field" do
      body =
        @body
        |> String.replace(
          "      field :patient_id, :id, subject: :patient\n    end\n  end",
          "      field :patient_id, :id, subject: :patient\n      field :period_id, :period_id\n" <>
            "      field :clinic, :clinic_ref\n    end\n  end"
        )
        |> String.replace("correlate :visit_id\n", "correlate [:visit_id, :period_id, :clinic]\n")

      assert links("LinksIdCorrelation", body) == []
    end
  end

  describe "F7: no domain value holding personal data where the library keeps it outside the log" do
    test "in a process manager's state, directly, through an alias and in a list, and as a scope" do
      body =
        @body
        |> String.replace(
          "    param :clinic_id, :id\n    scope :clinic_id",
          "    param :clinic_id, :contact\n    scope :clinic_id"
        )
        |> String.replace(
          "    field :clinic_id, :id\n    field :amount, :money",
          "    field :clinic_id, :contact\n    field :amount, :money"
        )
        |> Kernel.<>("""
          process_manager :chase, "Pogoń" do
            correlate :visit_id

            state do
              field :contact, :contact
              field :aliased, :contact_ref
              field :contacts, {:list, :contact}
              field :amount, :money
            end

            starts_on :payment_recorded
          end
        """)

      violations = links("LinksPersonalValues", body)

      assert assert_linked(
               violations,
               "F7: process manager :chase, state, field :contact is of :contact",
               "links_personal_values.ex",
               59
             ) =~
               "which holds personal data, and a process manager's state is stored outside the log"

      assert_linked(
        violations,
        "field :aliased is of :contact_ref",
        "links_personal_values.ex",
        60
      )

      assert_linked(
        violations,
        "field :contacts is of {:list, :contact}",
        "links_personal_values.ex",
        61
      )

      assert assert_linked(
               violations,
               "F7: query :payments_in_clinic, parameter :clinic_id is of :contact",
               "links_personal_values.ex",
               38
             ) =~
               "it is the query's scope, whose value is written with every authorization decision"

      # Since E9c the same scope is also refused for being made of fields (D10).
      assert_linked(
        violations,
        "D10: query :payments_in_clinic is scoped by :clinic_id, a :contact made of fields",
        "links_personal_values.ex",
        38
      )

      # :amount is of :money, which holds nothing personal: the control.
      assert length(violations) == 5
    end
  end

  describe "F5 and D11: personal data inside a domain value, where it would escape erasure" do
    test "a personal field of such a value, and a publication carrying one" do
      body =
        @body
        |> String.replace(
          "field :patient_id, :id, subject: :patient\n    end\n  end",
          "field :patient_id, :id, subject: :patient\n" <>
            "      field :carer, :contact, personal: :patient_id\n" <>
            "      field :contacts, {:list, :contact}\n    end\n  end"
        )
        |> String.replace(
          "fields: [:visit_id, :amount]",
          "fields: [:visit_id, :amount, :contacts]"
        )

      violations = links("LinksPersonalInside", body)

      assert assert_linked(
               violations,
               "F5: event :payment_recorded, field :carer is personal",
               "links_personal_inside.ex",
               20
             ) =~ ":contact holds personal data of its own, which would be sealed under"

      assert assert_linked(
               violations,
               "D11: publication :payment_recorded carries :contacts",
               "links_personal_inside.ex"
             ) =~ "which holds personal data; a copy on a broker cannot be erased"

      # Control: :contacts, not personal itself and not published before, was no problem.
      assert length(violations) == 2
    end
  end

  describe "X4: externals are the domain's" do
    test "since plan EL2, a field's issued_by naming no external; control: one naming one" do
      right =
        String.replace(
          @body,
          "field :amounts, {:list, :money}",
          "field :amounts, {:list, :money}\n      field :claim_no, :id, issued_by: :payer_registry"
        )

      assert links("LinksIssuedRight", right) == []

      violations =
        links(
          "LinksIssuedWrong",
          String.replace(right, "issued_by: :payer_registry", "issued_by: :payer_regstry")
        )

      assert assert_linked(
               violations,
               "X4: event :payment_recorded, field :claim_no: issued_by :payer_regstry is not an external",
               "links_issued_wrong.ex"
             ) =~ "did you mean :payer_registry?"
    end

    test "depends_on and calls naming no external" do
      body =
        @body
        |> String.replace("depends_on: :payer_registry", "depends_on: :payer_regsitry")
        |> String.replace("calls: :payer_registry", "calls: :bank")

      violations = links("LinksExternals", body)

      assert assert_linked(
               violations,
               "X4: event :payment_recorded: depends_on",
               "links_externals.ex",
               15
             ) =~
               "did you mean :payer_registry?"

      assert assert_linked(
               violations,
               "X4: effect :notify_payer: calls :bank",
               "links_externals.ex",
               28
             ) =~
               "is not an external of #{inspect(@domain)}; it declares [:payer_registry]"
    end
  end

  describe "D10: an actor asking a scoped query carries its scope" do
    test "an actor without the scope dimension" do
      violations =
        links(
          "LinksScope",
          String.replace(
            @body,
            "reads: :payments, by: :reception",
            "reads: :payments, by: [:reception, :cashier]"
          )
        )

      assert assert_linked(violations, "D10:", "links_scope.ex", 36) =~
               "query :payments_in_clinic is scoped by :clinic_id, and actor :cashier of " <>
                 "#{inspect(@domain)} does not carry it"

      # :reception carries it, which is the control.
      assert length(violations) == 1
    end
  end

  describe "D10: an actor issuing a scoped command carries its scope" do
    test "an actor without the scope dimension" do
      body =
        @body
        |> String.replace(
          "rejects: :paid_once do\n      field :amount, :money",
          "rejects: :paid_once, scope: :clinic_id do\n      field :clinic_id, :id\n      field :amount, :money"
        )
        |> String.replace(
          ~s|%{amount: 100, patient_id: "p-1"}|,
          ~s|%{amount: 100, patient_id: "p-1", clinic_id: "c-1"}|
        )

      violations = links("LinksCommandScope", body)

      assert assert_linked(violations, "D10:", "links_command_scope.ex", 9) =~
               "command :record_payment is scoped by :clinic_id, and actor :cashier of " <>
                 "#{inspect(@domain)} does not carry it"

      # :reception carries it, which is the control.
      assert length(violations) == 1
    end

    test "a scope typed by a value made of fields" do
      command = """
          command :contact_patient, "Kontakt", by: :reception, emits: :payment_recorded,
            scope: :contact do
            field :contact, :contact
          end

          command :record_payment,\
      """

      body = String.replace(@body, "    command :record_payment,", command, global: false)
      assert body != @body

      violations = links("LinksCompositeScope", body)

      assert Enum.any?(violations, fn %{message: message} ->
               message =~
                 "D10: command :contact_patient is scoped by :contact, a :contact made of fields; " <>
                   "a scope is one value"
             end),
             inspect(violations)
    end

    test "a scope typed by an alias of a value made of fields, or of a list" do
      command = """
          command :contact_patient, "Kontakt", by: :reception, emits: :payment_recorded,
            scope: :contact do
            field :contact, :contact_ref
          end

          command :move_patient, "Przeniesienie", by: :reception, emits: :payment_recorded,
            scope: :clinics do
            field :clinics, :clinic_ids
          end

          command :record_payment,\\
      """

      body = String.replace(@body, "    command :record_payment,", command, global: false)
      messages = Enum.map(links("LinksAliasScope", body), & &1.message)

      assert Enum.any?(
               messages,
               &(&1 =~
                   "command :contact_patient is scoped by :contact, a :contact_ref made of fields")
             )

      assert Enum.any?(
               messages,
               &(&1 =~
                   "command :move_patient is scoped by :clinics, a :clinic_ids which is a list")
             )
    end
  end

  describe "D11: a publication is named under the application's namespace" do
    test "a name under another application's" do
      violations =
        links(
          "LinksNamespace",
          String.replace(
            @body,
            ~s|"clinic.payment.recorded.v1"|,
            ~s|"billing.payment.recorded.v1"|
          )
        )

      assert assert_linked(violations, "D11:", "links_namespace.ex", 42) =~
               ~s|publish :payment_recorded is named "billing.payment.recorded.v1", outside the | <>
                 ~s|application's namespace "clinic."|
    end

    test "control: a namespace with a dash, the domain's name: (#50)" do
      body = dashed(@body, "my-shop.payment.recorded.v1")
      assert links("LinksDashedRight", body, domain: inspect(@dashed), namespace: "my-shop") == []
    end

    test "the same name with an underscore is outside it" do
      violations =
        links("LinksDashedWrong", dashed(@body, "my_shop.payment.recorded.v1"),
          domain: inspect(@dashed),
          namespace: "my-shop"
        )

      assert assert_linked(violations, "D11:", "links_dashed_wrong.ex", 42) =~
               ~s|publish :payment_recorded is named "my_shop.payment.recorded.v1", outside the | <>
                 ~s|application's namespace "my-shop."|

      # The publication is the only thing outside it: the contract's own id is not.
      assert length(violations) == 1
    end
  end

  defp dashed(body, name),
    do: String.replace(body, ~s|"clinic.payment.recorded.v1"|, inspect(name))
end
