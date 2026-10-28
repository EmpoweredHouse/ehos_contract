defmodule EhOsContract.GraphOverlayTest do
  @moduledoc """
  Plan E13a, batch 5: the overlay of every contract and every domain of the sandbox's
  case studies holds to the schema the engine ships and joins the document it names.
  """

  use EhOsContractHost.DataCase, async: false

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.Registry

  # Built when a test first asks for it, never into a module attribute: on OTP 28 a
  # compiled regex is a reference, which Elixir 1.18 cannot put into the code of a
  # function that reads the attribute (#492).
  defp schema do
    with nil <- :persistent_term.get({__MODULE__, :schema}, nil) do
      built = Overlay.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()
      :persistent_term.put({__MODULE__, :schema}, built)
      built
    end
  end

  test "every overlay holds to its schema and names its document's digest" do
    contracts = Registry.contracts()
    modules = contracts ++ Registry.processes()

    overlays =
      for(c <- contracts, do: {Overlay.contract(c), Document.contract(c)}) ++
        for(p <- Registry.processes(), do: {Overlay.process(p), Document.process(p)}) ++
        for d <- Registry.domains(),
            do: {Overlay.domain(d, modules), Document.domain(d, modules)}

    for {overlay, document} <- overlays do
      assert {:ok, _} = JSV.validate(overlay, schema()),
             inspect(overlay["contract"] || overlay["process"] || overlay["domain"])

      assert overlay["document_digest"] == document["digest"]

      ids = for {_t, xs} <- document["nodes"], x <- xs, into: MapSet.new(), do: x["id"]
      defined = for {_t, xs} <- overlay["observed"]["relations"], x <- xs, do: x["id"]

      relations =
        for {_t, xs} <- document["relations"], x <- xs, into: MapSet.new(defined), do: x["id"]

      for id <- Map.keys(overlay["nodes"]), do: assert(MapSet.member?(ids, id), id)
      for id <- Map.keys(overlay["relations"]), do: assert(MapSet.member?(relations, id), id)
    end
  end

  # Plan DD, P2e (#220): with nothing in the log, the order has no runs, and its promise
  # has verdicts all zero, not none: the report judges it.
  test "the order's overlay has its runs and its promise's verdicts" do
    o = Overlay.process(Fulfilment.Processes.Order)

    assert {:ok, _} = JSV.validate(o, schema())
    assert o["nodes"]["process:fulfilment.order"] == %{"runs" => 0}

    assert %{"violated" => 0, "instances" => 0, "suspended" => 0} =
             o["nodes"]["promise:fulfilment.order:dispatched_within_a_day_of_payment"]

    domain = Overlay.domain(Billing.Domain, Registry.contracts() ++ Registry.processes())
    assert domain["nodes"]["process:billing.month"] == %{"runs" => 0}
  end
end
