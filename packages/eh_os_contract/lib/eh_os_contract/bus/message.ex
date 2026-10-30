defmodule EhOsContract.Bus.Message do
  @moduledoc """
  One integration event on the way between two applications.

  - `id` — `<source event id>/<name>`, the same every time the relay publishes it;
  - `key` — what makes two messages one event, so the subscriber's inbox takes only
    the first: the SHA-256, in hex, of the name and the values of the
    fields the `publish` declares `idempotent_on:`. The first event recorded again
    under a new id has the same values, and its message has the same key. The id
    stands in for it when the publication declares no such fields, or one of them is
    `nil`, which identifies nothing;
  - `name` — the versioned name the `publish` declares, `"billing.invoice.issued.v1"`;
  - `correlation_id` — the source event's, which the subscriber's events carry on, so a
    run across two applications can be assembled;
  - `payload` — the declared `fields` of the source event and nothing else, as JSON
    (`EhOsContract.Bus`, "A message").
  """

  # An integration event (v2 §16); its key is what makes two messages one event, so the same
  # event published again under a new id is still taken once.

  @enforce_keys [:id, :key, :name, :correlation_id, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          name: String.t(),
          correlation_id: String.t(),
          payload: %{optional(String.t()) => term()}
        }
end
