defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` documents — a contract's and a domain's graph of facts
  (batch 3) — and the declared shape of a process as data (batch 2), which the
  dashboard still draws. Every document of every fixture holds to the schema that
  ships in `priv/schema`, is JSON as it stands, says nothing from the log, joins on
  ids that resolve, holds every fact today's pictures draw, and is the same document,
  digest included, however many times it is built.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Graph.{Contract, Declared, Document}
  alias EhOsContract.{Model, Registry}

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp documents do
    contracts = Registry.contracts()

    for(c <- contracts, do: {c, Document.contract(c)}) ++
      for d <- Registry.domains(), do: {d, Document.domain(d, contracts)}
  end

  defp nodes(document), do: for({_kind, ns} <- document["nodes"], n <- ns, do: n)
  defp relations(document), do: for({_type, rs} <- document["relations"], r <- rs, do: r)

  defp relation(document, type, from, to),
    do: Enum.find(document["relations"][type], &(&1["from"] == from and &1["to"] == to))

  defp node(document, kind, id), do: Enum.find(document["nodes"][kind], &(&1["id"] == id))

  test "every document of every fixture holds to the schema" do
    for {module, document} <- documents() do
      case JSV.validate(document, @schema) do
        {:ok, _} -> :ok
        {:error, error} -> flunk("#{inspect(module)}: #{inspect(JSV.normalize_error(error))}")
      end
    end
  end

  test "the schema refuses the log, a look, an unknown kind or type and a missing key" do
    document = Document.contract(DispatchRig.Ledger)
    valid? = &match?({:ok, _}, JSV.validate(&1, @schema))

    first = fn group, key, f ->
      update_in(document, [group, key], fn [x | r] -> [f.(x) | r] end)
    end

    assert valid?.(document)
    refute valid?.(first.("nodes", "command", &Map.put(&1, "counts", [2, 1])))
    refute valid?.(first.("relations", "emits", &Map.put(&1, "line", "dotted")))
    refute valid?.(first.("relations", "emits", &Map.delete(&1, "id")))
    refute valid?.(first.("nodes", "event", &Map.put(&1, "label", nil)))
    refute valid?.(put_in(document, ["relations", "leads_to"], []))
    refute valid?.(put_in(document, ["nodes", "lane"], []))
    refute valid?.(update_in(document, ["relations"], &Map.delete(&1, "emits")))
    refute valid?.(Map.delete(document, "digest"))
  end

  test "a document is JSON as it stands, and its digest is of the rest of it" do
    for {module, document} <- documents() do
      assert document |> Jason.encode!() |> Jason.decode!() == document, inspect(module)
      assert document["digest"] == Document.digest(document), inspect(module)
    end
  end

  test "the same declarations give the same documents, digests included" do
    assert documents() == documents()
  end

  test "ids are unique in a document, and every relation and owner resolves in it" do
    owners = ~w(unit stage process process_manager of context subdomain contract)

    for {module, document} <- documents() do
      ids = Enum.map(nodes(document), & &1["id"]) ++ Enum.map(relations(document), & &1["id"])
      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      here = MapSet.new(nodes(document), & &1["id"])
      resolves? = &MapSet.member?(here, &1)

      for r <- relations(document), id <- [r["from"], r["to"]] do
        assert resolves?.(id), "#{inspect(module)}: relation #{r["id"]} ends at #{id}"
      end

      for n <- nodes(document), key <- owners, id = n[key], id != nil do
        assert resolves?.(id), "#{inspect(module)}: #{n["id"]}'s #{key} is #{id}"
      end

      # An id a relation holds besides its ends: the way in a manager acts on, the event
      # of a transition or a publication, the events between two contracts.
      for r <- relations(document),
          id <- [r["on"], r["event"] | for(e <- r["events"] || [], do: e["event"])],
          id != nil do
        assert resolves?.(id), "#{inspect(module)}: #{r["id"]} names #{id}"
      end

      if document["kind"] == "contract",
        do: assert(resolves?.(document["context"]), inspect(module))
    end
  end

  test "every node and edge today's pictures draw is a fact of the document" do
    contracts = Registry.contracts()

    for c <- contracts, do: assert(EhOsContract.GraphCoverage.contract(c) == [], inspect(c))

    for d <- Registry.domains(),
        do: assert(EhOsContract.GraphCoverage.domain(d, contracts) == [], inspect(d))

    # And the check is not empty: a document without a relation type, a node kind or a
    # group's owner the pictures draw fails it.
    cut = fn module, document, path ->
      EhOsContract.GraphCoverage.contract(module, put_in(document, path, []))
    end

    ledger = Document.contract(DispatchRig.Ledger)
    refute cut.(DispatchRig.Ledger, ledger, ["relations", "sets"]) == []

    refute cut.(LifecycleRig.Visits, Document.contract(LifecycleRig.Visits), ["nodes", "status"]) ==
             []

    unowned =
      update_in(ledger, ["nodes", "command"], fn [c | r] -> [Map.delete(c, "unit") | r] end)

    refute EhOsContract.GraphCoverage.contract(DispatchRig.Ledger, unowned) == []

    domain = Model.fetch(DispatchRig.Ledger).domain
    document = put_in(Document.domain(domain, contracts), ["relations", "consumed_by"], [])
    refute EhOsContract.GraphCoverage.domain(domain, contracts, document) == []
  end

  test "the schema names every node kind and relation type the engine builds, and no other" do
    schema = Document.schema_path() |> File.read!() |> Jason.decode!()

    for {kind, document} <- [contract: "contract_document", domain: "domain_document"] do
      %{nodes: nodes, relations: relations} = EhOsContract.Graph.Facts.kinds(kind)
      props = schema["$defs"][document]["properties"]

      assert Enum.sort(props["nodes"]["required"]) == Enum.sort(Enum.map(nodes, &to_string/1))

      assert Enum.sort(props["relations"]["required"]) ==
               Enum.sort(Enum.map(relations, &to_string/1))
    end
  end

  test "the log is not in a document, even where the contract has run" do
    # The schema closes every object, so a key of the overlay would fail it; this says
    # why, where it is read.
    for {_module, document} <- documents(), item <- nodes(document) ++ relations(document) do
      refute Enum.any?(~w(overlay counts runs), &Map.has_key?(item, &1))
    end
  end

  test "the digest moves with what is declared, and not with the order contracts are given in" do
    document = Document.contract(DispatchRig.Ledger)

    relabelled =
      update_in(document, ["nodes", "command"], fn [node | rest] ->
        [%{node | "label" => node["label"] <> "!"} | rest]
      end)

    refute Document.digest(relabelled) == document["digest"]

    contracts = Registry.contracts()

    for domain <- Registry.domains() do
      assert Document.domain(domain, Enum.reverse(contracts)) ==
               Document.domain(domain, contracts)
    end
  end

  describe "the facts of a contract" do
    test "a process manager's relations carry the way in they act on" do
      d = Document.contract(DispatchRig.Ledger)
      id = &Document.id([&1, DispatchRig.Ledger | List.wrap(&2)])
      pm = id.(:process_manager, :first_deposit_chase)
      due = id.(:timer, [:first_deposit_chase, :first_deposit_due])

      assert %{"on" => on, "phase" => "start"} = relation(d, "sets", pm, due)
      assert on == id.(:event, :account_opened)
      assert relation(d, "starts", on, pm)

      assert %{"on" => deposited, "phase" => "run"} = relation(d, "cancels", pm, due)
      assert relation(d, "handled_by", deposited, pm)
      assert relation(d, "ends", id.(:event, :account_flagged), pm)
      assert relation(d, "fires", due, id.(:command, :flag_account))
      assert %{"process_manager" => ^pm} = node(d, "timer", due)
    end

    test "a rule is its owner's, and a command outside its statuses is refused on one" do
      d = Document.contract(LifecycleRig.Visits)
      id = &Document.id([&1, LifecycleRig.Visits | List.wrap(&2)])
      admit = id.(:command, :admit_patient)
      rule = id.(:invariant, [:unit, :visit, :only_a_booked_visit])

      assert %{"of" => of} = node(d, "invariant", rule)
      assert of == id.(:unit, :visit)
      assert %{"outside_from" => true} = relation(d, "refused_on", admit, rule)
      assert relation(d, "allowed_in", admit, id.(:status, [:visit, :booked]))

      assert %{"event" => event} =
               relation(
                 d,
                 "transition",
                 id.(:status, [:visit, :booked]),
                 id.(:status, [:visit, :in_progress])
               )

      assert event == id.(:event, :patient_arrived)
      assert relation(d, "enters", id.(:event, :booked), id.(:status, [:visit, :booked]))
    end

    test "a received event is handled through the inbox and comes from a publication" do
      d = Document.contract(BusRig.Stock)
      model = Model.fetch(BusRig.Stock)
      event = Document.id([:event, BusRig.Stock, :order_placed])
      publication = Document.id([:publication, model.domain, "bus_rig_shop.order.placed.v1"])

      assert relation(d, "received_as", publication, event)

      assert [%{"via_inbox" => true} | _] =
               for(r <- d["relations"]["handled_by"], r["from"] == event, do: r)

      refute Map.has_key?(node(d, "event", event), "unit")
    end

    test "a manager's own timer may be a way in, during the run" do
      model =
        compile_contract("GraphFactsTimer", """
          process :visit, "Visit" do
            correlate :visit_id
          end

          aggregate :visit, "Visit" do
            identity :visit_id
            command :book, "Book", by: :reception, emits: :booked
            command :remind, "Remind", by: :reception, emits: :reminded
            event :booked, "Booked"
            event :reminded, "Reminded"
          end

          process_manager :chase, "Chase" do
            correlate :visit_id
            starts_on :booked, sets: :later
            on :later, issues: :remind, sets: :later
            timer :later, "Later", wait: {1, :day}
          end
        """)

      d = Document.contract(model)
      id = &Document.id([&1, model.module | List.wrap(&2)])
      pm = id.(:process_manager, :chase)
      later = id.(:timer, [:chase, :later])

      assert %{"on" => ^later, "phase" => "run"} =
               relation(d, "issues", pm, id.(:command, :remind))

      assert Enum.any?(d["relations"]["sets"], &(&1["on"] == later and &1["phase"] == "run"))
      refute Enum.any?(d["relations"]["handled_by"], &(&1["from"] == later))
    end

    test "what a contract names and its domain does not declare is a node by its name" do
      # `Clinic`, the domain `compile_contract/2` names, does not exist (v2 §8).
      model =
        compile_contract("GraphFactsNoDomain", """
          process :visit, "Visit" do
            correlate :visit_id
          end

          aggregate :visit, "Visit" do
            identity :visit_id
            command :book, "Book", by: :reception, emits: :booked
            event :booked, "Booked", depends_on: :registry
          end

          effect :notify, "Notify", handles: :booked, calls: :p1,
            idempotency: [key: :event_id, owner: :downstream]
        """)

      d = Document.contract(model)
      here = MapSet.new(nodes(d), & &1["id"])

      for r <- relations(d), id <- [r["from"], r["to"]], do: assert(MapSet.member?(here, id), id)

      assert %{"label" => "reception"} =
               node(d, "actor", Document.id([:actor, Clinic, :reception]))

      assert node(d, "external", Document.id([:external, Clinic, :registry]))
      assert node(d, "external", Document.id([:external, Clinic, :p1]))
    end

    test "a consumed event keeps its name here and says which sibling event it is" do
      model =
        compile_contract("GraphFactsRename", """
          consumes DispatchRig.Ledger, :account_opened, as: [account_opened: :opened]

          process :welcome, "Welcome" do
            correlate :account_id
            include :opened
          end
        """)

      d = Document.contract(model)
      here = Document.id([:event, model.module, :opened])

      assert %{"declared_as" => sibling, "included" => true} = node(d, "event", here)
      assert sibling == Document.id([:event, DispatchRig.Ledger, :account_opened])
      refute Enum.any?(nodes(d), &(&1["id"] == sibling))
    end
  end

  describe "the declared shape of a process" do
    test "its stages are groups in their order, the order an edge between them" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      stage = &Document.id([:stage, ProcessShapes.Promised, :handling, &1])
      model = Model.fetch(ProcessShapes.Promised)

      assert Enum.map(graph.groups, & &1.name) == Enum.map(model.process.stages, & &1.name)

      assert %{from: from, to: to, relation: :precedes} =
               Enum.find(graph.edges, &(&1.relation == :precedes))

      assert {from, to} == {stage.(:intake), stage.(:decision)}

      intake = Enum.find(graph.groups, &(&1.name == :intake))
      assert Document.id([:event, ProcessShapes.Promised, :request_received]) in intake.nodes
    end

    test "a promise is an edge with its window, and its or_else another" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      event = &Document.id([:event, ProcessShapes.Promised, &1])

      assert %{within: %{amount: 2, unit: :day}, promise: promise} =
               Enum.find(graph.edges, &(&1.relation == :eventually))

      assert Enum.find(graph.edges, &(&1.relation == :eventually)).to ==
               event.(:request_completed)

      assert %{from: from, to: to, promise: ^promise} =
               Enum.find(graph.edges, &(&1.relation == :or_else))

      assert {from, to} == {event.(:request_received), event.(:refusal_notified)}

      terminal = for %{kind: :event, terminal: true} = e <- graph.nodes, do: e.name
      assert Enum.sort(terminal) == [:refusal_notified, :request_completed]
    end

    test "an included event has the id it has on the contract's full graph" do
      declared = Declared.build(DispatchRig.Branch, :branch)
      full = Contract.build(DispatchRig.Branch)
      id = Document.id([:event, DispatchRig.Branch, :account_opened])

      assert Enum.any?(declared.nodes, &(&1.id == id))
      assert Enum.any?(full.nodes, &(&1.id == id))
    end

    test "an event's dependency is an edge to the domain's external" do
      graph = Declared.build(UniversalityGate.TreatmentEpisode, :treatment_episode)
      model = Model.fetch(UniversalityGate.TreatmentEpisode)
      external = Document.id([:external, model.domain, :payer_registry])

      assert %{label: "Payer registry: confirmation of eligibility for treatment"} =
               Enum.find(graph.nodes, &(&1.id == external))

      assert Enum.any?(graph.edges, &(&1.relation == :depends_on and &1.to == external))
    end

    test "a process the contract does not declare is refused" do
      assert_raise ArgumentError, ~r/declares no process :nope/, fn ->
        Declared.build(ProcessShapes.Promised, :nope)
      end
    end
  end
end
