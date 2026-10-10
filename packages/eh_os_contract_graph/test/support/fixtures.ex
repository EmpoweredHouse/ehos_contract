defmodule EhOsContract.GraphRenderer.Fixtures do
  @moduledoc false
  # Documents as the engine gave them on 7 and 8 October 2026, refreshed on 9 October with
  # what a field keeps and which patterns are symmetric (`mix eh_os_contract.graph
  # --contract <id>` in sandbox/), committed so that this package's tests need no engine: five
  # contracts and a domain of the sandbox's test material — an aggregate with a read side,
  # a process manager with a timer, a process with stages and a promise, a boundary, and a
  # lifecycle. They do not follow the sandbox when its
  # contracts change; sandbox/test/graph_renderer_test.exs draws every document the engine
  # gives today. Two hand-made documents beside them hold what no client wrote: edge_cases.json,
  # ids of any character, a loop and a dangling relation; messaging.json, an event published to
  # and one received from another application, the inbox, and a manager that ends and cancels.

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

  @doc "Every node and every relation of `document`, flat."
  def nodes(document), do: for({_kind, group} <- document["nodes"], node <- group, do: node)
  def relations(document), do: for({_type, group} <- document["relations"], r <- group, do: r)
end
