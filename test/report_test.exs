defmodule Taxvision.ReportTest do
  @moduledoc """
  Stage 1.7: **the conformance report for a period.**

  The acceptance criterion has two parts and the second is the hard one:

  1. readable without explaining what the columns mean,
  2. **it does not contain a `deadline` marked `unverified`.**

  The second is measurable and is the first block below. The first is soft by
  nature, but it can be pinned from the opposite side: the report contains not a
  single technical event name, because every one is replaced by a label from the
  contract.

  The Polish strings asserted on below are the report's own output — this is the
  one artifact an accountant reads, so its sentences are in their language. See
  `Taxvision.Report`.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth, as: Contract

  @consistent %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @divergent %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp registries(responses) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: responses)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp open_month(company, period \\ "2026-07") do
    {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: period})
  end

  defp data(opts \\ []), do: PNS.Conformance.report(Contract, opts)
  defp text(opts \\ []), do: opts |> data() |> Taxvision.Report.render()

  describe "acceptance criterion: no unconfirmed declarations" do
    test "a deadline marked `unverified` does not reach the report's data" do
      # `deadline: {25, :day}` sits in the contract with `unverified: [:deadline]`,
      # because the number is plausible but **nobody from TaxVision supplied it**.
      assert :deadline in Contract.process(:accounting_month).unverified

      [process] = data().processes
      keys = Enum.map(process.declarations, & &1.key)

      refute :deadline in keys,
             "an unconfirmed declaration in an evidence report reads as measured — " <>
               "and a false metric is worse than a missing one, because it is the metric the product sells"

      # The cadence is confirmed by the workshop [WF 00:34:40], so it stays.
      assert :cadence in keys
    end

    test "the deadline does not reach the rendered text either" do
      refute text() =~ "Termin"
      refute text() =~ "25"
    end

    test "if the deadline were confirmed, it would appear" do
      # Proof that the filter acts on `unverified` rather than simply being unable
      # to print a deadline. Without this the first test would also pass with a
      # broken filter.
      process = Contract.process(:accounting_month)
      confirmed = %{process | unverified: []}

      refute Enum.any?(PNS.Conformance.verified_declarations(process), &(&1.key == :deadline))
      assert Enum.any?(PNS.Conformance.verified_declarations(confirmed), &(&1.key == :deadline))
    end
  end

  describe "acceptance criterion: readable without explanation" do
    setup do
      registries(%{"c-1" => {:ok, @consistent}, "c-2" => {:ok, @divergent}})
      open_month("c-1")
      open_month("c-2")
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "the steps are named with business labels, not with event names" do
      t = text()

      # The assertion is a sentence composed of labels, because `trace` has no
      # `label`.
      assert t =~ "po „Potwierdzono komplet danych historycznych”"
      assert t =~ "następuje „Otwarto miesiąc księgowy”"

      refute t =~ "data_completeness_confirmed"
      refute t =~ "accounting_month_opened"
    end

    test "satisfaction through the fallback path is named conformance, not an exception" do
      # Blocking the month is a correct ending. A report that called it a problem
      # would be switched off after the first month.
      assert text() =~ "Dotrzymane we wszystkich 2 przebiegach"
      assert text() =~ "zgodne z ustaleniem"
    end

    test "the screen's four questions are in one artifact" do
      t = text()

      assert t =~ "USTALENIA"
      assert t =~ "Wersja ustaleń"
      assert t =~ "PROCES"
      assert t =~ "Ustalenie: po"
      assert t =~ "ROZBIEŻNOŚCI"
    end

    test "the absence of divergence is a sentence, not an empty section" do
      assert text() =~ "Brak: nic nie zaszło poza ustaleniami"
    end
  end

  describe "the report is for a period" do
    test "the window cuts off runs from outside the period" do
      open_month("c-1", "2026-06")
      open_month("c-2", "2026-07")

      everything = data()
      recent = data(since: ~U[2026-08-05 00:00:00.000000Z])

      [p_everything] = everything.processes
      [p_recent] = recent.processes

      assert p_everything.runs == 2
      assert p_recent.runs == 2

      # A window in the future cannot contain anything — proof that the bound
      # works rather than being ignored.
      empty = data(since: ~U[2027-01-01 00:00:00.000000Z])
      [p_empty] = empty.processes

      assert p_empty.runs == 0
    end

    test "a period with no runs says \"there is nothing to judge\", not \"all is well\"" do
      open_month("c-1")

      t = text(since: ~U[2027-01-01 00:00:00.000000Z])

      assert t =~ "nie było ani jednego przebiegu"
      refute t =~ "Wszystkie ustalone kroki zostały"
    end

    test "the header names the period the report is about" do
      t = text(since: ~U[2026-07-01 00:00:00.000000Z], until: ~U[2026-07-31 23:59:59.000000Z])
      assert t =~ "2026-07-01 – 2026-07-31"
    end
  end

  describe "drift is attributed to the right contract" do
    test "drift enters the report of the contract whose event caused it" do
      open_month("c-1")

      Repo.insert!(%PNS.Event{
        type: "event_outside_the_agreement",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert [divergence] = data().drift
      assert divergence.to == "event_outside_the_agreement"
      assert divergence.from_label == "Otwarto miesiąc księgowy"

      # Another contract's report has no business seeing this.
      assert PNS.Conformance.report(UniversalityGate.TreatmentEpisode).drift == []
    end
  end

  describe "a failing step reads as a failure, not as a step nobody took" do
    setup do
      registries(%{"c-1" => {:ok, @consistent}})
      open_month("c-1")
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "the sentence says it is being attempted and not succeeding" do
      # Rendering is pure, so the failing branch is exercised with the shape it is
      # contracted to accept rather than by breaking a TaxVision handler. No client
      # handler fails today, and making one fail to reach a renderer branch would be
      # changing the domain to suit a test.
      report = data()
      [process | rest] = report.processes

      failing = %{
        from: :accounting_month_opened,
        to: :month_closed,
        from_label: "Otwarto miesiąc księgowy",
        to_label: "Zamknięto miesiąc księgowy",
        async: false,
        in_flight: 0,
        failing: 2
      }

      text =
        %{report | processes: [%{process | failing: [failing]} | rest]}
        |> Taxvision.Report.render()

      assert text =~ "Ustalone kroki, które są próbowane i się nie udają:"
      assert text =~ "Otwarto miesiąc księgowy → Zamknięto miesiąc księgowy"
      assert text =~ "nie udało się w 2 przebiegach"

      # **One edge, one section.** The untraversed section is legitimately present
      # here too — only the consistent branch ran, so the divergent path really was
      # never taken — which is exactly why the assertion has to be about this edge
      # rather than about the section existing. An earlier version of this test
      # asserted the section was absent and was simply wrong about the domain.
      occurrences =
        text
        |> String.split("Otwarto miesiąc księgowy → Zamknięto miesiąc księgowy")
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1,
             "the same edge in two sections says two different things about one finding"
    end

    test "one failing run is singular, because a report is read aloud" do
      report = data()
      [process | rest] = report.processes

      failing = %{
        from: :accounting_month_opened,
        to: :month_closed,
        from_label: "Otwarto miesiąc księgowy",
        to_label: "Zamknięto miesiąc księgowy",
        async: false,
        in_flight: 0,
        failing: 1
      }

      text =
        %{report | processes: [%{process | failing: [failing]} | rest]}
        |> Taxvision.Report.render()

      assert text =~ "nie udało się w 1 przebiegu"
    end
  end
end
