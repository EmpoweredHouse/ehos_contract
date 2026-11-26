defmodule EhosContract.GraphSeedTest do
  @moduledoc """
  The domain's seed actor in the `graph.v1` documents (#683): no relation leaves it, the
  domain's document carries its `not_seeded` with the reasons, and each command says
  whether the seed may issue it. On the invented `SeedRig`, and on a contract here that
  names the seed in a `by:`, which `check` refuses and the graph does not draw.
  """

  use ExUnit.Case, async: true

  alias EhosContract.Graph.Document

  # Invented: the seed named where `check` refuses it.
  defmodule Misnamed do
    @moduledoc false
    use EhosContract.Contract, domain: SeedRig.Domain, context: :shop, id: "seed_rig.misnamed"

    aggregate :slip, "Slip" do
      identity :slip_id
      command :print_slip, "Print a slip", by: [:clerk, :sample_data], emits: :slip_printed
      event :slip_printed, "Slip printed", recorded_by: :sample_data
    end
  end

  @seed Document.id([:actor, SeedRig.Domain, :sample_data])

  defp relations(document), do: for({_type, rs} <- document["relations"], r <- rs, do: r)
  defp named(document, kind, name), do: Enum.find(document["nodes"][kind], &(&1["name"] == name))

  test "no relation leaves the seed, on a contract's graph or the domain's" do
    for document <- [
          Document.contract(SeedRig.Shop),
          Document.contract(Misnamed),
          Document.domain(SeedRig.Domain, [SeedRig.Shop, Misnamed])
        ] do
      assert Enum.filter(relations(document), &(&1["from"] == @seed)) == []
    end

    # Named in a `by:`, the seed is not drawn on the contract's graph at all; the clerk is.
    misnamed = Document.contract(Misnamed)
    refute named(misnamed, "actor", "sample_data")
    assert named(misnamed, "actor", "clerk")
  end

  test "the domain's document gives the seed its kind and its not_seeded, with why" do
    seed = named(Document.domain(SeedRig.Domain, [SeedRig.Shop]), "actor", "sample_data")

    assert seed["actor_kind"] == "seed"

    assert seed["not_seeded"] == [
             %{"name" => "refund_order", "reason" => "A refund moves a client's money"}
           ]

    refute seed["role"]

    # Control: a person carries no list.
    refute named(Document.domain(SeedRig.Domain, [SeedRig.Shop]), "actor", "clerk")["not_seeded"]
  end

  test "each command says whether the seed may issue it" do
    shop = Document.contract(SeedRig.Shop)
    seed = &named(shop, "command", &1)["seed"]

    assert seed.("place_order") == "seeded"
    assert seed.("hand_over") == "seeded"
    # Listed; kept for the person its unit names; issued only by the application's code.
    assert seed.("refund_order") == "not_seeded"
    assert seed.("release_order") == "not_seeded"
    assert seed.("archive_order") == "not_seeded"

    assert named(shop, "command", "refund_order")["not_seeded_because"] ==
             "A refund moves a client's money"

    refute named(shop, "command", "release_order")["not_seeded_because"]
  end

  test "a domain with no seed says nothing about one" do
    for command <- Document.contract(PersonRig.Desk)["nodes"]["command"] do
      refute Map.has_key?(command, "seed")
    end
  end
end
