defmodule EhosContract.Bus do
  @moduledoc """
  Carries an integration event from one application to another. The bus is the
  interface between the engine and a transport, such as a message broker.

      config :ehos_contract, bus: {EhosContract.Bus.Local, []}

  The engine is on both sides of the bus:

  - The *relay* reads from the log the events that a `publish` declares. It hands
    them to `c:publish/2`.
  - The *inbox* of the subscriber takes each message. It commits what its policies
    decide, and only then acknowledges the message.

  An *adapter* implements the bus between these two parts. This package supplies
  `EhosContract.Bus.Local`, for tests and for one node. The adapters for a real
  transport, such as JetStream, are not in this library. The library depends on no
  transport.

  ## What occurs between the relay, the bus and the inbox?

  ![The relay publishes each batch through the adapter in a transaction, and the durable consumer of an inbox acknowledges each message after its commit.](img/bus-callbacks.svg)

  1. At boot, the engine starts the durable consumer of each inbox with
     `c:consumer/2`. It starts each inbox before any relay.
  2. The durable consumer subscribes to the transport under its name.
  3. In a transaction, the relay publishes a batch of messages through `c:publish/2`.
  4. The adapter hands the batch to the transport.
  5. The adapter confirms with `:ok` when the transport holds each message. The relay
     then moves its position, in the same transaction.
  6. Later, the transport delivers each message to the durable consumer.
  7. The durable consumer calls the handler of the inbox with the message.
  8. The handler answers `:ack` after its commit, or `:nack`.
  9. After `:ack`, the durable consumer acknowledges the message to the transport.
     After `:nack`, it does not: the message stays with the transport, which delivers
     it again later.

  [How does an event reach another contract?](between-contracts.md)
  tells the same path from the side of the contracts.

  ## What an adapter promises

  `EhosContract.Bus.Suite` checks what a test can see of these promises. Any adapter
  can run it. It cannot see that an order is absent, or how a relay handles an error.
  `EhosContract.Relay` tells about the relay.

  - **`:ok` from `c:publish/2` means that the transport holds each message of the
    batch.** An error means that it can hold some of them. Then the relay publishes
    the whole batch again, under the same ids.
  - **At least once.** A message reaches each durable consumer of its name that was
    subscribed when the message was published. It comes again until the handler of
    that consumer returns `:ack`.
    - A handler that returns `:nack`, raises, exits or throws gets the message again
      later.
    - A durable consumer that stops with a message in hand gets it again later.
    - A durable consumer that comes back under the same name gets what was published while
      it was down.
  - **No order.** Messages can arrive in any order, and a message delivered again can
    arrive after a later one. The relay publishes in the order of the log, but nothing
    after it can rely on that order.
  - **No deduplication is necessary.** A message published two times can arrive two
    times. The inbox drops the second one by its key. A transport that deduplicates,
    such as JetStream with `Nats-Msg-Id`, saves work, and changes no result.
  - **The adapter decides where a new durable consumer starts.** One rule holds: it
    gets what is published after it first subscribed.
    `EhosContract.Bus.Local` gives it nothing older.
  - **No limit on deliveries.** A message whose handler never succeeds comes again for
    as long as the transport keeps it. Only a limit of the transport stops it, such as
    `MaxDeliver` of JetStream. The inbox answers `:nack` to what it cannot take, so
    that nothing is lost while a person corrects the cause (`EhosContract.Inbox`).

  ## Who can consume a name?

  The engine does not decide who can consume a name. The `subscribe` of the
  subscriber derives the capability `<name>.subscribe`, where the name has no version.
  It derives it only for an event that a policy handles. The platform that issues the
  credentials grants the capability, and the adapter of the transport routes by the
  grant. An adapter that cannot refuse a consumer without the grant lets each
  consumer in.

  ## What does a message carry?

  `EhosContract.Bus.Message` carries five things:

  - the id;
  - the key that tells one event from another;
  - the name, with its version;
  - the correlation;
  - the payload.

  **The payload is JSON**: string keys, and values that a JSON encoder turns into text
  and back. What arrives is what `Jason` decodes, not the Elixir terms that were sent.
  `EhosContract.Bus.Local` encodes and decodes the payload on the way. So a term that
  a real transport cannot carry fails in a test, not in production.
  """

  alias EhosContract.Bus.Message

  @typedoc "What a handler says of a message: done, or deliver it again later."
  @type verdict :: :ack | :nack

  @typedoc "Called once per delivery, in the adapter's process."
  @type handler :: (Message.t() -> verdict())

  @typedoc """
  A durable consumer:

  - `name`: unique on the transport, and the same after a restart. The engine names
    the consumer of an inbox `"<contract id>:inbox:<name>"`, with the dots of the id.
  - `names`: the names of the messages that it takes.
  - `handler`: the function that gets each delivery.

  If the transport accepts fewer characters in a name, the adapter maps the name.
  Example: a durable name of JetStream has no `.`. Map each name the same way each
  time, and never two names to one. If `shop.stock` and `shop_stock` shared a durable
  consumer, each would get only part of the messages.
  """
  # A consumer's name carries the contract's id, dots and all (plan DD, ID4, #178).
  @type consumer :: %{name: String.t(), names: [String.t(), ...], handler: handler()}

  @doc """
  Hands `messages` to the transport. Returns when the transport holds each message.

  **The relay calls it inside a database transaction.** That transaction holds its
  row and a pooled connection until the call returns. So return within a few seconds,
  well under the timeout of the repo (15 seconds by default).

  - If the transport has not confirmed by then, return `{:error, :timeout}`.
  - Wait for the confirmations of a batch together, not one after the other.
  - `EhosContract.Bus.Local` stops after 5 seconds.

  If a call takes longer than the timeout of the repo, the relay loses its connection
  after the transport took the batch. Then the position never moves, and the relay
  publishes the same batch again and again.

  **Return `{:error, reason}` only for an error that a new try can correct**: a
  transport that is down or slow. Then the relay keeps its position, counts no
  attempt, and tries again after 5 seconds, with no end. An exit counts as such an
  error, but an adapter must return the error, not exit.

  **Raise for an error that a new try does not correct.** Examples:

  - a payload that JSON cannot encode;
  - a message over the size limit of the broker;
  - a subject that the broker refuses.

  Then the relay publishes the batch again, one event at a time. It
  publishes the events before the bad one, and stops at the bad one. After three
  attempts, the relay is `failing` at that event, where a person sees it.
  """
  @callback publish(opts :: keyword(), messages :: [Message.t()]) :: :ok | {:error, term()}

  @doc """
  Returns the child spec of the process that runs `consumer`. When it starts, the
  process subscribes under the name of the consumer. Then it delivers each message to
  the handler, until it stops.

  **The consumer is subscribed when its start returns.** The engine starts each inbox
  before any relay. So in one node, a relay publishes nothing before the inbox that
  takes it listens (`EhosContract.Inbox`).

  **The start returns quickly**, subscribed or failed. The boot of the engine waits
  for each start, one inbox after the other. A start that waits for a transport that
  does not answer holds the boot of the host for as long. If the transport is down,
  return an error at once. The engine starts the child again later.

  **The state and the exit reasons hold no credentials.** When a process stops, OTP
  writes its last state and its reason to the log. The engine cannot control that.
  Keep the secrets of a connection out of the reason, and out of the state with
  `format_status/1`.
  """
  @callback consumer(opts :: keyword(), consumer()) :: Supervisor.child_spec()

  # The configured adapter and its options, from `config :ehos_contract, bus:` — a
  # module or `{module, opts}` — or `nil` when there is none.
  # Called by subscription.ex, supervisor.ex.
  @doc false
  @spec adapter() :: {module(), keyword()} | nil
  def adapter do
    case EhosContract.Config.get(:bus) do
      nil ->
        nil

      {module, opts} when is_atom(module) and is_list(opts) ->
        {module, opts}

      module when is_atom(module) ->
        {module, []}

      # The shape only: the value may hold a broker's credentials.
      other ->
        raise ArgumentError,
              "config :ehos_contract, bus: must be a module or {module, opts} with opts a " <>
                "keyword list, got #{shape(other)}"
    end
  end

  defp shape({module, %{}}) when is_atom(module), do: "{#{inspect(module)}, a map}"
  defp shape(value) when is_tuple(value), do: "a tuple of #{tuple_size(value)}"
  defp shape(value) when is_map(value), do: "a map"
  defp shape(value) when is_binary(value), do: "a string"
  defp shape(value) when is_list(value), do: "a list"
  defp shape(_value), do: "another term"

  @doc "`c:publish/2` on the configured adapter."
  @spec publish([Message.t()]) :: :ok | {:error, term()}
  def publish(messages) do
    {module, opts} = adapter!()
    module.publish(opts, messages)
  end

  @doc "`c:consumer/2` on the configured adapter."
  @spec consumer(consumer()) :: Supervisor.child_spec()
  def consumer(consumer) do
    {module, opts} = adapter!()
    module.consumer(opts, consumer)
  end

  defp adapter! do
    adapter() ||
      raise ArgumentError,
            "no bus is configured: set config :ehos_contract, bus: {Adapter, opts}"
  end
end
