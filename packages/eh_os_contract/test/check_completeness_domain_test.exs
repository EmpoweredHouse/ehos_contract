defmodule EhOsContract.CheckCompletenessDomainTest do
  @moduledoc """
  Plan EL1: **ESDM's completeness rules that read a whole domain** — an actor, an
  external, a context or a relation no contract uses, and a reference into another
  context no relation covers. Each finding points at the declaration it is about,
  and each rule has a control beside it that it leaves alone.

  The fixture is one invented clinic domain and three contracts, compiled here and
  handed to the rules directly, so none of it joins the registry and warns in this
  package's own `mix eh_os_contract.check`.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @domain EhOsContract.CheckCompletenessDomainTest.Clinic
  @settlement EhOsContract.CheckCompletenessDomainTest.Settlement
  @scheduling EhOsContract.CheckCompletenessDomainTest.Scheduling
  @reporting EhOsContract.CheckCompletenessDomainTest.Reporting

  setup_all do
    # Line numbers below are the file's: `defmodule` is line 1.
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        context :scheduling, "Terminarz", subdomain: :supporting
        context :reporting, "Raporty", subdomain: :generic
        context :archive, "Archiwum", subdomain: :generic

        actor :reception, :human, "Recepcja"
        actor :gateway, :system, "Bramka", backed_by: :payer_registry
        actor :auditor, :human, "Audytor"

        external :payer_registry, "Rejestr płatnika", direction: :outbound
        external :sms, "Bramka SMS", direction: :outbound
        external :ledger, "Księga", direction: :outbound

        entity :clinic, "Przychodnia", context: :scheduling, identified_by: :clinic_id do
          field :clinic_id, :id
        end

        relation :customer_supplier, upstream: :scheduling, downstream: :settlement
        relation :partnership, between: [:scheduling, :archive]

        subdomain :core, "Core", type: :core
        subdomain :supporting, "Supporting", type: :supporting
        subdomain :generic, "Generic", type: :generic
        subdomain :legacy, "Dawne", type: :generic
      end
      """,
      "clinic.ex"
    )

    compile(
      """
      defmodule #{inspect(@settlement)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :record_payment, "Płatność", by: [:reception, :gateway], emits: :payment_recorded do
            field :clinic_id, {:id, :clinic}
          end

          event :payment_recorded, "Zapłacono" do
            field :clinic_id, {:id, :clinic}
          end
        end

        effect :notify, "Powiadom", handles: :payment_recorded, calls: :sms, idempotency: :visit_id

        process :visit, "Wizyta" do
          correlate :visit_id
        end
      end

      defmodule #{inspect(@scheduling)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :scheduling

        aggregate :slot, "Termin" do
          identity :slot_id
          command :book, "Rezerwacja", by: :reception, emits: :booked
          event :booked, "Zarezerwowano"
        end

        process :slot, "Termin" do
          correlate :slot_id
        end
      end

      defmodule #{inspect(@reporting)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :reporting

        consumes #{inspect(@settlement)}, :payment_recorded

        read_model :payments, "Płatności", projects: :payment_recorded do
          field :visit_id, :id
        end

        process :reporting, "Raporty" do
          correlate :visit_id
        end
      end
      """,
      "contracts.ex"
    )

    :ok
  end

  defp findings(rule) do
    for %Finding{rule: ^rule} = f <-
          Completeness.findings([@settlement, @scheduling, @reporting]),
        do: {f.message, Finding.place(f)}
  end

  test "an actor no contract names, at its declaration; control: one only a system stands for" do
    assert [{message, {"clinic.ex", 11}}] = findings("orphan-actor")
    assert message =~ "actor :auditor of #{inspect(@domain)} is in no command's or query's `by:`"
  end

  test "an external nothing uses; control: one an actor stands for, one an effect calls" do
    assert [{message, {"clinic.ex", 15}}] = findings("orphan-external-system")
    assert message =~ "external :ledger"
  end

  test "a context no contract belongs to; control: the three that have one" do
    assert [{message, {"clinic.ex", 7}}] = findings("bounded-context-without-content")
    assert message =~ "context :archive"
  end

  test "a relation nothing crosses; control: one an entity reference crosses" do
    assert [{message, {"clinic.ex", 22}}] = findings("orphan-context-mapping")
    assert message =~ "relation :partnership between :archive and :scheduling"
  end

  test "a contract consuming one of another context with no relation between them" do
    # Reporting consumes Settlement, and nothing relates the two contexts; Settlement
    # names Scheduling's entity, which the customer-supplier relation covers.
    assert [{message, {"contracts.ex", 40}}] =
             findings("cross-bounded-context-reference-without-mapping")

    assert message =~
             "#{inspect(@reporting)} in context :reporting consumes #{inspect(@settlement)} " <>
               "of context :settlement"
  end

  test "a subdomain no context belongs to; control: the three contexts name theirs" do
    assert [{message, {"clinic.ex", 27}}] = findings("subdomain-without-bounded-context")
    assert message =~ "subdomain :legacy of #{inspect(@domain)} is the `subdomain:` of no context"
  end
end
