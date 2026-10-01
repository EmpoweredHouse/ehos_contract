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
  - **A batch that raises goes again one event at a time**, so the failure lands on
    the event at fault and what comes before it leaves.

  What a host should know besides:

  - **It holds a pooled connection while it publishes**, one per relay per node, for
    as long as `c:EhOsContract.Bus.publish/2` takes, which is why that callback has to
    return within seconds (a decision of 1 October 2026, `PLAN.md`).
  - **Its row is keyed by the `publish`'s name, not its `as:`.** Renaming the
    declaration makes a new relay at the head of the log, and what the old one had
    not yet published — behind an outage, or with no bus configured — never leaves;
    the old row stays. Removing a `publish` and adding it back later finds the old row,
    and the relay resumes from where it stood, publishing everything since.
  - **It publishes the fields as stored.** Rule D11 refuses a `personal:` field in a
    `publish`, and that holds for today's declaration: a field that was `personal:` in
    an earlier version of the contract is still sealed in the events written then, and
    goes out sealed. The key never leaves, so it is not readable, but it is not the
    value either.
  - **Identities go out in the clear**, as they are stored: a unit's identity or an
    `{:id, subject}` field in `fields` names its subject, also after the subject is
    erased, when a reset publishes the log again.
  - **Only a contract of a configured application has a relay**
    (`config :eh_os_contract, applications:`, as for every ordered consumer): a
    `publish` elsewhere is compiled and never published.
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

  Its key is what the subscriber's inbox tells one fact by (`EhOsContract.Bus.Message`):
  the SHA-256 of the name and the `idempotent_on:` values, so a second event with the
  same values — a fact recorded twice, or a log moved under new ids — has the key of
  the first. Without such fields, or with one of them `nil`, the key is the id.
  """
  @spec message(map(), Event.t()) :: Bus.Message.t()
  def message(%{publication: publication}, %Event{} = event) do
    stored = event.payload || %{}

    payload =
      Map.new(publication.fields, &{Atom.to_string(&1), Map.get(stored, Atom.to_string(&1))})

    id = "#{event.id}/#{publication.as}"

    %Bus.Message{
      id: id,
      key: key(publication, payload) || id,
      name: publication.as,
      correlation_id: event.correlation_id,
      payload: payload
    }
  end

  # The full digest, not `EhOsContract.Digest.hash/1`'s twelve characters: two facts
  # whose keys collide are one fact to the inbox, and the second is dropped.
  defp key(%{idempotent_on: []}, _payload), do: nil

  defp key(publication, payload) do
    values =
      Enum.map(
        publication.idempotent_on,
        &{Atom.to_string(&1), Map.get(payload, Atom.to_string(&1))}
      )

    if Enum.all?(values, fn {_field, value} -> value != nil end) do
      :sha256
      |> :crypto.hash(EhOsContract.Digest.canonical([publication.as, values]))
      |> Base.encode16(case: :lower)
    end
  end
end
