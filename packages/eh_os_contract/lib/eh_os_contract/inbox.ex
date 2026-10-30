defmodule EhOsContract.Inbox do
  # The same event published again under a new id is a failure EHOS's design names, and the
  # inbox takes it once; rows are kept for good by #64; the grant to publish and the
  # `<name>.subscribe` capability are EHOS's.
  @moduledoc """
  Where another application's published event arrives: one durable consumer on
  `EhOsContract.Bus` per `subscribe "<name>"` that a policy handles. The event never
  enters this application's log; what its policies decide does.

  **One transaction, then the acknowledgement.** A message is decoded into the
  contract's received struct, `C.Received.X`, and in one transaction the inbox
  writes its row in `eh_os_contract_inbox` and runs each policy that handles it,
  whose commands are dispatched as a policy's always are. Only once that commits does
  it answer `:ack`, and wake the consumers fed from the log if those commands
  appended what one reads. A consumer that stops in
  between gets the message again, and finds either nothing written or the row.

  **One event, one reaction.** The row is keyed by the inbox and the message's key
  (`EhOsContract.Bus.Message`), so a second delivery of a message, and the same event
  published again under a new id, find the row: the inbox acknowledges and writes
  nothing.

  **What it keeps, and for how long: every row, for good.** The row is what drops a
  second delivery and the same event published again under a new id, so a row removed
  is an event that can be taken twice: a window would hold a republished event off only
  for as long as it lasts. Until the transport says how long it can deliver a message again
  (JetStream's stream retention, EHOS's), nothing is pruned. A row is about 250 bytes
  with its key's index for a short key, one per event per inbox; what the table holds is the host's to
  watch with its database's own measures:

      SELECT consumer, count(*), min(received_at)
      FROM eh_os_contract_inbox GROUP BY consumer;

      SELECT pg_size_pretty(pg_total_relation_size('eh_os_contract_inbox'));

  **Who may publish is the transport's to enforce.** The inbox takes what its
  consumer is delivered, key and correlation as they come: that only the publisher
  publishes under its name is the grant's, on the transport.

  **What the policy is told.** The received struct's `__meta__` holds the
  correlation the message carried, so the subscriber's events join the publisher's
  run, and as `id` the row's, which is what the policy's commands name as their
  cause: the row holds the message's id. It holds no position, since the event is in
  no log here, no actor and no time of its own: the publisher's are not sent.

  **What is delivered again.** A message whose payload does not fit the fields the
  subscription declares, and one whose policy raises, rolls back and is answered `:nack`,
  logged with the message's name and id and the kind of failure, never a value:
  nothing is lost while the subscriber's declaration or code is put right, and the
  transport's own limit on deliveries (JetStream's `MaxDeliver`) is what stops one
  that never succeeds. A rejection is the unit's answer, as for any policy, and is
  taken.

  **When it subscribes.** The engine's tree starts every inbox before any relay
  (`EhOsContract`, the child a host adds), each through a keeper process that starts
  the adapter's consumer while it starts itself, and a consumer is subscribed once
  its child has started, so in one node — two applications side by side on
  `EhOsContract.Bus.Local` — nothing a relay publishes is published before its
  subscriber is listening. A transport that refuses, at boot or later, stops neither
  the boot nor the runners: the keeper logs it and starts the consumer again later. A
  broker of `EhOsContract.Bus.Local` that restarts knows no consumer until the keeper
  has started its own again, at once, and what a relay publishes in between is lost,
  as everything that broker held is. Between nodes the durable consumer is the transport's,
  created when EHOS grants the capability `<name>.subscribe`, and
  what was published before that is the publisher's history, which a subscriber
  asks its owner for, not the bus.
  """

  alias EhOsContract.{Bus, Codec, Consumer, Implementations, InboxRecord, Meta, Model}
  alias EhOsContract.Subscription.Runner

  require Logger

  # The durable consumer of `inbox`, for `EhOsContract.Bus.consumer/1`. Called by
  # the inbox's keeper when it starts the adapter's consumer.
  @doc false
  @spec consumer(Implementations.inbox()) :: Bus.consumer()
  def consumer(inbox), do: %{name: inbox.key, names: [inbox.from], handler: &take(inbox, &1)}

  # Takes one delivery of `message` into `inbox`: `:ack` once its row and what its
  # policies dispatched are committed, or when the row was there already; `:nack` when
  # the message does not fit what the contract subscribes to, or a policy fails.
  # Called as the handler `consumer/1` gives the bus, and by the inbox's tests.
  @doc false
  @spec take(Implementations.inbox(), Bus.Message.t()) :: Bus.verdict()
  def take(inbox, %Bus.Message{} = message) do
    model = Model.fetch(inbox.contract)

    case Codec.decode(inbox.fields, message.payload, Codec.values(model.domain)) do
      {:ok, fields} ->
        commit(inbox, model, message, fields)

      {:error, problems} ->
        again(inbox, message, "does not fit the fields it consumes: #{inspect(problems)}")
    end
  end

  defp commit(inbox, model, message, fields) do
    repo = EhOsContract.Config.fetch!(:repo)

    {:ok, _} =
      Runner.transaction(repo, fn ->
        # By the engine's clock, as the events its policies append, so a report's bounds
        # read the two alike (`EhOsContract.Paths`).
        row = %{
          consumer: inbox.key,
          key: message.key,
          id: Ecto.UUID.generate(),
          message_id: message.id,
          received_at: EhOsContract.Clock.now()
        }

        case repo.insert_all(InboxRecord, [row], on_conflict: :nothing) do
          {1, _} -> react(inbox, model, message, fields, row.id)
          {0, _} -> :taken_before
        end
      end)

    :ack
  rescue
    exception -> again(inbox, message, "failed (#{inspect(exception.__struct__)})")
  catch
    # The kind only: a thrown value or an exit's reason may carry what was read.
    kind, _reason -> again(inbox, message, "failed (#{inspect(kind)})")
  end

  defp react(inbox, model, message, fields, id) do
    received =
      struct!(
        Model.module_for(model, :event, inbox.name),
        Map.put(fields, :__meta__, %Meta{id: id, correlation_id: message.correlation_id})
      )

    Enum.each(inbox.policies, &Consumer.handle!(&1, received, []))
  end

  defp again(inbox, message, what) do
    Logger.warning(
      "inbox #{inbox.key}: #{inspect(message.name)} #{inspect(message.id)} #{what}; it is " <>
        "delivered again later"
    )

    :nack
  end
end
