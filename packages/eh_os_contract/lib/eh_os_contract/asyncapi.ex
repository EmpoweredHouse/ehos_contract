defmodule EhOsContract.AsyncAPI do
  @moduledoc """
  An AsyncAPI 3.0 document generated from a contract, with a digest.

  The digest is the point. A build records what the contract said; an instance
  serves what it says now; comparing the two answers "is the thing running the thing
  we agreed" without reading any code.

  ## What maps cleanly, and what is forced

  In v2, only a `publish` crosses the application's boundary (D11), so every
  declaration becomes one channel, one message and one `send` operation. Internal
  domain events do not leak into the document. Payload fields map to JSON Schema
  through `EhOsContract.JsonSchema`, the same projection OpenAPI uses.

  The v1 projection stays until E11 removes v1 itself. It maps every event to a
  message because v1 has no `publish` boundary. Past there, three things are worth
  saying out loud rather than burying:

  **A channel is not a process.** A channel is an address messages flow over. An EhOsContract
  process is a *run* — it has identity, stages, an ending. There is no broker here
  at all; the transport is a Postgres table and in-process dispatch. The channel is
  a grouping and its `address` is deliberately undefined, so nobody wires a broker to
  it believing this document promised one. Everything a process actually declares
  travels in `x-eh-os-contract-process`.

  **`trace` has no representation.** AsyncAPI has no vocabulary for a temporal
  assertion, which means the sharpest thing this engine declares is the one thing the
  standard cannot express. It goes in `x-eh-os-contract-traces`, which no AsyncAPI tool reads.
  Anyone choosing EhOsContract *because* it emits AsyncAPI is choosing it for the least of it.

  **`retain` must not be silently dropped.** A consumer reading a spec that shows a
  field, without showing that the field is hashed or discarded before it is ever
  stored, has been told something false by omission. `x-eh-os-contract-retain` carries it.

  **`external` is deliberately absent.** The obvious mapping is to `servers`, and it
  is wrong: an `external` is named after the business fact it supplies and never
  after the vendor, which is a decision the declaration exists to enforce. A `server`
  is a vendor address. Mapping one to the other would break the rule by publishing
  it.

  `rule` and `example` are absent too, and correctly: they pin a pure function, and
  nothing about them is a message.

  ## Operations

  A v2 `publish` is an AsyncAPI `send` operation. Handler edges are still absent:
  including them would make the document depend on the wiring version and move its
  digest when somebody renamed an internal implementation.

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
  inside the thing it hashes. Through `EhOsContract.Digest`, which sorts map keys, so the
  value does not depend on the order JSON happens to be written in — the property
  that module exists for.

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
    for contract <- EhOsContract.Registry.v2_contracts() do
      %{
        "contract" => inspect(contract),
        "version" => Model.fetch(contract).version,
        "digest" => contract |> document() |> get_in(["info", "x-eh-os-contract-digest"])
      }
    end
    |> Enum.sort_by(& &1["contract"])
  end

  @spec body(module()) :: map()
  defp body(contract) do
    case Model.fetch(contract) do
      %{units: _} = model -> v2_body(model)
      _v1 -> v1_body(contract)
    end
  end

  defp v2_body(model) do
    %{
      "asyncapi" => @asyncapi_version,
      "info" => %{
        "title" => inspect(model.module),
        "version" => model.version,
        "x-eh-os-contract-engine" => EhOsContract.version()
      },
      "channels" => v2_channels(model),
      "operations" => v2_operations(model),
      "components" => %{"messages" => v2_messages(model)}
    }
  end

  defp v2_channels(model) do
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

  defp v2_operations(model) do
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

  defp v2_messages(model) do
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

  defp v1_body(contract) do
    %{
      "asyncapi" => @asyncapi_version,
      "info" => %{
        "title" => inspect(contract),
        "version" => Model.version(contract),
        "x-eh-os-contract-engine" => EhOsContract.version(),
        "x-eh-os-contract-traces" => v1_traces(contract),
        "x-eh-os-contract-commands" => v1_commands(contract)
      },
      "channels" => v1_channels(contract),
      "components" => %{"messages" => v1_messages(contract)}
    }
  end

  # `address: nil` is not an omission — see the moduledoc. A channel here groups the
  # messages of one run, and claims nothing about where they travel.
  @spec v1_channels(module()) :: map()
  defp v1_channels(contract) do
    for process <- Model.processes(contract), into: %{} do
      events = Model.events_of(contract, process.name)

      {to_string(process.name),
       %{
         "address" => nil,
         "title" => process.label,
         "messages" =>
           Map.new(events, fn e ->
             {to_string(e.name), %{"$ref" => "#/components/messages/#{v1_message_name(e.name)}"}}
           end),
         "x-eh-os-contract-process" => %{
           "instance" => Enum.map(process.instance, &to_string/1),
           "stages" => Enum.map(process.stages, &to_string/1),
           "cadence" => duration(process.cadence),
           "deadline" => duration(process.deadline),
           "accountable" => process.accountable,
           "unverified" => Enum.map(process.unverified, &to_string/1)
         }
       }}
    end
  end

  @spec v1_messages(module()) :: map()
  defp v1_messages(contract) do
    for event <- Model.events(contract), into: %{} do
      {v1_message_name(event.name),
       %{
         "name" => to_string(event.name),
         "title" => event.label,
         "payload" => v1_schema(event.payload),
         "x-eh-os-contract-retain" =>
           Map.new(event.retain, fn {k, v} -> {to_string(k), to_string(v)} end),
         "x-eh-os-contract-identity" => event.identity && Enum.map(event.identity, &to_string/1),
         "x-eh-os-contract-terminal" => event.terminal
       }}
    end
  end

  @spec v1_schema(map()) :: map()
  defp v1_schema(payload) do
    %{
      "type" => "object",
      "properties" =>
        Map.new(payload, fn {field, type} -> {to_string(field), v1_property(type)} end),
      # Every declared field is present on every emission — this DSL expresses
      # optionality by declaring a second event, never by omitting a field.
      "required" => payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    }
  end

  # `:id` and `:string` are both strings on the wire and are **not** the same
  # declaration: the distinction is what gives the retention check its signal. It
  # travels as `x-eh-os-contract-type` rather than as a `format`, because inventing a format
  # name is a private convention wearing a standard's clothes.
  @spec v1_property(atom() | {:enum, [term()]}) :: map()
  defp v1_property(:integer),
    do: %{"type" => "integer", "x-eh-os-contract-type" => "integer"}

  defp v1_property(:timestamp),
    do: %{"type" => "string", "format" => "date-time", "x-eh-os-contract-type" => "timestamp"}

  defp v1_property({:enum, values}) do
    %{
      "type" => "string",
      "enum" => Enum.map(values, &to_string/1),
      "x-eh-os-contract-type" => "enum"
    }
  end

  defp v1_property(type),
    do: %{"type" => "string", "x-eh-os-contract-type" => to_string(type)}

  @spec v1_traces(module()) :: [map()]
  defp v1_traces(contract) do
    for trace <- Model.traces(contract) do
      %{
        "name" => to_string(trace.name),
        "from" => to_string(trace.from),
        "eventually" => to_string(trace.eventually),
        "or_else" => trace.or_else && to_string(trace.or_else),
        "within" => duration(trace.within)
      }
    end
  end

  @spec v1_commands(module()) :: [map()]
  defp v1_commands(contract) do
    for command <- Model.commands(contract) do
      %{
        "name" => to_string(command.name),
        "title" => command.label,
        "process" => to_string(command.process),
        "principals" => Enum.map(command.principals, &to_string/1),
        "payload" => v1_schema(command.payload)
      }
    end
  end

  @spec duration(EhOsContract.Duration.t() | nil) :: map() | nil
  defp duration(nil), do: nil
  defp duration({count, unit}), do: %{"count" => count, "unit" => to_string(unit)}

  # Kept only for the v1 projection, which E11 removes. A v2 publication's exact,
  # globally versioned name is already an injective component key.
  @spec v1_message_name(atom()) :: String.t()
  defp v1_message_name(event_name) do
    event_name |> to_string() |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end
end
