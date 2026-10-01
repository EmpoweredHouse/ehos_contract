defmodule EhOsContract.Bus do
  @moduledoc """
  How an integration event leaves one application and reaches another (v2 §16, D11 and
  D12): the seam between the engine and a transport.

  The engine is on both sides of it. The relay publishes what a `publish` declares,
  from the log, and advances its checkpoint when `c:publish/2` returns `:ok`; the
  subscriber's inbox takes a message, commits what its policy decides, and only then
  acknowledges. What sits between the two, and only that, is an adapter: this package
  ships `EhOsContract.Bus.Local` for tests and development, and the transport adapters
  (JetStream through `gnat`, EHOS's relay) are EHOS's. The library depends on none of
  them.

      config :eh_os_contract, bus: {EhOsContract.Bus.Local, []}

  ## What an adapter promises

  `EhOsContract.Bus.Suite` checks what a test can see of this, and any adapter can run
  it. It cannot see the absence of an order, nor how a relay treats an error, which is
  E12b's.

  - **`:ok` from `c:publish/2` means the transport holds every message of the batch.**
    An error means it may hold some of them: the relay publishes the whole batch again,
    under the same ids.
  - **At least once.** A message reaches every durable consumer of its name that was
    subscribed when it was published, and comes again until that consumer's handler
    returns `:ack`. A handler that returns `:nack`, raises, exits or throws, and a
    consumer that stops with a message in hand, get it again later. A consumer that
    comes back under the same name gets what was published while it was down.
  - **No order.** Messages may arrive in any order, and a redelivered one after a later
    one. The relay publishes in log order, but nothing downstream may rely on it
    (v2 §16, the note of 1 October 2026).
  - **No deduplication is required.** A message published twice may arrive twice. The
    inbox drops the second one by its key, so a transport that deduplicates (JetStream's
    `Nats-Msg-Id`) saves work and changes no result.
  - **Where a new consumer starts** is the adapter's, beyond one thing: it gets what is
    published after it first subscribed. `EhOsContract.Bus.Local` gives it nothing
    older.
  - **No bound on redelivery.** A message whose handler never succeeds comes again for
    as long as the transport keeps it. What stops it is the transport's own limit
    (JetStream's `MaxDeliver`), not this behaviour, nor the inbox, which answers
    `:nack` to what it cannot take, so that nothing is lost while it is put right
    (`EhOsContract.Inbox`).

  Who may consume a name is not the engine's question either. The subscriber's
  `consumes` derives the capability `<name>.subscribe`, EHOS grants it per environment,
  and the transport adapter routes by the grant (`eh-os` D-41). An adapter that cannot
  refuse an ungranted consumer grants every one.

  ## A message

  `EhOsContract.Bus.Message` carries five things: the id, the key that tells one fact
  from another, the versioned name, the correlation and the payload. **The payload is
  JSON**: string keys, and values a JSON encoder turns into text and back — what
  arrives is what `Jason` decodes, not the Elixir terms that were sent.
  `EhOsContract.Bus.Local` encodes and decodes it on the way, so a term a real
  transport could not carry fails in a test and not in production.
  """

  alias EhOsContract.Bus.Message

  @typedoc "What a handler says of a message: done, or deliver it again later."
  @type verdict :: :ack | :nack

  @typedoc "Called once per delivery, in the adapter's process."
  @type handler :: (Message.t() -> verdict())

  @typedoc """
  A durable consumer: its `name`, unique on the transport and kept across restarts; the
  message names it takes; and the handler each delivery goes to. The engine names an
  inbox's consumer `"<contract>:inbox:<name>"`, with the dots of a module's name in it;
  an adapter whose transport takes fewer characters in a consumer's name (JetStream's
  durable names take no `.`) maps it, the same way every time and never two names to
  one: `Shop.Stock` and `Shop_Stock` sharing a durable consumer would each get only
  part of the messages.
  """
  @type consumer :: %{name: String.t(), names: [String.t(), ...], handler: handler()}

  @doc """
  Hands `messages` to the transport, returning once it holds every one.

  **It is called inside a database transaction** — the relay's step, which holds its
  row and a pooled connection until this returns — **so it returns within a few
  seconds**, well under the repo's timeout (15 seconds by default): a broker that has
  not confirmed by then is `{:error, :timeout}`. Wait for the confirmations of a
  batch together, not one after another. `EhOsContract.Bus.Local` gives up after 5.
  A call that outlives the repo's timeout loses the connection after the transport
  took the batch, so the position never moves and the same batch goes out again and
  again.

  `{:error, reason}`, never an exit, **only for what trying again can fix**: a
  transport that is down or slow. The relay then keeps its position, counts no
  attempt, and tries again in five seconds, for as long as it takes. Anything trying
  again will not fix raises — a payload JSON cannot encode, a message over the
  broker's size limit, a subject it refuses — so that the relay stops at that event,
  `failing`, where a person sees it, instead of retrying it forever.
  """
  @callback publish(opts :: keyword(), messages :: [Message.t()]) :: :ok | {:error, term()}

  @doc """
  The child that runs `consumer`: started, it subscribes under the consumer's name, and
  delivers to its handler until it is stopped.

  **It is subscribed once its start has returned.** The engine starts every inbox
  before any relay, and relies on this for nothing a relay publishes to be published,
  in one node, before the inbox that takes it listens (`EhOsContract.Inbox`).

  **Its start returns quickly**, subscribed or failed: the engine's boot waits for it,
  one inbox after another, so a start that waits on a transport that does not answer
  holds the host's boot for as long. A transport that is down is an error at once; the
  engine starts the child again later (`EhOsContract.Inbox.Keeper`).

  **Its state and its exit reasons carry no credentials.** What OTP reports of a
  process that stops — its last state and its reason, in the log — is the adapter's,
  out of the engine's reach: keep a connection's secrets out of the reason, and out of
  the state with `format_status/1`.
  """
  @callback consumer(opts :: keyword(), consumer()) :: Supervisor.child_spec()

  @doc """
  The configured adapter and its options, from `config :eh_os_contract, bus:` — a
  module or `{module, opts}` — or `nil` when there is none.
  """
  @spec adapter() :: {module(), keyword()} | nil
  def adapter do
    case Application.get_env(:eh_os_contract, :bus) do
      nil ->
        nil

      {module, opts} when is_atom(module) and is_list(opts) ->
        {module, opts}

      module when is_atom(module) ->
        {module, []}

      # The shape only: the value may hold a broker's credentials.
      other ->
        raise ArgumentError,
              "config :eh_os_contract, bus: must be a module or {module, opts} with opts a " <>
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
            "no bus is configured: set config :eh_os_contract, bus: {Adapter, opts}"
  end
end
