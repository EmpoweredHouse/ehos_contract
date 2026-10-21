defmodule EhOsContract.ExternalOperationsTest do
  @moduledoc """
  Plan EP5a: **what an external system does, and which of it an effect asks for.** An
  external may declare `operation`s, ESDM's `capabilities`; once it does, every
  `calls:` to it names one, `calls: {:registry, :submit_report}` (X4), and `check` warns of
  an operation no effect calls (`operation-never-called`). An external without
  operations is called as before, and its domain's version does not move.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.Completeness
  alias EhOsContract.Contract.Doc
  alias EhOsContract.{Model, Pages}

  @domain EhOsContract.ExternalOperationsTest.Clinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        subdomain :core, "Core", type: :core
        context :reporting, "Reports", subdomain: :core
        actor :specialist, :human, "Specialist"

        external :registry, "Health registry", direction: :bidirectional do
          operation :submit_report, "Accept a report of a medical incident", source: "X-09"
          operation :withdraw_report, "Withdraw the report"
        end

        external :mail, "Mail", direction: :outbound
      end
      """,
      "operations_clinic.ex"
    )

    compile(
      reporting("OperationsModel", """
        effect :send, "Send", handles: :queued,
          calls: [{:registry, :submit_report}, :mail],
          idempotency: [key: :event_id, owner: :downstream]

        effect :notify, "Notify", handles: :queued, calls: :mail,
          idempotency: [key: :event_id, owner: :self]

        effect :resend, "Send again", handles: :queued,
          calls: [{:registry, :submit_report}, {:registry, :submit_report}],
          idempotency: [key: :event_id, owner: :downstream]
      """),
      "operations_model.ex"
    )

    :ok
  end

  defp reporting(name, effects) do
    """
    defmodule EhOsContract.Fixtures.#{name} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :reporting, id: "clinic.#{contract_name(name)}"

      aggregate :report, "Report" do
        identity :report_id
        command :queue, "Queue", by: :specialist, emits: :queued
        event :queued, "Queued"
      end

    #{effects}
    end
    """
  end

  defp links(name, effects),
    do: links([{"#{Macro.underscore(name)}.ex", reporting(name, effects)}])

  describe "the domain" do
    test "keeps an external's operations, and hashes one without them as before" do
      domain = Model.fetch(@domain)
      registry = Enum.find(domain.externals, &(&1.name == :registry))
      mail = Enum.find(domain.externals, &(&1.name == :mail))

      assert [
               %{name: :submit_report, label: "Accept a report of a medical incident"},
               %{name: :withdraw_report, source: nil}
             ] = registry.operations

      assert mail.operations == []

      # The same domain with the operations gone: only the registry's digest and the version move.
      compile(
        """
        defmodule EhOsContract.ExternalOperationsTest.Bare do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core
          context :reporting, "Reports", subdomain: :core
          external :registry, "Health registry", direction: :bidirectional
          external :mail, "Mail", direction: :outbound
        end
        """,
        "operations_bare.ex"
      )

      bare = Model.fetch(EhOsContract.ExternalOperationsTest.Bare)
      assert bare.digests["external:mail"] == domain.digests["external:mail"]
      refute bare.digests["external:registry"] == domain.digests["external:registry"]
    end

    test "D1 refuses an operation named twice, and one not snake_case" do
      message =
        """
        defmodule EhOsContract.ExternalOperationsTest.Dup do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core
          context :reporting, "Reports", subdomain: :core

          external :registry, "Health registry", direction: :bidirectional do
            operation :submit, "Accept"
            operation :submit, "Accept again"
            operation :Withdraw, "Withdraw"
          end
        end
        """
        |> compile_error("operations_dup.ex")
        |> Exception.message()

      assert message =~ "D1: external :registry declares the operation :submit twice"
      assert message =~ "D1: operation :Withdraw of external :registry is not snake_case"
    end
  end

  describe "X4: a call to a system with operations" do
    test "control: a call naming an operation, and a bare call to a system without any" do
      assert links("OperationsRight", """
               effect :send, "Send", handles: :queued,
                 calls: [{:registry, :submit_report}, :mail],
                 idempotency: [key: :event_id, owner: :downstream]
             """) == []
    end

    test "refuses an operation the system does not declare, and a bare call to one that does" do
      violations =
        links("OperationsWrong", """
          effect :send, "Send", handles: :queued, calls: {:registry, :submit_reprot},
            idempotency: [key: :event_id, owner: :downstream]

          effect :resend, "Send again", handles: :queued, calls: :registry,
            idempotency: [key: :event_id, owner: :downstream]
        """)

      assert assert_linked(
               violations,
               "effect :send: calls {:registry, :submit_reprot}",
               "operations_wrong.ex",
               10
             ) =~
               "and :submit_reprot is not an operation of external :registry of " <>
                 "EhOsContract.ExternalOperationsTest.Clinic; did you mean :submit_report?"

      assert assert_linked(
               violations,
               "effect :resend: calls :registry",
               "operations_wrong.ex",
               13
             ) =~
               "external :registry declares what it does, so the call names one of its operations: " <>
                 "{:registry, :submit_report}, {:registry, :withdraw_report}"
    end

    test "refuses an operation of a system without any, and names a repeated call once" do
      violations =
        links("OperationsNone", """
          effect :send, "Send", handles: :queued, calls: [{:mail, :send}, :registry, :registry],
            idempotency: [key: :event_id, owner: :downstream]
        """)

      assert [first, second] = Enum.sort_by(violations, & &1.message)

      assert first.message =~
               "calls :registry, and external :registry declares what it does"

      assert second.message =~
               "calls {:mail, :send}, and external :mail of " <>
                 "EhOsContract.ExternalOperationsTest.Clinic declares no operations, so the " <>
                 "call names the system alone: :mail"
    end

    test "names the system first when it is not one of the domain's" do
      violations =
        links("OperationsNoSystem", """
          effect :send, "Send", handles: :queued, calls: {:p2, :submit_report},
            idempotency: [key: :event_id, owner: :downstream]
        """)

      assert [%{message: message}] = violations
      assert message =~ "X4: effect :send: calls :p2 is not an external of"
    end
  end

  test "check says nothing of the operations of a system no effect calls" do
    compile(
      """
      defmodule EhOsContract.ExternalOperationsTest.Quiet do
        use EhOsContract.Domain, name: :quiet, language: :pl

        subdomain :core, "Core", type: :core
        context :reporting, "Reports", subdomain: :core
        actor :specialist, :human, "Specialist"

        external :registry, "Health registry", direction: :bidirectional do
          operation :submit_report, "Accept a report"
        end
      end

      defmodule EhOsContract.ExternalOperationsTest.QuietReports do
        use EhOsContract.Contract,
          domain: EhOsContract.ExternalOperationsTest.Quiet,
          context: :reporting, id: "quiet.quiet_reports"

        aggregate :report, "Report" do
          identity :report_id
          command :queue, "Queue", by: :specialist, emits: :queued
          event :queued, "Queued"
        end
      end
      """,
      "operations_quiet.ex"
    )

    rules =
      for f <- Completeness.findings([EhOsContract.ExternalOperationsTest.QuietReports]),
          f.rule in ["orphan-external-system", "operation-never-called"],
          do: f.rule

    assert rules == ["orphan-external-system"]
  end

  describe "the model and its readers" do
    setup do
      module = EhOsContract.Fixtures.OperationsModel
      %{module: module, model: Model.fetch(module)}
    end

    test "calls keeps the systems, and the operations named go under their own key", %{
      model: model
    } do
      send = Enum.find(model.effects, &(&1.name == :send))
      notify = Enum.find(model.effects, &(&1.name == :notify))

      assert send.calls == [:registry, :mail]
      assert send.operations == [%{external: :registry, name: :submit_report}]
      assert notify.calls == [:mail]
      refute Map.has_key?(notify, :operations)

      # A call written twice is one call.
      resend = Enum.find(model.effects, &(&1.name == :resend))
      assert resend.calls == [:registry]
      assert resend.operations == [%{external: :registry, name: :submit_report}]
    end

    test "the callback's doc and the pages say the operation", %{model: model} do
      assert Doc.callback(model, :effect, :send, :queued) =~
               "Calls `registry` (`submit_report`), `mail`."

      pages = Pages.render(Model.fetch(@domain), [model])
      text = pages |> Map.values() |> Enum.join("\n")

      assert text =~ "Calls: `registry` (`submit_report`), `mail`."

      assert text =~
               "  - operation `submit_report` — Accept a report of a medical incident · " <>
                 "_source: X-09_"
    end

    test "check warns of an operation no effect calls", %{module: module} do
      assert [finding] =
               for(
                 f <- Completeness.findings([module]),
                 f.rule == "operation-never-called",
                 do: f
               )

      assert finding.message =~
               "operation :withdraw_report of external :registry of " <>
                 "EhOsContract.ExternalOperationsTest.Clinic is called by no effect"

      # It points at the operation, not at its system.
      assert EhOsContract.Check.Finding.place(finding) == {"operations_clinic.ex", 10}
    end
  end
end
