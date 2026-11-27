defmodule EhosContract.Relay do
  # At least once, never zero times: the notes of 1 October 2026 in v2 §16. An event of
  # newer code waits: plan W1. `publish/2` returns within seconds: a decision of
  # 1 October 2026.
  @moduledoc """
  What carries a `publish` out of the application: one ordered subscription over the
  log per publication, which hands what it reads to `EhosContract.Bus`. The log is
  the outbox; there is no outbox table.

  A relay is a consumer fed from the log like a policy delivered `:at_least_once`,
  listed by `mix ehos_contract.subscriptions`, with its row in
  `ehos_contract_subscriptions` under `"<contract id>:relay:<name>"`, and it differs
  in what it does with a batch:

  - **It moves only when the transport holds the batch.** A step reads up to
    100 events of the publication's type, builds a message from each and calls
    `EhosContract.Bus.publish/1`; the position advances in the same transaction, on
    `:ok`. A relay that stops between the two publishes the batch again, under the
    same ids, so a message can arrive twice at a consumer subscribed when it was
    published, never zero times, and never without its event in the log.
  - **An unreachable transport is not a failure of the event.** `{:error, reason}`
    leaves the position where it was, counts no attempt, and the runner tries again
    later: an outage of the broker must not stop a relay for a person to restart. A
    raise is a defect and is a failure like a policy's: three, and the relay is
    `failing` at that position until someone decides. Skipping the event is that
    decision, and it means the event never leaves.
  - **An event written by newer code waits**: one whose fields are of a
    newer version than this node declares is not published. The events before it in
    the batch go, one at a time, and the relay stops at it, counting no attempt, until
    the node runs the newer code.
  - **With no bus configured, it waits.** The row is written at the first boot and
    its position holds, so once a bus is configured the relay publishes everything
    since, rather than starting over at the head.
  - **It starts at the head of the log**, as a policy does: what is in the log when a
    `publish` is first deployed is history, and nothing publishes it by itself.
    `mix ehos_contract.subscriptions --reset` moves it back to position 0, and it
    publishes the whole log again under the same ids — a person's decision.
  - **A batch that raises goes again one event at a time**, so the failure lands on
    the event at fault and what comes before it leaves.

  What a host should know besides:

  - **It holds a pooled connection while it publishes**, one per relay per node, for
    as long as `c:EhosContract.Bus.publish/2` takes, which is why that callback has to
    return within seconds.
  - **Its row is keyed by the `publish`'s name, not its `version:`.** A raised version
    keeps the relay where it stands, and the events after it go out under the new name.
    Renaming the declaration makes a new relay at the head of the log, and what the old one had
    not yet published — behind an outage, or with no bus configured — never leaves;
    the old row stays. Removing a `publish` and adding it back later finds the old row,
    and the relay resumes from where it stood, publishing everything since.
  - **It publishes the fields as stored.** Rule D11 refuses a `personal:` field in a
    `publish`, and that holds for today's declaration: a field that was `personal:` in
    an earlier version of the contract is still sealed in the events written then, and
    goes out sealed. So does a field an `upcast` renamed a personal field onto: an older
    row is published in the event's current shape, its seals as they are. The key never leaves, so it is not readable, but it is not the
    value either. The schema lock keeps both out: `mix ehos_contract.schema --check`
    refuses a field that stops being personal, and one a personal field is renamed onto,
    even with a step. An application without the lock, or one that ran `--forget` on a
    version its log holds rows of, can still publish a seal.
  - **Identities go out in the clear**, as they are stored: a unit's identity or an
    `{:id, subject}` field in `fields` names its subject, also after the subject is
    erased, when a reset publishes the log again.
  - **Only a contract of a configured application has a relay**
    (`config :ehos_contract, applications:`, as for every ordered consumer): a
    `publish` elsewhere is compiled and never published.
  """

  alias EhosContract.{Bus, Event}

  # How many events one step of a relay reads and publishes at most.
  # Called by subscription.ex.
  @doc false
  @spec batch() :: pos_integer()
  def batch, do: 100

  # The message a relay publishes for `event`: its id is `<event id>/<name>`, where
  # `name` is the versioned name the publication declares, its correlation the
  # event's, and its payload the declared `fields` of the event, as stored, and nothing
  # else. A field the event does not carry is `nil`.
  #
  # Its key is what the subscriber's inbox tells one event by (`EhosContract.Bus.Message`):
  # the SHA-256 of the name and the `idempotent_on:` values, so a second event with the
  # same values — an event recorded twice, or a log moved under new ids — has the key of
  # the first. Without such fields, or with one of them `nil`, the key is the id.
  #
  # It takes the payload as stored, so the relay holds each event to the version its
  # fields were written with before it builds the message (plan W1).
  # Called by subscription.ex.
  @doc false
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

  # Two events whose keys collide are one event to the inbox, and the second is dropped:
  # so the full digest, not twelve characters, of an encoding that prefixes each
  # string with its length, so a delimiter inside a value cannot make two lists of
  # values encode alike.
  defp key(%{idempotent_on: []}, _payload), do: nil

  defp key(publication, payload) do
    values =
      Enum.map(
        publication.idempotent_on,
        &{Atom.to_string(&1), Map.get(payload, Atom.to_string(&1))}
      )

    if Enum.all?(values, fn {_field, value} -> value != nil end),
      do: EhosContract.Digest.document_digest([publication.as, values])
  end
end
