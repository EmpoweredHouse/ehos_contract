defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` document of every contract and every domain of the sandbox's
  case studies holds to the schema the engine ships, every id in it resolves, and none
  carries a personal value a scenario gives. The
  engine's own suite checks its fixtures; these are the documents a renderer will
  actually be given.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Graph.Document
  alias EhOsContract.Registry

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp documents do
    contracts = Registry.contracts()
    modules = contracts ++ Registry.processes()

    for(c <- contracts, do: {c, Document.contract(c)}) ++
      for(p <- Registry.processes(), do: {p, Document.process(p)}) ++
      for d <- Registry.domains(), do: {d, Document.domain(d, modules)}
  end

  test "every contract and every domain gives a document, all of them" do
    names = documents() |> Enum.map(&elem(&1, 0)) |> Enum.map(&inspect/1)

    for prefix <- ~w(Lending. Billing. Fulfilment.) do
      assert Enum.count(names, &String.starts_with?(&1, prefix)) >= 2, prefix
    end
  end

  test "every document holds to the schema" do
    for {module, document} <- documents() do
      case JSV.validate(document, @schema) do
        {:ok, _} -> :ok
        {:error, error} -> flunk("#{inspect(module)}: #{inspect(JSV.normalize_error(error))}")
      end
    end
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

  test "ids are unique in a document, and every relation, owner and scenario resolves in it" do
    for {module, document} <- documents() do
      nodes = for {_kind, ns} <- document["nodes"], n <- ns, do: n
      relations = for {_type, rs} <- document["relations"], r <- rs, do: r
      scenarios = for {_kind, ss} <- document["scenarios"] || %{}, s <- ss, do: s

      ids =
        Enum.map(nodes, & &1["id"]) ++
          Enum.map(relations, & &1["id"]) ++ Enum.map(scenarios, & &1["id"])

      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      here = MapSet.new(nodes, & &1["id"])

      for r <- relations, id <- [r["from"], r["to"]] do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{r["id"]} ends at #{id}"
      end

      for {kind, ns} <- document["nodes"],
          n <- ns,
          key <- Map.get(@owners, kind, []),
          id = n[key] do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{n["id"]}'s #{key} is #{id}"
      end

      relation_ids = MapSet.new(relations, & &1["id"])

      for s <- scenarios do
        assert MapSet.member?(here, s["target"]), "#{inspect(module)}: #{s["id"]}"

        for id <- s["covers"],
            do: assert(MapSet.member?(relation_ids, id), "#{inspect(module)}: #{s["id"]} #{id}")
      end
    end
  end

  # The values the exported model is held to (`E10OutputsTest`), in every graph document:
  # the library's member's name and e-mail.
  test "no document carries a personal scenario value" do
    for {module, document} <- documents() do
      encoded = Jason.encode!(document)

      for personal <- ["Ada Lovelace", "ada@example.org", "ada@example.net"] do
        refute encoded =~ personal, "#{inspect(module)} carries #{personal}"
      end
    end

    # And the check is not empty: the scenarios are there, with what is not personal.
    # The library's member, given to a query's scenario, keeps the name's key and not its
    # value, and so does the row the query answers.
    membership = Document.contract(Lending.Contracts.Membership)

    assert [%{"given" => [%{"data" => registered} | _], "answers" => [row]}] =
             membership["scenarios"]["query"]

    assert Map.has_key?(registered, "name") and registered["name"] == nil
    assert Map.has_key?(row, "email") and row["email"] == nil
  end

  test "a domain's document does not depend on the order its contracts are given in" do
    modules = Registry.contracts() ++ Registry.processes()

    for domain <- Registry.domains() do
      assert Document.domain(domain, Enum.reverse(modules)) ==
               Document.domain(domain, modules)
    end
  end

  # Plan DD, OW1 (#355): what a promise waits on through an earlier step.
  test "the order's promise waits on the carrier, and the billing month's on nothing" do
    d = Document.process(Fulfilment.Processes.Order)
    promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"
    carrier = Document.id([:external, Fulfilment.Domain, :carrier])

    assert [%{"from" => ^promise, "to" => ^carrier}] = d["relations"]["waits_on"]
    assert carrier in Enum.map(d["nodes"]["external"], & &1["id"])

    assert Document.process(Billing.Processes.Month)["relations"]["waits_on"] == []
  end

  # Plan DD, P2e (#220): an order, from three contexts' events.
  test "the order's document has its stages, the events from three contracts and its promise" do
    d = Document.process(Fulfilment.Processes.Order)
    stage = &Document.id([:stage, "fulfilment.order", &1])

    assert %{"kind" => "process", "process" => "fulfilment.order"} = d

    assert Enum.map(d["nodes"]["stage"], & &1["id"]) ==
             [stage.(:ordering), stage.(:picking), stage.(:shipping)]

    assert Enum.map(d["nodes"]["contract"], & &1["name"]) ==
             ~w(fulfilment.orders fulfilment.warehouse fulfilment.shipping)

    events = Map.new(d["nodes"]["event"], &{&1["id"], &1})

    # Each event under the id it has in its contract's document.
    for contract <- [
          Fulfilment.Contracts.Orders,
          Fulfilment.Contracts.Warehouse,
          Fulfilment.Contracts.Shipping
        ],
        own = Document.contract(contract)["nodes"]["event"],
        e <- own,
        Map.has_key?(events, e["id"]) do
      assert events[e["id"]]["label"] == e["label"]
    end

    assert %{"stage" => ordering} = events["event:fulfilment.orders:payment_confirmed"]
    assert ordering == stage.(:ordering)

    terminal = for {id, %{"terminal" => true}} <- events, do: id

    assert Enum.sort(terminal) == [
             "event:fulfilment.orders:cancelled",
             "event:fulfilment.shipping:delivered"
           ]

    promise = "promise:fulfilment.order:dispatched_within_a_day_of_payment"

    assert [%{"id" => ^promise}] = d["nodes"]["promise"]

    for {type, event} <- [
          {"opens", "event:fulfilment.orders:payment_confirmed"},
          {"fulfils", "event:fulfilment.shipping:dispatched"}
        ] do
      assert [%{"from" => ^event, "to" => ^promise}] = d["relations"][type], type
    end

    assert d["relations"]["or_else"] == []

    dispatcher = Document.id([:actor, Fulfilment.Domain, :dispatcher])
    assert [%{"from" => ^dispatcher}] = d["relations"]["accountable_for"]

    # Fulfilment's system has its process module, with an arrow to each contract it includes.
    domain =
      Document.domain(Fulfilment.Domain, Registry.contracts() ++ Registry.processes())

    assert Enum.map(domain["nodes"]["process"], & &1["name"]) == ~w(fulfilment.order)

    included =
      for r <- domain["relations"]["includes"],
          r["from"] == "process:fulfilment.order",
          do: r["to"]

    assert Enum.sort(included) ==
             Enum.sort(Enum.map(d["nodes"]["contract"], & &1["id"]))
  end
end
