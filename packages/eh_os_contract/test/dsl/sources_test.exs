defmodule EhOsContract.SourcesTest do
  @moduledoc """
  Plan EP1: **`source:` on every declaration** — where it comes from in the workshop
  material, the first rung of the ladder from prose to a test. The kinds that had it
  from the start keep it in the model `nil` or not; the kinds that took it in EP1 keep
  it only where it is set, so no declaration written without it moves its digest.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.{Digest, Model, Pages}

  @sourced """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      command :close_visit, "Zamknij wizytę", by: :reception, emits: :visit_closed
      command :report_visit, "Zgłoś wizytę", emits: :visit_reported

      event :visit_closed, "Wizyta zamknięta"
      event :visit_reported, "Wizyta zgłoszona"
    end

    policy :report_on_close, "Zamknięta wizyta jest zgłaszana",
      handles: :visit_closed, issues: :report_visit, source: "P-07"

    effect :notify_registry, "Powiadom rejestr",
      handles: :visit_reported, idempotency: :event_id, source: "P-08"

    process_manager :chase, "Pogoń za zgłoszeniem", source: "P-09" do
      correlate :visit_id
      starts_on :visit_closed, sets: :due
      timer :due, wait: {24, :hour}, issues: :report_visit, source: "H21"
      ends_on :visit_reported
    end

    read_model :visits, "Wizyty", projects: :visit_closed, source: "R-01" do
      field :visit_id, :id
    end

    query :visits_of, "Wizyty recepcji", reads: :visits, by: :reception, source: "R-02" do
      param :visit_id, :id
    end

    process :visit, "Wizyta", source: "W1 00:12:00" do
      correlate :visit_id
    end
  """

  @unsourced """
    aggregate :visit, "Wizyta" do
      identity :visit_id

      command :close_visit, "Zamknij wizytę", by: :reception, emits: :visit_closed
      command :report_visit, "Zgłoś wizytę", emits: :visit_reported

      event :visit_closed, "Wizyta zamknięta"
      event :visit_reported, "Wizyta zgłoszona"
    end

    policy :report_on_close, "Zamknięta wizyta jest zgłaszana",
      handles: :visit_closed, issues: :report_visit

    effect :notify_registry, "Powiadom rejestr", handles: :visit_reported, idempotency: :event_id

    process_manager :chase, "Pogoń za zgłoszeniem" do
      correlate :visit_id
      starts_on :visit_closed, sets: :due
      timer :due, wait: {24, :hour}, issues: :report_visit
      ends_on :visit_reported
    end

    read_model :visits, "Wizyty", projects: :visit_closed do
      field :visit_id, :id
    end

    query :visits_of, "Wizyty recepcji", reads: :visits, by: :reception do
      param :visit_id, :id
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end
  """

  defp domain(name, body) do
    compile(
      """
      defmodule EhOsContract.SourcesTest.#{name} do
        use EhOsContract.Domain, name: :clinic, language: :pl

      #{body}
      end
      """,
      "#{Macro.underscore(name)}.ex"
    )

    Model.fetch(Module.concat(EhOsContract.SourcesTest, name))
  end

  @domain_sourced """
    context :settlement, "Rozliczenia", subdomain: :billing
    context :scheduling, "Grafik", subdomain: :billing
    subdomain :billing, "Rozliczenia", type: :supporting

    actor :reception, :human, "Recepcja", source: "W1 00:03:10"
    subject :patient, "Pacjent", source: "RODO"
    value :money, :integer, unit: :grosze, source: "E-55"
    external :p1, "Rejestr P1", direction: :outbound, source: "Dz.U. 2025 poz. 866"
    relation :customer_supplier, upstream: :scheduling, downstream: :settlement, source: "W2"
  """

  @domain_unsourced """
    context :settlement, "Rozliczenia", subdomain: :billing
    context :scheduling, "Grafik", subdomain: :billing
    subdomain :billing, "Rozliczenia", type: :supporting

    actor :reception, :human, "Recepcja"
    subject :patient, "Pacjent"
    value :money, :integer, unit: :grosze
    external :p1, "Rejestr P1", direction: :outbound
    relation :customer_supplier, upstream: :scheduling, downstream: :settlement
  """

  setup_all do
    %{
      sourced: compile_contract("Sourced", @sourced),
      unsourced: compile_contract("Unsourced", @unsourced)
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
               {"P-07", "P-08", "P-09", "H21"}

      assert {read_model.source, query.source, model.process.source} ==
               {"R-01", "R-02", "W1 00:12:00"}
    end

    test "leaves the key out where it is not set, so no digest moves", %{unsourced: model} do
      [pm] = model.process_managers

      for declaration <-
            model.policies ++
              model.effects ++
              model.process_managers ++
              pm.timers ++ model.read_models ++ model.queries ++ [model.process] do
        refute Map.has_key?(declaration, :source), inspect(declaration)
      end
    end

    test "a source moves the declaration's digest and nothing else's", %{
      sourced: sourced,
      unsourced: unsourced
    } do
      moved =
        for {key, digest} <- sourced.digests, unsourced.digests[key] != digest, do: key

      assert Enum.sort(moved) ==
               Enum.sort([
                 "policy:report_on_close",
                 "effect:notify_registry",
                 "process_manager:chase",
                 "read_model:visits",
                 "query:visits_of",
                 "process:visit"
               ])
    end
  end

  describe "a domain" do
    test "keeps each declaration's source in the model" do
      model = domain("Sourced", @domain_sourced)

      assert [%{source: "W1 00:03:10"}] = model.actors
      assert [%{source: "RODO"}] = model.subjects
      assert [%{source: "E-55"}] = model.values
      assert [%{source: "Dz.U. 2025 poz. 866"}] = model.externals
      assert [%{source: "W2"}] = model.relations
    end

    test "leaves the key out where it is not set, so no digest moves" do
      model = domain("Unsourced", @domain_unsourced)

      for declaration <-
            model.actors ++ model.subjects ++ model.values ++ model.externals ++ model.relations do
        refute Map.has_key?(declaration, :source), inspect(declaration)
      end

      [actor] = model.actors
      assert model.digests["actor:reception"] == Digest.hash(actor)
    end
  end

  describe "the pages" do
    test "say where each declaration comes from" do
      domain = domain("Paged", @domain_sourced)
      contract = %{compile_contract("Paged", @sourced) | domain: domain.module}
      pages = Pages.render(domain, [contract])
      dir = "settlement/paged"

      index = pages["index.md"]
      assert index =~ "- `reception` — Recepcja · human · _source: W1 00:03:10_"
      assert index =~ "- `patient` — Pacjent · _source: RODO_"
      assert index =~ "- `p1` — Rejestr P1 · outbound · _source: Dz.U. 2025 poz. 866_"
      assert index =~ "· _source: W2_"
      assert pages["values/money.md"] =~ "_Source: E-55_"

      assert pages["#{dir}/policies/report_on_close.md"] =~ "_Source: P-07_"
      assert pages["#{dir}/effects/notify_registry.md"] =~ "_Source: P-08_"
      assert pages["#{dir}/process_managers/chase.md"] =~ "_Source: P-09_"
      assert pages["#{dir}/process_managers/chase.md"] =~ "· _source: H21_"
      assert pages["#{dir}/read_models/visits.md"] =~ "_Source: R-01_"
      assert pages["#{dir}/queries/visits_of.md"] =~ "_Source: R-02_"
      assert pages["#{dir}/index.md"] =~ "_Source: W1 00:12:00_"
    end
  end
end
