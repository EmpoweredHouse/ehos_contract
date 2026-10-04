defmodule EhOsContract.GraphLifecycleTest do
  @moduledoc """
  Plan LC4b (#99): an aggregate's lifecycle as a diagram — where it starts, its
  statuses and ends, the transitions named by their events — and, with the log over
  it, the report's counts on each arrow. On the invented `LifecycleRig.Visits`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, Graph}
  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AdmitPatient, BookVisit, CloseVisit}
  alias LifecycleRig.Visits.Events.PatientArrived

  defp reception,
    do:
      Actor.credential(
        "u-reception",
        Enum.map(~w(book_visit admit_patient close_visit), &"lifecycle_rig.#{&1}")
      )

  defp issue(module, visit),
    do:
      {:ok, _} =
        EhOsContract.dispatch(Visits, struct(module, visit_id: visit), actor: reception())

  test "the declared lifecycle: a start, the statuses, the ends heavier, the events on the arrows" do
    text = Graph.lifecycle_to_mermaid(Visits, :visit)

    assert text =~ "flowchart TB"
    assert text =~ ~s'start((" ")):::start'
    assert text =~ ~s'status_booked("Booked"):::status'
    assert text =~ ~s'status_closed(["Closed"]):::status_end'
    assert text =~ ~s'start -->|"Visit booked"| status_booked'
    assert text =~ ~s'status_booked -->|"Patient arrived"| status_in_progress'
    assert text =~ "classDef status_end"
    refute text =~ "-.->"
  end

  test "with the log over it: how often, not yet, never, and what was not declared" do
    issue(BookVisit, "v-1")
    issue(AdmitPatient, "v-1")
    issue(CloseVisit, "v-1")
    issue(BookVisit, "v-2")

    {:ok, _} =
      EhOsContract.record(Visits, %PatientArrived{visit_id: "v-1"},
        actor: Actor.system(:front_desk)
      )

    text = Graph.lifecycle_to_mermaid(Visits, :visit, overlay: true)

    assert text =~ ~s'start -->|"Visit booked · 2x"| status_booked'
    assert text =~ ~s'status_in_progress -->|"Visit closed · 1x"| status_closed'
    # v-2 is still booked, so it can still be cancelled.
    assert text =~ ~s'status_booked -->|"Visit cancelled · not yet"| status_cancelled'

    assert text =~
             ~s'status_closed -.->|"Patient arrived · not declared, 1x"| status_closed'
  end

  test "given the report's lifecycles, it draws them without reading the log again" do
    issue(BookVisit, "v-1")
    lifecycles = EhOsContract.Conformance.lifecycles(Visits, [])
    # Written after the report was computed: a drawing from it does not see it.
    issue(BookVisit, "v-2")

    text = Graph.lifecycle_to_mermaid(Visits, :visit, overlay: true, lifecycles: lifecycles)

    assert text =~ ~s'start -->|"Visit booked · 1x"| status_booked'
  end

  test "an aggregate without a lifecycle is refused, naming those with one" do
    error =
      assert_raise ArgumentError, fn ->
        Graph.lifecycle_to_mermaid(BoundaryRig.Waitlist, :entry)
      end

    assert error.message =~ "unit :entry of BoundaryRig.Waitlist declares no lifecycle"
  end

  describe "mix eh_os_contract.graph --lifecycle" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    @tag :tmp_dir
    test "--since keeps the offset it is given, and reads a time without one as UTC", %{
      tmp_dir: dir
    } do
      path = Path.join(dir, "since.mmd")
      before = DateTime.utc_now()
      {:ok, _} = EhOsContract.dispatch(Visits, %BookVisit{visit_id: "v-1"}, actor: reception())

      # One hour after `before` on the clock of a zone two hours ahead: an hour before
      # it in UTC, so the booking is in the period. Read without its offset, it would
      # be an hour after, and the booking would not.
      digits =
        before |> DateTime.add(1, :hour) |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

      draw = fn since ->
        Mix.Tasks.EhOsContract.Graph.run(
          ~w(--contract LifecycleRig.Visits --lifecycle visit --overlay --output) ++
            [path, "--since", since]
        )

        File.read!(path)
      end

      assert draw.(digits <> "+02:00") =~ ~s'start -->|"Visit booked · 1x"| status_booked'
      # The same digits without an offset are UTC: an hour after the booking.
      assert draw.(digits) =~ ~s'start -->|"Visit booked · 0x"| status_booked'

      assert_raise Mix.Error, ~r/--since needs an ISO8601 time/, fn -> draw.("yesterday") end
    end

    @tag :tmp_dir
    test "draws an aggregate's lifecycle", %{tmp_dir: dir} do
      path = Path.join(dir, "lifecycle.mmd")

      Mix.Tasks.EhOsContract.Graph.run(
        ~w(--contract LifecycleRig.Visits --lifecycle visit --output) ++ [path]
      )

      assert File.read!(path) =~ ~s'start -->|"Visit booked"| status_booked'
    end

    test "refuses an aggregate without one, a lifecycle without its contract, and both pictures" do
      assert_raise Mix.Error,
                   ~r/LifecycleRig\.Visits has no aggregate nonesuch with a lifecycle\. With one: visit/,
                   fn ->
                     Mix.Tasks.EhOsContract.Graph.run(
                       ~w(--contract LifecycleRig.Visits --lifecycle nonesuch)
                     )
                   end

      assert_raise Mix.Error, ~r/pass --contract too/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--lifecycle visit))
      end

      assert_raise Mix.Error, ~r/--since applies to --overlay/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(
          ~w(--contract LifecycleRig.Visits --lifecycle visit --since 2026-01-01T00:00:00)
        )
      end

      assert_raise Mix.Error, ~r/BoundaryRig\.Waitlist declares no lifecycle/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--contract BoundaryRig.Waitlist --lifecycle entry))
      end

      assert_raise Mix.Error, ~r/--unit and --lifecycle draw different pictures/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(
          ~w(--contract LifecycleRig.Visits --unit visit --lifecycle visit)
        )
      end
    end
  end
end
