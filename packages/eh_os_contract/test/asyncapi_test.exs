defmodule EhOsContract.AsyncAPITest do
  @moduledoc """
  Stage 5.9: **the contract as a document somebody else's tooling can read.**

  In v2 only a `publish` crosses the application's boundary (D11), so the document
  is a catalogue of publications: each one a channel, a message and a `send`
  operation, and nothing of the internal domain events. The digest is computed over
  the document without its own key, so two instances that agree about everything
  agree about it too.
  """

  use ExUnit.Case, async: true

  defmodule Published do
    @moduledoc false
    use EhOsContract.Contract, domain: DispatchRig.Domain, context: :ledger

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
    use EhOsContract.Contract, domain: DispatchRig.Domain, context: :ledger

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

  # `CollidingNames` with its publications written the other way round, and with one
  # publication's fields changed: the two sides of "the digest is about content".
  defmodule ReorderedNames do
    @moduledoc false
    use EhOsContract.Contract, domain: DispatchRig.Domain, context: :ledger

    aggregate :probe, "Probe" do
      identity :probe_id
      event :first, "First", recorded_by: :clerk
      event :second, "Second", recorded_by: :clerk
    end

    publish :foo_1,
      as: "dispatch_rig.foo_1.v1",
      from: :second,
      fields: [:probe_id],
      idempotent_on: [:probe_id]

    publish :foo1,
      as: "dispatch_rig.foo1.v1",
      from: :first,
      fields: [:probe_id],
      idempotent_on: [:probe_id]

    process :probe, "Probe" do
      correlate :probe_id
    end
  end

  defmodule ChangedNames do
    @moduledoc false
    use EhOsContract.Contract, domain: DispatchRig.Domain, context: :ledger

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
      as: "dispatch_rig.foo_1.v2",
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

      # The codec's bounds, where JSON Schema has a word for them.
      assert payload["properties"]["transfer_id"] == %{
               "type" => "string",
               "minLength" => 1,
               "maxLength" => 255,
               "x-eh-os-contract-max-bytes" => 255,
               "x-eh-os-contract-type" => "id"
             }

      assert payload["properties"]["amount"] == %{
               "type" => "integer",
               "format" => "int64",
               "minimum" => -9_223_372_036_854_775_808,
               "maximum" => 9_223_372_036_854_775_807,
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

  # Compared with `info` put aside: three fixtures are three modules, and a module's
  # name and version are legitimately part of its document. Reordering one module's
  # declarations between two calls is something no test can do, so this is the
  # closest honest form of the claim.
  defp content_digest(contract) do
    contract
    |> EhOsContract.AsyncAPI.document()
    |> Map.delete("info")
    |> EhOsContract.Digest.document_hash()
  end

  describe "the digest" do
    test "does not move when publications are only reordered" do
      # A generator writing `channels` as a list in declaration order would bring back
      # the order dependence `EhOsContract.Digest` exists to remove.
      assert content_digest(CollidingNames) == content_digest(ReorderedNames)
    end

    test "moves when a publication actually changes" do
      refute content_digest(CollidingNames) == content_digest(ChangedNames)
    end

    test "is stable across two calls" do
      assert EhOsContract.AsyncAPI.document(Published)["info"]["x-eh-os-contract-digest"] ==
               EhOsContract.AsyncAPI.document(Published)["info"]["x-eh-os-contract-digest"]
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
      doc = EhOsContract.AsyncAPI.document(Published)
      tampered = put_in(doc, ["info", "x-eh-os-contract-digest"], "0000deadbeef")

      assert EhOsContract.AsyncAPI.digest(tampered) == EhOsContract.AsyncAPI.digest(doc)
      assert EhOsContract.AsyncAPI.digest(doc) == doc["info"]["x-eh-os-contract-digest"]
    end
  end
end
