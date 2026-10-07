defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` documents — a contract's and a domain's graph of facts
  (batch 3) — and the declared shape of a process as data (batch 2), which the
  dashboard still draws. Every document of every fixture holds to the schema that
  ships in `priv/schema`, is JSON as it stands, joins on ids that resolve, holds every
  fact today's pictures draw, and is written with every object's keys in order, so its
  bytes depend on its content alone. That it says nothing from the log is
  `GraphOverlayTest`'s, which writes the log and builds the document again.
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

  # The fields naming an owner, by kind: a value's `unit` is a unit of measure, and a
  # domain's contract's `process` is the process's name and label.
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

    happened ++
      issued ++
      Enum.reject(
        [
          s["actor"],
          s["rejected"],
          s["command"]["command"],
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

    # What a picture says beyond a node's being there: an external giving a field its
    # value, and how many scenarios pin a unit's arrow.
    visits = EhOsContract.GraphDocumentTest.Visits
    document = Document.contract(visits)
    assert EhOsContract.GraphCoverage.contract(visits, document) == []
    refute cut.(visits, document, ["scenarios", "unit"]) == []

    unissued =
      update_in(document, ["nodes", "command"], fn commands ->
        for c <- commands,
            do: Map.update!(c, "fields", fn fs -> Enum.map(fs, &Map.delete(&1, "issued_by")) end)
      end)

    refute EhOsContract.GraphCoverage.contract(visits, unissued) == []
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

          process :welcome, "Welcome" do
            correlate :account_id
            include :opened
          end
        """)

      d = Document.contract(model)
      here = Document.id([:event, model.id, :opened])

      assert %{"declared_as" => sibling, "included" => true} = node(d, "event", here)
      assert sibling == Document.id([:event, scope(DispatchRig.Ledger), :account_opened])
      refute Enum.any?(nodes(d), &(&1["id"] == sibling))
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

        process :visit, "Visit" do
          correlate :visit_id
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
               "label" => nil,
               "process" => %{"name" => "visit", "label" => "Visit"}
             } = node(d, "contract", contract)
    end
  end

  describe "a node's content is its declaration's" do
    # Against the model, for every fixture: what a panel shows of each kind, as data.
    test "reactions, timers, queries, commands, events, units, statuses and the process" do
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
          assert n["terminal"] == (e.terminal || nil)
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

        for p <- List.wrap(Model.process(model)) do
          n = node(d, "process", id.(:process, p.name))
          assert n["deadline"] == json.(p.deadline)
          assert n["correlate"] == json.(p.correlate)
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
    test "a node's label is the client's words or nil, never its name" do
      d = Document.contract(ProcessShapes.Promised)

      for kind <- ~w(promise stage), n <- d["nodes"][kind] do
        assert n["label"] == nil or n["label"] != n["name"], n["id"]
      end

      assert [_ | _] = d["nodes"]["promise"]
      assert Enum.all?(d["nodes"]["promise"], &(&1["label"] == nil))

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

  describe "the declared shape of a process" do
    test "its stages are groups in their order, the order an edge between them" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      stage = &Document.id([:stage, scope(ProcessShapes.Promised), :handling, &1])
      model = Model.fetch(ProcessShapes.Promised)

      assert Enum.map(graph.groups, & &1.name) == Enum.map(Model.process(model).stages, & &1.name)

      assert %{from: from, to: to, relation: :precedes} =
               Enum.find(graph.edges, &(&1.relation == :precedes))

      assert {from, to} == {stage.(:intake), stage.(:decision)}

      intake = Enum.find(graph.groups, &(&1.name == :intake))

      assert Document.id([:event, scope(ProcessShapes.Promised), :request_received]) in intake.nodes
    end

    test "a promise is an edge with its window, and its or_else another" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      event = &Document.id([:event, scope(ProcessShapes.Promised), &1])

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
      id = Document.id([:event, scope(DispatchRig.Branch), :account_opened])

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
