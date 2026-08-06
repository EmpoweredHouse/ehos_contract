defmodule PNS.TraceTest do
  @moduledoc """
  Stage 1.5: **evaluating `trace` assertions per run.**

  There is one acceptance criterion and it is the first test below: with a blocked
  month the assertion is **satisfied through `or_else`**, not violated. Blocking is
  a correct ending, just not the one we wanted — and a tool that shouts about every
  correctly blocked month gets switched off within a week.

  The rest of the tests pin the semantic decisions, each of which can be reversed
  without breaking anything else.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth, as: Contract

  @assertion :month_opens_or_is_blocked
  @consistent %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @divergent %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp registries(responses) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: responses)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp open_month(company, period \\ "2026-07") do
    {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: period})
  end

  # The divergence notification goes out through an **asynchronous** handler, so
  # `or_else` does not exist in the log until the job runs. In tests jobs stay put
  # (`testing: :manual`), which is an advantage here: it separates "the agreement
  # was kept" from "the agreement is about to be kept".
  defp run_jobs, do: Oban.drain_queue(queue: :events)

  defp evaluate(opts \\ []), do: PNS.Trace.evaluate(Contract, @assertion, opts)

  describe "acceptance criterion" do
    test "a blocked month is SATISFIED through or_else, not violated" do
      registries(%{"c-1" => {:ok, @divergent}})
      open_month("c-1")
      run_jobs()

      assert [verdict] = evaluate()

      assert verdict.verdict == :satisfied,
             "blocking on a divergence is a correct ending of the process, not a broken agreement"

      assert verdict.via == :or_else
      assert verdict.instance_id == instance("c-1", "2026-07")
    end

    test "an opened month is satisfied through eventually" do
      registries(%{"c-1" => {:ok, @consistent}})
      open_month("c-1")

      assert [verdict] = evaluate()
      assert verdict.verdict == :satisfied
      assert verdict.via == :eventually
    end

    test "two runs, two different ways of being satisfied — and they do not mix" do
      # This is 1.1 and 1.5 tied together: without run identity this assertion
      # would be counted once, globally, and would credit both runs the same way.
      registries(%{"c-1" => {:ok, @consistent}, "c-2" => {:ok, @divergent}})
      open_month("c-1")
      open_month("c-2")
      run_jobs()

      by_instance = Map.new(evaluate(), &{&1.instance_id, &1})

      assert by_instance[instance("c-1", "2026-07")].via == :eventually
      assert by_instance[instance("c-2", "2026-07")].via == :or_else

      assert PNS.Trace.summary(evaluate()) == %{
               satisfied: 2,
               satisfied_via_eventually: 1,
               satisfied_via_or_else: 1,
               violated: 0,
               pending: 0,
               # Since stage 1.5b. Reported separately and never folded into `violated`,
               # because a suspended run is the one the client is not answerable for.
               suspended: 0,
               instances: 2
             }
    end
  end

  describe "leaving the BEAM process boundary" do
    test "while the `or_else` job sits in the queue the verdict is `pending`" do
      # This is the same lesson as the overlay's fourth state: "not yet" looks
      # identical in the log to "never". The decision to block has been taken, but
      # the notification has not gone out, so the agreement is not **yet** kept —
      # and the verdict has no business claiming that it is.
      registries(%{"c-1" => {:ok, @divergent}})
      open_month("c-1")

      assert [verdict] = evaluate()
      assert verdict.verdict == :pending

      # And once the job has run, the same assertion is satisfied. The cost of
      # asynchrony is named: a job wedged past the window counts as a violation —
      # correctly, because the notification really did not go out.
      run_jobs()
      assert [%{verdict: :satisfied, via: :or_else}] = evaluate()
    end
  end

  describe "the window" do
    # Events inserted directly, because that is the only way to set `occurred_at`.
    defp fact(type, company, at, period \\ "2026-07") do
      Repo.insert!(%PNS.Event{
        type: to_string(type),
        contract: inspect(Contract),
        contract_version: Contract.version(),
        process: "accounting_month",
        instance_id: instance(company, period),
        correlation_id: Ecto.UUID.generate(),
        payload: %{"company_id" => company, "period_id" => period_id!(period)},
        occurred_at: at
      })
    end

    @start ~U[2026-07-01 09:00:00.000000Z]

    test "before the window elapses the verdict is `pending`, not `violated`" do
      fact(:data_completeness_confirmed, "c-1", @start)

      assert [verdict] = evaluate(now: DateTime.add(@start, 1, :day))
      assert verdict.verdict == :pending
      assert verdict.deadline_at == DateTime.add(@start, 2, :day)
    end

    test "after the window elapses with neither ending, the verdict is `violated`" do
      fact(:data_completeness_confirmed, "c-1", @start)

      assert [verdict] = evaluate(now: DateTime.add(@start, 3, :day))
      assert verdict.verdict == :violated
      assert verdict.via == nil
    end

    test "an ending after the deadline does not rescue the assertion" do
      fact(:data_completeness_confirmed, "c-1", @start)
      fact(:accounting_month_opened, "c-1", DateTime.add(@start, 5, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 6, :day))
      assert verdict.verdict == :violated
    end

    test "a repeated `from` does NOT move the deadline" do
      # If the window ran from the last occurrence, a process could outrun its own
      # deadline forever by simply emitting `from` again — and this assertion
      # could never be violated.
      fact(:data_completeness_confirmed, "c-1", @start)
      fact(:data_completeness_confirmed, "c-1", DateTime.add(@start, 10, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 11, :day))
      assert verdict.verdict == :violated
      assert verdict.from_at == @start
    end

    test "`or_else` is bound by the deadline too" do
      # A decision for the process owner to confirm: "within two days, X or Y"
      # means both are meant to fit. Otherwise the deadline is useless.
      fact(:data_completeness_confirmed, "c-1", @start)
      fact(:discrepancy_notification_sent, "c-1", DateTime.add(@start, 4, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 5, :day))
      assert verdict.verdict == :violated
    end
  end

  describe "the assertion is conditional" do
    test "a run with no `from` is not evaluated at all" do
      # It is neither satisfied nor violated — there is nothing to judge. Counting
      # it as a violation would raise an alarm for every case not yet started.
      fact(:accounting_month_opened, "c-9", @start)

      assert evaluate(now: DateTime.add(@start, 30, :day)) == []
    end

    test "an empty log is zero verdicts, not zero violations" do
      assert evaluate() == []
      assert PNS.Trace.summary(evaluate()).instances == 0
    end
  end

  describe "every contract" do
    test "the second domain's assertions are evaluated by the same code" do
      registries(%{"c-1" => {:ok, @consistent}})
      open_month("c-1")

      all = PNS.Trace.evaluate_all()
      names = Enum.map(all, & &1.trace) |> Enum.sort()

      # Three contracts now, the third being the shapes rig — which is where the
      # `:suspended` verdict is exercised, because TaxVision's one dependency is consulted
      # before its assertion window opens.
      assert names == [
               :episode_reaches_an_end,
               :month_opens_or_is_blocked,
               :referral_reaches_a_decision,
               :submission_reaches_inspection
             ]

      # The medical contract has no implementation, so its assertions have no runs
      # to judge — and that is zero verdicts, not zero violations.
      medical = Enum.filter(all, &(&1.contract == UniversalityGate.TreatmentEpisode))
      assert Enum.all?(medical, &(&1.verdicts == []))
    end
  end
end
