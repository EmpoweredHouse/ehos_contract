defmodule PNS.AsyncAPI do
  @moduledoc """
  An AsyncAPI 3.0 document generated from a contract, with a digest.

  The digest is the point. A build records what the contract said; an instance
  serves what it says now; comparing the two answers "is the thing running the thing
  we agreed" without reading any code.

  ## What maps cleanly, and what is forced

  Events map to messages and payload fields to JSON Schema, and that part is honest.
  Past there, three things are worth saying out loud rather than burying:

  **A channel is not a process.** A channel is an address messages flow over. A PNS
  process is a *run* — it has identity, stages, an ending. There is no broker here
  at all; the transport is a Postgres table and in-process dispatch. The channel is
  a grouping and its `address` is deliberately undefined, so nobody wires a broker to
  it believing this document promised one. Everything a process actually declares
  travels in `x-pns-process`.

  **`trace` has no representation.** AsyncAPI has no vocabulary for a temporal
  assertion, which means the sharpest thing this engine declares is the one thing the
  standard cannot express. It goes in `x-pns-traces`, which no AsyncAPI tool reads.
  Anyone choosing PNS *because* it emits AsyncAPI is choosing it for the least of it.

  **`retain` must not be silently dropped.** A consumer reading a spec that shows a
  field, without showing that the field is hashed or discarded before it is ever
  stored, has been told something false by omission. `x-pns-retain` carries it.

  **`external` is deliberately absent.** The obvious mapping is to `servers`, and it
  is wrong: an `external` is named after the business fact it supplies and never
  after the vendor, which is a decision the declaration exists to enforce. A `server`
  is a vendor address. Mapping one to the other would break the rule by publishing
  it.

  `rule` and `example` are absent too, and correctly: they pin a pure function, and
  nothing about them is a message.

  ## No `operations`

  Handler edges map well to operations, and they are left out anyway. Including them
  would make the document depend on the wiring version as well as the contract
  version, so the digest would move when somebody renamed a handler — churn in the
  one number this whole document exists to let people compare.

  ## One document per contract

  `version/0` is per contract. A merged document would need a digest of digests and
  would hide which contract moved.
  """

  @asyncapi_version "3.0.0"

  @doc """
  The document for one contract, with its digest already inserted.
  """
  @spec document(module()) :: map()
  def document(contract) do
    body = body(contract)
    put_in(body, ["info", "x-pns-digest"], digest(body))
  end

  @doc """
  The digest of a document.

  Computed over the document **without** its digest key, because the digest lives
  inside the thing it hashes. Through `PNS.Digest`, which sorts map keys, so the
  value does not depend on the order JSON happens to be written in — the property
  that module exists for.

  It hashes the *generated* document rather than the contract, deliberately: a
  change to this generator changes what an instance claims about itself, and a
  consumer comparing digests has to see that.
  """
  @spec digest(map()) :: String.t()
  def digest(document) do
    document
    |> update_in(["info"], &Map.delete(&1, "x-pns-digest"))
    |> PNS.Digest.hash()
  end

  @doc """
  Every registered contract, with its version and document digest.

  The index a consumer reads to find out what changed before fetching anything.
  """
  @spec index() :: [map()]
  def index do
    for contract <- PNS.Registry.contracts() do
      %{
        "contract" => inspect(contract),
        "version" => contract.version(),
        "digest" => contract |> document() |> get_in(["info", "x-pns-digest"])
      }
    end
    |> Enum.sort_by(& &1["contract"])
  end

  @spec body(module()) :: map()
  defp body(contract) do
    %{
      "asyncapi" => @asyncapi_version,
      "info" => %{
        "title" => inspect(contract),
        "version" => contract.version(),
        "x-pns-engine" => PNS.version(),
        "x-pns-traces" => traces(contract),
        "x-pns-commands" => commands(contract)
      },
      "channels" => channels(contract),
      "components" => %{"messages" => messages(contract)}
    }
  end

  # `address: nil` is not an omission — see the moduledoc. A channel here groups the
  # messages of one run, and claims nothing about where they travel.
  @spec channels(module()) :: map()
  defp channels(contract) do
    for process <- contract.processes(), into: %{} do
      events = contract.events_of(process.name)

      {to_string(process.name),
       %{
         "address" => nil,
         "title" => process.label,
         "messages" =>
           Map.new(events, fn e ->
             {to_string(e.name), %{"$ref" => "#/components/messages/#{message_name(e.name)}"}}
           end),
         "x-pns-process" => %{
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

  @spec messages(module()) :: map()
  defp messages(contract) do
    for event <- contract.events(), into: %{} do
      {message_name(event.name),
       %{
         "name" => to_string(event.name),
         "title" => event.label,
         "payload" => schema(event.payload),
         "x-pns-retain" => Map.new(event.retain, fn {k, v} -> {to_string(k), to_string(v)} end),
         "x-pns-identity" => event.identity && Enum.map(event.identity, &to_string/1),
         "x-pns-terminal" => event.terminal
       }}
    end
  end

  @spec schema(map()) :: map()
  defp schema(payload) do
    %{
      "type" => "object",
      "properties" => Map.new(payload, fn {field, type} -> {to_string(field), property(type)} end),
      # Every declared field is present on every emission — this DSL expresses
      # optionality by declaring a second event, never by omitting a field.
      "required" => payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    }
  end

  # `:id` and `:string` are both strings on the wire and are **not** the same
  # declaration: the distinction is what gives the retention check its signal. It
  # travels as `x-pns-type` rather than as a `format`, because inventing a format
  # name is a private convention wearing a standard's clothes.
  @spec property(atom() | {:enum, [term()]}) :: map()
  defp property(:integer), do: %{"type" => "integer", "x-pns-type" => "integer"}

  defp property(:timestamp),
    do: %{"type" => "string", "format" => "date-time", "x-pns-type" => "timestamp"}

  defp property({:enum, values}) do
    %{"type" => "string", "enum" => Enum.map(values, &to_string/1), "x-pns-type" => "enum"}
  end

  defp property(type), do: %{"type" => "string", "x-pns-type" => to_string(type)}

  @spec traces(module()) :: [map()]
  defp traces(contract) do
    for trace <- contract.traces() do
      %{
        "name" => to_string(trace.name),
        "from" => to_string(trace.from),
        "eventually" => to_string(trace.eventually),
        "or_else" => trace.or_else && to_string(trace.or_else),
        "within" => duration(trace.within)
      }
    end
  end

  @spec commands(module()) :: [map()]
  defp commands(contract) do
    for command <- contract.commands() do
      %{
        "name" => to_string(command.name),
        "title" => command.label,
        "process" => to_string(command.process),
        "principals" => Enum.map(command.principals, &to_string/1),
        "payload" => schema(command.payload)
      }
    end
  end

  @spec duration(PNS.Duration.t() | nil) :: map() | nil
  defp duration(nil), do: nil
  defp duration({count, unit}), do: %{"count" => count, "unit" => to_string(unit)}

  # AsyncAPI message names are identifiers in a document, not event names. Kept
  # distinct so the `name` field stays the contract's own spelling.
  @spec message_name(atom()) :: String.t()
  defp message_name(event_name) do
    event_name |> to_string() |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end
end
