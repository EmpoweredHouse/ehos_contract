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

  `EhOsContract.Bus.Suite` checks all of this. Any adapter can run it.

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
    inbox drops the second one by its id, so a transport that deduplicates (JetStream's
    `Nats-Msg-Id`) saves work and changes no result.
  - **Where a new consumer starts** is the adapter's, beyond one thing: it gets what is
    published after it first subscribed. `EhOsContract.Bus.Local` gives it nothing
    older.

  Who may consume a name is not the engine's question either. The subscriber's
  `consumes` derives the capability `<name>.subscribe`, EHOS grants it per environment,
  and the transport adapter routes by the grant (`eh-os` D-41). An adapter that cannot
  refuse an ungranted consumer grants every one.

  ## A message

  `EhOsContract.Bus.Message` carries four things: the id, the versioned name, the
  correlation and the payload. **The payload is JSON**: string keys, and values a JSON
  encoder turns into text and back — what arrives is what `Jason` decodes, not the
  Elixir terms that were sent. `EhOsContract.Bus.Local` encodes and decodes it on the
  way, so a term a real transport could not carry fails in a test and not in production.
  """

  alias EhOsContract.Bus.Message

  @typedoc "What a handler says of a message: done, or deliver it again later."
  @type verdict :: :ack | :nack

  @typedoc "Called once per delivery, in the adapter's process."
  @type handler :: (Message.t() -> verdict())

  @typedoc """
  A durable consumer: its `name`, unique on the transport and kept across restarts; the
  message names it takes; and the handler each delivery goes to.
  """
  @type consumer :: %{name: String.t(), names: [String.t(), ...], handler: handler()}

  @doc "Hands `messages` to the transport, returning once it holds every one."
  @callback publish(opts :: keyword(), messages :: [Message.t()]) :: :ok | {:error, term()}

  @doc """
  The child that runs `consumer`: started, it subscribes under the consumer's name, and
  delivers to its handler until it is stopped.
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

      other ->
        raise ArgumentError,
              "config :eh_os_contract, bus: #{inspect(other)} is not a module or {module, opts}"
    end
  end

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
