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

    for p <- Registry.processes() do
      p |> Overlay.process() |> valid!() |> joins!(Document.process(p))
    end

    modules = contracts ++ Registry.processes()

    for d <- Registry.domains() do
      d |> Overlay.domain(contracts) |> valid!() |> joins!(Document.domain(d, contracts))
      d |> Overlay.domain(modules) |> valid!() |> joins!(Document.domain(d, modules))
    end
  end

  test "the facts document does not depend on the log" do
    before = Document.contract(DispatchRig.Ledger)
    domain = Document.domain(DispatchRig.Domain, Registry.contracts())
    seed_ledger()

    assert Document.contract(DispatchRig.Ledger) == before
    assert Document.domain(DispatchRig.Domain, Registry.contracts()) == domain
  end

  test "an event's occurrences, and a step's numbers on its emits" do
    seed_ledger()
    d = Document.contract(DispatchRig.Ledger)
    o = Overlay.contract(DispatchRig.Ledger)
    id = &Document.id([&1, "dispatch_rig.ledger", &2])

    assert o["nodes"][id.(:event, :deposited)] == %{"occurrences" => 2}

    # Counted by type, whatever declares it; a type the log does not hold has no entry.
    assert Paths.occurrences_by_type(["dispatch_rig.ledger.deposited", "nowhere.nothing"]) ==
             %{"dispatch_rig.ledger.deposited" => 2}

    assert Paths.occurrences_by_type([]) == %{}
    assert o["nodes"][id.(:event, :account_opened)] == %{"occurrences" => 2}

    # A contract has no runs: they are a process module's.
    o |> valid!() |> joins!(d)
    refute Enum.any?(Map.values(o["nodes"]), &Map.has_key?(&1, "runs"))

    deposit =
      o["relations"][relation(d, "emits", id.(:command, :deposit), id.(:event, :deposited))]

    assert %{"taken" => 2, "untraversed" => false, "pending" => false} = deposit

    # The numbers are the report's, step for step.
    observed = Paths.observe(DispatchRig.Ledger)
    step = Enum.find(observed, &(&1.from.name == :deposit and &1.to.name == :deposited))
    assert deposit["waiting"] == Model.json_data(step.in_flight)
    assert deposit["failing"] == Model.json_data(step.failing)

    never =
      for s <- Conformance.report(DispatchRig.Ledger).paths.untraversed,
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
    id = &Document.id([&1, Model.fetch(ProcessShapes.Promised).id, &2])

    notify =
      o["relations"][
        relation(d, "issues", id.(:policy, :notify_on_refusal), id.(:command, :notify_refusal))
      ]

    assert %{"taken" => 0, "untraversed" => false, "pending" => false} = notify

    assert notify["waiting"]["lag"] + notify["waiting"]["effects"] + notify["waiting"]["timers"] ==
             1

    # The report's reading comes with the numbers: it waits, and nothing fails.
    assert %{"waits" => true, "fails" => false} = notify

    # What the waiting command would emit is behind it: not yet, and not never.
    behind =
      o["relations"][
        relation(d, "emits", id.(:command, :notify_refusal), id.(:event, :refusal_notified))
      ]

    assert %{"taken" => 0, "pending" => true, "untraversed" => false} = behind
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
    visits = Model.fetch(Visits).id
    status = &Document.id([:status, visits, :visit, &1])
    event = &Document.id([:event, visits, &1])

    assert o["nodes"][Document.id([:unit, visits, :visit])] == %{"aggregates" => 2}

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

  test "a domain's: the events between two contracts, and each contract's drift" do
    seed_ledger()
    contracts = Registry.contracts()
    o = Overlay.domain(DispatchRig.Domain, contracts)
    contract = &Document.id([:contract, Model.fetch(&1).id])

    # Plan DD, G1 (#297): a contract's node carries its drift, as the report counts it —
    # its declared steps and transitions never taken, its moves no lifecycle allows — and
    # no runs, which are a process module's.
    for c <- [DispatchRig.Ledger, DispatchRig.Branch] do
      steps = c |> Conformance.steps([]) |> Enum.uniq()
      lifecycles = Conformance.lifecycles(Model.fetch(c), [])

      assert o["nodes"][contract.(c)] == %{
               "untraversed" =>
                 Enum.count(steps, & &1.untraversed) +
                   Enum.sum(for l <- lifecycles, do: length(l.untraversed)),
               "undeclared" => Enum.sum(for l <- lifecycles, do: length(l.undeclared))
             }
    end

    # Some of the ledger's declared paths the seed never takes.
    assert o["nodes"][contract.(DispatchRig.Ledger)]["untraversed"] > 0
    refute Enum.any?(Map.values(o["nodes"]), &Map.has_key?(&1, "runs"))

    between =
      Document.id([:consumed_by, contract.(DispatchRig.Ledger), contract.(DispatchRig.Branch)])

    assert %{"events" => 2, "failing" => false} = o["relations"][between]
    assert o["version"] == Model.fetch(DispatchRig.Domain).version
  end

  # Plan DD, P2e (#220): a process module's runs, its events and its promise's verdicts,
  # the report's own.
  describe "a process module's" do
    alias DispatchRig.AccountReview
    alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
    alias DispatchRig.Ledger.Events.BalanceConfirmed

    defp review(account, confirmed?) do
      clerk = Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit
        dispatch_rig.withdraw))

      for command <- [
            %OpenAccount{account_id: account, branch_id: "b-7"},
            %Deposit{account_id: account, amount: 100},
            %Withdraw{account_id: account, amount: 50}
          ] do
        {:ok, _} = EhOsContract.dispatch(DispatchRig.Ledger, command, actor: clerk)
      end

      if confirmed? do
        auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

        {:ok, _} =
          EhOsContract.record(DispatchRig.Ledger, %BalanceConfirmed{account_id: account},
            actor: auditor
          )
      end
    end

    test "runs on the process, occurrences on its events, verdicts on its promise" do
      review("a-1", true)
      review("a-2", false)

      d = Document.process(AccountReview)
      o = AccountReview |> Overlay.process() |> valid!() |> joins!(d)
      report = Conformance.process(Model.fetch(AccountReview))
      event = &Document.id([:event, "dispatch_rig.ledger", &1])

      assert %{"kind" => "process", "process" => "dispatch_rig.account_review"} = o
      assert o["version"] == Model.fetch(AccountReview).version
      assert o["nodes"]["process:dispatch_rig.account_review"] == %{"runs" => report.runs}
      assert report.runs == 2

      assert o["nodes"][event.(:withdrawn)] == %{"occurrences" => 2}
      assert o["nodes"][event.(:balance_confirmed)] == %{"occurrences" => 1}

      # Only the events it includes: the ledger's deposits are not on its picture.
      refute Map.has_key?(o["nodes"], event.(:deposited))

      [promise] = report.promises

      assert o["nodes"][
               "promise:dispatch_rig.account_review:balance_confirmed_after_withdrawal"
             ] == %{
               "satisfied" => 1,
               "satisfied_via_eventually" => 1,
               "satisfied_via_or_else" => 0,
               "violated" => 0,
               "pending" => 1,
               "suspended" => 0,
               "instances" => 2
             }

      assert promise.pending == 1
      assert o["relations"] == %{}

      # A period after everything counts nothing.
      later = Overlay.process(AccountReview, since: DateTime.add(DateTime.utc_now(), 3600))
      assert later["nodes"]["process:dispatch_rig.account_review"] == %{"runs" => 0}
      # An event that did not happen is 0, not missing, so no reader infers the zero.
      assert later["nodes"][event.(:withdrawn)] == %{"occurrences" => 0}
    end

    # The ids are the facts' to make: the overlay reads them from its document, so it
    # follows them wherever they change.
    test "keys its numbers by the ids its document gives, and by nothing else" do
      review("a-1", true)
      d = Document.process(AccountReview)
      o = Overlay.process(AccountReview)

      [process] = d["nodes"]["process"]
      events = for e <- d["nodes"]["event"], do: e["id"]
      promises = for p <- d["nodes"]["promise"], do: p["id"]

      assert Enum.sort(Map.keys(o["nodes"])) == Enum.sort([process["id"] | events ++ promises])
    end

    test "a promise the owner has yet to confirm has no verdicts, as in the report" do
      process = compile_unverified_promise()
      o = process |> Overlay.process() |> valid!() |> joins!(Document.process(process))

      assert [%{"unverified" => true, "id" => id}] =
               Document.process(process)["nodes"]["promise"]

      refute Map.has_key?(o["nodes"], id)
    end

    test "the domain's puts each process module's runs on its node" do
      review("a-1", true)
      modules = Registry.contracts() ++ Registry.processes()

      o =
        DispatchRig.Domain
        |> Overlay.domain(modules)
        |> valid!()
        |> joins!(Document.domain(DispatchRig.Domain, modules))

      assert o["nodes"]["process:dispatch_rig.account_review"] == %{"runs" => 1}
      assert o["nodes"]["process:dispatch_rig.branch_run"] == %{"runs" => 1}
    end
  end

  defp compile_unverified_promise do
    %{module: module} =
      EhOsContract.DslCase.compile_process(
        "UnverifiedReview",
        """
          correlate :account_id
          stage :withdrawal, include: [{DispatchRig.Ledger, :withdrawn}]
          stage :confirmation, include: [{DispatchRig.Ledger, :balance_confirmed}]
          ends_on :balance_confirmed

          promise :confirmed do
            from :withdrawn
            eventually :balance_confirmed
            within {1, :day}
            unverified true
          end
        """,
        id: "dispatch_rig.unverified_review",
        domain: DispatchRig.Domain
      )

    module
  end

  # How many queries `fun` sends to the repo.
  defp queries(fun) do
    handler = "graph-queries-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:eh_os_contract, :test_repo, :query],
      fn _event, _measurements, _meta, _config -> :counters.add(counter, 1, 1) end,
      nil
    )

    try do
      fun.()
      :counters.get(counter, 1)
    after
      :telemetry.detach(handler)
    end
  end

  test "a domain's reads each contract's drift, the consumers' steps, and counts every pair at once" do
    contracts = Registry.contracts()
    mine = Enum.filter(contracts, &(Model.fetch(&1).domain == DispatchRig.Domain))

    # Each contract's steps and lifecycles once, for its drift (plan DD, G1, #297);
    # DispatchRig.Branch, the one consumer, its steps again for what crosses; and one count
    # for every pair of contracts.
    drift =
      queries(fn ->
        for c <- mine, do: {Conformance.steps(c, []), Conformance.lifecycles(Model.fetch(c), [])}
      end)

    budget = drift + queries(fn -> Paths.observe(DispatchRig.Branch) end) + 1

    contracts_only = queries(fn -> Overlay.domain(DispatchRig.Domain, contracts) end)
    assert contracts_only <= budget

    # And at most one more for the runs of all its process modules, however many there are.
    processes = Enum.filter(Registry.processes(), &(Model.fetch(&1).domain == DispatchRig.Domain))
    assert length(processes) >= 2
    modules = contracts ++ processes

    assert queries(fn -> Overlay.domain(DispatchRig.Domain, modules) end) <= contracts_only + 1
  end

  test "a promise's verdicts are asked of a process module, never of a contract" do
    assert_raise ArgumentError, ~r/is not a process module/, fn ->
      Conformance.promise_verdicts(Model.fetch(DispatchRig.Branch))
    end
  end

  test "the overlay says its period, and counts only what happened in it" do
    seed_ledger()
    since = DateTime.add(DateTime.utc_now(), 3600)
    o = Overlay.contract(DispatchRig.Ledger, since: since)

    assert o["since"] == DateTime.to_iso8601(since)
    assert o["until"] == nil
    assert o["version"] == Model.fetch(DispatchRig.Ledger).version
    id = &Document.id([&1, "dispatch_rig.ledger", &2])
    refute Map.has_key?(o["nodes"], id.(:event, :deposited))

    d = Document.contract(DispatchRig.Ledger)
    deposit = relation(d, "emits", id.(:command, :deposit), id.(:event, :deposited))
    assert %{"taken" => 0} = o["relations"][deposit]

    until = DateTime.add(DateTime.utc_now(), -3600)
    earlier = Overlay.contract(DispatchRig.Ledger, until: until)
    assert earlier["until"] == DateTime.to_iso8601(until)
    assert %{"taken" => 0} = earlier["relations"][deposit]
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
    assert entry["taken"] == step.taken, where
    assert entry["waiting"] == Model.json_data(step.in_flight), where
    assert entry["failing"] == Model.json_data(step.failing), where
    assert entry["waits"] == Conformance.waiting?(step), where
    assert entry["fails"] == Conformance.failing?(step), where
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
    ref = &Document.id([&1.kind, model.id, &1.name])

    # The overlay's "never" is the report's, line for line.
    assert MapSet.new(Conformance.report(model).paths.untraversed, &key/1) ==
             MapSet.new(for(s <- steps, s.untraversed, do: key(s))),
           inspect(c)

    {phased, ended} =
      steps
      |> Enum.map(&{&1, ends(d, model.id, &1)})
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
          Map.has_key?(entry, "taken") or Map.has_key?(entry, "by_trigger"),
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
    id = &Document.id([&1, model.id, &2])

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

    assert %{"taken" => 0} = o["relations"][moved["id"]]
  end

  test "a policy's relation carries each triggering event's numbers, and no total" do
    seed_visits()
    d = Document.contract(PhaseRig.Visits)
    o = Overlay.contract(PhaseRig.Visits)
    id = &Document.id([&1, "phase_rig.visits", &2])

    rid = relation(d, "issues", id.(:policy, :remind_on_change), id.(:command, :remind))

    assert %{
             "by_trigger" => %{
               booked: %{"taken" => 6, "untraversed" => false},
               moved: %{"taken" => 2}
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
    id = &Document.id([&1, "phase_rig.visits", &2])

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

    assert step.taken == 5
  end
end
