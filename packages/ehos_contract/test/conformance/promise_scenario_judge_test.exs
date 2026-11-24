defmodule EhosContract.PromiseScenarioJudgeTest do
  @moduledoc """
  Plan DD, S2 (#251): **`EhosContract.ScenarioCase.judge/2`** over a process whose
  promise waits on an external system and is made per item inside a run: an order's
  every parcel is delivered within two days, or recorded lost. The rig is compiled here,
  not in `test/support/`, so that the engine's own check does not count it. What
  `ProcessShapes.Handling`'s scenarios show, each verdict and route of an ordinary
  promise, is `ProcessShapes.HandlingScenariosTest`'s.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.{Model, ScenarioCase}

  @fixtures EhosContract.Fixtures

  setup_all do
    compile(
      """
      defmodule #{inspect(@fixtures)}.JudgeShop do
        use EhosContract.Domain, name: :shop, language: :en

        context :shipping, "Shipping", subdomain: :core
        actor :warehouse, :human, "Warehouse", context: :shipping
        actor :courier_link, :system, "Courier link", backed_by: :courier, context: :shipping
        external :courier, "Courier", direction: :inbound

        subdomain :core, "Core", type: :core
      end

      defmodule #{inspect(@fixtures)}.JudgeShipping do
        use EhosContract.Contract,
          domain: #{inspect(@fixtures)}.JudgeShop,
          context: :shipping,
          id: "shop.judge_shipping"

        aggregate :parcel, "Parcel" do
          identity [:order_id, :parcel_id]

          event :parcel_shipped, "Parcel shipped", recorded_by: :warehouse
          event :parcel_delivered, "Parcel delivered", recorded_by: :courier_link, depends_on: :courier
          event :parcel_lost, "Parcel lost", recorded_by: :warehouse
        end
      end

      defmodule #{inspect(@fixtures)}.JudgeDelivery do
        use EhosContract.Process,
          id: "shop.judge_delivery",
          domain: #{inspect(@fixtures)}.JudgeShop,
          label: "Delivery"

        correlate :order_id

        stage :shipping,
          include: [{#{inspect(@fixtures)}.JudgeShipping, [:parcel_shipped, :parcel_delivered, :parcel_lost]}]

        promise :every_parcel_delivered do
          from :parcel_shipped
          eventually :parcel_delivered
          within {2, :day}
          or_else :parcel_lost
        end
      end
      """,
      "judge_shop.ex"
    )

    :ok
  end

  defp scenario(verdict, given, opts \\ []) do
    %{
      description: "a case",
      verdict: verdict,
      via: Keyword.get(opts, :via),
      given:
        for(
          {event, order, parcel, at} <- given,
          do: %{event: event, data: %{order_id: order, parcel_id: parcel}, at: at}
        ),
      outages: for(at <- Keyword.get(opts, :outages, []), do: %{external: :courier, at: at}),
      promise: %{
        name: :every_parcel_delivered,
        at: Keyword.get(opts, :now, "2026-09-10T09:00:00Z")
      }
    }
  end

  defp judge(scenario), do: ScenarioCase.judge(Module.concat(@fixtures, JudgeDelivery), scenario)

  test "the trace is made per item, so the run is judged by its every parcel" do
    assert %{identity: ["order_id", "parcel_id"]} =
             EhosContract.Trace.trace(
               Model.fetch(Module.concat(@fixtures, JudgeDelivery)),
               :every_parcel_delivered
             )
  end

  test "every parcel delivered in time: kept" do
    assert judge(
             scenario(
               :satisfied,
               [
                 {:parcel_shipped, "o-1", "p-1", "2026-09-07T09:00:00Z"},
                 {:parcel_shipped, "o-1", "p-2", "2026-09-07T09:00:00Z"},
                 {:parcel_delivered, "o-1", "p-1", "2026-09-08T09:00:00Z"},
                 {:parcel_delivered, "o-1", "p-2", "2026-09-08T10:00:00Z"}
               ],
               via: :eventually
             )
           )
  end

  test "one parcel of two delivered: broken, and the scenario saying kept fails" do
    given = [
      {:parcel_shipped, "o-1", "p-1", "2026-09-07T09:00:00Z"},
      {:parcel_shipped, "o-1", "p-2", "2026-09-07T09:00:00Z"},
      {:parcel_delivered, "o-1", "p-1", "2026-09-08T09:00:00Z"}
    ]

    assert judge(scenario(:violated, given))

    error = assert_raise ExUnit.AssertionError, fn -> judge(scenario(:satisfied, given)) end

    assert error.message =~
             "promise :every_parcel_delivered, judged at 2026-09-10T09:00:00Z, is :violated, " <>
               "and the scenario says :satisfied; its window opened at 2026-09-07T09:00:00Z " <>
               "and closes at 2026-09-09T09:00:00Z"
  end

  test "the courier down while a parcel was awaited: excused" do
    given = [
      {:parcel_shipped, "o-1", "p-1", "2026-09-07T09:00:00Z"},
      {:parcel_shipped, "o-1", "p-2", "2026-09-07T09:00:00Z"},
      {:parcel_delivered, "o-1", "p-1", "2026-09-08T09:00:00Z"}
    ]

    assert judge(scenario(:suspended, given, outages: ["2026-09-08T12:00:00Z"]))

    # After the window closed, the outage excuses nothing.
    assert judge(scenario(:violated, given, outages: ["2026-09-09T12:00:00Z"]))
  end

  test "a parcel delivered once and another recorded lost: kept, by no one route" do
    given = [
      {:parcel_shipped, "o-1", "p-1", "2026-09-07T09:00:00Z"},
      {:parcel_shipped, "o-1", "p-2", "2026-09-07T09:00:00Z"},
      {:parcel_delivered, "o-1", "p-1", "2026-09-08T09:00:00Z"},
      {:parcel_lost, "o-1", "p-2", "2026-09-08T10:00:00Z"}
    ]

    assert judge(scenario(:satisfied, given))

    error =
      assert_raise ExUnit.AssertionError, fn ->
        judge(scenario(:satisfied, given, via: :or_else))
      end

    assert error.message =~ "is :satisfied, and the scenario says :satisfied via :or_else"
  end

  test "givens of two orders make two runs, and the scenario fails saying so" do
    given = [
      {:parcel_shipped, "o-1", "p-1", "2026-09-07T09:00:00Z"},
      {:parcel_shipped, "o-2", "p-1", "2026-09-07T09:00:00Z"}
    ]

    error =
      assert_raise ExUnit.AssertionError, fn ->
        judge(scenario(:pending, given, now: "2026-09-08T09:00:00Z"))
      end

    assert error.message =~
             ~s|the givens make 2 judged runs, ["shop.judge_delivery|
  end

  test "process: naming a contract is refused when the test compiles" do
    assert_raise ArgumentError, ~r/is not a process module/, fn ->
      Code.compile_quoted(
        quote do
          defmodule EhosContract.Fixtures.JudgeNotAProcessTest do
            use EhosContract.ScenarioCase, process: ProcessShapes.Promised
          end
        end
      )
    end
  end
end
