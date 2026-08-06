defmodule PNS.InstanceTest do
  @moduledoc """
  The acceptance criterion of stage 1.1: **an assertion counted over two parallel
  runs does not confuse their events.**

  This file is written to show the difference rather than only to check a new
  counter. Wherever it makes sense, the per-run result stands next to the per-event-type
  one — that is, next to what the engine counted before this stage. Without that
  comparison "the counter says 1" is a number with no meaning.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth

  @consistent %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @divergent %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp registries(responses) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: responses)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp instance(company_id, period), do: "accounting_month|#{company_id}|#{period}"

  describe "run identity in the log" do
    test "the run key comes from `instance:` and is written on the event" do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

      event = List.first(events_of(:data_completeness_confirmed))

      assert event.process == "accounting_month"
      assert event.instance_id == instance("c-1", "2026-07")
    end

    test "every event of one command lands in one run" do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

      instances = Repo.all(from e in PNS.Event, select: e.instance_id) |> Enum.uniq()

      assert instances == [instance("c-1", "2026-07")]
    end

    test "the same company in two months is two runs, not one" do
      # `correlation_id` would answer the same way here, because these are two
      # commands. But one command opening two months would also give two runs, and
      # one month opened by two commands would give one. These are different
      # questions.
      for period <- ["2026-06", "2026-07"] do
        {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: period})
      end

      instances = Repo.all(from e in PNS.Event, select: e.instance_id) |> Enum.uniq() |> Enum.sort()

      assert instances == [instance("c-1", "2026-06"), instance("c-1", "2026-07")]
    end

    test "an event missing an instance field does not enter the log" do
      # Still refused, and since stage 2.2b **by a different check**. Payload validation
      # runs before the run key is computed and rejects any declared field that is
      # missing, so it reaches this case first. The consequence for the log is the one
      # that matters and is unchanged: the event does not land with an empty key segment
      # and merge with another company's run.
      assert_raise ArgumentError, ~r/`period` is declared and missing/, fn ->
        PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: "c-1"})
      end

      assert events_of(:registry_data_consistent) == []
    end

    test "the run key still guards a direct caller, where nothing validated first" do
      # `PNS.Instance.key/3` is public, so it can be reached without going through the
      # emitter — and there its own check is the only thing standing between a missing
      # field and a key with a hole in it. Unreachable from `emit` is not the same as
      # dead, and the difference is worth a test rather than a comment.
      assert_raise ArgumentError, ~r/does not carry instance field :period/, fn ->
        PNS.Instance.key(AccountingMonth, :registry_data_consistent, %{company_id: "c-1"})
      end
    end
  end

  describe "two parallel runs" do
    setup do
      # c-1 passes the check, c-2 does not. Both runs start with the same event, so
      # per event type they are indistinguishable.
      registries(%{"c-1" => {:ok, @consistent}, "c-2" => {:ok, @divergent}})

      for company <- ["c-1", "c-2"] do
        {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: "2026-07"})
      end

      :ok
    end

    test "\"after X, eventually Y\" is true for one run rather than for both" do
      # This is the whole reason stage 1.1 comes before assertion evaluation. The
      # `month_opens_or_is_blocked` assertion says: after the data set is confirmed
      # complete, the month opens **or** a divergence notification goes out.
      c1 = PNS.Graph.observed(instance: instance("c-1", "2026-07")).nodes
      c2 = PNS.Graph.observed(instance: instance("c-2", "2026-07")).nodes

      assert Map.has_key?(c1, "data_completeness_confirmed")
      assert Map.has_key?(c2, "data_completeness_confirmed")

      assert Map.has_key?(c1, "accounting_month_opened")
      refute Map.has_key?(c2, "accounting_month_opened")

      # And this is the same assertion counted per event type, that is, the way the
      # engine counted before this stage: "`accounting_month_opened` happened after
      # `data_completeness_confirmed`" is **true globally** and would credit run
      # c-2, which never opened.
      globally = PNS.Graph.observed().nodes
      assert globally["data_completeness_confirmed"].count == 2
      assert globally["accounting_month_opened"].count == 1
    end

    test "an edge counter has two dimensions: occurrences and runs" do
      overlay = PNS.Graph.overlay()
      edge = Enum.find(overlay, &(&1.to == :accounting_month_opened))

      # The edge is `confirmed`, because somebody traversed it. And that is exactly
      # the hidden silence: **one of two** runs traversed it.
      assert edge.state == :confirmed
      assert edge.count == 1
      assert edge.instances == 1
      assert edge.of_instances == 2
    end

    test "an event repeated within one run raises occurrences, not runs" do
      # Occurrences go up, runs do not. The version without that distinction read
      # one company repeating an operation as coverage of the whole population.
      #
      # Re-checking the registries in an already-open month is legal and cascades
      # nothing — which is why this uses that rather than the edge that opens the
      # month, which the aggregate's invariant rightly lets through only once.
      PNS.emit!(AccountingMonth, :registry_status_checked, %{
        company_id: "c-1",
        period: "2026-07",
        checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

      node = PNS.Graph.observed().nodes["registry_status_checked"]

      assert node.count == 3
      assert node.instances == 2
    end

    test "the number of runs of a process is a count, not a list of companies" do
      # Deliberately. "Which company has no open July" is a question for the client
      # application; PNS answers the question about the path.
      assert PNS.Graph.process_instances() == %{"accounting_month" => 2}
    end
  end
end
