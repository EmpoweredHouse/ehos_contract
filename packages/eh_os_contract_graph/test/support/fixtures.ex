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

  @doc """
  Every fixture document by its name, and the order process with its other way, for the
  tests that go over every element of every document.
  """
  def documents,
    do:
      for(name <- names(), do: {name, document(name)}) ++
        [{"process.fulfilment.order, with its other way", order_with_other_way()}]

  @doc "Every node and every relation of `document`, flat."
  def nodes(document), do: for({_kind, group} <- document["nodes"], node <- group, do: node)
  def relations(document), do: for({_type, group} <- document["relations"], r <- group, do: r)
end
