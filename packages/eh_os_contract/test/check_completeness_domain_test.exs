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

        entity :clinic, "Przychodnia", context: :scheduling, identity: :clinic_id do
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
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement

        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :record_payment, "Płatność", by: [:reception, :gateway], emits: :payment_recorded do
            field :clinic_id, {:id, :clinic}
          end

          event :payment_recorded, "Zapłacono" do
            field :clinic_id, {:id, :clinic}
          end
        end

        effect :notify, "Powiadom", handles: :payment_recorded, calls: :sms, idempotency: [key: :visit_id, owner: :self]

        process :visit, "Wizyta" do
          correlate :visit_id
        end
      end

      defmodule #{inspect(@scheduling)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :scheduling

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
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :reporting

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

  test "a scoped actor may not get an application-wide command; control: scoped and unscoped actors" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.ScopedDomain do
        use EhOsContract.Domain, name: :scoped, language: :pl

        subdomain :core, "Core", type: :core
        context :work, "Praca", subdomain: :core
        actor :clerk, :human, "Księgowa", scope: [:company_id]
        actor :administrator, :human, "Administrator"
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.ScopedContract do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.ScopedDomain,
          context: :work

        aggregate :company, "Firma" do
          identity :company_id
          command :rename, "Zmień nazwę", by: :clerk, emits: :renamed
          command :archive, "Archiwizuj", by: :clerk, scope: :company_id, emits: :archived
          command :restore, "Przywróć", by: :administrator, emits: :restored
          event :renamed, "Zmieniono nazwę"
          event :archived, "Zarchiwizowano"
          event :restored, "Przywrócono"
        end

        process :company, "Firma", accountable: :clerk do
          correlate :company_id
        end
      end
      """,
      "scoped_actor.ex"
    )

    contract = EhOsContract.CheckCompletenessDomainTest.ScopedContract

    assert [%Finding{message: message} = finding] =
             for(
               f <- Completeness.findings([contract]),
               f.rule == "scoped-actor-with-unscoped-command",
               do: f
             )

    assert message =~ "actor :clerk"
    assert message =~ "command :rename"
    assert Finding.place(finding) == {"scoped_actor.ex", 17}
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
    assert [{message, {"clinic.ex", 21}}] = findings("orphan-context-mapping")
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
    assert [{message, {"clinic.ex", 26}}] = findings("subdomain-without-bounded-context")
    assert message =~ "subdomain :legacy of #{inspect(@domain)} is the `subdomain:` of no context"
  end

  test "a relation to an external is crossed by a contract that calls it, and uses the external" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.Billing do
        use EhOsContract.Domain, name: :billing, language: :pl

        subdomain :supporting, "Wsparcie", type: :supporting
        context :invoicing, "Fakturowanie", subdomain: :supporting
        context :archive, "Archiwum", subdomain: :supporting
        actor :accountant, :human, "Księgowa"
        external :ksef, "KSeF", direction: :outbound
        external :registry, "Rejestr", direction: :outbound
        relation :conformist, upstream: :ksef, downstream: :invoicing
        relation :conformist, upstream: :registry, downstream: :archive
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Invoices do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Billing,
          context: :invoicing

        aggregate :invoice, "Faktura" do
          identity :invoice_id
          command :issue, "Wystaw", by: :accountant, emits: :issued
          event :issued, "Wystawiono"
        end

        effect :send, "Wyślij do KSeF", handles: :issued, calls: :ksef, idempotency: [key: :invoice_id, owner: :self]

        process :invoice, "Faktura" do
          correlate :invoice_id
        end
      end
      """,
      "billing.ex"
    )

    rules =
      for f <- Completeness.findings([EhOsContract.CheckCompletenessDomainTest.Invoices]),
          f.rule in ["orphan-context-mapping", "orphan-external-system"],
          do: {f.rule, f.message}

    # :registry ends a relation, so it is not an orphan; nothing of :archive calls it,
    # so that relation is. :ksef is called by the effect: its relation is crossed.
    assert [{"orphan-context-mapping", message}] = rules
    assert message =~ "relation :conformist between :registry and :archive"
  end

  test "an external a field is issued by is used, and so is the relation to it" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.ReportsDomain do
        use EhOsContract.Domain, name: :reporting, language: :pl

        subdomain :supporting, "Wsparcie", type: :supporting
        context :reports, "Raporty", subdomain: :supporting
        actor :specialist, :human, "Specjalista"
        external :p1, "P1", direction: :outbound
        relation :conformist, upstream: :p1, downstream: :reports
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Reports do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.ReportsDomain,
          context: :reports

        aggregate :report, "Zgłoszenie" do
          identity :visit_id
          command :note_number, "Zapisz numer", by: :specialist, emits: :numbered do
            field :p1_report_id, :id, issued_by: :p1
          end

          event :numbered, "Zapisano numer" do
            field :p1_report_id, :id, issued_by: :p1
          end
        end

        process :report, "Zgłoszenie" do
          correlate :visit_id
        end
      end
      """,
      "reporting.ex"
    )

    assert for(
             f <- Completeness.findings([EhOsContract.CheckCompletenessDomainTest.Reports]),
             f.rule in ["orphan-context-mapping", "orphan-external-system"],
             do: f
           ) == []
  end

  test "a relation to an external is crossed by an entity it issues, and by a query an actor it backs asks" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.Ledger do
        use EhOsContract.Domain, name: :ledger, language: :pl

        subdomain :supporting, "Wsparcie", type: :supporting
        context :invoicing, "Fakturowanie", subdomain: :supporting
        context :reports, "Raporty", subdomain: :supporting
        actor :accountant, :human, "Księgowa"
        actor :bot, :system, "Robot rejestru", backed_by: :registry
        external :ksef, "KSeF", direction: :outbound
        external :registry, "Rejestr", direction: :inbound
        relation :conformist, upstream: :ksef, downstream: :invoicing
        relation :conformist, upstream: :registry, downstream: :reports

        entity :invoice, "Faktura", context: :invoicing, identity: :number, issued_by: :ksef do
        end
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Invoicing do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Ledger,
          context: :invoicing

        aggregate :draft, "Szkic" do
          identity :draft_id
          command :prepare, "Przygotuj", by: :accountant, emits: :prepared
          event :prepared, "Przygotowano"
        end

        process :draft, "Szkic" do
          correlate :draft_id
        end
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Reports do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Ledger,
          context: :reports

        aggregate :report, "Raport" do
          identity :report_id
          command :file, "Złóż", by: :accountant, emits: :filed
          event :filed, "Złożono"
        end

        read_model :filed_reports, "Raporty", projects: :filed do
          field :report_id, :id
        end

        query :reports, "Raporty", reads: :filed_reports, by: :bot do
          param :report_id, :id
        end

        process :report, "Raport" do
          correlate :report_id
        end
      end
      """,
      "ledger.ex"
    )

    contracts = [
      EhOsContract.CheckCompletenessDomainTest.Invoicing,
      EhOsContract.CheckCompletenessDomainTest.Reports
    ]

    assert for(f <- Completeness.findings(contracts), f.rule == "orphan-context-mapping", do: f) ==
             []
  end

  test "a key named issued_by in a scenario's data is not a field's issuer" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.Desk do
        use EhOsContract.Domain, name: :desk, language: :pl

        subdomain :supporting, "Wsparcie", type: :supporting
        context :desk, "Recepcja", subdomain: :supporting
        actor :reception, :human, "Recepcja"
        external :sms, "SMS", direction: :outbound
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Notes do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Desk,
          context: :desk

        aggregate :note, "Notatka" do
          identity :note_id

          command :write, "Zapisz", by: :reception, emits: :written do
            field :issued_by, {:enum, [:sms, :hand]}
          end

          event :written, "Zapisano" do
            field :issued_by, {:enum, [:sms, :hand]}
          end
        end

        process :note, "Notatka" do
          correlate :note_id
        end

        scenario "zapis ręczny" do
          command :write, %{issued_by: :sms}
          expect :written, %{issued_by: :sms}
        end
      end
      """,
      "desk.ex"
    )

    assert [%{message: message}] =
             for(
               f <- Completeness.findings([EhOsContract.CheckCompletenessDomainTest.Notes]),
               f.rule == "orphan-external-system",
               do: f
             )

    assert message =~ "external :sms"
  end
end
