defmodule EhosContract.CheckDirectionsTest do
  @moduledoc """
  Plan EL2, rule 3 of the prose review: **an external used against its `direction:`** — called
  though it only sends to us, or issuing a value or backing an actor though we only
  send to it; a call to a system that only sends to us is not one, since an effect
  calls to fetch as well. Each finding stands at the use, with controls.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Completeness, Finding}

  setup_all do
    compile(
      """
      defmodule EhosContract.CheckDirectionsTest.Clinic do
        use EhosContract.Domain, name: :directions, language: :en

        subdomain :core, "Core", type: :core
        context :reporting, "Reports", subdomain: :core
        actor :reception, :human, "Front desk"
        actor :bank_feed, :system, "Bank statements", backed_by: :e_invoicing
        actor :registry_answers, :system, "Registry answers", backed_by: :health_registry
        external :bank, "Bank", direction: :inbound
        external :e_invoicing, "E-invoicing registry", direction: :outbound
        external :health_registry, "Health registry", direction: :bidirectional

        entity :invoice, "Invoice", context: :reporting, identity: :number, issued_by: :e_invoicing do
        end
      end

      defmodule EhosContract.CheckDirectionsTest.Reports do
        use EhosContract.Contract,
          domain: EhosContract.CheckDirectionsTest.Clinic,
          context: :reporting, id: "directions.reports"

        aggregate :report, "Report" do
          identity :report_id

          command :file, "File", by: [:reception, :bank_feed, :registry_answers], emits: :filed do
            field :invoice_no, :id, issued_by: :e_invoicing
            field :registry_no, :id, issued_by: :health_registry
          end

          event :filed, "Filed"
        end

        effect :ask_bank, "Ask the bank", handles: :filed, calls: :bank, idempotency: [key: :report_id, owner: :self]
        effect :send_to_registry, "Send to the health registry", handles: :filed, calls: :health_registry, idempotency: [key: :report_id, owner: :self]
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "a value and an actor from an outbound system, in a contract and in the domain; control: a call to an inbound one, a bidirectional one" do
    found =
      for %Finding{rule: "external-direction-contradicted"} = f <-
            Completeness.findings([EhosContract.CheckDirectionsTest.Reports]),
          do: {f.message, Finding.place(f)}

    assert [
             {"actor :bank_feed is backed_by: :e_invoicing" <> _, {"clinic.ex", 7}},
             {"entity :invoice, identity :number is issued_by: :e_invoicing" <> _,
              {"clinic.ex", 13}},
             {"field :invoice_no is issued_by: :e_invoicing" <> _, _command}
           ] = Enum.sort(found)
  end
end
