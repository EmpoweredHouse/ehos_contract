defmodule EhOsContract.TraceTest do
  @moduledoc """
  **`EhOsContract.Trace`'s pure core, without a database** (plan W3): `trace/2` reads
  what a promise is judged on from the contract, and `judge/3` gives verdicts for
  events handed to it rather than read from the log.

  The rules themselves are pinned against the log in `test/conformance/promise_*.exs`,
  through `evaluate/3`, which is `judge/3` over the log's rows. This file pins that the
  same rules hold with no log at all — which is what a scenario of a promise (S2) will
  need — and that `judge/3` reads neither the log nor the clock.

  Invented, and out of the registry.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Trace

  defmodule Domain do
    @moduledoc "# INVENTED. NOT A DOMAIN."

    use EhOsContract.Domain, name: :trace_core, language: :en

    context :desk, "Desk", subdomain: :core
    actor :clerk, :system, "Clerk"
    subdomain :core, "Core", type: :core
  end

  defmodule Requests do
    @moduledoc """
    # INVENTED. NOT A DOMAIN.

    A request, answered or refused within a day; and its items, each inspected
    within a day — a promise made per item inside the request's run.
    """

    use EhOsContract.Contract, domain: EhOsContract.TraceTest.Domain, context: :desk

    aggregate :request, "Request" do
      identity [:request_id]

      event :requested, "Requested", recorded_by: :clerk
      event :answered, "Answered", recorded_by: :clerk
      event :refused, "Refused", recorded_by: :clerk
    end

    aggregate :item, "Item" do
      identity [:request_id, :item_no]

      event :item_submitted, "Item submitted", recorded_by: :clerk
      event :item_inspected, "Item inspected", recorded_by: :clerk
    end

    process :desk, "Desk" do
      correlate :request_id

      promise :answered_in_a_day do
        from :requested
        eventually :answered
        within {1, :day}
        or_else :refused
      end

      promise :items_inspected_in_a_day do
        from :item_submitted
        eventually :item_inspected
        within {1, :day}
      end
    end
  end

  @from ~U[2026-07-01 09:00:00.000000Z]
  @inside ~U[2026-07-01 15:00:00.000000Z]
  @deadline ~U[2026-07-02 09:00:00.000000Z]
  @later ~U[2026-07-05 09:00:00.000000Z]

  defp at(run, event, occurred_at, payload \\ %{}),
    do: %{instance_id: run, type: "desk.#{event}", occurred_at: occurred_at, payload: payload}

  defp item(run, event, item_no, occurred_at),
    do: at(run, event, occurred_at, %{"request_id" => run, "item_no" => item_no})

  defp judge(occurrences, opts \\ []),
    do:
      Trace.judge(
        Trace.trace(Requests, :answered_in_a_day),
        occurrences,
        Keyword.merge([now: @later], opts)
      )

  describe "trace/2" do
    test "names the promise's events by their stored types, with its window" do
      assert Trace.trace(Requests, :answered_in_a_day) == %{
               from: "desk.requested",
               eventually: "desk.answered",
               or_else: "desk.refused",
               within: {1, :day},
               identity: nil
             }
    end

    test "carries the item's identity when from's unit is finer than the run" do
      assert Trace.trace(Requests, :items_inspected_in_a_day).identity == [
               "request_id",
               "item_no"
             ]
    end

    test "takes a model as well as a module" do
      model = EhOsContract.Model.fetch(Requests)

      assert Trace.trace(model, :answered_in_a_day) ==
               Trace.trace(Requests, :answered_in_a_day)
    end

    test "refuses a promise the contract does not declare, and a domain" do
      assert_raise ArgumentError, ~r/does not declare promise :nope/, fn ->
        Trace.trace(Requests, :nope)
      end

      assert_raise ArgumentError, ~r/does not declare promise :answered_in_a_day/, fn ->
        Trace.trace(Domain, :answered_in_a_day)
      end
    end
  end

  describe "judge/3 over events no log holds" do
    test "each of the four verdicts, one run each" do
      verdicts =
        judge(
          [
            at("answered", :requested, @from),
            at("answered", :answered, @inside),
            at("refused", :requested, @from),
            at("refused", :refused, @inside),
            at("late", :requested, @from),
            at("late", :answered, @later),
            at("open", :requested, @later)
          ],
          outages: []
        )

      assert Map.new(verdicts, &{&1.instance_id, {&1.verdict, &1.via}}) == %{
               "answered" => {:satisfied, :eventually},
               "refused" => {:satisfied, :or_else},
               "late" => {:violated, nil},
               "open" => {:pending, nil}
             }

      assert %{deadline_at: @deadline, resolved_at: @inside} =
               Enum.find(verdicts, &(&1.instance_id == "answered"))
    end

    test "an outage inside a window that closed empty suspends the run; outside it, it does not" do
      occurrences = [at("r", :requested, @from)]

      assert [%{verdict: :suspended}] = judge(occurrences, outages: [@inside])
      assert [%{verdict: :violated}] = judge(occurrences, outages: [@later])
      assert [%{verdict: :violated}] = judge(occurrences)
    end

    test "a run with no from is not judged, and events of other types are ignored" do
      assert judge([at("r", :answered, @inside)]) == []

      assert [%{verdict: :violated}] =
               judge([at("r", :requested, @from), at("r", :item_inspected, @inside)])
    end

    test "verdicts come in the order their windows opened" do
      # Named against the order of their windows, so that the order of the keys
      # cannot pass for it.
      verdicts = judge([at("a", :requested, @inside), at("b", :requested, @from)])
      assert Enum.map(verdicts, & &1.instance_id) == ["b", "a"]
    end

    test "the clock is the one it is given, never the wall's" do
      occurrences = [at("r", :requested, @from)]

      assert [%{verdict: :pending}] = judge(occurrences, now: @inside)
      assert [%{verdict: :violated}] = judge(occurrences, now: @deadline)

      assert_raise KeyError, fn ->
        Trace.judge(Trace.trace(Requests, :answered_in_a_day), occurrences, [])
      end
    end
  end

  describe "judge/3 over a promise made per item" do
    setup do
      %{trace: Trace.trace(Requests, :items_inspected_in_a_day)}
    end

    test "the run's one verdict is the worst of its items'", %{trace: trace} do
      occurrences = [
        item("r", :item_submitted, 1, @from),
        item("r", :item_submitted, 2, @from),
        item("r", :item_inspected, 1, @inside)
      ]

      assert [%{instance_id: "r", verdict: :violated}] =
               Trace.judge(trace, occurrences, now: @later)

      inspected = occurrences ++ [item("r", :item_inspected, 2, @inside)]

      assert [%{verdict: :satisfied, via: :eventually}] =
               Trace.judge(trace, inspected, now: @later)
    end

    test "a payload keyed by atoms is refused, not read as carrying no item", %{trace: trace} do
      # Read as missing, both items would share the key {nil, nil} and the one
      # inspection would resolve them both.
      occurrences = [
        %{
          instance_id: "r",
          type: "desk.item_submitted",
          occurred_at: @from,
          payload: %{request_id: "r", item_no: 1}
        },
        %{
          instance_id: "r",
          type: "desk.item_submitted",
          occurred_at: @from,
          payload: %{request_id: "r", item_no: 2}
        },
        %{
          instance_id: "r",
          type: "desk.item_inspected",
          occurred_at: @inside,
          payload: %{request_id: "r", item_no: 1}
        }
      ]

      assert_raise ArgumentError, ~r/request_id under an atom key/, fn ->
        Trace.judge(trace, occurrences, now: @later)
      end
    end

    test "an occurrence without its payload is refused, naming the identity", %{trace: trace} do
      occurrences = [%{instance_id: "r", type: "desk.item_submitted", occurred_at: @from}]

      assert_raise ArgumentError, ~r/needs its payload.*request_id, item_no/, fn ->
        Trace.judge(trace, occurrences, now: @later)
      end
    end

    test "a hit resolves only the item its payload names", %{trace: trace} do
      occurrences = [item("r", :item_submitted, 1, @from), item("r", :item_inspected, 2, @inside)]

      assert [%{verdict: :violated}] = Trace.judge(trace, occurrences, now: @later)
    end
  end
end
