defmodule EhOsContract.AsyncAPI do
  @moduledoc """
  An AsyncAPI 3.0 document generated from a contract, with a digest.

  The digest is the point. A build records what the contract said; an instance
  serves what it says now; comparing the two answers "is the thing running the thing
  we agreed" without reading any code.

  ## What maps cleanly, and what is forced

  Only a `publish` crosses the application's boundary, so every declaration
  becomes one channel, one message and one `send` operation. Internal domain events
  do not leak into the document. Payload fields map to JSON Schema the same way they
  do in `EhOsContract.OpenAPI`.

  **`external` is deliberately absent.** The obvious mapping is to `servers`, and it
  is wrong: an `external` is named after the business fact it supplies and never
  after the vendor, which is a decision the declaration exists to enforce. A `server`
  is a vendor address. Mapping one to the other would break the rule by publishing
  it.

  `rule` and its examples are absent too, and correctly: they pin a pure function, and
  nothing about them is a message.

  ## Operations

  A `publish` is an AsyncAPI `send` operation. Reactions are absent: including them
  would make the document depend on the wiring version and move its digest when
  somebody renamed an internal implementation.

  ## One document per contract

  `version/0` is per contract. A merged document would need a digest of digests and
  would hide which contract moved.
  """

  alias EhOsContract.{JsonSchema, Model}

  @asyncapi_version "3.0.0"

  @doc """
  The document for one contract, with its digest already inserted.
  """
  @spec document(module()) :: map()
  def document(contract) do
    body = body(contract)
    put_in(body, ["info", "x-eh-os-contract-digest"], digest(body))
  end

  @doc """
  The digest of a document.

  Computed over the document **without** its digest key, because the digest lives
  inside the thing it hashes. Map keys are sorted before hashing, so the value does
  not depend on the order JSON happens to be written in. It is the first twelve hex
  characters of a SHA-256.

  It hashes the *generated* document rather than the contract, deliberately: a
  change to this generator changes what an instance claims about itself, and a
  consumer comparing digests has to see that.
  """
  @spec digest(map()) :: String.t()
  def digest(document) do
    document
    |> update_in(["info"], &Map.delete(&1, "x-eh-os-contract-digest"))
    |> EhOsContract.Digest.document_hash()
  end

  @doc """
  Every registered contract, with its version and document digest.

  The index a consumer reads to find out what changed before fetching anything.
  """
  @spec index() :: [map()]
  def index do
    for contract <- EhOsContract.Registry.contracts(), model = Model.fetch(contract) do
      %{
        "contract" => model.id,
        "module" => inspect(contract),
        "version" => model.version,
        "digest" => contract |> document() |> get_in(["info", "x-eh-os-contract-digest"])
      }
    end
    |> Enum.sort_by(& &1["contract"])
  end

  @spec body(module()) :: map()
  defp body(contract), do: contract |> Model.fetch() |> from_model()

  defp from_model(model) do
    %{
      "asyncapi" => @asyncapi_version,
      "info" => %{
        "title" => inspect(model.module),
        # Plan DD, P1a (#183): the name the API is asked by, to join with the report.
        "x-eh-os-contract-id" => model.id,
        "version" => model.version,
        "x-eh-os-contract-engine" => EhOsContract.version()
      },
      "channels" => channels(model),
      "operations" => operations(model),
      "components" => %{"messages" => messages(model)}
    }
  end

  defp channels(model) do
    for publication <- model.publishes, into: %{} do
      event = published_event(model, publication)
      message = publication.as

      {to_string(publication.name),
       %{
         "address" => publication.as,
         "title" => event.label,
         "messages" => %{
           message => %{"$ref" => "#/components/messages/#{message}"}
         }
       }}
    end
  end

  defp operations(model) do
    for publication <- model.publishes, into: %{} do
      channel = to_string(publication.name)
      message = publication.as

      {"publish_#{publication.name}",
       %{
         "action" => "send",
         "channel" => %{"$ref" => "#/channels/#{channel}"},
         "messages" => [%{"$ref" => "#/channels/#{channel}/messages/#{message}"}]
       }}
    end
  end

  defp messages(model) do
    domain = Model.fetch(model.domain)

    for publication <- model.publishes, into: %{} do
      event = published_event(model, publication)
      fields = Enum.filter(event.fields, &(&1.name in publication.fields))

      {publication.as,
       %{
         "name" => publication.as,
         "title" => event.label,
         "contentType" => "application/json",
         "payload" => JsonSchema.object(fields, domain),
         "x-eh-os-contract-source-event" => to_string(publication.from),
         "x-eh-os-contract-schema-version" => event.schema_version,
         "x-eh-os-contract-idempotent-on" => Enum.map(publication.idempotent_on, &to_string/1)
       }}
    end
  end

  defp published_event(model, publication),
    do: Enum.find(model.events, &(&1.name == publication.from))
end
