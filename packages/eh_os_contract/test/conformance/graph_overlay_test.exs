defmodule EhOsContract.GraphOverlayTest do
  @moduledoc """
  Plan E13a, batch 5: what the log says over a `graph.v1` document, as a document of
  its own — numbers keyed by the facts' ids, the report's and the pictures' numbers
  and no others, and the facts document unmoved by anything in the log.
  """

  use EhOsContract.DataCase, async: false

  import EhOsContract.DslCase, only: [compile_contract: 2]

  alias EhOsContract.{Actor, Conformance, Model, Paths, Registry}
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

  test "every step's numbers sit on the one relation that ends it" do
    seed_ledger()

    for c <- Registry.contracts() do
      d = Document.contract(c)
      o = Overlay.contract(c)
      ref = &Document.id([&1.kind, c, &1.name])
      steps = Enum.uniq(Conformance.steps(c))

      for step <- steps do
        {type, from, to, on} =
          cond do
            step.via == nil ->
              {"emits", ref.(step.from), ref.(step.to), nil}

            step.from.kind == :timer ->
              {"fires", Document.id([:timer, c, step.via.name, step.from.name]), ref.(step.to),
               nil}

            step.to == nil ->
              {"handled_by", ref.(step.from), ref.(step.via), nil}

            step.via.kind == :process_manager ->
              {"issues", ref.(step.via), ref.(step.to), ref.(step.from)}

            true ->
              {"issues", ref.(step.via), ref.(step.to), nil}
          end

        [r] =
          for r <- d["relations"][type],
              r["from"] == from,
              r["to"] == to,
              on == nil or r["on"] == on,
              do: r

        assert o["relations"][r["id"]]["runs"] == step.runs, "#{inspect(c)}: #{r["id"]}"
        assert o["relations"][r["id"]]["untraversed"] == step.untraversed
      end

      numbered = for {rid, %{"of_runs" => _}} <- o["relations"], do: rid
      assert length(numbered) == length(steps), inspect(c)
    end
  end

  test "a relation two steps end at, and two relations one step ends at, get no numbers" do
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
          event :booked, "Booked"
          event :moved, "Moved"
          event :reminded, "Reminded"
        end

        policy :remind_on_change, "Remind on a change", handles: [:booked, :moved], issues: :remind

        process_manager :chase, "Chase" do
          correlate :visit_id
          starts_on :booked, issues: :remind
          on :booked, issues: :remind
        end
      """)

    d = Document.contract(model)
    o = Overlay.contract(model)
    id = &Document.id([&1, model.module, &2])

    shared = relation(d, "issues", id.(:policy, :remind_on_change), id.(:command, :remind))
    refute Map.has_key?(o["relations"], shared)

    for r <- d["relations"]["issues"],
        r["from"] == id.(:process_manager, :chase),
        do: refute(Map.has_key?(o["relations"], r["id"]))

    # The steps that do match one relation each still carry theirs.
    assert Map.has_key?(
             o["relations"],
             relation(d, "emits", id.(:command, :book), id.(:event, :booked))
           )
  end
end
