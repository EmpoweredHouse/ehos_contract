defmodule EhosContract.SourcesTest do
  @moduledoc """
  Plan EP1: **`source:` on every declaration** — where it comes from in the workshop
  material, the first rung of the ladder from prose to a test. Every kind keeps the key
  in the model, `nil` or not. Since plan DD, V5 (#322) a source is one of the words: it
  moves the text digests and not the version.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.{Model, Pages}

  @sourced """
    aggregate :visit, "Visit" do
      identity :visit_id

      command :close_visit, "Close the visit", by: :reception, emits: :visit_closed
      command :report_visit, "Report the visit", emits: :visit_reported

      event :visit_closed, "Visit closed"
      event :visit_reported, "Visit reported"
    end

    policy :report_on_close, "A closed visit is reported",
      handles: :visit_closed, issues: :report_visit, source: "Q-21"

    effect :notify_registry, "Notify the registry",
      handles: :visit_reported, idempotency: [key: :event_id, owner: :self], source: "Q-22"

    process_manager :chase, "Chasing the report", source: "Q-23" do
      correlate :visit_id
      starts_on :visit_closed, sets: :due
      timer :due, "Due", wait: {24, :hour}, issues: :report_visit, source: "K14"
      ends_on :visit_reported
    end

    read_model :visits, "Visits", projects: :visit_closed, source: "V-31" do
      field :visit_id, :id
    end

    query :visits_of, "Reception's visits", reads: :visits, by: :reception, source: "V-32" do
      param :visit_id, :id
    end
  """

  @unsourced """
    aggregate :visit, "Visit" do
      identity :visit_id

      command :close_visit, "Close the visit", by: :reception, emits: :visit_closed
      command :report_visit, "Report the visit", emits: :visit_reported

      event :visit_closed, "Visit closed"
      event :visit_reported, "Visit reported"
    end

    policy :report_on_close, "A closed visit is reported",
      handles: :visit_closed, issues: :report_visit

    effect :notify_registry, "Notify the registry", handles: :visit_reported, idempotency: [key: :event_id, owner: :self]

    process_manager :chase, "Chasing the report" do
      correlate :visit_id
      starts_on :visit_closed, sets: :due
      timer :due, "Due", wait: {24, :hour}, issues: :report_visit
      ends_on :visit_reported
    end

    read_model :visits, "Visits", projects: :visit_closed do
      field :visit_id, :id
    end

    query :visits_of, "Reception's visits", reads: :visits, by: :reception do
      param :visit_id, :id
    end
  """

  defp domain(name, body) do
    compile(
      """
      defmodule EhosContract.SourcesTest.#{name} do
        use EhosContract.Domain, name: :clinic, language: :pl

      #{body}
      end
      """,
      "#{Macro.underscore(name)}.ex"
    )

    Model.fetch(Module.concat(EhosContract.SourcesTest, name))
  end

  @domain_sourced """
    context :settlement, "Settlement", subdomain: :billing
    context :scheduling, "Schedule", subdomain: :billing
    subdomain :billing, "Settlement", type: :supporting

    actor :reception, :human, "Reception", source: "M1 00:03:10"
    subject :patient, "Patient", source: "GDPR"
    value :money, :integer, unit: :cents, source: "E-82"
    external :registry, "Health registry", direction: :outbound, source: "Example Act, s. 12"
    relation :customer_supplier, upstream: :scheduling, downstream: :settlement, source: "M2"
    relation :partnership, between: [:settlement, :scheduling], source: "M3"
  """

  @domain_unsourced """
    context :settlement, "Settlement", subdomain: :billing
    context :scheduling, "Schedule", subdomain: :billing
    subdomain :billing, "Settlement", type: :supporting

    actor :reception, :human, "Reception"
    subject :patient, "Patient"
    value :money, :integer, unit: :cents
    external :registry, "Health registry", direction: :outbound
    relation :customer_supplier, upstream: :scheduling, downstream: :settlement
  """

  setup_all do
    %{
      sourced: compile_contract("Sourced", @sourced, id: "clinic.visits"),
      unsourced: compile_contract("Unsourced", @unsourced, id: "clinic.visits")
    }
  end

  describe "a contract" do
    test "keeps each declaration's source in the model", %{sourced: model} do
      [policy] = model.policies
      [effect] = model.effects
      [pm] = model.process_managers
      [timer] = pm.timers
      [read_model] = model.read_models
      [query] = model.queries

      assert {policy.source, effect.source, pm.source, timer.source} ==
               {"Q-21", "Q-22", "Q-23", "K14"}

      assert {read_model.source, query.source} == {"V-31", "V-32"}
    end

    test "without one, keeps the key as nil", %{
      unsourced: model
    } do
      [pm] = model.process_managers

      for declaration <-
            model.policies ++
              model.effects ++
              model.process_managers ++
              pm.timers ++ model.read_models ++ model.queries do
        assert Map.fetch!(declaration, :source) == nil, inspect(declaration)
      end
    end

    test "a source moves the declaration's words and not the version", %{
      sourced: sourced,
      unsourced: unsourced
    } do
      assert sourced.version == unsourced.version
      assert sourced.digests == unsourced.digests
      refute sourced.text_digest == unsourced.text_digest

      moved =
        for {key, digest} <- sourced.text_digests,
            unsourced.text_digests[key] != digest,
            do: key

      assert Enum.sort(moved) ==
               Enum.sort([
                 "policy:report_on_close",
                 "effect:notify_registry",
                 "process_manager:chase",
                 "read_model:visits",
                 "query:visits_of"
               ])
    end
  end

  describe "a domain" do
    test "keeps each declaration's source in the model" do
      model = domain("Sourced", @domain_sourced)

      assert [%{source: "M1 00:03:10"}] = model.actors
      assert [%{source: "GDPR"}] = model.subjects
      assert [%{source: "E-82"}] = model.values
      assert [%{source: "Example Act, s. 12"}] = model.externals
      assert [%{source: "M2"}, %{source: "M3"}] = model.relations
    end

    test "without one, keeps the key as nil" do
      model = domain("Unsourced", @domain_unsourced)

      for declaration <-
            model.actors ++ model.subjects ++ model.values ++ model.externals ++ model.relations do
        assert Map.fetch!(declaration, :source) == nil, inspect(declaration)
      end
    end
  end

  describe "the pages" do
    test "say where each declaration comes from" do
      domain = domain("Paged", @domain_sourced)
      contract = %{compile_contract("Paged", @sourced) | domain: domain.module}
      pages = Pages.render(domain, [contract])
      dir = "settlement/paged"

      index = pages["index.md"]
      assert index =~ "- `reception` — Reception · human · _source: M1 00:03:10_"
      assert index =~ "- `patient` — Patient · _source: GDPR_"
      assert index =~ "- `registry` — Health registry · outbound · _source: Example Act, s. 12_"
      assert index =~ "[`settlement`](settlement/index.md) · _source: M2_"
      assert index =~ "[`scheduling`](scheduling/index.md) · _source: M3_"
      assert pages["values/money.md"] =~ "_Source: E-82_"

      assert pages["#{dir}/policies/report_on_close.md"] =~ "_Source: Q-21_"
      assert pages["#{dir}/effects/notify_registry.md"] =~ "_Source: Q-22_"
      assert pages["#{dir}/process_managers/chase.md"] =~ "_Source: Q-23_"
      assert pages["#{dir}/process_managers/chase.md"] =~ "· _source: K14_"
      assert pages["#{dir}/read_models/visits.md"] =~ "_Source: V-31_"
      assert pages["#{dir}/queries/visits_of.md"] =~ "_Source: V-32_"
    end
  end
end
