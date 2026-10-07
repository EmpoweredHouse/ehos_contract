defmodule EhOsContract.GraphContractTest do
  @moduledoc """
  Plan EG1: a v2 contract's full graph and one unit of it. The full graph is the
  steps `GraphTest` pins, and around them each unit's group, the actors, the read
  side and the external systems; the unit is its state, commands, events and
  invariants, with the scenarios counted on each path.

  The fixture for the outside world is compiled here, so it joins no registry and
  warns in no `mix eh_os_contract.check`.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Graph

  @domain EhOsContract.GraphContractTest.Clinic
  @contract EhOsContract.GraphContractTest.Invoicing
  # Names a domain that does not exist, which a contract may (v2 §8).
  @constrained EhOsContract.Fixtures.GraphConstrained

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :graph_clinic, language: :en

        subdomain :supporting, "Supporting", type: :supporting
        context :invoicing, "Invoicing", subdomain: :supporting

        actor :accountant, :human, "Accountant"
        actor :bot, :system, "Registry robot", backed_by: :registry

        external :tax_office, "Tax office", direction: :outbound
        external :registry, "Company registry", direction: :inbound
        external :mail, "Mail", direction: :outbound

        entity :invoice, "Invoice", context: :invoicing, identity: :number, issued_by: :tax_office do
        end
      end

      defmodule #{inspect(@contract)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :invoicing, id: "graph_clinic.#{contract_name(@contract)}"

        aggregate :draft, "Draft" do
          identity :draft_id

          command :prepare, "Prepare", by: :accountant, emits: :prepared do
            field :company_id, :id, issued_by: :registry
          end

          command :issue, "Issue", by: :accountant, emits: :sent do
            field :invoice, {:id, :invoice}
          end

          event :prepared, "Prepared" do
            field :company_id, :id
          end

          event :sent, "Sent", depends_on: :tax_office do
            field :invoice, {:id, :invoice}
          end

          event :registry_checked, "Registry checked", recorded_by: :bot
        end

        effect :mail_copy, "Mail a copy", handles: :sent, calls: :mail, idempotency: [key: :draft_id, owner: :self]
      end
      """,
      "graph_clinic.ex"
    )

    compile(
      contract("GraphConstrained", """
        aggregate :visit, "Visit" do
          identity :visit_id

          command :record_payment, "Record a payment",
            by: :reception, emits: :payment_recorded, rejects: :positive_amount do
            field :amount, :integer
            constraint :positive_amount, "A payment is more than nothing"
          end

          event :payment_recorded, "Payment recorded" do
            field :amount, :integer
          end
        end

        scenario "nothing paid is refused" do
          command :record_payment, %{amount: 0}
          rejected :positive_amount
        end
      """),
      "graph_constrained.ex"
    )

    :ok
  end

  # Every edge of a graph built as data starts and ends at a node it declares.
  defp declared_ends!(graph) do
    ids = MapSet.new(graph.nodes, & &1.id)

    for edge <- graph.edges, id <- [edge.from, edge.to] do
      assert MapSet.member?(ids, id), "edge #{edge.from} -> #{edge.to}: #{id} is no node"
    end
  end

  describe "the full graph" do
    test "each unit's commands and events are a group of their own" do
      diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)

      assert diagram =~ ~s(    subgraph unit_account["Account · aggregate"]\n)
      assert diagram =~ ~s(        command_deposit["Deposit"]:::command)
      assert diagram =~ ~s(        event_deposited["Deposited"]:::event)
      # A consumer is nobody's unit, so it is drawn outside every group.
      assert diagram =~ ~s(\n    policy_flag_large_deposit{{)
    end

    test "an actor issues its commands, records its events and asks its queries" do
      diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)

      assert diagram =~ ~s|actor_clerk("Clerk"):::actor|
      assert diagram =~ "actor_clerk --> command_open_account"
      assert diagram =~ "actor_nightly_import --> command_deposit"
      assert diagram =~ "actor_auditor -->|records| event_balance_confirmed"
      assert diagram =~ "actor_auditor --> query_balance_of"
      # A command only a consumer issues has no actor before it.
      refute diagram =~ ~r/actor_\w+ --> command_flag_account/
    end

    test "a read model is fed by what it projects, and a query reads it" do
      diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)

      assert diagram =~ ~s|query_balance_of[/"Balance of one account"/]:::query|
      assert diagram =~ ~s(read_model_balances["Balances"]:::read_model)
      assert diagram =~ "event_account_opened --> read_model_balances"
      # Projected after the transaction, so an asynchronous delivery.
      assert diagram =~ "event_withdrawn -.->|async| read_model_ledger_lines"
      assert diagram =~ "query_lines_of -->|reads| read_model_ledger_lines"
    end

    test "an external is drawn where the contract touches it, and nowhere else" do
      diagram = Graph.contract_to_mermaid(@contract)

      assert diagram =~ ~s|external_mail[("Mail")]:::external|
      assert diagram =~ "effect_mail_copy -.->|calls| external_mail"
      assert diagram =~ "event_sent -.- external_tax_office"
      assert diagram =~ "actor_bot -. backed by .- external_registry"
      assert diagram =~ "external_registry -.->|gives company_id| command_prepare"
      # The entity's identifier is the tax office's, so every field referring to it is.
      assert diagram =~ "external_tax_office -.->|gives invoice| command_issue"
      assert diagram =~ "external_tax_office -.->|gives invoice| event_sent"
      assert diagram =~ "classDef external"

      # Ledger's domain declares no external, and the picture says none.
      refute Graph.contract_to_mermaid(DispatchRig.Ledger) =~ "external"
    end

    test "a contract whose domain does not exist draws its actors by name" do
      assert Graph.contract_to_mermaid(@constrained) =~
               ~s|actor_reception("reception"):::actor|
    end

    test "every node and edge is drawn once, in the same order on every call" do
      diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)
      lines = String.split(diagram, "\n")

      assert lines == Enum.uniq(lines)
      assert diagram == Graph.contract_to_mermaid(DispatchRig.Ledger)
    end
  end

  describe "a unit" do
    test "an aggregate's state is a card of its fields, built from its own events" do
      diagram = Graph.unit_to_mermaid(DispatchRig.Ledger, :account)

      assert diagram =~
               ~s(state_account["Account · aggregate<br/>account_id: id · identity<br/>balance: integer"]:::state)

      assert diagram =~ "event_deposited -.-> state_account"
      assert diagram =~ "event_balance_confirmed -.-> state_account"
      # Only the unit: no consumer, read model or actor.
      refute diagram =~ "policy_"
      refute diagram =~ "read_model_"
      refute diagram =~ "actor_"
    end

    test "scenarios are counted on the paths they pin, and a refusal hangs off its command" do
      diagram = Graph.unit_to_mermaid(BoundaryRig.Enrolment, :seat)

      assert diagram =~ "command_subscribe -->|2 scenarios| event_student_subscribed"

      assert diagram =~
               ~s(invariant_a_seat_is_free{"A course never has more students than seats"}:::invariant)

      assert diagram =~
               "command_subscribe -.->|may be refused · 1 scenario| invariant_a_seat_is_free"

      # No scenario pins opening an account, so its edge has no count.
      assert Graph.unit_to_mermaid(DispatchRig.Ledger, :account) =~
               "command_open_account --> event_account_opened\n"
    end

    test "a dynamic consistency boundary is built from what it consults, a sibling's events too" do
      diagram = Graph.unit_to_mermaid(BoundaryRig.Enrolment, :seat)

      assert diagram =~ ~s(state_seat["Seat on a course · dcb<br/>)
      assert diagram =~ "capacity: integer · optional"
      assert diagram =~ ~s(event_course_defined["Course defined"]:::event)
      assert diagram =~ "event_course_defined -.->|consulted by course_id| state_seat"
      assert diagram =~ "event_enrolment_closed -.->|consulted, where stated in prose| state_seat"
    end

    test "a command refused on a constraint of its own points at that constraint" do
      diagram = Graph.unit_to_mermaid(@constrained, :visit)

      assert diagram =~
               ~s(constraint_record_payment_positive_amount{"A payment is more than nothing"}:::constraint)

      assert diagram =~
               "command_record_payment -.->|may be refused · 1 scenario| constraint_record_payment_positive_amount"
    end

    test "every edge of every unit and contract ends at a node the graph declares" do
      contracts = EhOsContract.Registry.contracts() ++ [@contract, @constrained]

      for contract <- contracts, unit <- EhOsContract.Model.fetch(contract).units do
        declared_ends!(EhOsContract.Graph.Unit.build(contract, unit.name))
      end

      for contract <- contracts, do: declared_ends!(EhOsContract.Graph.Contract.build(contract))
    end

    test "every node of every graph has an id of its own, and every edge ends at one" do
      contracts = EhOsContract.Registry.contracts() ++ [@contract, @constrained]
      by_domain = Enum.group_by(contracts, &EhOsContract.Model.fetch(&1).domain)

      build = fn ->
        for(
          contract <- contracts,
          model = EhOsContract.Model.fetch(contract),
          graph <-
            [EhOsContract.Graph.Contract.build(contract)] ++
              for(u <- model.units, do: EhOsContract.Graph.Unit.build(contract, u.name)) ++
              for(
                u <- model.units,
                EhOsContract.Lifecycle.of(u),
                do: EhOsContract.Graph.Lifecycle.build(contract, u.name)
              ),
          do: {contract, graph}
        ) ++
          for domain <- EhOsContract.Registry.domains(),
              graph <- [
                EhOsContract.Graph.ContextMap.build(domain),
                EhOsContract.Graph.System.build(domain, Map.get(by_domain, domain, []))
              ],
              do: {domain, graph}
      end

      graphs = build.()

      # Mermaid's ids were numbered where two met; the document's are the declarations'
      # own, so two nodes meeting on one id would be two declarations drawn as one.
      for {module, graph} <- graphs do
        ids = Enum.map(graph.nodes, & &1.id)
        assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"
        declared_ends!(graph)
      end

      # The same declarations, built again, give the same graphs.
      assert build.() == graphs
    end

    test "two units' invariants of one name are two declarations, with two ids" do
      compile(
        contract("GraphTwinRules", ~S'''
          aggregate :visit, "Visit" do
            identity :visit_id
            invariant :paid, "The visit is paid"
            command :close_visit, "Close", by: :reception, emits: :visit_closed, rejects: :paid
            event :visit_closed, "Closed"
          end

          aggregate :order, "Order" do
            identity :visit_id
            invariant :paid, "The order is paid"
            command :ship_order, "Ship", by: :reception, emits: :order_shipped, rejects: :paid
            event :order_shipped, "Shipped"
          end

          scenario "unpaid visit" do
            command :close_visit
            rejected :paid
          end

          scenario "unpaid order" do
            command :ship_order
            rejected :paid
          end
        '''),
        "graph_twin_rules.ex"
      )

      rule = fn unit ->
        EhOsContract.Fixtures.GraphTwinRules
        |> EhOsContract.Graph.Unit.build(unit)
        |> Map.fetch!(:nodes)
        |> Enum.find(&(&1.kind == :invariant))
      end

      assert rule.(:visit).id == "invariant:clinic.graph_twin_rules:visit:paid"
      assert rule.(:order).id == "invariant:clinic.graph_twin_rules:order:paid"
    end

    test "a label written over several lines stays on its node's line" do
      compile(
        contract("GraphMultiline", ~S'''
          aggregate :visit, "Visit" do
            identity :visit_id

            invariant :paid, """
            Paid in full
            ```
            and "nothing" owed
            """

            command :close, "Close", by: :reception, emits: :closed, rejects: :paid
            event :closed, "Closed"
          end

          scenario "unpaid" do
            command :close
            rejected :paid
          end
        '''),
        "graph_multiline.ex"
      )

      diagram = Graph.unit_to_mermaid(EhOsContract.Fixtures.GraphMultiline, :visit)

      assert diagram =~
               ~s(invariant_paid{"Paid in full ``` and #quot;nothing#quot; owed "}:::invariant\n)

      refute diagram =~ "\n```"
    end

    # "ą" is C4 85 in UTF-8, and 85 is a line break to a regex that reads bytes.
    test "a label's own letters are left alone, whatever bytes spell them" do
      assert EhOsContract.Graph.Mermaid.escape("Linie sumują się\ndo „całości”") ==
               "Linie sumują się do „całości”"
    end

    test "a label's angle brackets and hash print as written, not as a tag or an entity" do
      assert EhOsContract.Graph.Mermaid.escape("kwota < 200 zł, faktura #12; <b>") ==
               "kwota #lt; 200 zł, faktura #35;12; #lt;b#gt;"
    end

    test "the state card's lines are broken by the renderer, and a field's text is escaped" do
      node = %{
        id: "state:X:x",
        kind: :state,
        name: :x,
        label: "Wizyta",
        unit_kind: :aggregate,
        fields: [%{name: :"a<b", type: :id, identity: false, optional: false}]
      }

      assert EhOsContract.Graph.Mermaid.render(%{nodes: [node], edges: []}) =~
               ~s(\n    state_x["Wizyta · aggregate<br/>a#lt;b: id"]:::state\n)
    end

    test "a unit the contract does not have is refused, naming the ones it has" do
      assert_raise ArgumentError, ~r/has no unit :nonesuch; it has \[:account\]/, fn ->
        Graph.unit_to_mermaid(DispatchRig.Ledger, :nonesuch)
      end
    end
  end

  describe "mix eh_os_contract.graph" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    @tag :tmp_dir
    test "--contract draws the full graph, and --unit one unit of it", %{tmp_dir: dir} do
      path = Path.join(dir, "graph.mmd")

      Mix.Tasks.EhOsContract.Graph.run(["--contract", "dispatch_rig.ledger", "--output", path])
      assert File.read!(path) =~ "actor_clerk --> command_open_account"

      Mix.Tasks.EhOsContract.Graph.run([
        "--contract",
        "dispatch_rig.ledger",
        "--unit",
        "account",
        "--output",
        path
      ])

      assert File.read!(path) =~ "state_account["
    end

    test "an unknown contract or unit, a unit without its contract, and a flag it would drop are refused" do
      assert_raise Mix.Error,
                   ~r/no contract Nonesuch\. Registered: .*dispatch_rig\.ledger/,
                   fn ->
                     Mix.Tasks.EhOsContract.Graph.run(["--contract", "Nonesuch"])
                   end

      assert_raise Mix.Error,
                   ~r/dispatch_rig\.ledger has no unit nonesuch\. Units: account/,
                   fn ->
                     Mix.Tasks.EhOsContract.Graph.run([
                       "--contract",
                       "dispatch_rig.ledger",
                       "--unit",
                       "nonesuch"
                     ])
                   end

      assert_raise Mix.Error, ~r/--unit draws the declarations only/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(
          ~w(--contract dispatch_rig.ledger --unit account --overlay)
        )
      end

      assert_raise Mix.Error, ~r/pass one of them/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--contract dispatch_rig.ledger --process ledger))
      end

      assert_raise Mix.Error, ~r/pass --contract too/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(["--unit", "account"])
      end
    end
  end
end
