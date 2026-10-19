defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` document of every contract and every domain of the sandbox —
  the client trees and the invented case studies — holds to the schema the engine
  ships, every id in it resolves, and none carries a personal value of Rehmed's. The
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

    for prefix <- ~w(Taxvision. Rehmed. AppuniteEquipment. Lending. Billing. Fulfilment.) do
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

  # StatutoryReporting's policy scenarios start from ClinicalDocumentation's closing, a
  # sibling's event, whose personal fields are declared there: the same values the
  # exported model is held to (`E10OutputsTest`), in every graph document, and the
  # library's member's name and e-mail.
  test "no document carries a personal scenario value" do
    for {module, document} <- documents() do
      encoded = Jason.encode!(document)

      for personal <- [
            "85010112345",
            "M54.5",
            "93.39",
            "Ada Lovelace",
            "ada@example.org",
            "ada@example.net"
          ] do
        refute encoded =~ personal, "#{inspect(module)} carries #{personal}"
      end
    end

    # And the check is not empty: the scenarios are there, with what is not personal.
    reporting = Document.contract(Rehmed.Contracts.StatutoryReporting)
    assert [%{"event" => %{"data" => data}} | _] = reporting["scenarios"]["policy"]
    assert Map.has_key?(data, "pesel") and data["pesel"] == nil

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
  test "the accounting month's promise waits on the registries, and the clinical visit's on nothing" do
    d = Document.process(Taxvision.Processes.AccountingMonth)
    promise = "promise:taxvision.accounting_month:month_opens_or_is_blocked"
    registries = Document.id([:external, Taxvision.Domain, :registries])

    assert [%{"from" => ^promise, "to" => ^registries}] = d["relations"]["waits_on"]
    assert registries in Enum.map(d["nodes"]["external"], & &1["id"])

    assert Document.process(Rehmed.Processes.ClinicalVisit)["relations"]["waits_on"] == []
  end

  # Plan DD, P2e (#220): the clinic's visit, from three contexts' events.
  test "the clinical visit's document has its stages, the events from three contracts and its promise" do
    d = Document.process(Rehmed.Processes.ClinicalVisit)
    stage = &Document.id([:stage, "rehmed.clinical_visit", &1])

    assert %{"kind" => "process", "process" => "rehmed.clinical_visit"} = d

    assert Enum.map(d["nodes"]["stage"], & &1["id"]) ==
             [stage.(:departure), stage.(:closing), stage.(:reporting)]

    assert Enum.map(d["nodes"]["contract"], & &1["name"]) ==
             ~w(rehmed.scheduling rehmed.clinical_documentation rehmed.statutory_reporting)

    events = Map.new(d["nodes"]["event"], &{&1["id"], &1})

    # Each event under the id it has in its contract's document.
    for contract <- [
          Rehmed.Contracts.Scheduling,
          Rehmed.Contracts.ClinicalDocumentation,
          Rehmed.Contracts.StatutoryReporting
        ],
        own = Document.contract(contract)["nodes"]["event"],
        e <- own,
        Map.has_key?(events, e["id"]) do
      assert events[e["id"]]["label"] == e["label"]
    end

    assert %{"stage" => departure} = events["event:rehmed.scheduling:visit_completed"]
    assert departure == stage.(:departure)

    terminal = for {id, %{"terminal" => true}} <- events, do: id

    assert Enum.sort(terminal) == [
             "event:rehmed.statutory_reporting:p1_report_sent",
             "event:rehmed.statutory_reporting:p1_reporting_not_required"
           ]

    promise = "promise:rehmed.clinical_visit:medical_event_reported_within_statutory_window"

    assert [%{"id" => ^promise, "source" => "Dz.U. 2025 poz. 866"}] = d["nodes"]["promise"]

    for {type, event} <- [
          {"opens", "event:rehmed.scheduling:visit_completed"},
          {"fulfils", "event:rehmed.statutory_reporting:p1_report_sent"},
          {"or_else", "event:rehmed.statutory_reporting:p1_reporting_not_required"}
        ] do
      assert [%{"from" => ^event, "to" => ^promise}] = d["relations"][type], type
    end

    manager = Document.id([:actor, Rehmed.Domain, :manager])
    assert [%{"from" => ^manager}] = d["relations"]["accountable_for"]

    # Rehmed's system has its two process modules, each with an arrow to what it includes.
    domain =
      Document.domain(Rehmed.Domain, Registry.contracts() ++ Registry.processes())

    assert Enum.map(domain["nodes"]["process"], & &1["name"]) ==
             ~w(rehmed.clinical_visit rehmed.payer_settlement)

    included =
      for r <- domain["relations"]["includes"],
          r["from"] == "process:rehmed.clinical_visit",
          do: r["to"]

    assert Enum.sort(included) ==
             Enum.sort(Enum.map(d["nodes"]["contract"], & &1["id"]))
  end
end
