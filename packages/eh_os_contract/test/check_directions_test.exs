defmodule EhOsContract.CheckDirectionsTest do
  @moduledoc """
  Plan EL2, "Po EL2" rule 3: **an external used against its `direction:`** — called
  though it only sends to us, or issuing a value or backing an actor though we only
  send to it. Each finding stands at the use, with a `:bidirectional` control.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  setup_all do
    compile(
      """
      defmodule EhOsContract.CheckDirectionsTest.Clinic do
        use EhOsContract.Domain, name: :directions, language: :pl

        subdomain :core, "Rdzeń", type: :core
        context :reporting, "Raporty", subdomain: :core
        actor :reception, :human, "Recepcja"
        actor :bank_feed, :system, "Wyciągi", backed_by: :ksef
        actor :p1_answers, :system, "Odpowiedzi P1", backed_by: :p1
        external :bank, "Bank", direction: :inbound
        external :ksef, "KSeF", direction: :outbound
        external :p1, "P1", direction: :bidirectional
      end

      defmodule EhOsContract.CheckDirectionsTest.Reports do
        use EhOsContract.Next.Contract,
          domain: EhOsContract.CheckDirectionsTest.Clinic,
          context: :reporting

        aggregate :report, "Raport" do
          identity :report_id

          command :file, "Złóż", by: [:reception, :bank_feed, :p1_answers], emits: :filed do
            field :invoice_no, :id, issued_by: :ksef
            field :p1_no, :id, issued_by: :p1
          end

          event :filed, "Złożono"
        end

        effect :ask_bank, "Zapytaj bank", handles: :filed, calls: :bank, idempotency: :report_id
        effect :send_p1, "Wyślij do P1", handles: :filed, calls: :p1, idempotency: :report_id

        process :report, "Raport" do
          correlate :report_id
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "a call to an inbound system, a value and an actor from an outbound one; control: a bidirectional one" do
    found =
      for %Finding{rule: "external-direction-contradicted"} = f <-
            Completeness.findings([EhOsContract.CheckDirectionsTest.Reports]),
          do: {f.message, Finding.place(f)}

    assert [
             {"actor :bank_feed is backed_by: :ksef" <> _, {"clinic.ex", 7}},
             {"effect :ask_bank of EhOsContract.CheckDirectionsTest.Reports calls :bank" <> _,
              {"clinic.ex", 30}},
             {"field :invoice_no is issued_by: :ksef" <> _, {"clinic.ex", 23}}
           ] = Enum.sort(found)
  end
end
