defmodule EhOsContract.GraphDomainTest do
  @moduledoc """
  Plan EG2: a domain's two pictures. The context map is its subdomains, contexts,
  external systems and the relations between them; the system is its v2 contracts
  in their contexts and what one consumes from another or through a publication,
  with the log over it.

  The fixture is compiled here, so it joins no registry and warns in no
  `mix eh_os_contract.check`. Its labels are Polish, as a client's are.
  """

  use EhOsContract.DataCase, async: false

  import EhOsContract.DslCase, only: [compile: 2]

  alias EhOsContract.Graph

  @domain EhOsContract.GraphDomainTest.Clinic
  @scheduling EhOsContract.GraphDomainTest.Scheduling
  @settlement EhOsContract.GraphDomainTest.Settlement

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :graph_domain_clinic, language: :pl

        subdomain :core, "Rdzeń", type: :core
        subdomain :supporting, "Wsparcie", type: :supporting

        context :scheduling, "Umawianie i zasoby", subdomain: :core
        context :settlement, "Rozliczenia", subdomain: :supporting
        context :archive, "Archiwum", subdomain: :supporting

        actor :reception, :human, "Recepcja"

        external :payer_registry, "Rejestr płatnika", direction: :inbound
        external :sms, "Bramka SMS", direction: :outbound

        relation :customer_supplier, upstream: :scheduling, downstream: :settlement
        relation :conformist, upstream: :payer_registry, downstream: :settlement
        relation :partnership, between: [:scheduling, :archive]
        relation :separate_ways, between: [:settlement, :archive]
      end

      defmodule #{inspect(@scheduling)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :scheduling

        aggregate :slot, "Termin" do
          identity :visit_id
          command :book, "Rezerwacja", by: :reception, emits: :booked
          event :booked, "Zarezerwowano wizytę"
        end

        publish :booked, as: "clinic.visit.booked.v1", from: :booked, fields: [:visit_id]

        process :slot, "Termin wizyty" do
          correlate :visit_id
        end
      end

      defmodule #{inspect(@settlement)} do
        use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

        consumes #{inspect(@scheduling)}, :booked
        consumes "clinic.visit.booked.v1", as: :booked_elsewhere do
          field :visit_id, :id
        end

        aggregate :visit, "Rozliczenie wizyty" do
          identity :visit_id
          command :close, "Zamknięcie rozliczenia", by: :reception, emits: :closed
          event :closed, "Zamknięto rozliczenie"
        end

        process :visit, "Rozliczenie wizyty" do
          correlate :visit_id
          include :booked
        end
      end
      """,
      "graph_domain_clinic.ex"
    )

    :ok
  end

  describe "the context map" do
    test "each subdomain is a group of its contexts, in the client's words" do
      map = Graph.context_map_to_mermaid(@domain)

      assert map =~ ~s(    subgraph subdomain_core["Rdzeń · core"]\n)
      assert map =~ ~s|        context_scheduling("Umawianie i zasoby"):::context|
      assert map =~ ~s|        context_settlement("Rozliczenia"):::context|
    end

    test "a directed relation runs from upstream to downstream, an external at either end" do
      map = Graph.context_map_to_mermaid(@domain)

      assert map =~ "context_scheduling -->|customer supplier| context_settlement"
      assert map =~ "external_payer_registry -->|conformist| context_settlement"
      assert map =~ ~s|external_payer_registry[("Rejestr płatnika")]:::external|
    end

    test "a symmetric relation has no arrowhead, and separate ways is dashed" do
      map = Graph.context_map_to_mermaid(@domain)

      assert map =~ "context_scheduling ---|partnership| context_archive"
      assert map =~ "context_settlement -. separate ways .- context_archive"
    end

    test "an external no relation reaches is on the map anyway" do
      assert Graph.context_map_to_mermaid(@domain) =~ ~s|external_sms[("Bramka SMS")]:::external|
    end

    test "the domain's page carries its map" do
      index = EhOsContract.Pages.render(@domain, [@scheduling, @settlement])["index.md"]

      assert index =~
               "## Context map\n\n```mermaid\n" <>
                 Graph.context_map_to_mermaid(@domain) <> "\n```\n"
    end
  end

  describe "the system" do
    defp system(opts \\ []),
      do: Graph.system_to_mermaid(@domain, [@scheduling, @settlement], opts)

    test "each context is a group of its contracts, and a consumed sibling an arrow to its consumer" do
      diagram = system()
      scheduling = "contract_eh_os_contract_graph_domain_test_scheduling"

      assert diagram =~ ~s(    subgraph context_scheduling["Umawianie i zasoby · context"]\n)

      assert diagram =~
               ~s(        #{scheduling}["Scheduling · Termin wizyty"]:::contract)

      assert diagram =~
               "#{scheduling} -->|booked| contract_eh_os_contract_graph_domain_test_settlement"
    end

    test "a publication is one node, which the publisher and a consumer of its name meet on" do
      diagram = system()

      assert diagram =~
               ~s(publication_clinic_visit_booked_v1[/"clinic.visit.booked.v1"\\]:::publication)

      assert diagram =~
               "contract_eh_os_contract_graph_domain_test_scheduling -.->|publishes booked| publication_clinic_visit_booked_v1"

      assert diagram =~
               "publication_clinic_visit_booked_v1 -.->|as booked_elsewhere| contract_eh_os_contract_graph_domain_test_settlement"

      assert length(String.split(diagram, "publication_clinic_visit_booked_v1[")) == 2
    end

    test "a contract naming another domain is left out, and so is a context with no contract" do
      diagram = Graph.system_to_mermaid(@domain, [@scheduling, @settlement, DispatchRig.Ledger])

      refute diagram =~ "dispatch_rig"
      refute diagram =~ "context_archive"
    end

    test "the overlay puts a process's runs on its contract and the consumed events on the edge" do
      clerk = EhOsContract.Actor.credential("u-1", ["dispatch_rig.open_account"])

      for account <- ["a-1", "a-2"] do
        {:ok, _} =
          EhOsContract.dispatch(
            DispatchRig.Ledger,
            %DispatchRig.Ledger.Commands.OpenAccount{account_id: account, branch_id: "b-7"},
            actor: clerk
          )
      end

      diagram =
        Graph.system_to_mermaid(DispatchRig.Domain, EhOsContract.Registry.v2_contracts(),
          overlay: true
        )

      assert diagram =~ ~s|contract_dispatch_rig_ledger["Ledger · Ledger (2 runs)"]:::contract|
      assert diagram =~ ~s|contract_dispatch_rig_branch["Branch · Branch (1 run)"]:::contract|

      assert diagram =~
               "contract_dispatch_rig_ledger -->|account_opened · 2 events| contract_dispatch_rig_branch"

      # Without the overlay, the edge names what flows and nothing counts it.
      assert Graph.system_to_mermaid(DispatchRig.Domain, EhOsContract.Registry.v2_contracts()) =~
               "contract_dispatch_rig_ledger -->|account_opened| contract_dispatch_rig_branch"
    end
  end

  describe "mix eh_os_contract.graph" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    @tag :tmp_dir
    test "--map draws a domain's context map, and --system its contracts", %{tmp_dir: dir} do
      path = Path.join(dir, "graph.mmd")

      Mix.Tasks.EhOsContract.Graph.run(~w(--map dispatch_rig --output #{path}))
      assert File.read!(path) =~ ~s|context_ledger("Ledger"):::context|

      Mix.Tasks.EhOsContract.Graph.run(~w(--system dispatch_rig --overlay --output #{path}))

      assert File.read!(path) =~
               "contract_dispatch_rig_ledger -->|account_opened · 0 events| contract_dispatch_rig_branch"
    end

    test "an unknown domain, a map with the log, and two pictures at once are refused" do
      assert_raise Mix.Error, ~r/no domain nonesuch\. Registered: .*dispatch_rig/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--map nonesuch))
      end

      assert_raise Mix.Error, ~r/--map draws the domain's declarations only/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--map dispatch_rig --overlay))
      end

      assert_raise Mix.Error, ~r/--map and --system draw different pictures/, fn ->
        Mix.Tasks.EhOsContract.Graph.run(~w(--map dispatch_rig --system dispatch_rig))
      end
    end
  end
end
