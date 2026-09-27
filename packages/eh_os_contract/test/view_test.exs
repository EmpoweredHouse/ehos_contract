defmodule EhOsContract.ViewTest do
  @moduledoc """
  Plan EL2: **a domain as a tree for a terminal** (ESDM's `view`): contexts, the
  contracts in each, their units, consumers, read models and queries, with what
  connects them, and with `details:` what each declares.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.View

  @domain EhOsContract.ViewTest.Clinic
  @visits EhOsContract.ViewTest.Visits

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        context :archive, "Archiwum", subdomain: :generic
        actor :reception, :human, "Recepcja"
        external :sms, "Bramka SMS", direction: :outbound
      end

      defmodule #{inspect(@visits)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

        aggregate :visit, "Wizyta" do
          identity :visit_id
          invariant :paid_once, "Wizyta jest opłacona raz"

          command :pay, "Zapłać", by: :reception, emits: :paid, rejects: :paid_once do
            field :amount, :integer
          end

          event :paid, "Zapłacono" do
            field :amount, :integer
          end

          event :noted, "Zanotowano", recorded_by: :reception
        end

        policy :thank, "Podziękuj", handles: :paid, issues: :pay
        effect :text, "SMS", handles: :paid, calls: :sms, idempotency: :visit_id

        read_model :payments, "Płatności", projects: :paid do
          field :amount, :integer
        end

        query :payments_of, "Płatności", reads: :payments, by: :reception do
          param :visit_id, :id
        end

        process :visit, "Wizyta" do
          correlate :visit_id
        end

        scenario "druga płatność odrzucona" do
          given :paid, %{amount: 1}
          command :pay, %{amount: 1}
          rejected :paid_once
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "the domain, its contexts, a contract and what it holds, each with what connects it" do
    assert View.render(@domain, [@visits]) ==
             """
             domain clinic  2 contexts · 1 contract
             ├─ context settlement  Rozliczenia · core · 1 contract
             │  └─ contract #{inspect(@visits)}  process visit
             │     ├─ aggregate visit  1 cmd · 2 evts
             │     │  ├─ command pay  → paid
             │     │  ├─ event paid  ← pay
             │     │  └─ event noted  ← recorded by reception
             │     ├─ policy thank  ← paid → pay
             │     ├─ effect text  ← paid → sms
             │     ├─ read model payments  ← paid
             │     └─ query payments_of  → payments
             └─ context archive  Archiwum · generic · no contract\
             """
  end

  test "one branch, with the declarations under each row" do
    assert View.render(@domain, [@visits], path: [:settlement, :visit], details: true) ==
             """
             domain clinic  2 contexts · 1 contract
             └─ context settlement  Rozliczenia · core · 1 contract
                └─ contract #{inspect(@visits)}  process visit
                   └─ aggregate visit  1 cmd · 2 evts
                      │  identity: visit_id
                      │  invariant paid_once — Wizyta jest opłacona raz
                      ├─ command pay  → paid
                      │     visit_id: :id
                      │     amount: :integer
                      ├─ event paid  ← pay
                      │     visit_id: :id
                      │     amount: :integer
                      └─ event noted  ← recorded by reception
                            visit_id: :id\
             """
  end

  test "control: a contract of another domain is not in the tree" do
    refute View.render(@domain, [ProcessShapes.Next.Bare]) =~ "ProcessShapes"
  end
end
