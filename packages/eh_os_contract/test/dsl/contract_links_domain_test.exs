defmodule EhOsContract.Next.ContractLinksDomainTest do
  @moduledoc """
  v2 plan, E5b: **the L3 rules that read the domain** — X1–X4, and the parts of D10
  and D11 a contract cannot check alone (v2 §6, §16). Each violation names the
  declaration's file and line, and has a control beside it that passes.
  """

  use EhOsContract.DslCase, async: false

  @domain EhOsContract.Next.Fixtures.LinksClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        context :scheduling, "Terminarz", subdomain: :supporting

        actor :reception, :human, "Recepcja", scope: [:clinic_id]
        actor :cashier, :human, "Kasjer"
        actor :scheduler, :human, "Rejestracja", context: :scheduling

        subject :patient, "Pacjent"
        value :money, :integer, unit: :grosze
        external :payer_registry, "Rejestr płatnika", direction: :outbound
      end
      """,
      "links_clinic.ex"
    )

    :ok
  end

  # Line 4 of the file is the first line of the body.
  defp source(name, body, opts) do
    domain = Keyword.get(opts, :domain, inspect(@domain))
    context = Keyword.get(opts, :context, :settlement)

    """
    defmodule EhOsContract.Next.Fixtures.#{name} do
      use EhOsContract.Next.Contract, domain: #{domain}, context: #{inspect(context)}

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
        field :clinic_id, :id
        field :amounts, {:list, :money}
        field :patient_id, :id, subject: :patient
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
      accountable :reception
    end

    effect :notify_payer, "Powiadom płatnika", handles: :payment_recorded,
      calls: :payer_registry, idempotency: :visit_id

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
      violations = links("LinksNoDomain", @body, domain: "EhOsContract.Next.Fixtures.Nowhere")

      assert assert_linked(violations, "X1:", "links_no_domain.ex", 2) =~
               "names domain EhOsContract.Next.Fixtures.Nowhere, which is not a compiled " <>
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

        process :slot, "Termin" do
          correlate :slot_id
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

  describe "X4: externals are the domain's" do
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
  end
end
