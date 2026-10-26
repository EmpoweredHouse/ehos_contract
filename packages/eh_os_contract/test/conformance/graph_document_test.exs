defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` documents — a contract's and a domain's graph of facts.
  Every document of every fixture holds to the schema that ships in `priv/schema`, is
  JSON as it stands, joins on ids that resolve, and is written with every object's
  keys in order, so its bytes depend on its content alone. That it says nothing from the log is
  `GraphOverlayTest`'s, which writes the log and builds the document again.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Graph.Document
  alias EhOsContract.{Model, Registry}

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  # A contract that consumes the ledger's event, as `DispatchRig.Branch` does, and has a
  # scenario with a dated given. Invented.
  defmodule Openings do
    @moduledoc false
    use EhOsContract.Contract,
      domain: DispatchRig.Domain,
      context: :ledger,
      id: "dispatch_rig.graph_openings"

    consumes DispatchRig.Ledger, :account_opened

    aggregate :branch_note, "Branch note" do
      identity :branch_id
      command :note_branch, "Note a branch", by: :auditor, emits: :branch_noted
      event :branch_noted, "Branch noted"
    end

    scenario "a branch is noted again" do
      actor :auditor
      given :branch_noted, %{branch_id: "b-1"}, at: "2026-09-07T09:00:00+02:00"
      command :note_branch, %{branch_id: "b-1"}
      expect :branch_noted, %{branch_id: "b-1"}
    end
  end

  # Plan DD, L3 (#286): fields that identify a unit, this contract's own and
  # `Openings`'s. Invented, as `Openings` is.
  defmodule Notes do
    @moduledoc false
    use EhOsContract.Contract,
      domain: DispatchRig.Domain,
      context: :ledger,
      id: "dispatch_rig.graph_notes"

    aggregate :note, "Note" do
      identity :note_id

      command :write_note, "Write a note", by: :auditor, emits: :note_written do
        field :previous_id, {:id, :note}, optional: true
        field :branch_id, {:id, :branch_note}
      end

      event :note_written, "Note written"
    end
  end

  # The registry's, and this file's, one of them with fields that identify units; and
  # every process module's.
  defp documents do
    contracts = Registry.contracts() ++ [Openings, Notes]
    modules = contracts ++ Registry.processes()

    for(c <- contracts, do: {c, Document.contract(c)}) ++
      for(p <- Registry.processes(), do: {p, Document.process(p)}) ++
      for d <- Registry.domains(), do: {d, Document.domain(d, modules)}
  end

  # The fields naming an owner, by kind: a value's `unit` is a unit of measure.
  @owners %{
    "stage" => ~w(process),
    "promise" => ~w(process),
    "status" => ~w(unit),
    "invariant" => ~w(of),
    "constraint" => ~w(of),
    "command" => ~w(unit),
    "event" => ~w(unit stage contract),
    "timer" => ~w(process_manager),
    "actor" => ~w(context),
    "value" => ~w(context),
    "entity" => ~w(context),
    "context" => ~w(subdomain),
    "contract" => ~w(context)
  }

  defp nodes(document), do: for({_kind, ns} <- document["nodes"], n <- ns, do: n)

  defp scenarios(document),
    do: for({_kind, ss} <- document["scenarios"] || %{}, s <- ss, do: s)

  # Every field of every node, with its kind, wherever the node keeps it.
  defp fields(document) do
    for {kind, ns} <- document["nodes"],
        n <- ns,
        key <- ~w(fields state params),
        is_list(n[key]),
        f <- n[key],
        do: {kind, f}
  end

  # The node ids a scenario names besides its target.
  defp scenario_nodes(s) do
    happened = for key <- ~w(given expect), e <- s[key] || [], do: e["event"]
    issued = for i <- s["issues"] || [], do: i["command"]
    trigger = s["trigger"] || %{}

    # A recording is refused on a value's invariant, which names the value (issue #430).
    rejected =
      case s["rejected"] do
        %{"value" => value} -> value
        rule -> rule
      end

    happened ++
      issued ++
      Enum.reject(
        [
          s["actor"],
          rejected,
          s["command"]["command"],
          s["record"]["event"],
          s["event"]["event"],
          trigger["event"],
          trigger["timer"]
        ],
        &is_nil/1
      ) ++ (s["sets"] || []) ++ (s["cancels"] || []) ++ (s["illustrates"] || [])
  end

  defp relations(document), do: for({_type, rs} <- document["relations"], r <- rs, do: r)

  defp relation(document, type, from, to, attrs \\ %{}) do
    Enum.find(document["relations"][type], fn r ->
      r["from"] == from and r["to"] == to and Enum.all?(attrs, fn {k, v} -> r[k] == v end)
    end)
  end

  defp node(document, kind, id), do: Enum.find(document["nodes"][kind], &(&1["id"] == id))

  defp node_named(document, kind, name),
    do: Enum.find(document["nodes"][kind], &(&1["name"] == name))

  # What a contract declares is scoped to its `id:` (plan DD, ID3, #173).
  defp scope(contract), do: Model.fetch(contract).id

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
    refute valid?.(first.("nodes", "event", &Map.delete(&1, "label")))
    refute valid?.(first.("nodes", "command", &Map.put(&1, "fields", [%{"name" => "x"}])))
    refute valid?.(first.("scenarios", "unit", &Map.put(&1, "count", 2)))
    refute valid?.(update_in(document, ["scenarios"], &Map.delete(&1, "policy")))
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

  test "a document's bytes depend on its content alone: every object's keys in order" do
    document = Document.contract(DispatchRig.Ledger)
    encoded = Document.encode(document)

    assert Jason.decode!(encoded) == document

    # A map of more than 32 keys, which Erlang keeps unordered, has them in order,
    # however deep in lists and maps it sits.
    large = Map.new(for i <- 1..40, do: {"k#{String.pad_leading("#{i}", 2, "0")}", i})
    keys = for i <- 1..40, do: ~s("k#{String.pad_leading("#{i}", 2, "0")}":#{i})
    in_order = "{" <> Enum.join(keys, ",") <> "}"
    assert Document.encode(large) == in_order
    assert Document.encode(%{"a" => [%{"b" => large}]}) == ~s({"a":[{"b":#{in_order}}]})

    assert Document.encode(%{"b" => 1, "a" => %{"d" => 1, "c" => 2}}) ==
             ~s({"a":{"c":2,"d":1},"b":1})
  end

  # Every object of every real document, at every depth, is written with its keys in
  # order — read back in the order written, not through a map, which would hide it.
  test "every document of every fixture is written with every object's keys in order" do
    for {module, document} <- documents() do
      encoded = Document.encode(document)
      assert keys_in_order?(Jason.decode!(encoded, objects: :ordered_objects)), inspect(module)
      assert Jason.decode!(encoded) == document, inspect(module)
    end
  end

  defp keys_in_order?(%Jason.OrderedObject{values: values}) do
    keys = Enum.map(values, &elem(&1, 0))
    keys == Enum.sort(keys) and Enum.all?(values, &keys_in_order?(elem(&1, 1)))
  end

  defp keys_in_order?(list) when is_list(list), do: Enum.all?(list, &keys_in_order?/1)
  defp keys_in_order?(_), do: true

  test "ids are unique in a document, and every relation, owner, field and scenario resolves in it" do
    for {module, document} <- documents() do
      ids =
        Enum.map(nodes(document), & &1["id"]) ++
          Enum.map(relations(document), & &1["id"]) ++
          Enum.map(scenarios(document), & &1["id"])

      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      here = MapSet.new(nodes(document), & &1["id"])
      resolves? = &MapSet.member?(here, &1)

      for r <- relations(document), id <- [r["from"], r["to"]] do
        assert resolves?.(id), "#{inspect(module)}: relation #{r["id"]} ends at #{id}"
      end

      for {kind, ns} <- document["nodes"],
          n <- ns,
          key <- Map.get(@owners, kind, []),
          id = n[key] do
        assert resolves?.(id), "#{inspect(module)}: #{n["id"]}'s #{key} is #{id}"
      end

      for {kind, f} <- fields(document),
          key <- ~w(subject value refers_to issued_by),
          id = f[key] do
        assert resolves?.(id), "#{inspect(module)}: a field of a #{kind} names #{id}"
      end

      relation_ids = MapSet.new(relations(document), & &1["id"])

      for s <- scenarios(document) do
        for id <- [s["target"] | scenario_nodes(s)],
            do: assert(resolves?.(id), "#{inspect(module)}: #{s["id"]} names #{id}")

        for id <- s["covers"],
            do:
              assert(
                MapSet.member?(relation_ids, id),
                "#{inspect(module)}: #{s["id"]} covers #{id}"
              )
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

      if document["kind"] == "process",
        do: assert(resolves?.(Document.id([:process, document["process"]])), inspect(module))
    end
  end

  test "the schema names every node kind and relation type the engine builds, and no other" do
    schema = Document.schema_path() |> File.read!() |> Jason.decode!()

    for {kind, document} <- [
          contract: "contract_document",
          process: "process_document",
          domain: "domain_document"
        ] do
      %{nodes: nodes, relations: relations} = EhOsContract.Graph.Facts.kinds(kind)
      props = schema["$defs"][document]["properties"]

      assert Enum.sort(props["nodes"]["required"]) == Enum.sort(Enum.map(nodes, &to_string/1))

      assert Enum.sort(props["relations"]["required"]) ==
               Enum.sort(Enum.map(relations, &to_string/1))
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
    # The user's decision B (7 October): ids follow the contract's `id:`, as the log and
    # the dashboard's APIs name it, so a module moved under the same id moves no id.
    test "the contract is named by its id, and what it declares is scoped to it" do
      d = Document.contract(DispatchRig.Ledger)

      assert %{"contract" => "dispatch_rig.ledger", "module" => "DispatchRig.Ledger"} = d
      assert node(d, "command", "command:dispatch_rig.ledger:withdraw")
      assert node(d, "actor", "actor:DispatchRig.Domain:clerk")
    end

    # Plan DD, C1 (#304): what a unit's page says, its node says too.
    test "a unit none of whose commands can be refused is marked as recording only" do
      openings = Document.contract(Openings)
      branch = node(openings, "unit", "unit:dispatch_rig.graph_openings:branch_note")
      assert branch["records_only"] == true
      assert {:ok, _} = JSV.validate(openings, @schema)

      account =
        node(Document.contract(DispatchRig.Ledger), "unit", "unit:dispatch_rig.ledger:account")

      refute Map.has_key?(account, "records_only")
    end

    # Issue #430: a recording has no command, which a unit's scenario always carries, so
    # it is a group of its own; it is about its unit and covers the actor's arrow.
    test "a recording's scenario is about its unit, and is refused on a value's invariant" do
      d = Document.contract(ValueRig.Till)
      assert {:ok, _} = JSV.validate(d, @schema)

      [counted, nothing] = d["scenarios"]["record"]

      record =
        relation(d, "may_record", "actor:ValueRig.Domain:counter", "event:value_rig.till:counted")

      assert %{
               "target" => "unit:value_rig.till:till",
               "actor" => "actor:ValueRig.Domain:counter",
               "record" => %{
                 "event" => "event:value_rig.till:counted",
                 "data" => %{"amount" => 250}
               },
               "expect" => [%{"event" => "event:value_rig.till:counted"}],
               "covers" => [covered]
             } = counted

      assert covered == record["id"]

      assert nothing["rejected"] == %{
               "value" => "value:ValueRig.Domain:amount",
               "invariant" => "positive"
             }
    end

    # Issue #458: a command refused for its data names the value's invariant, as a
    # recording does, beside `rejected`, which an older reader takes for a rule's id. It
    # covers no arrow to a rule: none refuses it.
    test "a command refused on a value's invariant names the value, and no rule" do
      d = Document.contract(ValueRig.Till)
      assert {:ok, _} = JSV.validate(d, @schema)
      scenarios = Map.new(d["scenarios"]["unit"], &{&1["description"], &1})

      no_day = scenarios["a drawer is not opened for a shift that is no day"]

      assert no_day["rejected_on_value"] == %{
               "value" => "value:ValueRig.Domain:shift",
               "invariant" => "named_by_day"
             }

      refute Map.has_key?(no_day, "rejected")
      assert no_day["covers"] == []

      assert scenarios["nothing is paid in"]["rejected_on_value"] == %{
               "value" => "value:ValueRig.Domain:amount",
               "invariant" => "positive"
             }

      refute Map.has_key?(
               scenarios["a drawer is opened for a shift named by its day"],
               "rejected_on_value"
             )
    end

    # The review of #458: two values declare an invariant of the same name, and the data
    # breaks the later field's, so the graph names that field's value, as dispatch refuses.
    test "a command refused for its data names the value the data breaks" do
      d = Document.contract(TipRig.Till)
      assert {:ok, _} = JSV.validate(d, @schema)

      named =
        for s <- d["scenarios"]["unit"],
            s["rejected_on_value"],
            into: %{},
            do: {s["description"], s["rejected_on_value"]["value"]}

      assert named == %{
               "a tip of nothing is not paid in" => "value:TipRig.Domain:tip",
               "a payment with a tip of nothing is not settled" => "value:TipRig.Domain:tip",
               "an amount of nothing is not paid in" => "value:TipRig.Domain:amount"
             }

      [counted] =
        for s <- d["scenarios"]["record"], s["rejected"], do: s["rejected"]["value"]

      assert counted == "value:TipRig.Domain:tip"

      # Without the domain's checks, the declarations alone decide: the first declared.
      fields = Enum.find(Model.fetch(TipRig.Till).commands, &(&1.name == :pay_in)).fields
      values = EhOsContract.Codec.values(TipRig.Domain)

      assert EhOsContract.Contract.Links.Scenarios.refusing_value(
               fields,
               :positive,
               values,
               %{amount: 250, tip: 0},
               nil
             ) == :amount
    end

    test "a process manager's relations carry the way in they act on" do
      d = Document.contract(DispatchRig.Ledger)
      id = &Document.id([&1, scope(DispatchRig.Ledger) | List.wrap(&2)])
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
      id = &Document.id([&1, scope(LifecycleRig.Visits) | List.wrap(&2)])
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
      event = Document.id([:event, scope(BusRig.Stock), :order_placed])
      publication = Document.id([:publication, model.domain, "bus_rig_shop.order.placed.v1"])

      assert relation(d, "received_as", publication, event)

      assert [%{"via_inbox" => true} | _] =
               for(r <- d["relations"]["handled_by"], r["from"] == event, do: r)

      refute Map.has_key?(node(d, "event", event), "unit")
    end

    # Two shapes the compiler accepts that put two relations of one type between the
    # same two nodes: a DCB consulting one event twice, and one publication received
    # under two names (the domain's `subscribed_by`). What tells them apart is in the id.
    test "two relations of one type between the same two nodes have two ids" do
      compile("""
      defmodule EhOsContract.GraphDocumentTest.Twice do
        use EhOsContract.Contract,
          domain: BusRig.Warehouse,
          context: :stock,
          id: "bus_rig_warehouse.twice"

        subscribe "bus_rig_shop.order.placed.v1", as: :placed do
          field :order_id, :id
        end

        subscribe "bus_rig_shop.order.placed.v1", as: :placed_again do
          field :order_id, :id
          field :total, :integer
        end

        aggregate :reservation, "Reservation" do
          identity :order_id

          command :reserve, "Reserve", by: :keeper, emits: :reserved do
            field :total, :integer
          end

          event :reserved, "Reserved" do
            field :total, :integer
          end
        end

        dcb :limit, "Limit" do
          identity :order_id
          consults :reserved, match: :order_id
          consults :reserved, where: "a reservation of the same week"
          consults :reserved, where: "a reservation of the same keeper"
          command :hold, "Hold", by: :keeper, emits: :held
          event :held, "Held"
        end

        policy :reserve_on_order, "Reserve on an order",
          handles: [:placed, :placed_again],
          issues: :reserve
      end
      """)

      module = EhOsContract.GraphDocumentTest.Twice
      d = Document.contract(module)
      domain = Document.domain(BusRig.Warehouse, [module])

      consulted =
        for r <- d["relations"]["consulted_by"],
            r["to"] == Document.id([:unit, scope(module), :limit]),
            do: r["id"]

      assert length(consulted) == 3 and consulted == Enum.uniq(consulted)

      subscribed =
        for r <- domain["relations"]["subscribed_by"], r["to"] =~ "twice", do: r

      assert ["placed", "placed_again"] == Enum.sort(Enum.map(subscribed, & &1["as"]))
      assert subscribed |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == 2

      # One grant takes the publication, under either name.
      [{grant, %{kind: :subscribe}}] =
        Enum.filter(Model.capabilities(module), &match?({_, %{kind: :subscribe}}, &1))

      assert Enum.all?(subscribed, &(&1["capability"] == grant))

      for as <- [:placed, :placed_again],
          do:
            assert(
              %{"capability" => ^grant} =
                node(d, "event", Document.id([:event, scope(module), as]))
            )

      for document <- [d, domain] do
        assert {:ok, _} = JSV.validate(document, @schema)
        ids = Enum.map(relations(document), & &1["id"])
        assert ids == Enum.uniq(ids)
      end
    end

    test "a manager's own timer may be a way in, during the run" do
      model =
        compile_contract("GraphFactsTimer", """
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
      id = &Document.id([&1, model.id | List.wrap(&2)])
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

      assert %{"name" => "reception", "label" => nil} =
               node(d, "actor", Document.id([:actor, Clinic, :reception]))

      assert node(d, "external", Document.id([:external, Clinic, :registry]))
      assert node(d, "external", Document.id([:external, Clinic, :p1]))
    end

    test "a consumed event keeps its name here and says which sibling event it is" do
      model =
        compile_contract("GraphFactsRename", """
          consumes DispatchRig.Ledger, :account_opened, as: [account_opened: :opened]
        """)

      d = Document.contract(model)
      here = Document.id([:event, model.id, :opened])

      assert %{"declared_as" => sibling, "declared_in" => contract} = node(d, "event", here)
      assert sibling == Document.id([:event, scope(DispatchRig.Ledger), :account_opened])
      refute Enum.any?(nodes(d), &(&1["id"] == sibling))

      # Plan DD, G1 (#297): the contract it is declared in, said rather than read out of
      # the id; the contract's own events say none.
      assert contract == scope(DispatchRig.Ledger)

      for %{"unit" => _} = own <- d["nodes"]["event"],
          do: refute(Map.has_key?(own, "declared_in"), own["id"])
    end
  end

  # A domain and a contract with what a panel shows: personal data, a value, an
  # entity its issuer gives, an inline enum, capabilities.
  setup_all do
    compile(
      """
      defmodule EhOsContract.GraphDocumentTest.Clinic do
        use EhOsContract.Domain, name: :graph_clinic, language: :en

        subdomain :core, "Core", type: :core
        context :visits, "Visits", subdomain: :core

        actor :reception, :human, "Reception" do
          responsibility :day, "Closes the day", source: "W-1"
        end

        actor :feed, :system, "Registry feed", backed_by: :registry
        subject :patient, "Patient"

        external :registry, "Registry",
          direction: :bidirectional,
          expected_latency: {5, :second} do
          operation :look_up, "Look up"
        end

        value :method, {:enum, [card: "Card", cash: "Cash"]}

        value :money, :integer, label: "Money", unit: :cents
        value :fee, :money

        value :contact, label: "Contact" do
          field :patient_id, :id, subject: :patient
          field :phone, :string, personal: :patient_id

          invariant :reachable, "A contact can be reached",
            satisfied_by: [%{patient_id: "p-1", phone: "+48-555-0199"}],
            violated_by: [%{patient_id: "p-1", phone: "+48-555-0100"}]
        end

        value :code, :string, label: "Code" do
          invariant :short, "A code is short", satisfied_by: ["A1"], violated_by: ["TOO-LONG"]
        end

        entity :service, "Service", context: :visits, identity: :service_id, issued_by: :registry do
        end
      end

      defmodule EhOsContract.GraphDocumentTest.Visits do
        use EhOsContract.Contract,
          domain: EhOsContract.GraphDocumentTest.Clinic,
          context: :visits,
          id: "graph_clinic.visits"

        aggregate :visit, "Visit" do
          identity :visit_id

          command :pay, "Pay", by: :reception, emits: :paid do
            field :patient_id, :id, subject: :patient
            field :name, :string, personal: :patient_id
            field :method, :method
            field :service_id, {:id, :service}
            field :kind, {:enum, [:walk_in, booked: "Booked"]}
            field :code, :code, optional: true
            field :fee, :fee, optional: true
          end

          state do
            field :kind, {:enum, [:walk_in, booked: "Booked"]}, default: :booked
            field :patient_id, :id, subject: :patient
            field :nickname, :string, personal: :patient_id, default: "Secret Default"
          end

          event :paid, "Paid", recorded_by: :reception do
            field :patient_id, :id, subject: :patient
            field :name, :string, personal: :patient_id
            field :method, :method
          end
        end

        domain_service :lookup, "Lookup" do
          function :service_for, "The service a contact books" do
            argument :contact, :contact
            returns {:id, :service}

            rule :first, "The first service",
              examples: [{[%{patient_id: "p-1", phone: "+48-555-0177"}], "s-1"}]
          end
        end

        scenario "a patient pays" do
          command :pay, %{
            patient_id: "p-1",
            name: "Ada Example",
            method: :card,
            service_id: "s-1",
            kind: :booked
          }
          expect :paid, %{patient_id: "p-1", name: "Ada Example", method: :card}
        end
      end
      """,
      "graph_clinic.ex"
    )

    :ok
  end

  describe "what a panel shows" do
    setup do
      %{
        d: Document.contract(EhOsContract.GraphDocumentTest.Visits),
        id: &Document.id([&1, scope(EhOsContract.GraphDocumentTest.Visits) | List.wrap(&2)]),
        domain: &Document.id([&1, EhOsContract.GraphDocumentTest.Clinic, &2])
      }
    end

    test "a field says what it is, in one shape, with the domain's declarations as ids",
         %{d: d, id: id, domain: domain} do
      %{"fields" => fields, "capability" => "graph_clinic.pay"} =
        node(d, "command", id.(:command, :pay))

      by_name = Map.new(fields, &{&1["name"], &1})

      assert by_name["patient_id"] == %{
               "name" => "patient_id",
               "label" => nil,
               "type" => "id",
               "required" => true,
               "subject" => domain.(:subject, :patient)
             }

      assert %{"personal_of" => "patient_id"} = by_name["name"]
      refute Map.has_key?(by_name["name"], "subject")
      assert %{"type" => "method", "value" => method} = by_name["method"]
      assert method == domain.(:value, :method)

      # The entity's identity is issued by the registry, so a field naming it is too.
      assert %{"refers_to" => service, "issued_by" => registry} = by_name["service_id"]
      assert {service, registry} == {domain.(:entity, :service), domain.(:external, :registry)}

      kind = %{
        "type" => %{
          "enum" => [
            %{"value" => "walk_in", "label" => nil},
            %{"value" => "booked", "label" => "Booked"}
          ]
        }
      }

      assert Map.take(by_name["kind"], ["type"]) == kind
      refute Map.has_key?(by_name["kind"], "default")

      assert %{"state" => [_identity, %{"name" => "kind", "default" => "booked"} | _]} =
               node(d, "unit", id.(:unit, :visit))

      # A value typed as another value names it, and that value is in the document.
      assert %{"type" => "fee", "value" => fee} = by_name["fee"]
      assert %{"type" => "money", "value" => money} = node(d, "value", fee)
      assert %{"type" => "integer", "unit" => "cents"} = node(d, "value", money)

      # A function returning an entity's id says so, as a field would.
      assert %{"functions" => [%{"returns" => returns, "arguments" => [argument]}]} =
               node(d, "domain_service", id.(:domain_service, :lookup))

      assert returns == %{
               "type" => "id",
               "required" => true,
               "refers_to" => domain.(:entity, :service),
               "issued_by" => domain.(:external, :registry)
             }

      assert argument["value"] == domain.(:value, :contact)

      assert %{"required" => false} = by_name["code"]

      assert %{"capability" => "graph_clinic.paid"} = node(d, "event", id.(:event, :paid))
    end

    test "the domain's declarations a contract names carry their content", %{d: d, domain: domain} do
      assert %{
               "actor_kind" => "human",
               "role" => "graph_clinic.reception",
               "responsibilities" => [%{"name" => "day", "label" => "Closes the day"}]
             } = node(d, "actor", domain.(:actor, :reception))

      assert %{
               "direction" => "bidirectional",
               "expected_latency" => %{"amount" => 5, "unit" => "second"},
               "operations" => [%{"name" => "look_up", "label" => "Look up", "source" => nil}]
             } = node(d, "external", domain.(:external, :registry))

      assert %{
               "label" => nil,
               "type" => %{"enum" => [%{"value" => "card", "label" => "Card"} | _]}
             } = node(d, "value", domain.(:value, :method))

      assert %{
               "type" => "string",
               "invariants" => [%{"satisfied_by" => ["A1"], "violated_by" => ["TOO-LONG"]}]
             } = node(d, "value", domain.(:value, :code))

      assert %{"identity" => "service_id", "fields" => [%{"issued_by" => _}]} =
               node(d, "entity", domain.(:entity, :service))
    end

    test "a field says what keeps its value about a person, where something does" do
      d = Document.contract(ShreddingRig.Members)

      fields = fn kind, name ->
        Map.new(node_named(d, kind, name)["fields"], &{&1["name"], &1})
      end

      # An event's personal data is sealed in the log, and its pointer stays in the clear.
      joined = fields.("event", "joined")
      assert joined["name"]["kept"] == "log_sealed"
      assert joined["member_id"]["kept"] == "log_clear"
      refute Map.has_key?(joined["plan"], "kept")

      # A read model's personal data is in its rows, forgotten on erasure; its pointer
      # says nothing more.
      members = fields.("read_model", "members")
      assert members["name"]["kept"] == "rows_forgotten"
      refute Map.has_key?(members["member_id"], "kept")

      # A command's and a state's keep nothing of it.
      visits = Document.contract(EhOsContract.GraphDocumentTest.Visits)
      pay = Map.new(node_named(visits, "command", "pay")["fields"], &{&1["name"], &1})
      refute Map.has_key?(pay["name"], "kept")
      refute Map.has_key?(pay["patient_id"], "kept")

      for f <- node_named(visits, "unit", "visit")["state"],
          do: refute(Map.has_key?(f, "kept"), f["name"])
    end

    test "no personal value is in a document, in a scenario or anywhere else", %{d: d} do
      domain =
        Document.domain(EhOsContract.GraphDocumentTest.Clinic, [
          EhOsContract.GraphDocumentTest.Visits
        ])

      # A scenario's data, a state's default, a domain service's rule example and a
      # value's invariant examples, in both documents.
      personal = ["Ada Example", "Secret Default", "+48-555-0177", "+48-555-0199", "+48-555-0100"]

      for document <- [d, domain], value <- personal do
        refute Jason.encode!(document) =~ value
      end

      # And what is not personal is still there.
      assert Jason.encode!(d) =~ "s-1"
      assert Jason.encode!(domain) =~ "p-1"

      assert [%{"command" => %{"data" => %{"name" => nil, "patient_id" => "p-1"}}}] =
               d["scenarios"]["unit"]
    end

    test "a domain's actor says what its role may do, by contract", %{domain: domain} do
      d =
        Document.domain(EhOsContract.GraphDocumentTest.Clinic, [
          EhOsContract.GraphDocumentTest.Visits
        ])

      contract = Document.id([:contract, scope(EhOsContract.GraphDocumentTest.Visits)])
      id = &Document.id([&1, scope(EhOsContract.GraphDocumentTest.Visits), &2])

      assert %{"capabilities" => capabilities} = node(d, "actor", domain.(:actor, :reception))

      assert Enum.sort(capabilities) ==
               Enum.sort([
                 %{
                   "capability" => "graph_clinic.paid",
                   "kind" => "record",
                   "contract" => contract,
                   "declaration" => id.(:event, :paid)
                 },
                 %{
                   "capability" => "graph_clinic.pay",
                   "kind" => "command",
                   "contract" => contract,
                   "declaration" => id.(:command, :pay)
                 }
               ])

      assert %{"capabilities" => []} = node(d, "actor", domain.(:actor, :feed))

      assert %{
               "name" => "graph_clinic.visits",
               "module" => "EhOsContract.GraphDocumentTest.Visits",
               "label" => nil
             } = node(d, "contract", contract)

      # A contract declares no process, so its node names none.
      refute Map.has_key?(node(d, "contract", contract), "process")
      refute Map.has_key?(node(d, "contract", contract), "correlate")
    end
  end

  # Plan DD, L3 (#286).
  test "a field identifying the contract's own unit names its node; one of a sibling's names none" do
    d = Document.contract(Notes)
    command = node(d, "command", Document.id([:command, scope(Notes), :write_note]))
    by_name = Map.new(command["fields"], &{&1["name"], &1})

    assert by_name["previous_id"]["refers_to"] == Document.id([:unit, scope(Notes), :note])
    assert node(d, "unit", by_name["previous_id"]["refers_to"])
    refute Map.has_key?(by_name["branch_id"], "refers_to")

    # Neither unit is taken for an entity the domain does not declare.
    names = for e <- d["nodes"]["entity"], do: e["name"]
    refute "note" in names
    refute "branch_note" in names
  end

  # Plan DD, L3 (#286): the domain's document draws what one contract's cannot.
  test "a domain draws a contract keeping a sibling's unit's number, once per pair" do
    d = Document.domain(DispatchRig.Domain, Registry.contracts() ++ [Openings, Notes])

    contract = &Document.id([:contract, scope(&1)])

    assert [relation] =
             for(r <- d["relations"]["refers_to"], r["from"] == contract.(Notes), do: r)

    assert relation["to"] == contract.(Openings)
    assert relation["units"] == ["branch_note"]

    # Its own unit is no sibling's, and a contract without such a field has none.
    refute Enum.any?(d["relations"]["refers_to"], &(&1["to"] == &1["from"]))
    assert Document.domain(DispatchRig.Domain, [Openings])["relations"]["refers_to"] == []
  end

  # Plan DD, L3 (#286): a reference is a declared field's, never a key of example data.
  test "a key named refers_to in a scenario's data refers to nothing" do
    model = Model.fetch(Openings)
    [scenario | rest] = model.scenarios
    scenario = put_in(scenario, [Access.key(:given), Access.at(0), :data], %{refers_to: :note})

    assert EhOsContract.References.in_model(%{model | scenarios: [scenario | rest]}) == []
    assert EhOsContract.References.in_model(Model.fetch(Notes)) == [:note, :branch_note]
  end

  describe "a node's content is its declaration's" do
    # Against the model, for every fixture: what a panel shows of each kind, as data.
    test "reactions, timers, queries, commands, events, units and statuses" do
      for c <- Registry.contracts() do
        model = Model.fetch(c)
        d = Document.contract(model)
        id = &Document.id([&1, model.id | List.wrap(&2)])
        json = &Model.json_data/1
        put = &if(&2 in [nil, false], do: &1, else: Map.put(&1, &3, json.(&2)))

        for {kind, declarations} <- [
              policy: model.policies,
              effect: model.effects,
              process_manager: model.process_managers
            ],
            r <- declarations do
          n = node(d, to_string(kind), id.(kind, r.name))
          assert n["delivery"] == json.(r.delivery)
          assert n["idempotency"] == json.(r.idempotency)
        end

        for pm <- model.process_managers, t <- pm.timers do
          n = node(d, "timer", id.(:timer, [pm.name, t.name]))
          assert Map.take(n, ~w(wait at)) == %{} |> put.(t.wait, "wait") |> put.(t.at, "at")
        end

        for q <- model.queries do
          n = node(d, "query", id.(:query, q.name))
          assert n["returns"] == json.(q.returns)
          assert n["scope"] == json.(q.scope)
          assert Enum.map(n["params"], & &1["name"]) == Enum.map(q.params, &to_string(&1.name))
        end

        for cmd <- model.commands do
          n = node(d, "command", id.(:command, cmd.name))
          assert n["scope"] == json.(cmd[:scope])
          assert n["creates"] == cmd[:creates]
          assert Enum.map(n["fields"], & &1["name"]) == Enum.map(cmd.fields, &to_string(&1.name))
        end

        for e <- model.events do
          n = node(d, "event", id.(:event, e.name))
          assert {n["type"], n["schema_version"]} == {e.type, e.schema_version}
        end

        for u <- model.units do
          n = node(d, "unit", id.(:unit, u.name))
          assert {n["unit_kind"], n["identity"]} == {json.(u.kind), json.(u.identity)}
          assert n["generated"] == json.(u[:generated])

          for s <- (u[:lifecycle] && u.lifecycle.statuses) || [],
              do:
                assert(
                  node(d, "status", id.(:status, [u.name, s.name]))["final"] == (s.final || nil)
                )
        end
      end
    end

    test "a received event carries the application's grant to take it" do
      d = Document.contract(BusRig.Stock)

      [{grant, %{kind: :subscribe}}] =
        Enum.filter(Model.capabilities(BusRig.Stock), &match?({_, %{kind: :subscribe}}, &1))

      assert %{"capability" => ^grant} =
               node(d, "event", Document.id([:event, scope(BusRig.Stock), :order_placed]))
    end

    test "a publication has no words of its own" do
      d = Document.contract(BusRig.Stock)
      assert [_ | _] = d["nodes"]["publication"]
      assert Enum.all?(d["nodes"]["publication"], &(&1["label"] == nil))
    end
  end

  describe "labels" do
    test "a node's label is the client's words or nil" do
      for {_module, document} <- documents(), n <- nodes(document), n["label"] != nil do
        assert is_binary(n["label"])
      end
    end
  end

  describe "scenarios" do
    test "a unit's covers the arrows to what it expects, or to the rule it is refused on" do
      d = Document.contract(DispatchRig.Ledger)
      id = &Document.id([&1, scope(DispatchRig.Ledger) | List.wrap(&2)])
      withdraw = id.(:command, :withdraw)
      rule = id.(:invariant, [:unit, :account, :balance_never_negative])
      by = &Enum.find(d["scenarios"]["unit"], fn s -> s["description"] == &1 end)

      assert %{"rejected" => ^rule, "covers" => [covered], "target" => target} =
               by.("a withdrawal beyond the balance is refused")

      assert covered == relation(d, "refused_on", withdraw, rule)["id"]
      assert target == id.(:unit, :account)

      assert %{"covers" => [emits]} = by.("a withdrawal within the balance goes through")
      assert emits == relation(d, "emits", withdraw, id.(:event, :withdrawn))["id"]
    end

    test "a process manager's starts its run only on a starting event with no run before it" do
      model =
        compile_contract("GraphFactsChase", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :book, "Book", by: :reception, emits: :booked
            command :remind, "Remind", by: :reception, emits: :reminded
            command :close, "Close", by: :reception, emits: :closed
            event :booked, "Booked"
            event :reminded, "Reminded"
            event :closed, "Closed"
          end

          process_manager :chase, "Chase" do
            correlate :visit_id
            starts_on :booked, sets: :later
            on :booked, issues: :remind
            on :reminded, cancels: :later
            ends_on :closed
            timer :later, "Later", wait: {1, :day}, issues: :remind
          end

          scenario "a booking starts the chase" do
            on :booked, %{visit_id: "v-1"}
            sets :later
          end

          scenario "a second booking arrives in the run" do
            given :booked, %{visit_id: "v-1"}
            on :booked, %{visit_id: "v-1"}
            issues :remind, %{visit_id: "v-1"}
          end

          scenario "the reminder is due" do
            given :booked, %{visit_id: "v-1"}
            on :later
            issues :remind, %{visit_id: "v-1"}
          end

          scenario "a reminder cancels the timer" do
            given :booked, %{visit_id: "v-1"}
            on :reminded, %{visit_id: "v-1"}
            cancels :later
          end

          scenario "closing ends the chase" do
            given :booked, %{visit_id: "v-1"}
            on :closed, %{visit_id: "v-1"}
            ended true
          end
        """)

      d = Document.contract(model)
      id = &Document.id([&1, model.id | List.wrap(&2)])
      pm = id.(:process_manager, :chase)
      later = id.(:timer, [:chase, :later])
      remind = id.(:command, :remind)
      by = &Enum.find(d["scenarios"]["process_manager"], fn s -> s["description"] == &1 end)
      rel = fn type, from, to, attrs -> relation(d, type, from, to, attrs)["id"] end
      booked = id.(:event, :booked)

      assert %{"phase" => "start", "covers" => covers} = by.("a booking starts the chase")

      assert covers == [
               rel.("starts", booked, pm, %{}),
               rel.("sets", pm, later, %{"on" => booked, "phase" => "start"})
             ]

      assert %{"phase" => "run", "covers" => covers} = by.("a second booking arrives in the run")

      assert covers == [
               rel.("handled_by", booked, pm, %{}),
               rel.("issues", pm, remind, %{"on" => booked, "phase" => "run"})
             ]

      assert %{"phase" => "run", "trigger" => %{"timer" => ^later}, "covers" => covers} =
               by.("the reminder is due")

      assert covers == [rel.("fires", later, remind, %{})]

      reminded = id.(:event, :reminded)

      assert %{"covers" => covers} = by.("a reminder cancels the timer")

      assert covers == [
               rel.("handled_by", reminded, pm, %{}),
               rel.("cancels", pm, later, %{"on" => reminded, "phase" => "run"})
             ]

      assert %{"ended" => true, "covers" => covers} = by.("closing ends the chase")
      assert covers == [rel.("ends", id.(:event, :closed), pm, %{})]
    end

    test "a policy's covers the event's arrow to it and its arrow to each command" do
      for {_module, %{"kind" => "contract"} = d} <- documents(), s <- d["scenarios"]["policy"] do
        types =
          for covered <- s["covers"],
              do:
                Enum.find_value(d["relations"], fn {t, rs} ->
                  Enum.any?(rs, &(&1["id"] == covered)) && t
                end)

        assert "handled_by" in types

        assert Enum.count(types, &(&1 == "issues")) ==
                 length(Enum.uniq_by(s["issues"], & &1["command"]))
      end
    end

    test "a query's covers its read and the projections of what it is given" do
      d = Document.contract(DispatchRig.Ledger)

      for s <- d["scenarios"]["query"] do
        [read | projections] = s["covers"]
        assert %{"from" => query} = Enum.find(d["relations"]["reads"], &(&1["id"] == read))
        assert query == s["target"]

        for p <- projections,
            do: assert(Enum.any?(d["relations"]["projected_into"], &(&1["id"] == p)))
      end
    end
  end

  test "a context-mapping pattern declared between two contexts says it is symmetric" do
    compile(
      """
      defmodule EhOsContract.GraphDocumentTest.Mapped do
        use EhOsContract.Domain, name: :graph_mapped, language: :en

        subdomain :core, "Core", type: :core
        context :front, "Front", subdomain: :core
        context :back, "Back", subdomain: :core
        context :books, "Books", subdomain: :core

        relation :partnership, between: [:front, :back]
        relation :customer_supplier, upstream: :front, downstream: :books
      end
      """,
      "graph_mapped.ex"
    )

    d = Document.domain(EhOsContract.GraphDocumentTest.Mapped, [])
    assert [%{"symmetric" => true}] = d["relations"]["partnership"]
    assert [supplier] = d["relations"]["customer_supplier"]
    refute Map.has_key?(supplier, "symmetric")
    assert JSV.validate(d, @schema) |> elem(0) == :ok
  end

  # A term's word in code (plan DD, L1, #269): its text in the domain's `code_language:`
  # — the term itself in a context written in that language, its translation into it
  # otherwise, none without one — as the glossary and the check read it.
  test "a domain says the language of its code, and a term its word in code" do
    compile(
      """
      defmodule EhOsContract.GraphDocumentTest.Coded do
        use EhOsContract.Domain, name: :graph_coded, language: :en, code_language: :de

        subdomain :core, "Core", type: :core

        context :front, "Front", subdomain: :core do
          term "Visit", definition: "A held slot" do
            translation :de, "Besuch", definition: "Ein gehaltener Termin"
          end

          term "Payer", definition: "Who pays"
        end

        context :books, "Books", subdomain: :core, language: :de do
          term "Buch", definition: "Ein Buch"
        end
      end
      """,
      "graph_coded.ex"
    )

    d = Document.domain(EhOsContract.GraphDocumentTest.Coded, [])
    assert d["code_language"] == "de"

    terms =
      for c <- d["nodes"]["context"], t <- c["terms"], into: %{}, do: {t["text"], t["code"]}

    assert terms == %{"Visit" => "Besuch", "Payer" => nil, "Buch" => "Buch"}
    assert JSV.validate(d, @schema) |> elem(0) == :ok
    assert Document.domain(DispatchRig.Domain, [])["code_language"] == "en"
  end

  # What main's plan DD added to a command and a scenario: what the decision reads
  # (T2a, #240), the one person who may issue it (A1, #247), and a given's moment (S2,
  # #251).
  describe "a command's reads and its person, and a scenario's rows, person and moments" do
    test "a command says what its decision reads, by name, field and entity" do
      d = Document.contract(ReadRig.Orders)
      place = node(d, "command", Document.id([:command, scope(ReadRig.Orders), :place_order]))
      entity = Document.id([:entity, ReadRig.Domain, :product])

      assert place["reads"] == [
               %{"name" => "product", "field" => "product_id", "entity" => entity}
             ]

      assert node(d, "entity", entity)

      cancel = node(d, "command", Document.id([:command, scope(ReadRig.Orders), :cancel_order]))
      refute Map.has_key?(cancel, "reads")
    end

    test "a unit's scenario gives the rows its command reads" do
      d = Document.contract(ReadRig.Orders)
      entity = Document.id([:entity, ReadRig.Domain, :product])

      scenario =
        Enum.find(d["scenarios"]["unit"], &(&1["description"] =~ "totals the price"))

      assert [%{"entity" => ^entity, "data" => %{"product_id" => "product-tea"} = row}] =
               scenario["given_entities"]

      assert row["price"] == 4
    end

    test "a command names the field of the one person who may issue it, and the rule it refuses others on" do
      d = Document.contract(PersonRig.Desk)
      c = scope(PersonRig.Desk)
      resolve = Document.id([:command, c, :resolve_ticket])
      rule = Document.id([:invariant, c, :unit, :ticket, :only_its_assignee_resolves])

      assert node(d, "command", resolve)["actor_is"] == "assignee_id"
      assert %{"actor_is" => true} = relation(d, "refused_on", resolve, rule)
      refute Map.has_key?(relation(d, "refused_on", resolve, rule), "outside_from")

      assign = node(d, "command", Document.id([:command, c, :assign_ticket]))
      refute Map.has_key?(assign, "actor_is")

      as = for s <- d["scenarios"]["unit"], s["as"], into: %{}, do: {s["description"], s["as"]}
      assert as["the clerk it is assigned to resolves it"] == "clerk-ada"
      assert as["another clerk does not"] == "clerk-bo"
    end

    test "a given keeps the moment the scenario dates it at" do
      d = Document.contract(Openings)
      [scenario] = d["scenarios"]["unit"]

      assert [%{"at" => "2026-09-07T09:00:00+02:00"}] = scenario["given"]
      assert [expected] = scenario["expect"]
      refute Map.has_key?(expected, "at")
      assert JSV.validate(d, @schema) |> elem(0) == :ok
    end
  end

  describe "a contract's document" do
    # Plan DD, P2e (#220): what a process module's document holds is not a contract's.
    test "has no kind of a process, since a contract declares none" do
      for c <- Registry.contracts() ++ [Openings, Notes] do
        d = Document.contract(c)

        for kind <- ~w(process stage promise), do: refute(Map.has_key?(d["nodes"], kind), kind)

        for type <- ~w(opens fulfils or_else accountable_for),
            do: refute(Map.has_key?(d["relations"], type), type)

        for e <- d["nodes"]["event"],
            key <- ~w(stage included terminal),
            do: refute(Map.has_key?(e, key), "#{e["id"]} has #{key}")
      end
    end

    test "an event's dependency is a relation to the domain's external" do
      d = Document.contract(UniversalityGate.TreatmentEpisode)
      model = Model.fetch(UniversalityGate.TreatmentEpisode)
      external = Document.id([:external, model.domain, :payer_registry])

      assert %{"label" => "Payer registry: confirmation of eligibility for treatment"} =
               node(d, "external", external)

      assert Enum.any?(d["relations"]["depends_on"], &(&1["to"] == external))
    end
  end

  # Plan DD, P2e (#220): a process module's own document, and its node in the domain's.
  describe "a process module's document" do
    test "says what one run is: its stages, the events they include, its promise, who answers" do
      d = Document.process(DispatchRig.AccountReview)
      ledger = Document.contract(DispatchRig.Ledger)
      pid = "process:dispatch_rig.account_review"
      event = &Document.id([:event, "dispatch_rig.ledger", &1])
      stage = &Document.id([:stage, "dispatch_rig.account_review", &1])
      promise = "promise:dispatch_rig.account_review:balance_confirmed_after_withdrawal"

      assert %{
               "kind" => "process",
               "process" => "dispatch_rig.account_review",
               "module" => "DispatchRig.AccountReview",
               "domain" => "DispatchRig.Domain",
               "label" => "Account review"
             } = d

      assert d["version"] == Model.fetch(DispatchRig.AccountReview).version

      assert [
               %{
                 "id" => ^pid,
                 "correlate" => ["account_id"],
                 "deadline" => %{"amount" => 2, "unit" => "day", "unverified" => false}
               }
             ] = d["nodes"]["process"]

      assert Enum.map(d["nodes"]["stage"], & &1["id"]) ==
               [stage.(:withdrawal), stage.(:confirmation)]

      # An event keeps the id it has in its contract's document, so the two join.
      assert [withdrawn, confirmed] = d["nodes"]["event"]

      assert %{
               "id" => "event:dispatch_rig.ledger:withdrawn",
               "contract" => "contract:dispatch_rig.ledger",
               "type" => "dispatch_rig.ledger.withdrawn"
             } = withdrawn

      assert withdrawn["stage"] == stage.(:withdrawal)
      refute Map.has_key?(withdrawn, "terminal")
      assert %{"terminal" => true} = confirmed
      assert confirmed["stage"] == stage.(:confirmation)

      for e <- d["nodes"]["event"] do
        assert %{"label" => label} = node(ledger, "event", e["id"])
        assert e["label"] == label
      end

      assert [%{"id" => "contract:dispatch_rig.ledger", "module" => "DispatchRig.Ledger"}] =
               d["nodes"]["contract"]

      assert [%{"id" => ^promise, "within" => %{"amount" => 1, "unit" => "day"}}] =
               d["nodes"]["promise"]

      assert relation(d, "opens", event.(:withdrawn), promise)
      assert relation(d, "fulfils", event.(:balance_confirmed), promise)
      assert d["relations"]["or_else"] == []

      auditor = Document.id([:actor, DispatchRig.Domain, :auditor])
      assert relation(d, "accountable_for", auditor, pid)
      assert node(d, "actor", auditor)
    end

    test "a promise the owner has yet to confirm says so, and an or_else is a relation" do
      d = Document.process(ProcessShapes.Handling)
      promise = "promise:process_shapes.handling:completed_or_refusal_notified"
      event = &Document.id([:event, "process_shapes.promised", &1])

      assert [%{"id" => ^promise}] = d["nodes"]["promise"]
      assert relation(d, "or_else", event.(:refusal_notified), promise)

      assert [%{"deadline" => %{"unverified" => true}}] = d["nodes"]["process"]
      assert d["nodes"]["actor"] == [] and d["relations"]["accountable_for"] == []

      assert Enum.count(d["nodes"]["event"], & &1["terminal"]) == 2
    end

    test "draws who answers for it only where the domain declares them, as the domain's does" do
      %{module: module} =
        EhOsContract.DslCase.compile_process(
          "GraphUndeclaredOwner",
          """
            correlate :account_id
            stage :withdrawal, include: [{DispatchRig.Ledger, :withdrawn}]
          """,
          id: "dispatch_rig.graph_undeclared_owner",
          domain: DispatchRig.Domain,
          accountable: :nobody_declared
        )

      d = Document.process(module)
      assert d["nodes"]["actor"] == [] and d["relations"]["accountable_for"] == []

      domain = Document.domain(DispatchRig.Domain, [DispatchRig.Ledger, module])
      assert [_] = domain["nodes"]["process"]
      assert domain["relations"]["accountable_for"] == []
      assert JSV.validate(d, @schema) |> elem(0) == :ok
    end

    # An outage of a system an event rests on suspends a promise, so the picture of the
    # process names the system, as the contract's document does.
    test "names the external systems its events rest on, as the contract's document does" do
      d = Document.process(UniversalityGate.TreatmentEpisodeRun)
      contract = Document.contract(UniversalityGate.TreatmentEpisode)
      registry = Document.id([:external, UniversalityGate.Domain, :payer_registry])
      checked = "event:universality_gate.treatment_episode:payer_eligibility_checked"

      assert [%{"id" => ^registry, "label" => label}] = d["nodes"]["external"]
      assert label == node(contract, "external", registry)["label"]
      assert [%{"from" => ^checked, "to" => ^registry}] = d["relations"]["depends_on"]
      assert d["relations"]["depends_on"] == contract["relations"]["depends_on"]

      assert Document.process(DispatchRig.AccountReview)["nodes"]["external"] == []
      assert JSV.validate(d, @schema) |> elem(0) == :ok
    end

    test "is a process module's alone, and does not depend on anything but it" do
      assert_raise ArgumentError, ~r/is a contract, not a process module/, fn ->
        Document.process(DispatchRig.Ledger)
      end

      assert Document.process(DispatchRig.AccountReview) ==
               Document.process(Model.fetch(DispatchRig.AccountReview))
    end
  end

  describe "a domain's process modules" do
    test "are nodes, with an arrow to each contract they include and from who answers" do
      modules = Registry.contracts() ++ Registry.processes()
      d = Document.domain(DispatchRig.Domain, modules)
      review = "process:dispatch_rig.account_review"

      assert %{
               "name" => "dispatch_rig.account_review",
               "label" => "Account review",
               "module" => "DispatchRig.AccountReview",
               "correlate" => ["account_id"]
             } = node(d, "process", review)

      # One node id in both documents.
      assert [%{"id" => ^review}] =
               Document.process(DispatchRig.AccountReview)["nodes"]["process"]

      assert relation(d, "includes", review, "contract:dispatch_rig.ledger")
      auditor = Document.id([:actor, DispatchRig.Domain, :auditor])
      assert relation(d, "accountable_for", auditor, review)

      # Another domain's are left out, and without process modules there are none.
      refute Enum.any?(d["nodes"]["process"], &(&1["name"] == "process_shapes.handling"))
      assert Document.domain(DispatchRig.Domain, Registry.contracts())["nodes"]["process"] == []

      # A contract left out of the list gets no arrow.
      alone = Document.domain(DispatchRig.Domain, [DispatchRig.AccountReview])
      assert [_] = alone["nodes"]["process"]
      assert alone["relations"]["includes"] == []
    end
  end
end
