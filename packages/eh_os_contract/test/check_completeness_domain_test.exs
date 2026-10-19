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
        use EhOsContract.Domain, name: :clinic, language: :en

        context :settlement, "Settlement", subdomain: :core
        context :scheduling, "Scheduling", subdomain: :supporting
        context :reporting, "Reports", subdomain: :generic
        context :archive, "Archive", subdomain: :generic

        actor :reception, :human, "Front desk"
        actor :gateway, :system, "Gateway", backed_by: :payer_registry
        actor :auditor, :human, "Auditor"

        external :payer_registry, "Payer registry", direction: :outbound
        external :sms, "SMS gateway", direction: :outbound
        external :ledger, "Ledger", direction: :outbound

        entity :clinic, "Clinic", context: :scheduling, identity: :clinic_id do
        end

        relation :customer_supplier, upstream: :scheduling, downstream: :settlement
        relation :partnership, between: [:scheduling, :archive]

        subdomain :core, "Core", type: :core
        subdomain :supporting, "Supporting", type: :supporting
        subdomain :generic, "Generic", type: :generic
        subdomain :legacy, "Legacy", type: :generic

        value :money, :integer, unit: :cents, label: "Amount"
        value :room_code, :string
        value :room_kind, {:enum, [:surgery, treatment: "Treatment room"]}, label: "Room kind"
      end
      """,
      "clinic.ex"
    )

    compile(
      """
      defmodule #{inspect(@settlement)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(@settlement)}"

        aggregate :visit, "Visit" do
          identity :visit_id

          command :record_payment, "Payment", by: [:reception, :gateway], emits: :payment_recorded do
            field :clinic_id, {:id, :clinic}
          end

          event :payment_recorded, "Paid" do
            field :clinic_id, {:id, :clinic}
          end
        end

        effect :notify, "Notify", handles: :payment_recorded, calls: :sms, idempotency: [key: :visit_id, owner: :self]
      end

      defmodule #{inspect(@scheduling)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :scheduling, id: "clinic.#{contract_name(@scheduling)}"

        aggregate :slot, "Slot" do
          identity :slot_id
          command :book, "Booking", by: :reception, emits: :booked
          event :booked, "Booked"
        end
      end

      defmodule #{inspect(@reporting)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :reporting, id: "clinic.#{contract_name(@reporting)}"

        consumes #{inspect(@settlement)}, :payment_recorded

        read_model :payments, "Payments", projects: :payment_recorded do
          field :visit_id, :id
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

  # Plan DD, L4 (#326).
  test "a value or an enum member without a label, at the value; control: labelled ones" do
    assert [{code, {"clinic.ex", 29}}, {kind, {"clinic.ex", 30}}] =
             Enum.sort_by(findings("owner-view-without-label"), &elem(&1, 1))

    assert code =~ "value :room_code of #{inspect(@domain)}: the value has no label"
    assert kind =~ "value :room_kind of #{inspect(@domain)}: member :surgery has no label"
  end

  test "an actor no contract names, at its declaration; control: one only a system stands for" do
    assert [{message, {"clinic.ex", 11}}] = findings("orphan-actor")
    assert message =~ "actor :auditor of #{inspect(@domain)} is in no command's or query's `by:`"
  end

  # Plan DD, P2h (#221): a process module's `accountable` gives an actor something to do,
  # as a contract's process did; one of another domain gives this one's nothing.
  test "an actor a process module of the domain holds accountable is named" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.Audit do
        use EhOsContract.Process,
          id: "clinic.audit",
          domain: #{inspect(@domain)},
          label: "Audit",
          accountable: :auditor

        correlate :visit_id
        stage :payment, include: [{#{inspect(@settlement)}, :payment_recorded}]
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.ElsewhereAudit do
        use EhOsContract.Process,
          id: "elsewhere.audit",
          domain: EhOsContract.CheckCompletenessDomainTest.Elsewhere,
          label: "Audit",
          accountable: :auditor

        correlate :visit_id
        stage :payment, include: [{#{inspect(@settlement)}, :payment_recorded}]
      end
      """,
      "audit.ex"
    )

    orphans = fn processes ->
      for %Finding{rule: "orphan-actor"} = f <-
            Completeness.findings([@settlement, @scheduling, @reporting], processes),
          do: f.message
    end

    assert orphans.([EhOsContract.CheckCompletenessDomainTest.Audit]) == []

    assert [message] = orphans.([EhOsContract.CheckCompletenessDomainTest.ElsewhereAudit])
    assert message =~ "actor :auditor of #{inspect(@domain)}"
  end

  test "a scoped actor may not get an application-wide command; control: scoped and unscoped actors" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.ScopedDomain do
        use EhOsContract.Domain, name: :scoped, language: :en

        subdomain :core, "Core", type: :core
        context :work, "Work", subdomain: :core
        actor :clerk, :human, "Accountant", scope: [:company_id]
        actor :administrator, :human, "Administrator"
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.ScopedContract do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.ScopedDomain,
          context: :work, id: "scoped.scoped_contract"

        aggregate :company, "Company" do
          identity :company_id
          command :rename, "Rename", by: :clerk, emits: :renamed
          command :archive, "Archive", by: :clerk, scope: :company_id, emits: :archived
          command :restore, "Restore", by: :administrator, emits: :restored
          event :renamed, "Renamed"
          event :archived, "Archived"
          event :restored, "Restored"
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
    assert [{message, {"contracts.ex", 32}}] =
             findings("cross-bounded-context-reference-without-mapping")

    assert message =~
             "#{inspect(@reporting)} in context :reporting consumes #{inspect(@settlement)} " <>
               "of context :settlement"
  end

  # Plan DD, L3 (#286): a field typed `{:id, unit}` of another context's unit is a
  # reference into that context, as one naming an entity it owns is.
  defp unit_reference(name, relation) do
    domain = Module.concat(__MODULE__, "#{name}Domain")
    scheduling = Module.concat(__MODULE__, "#{name}Scheduling")
    billing = Module.concat(__MODULE__, "#{name}Billing")
    namespace = Macro.underscore(name)

    compile(
      """
      defmodule #{inspect(domain)} do
        use EhOsContract.Domain, name: :#{namespace}, language: :en

        subdomain :supporting, "Support", type: :supporting
        context :scheduling, "Scheduling", subdomain: :supporting
        context :billing, "Settlement", subdomain: :supporting
        actor :reception, :human, "Front desk"
        #{relation}
      end

      defmodule #{inspect(scheduling)} do
        use EhOsContract.Contract, domain: #{inspect(domain)}, context: :scheduling, id: "#{namespace}.scheduling"

        aggregate :appointment, "Visit" do
          identity :appointment_id
          command :book, "Book", by: :reception, emits: :booked
          event :booked, "Booked"
        end
      end

      defmodule #{inspect(billing)} do
        use EhOsContract.Contract, domain: #{inspect(domain)}, context: :billing, id: "#{namespace}.billing"

        aggregate :bill, "Bill" do
          identity :bill_id

          command :charge, "Charge", by: :reception, emits: :charged do
            field :appointment_id, {:id, :appointment}
          end

          event :charged, "Charged" do
            field :appointment_id, {:id, :appointment}
          end
        end
      end
      """,
      "#{namespace}.ex"
    )

    for f <- Completeness.findings([scheduling, billing]),
        f.rule in [
          "cross-bounded-context-reference-without-mapping",
          "orphan-context-mapping"
        ],
        do: {f.rule, f.message}
  end

  test "a field identifying another context's unit with no relation between them" do
    assert [{"cross-bounded-context-reference-without-mapping", message}] =
             unit_reference("UnitUnmapped", "")

    assert message =~
             "UnitUnmappedBilling in context :billing names unit :appointment of " <>
               "#{inspect(__MODULE__)}.UnitUnmappedScheduling of context :scheduling"
  end

  test "a field identifying a unit against the relation's direction is the compiler's (X11), and crosses it" do
    relation = "relation :customer_supplier, upstream: :billing, downstream: :scheduling"
    assert unit_reference("UnitAgainst", relation) == []
  end

  test "control: a relation the unit reference follows, crossed and not orphaned" do
    relation = "relation :customer_supplier, upstream: :scheduling, downstream: :billing"
    assert unit_reference("UnitMapped", relation) == []
  end

  test "a subdomain no context belongs to; control: the three contexts name theirs" do
    assert [{message, {"clinic.ex", 26}}] = findings("subdomain-without-bounded-context")
    assert message =~ "subdomain :legacy of #{inspect(@domain)} is the `subdomain:` of no context"
  end

  test "a relation to an external is crossed by a contract that calls it, and uses the external" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.Billing do
        use EhOsContract.Domain, name: :billing, language: :en

        subdomain :supporting, "Support", type: :supporting
        context :invoicing, "Invoicing", subdomain: :supporting
        context :archive, "Archive", subdomain: :supporting
        actor :accountant, :human, "Accountant"
        external :e_invoicing, "E-invoicing registry", direction: :outbound
        external :registry, "Registry", direction: :outbound
        relation :conformist, upstream: :e_invoicing, downstream: :invoicing
        relation :conformist, upstream: :registry, downstream: :archive
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Invoices do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Billing,
          context: :invoicing, id: "billing.invoices"

        aggregate :invoice, "Invoice" do
          identity :invoice_id
          command :issue, "Issue", by: :accountant, emits: :issued
          event :issued, "Issued"
        end

        effect :send, "Send to the e-invoicing registry", handles: :issued, calls: :e_invoicing, idempotency: [key: :invoice_id, owner: :self]
      end
      """,
      "billing.ex"
    )

    rules =
      for f <- Completeness.findings([EhOsContract.CheckCompletenessDomainTest.Invoices]),
          f.rule in ["orphan-context-mapping", "orphan-external-system"],
          do: {f.rule, f.message}

    # :registry ends a relation, so it is not an orphan; nothing of :archive calls it,
    # so that relation is. :e_invoicing is called by the effect: its relation is crossed.
    assert [{"orphan-context-mapping", message}] = rules
    assert message =~ "relation :conformist between :registry and :archive"
  end

  test "an external a field is issued by is used, and so is the relation to it" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessDomainTest.ReportsDomain do
        use EhOsContract.Domain, name: :reporting, language: :en

        subdomain :supporting, "Support", type: :supporting
        context :reports, "Reports", subdomain: :supporting
        actor :specialist, :human, "Specialist"
        external :health_registry, "Health registry", direction: :outbound
        relation :conformist, upstream: :health_registry, downstream: :reports
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Reports do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.ReportsDomain,
          context: :reports, id: "reporting.reports"

        aggregate :report, "Report" do
          identity :visit_id
          command :note_number, "Note the number", by: :specialist, emits: :numbered do
            field :registry_report_id, :id, issued_by: :health_registry
          end

          event :numbered, "Number noted" do
            field :registry_report_id, :id, issued_by: :health_registry
          end
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
        use EhOsContract.Domain, name: :ledger, language: :en

        subdomain :supporting, "Support", type: :supporting
        context :invoicing, "Invoicing", subdomain: :supporting
        context :reports, "Reports", subdomain: :supporting
        actor :accountant, :human, "Accountant"
        actor :bot, :system, "Registry robot", backed_by: :registry
        external :e_invoicing, "E-invoicing registry", direction: :outbound
        external :registry, "Registry", direction: :inbound
        relation :conformist, upstream: :e_invoicing, downstream: :invoicing
        relation :conformist, upstream: :registry, downstream: :reports

        entity :invoice, "Invoice", context: :invoicing, identity: :number, issued_by: :e_invoicing do
        end
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Invoicing do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Ledger,
          context: :invoicing, id: "ledger.invoicing"

        aggregate :draft, "Draft" do
          identity :draft_id
          command :prepare, "Prepare", by: :accountant, emits: :prepared
          event :prepared, "Prepared"
        end
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Reports do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Ledger,
          context: :reports, id: "ledger.reports"

        aggregate :report, "Report" do
          identity :report_id
          command :file, "File", by: :accountant, emits: :filed
          event :filed, "Filed"
        end

        read_model :filed_reports, "Reports", projects: :filed do
          field :report_id, :id
        end

        query :reports, "Reports", reads: :filed_reports, by: :bot do
          param :report_id, :id
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
        use EhOsContract.Domain, name: :desk, language: :en

        subdomain :supporting, "Support", type: :supporting
        context :desk, "Front desk", subdomain: :supporting
        actor :reception, :human, "Front desk"
        external :sms, "SMS", direction: :outbound
      end

      defmodule EhOsContract.CheckCompletenessDomainTest.Notes do
        use EhOsContract.Contract,
          domain: EhOsContract.CheckCompletenessDomainTest.Desk,
          context: :desk, id: "desk.notes"

        aggregate :note, "Note" do
          identity :note_id

          command :write, "Write", by: :reception, emits: :written do
            field :issued_by, {:enum, [:sms, :hand]}
          end

          event :written, "Written" do
            field :issued_by, {:enum, [:sms, :hand]}
          end
        end

        scenario "written by hand" do
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
