defmodule PNS.AsyncAPITest do
  @moduledoc """
  Stage 5.9: **the contract as a document somebody else's tooling can read.**

  What this generates is a message catalogue. The `trace`, the `rule`, the
  `example`, the retention policy and the stage order — everything that makes this
  a conformance engine rather than a schema registry — leave the document as
  `x-pns-*` extensions that no AsyncAPI tool reads. That is worth knowing before
  anybody concludes the contract "is" AsyncAPI.
  """

  use ExUnit.Case, async: true

  alias ProcessShapes.Promised, as: Contract

  defmodule Ordered do
    @moduledoc false
    use PNS.Contract

    event :first, label: "First", payload: %{case_id: :id}, process: :p
    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  defmodule Reordered do
    @moduledoc false
    use PNS.Contract

    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    event :first, label: "First", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  defmodule Changed do
    @moduledoc false
    use PNS.Contract

    event :first, label: "First", payload: %{case_id: :string}, process: :p
    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  describe "the catalogue" do
    test "every declared event appears exactly once as a message" do
      messages = PNS.AsyncAPI.document(Contract)["components"]["messages"]

      assert map_size(messages) == length(Contract.events())

      names = messages |> Map.values() |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == Contract.event_names() |> Enum.map(&to_string/1) |> Enum.sort()
    end

    test "a payload field's type maps to a pinned literal" do
      # Pinned the way `payload_types/0` is pinned, and for the same reason: adding a
      # type without teaching the generator fails here the same day, rather than
      # producing a spec that is quietly wrong about a field.
      mapping = %{
        id: %{"type" => "string", "x-pns-type" => "id"},
        string: %{"type" => "string", "x-pns-type" => "string"},
        integer: %{"type" => "integer", "x-pns-type" => "integer"},
        timestamp: %{"type" => "string", "format" => "date-time", "x-pns-type" => "timestamp"},
        enum: %{"type" => "string", "x-pns-type" => "enum"}
      }

      assert Map.keys(mapping) |> Enum.sort() == Enum.sort(PNS.Contract.payload_types())

      for {type, expected} <- mapping do
        defmodule_payload = %{field: type}
        doc = schema_for(defmodule_payload)
        assert doc["properties"]["field"] == expected
      end
    end

    test "`:id` and `:string` stay distinguishable, because the retention check needs it" do
      # Both are strings on the wire and are not the same declaration. Carried as
      # `x-pns-type` rather than as a `format`, which would be a private convention
      # wearing a standard's clothes.
      doc = schema_for(%{a: :id, b: :string})

      assert doc["properties"]["a"]["type"] == doc["properties"]["b"]["type"]
      refute doc["properties"]["a"]["x-pns-type"] == doc["properties"]["b"]["x-pns-type"]
    end

    test "retention travels, because a spec that hides it lies by omission" do
      messages = PNS.AsyncAPI.document(ProcessShapes.Rig)["components"]["messages"]

      retains =
        messages |> Map.values() |> Enum.map(& &1["x-pns-retain"]) |> Enum.reject(&(&1 == %{}))

      refute retains == [],
             "the rig declares a `retain` policy and the document shows no sign of it"
    end

    test "what the standard cannot express is carried as an extension, not dropped" do
      info = PNS.AsyncAPI.document(Contract)["info"]

      assert [trace] = info["x-pns-traces"]
      assert trace["name"] == "completed_or_refusal_notified"
      assert trace["within"] == %{"count" => 2, "unit" => "day"}
    end

    test "a command is in the document rather than silently absent" do
      # `command` arrived one stage before this generator. A declaration kind that
      # exists and produces nothing in the spec is the failure `mix pns.docs` had and
      # that `schema/0` is pinned below to prevent repeating.
      info = PNS.AsyncAPI.document(UniversalityGate.TreatmentEpisode)["info"]

      assert [command] = info["x-pns-commands"]
      assert command["name"] == "qualify_referral"
      assert command["principals"] == ["human"]
    end

    test "`external` is absent, and that is a decision" do
      # The obvious mapping is `servers`, and it is wrong: an `external` is named
      # after the business fact it supplies and never after the vendor, which is what
      # the declaration exists to enforce. A `server` is a vendor address.
      doc = PNS.AsyncAPI.document(ProcessShapes.Rig)

      refute Map.has_key?(doc, "servers")
      refute Enum.empty?(ProcessShapes.Rig.externals())
    end

    test "no `operations`, so the digest does not move when a handler is renamed" do
      refute Map.has_key?(PNS.AsyncAPI.document(Contract), "operations")
    end
  end

  describe "the digest" do
    test "is stable across two calls" do
      assert PNS.AsyncAPI.document(Contract)["info"]["x-pns-digest"] ==
               PNS.AsyncAPI.document(Contract)["info"]["x-pns-digest"]
    end

    test "does not move when declarations are only reordered" do
      # The sharpest test here. A generator emitting `channels` as a *list* would
      # reintroduce exactly the order dependence `PNS.Digest` exists to remove.
      #
      # Compared with the title put aside, because two fixtures are two modules and a
      # module's name is legitimately part of its document. Stating the property on
      # one module would mean reordering its declarations between two calls, which no
      # test can do — so this is the closest honest form of the claim.
      assert digest(untitled(Ordered)) == digest(untitled(Reordered))
    end

    test "moves when a declaration actually changes" do
      refute digest(untitled(Ordered)) == digest(untitled(Changed))
    end

    test "does not depend on whatever sits in the digest key" do
      # It lives inside the thing it hashes, which is the classic way this goes
      # wrong: hash the document with the key present and the value depends on the
      # value, so two instances that agree about everything can disagree about this.
      #
      # **The first version of this test asserted `digest(doc) == doc[...]` and that
      # proved nothing** — the function is self-consistent whatever it hashes, so
      # substituting a placeholder for the deletion reddened nothing at all. Found by
      # running the reverse check, not by reading it.
      doc = PNS.AsyncAPI.document(Contract)
      tampered = put_in(doc, ["info", "x-pns-digest"], "0000deadbeef")

      assert PNS.AsyncAPI.digest(tampered) == PNS.AsyncAPI.digest(doc)
      assert PNS.AsyncAPI.digest(doc) == doc["info"]["x-pns-digest"]
    end
  end

  describe "the cross-stage guard" do
    test "a new declaration kind forces a decision about this document" do
      # `mix pns.docs` had a hard-coded list of kinds, so a seventh was silently
      # omitted from the generated reference while `--check` called the file current.
      # This is that failure mode's twin, guarded from the other side: an eighth kind
      # reddens here, and whoever adds it has to say what the spec does with it.
      assert PNS.Contract.schema() |> Map.keys() |> Enum.sort() ==
               [:command, :event, :example, :external, :process, :rule, :trace]
    end
  end

  defp digest(%{} = document), do: PNS.AsyncAPI.digest(document)
  defp digest(contract), do: PNS.AsyncAPI.document(contract)["info"]["x-pns-digest"]

  # Everything but the module's own name and version, which differ between two
  # fixtures by construction and say nothing about declaration order.
  defp untitled(contract) do
    contract
    |> PNS.AsyncAPI.document()
    |> update_in(["info"], &Map.drop(&1, ["title", "version"]))
  end

  defp schema_for(payload) do
    module = Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")

    fields = payload |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end) |> Enum.join(", ")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use PNS.Contract

      event :probe, label: "Probe", payload: %{#{fields}}, process: :p
      process :p, label: "P", instance: []
    end
    """)

    PNS.AsyncAPI.document(module)["components"]["messages"]["Probe"]["payload"]
  end
end
