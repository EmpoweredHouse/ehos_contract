defmodule EhosContract.NoProcessTest do
  @moduledoc """
  Plan DD, P1c (#190): a contract whose events no process module includes. Its units
  decide, dispatch appends to the log without indexing a run, and every reader answers
  for it with what it has: the lifecycle, the steps, no run, no promise. On the invented
  `LifecycleRig.Rooms`. Since plan DD, P2h (#221) no contract declares a process of its
  own.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.{
    Actor,
    Check,
    Conformance,
    EventRun,
    Model,
    Pages,
    Rejection,
    Report,
    View
  }

  alias EhosContract.{AsyncAPI, Graph, OpenAPI}
  alias LifecycleRig.Rooms
  alias LifecycleRig.Rooms.Commands.{OpenRoom, RetireRoom}

  defp reception,
    do: Actor.credential("u-reception", ~w(lifecycle_rig.open_room lifecycle_rig.retire_room))

  defp issue(module, room),
    do: EhosContract.dispatch(Rooms, struct(module, room_id: room), actor: reception())

  test "the model has no process" do
    refute Map.has_key?(Model.fetch(Rooms), :process)
    assert Model.process(Rooms) == nil
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

  test "the graph document and its overlay hold the contract, its unit and its lifecycle" do
    {:ok, _} = issue(OpenRoom, "r-1")

    document = Graph.Document.contract(Rooms)
    refute Map.has_key?(document["nodes"], "process")
    assert [%{"name" => "room"}] = document["nodes"]["unit"]

    assert Enum.any?(
             document["nodes"]["status"],
             &(&1["unit"] == "unit:lifecycle_rig.rooms:room")
           )

    assert Graph.Overlay.contract(Rooms)["nodes"]["event:lifecycle_rig.rooms:opened"] ==
             %{"occurrences" => 1}
  end

  test "the generated documents, the pages, the view and the check read it" do
    assert %{} = OpenAPI.document(Rooms)
    assert %{} = AsyncAPI.document(Rooms)
    assert Enum.any?(Map.keys(Pages.render(LifecycleRig.Domain, [Rooms])), &(&1 =~ "room"))
    assert View.render(LifecycleRig.Domain, [Rooms]) =~ "aggregate room"
    assert Check.findings([Rooms]) == []
  end
end
