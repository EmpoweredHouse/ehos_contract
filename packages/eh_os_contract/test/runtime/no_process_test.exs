defmodule EhOsContract.NoProcessTest do
  @moduledoc """
  Plan DD, P1c (#190): a contract may describe no process (R1). Its units decide,
  dispatch appends to the log without indexing a run, and every reader answers for it
  with what it has: the lifecycle, the steps, no run, no promise. On the invented
  `LifecycleRig.Rooms`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{
    Actor,
    Check,
    Conformance,
    EventRun,
    Graph,
    Model,
    Pages,
    Rejection,
    Report,
    View
  }

  alias EhOsContract.{AsyncAPI, OpenAPI}
  alias LifecycleRig.Rooms
  alias LifecycleRig.Rooms.Commands.{OpenRoom, RetireRoom}

  defp reception,
    do: Actor.credential("u-reception", ~w(lifecycle_rig.open_room lifecycle_rig.retire_room))

  defp issue(module, room),
    do: EhOsContract.dispatch(Rooms, struct(module, room_id: room), actor: reception())

  test "the model has no process" do
    assert Model.fetch(Rooms).process == nil
  end

  test "dispatch decides and appends, and files the events under no run" do
    assert {:ok, _} = issue(OpenRoom, "r-1")
    assert {:ok, _} = issue(RetireRoom, "r-1")
    assert {:error, %Rejection{invariant: :only_an_available_room}} = issue(RetireRoom, "r-1")

    assert Repo.aggregate(EventRun, :count) == 0
  end

  test "the report answers with the lifecycle and the steps, and no process" do
    {:ok, _} = issue(OpenRoom, "r-1")
    {:ok, _} = issue(RetireRoom, "r-1")
    {:ok, _} = issue(OpenRoom, "r-2")

    report = Conformance.report(Rooms)

    assert report.processes == []
    assert [%{aggregates: 2, untraversed: [], undeclared: []}] = report.lifecycles
    assert is_binary(Report.render(report))
  end

  test "the graphs draw the contract and its unit" do
    {:ok, _} = issue(OpenRoom, "r-1")

    assert Graph.contract_to_mermaid(Rooms, overlay: true) =~ "opened"
    assert Graph.unit_to_mermaid(Rooms, :room) =~ "retire_room"
    assert Graph.lifecycle_to_mermaid(Rooms, :room) =~ "retired"
  end

  test "the generated documents, the pages, the view and the check read it" do
    assert %{} = OpenAPI.document(Rooms)
    assert %{} = AsyncAPI.document(Rooms)
    assert Enum.any?(Map.keys(Pages.render(LifecycleRig.Domain, [Rooms])), &(&1 =~ "room"))
    assert View.render(LifecycleRig.Domain, [Rooms]) =~ "aggregate room"
    assert Check.findings([Rooms]) == []
  end
end
