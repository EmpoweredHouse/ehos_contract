defmodule EhOsContract.GraphRenderer.Fixtures do
  @moduledoc false
  # Documents as the engine gives them (`mix eh_os_contract.graph --contract <id>`, `--process
  # <id>` and `--domain rehmed` in sandbox/), committed so that this package's tests need no
  # engine: five contracts of the sandbox's test material — an aggregate with a read side, a
  # process manager with a timer, a boundary, and a lifecycle —, a process module with stages and
  # a promise, the clinic's visit, and the Rehmed domain with its process modules. Taken
  # again on 14 October 2026 (plan DD, P2e, #220), when a contract's document lost its process.
  # They do not follow the sandbox when its contracts change; sandbox/test/graph_renderer_test.exs
  # draws every document the engine gives today. Two hand-made documents beside them hold what no
  # client wrote: edge_cases.json, ids of any character, a loop and a dangling relation;
  # messaging.json, an event published to and one received from another application, the inbox,
  # and a manager that ends and cancels. For joining applications (plan DD, G1, #297), TaxVision's
  # domain, taken on 15 October 2026, whose accounting month publishes, and domain.ledger.json,
  # hand-made, an application that subscribes to it and to a name nobody in the set publishes.
  # Under overlays/, the visit's overlay as the engine gives it over an empty log.
  # Beside the clients' documents, the same kinds taken on 19 October 2026 from the sandbox's
  # invented case studies (publication programme, PB2, #369), which the tests move to before the
  # clients' leave: lending's circulation (an aggregate, a boundary, a process manager with a
  # timer, an entity read and a supplied field) and membership (personal data, a read model and
  # its query), billing's subscriptions (a never-ending process manager, a policy, a
  # publication) and payments (an effect and an external), fulfilment's warehouse (grants scoped
  # to a warehouse, and `actor_is`) and shipping (a lifecycle), its order process with its
  # overlay, and the lending domain (two process modules, translated terms), the billing domain
  # (a publication) and the fulfilment domain (three contexts).

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

  @doc "Every node and every relation of `document`, flat."
  def nodes(document), do: for({_kind, group} <- document["nodes"], node <- group, do: node)
  def relations(document), do: for({_type, group} <- document["relations"], r <- group, do: r)
end
