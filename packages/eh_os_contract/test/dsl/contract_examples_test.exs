defmodule EhOsContract.Next.ContractExamplesTest do
  @moduledoc """
  v2 plan, E4, acceptance: **the examples of v2 §4.5–4.6 compile in the notation
  they are written in**, apart from what D10–D12 changed.

  The examples are read from `docs/adr/contract-v2.md` itself rather than copied
  here, so an edit to an example there is checked here at once. The changes this
  test makes to them are listed in `@amendments`, each with its reason, and each
  must find its text: an amendment that no longer applies fails rather than passing
  silently.

  What the examples show and E4 does not build is left out, by name: the
  implementation modules and the scenario test (E5), and the dispatch through
  `EhOsContract.Capability` (E6). §4.6's fragments are declarations out of their
  contracts, so each is compiled inside the least contract that gives it the events,
  commands and process it names; that surrounding code is this test's, and the
  fragment itself stays as the ADR writes it.

  The ADR lives outside this package. Where the package is tested alone, without
  the repository around it, the file is missing and the tests are skipped.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model

  @adr Path.expand("../../../../docs/adr/contract-v2.md", __DIR__)

  # {text in the ADR, text compiled, why}
  @amendments [
    {"use EhOsContract.Contract, domain:", "use EhOsContract.Next.Contract, domain:",
     "the v2 DSL is EhOsContract.Next.Contract until the cut renames it (E11)"},
    {~s|"Dane firmy zgadzają się z rejestrami", public: true|,
     ~s|"Dane firmy zgadzają się z rejestrami"|,
     "D11: public: retired; a sibling process consumes the event without a flag"},
    {"by: [:reception, :manager] do\n  field :business_date, :date",
     "by: [:reception, :manager] do\n  param :business_date, :date",
     "D10: param replaces field for a query's parameters"},
    {~s|  context :scheduling, "Umawianie i zasoby", subdomain: :core|,
     ~s|  subdomain :core, "Rdzeń", type: :core\n| <>
       ~s|  subdomain :supporting, "Wsparcie", type: :supporting\n| <>
       ~s|  context :scheduling, "Umawianie i zasoby", subdomain: :core|,
     "plan EL2: a context names a subdomain the domain declares (D7)"}
  ]

  unless File.exists?(@adr),
    do: @moduletag(skip: "#{@adr} is not here: the package is tested alone")

  # §4.5's domain and contract are compiled once, here: two tests read them.
  setup_all do
    if File.exists?(@adr) do
      adr = File.read!(@adr)
      [domain, contract | _] = blocks(section(adr, "4.5"))
      compile(amend(domain), "rehmed/domain.ex")
      compile(amend(contract), "rehmed/contracts/visit_settlement.ex")
      %{four_six: fragments(section(adr, "4.6"))}
    else
      :ok
    end
  end

  describe "v2 §4.5, Rehmed VisitSettlement" do
    test "the domain and the contract compile as written" do
      model = Model.fetch(Rehmed.Contracts.VisitSettlement)
      assert %{domain: Rehmed.Domain, context: :settlement} = model
      assert Enum.map(model.units, & &1.name) == [:visit_settlement]
      assert length(model.commands) == 5
      assert length(model.scenarios) == 4
      assert Enum.map(model.process.stages, & &1.name) == [:charging, :payment]

      assert Enum.map(Model.fetch(Rehmed.Domain).actors, & &1.name) ==
               [:reception, :specialist, :manager]
    end

    test "§4.6's capabilities are what the contract derives", %{four_six: fragments} do
      # `#=> %{reception: %{commands: [...], queries: []}, ...}` is written per actor.
      # Since D14 that view is the model's `grants`, and `Model.capabilities/1` gives
      # the same capabilities under the names EHOS grants: `rehmed.<command>`.
      [_, expected] =
        Regex.run(
          ~r/#=> %\{reception: (%\{commands: \[[^\]]*\], queries: \[\]\})/,
          fragments.capabilities
        )

      {expected, _} = Code.eval_string(expected)
      model = Model.fetch(Rehmed.Contracts.VisitSettlement)

      assert Map.take(model.grants.reception, [:commands, :queries]) == expected

      reception =
        for {name, %{roles: roles}} <- Model.capabilities(model),
            "rehmed.reception" in roles,
            do: name

      assert Enum.sort(reception) == Enum.map(expected.commands, &"rehmed.#{&1}")
    end
  end

  describe "v2 §4.6, the other kinds" do
    test "consumes and a policy, with the event it consumes (TaxVision)", %{four_six: f} do
      [publisher, subscriber] = String.split(f.consumes, "\n\n", parts: 2)

      compile_example("AccountingMonth", """
        use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :accounting

        aggregate :accounting_month, "Miesiąc księgowy" do
          identity [:company_id, :period_id]
          command :confirm_registry_data, "Potwierdzenie danych", by: :accountant, emits: :registry_data_consistent
      #{amend(publisher)}
        end

        process :accounting_month, "Miesiąc księgowy" do
          correlate [:company_id, :period_id]
        end
      """)

      model =
        compile_example("MonthlyTasks", """
          use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :tasks

          aggregate :monthly_tasks, "Taski miesiąca" do
            identity [:company_id, :period_id]
            command :generate_monthly_tasks, "Wygenerowanie tasków", emits: :monthly_tasks_generated
            event :monthly_tasks_generated, "Wygenerowano taski"
          end

          process :monthly_tasks, "Taski miesiąca" do
            correlate [:company_id, :period_id]
          end

        #{String.replace(subscriber, "Taxvision.Contracts.AccountingMonth", inspect(example(:AccountingMonth)))}
        """)

      assert [%{handles: [:registry_data_consistent], issues: [:generate_monthly_tasks]}] =
               model.policies
    end

    test "an effect", %{four_six: f} do
      model =
        compile_example("Notification", """
          use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :accounting

          aggregate :registry_check, "Kontrola rejestrów" do
            identity :company_id
            command :check_registry, "Kontrola", by: :accountant, emits: :registry_discrepancy_detected
            event :registry_discrepancy_detected, "Wykryto rozjazd"
          end

          process :registry_check, "Kontrola rejestrów" do
            correlate :company_id
          end

        #{f.effect}
        """)

      assert [%{calls: [:mail], delivery: :at_least_once, idempotency: :downstream}] =
               model.effects
    end

    test "facts recorded rather than decided (D6)", %{four_six: f} do
      model =
        compile_example("Recorded", """
          use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :clinical

          aggregate :visit, "Wizyta" do
            identity :visit_id
        #{f.recorded}
          end

          process :clinical_visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert [
               %{recorded_by: [:specialist]},
               %{recorded_by: [:p1_integration], depends_on: :medical_event_registry}
             ] =
               model.events

      assert model.grants.specialist.records == [:visit_completed]
    end

    test "a process manager", %{four_six: f} do
      model =
        compile_example("DocumentationChase", """
          use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :clinical

          consumes Rehmed.Contracts.Scheduling, :visit_completed

          aggregate :visit_documentation, "Dokumentacja wizyty" do
            identity :visit_id
            command :chase_documentation, "Ponaglenie", emits: :documentation_chased
            command :close_visit_clinically, "Zamknięcie", by: :specialist, emits: :visit_closed_clinically
            event :documentation_chased, "Ponaglono"
            event :visit_closed_clinically, "Zamknięto klinicznie", terminal: true
          end

          process :clinical_visit, "Wizyta" do
            correlate :visit_id
          end

        #{f.process_manager}
        """)

      assert [%{timers: [%{name: :chase, wait: %{amount: 24, unit: :hour}}]}] =
               model.process_managers
    end

    test "a read model and a query", %{four_six: f} do
      model =
        compile_example("DailyTotals", """
          use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :settlement

          aggregate :visit_settlement, "Rozliczenie wizyty" do
            identity :visit_id
            command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded
            event :payment_recorded, "Pacjent opłacił wizytę"
          end

          process :visit_settlement, "Rozliczenie wizyty" do
            correlate :visit_id
          end

        #{amend(f.read_model)}
        """)

      assert [%{reads: :daily_totals, by: [:reception, :manager]}] = model.queries
    end

    test "a run over foreign events, and a promise (ClinicalVisit)", %{four_six: f} do
      model =
        compile_example("ClinicalVisit", """
          use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :clinical

        #{f.run}
        """)

      assert [
               %{
                 from: :visit_completed,
                 eventually: :p1_report_sent,
                 or_else: :p1_reporting_not_required
               }
             ] =
               model.process.promises
    end

    test "a dynamic consistency boundary (PayerSettlement)", %{four_six: f} do
      model =
        compile_example("PayerSettlement", """
          use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :settlement

          consumes Rehmed.Contracts.VisitSettlement, [:visit_marked_settled_with_payer, :visit_excluded_from_invoice]
          consumes Rehmed.Contracts.Scheduling, :visit_completed

        #{f.dcb}

          process :payer_settlement, "Rozliczenie płatnika" do
            correlate [:payer_id, :period_id]
            stage :invoicing
          end

          # S8: the invariant needs a scenario that is rejected on it.
          scenario "wizyta ani na fakturze, ani wykluczona — faktura odrzucona" do
            given :visit_completed
            command :issue_payer_invoice, %{invoice_id: "f-1"}
            rejected :every_delivered_visit_settled_or_excluded
          end
        """)

      assert [%{kind: :dcb, identity: [:payer_id, :period_id], consults: consults}] = model.units

      assert Enum.map(consults, & &1.event) == [
               :visit_marked_settled_with_payer,
               :visit_excluded_from_invoice,
               :visit_completed
             ]
    end
  end

  # --- reading the ADR -------------------------------------------------------------

  defp section(adr, number) do
    [_, rest] = String.split(adr, "\n### #{number} ", parts: 2)
    rest |> String.split(~r/\n##+ /, parts: 2) |> hd()
  end

  defp blocks(section) do
    for [_, code] <- Regex.scan(~r/```elixir\n(.*?)```/s, section), do: code
  end

  # §4.6 is one block of fragments, each under a comment line at the margin. Only the
  # declarations are kept: an implementation module (E5) ends its fragment.
  defp fragments(section) do
    [block] = blocks(section)

    by_header =
      ~r/^# (.+)\n/m
      |> Regex.split(block, include_captures: true, trim: true)
      |> Enum.chunk_every(2)
      |> Map.new(fn [header, code] -> {String.trim(header), code} end)

    pick = fn prefix ->
      {_, code} =
        Enum.find(by_header, fn {header, _} -> String.starts_with?(header, "# " <> prefix) end)

      code |> String.split("\ndefmodule ", parts: 2) |> hd() |> String.trim_trailing()
    end

    %{
      consumes: pick.("consumes + public + policy"),
      effect: pick.("effect"),
      recorded: pick.("a fact recorded"),
      process_manager: pick.("process manager"),
      read_model: pick.("read model + query"),
      run: pick.("a run over foreign events"),
      dcb: pick.("dynamic consistency boundary"),
      capabilities: pick.("capabilities")
    }
  end

  defp amend(code) do
    Enum.reduce(@amendments, code, fn {from, to, _why}, code -> String.replace(code, from, to) end)
  end

  test "every amendment still finds its text in the ADR" do
    adr = File.read!(@adr)

    for {from, _to, why} <- @amendments do
      assert adr =~ from, "the amendment for #{why} no longer applies: fix @amendments"
    end
  end

  defp example(name), do: Module.concat(EhOsContract.Next.Examples, name)

  defp compile_example(name, body) do
    compile(
      "defmodule #{inspect(example(name))} do\n#{body}\nend\n",
      "#{Macro.underscore(name)}.ex"
    )

    Model.fetch(example(name))
  end
end
