defmodule EhOsContract.GraphRenderer.Fixtures do
  @moduledoc false
  # Documents as the engine gives them (`mix eh_os_contract.graph --contract <id>`, `--process
  # <id>` and `--domain <name>` in sandbox/), committed so that this package's tests need no
  # engine. They were taken on 19 October 2026 from the sandbox's invented case studies
  # (publication programme, PB2, #369): lending's circulation (an aggregate, a boundary, a
  # process manager with a timer, an entity read and a supplied field) and membership
  # (personal data, a read model and its query), billing's subscriptions (a never-ending
  # process manager, a policy, a publication) and payments (an effect and an external),
  # fulfilment's warehouse (grants scoped to a warehouse, and `actor_is`) and shipping (a
  # lifecycle), its order process with its overlay over an empty log, and the lending domain
  # (two process modules, translated terms), the billing domain (a publication) and the
  # fulfilment domain (three contexts).
  #
  # They do not follow the sandbox when its contracts change; sandbox/test/graph_renderer_test.exs
  # draws every document the engine gives today. Three hand-made documents beside them hold what
  # no case study wrote: edge_cases.json, ids of any character, a loop and a dangling relation;
  # messaging.json, an event published to and one received from another application, the inbox,
  # and a manager that ends and cancels; and domain.ledger.json, for joining applications (plan
  # DD, G1, #297), an application that subscribes to billing's invoice and to a name nobody in
  # the set publishes.

  @dir Path.expand("../fixtures", __DIR__)

  @doc "Every fixture document, by file name without `.json`."
  def names,
    do:
      @dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&Path.rootname/1)
      |> Enum.sort()

  @doc "The fixture document `name`."
  def document(name), do: @dir |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()

  @doc "The overlay of the fixture document `name`."
  def overlay(name),
    do: @dir |> Path.join("overlays/#{name}.json") |> File.read!() |> JSON.decode!()

  @order_promise "promise:fulfilment.order:dispatched_within_a_day_of_payment"
  @cancelled "event:fulfilment.orders:cancelled"

  @doc """
  The order process with a second way to keep its promise, which its case study does not
  declare: a cancelled order keeps it, an `or_else` relation as the engine writes one.
  """
  def order_with_other_way,
    do:
      put_in(document("process.fulfilment.order"), ["relations", "or_else"], [
        %{
          "id" => "or_else:#{@cancelled}:#{@order_promise}",
          "from" => @cancelled,
          "to" => @order_promise
        }
      ])

  @circulation "lending.circulation"
  @hold "unit:lending.circulation:copy_hold"
  @lend "command:lending.circulation:lend_copy"
  @registered "event:lending.circulation:member_registered"
  @due "constraint:lending.circulation:command:lend_copy:due_within_a_month"

  @doc """
  Lending's circulation with three shapes its case study does not declare, each as the
  engine writes it: the hold on a copy consults membership's `member_registered` (an event
  of another contract, under the name it has here), lending a copy has a constraint (a
  rule of a command, which a unit's picture draws), and lending a copy reads a tariff whose
  field names no entity.
  """
  def circulation_variant do
    membership = document("lending.membership")

    [source] =
      for e <- membership["nodes"]["event"], e["name"] == "member_registered", do: e

    registered =
      source
      |> Map.take(~w(name label source fields type schema_version))
      |> Map.merge(%{
        "id" => @registered,
        "declared_as" => source["id"],
        "declared_in" => "lending.membership"
      })

    consulted = %{
      "id" => "consulted_by:#{@registered}:#{@hold}:match=member_id",
      "from" => @registered,
      "to" => @hold,
      "match" => ["member_id"]
    }

    due = %{
      "id" => @due,
      "name" => "due_within_a_month",
      "label" => "A copy is due back within a month",
      "source" => nil,
      "of" => @lend
    }

    refused = %{"id" => "refused_on:#{@lend}:#{@due}", "from" => @lend, "to" => @due}
    tariff = %{"name" => "tariff", "field" => "copy_id", "entity" => nil}

    document(@circulation)
    |> update_in(["nodes", "event"], &(&1 ++ [registered]))
    |> update_in(["relations", "consulted_by"], &(&1 ++ [consulted]))
    |> update_in(["nodes", "constraint"], &(&1 ++ [due]))
    |> update_in(["relations", "refused_on"], &(&1 ++ [refused]))
    |> update_in(["nodes", "command"], fn commands ->
      for c <- commands,
          do: if(c["id"] == @lend, do: update_in(c, ["reads"], &(&1 ++ [tariff])), else: c)
    end)
  end

  @warehouse "context:Fulfilment.Domain:warehouse"
  @shipping "context:Fulfilment.Domain:shipping"
  @carrier "external:Fulfilment.Domain:carrier"

  @doc """
  The fulfilment domain with two patterns its case study does not declare, as the engine
  writes them: a partnership declared between the warehouse and shipping, symmetric, and
  an anticorruption layer the warehouse keeps against the carrier.
  """
  def fulfilment_variant,
    do:
      document("domain.fulfilment")
      |> put_in(["relations", "partnership"], [
        %{
          "id" => "partnership:#{@warehouse}:#{@shipping}",
          "from" => @warehouse,
          "to" => @shipping,
          "symmetric" => true
        }
      ])
      |> put_in(["relations", "anticorruption_layer"], [
        %{
          "id" => "anticorruption_layer:#{@carrier}:#{@warehouse}",
          "from" => @carrier,
          "to" => @warehouse
        }
      ])

  @doc """
  `document` with the nodes `labels` names, by id, given those labels: a context labelled
  apart from its contract's module, which none of the case studies has.
  """
  def relabel(document, labels),
    do:
      update_in(document, ["nodes"], fn nodes ->
        Map.new(nodes, fn {kind, group} ->
          {kind, for(n <- group, do: Map.update!(n, "label", &Map.get(labels, n["id"], &1)))}
        end)
      end)

  @gateway "actor:Billing.Domain:gateway_integration"
  @collected "event:billing.payments:collected"
  @payment "unit:billing.payments:payment"

  @doc """
  Billing's payments with the scenarios that record what the gateway collected, as the
  engine writes them since a scenario can record an event (issue #430): one appended,
  one refused on the invariant of the amount's value.
  """
  def payments_recorded do
    recording = fn description, amount, outcome ->
      Map.merge(
        %{
          "id" => "scenario:billing.payments:#{description}",
          "description" => description,
          "target" => @payment,
          "covers" => ["may_record:#{@gateway}:#{@collected}"],
          "actor" => @gateway,
          "given" => [],
          "record" => %{"event" => @collected, "data" => %{"amount" => amount}},
          "expect" => []
        },
        outcome
      )
    end

    put_in(document("billing.payments"), ["scenarios", "record"], [
      recording.("the gateway records a payment it collected", 2_200, %{
        "expect" => [%{"event" => @collected, "data" => %{"amount" => 2_200}}]
      }),
      recording.("the gateway cannot record a negative amount collected", -1, %{
        "rejected" => %{"value" => "value:Billing.Domain:money", "invariant" => "not_negative"}
      })
    ])
  end

  @doc """
  Every fixture document by its name, and the variants above, for the tests that go over
  every element of every document.
  """
  def documents,
    do:
      for(name <- names(), do: {name, document(name)}) ++
        [
          {"process.fulfilment.order, with its other way", order_with_other_way()},
          {"lending.circulation, with its variants", circulation_variant()},
          {"domain.fulfilment, with its patterns", fulfilment_variant()},
          {"billing.payments, with its recordings", payments_recorded()}
        ]

  @doc "Every node and every relation of `document`, flat."
  def nodes(document), do: for({_kind, group} <- document["nodes"], node <- group, do: node)
  def relations(document), do: for({_type, group} <- document["relations"], r <- group, do: r)
end
