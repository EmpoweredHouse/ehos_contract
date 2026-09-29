defmodule EhOsContract.AsyncAPITest do
  @moduledoc """
  Stage 5.9: **the contract as a document somebody else's tooling can read.**

  What this generates is a message catalogue. The `trace`, the `rule`, the
  `example`, the retention policy and the stage order — everything that makes this
  a conformance engine rather than a schema registry — leave the document as
  `x-eh-os-contract-*` extensions that no AsyncAPI tool reads. That is worth knowing before
  anybody concludes the contract "is" AsyncAPI.
  """

  use ExUnit.Case, async: true

  alias ProcessShapes.Promised, as: Contract

  defmodule Ordered do
    @moduledoc false
    use EhOsContract.Contract

    event :first, label: "First", payload: %{case_id: :id}, process: :p
    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  defmodule Reordered do
    @moduledoc false
    use EhOsContract.Contract

    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    event :first, label: "First", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  defmodule Changed do
    @moduledoc false
    use EhOsContract.Contract

    event :first, label: "First", payload: %{case_id: :string}, process: :p
    event :second, label: "Second", payload: %{case_id: :id}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  defmodule Published do
    @moduledoc false
    use EhOsContract.Next.Contract, domain: DispatchRig.Domain, context: :ledger

    aggregate :transfer, "Transfer" do
      identity :transfer_id

      command :complete, "Complete the transfer",
        by: :clerk,
        scope: :branch_id,
        emits: :completed do
        field :branch_id, :id
        field :amount, :integer
        field :internal_note, :string, optional: true
      end

      event :completed, "Transfer completed" do
        field :branch_id, :id
        field :amount, :integer
        field :internal_note, :string, optional: true
      end
    end

    publish :transfer_completed,
      as: "dispatch_rig.transfer.completed.v1",
      from: :completed,
      fields: [:transfer_id, :branch_id, :amount],
      idempotent_on: [:transfer_id]

    process :transfer, "Transfer" do
      correlate :transfer_id
      accountable :clerk
    end
  end

  defmodule CollidingNames do
    @moduledoc false
    use EhOsContract.Next.Contract, domain: DispatchRig.Domain, context: :ledger

    aggregate :probe, "Probe" do
      identity :probe_id
      event :first, "First", recorded_by: :clerk
      event :second, "Second", recorded_by: :clerk
    end

    publish :foo1,
      as: "dispatch_rig.foo1.v1",
      from: :first,
      fields: [:probe_id],
      idempotent_on: [:probe_id]

    publish :foo_1,
      as: "dispatch_rig.foo_1.v1",
      from: :second,
      fields: [:probe_id],
      idempotent_on: [:probe_id]

    process :probe, "Probe" do
      correlate :probe_id
    end
  end

  describe "a v2 publication" do
    test "is the only event boundary and becomes one send operation" do
      document = EhOsContract.AsyncAPI.document(Published)

      assert %{
               "transfer_completed" => %{
                 "address" => "dispatch_rig.transfer.completed.v1",
                 "messages" => %{
                   "dispatch_rig.transfer.completed.v1" => %{
                     "$ref" => "#/components/messages/dispatch_rig.transfer.completed.v1"
                   }
                 }
               }
             } = document["channels"]

      assert %{
               "publish_transfer_completed" => %{
                 "action" => "send",
                 "channel" => %{"$ref" => "#/channels/transfer_completed"},
                 "messages" => [
                   %{
                     "$ref" =>
                       "#/channels/transfer_completed/messages/dispatch_rig.transfer.completed.v1"
                   }
                 ]
               }
             } = document["operations"]

      assert %{"dispatch_rig.transfer.completed.v1" => message} =
               document["components"]["messages"]

      assert message["name"] == "dispatch_rig.transfer.completed.v1"
      assert message["x-eh-os-contract-source-event"] == "completed"
      assert message["x-eh-os-contract-idempotent-on"] == ["transfer_id"]
      refute message["name"] == "completed"
    end

    test "carries only selected fields as a closed JSON Schema object" do
      payload =
        EhOsContract.AsyncAPI.document(Published)["components"]["messages"][
          "dispatch_rig.transfer.completed.v1"
        ]["payload"]

      assert payload["required"] == ["amount", "branch_id", "transfer_id"]
      assert payload["additionalProperties"] == false

      assert payload["properties"]["transfer_id"] == %{
               "type" => "string",
               "x-eh-os-contract-type" => "id"
             }

      assert payload["properties"]["amount"] == %{
               "type" => "integer",
               "x-eh-os-contract-type" => "integer"
             }

      refute Map.has_key?(payload["properties"], "internal_note")
    end

    test "a contract with no publications promises no message boundary" do
      document = EhOsContract.AsyncAPI.document(DispatchRig.Transfer)

      assert document["channels"] == %{}
      assert document["operations"] == %{}
      assert document["components"]["messages"] == %{}
    end

    test "exact publication names cannot overwrite one another after normalisation" do
      messages = EhOsContract.AsyncAPI.document(CollidingNames)["components"]["messages"]

      assert Map.keys(messages) |> Enum.sort() == [
               "dispatch_rig.foo1.v1",
               "dispatch_rig.foo_1.v1"
             ]
    end
  end

  describe "the catalogue" do
    test "every declared event appears exactly once as a message" do
      messages = EhOsContract.AsyncAPI.document(Contract)["components"]["messages"]

      assert map_size(messages) == length(Contract.events())

      names = messages |> Map.values() |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == Contract.event_names() |> Enum.map(&to_string/1) |> Enum.sort()
    end

    test "a payload field's type maps to a pinned literal" do
      # Pinned the way `payload_types/0` is pinned, and for the same reason: adding a
      # type without teaching the generator fails here the same day, rather than
      # producing a spec that is quietly wrong about a field.
      mapping = %{
        id: %{"type" => "string", "x-eh-os-contract-type" => "id"},
        string: %{"type" => "string", "x-eh-os-contract-type" => "string"},
        integer: %{"type" => "integer", "x-eh-os-contract-type" => "integer"},
        timestamp: %{
          "type" => "string",
          "format" => "date-time",
          "x-eh-os-contract-type" => "timestamp"
        },
        enum: %{"type" => "string", "x-eh-os-contract-type" => "enum"}
      }

      assert Map.keys(mapping) |> Enum.sort() == Enum.sort(EhOsContract.Contract.payload_types())

      for {type, expected} <- mapping do
        defmodule_payload = %{field: type}
        doc = schema_for(defmodule_payload)
        assert doc["properties"]["field"] == expected
      end
    end

    test "`:id` and `:string` stay distinguishable, because the retention check needs it" do
      # Both are strings on the wire and are not the same declaration. Carried as
      # `x-eh-os-contract-type` rather than as a `format`, which would be a private convention
      # wearing a standard's clothes.
      doc = schema_for(%{a: :id, b: :string})

      assert doc["properties"]["a"]["type"] == doc["properties"]["b"]["type"]

      refute doc["properties"]["a"]["x-eh-os-contract-type"] ==
               doc["properties"]["b"]["x-eh-os-contract-type"]
    end

    test "retention travels, because a spec that hides it lies by omission" do
      messages = EhOsContract.AsyncAPI.document(ProcessShapes.Rig)["components"]["messages"]

      retains =
        messages
        |> Map.values()
        |> Enum.map(& &1["x-eh-os-contract-retain"])
        |> Enum.reject(&(&1 == %{}))

      refute retains == [],
             "the rig declares a `retain` policy and the document shows no sign of it"
    end

    test "what the standard cannot express is carried as an extension, not dropped" do
      info = EhOsContract.AsyncAPI.document(Contract)["info"]

      assert [trace] = info["x-eh-os-contract-traces"]
      assert trace["name"] == "completed_or_refusal_notified"
      assert trace["within"] == %{"count" => 2, "unit" => "day"}
    end

    test "a command is in the document rather than silently absent" do
      # `command` arrived one stage before this generator. A declaration kind that
      # exists and produces nothing in the spec is the failure `mix eh_os_contract.docs` had and
      # that `schema/0` is pinned below to prevent repeating.
      info = EhOsContract.AsyncAPI.document(UniversalityGate.TreatmentEpisode)["info"]

      assert [command] = info["x-eh-os-contract-commands"]
      assert command["name"] == "qualify_referral"
      assert command["principals"] == ["human"]
    end

    test "`external` is absent, and that is a decision" do
      # The obvious mapping is `servers`, and it is wrong: an `external` is named
      # after the business fact it supplies and never after the vendor, which is what
      # the declaration exists to enforce. A `server` is a vendor address.
      doc = EhOsContract.AsyncAPI.document(ProcessShapes.Rig)

      refute Map.has_key?(doc, "servers")
      refute Enum.empty?(ProcessShapes.Rig.externals())
    end

    test "no `operations`, so the digest does not move when a handler is renamed" do
      refute Map.has_key?(EhOsContract.AsyncAPI.document(Contract), "operations")
    end
  end

  describe "the digest" do
    test "is stable across two calls" do
      assert EhOsContract.AsyncAPI.document(Contract)["info"]["x-eh-os-contract-digest"] ==
               EhOsContract.AsyncAPI.document(Contract)["info"]["x-eh-os-contract-digest"]
    end

    test "does not move when declarations are only reordered" do
      # The sharpest test here. A generator emitting `channels` as a *list* would
      # reintroduce exactly the order dependence `EhOsContract.Digest` exists to remove.
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
      doc = EhOsContract.AsyncAPI.document(Contract)
      tampered = put_in(doc, ["info", "x-eh-os-contract-digest"], "0000deadbeef")

      assert EhOsContract.AsyncAPI.digest(tampered) == EhOsContract.AsyncAPI.digest(doc)
      assert EhOsContract.AsyncAPI.digest(doc) == doc["info"]["x-eh-os-contract-digest"]
    end
  end

  describe "the cross-stage guard" do
    test "a new declaration kind forces a decision about this document" do
      # `mix eh_os_contract.docs` had a hard-coded list of kinds, so a seventh was silently
      # omitted from the generated reference while `--check` called the file current.
      # This is that failure mode's twin, guarded from the other side: an eighth kind
      # reddens here, and whoever adds it has to say what the spec does with it.
      assert EhOsContract.Contract.schema() |> Map.keys() |> Enum.sort() ==
               [:command, :event, :example, :external, :process, :rule, :trace]
    end
  end

  defp digest(%{} = document), do: EhOsContract.AsyncAPI.digest(document)

  defp digest(contract),
    do: EhOsContract.AsyncAPI.document(contract)["info"]["x-eh-os-contract-digest"]

  # Everything but the module's own name and version, which differ between two
  # fixtures by construction and say nothing about declaration order.
  defp untitled(contract) do
    contract
    |> EhOsContract.AsyncAPI.document()
    |> update_in(["info"], &Map.drop(&1, ["title", "version"]))
  end

  defp schema_for(payload) do
    module = Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")

    fields = payload |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end) |> Enum.join(", ")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use EhOsContract.Contract

      event :probe, label: "Probe", payload: %{#{fields}}, process: :p
      process :p, label: "P", instance: []
    end
    """)

    EhOsContract.AsyncAPI.document(module)["components"]["messages"]["Probe"]["payload"]
  end
end
