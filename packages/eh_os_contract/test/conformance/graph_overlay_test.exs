defmodule EhOsContract.GraphOverlayTest do
  @moduledoc """
  Plan E13a, batch 5: what the log says over a `graph.v1` document, as a document of
  its own — numbers keyed by the facts' ids, the report's and the pictures' numbers
  and no others, and the facts document unmoved by anything in the log.
  """

  use EhOsContract.DataCase, async: false

  import EhOsContract.DslCase, only: [compile_contract: 2]
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias EhOsContract.{Actor, Conformance, Model, Paths, Registry, Testing}

  alias EhOsContract.Graph.{Document, Overlay}
  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AdmitPatient, BookVisit, CloseVisit}
  alias LifecycleRig.Visits.Events.PatientArrived
  alias ProcessShapes.Seed

  @schema Overlay.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp valid!(overlay) do
    case JSV.validate(overlay, @schema) do
      {:ok, _} -> overlay
      {:error, error} -> flunk(inspect(JSV.normalize_error(error)))
    end
  end

  # Every key of the overlay is an id of the document, or of what the overlay defines.
  defp joins!(overlay, document) do
    defined = for {_type, rs} <- overlay["observed"]["relations"], r <- rs, do: r["id"]
    nodes = for {_kind, ns} <- document["nodes"], n <- ns, into: MapSet.new(), do: n["id"]

    relations =
      for {_type, rs} <- document["relations"], r <- rs, into: MapSet.new(defined), do: r["id"]

    for id <- Map.keys(overlay["nodes"]), do: assert(MapSet.member?(nodes, id), id)
    for id <- Map.keys(overlay["relations"]), do: assert(MapSet.member?(relations, id), id)

    # A relation's numbers by triggering event are keyed by the event's id.
    for {_rid, %{"by_trigger" => by}} <- overlay["relations"],
        id <- Map.keys(by),
        do: assert(MapSet.member?(nodes, id), id)

    for {_type, rs} <- overlay["observed"]["relations"],
        r <- rs,
        id <- [r["from"], r["to"]],
        do: assert(MapSet.member?(nodes, id), id)

    assert overlay["document_digest"] == document["digest"]
    overlay
  end

  defp relation(document, type, from, to) do
    Enum.find(document["relations"][type], &(&1["from"] == from and &1["to"] == to))["id"]
  end

  defp seed_ledger do
    clerk = Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

    for command <- [
          %DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-1", branch_id: "b-7"},
          %DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-2", branch_id: "b-7"},
          %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 5},
          %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 6}
        ] do
      {:ok, _} = EhOsContract.dispatch(DispatchRig.Ledger, command, actor: clerk)
    end
  end

  test "every contract's and domain's overlay holds to its schema and joins its document" do
    seed_ledger()
    contracts = Registry.contracts()

    for c <- contracts do
      c |> Overlay.contract() |> valid!() |> joins!(Document.contract(c))
    end

    for d <- Registry.domains() do
      d |> Overlay.domain(contracts) |> valid!() |> joins!(Document.domain(d, contracts))
    end
  end

  test "the facts document does not depend on the log" do
    before = Document.contract(DispatchRig.Ledger)
    domain = Document.domain(DispatchRig.Domain, Registry.contracts())
    seed_ledger()

    assert Document.contract(DispatchRig.Ledger) == before
    assert Document.domain(DispatchRig.Domain, Registry.contracts()) == domain
  end

  test "an event's occurrences and runs, a process's runs, and a step's numbers on its emits" do
    seed_ledger()
    d = Document.contract(DispatchRig.Ledger)
    o = Overlay.contract(DispatchRig.Ledger)
    id = &Document.id([&1, DispatchRig.Ledger, &2])

    assert o["nodes"][id.(:event, :deposited)] == %{"occurrences" => 2, "runs" => 1}
    assert o["nodes"][id.(:event, :account_opened)] == %{"occurrences" => 2, "runs" => 2}
    assert o["nodes"][id.(:process, :ledger)] == %{"runs" => 2}

    deposit =
      o["relations"][relation(d, "emits", id.(:command, :deposit), id.(:event, :deposited))]

    assert %{"runs" => 1, "of_runs" => 2, "untraversed" => false, "pending" => false} = deposit

    # The numbers are the report's, step for step.
    observed = Paths.observe(DispatchRig.Ledger)
    step = Enum.find(observed, &(&1.from.name == :deposit and &1.to.name == :deposited))
    assert deposit["waiting"] == Model.json_data(step.in_flight)
    assert deposit["failing"] == Model.json_data(step.failing)

    [process] = Conformance.report(DispatchRig.Ledger).processes

    never =
      for s <- process.untraversed,
          s.via == nil,
          do: relation(d, "emits", id.(:command, s.from.name), id.(:event, s.to.name))

    assert [_ | _] = never

    for rid <- never, do: assert(%{"untraversed" => true} = o["relations"][rid])
  end

  test "a step behind work still on its way is not yet, and waiting is by source" do
    Seed.deploy()
    Seed.request("r-1", :request_approved)
    Seed.request("r-2", :request_refused)

    d = Document.contract(ProcessShapes.Promised)
    o = Overlay.contract(ProcessShapes.Promised)
    id = &Document.id([&1, ProcessShapes.Promised, &2])

    notify =
      o["relations"][
        relation(d, "issues", id.(:policy, :notify_on_refusal), id.(:command, :notify_refusal))
      ]

    assert %{"runs" => 0, "of_runs" => 2, "untraversed" => false, "pending" => false} = notify

    assert notify["waiting"]["lag"] + notify["waiting"]["effects"] + notify["waiting"]["timers"] ==
             1

    # What the waiting command would emit is behind it: not yet, and not never.
    behind =
      o["relations"][
        relation(d, "emits", id.(:command, :notify_refusal), id.(:event, :refusal_notified))
      ]

    assert %{"runs" => 0, "pending" => true, "untraversed" => false} = behind
  end

  test "a lifecycle's transitions, an aggregate count, and a move it does not allow, defined" do
    reception =
      Actor.credential(
        "u-reception",
        Enum.map(~w(book_visit admit_patient close_visit), &"lifecycle_rig.#{&1}")
      )

    for {command, visit} <- [
          {BookVisit, "v-1"},
          {AdmitPatient, "v-1"},
          {CloseVisit, "v-1"},
          {BookVisit, "v-2"}
        ] do
      {:ok, _} = EhOsContract.dispatch(Visits, struct(command, visit_id: visit), actor: reception)
    end

    {:ok, _} =
      EhOsContract.record(Visits, %PatientArrived{visit_id: "v-1"},
        actor: Actor.system(:front_desk)
      )

    d = Document.contract(Visits)
    o = Overlay.contract(Visits) |> valid!() |> joins!(d)
    status = &Document.id([:status, Visits, :visit, &1])
    event = &Document.id([:event, Visits, &1])

    assert o["nodes"][Document.id([:unit, Visits, :visit])] == %{"aggregates" => 2}

    assert o["relations"][relation(d, "enters", event.(:booked), status.(:booked))] ==
             %{"count" => 2, "pending" => false, "untraversed" => false}

    cancelled =
      Enum.find(
        d["relations"]["transition"],
        &(&1["from"] == status.(:booked) and &1["to"] == status.(:cancelled))
      )

    assert %{"count" => 0, "pending" => true} = o["relations"][cancelled["id"]]

    closed = status.(:closed)

    assert [%{"id" => moved, "from" => ^closed, "to" => ^closed, "event" => arrived}] =
             o["observed"]["relations"]["undeclared"]

    assert arrived == event.(:patient_arrived)
    assert o["relations"][moved] == %{"count" => 1}
  end

  test "a domain's: each contract's runs and the events between two contracts" do
    seed_ledger()
    contracts = Registry.contracts()
    o = Overlay.domain(DispatchRig.Domain, contracts)
    contract = &Document.id([:contract, &1])

    assert o["nodes"][contract.(DispatchRig.Ledger)] == %{"runs" => 2}

    between =
      Document.id([:consumed_by, contract.(DispatchRig.Ledger), contract.(DispatchRig.Branch)])

    assert %{"events" => 2, "failing" => false} = o["relations"][between]
    assert o["version"] == Model.fetch(DispatchRig.Domain).version
  end

  test "the overlay says its period, and counts only what happened in it" do
    seed_ledger()
    since = DateTime.add(DateTime.utc_now(), 3600)
    o = Overlay.contract(DispatchRig.Ledger, since: since)

    assert o["since"] == DateTime.to_iso8601(since)
    assert o["until"] == nil
    assert o["version"] == Model.fetch(DispatchRig.Ledger).version
    assert o["nodes"][Document.id([:process, DispatchRig.Ledger, :ledger])] == %{"runs" => 0}
    refute Map.has_key?(o["nodes"], Document.id([:event, DispatchRig.Ledger, :deposited]))

    d = Document.contract(DispatchRig.Ledger)
    id = &Document.id([&1, DispatchRig.Ledger, &2])
    deposit = relation(d, "emits", id.(:command, :deposit), id.(:event, :deposited))
    assert %{"runs" => 0, "of_runs" => 0} = o["relations"][deposit]

    until = DateTime.add(DateTime.utc_now(), -3600)
    earlier = Overlay.contract(DispatchRig.Ledger, until: until)
    assert earlier["until"] == DateTime.to_iso8601(until)
    assert %{"runs" => 0} = earlier["relations"][deposit]
  end

  # --- the steps' numbers on their relations ------------------------------------------

  @clerk Actor.credential("u-1", ~w(phase_rig.book phase_rig.move phase_rig.close))

  defp visit(command, id) do
    command = struct(Module.concat([PhaseRig.Visits.Commands, command]), visit_id: id)
    {:ok, _} = EhOsContract.dispatch(PhaseRig.Visits, command, actor: @clerk)
  end

  # v-1: booked as its run starts and again during it, moved, closed, then booked after
  # the end, which no run takes; v-2: booked once; v-3: moved with no run; v-4: booked
  # twice. Drained after each command, so the manager takes the events in order.
  defp seed_visits do
    Testing.drain()

    for {command, id} <- [
          {Book, "v-1"},
          {Book, "v-1"},
          {Move, "v-1"},
          {Close, "v-1"},
          {Book, "v-1"},
          {Book, "v-2"},
          {Move, "v-3"},
          {Book, "v-4"},
          {Book, "v-4"}
        ] do
      visit(command, id)
      %{failing: []} = Testing.drain()
    end
  end

  # The relations of the document a step ends at, as the catalogue defines them.
  defp ends(document, c, step) do
    ref = &Document.id([&1.kind, c, &1.name])

    {type, from, to, on} =
      cond do
        step.via == nil ->
          {"emits", ref.(step.from), ref.(step.to), nil}

        step.from.kind == :timer ->
          {"fires", Document.id([:timer, c, step.via.name, step.from.name]), ref.(step.to), nil}

        step.to == nil ->
          {"handled_by", ref.(step.from), ref.(step.via), nil}

        step.via.kind == :process_manager ->
          {"issues", ref.(step.via), ref.(step.to), ref.(step.from)}

        true ->
          {"issues", ref.(step.via), ref.(step.to), nil}
      end

    for r <- document["relations"][type],
        r["from"] == from and r["to"] == to and (on == nil or r["on"] == on),
        do: r
  end

  defp same!(entry, step, where) do
    assert entry["runs"] == step.runs, where
    assert entry["of_runs"] == step.of_runs, where
    assert entry["waiting"] == Model.json_data(step.in_flight), where
    assert entry["failing"] == Model.json_data(step.failing), where
    assert entry["untraversed"] == step.untraversed, where
    assert entry["pending"] == step.pending, where
  end

  defp key(step), do: {step.from, step.via, step.to}

  # Every step the report has puts its numbers on a relation — flat where it is the
  # relation's one step, under `by_trigger` where several steps end there — except a
  # manager's step at its two phases' relations, which get none; no other relation
  # carries a step's numbers, and a step that ends at no relation, or at two that are
  # not such a manager's phases, fails here. Returns which of the three ways it met.
  defp every_step_numbered!(c) do
    d = Document.contract(c)

    # A shape the overlay does not know is logged; the fixtures have none, and the
    # manager's phases are a shape it knows.
    {o, log} = with_log(fn -> Overlay.contract(c) end)
    refute log =~ "where its numbers need one", log
    o = o |> valid!() |> joins!(d)
    model = Model.fetch(c)
    steps = Enum.uniq(Conformance.steps(model))
    ref = &Document.id([&1.kind, model.module, &1.name])

    # The overlay's "never" is the report's, line for line.
    if model.process do
      [process] = Conformance.report(model).processes

      assert MapSet.new(process.untraversed, &key/1) ==
               MapSet.new(for(s <- steps, s.untraversed, do: key(s))),
             inspect(c)
    end

    {phased, ended} =
      steps
      |> Enum.map(&{&1, ends(d, model.module, &1)})
      |> Enum.split_with(fn {_step, rs} -> length(rs) == 2 end)

    for {step, rs} <- phased do
      assert Enum.sort(Enum.map(rs, & &1["phase"])) == ["run", "start"], inspect(step)
      for r <- rs, do: refute(Map.has_key?(o["relations"], r["id"]), r["id"])
    end

    for {step, rs} <- ended, do: assert(length(rs) == 1, inspect(step))

    by_relation =
      ended
      |> Enum.map(fn {step, [r]} -> {r, step} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    ways =
      for {r, relation_steps} <- by_relation do
        entry = o["relations"][r["id"]]
        where = "#{inspect(c)}: #{r["id"]}"
        assert entry, where

        case relation_steps do
          [step] ->
            same!(entry, step, where)
            :flat

          many ->
            assert [{"by_trigger", by}] = Map.to_list(entry), where
            assert Enum.sort(Map.keys(by)) == Enum.sort(Enum.map(many, &ref.(&1.from))), where
            for step <- many, do: same!(by[ref.(step.from)], step, where)
            :by_trigger
        end
      end

    numbered =
      for {rid, entry} <- o["relations"],
          Map.has_key?(entry, "of_runs") or Map.has_key?(entry, "by_trigger"),
          do: rid

    assert Enum.sort(numbered) == by_relation |> Map.keys() |> Enum.map(& &1["id"]) |> Enum.sort()
    MapSet.new(ways ++ if(phased == [], do: [], else: [:phases_without_numbers]))
  end

  test "every step of every contract puts its numbers on a relation, but a manager's phases" do
    seed_ledger()
    seed_visits()

    ways =
      for c <- Registry.contracts(), reduce: MapSet.new() do
        ways -> MapSet.union(ways, every_step_numbered!(c))
      end

    # PhaseRig holds both shapes; the rest of the fixtures, one step a relation.
    assert ways == MapSet.new([:flat, :by_trigger, :phases_without_numbers])
  end

  test "both shapes compiled together, a policy issuing two commands on two events among them" do
    model =
      compile_contract("GraphOverlayShared", """
        process :visit, "Visit" do
          correlate :visit_id
        end

        aggregate :visit, "Visit" do
          identity :visit_id
          command :book, "Book", by: :reception, emits: :booked
          command :move, "Move", by: :reception, emits: :moved
          command :remind, "Remind", by: :reception, emits: :reminded
          command :log, "Log", by: :reception, emits: :logged
          event :booked, "Booked"
          event :moved, "Moved"
          event :reminded, "Reminded"
          event :logged, "Logged"
        end

        policy :remind_on_change, "Remind on a change",
          handles: [:booked, :moved],
          issues: [:remind, :log]

        process_manager :chase, "Chase" do
          correlate :visit_id
          starts_on :booked, issues: :remind
          on :booked, issues: :remind
          on :moved, issues: :remind
          ends_on :logged
        end
      """)

    assert every_step_numbered!(model) ==
             MapSet.new([:flat, :by_trigger, :phases_without_numbers])

    d = Document.contract(model)
    o = Overlay.contract(model)
    id = &Document.id([&1, model.module, &2])

    for command <- [:remind, :log] do
      rid = relation(d, "issues", id.(:policy, :remind_on_change), id.(:command, command))

      assert %{"by_trigger" => by} = o["relations"][rid]
      assert Map.keys(by) |> Enum.sort() == Enum.sort([id.(:event, :booked), id.(:event, :moved)])
    end

    # The manager's move, during a run only, is one step at one relation.
    moved =
      Enum.find(
        d["relations"]["issues"],
        &(&1["from"] == id.(:process_manager, :chase) and &1["on"] == id.(:event, :moved))
      )

    assert %{"runs" => 0, "of_runs" => 0} = o["relations"][moved["id"]]
  end

  test "a policy's relation carries each triggering event's numbers, and no total" do
    seed_visits()
    d = Document.contract(PhaseRig.Visits)
    o = Overlay.contract(PhaseRig.Visits)
    id = &Document.id([&1, PhaseRig.Visits, &2])

    rid = relation(d, "issues", id.(:policy, :remind_on_change), id.(:command, :remind))

    assert %{
             "by_trigger" => %{
               booked: %{"runs" => 3, "of_runs" => 4, "untraversed" => false},
               moved: %{"runs" => 2, "of_runs" => 4}
             }
           } =
             rekey(o["relations"][rid], booked: id.(:event, :booked), moved: id.(:event, :moved))
  end

  defp rekey(%{"by_trigger" => by}, names),
    do: %{"by_trigger" => Map.new(names, fn {name, id} -> {name, Map.fetch!(by, id)} end)}

  test "a manager's step at its start and during a run gets no numbers; the report reads it whole" do
    seed_visits()
    d = Document.contract(PhaseRig.Visits)
    o = Overlay.contract(PhaseRig.Visits)
    id = &Document.id([&1, PhaseRig.Visits, &2])

    phases =
      for r <- d["relations"]["issues"],
          r["from"] == id.(:process_manager, :watch) and r["on"] == id.(:event, :booked),
          do: r

    assert Enum.sort(Enum.map(phases, & &1["phase"])) == ["run", "start"]
    for r <- phases, do: refute(Map.has_key?(o["relations"], r["id"]))

    # v-1, v-2 and v-4 noted a booking, at the start of the run or during it.
    [step] =
      PhaseRig.Visits
      |> Paths.observe()
      |> Enum.filter(&(match?(%{kind: :process_manager}, &1.via) and &1.from.name == :booked))
      |> Enum.uniq()

    assert step.runs == 3
  end
end
