defmodule EhOsContract.Relay do
  @moduledoc """
  What carries a `publish` out of the application (v2 §16, D11): one ordered
  subscription over the log per publication, which hands what it reads to
  `EhOsContract.Bus`. The log is the outbox; there is no outbox table.

  A relay is a consumer like a policy (`EhOsContract.Subscription`), with its row in
  `eh_os_contract_subscriptions` under `"<contract>:relay:<name>"`, and it differs
  in what it does with a batch:

  - **It moves only when the transport holds the batch.** A step reads up to
    100 events of the publication's type, builds a message from each and calls
    `EhOsContract.Bus.publish/1`; the position advances in the same transaction, on
    `:ok`. A relay that stops between the two publishes the batch again, under the
    same ids, so a message can arrive twice at a consumer subscribed when it was
    published, never zero times, and never without its fact (the notes of 1 October
    2026 in v2 §16).
  - **An unreachable transport is not a failure of the event.** `{:error, reason}`
    leaves the position where it was, counts no attempt, and the runner tries again
    later: an outage of the broker must not stop a relay for a person to restart. A
    raise is a defect and is a failure like a policy's: three, and the relay is
    `failing` at that position until someone decides. Skipping the event is that
    decision, and it means the event never leaves.
  - **With no bus configured, it waits.** The row is written at the first boot and
    its position holds, so once a bus is configured the relay publishes everything
    since, rather than starting over at the head.
  - **It starts at the head of the log**, as a policy does: what is in the log when a
    `publish` is first deployed is history, and nothing publishes it by itself.
    `EhOsContract.Subscription.rebuild/2` moves it back to position 0, and it
    publishes the whole log again under the same ids — a person's decision.
  """

  alias EhOsContract.{Bus, Event}

  @doc "How many events one step of a relay reads and publishes at most."
  @spec batch() :: pos_integer()
  def batch, do: 100

  @doc """
  The message a relay publishes for `event`: its id is `<event id>/<name>`, where
  `name` is the versioned name the publication declares, its correlation the
  event's, and its payload the declared `fields` of the event, as stored, and nothing
  else. A field the event does not carry is `nil`.
  """
  @spec message(map(), Event.t()) :: Bus.Message.t()
  def message(%{publication: publication}, %Event{} = event) do
    payload = event.payload || %{}

    %Bus.Message{
      id: "#{event.id}/#{publication.as}",
      name: publication.as,
      correlation_id: event.correlation_id,
      payload:
        Map.new(publication.fields, &{Atom.to_string(&1), Map.get(payload, Atom.to_string(&1))})
    }
  end
end
